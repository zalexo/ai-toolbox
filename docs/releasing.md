# Releasing

This page is for the maintainer and the AI agents working on their behalf. Contributors do not need it.

## How releases work

AI Toolbox is developed in a private source repository. The public repository [zalexo/ai-toolbox](https://github.com/zalexo/ai-toolbox) receives one commit per release. That commit contains exactly the files of the source `main` branch at release time, so work-in-progress history stays private.

Every release commit ends with a trailer that names the source commit it was built from:

```text
Source-commit: <source commit SHA>
```

Each release is tagged with its local release date, `vYYYY.MM.DD`. A second release on the same day gets `vYYYY.MM.DD.2`, then `.3`, and so on. The script pushes the release commit and the annotated tag together, so either both appear in the public repository or neither does. It then creates a GitHub Release for the tag with the release message as notes. The toolbox version only identifies a snapshot; each mod keeps its own `version` in `.claude-plugin/plugin.json`.

After a successful push, the script records the published commit in the local Git ref `refs/ai-toolbox/last-release`. It uses this receipt to distinguish its releases from other public commits; a `Source-commit` trailer alone is not trusted. The receipt stays in this clone and is not pushed. In a fresh clone, or if the receipt is lost, existing public commits require the same review and `--ported` confirmation described below before publishing another release.

Pull requests are welcome in the public repository. When one is merged there, the maintainer ports it into the source repository before the next release, so the release does not overwrite it.

## One-time setup

In a clone of the private source repository, where `origin` is the source repository:

```sh
git remote add public https://github.com/zalexo/ai-toolbox.git
```

Install the [GitHub CLI](https://cli.github.com/) and sign in with `gh auth login`. The script uses it to create GitHub Releases.

## Before a release

1. Bump `version` in the mod's `.claude-plugin/plugin.json` if the change should reach installed users. Claude Code uses this version to detect updates.
2. Validate and test every changed mod with a compatible Claude Code build, as described in [CONTRIBUTING.md](../CONTRIBUTING.md).
3. Commit everything to `main` and push it to `origin`.

## Publish

Check first, then publish:

```sh
scripts/publish.sh --dry-run
scripts/publish.sh "Clock 0.4.0: show seconds"
```

The dry run pushes nothing. It lists every problem it finds, the tag the release would get, the files that would change, and the source commits since the last release. Use that list to write the release message: one line about what changed for users.

The script publishes the tree of `main`, not your working directory. It does not switch branches or touch your files. It pushes without force, so it cannot overwrite commits in the public repository.

The script stops when:

- there are uncommitted or untracked files;
- `main` differs from `origin/main`;
- the public repository has commits that the script did not publish, such as merged pull requests;
- the private repository name appears in a published file;
- `.env`, `.pem`, or `.key` files are tracked;
- the public remote is on GitHub and `gh` is missing or not signed in.

If the GitHub Release cannot be created after a successful push, the script prints the `gh release create` command to finish it by hand.

It warns when a mod changed but its `version` did not. It exits without publishing when the public repository already matches `main`.

Even when the trees already match, the script checks the working directory, source synchronization, and tracked files. A dry run with any reported problem exits with a nonzero status.

To run the release script's regression tests (Python 3 and Git required):

```sh
python3 scripts/test_publish.py
```

The tests use temporary local repositories and run only dry runs. They do not push or contact GitHub.

## Port changes made in the public repository

The public repository allows only squash merging, so each merged pull request is one commit on `public/main`.

When the script reports commits that it did not publish, bring them into `main` first:

```sh
git fetch public
git log --reverse --oneline refs/ai-toolbox/last-release..public/main
git cherry-pick -x <commit>...
git push origin main
scripts/publish.sh --dry-run --ported
scripts/publish.sh --ported "Release message"
```

List the commits oldest first. `-x` records the public commit in the source commit message, and the contributor stays the author. Without the release receipt, as in a fresh clone, use the list that the script reports and port only the commits that are not in `main` yet.

`--ported` confirms that those commits are now in `main`. The script does not check this itself. Without the port, the release would revert those changes.

## Rules for agents

- Publish only when the maintainer asks for a release. A release is public and cannot be taken back.
- Run `--dry-run` first and show the result to the maintainer.
- Never push to the `public` remote in any other way, and never force-push to it.
- Use `--ported` only after the reported commits are in `main`.
