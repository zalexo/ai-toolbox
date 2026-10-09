#!/usr/bin/env bash
# Publishes the source repository's main branch to the public repository as one commit.
# Maintainer tool; the full process is described in docs/releasing.md.
set -euo pipefail

SOURCE_REMOTE=origin
PUBLIC_REMOTE=public
BRANCH=main
TRAILER=Source-commit
# Local receipt, written only after this clone successfully publishes a release.
RELEASE_REF=refs/ai-toolbox/last-release

usage() {
  cat <<'EOF'
Usage: scripts/publish.sh [--dry-run] [--ported] "Release message"

Publishes the file tree of the source main branch to public/main as one commit,
tags it vYYYY.MM.DD, and creates a GitHub Release with the message as notes.

  --dry-run  Run every check and show what would be published. Pushes nothing.
  --ported   Confirm that commits made directly in the public repository
             are already ported into the source main branch.

See docs/releasing.md.
EOF
}

die() { printf 'publish: %s\n' "$1" >&2; exit 1; }
warn() { printf 'publish: warning: %s\n' "$1" >&2; }

dry_run=false
ported=false
message=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry_run=true ;;
    --ported) ported=true ;;
    -h|--help) usage; exit 0 ;;
    -*) usage >&2; die "unknown option: $1" ;;
    *) [ -z "$message" ] || die "pass the release message as one quoted argument"; message=$1 ;;
  esac
  shift
done
if [ -z "$message" ] && ! $dry_run; then usage >&2; exit 2; fi

# In a dry run, report every problem; otherwise stop at the first one.
problems=0
problem() {
  if $dry_run; then
    printf 'publish: problem: %s\n' "$1" >&2
    problems=$((problems + 1))
  else
    die "$1"
  fi
}

plugin_version() { sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1; }

cd "$(git rev-parse --show-toplevel)"

source_url=$(git remote get-url "$SOURCE_REMOTE" 2>/dev/null) \
  || die "remote '$SOURCE_REMOTE' (the private source repository) is not configured"
public_url=$(git remote get-url "$PUBLIC_REMOTE" 2>/dev/null) \
  || die "remote '$PUBLIC_REMOTE' (the public repository) is not configured; see docs/releasing.md"
source_name=$(basename "${source_url%.git}")
public_name=$(basename "${public_url%.git}")
[ "$source_name" != "$public_name" ] \
  || die "'$SOURCE_REMOTE' and '$PUBLIC_REMOTE' have the same repository name; run this in the private source clone"

[ -z "$(git status --porcelain)" ] \
  || problem "uncommitted or untracked files found; commit or remove them so the release matches $BRANCH"

git fetch --quiet "$SOURCE_REMOTE"
git fetch --quiet --prune "$PUBLIC_REMOTE"

source_commit=$(git rev-parse --verify -q "$BRANCH^{commit}") || die "branch '$BRANCH' not found"
source_remote_commit=$(git rev-parse --verify -q "refs/remotes/$SOURCE_REMOTE/$BRANCH") \
  || die "'$SOURCE_REMOTE/$BRANCH' not found; push $BRANCH first"
[ "$source_commit" = "$source_remote_commit" ] \
  || problem "$BRANCH differs from $SOURCE_REMOTE/$BRANCH; push or pull it first"

tree=$(git rev-parse "$source_commit^{tree}")
unchanged=false
if public_head=$(git rev-parse --verify -q "refs/remotes/$PUBLIC_REMOTE/$BRANCH"); then
  first=false
  if [ "$tree" = "$(git rev-parse "$public_head^{tree}")" ]; then
    unchanged=true
  fi
else
  first=true
  public_head=""
fi

last_release=""
if ! $first && ! $unchanged; then
  # A public commit message is not proof that this clone published the commit.
  last_release=$(git rev-parse --verify -q "$RELEASE_REF^{commit}" || true)
  if [ -n "$last_release" ] && ! git merge-base --is-ancestor "$last_release" "$public_head"; then
    last_release=""
  fi
  if [ -n "$last_release" ]; then
    foreign=$(git log --format='  %h %an: %s' "$last_release..$public_head")
  else
    foreign=$(git log --format='  %h %an: %s' "$public_head")
  fi
  if [ -n "$foreign" ]; then
    if $ported; then
      echo "publish: including commits made in the public repository, confirmed as ported:"
      echo "$foreign"
    else
      problem "$(printf '%s\n%s\n%s' \
        "$PUBLIC_REMOTE/$BRANCH has commits that this script did not publish:" "$foreign" \
        "Port them into $BRANCH, push, and rerun with --ported. See docs/releasing.md.")"
    fi
  fi
fi

if leaks=$(git grep -n -I -F -e "$source_name" "$source_commit" -- | sed "s/^$source_commit://"); then
  problem "$(printf '%s\n%s' "the private repository name '$source_name' appears in published files:" "$leaks")"
fi

secrets=$(git ls-tree -r --name-only "$source_commit" \
  | grep -E '(^|/)(\.env(\..*)?|[^/]*\.(pem|key))$' | grep -v -E '(^|/)\.env\.example$' || true)
[ -z "$secrets" ] || problem "$(printf '%s\n%s' "credential-like files are tracked:" "$secrets")"

if $unchanged; then
  [ "$problems" -eq 0 ] || die "dry run found $problems problem(s); nothing was pushed"
  echo "publish: nothing to publish; $PUBLIC_REMOTE/$BRANCH already matches $BRANCH"
  exit 0
fi

# Releases are tagged by local date: vYYYY.MM.DD, then vYYYY.MM.DD.2 for another release that day.
tag_base="v$(date +%Y.%m.%d)"
remote_tags=$(git ls-remote --tags --refs "$PUBLIC_REMOTE") || die "cannot list tags in '$PUBLIC_REMOTE'"
taken=$(printf '%s\n' "$remote_tags" | sed 's|.*refs/tags/||'; git tag -l "$tag_base*")
tag=$tag_base
n=1
while grep -qxF "$tag" <<<"$taken"; do
  n=$((n + 1))
  tag="$tag_base.$n"
done

github_repo=$(printf '%s\n' "${public_url%.git}" \
  | sed -n -E 's#^(https://github\.com/|ssh://git@github\.com/|git@github\.com:)([^/]+/[^/]+)$#\2#p')
if [ -n "$github_repo" ]; then
  if ! command -v gh >/dev/null 2>&1 || ! gh auth status --hostname github.com >/dev/null 2>&1; then
    problem "GitHub CLI 'gh' is not installed or not signed in; it creates the GitHub Release"
  fi
fi

if ! $first; then
  for manifest in $(git ls-tree -r --name-only "$source_commit" | grep '/\.claude-plugin/plugin\.json$'); do
    dir=${manifest%/.claude-plugin/plugin.json}
    git diff --quiet "$public_head" "$source_commit" -- "$dir" && continue
    old=$(git show "$public_head:$manifest" 2>/dev/null | plugin_version || true)
    new=$(git show "$source_commit:$manifest" | plugin_version)
    if [ -n "$old" ] && [ "$old" = "$new" ]; then
      warn "$dir changed but its version is still $new; bump it in $manifest if users should get an update"
    fi
  done
fi

echo "Source:  $BRANCH $(git log -1 --format='%h %s' "$source_commit")"
echo "Target:  $PUBLIC_REMOTE/$BRANCH ($public_url)"
echo "Tag:     $tag"
[ -z "$github_repo" ] || echo "Release: GitHub Release $tag in $github_repo"
if $first; then
  echo "Changes: first release, $(git ls-tree -r --name-only "$source_commit" | wc -l | tr -d ' ') files"
else
  echo "Changes:"
  git --no-pager diff --stat "$public_head" "$source_commit"
  last_source=""
  [ -z "$last_release" ] \
    || last_source=$(git log -1 --format=%B "$last_release" | sed -n "s/^$TRAILER: //p" | tail -n 1)
  if [ -n "$last_source" ] && git cat-file -e "$last_source^{commit}" 2>/dev/null; then
    echo "Source commits since the last release:"
    git --no-pager log --format='  %h %s' "$last_source..$source_commit"
  fi
fi

if $dry_run; then
  [ "$problems" -eq 0 ] || die "dry run found $problems problem(s); nothing was pushed"
  echo "publish: dry run passed; nothing was pushed"
  exit 0
fi

full_message=$(printf '%s\n\n%s: %s' "$message" "$TRAILER" "$source_commit")
if $first; then
  release=$(printf '%s\n' "$full_message" | git commit-tree "$tree" -F -)
else
  release=$(printf '%s\n' "$full_message" | git commit-tree "$tree" -p "$public_head" -F -)
fi
git tag -a "$tag" -m "$message" "$release"
# Atomic: the public branch and the tag are updated together or not at all.
if ! git push --atomic "$PUBLIC_REMOTE" "$release:refs/heads/$BRANCH" "refs/tags/$tag"; then
  git tag -d "$tag" >/dev/null
  die "push failed; nothing was published"
fi
git update-ref "$RELEASE_REF" "$release"
echo "publish: published $(git rev-parse --short "$release") to $PUBLIC_REMOTE/$BRANCH as $tag"
if [ -n "$github_repo" ]; then
  gh release create "$tag" --repo "$github_repo" --verify-tag --title "$tag" --notes "$message" \
    || warn "$tag is published, but its GitHub Release was not created; run: gh release create $tag --repo $github_repo --verify-tag --title $tag --notes \"<release message>\""
fi
