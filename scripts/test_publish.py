#!/usr/bin/env python3
"""Exercise release checks using disposable repositories, without any pushes."""

from datetime import date
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("publish.sh").resolve()
RELEASE_REF = "refs/ai-toolbox/last-release"


class PublishTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="ai-toolbox-publish-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.work = self.root / "work"
        self.source = self.root / "private-source.git"
        self.public = self.root / "published.git"
        self.env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
        self.env.update({
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": os.devnull,
            "GIT_ALLOW_PROTOCOL": "file",
            "GIT_TERMINAL_PROMPT": "0",
            "GIT_AUTHOR_NAME": "Release Test",
            "GIT_AUTHOR_EMAIL": "release-test@example.invalid",
            "GIT_COMMITTER_NAME": "Release Test",
            "GIT_COMMITTER_EMAIL": "release-test@example.invalid",
        })
        self.work.mkdir()
        self.git(self.root, "init", "--bare", "--quiet", str(self.source))
        self.git(self.root, "init", "--bare", "--quiet", str(self.public))
        self.git(self.work, "init", "--quiet", "-b", "main")
        self.commit({"README.md": "Release fixture\n"}, "Initial source")
        self.git(self.work, "remote", "add", "origin", str(self.source))
        self.git(self.work, "remote", "add", "public", str(self.public))
        self.sync_source()

    def git(self, cwd, *args, input=None):
        result = subprocess.run(
            ["git", *args], cwd=cwd, env=self.env, input=input,
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.strip()

    def commit(self, files, message):
        for name, content in files.items():
            path = self.work / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8")
        self.git(self.work, "add", ".")
        self.git(self.work, "commit", "--quiet", "-m", message)
        return self.git(self.work, "rev-parse", "HEAD")

    def sync_source(self):
        self.git(self.source, "fetch", "--quiet", str(self.work), "+main:refs/heads/main")

    def set_public(self, commit):
        self.git(self.public, "fetch", "--quiet", str(self.work), f"{commit}:refs/heads/main")

    def release_snapshot(self, trusted=True, parent=None):
        source = self.git(self.work, "rev-parse", "main")
        tree = self.git(self.work, "rev-parse", "main^{tree}")
        args = ["commit-tree", tree]
        if parent:
            args.extend(["-p", parent])
        release = self.git(
            self.work, *args, input=f"Fixture release\n\nSource-commit: {source}\n",
        )
        self.set_public(release)
        if trusted:
            self.git(self.work, "update-ref", RELEASE_REF, release)
        return release

    def public_change(self, parent, trailer=False):
        source = self.git(self.work, "rev-parse", "main")
        self.git(self.work, "checkout", "--quiet", "--detach", parent)
        message = "Public contribution"
        if trailer:
            message += f"\n\nSource-commit: {source}"
        public_commit = self.commit({"public-only.txt": "Keep this public change\n"}, message)
        self.set_public(public_commit)
        self.git(self.work, "checkout", "--quiet", "main")
        return public_commit

    def change_source(self):
        self.commit({"source-only.txt": "New source feature\n"}, "New source feature")
        self.sync_source()

    def dry_run(self, *args, success=True):
        before = self.git(self.public, "for-each-ref", "--format=%(refname) %(objectname)")
        receipt_before = self.git(self.work, "for-each-ref", "--format=%(objectname)", RELEASE_REF)
        result = subprocess.run(
            ["bash", str(SCRIPT), "--dry-run", *args], cwd=self.work, env=self.env,
            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20,
        )
        if success:
            self.assertEqual(result.returncode, 0, result.stdout)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertNotIn("dry run passed", result.stdout)
        after = self.git(self.public, "for-each-ref", "--format=%(refname) %(objectname)")
        self.assertEqual(before, after, "A dry run changed the public refs")
        receipt_after = self.git(self.work, "for-each-ref", "--format=%(objectname)", RELEASE_REF)
        self.assertEqual(receipt_before, receipt_after, "A dry run changed the release receipt")
        return result.stdout

    def test_first_release(self):
        output = self.dry_run()
        self.assertIn("first release", output)
        self.assertIn(f"Tag:     {date.today():v%Y.%m.%d}\n", output)
        self.assertNotIn("GitHub Release", output)
        self.assertIn("dry run passed", output)
        self.assertEqual(self.git(self.work, "for-each-ref", RELEASE_REF), "")

    def test_same_day_release_gets_next_tag_suffix(self):
        release = self.release_snapshot()
        today = f"{date.today():v%Y.%m.%d}"
        self.git(self.public, "tag", today, release)
        self.git(self.work, "tag", f"{today}.2", release)
        self.change_source()
        self.assertIn(f"Tag:     {today}.3\n", self.dry_run())

    def test_dirty_worktree_blocks_first_release(self):
        (self.work / "untracked.txt").write_text("Uncommitted\n")
        self.assertIn("uncommitted or untracked", self.dry_run(success=False))

    def test_unsynchronized_source_blocks_first_release(self):
        self.commit({"new.txt": "Unpushed\n"}, "Unpushed source")
        self.assertIn("main differs from origin/main", self.dry_run(success=False))

    def test_private_repository_name_blocks_release(self):
        self.commit({"notes.txt": "private-source\n"}, "Accidental private reference")
        self.sync_source()
        self.assertIn("private repository name", self.dry_run(success=False))

    def test_credential_file_blocks_release(self):
        self.commit({".env": "FIXTURE=value\n"}, "Accidental environment file")
        self.sync_source()
        self.assertIn("credential-like files", self.dry_run(success=False))

    def test_environment_example_is_allowed(self):
        self.commit({".env.example": "FIXTURE=\n"}, "Example environment")
        self.sync_source()
        self.dry_run()

    def test_trusted_release_allows_next_release(self):
        self.release_snapshot()
        self.change_source()
        self.assertIn("Source commits since the last release", self.dry_run())

    def test_public_contribution_requires_port_confirmation(self):
        release = self.release_snapshot()
        self.public_change(release)
        self.change_source()
        self.assertIn("Port them into main", self.dry_run(success=False))

    def test_forged_trailer_cannot_hide_public_contribution(self):
        release = self.release_snapshot()
        self.public_change(release, trailer=True)
        self.change_source()
        self.assertIn("Public contribution", self.dry_run(success=False))

    def test_exact_source_snapshot_is_not_trusted_without_receipt(self):
        release = self.release_snapshot()
        public_commit = self.public_change(release)
        self.release_snapshot(trusted=False, parent=public_commit)
        self.change_source()
        self.assertIn("Public contribution", self.dry_run(success=False))

    def test_fresh_clone_requires_port_confirmation(self):
        self.release_snapshot(trusted=False)
        self.change_source()
        self.assertIn("commits that this script did not publish", self.dry_run(success=False))

    def test_unrelated_receipt_does_not_hide_public_commits(self):
        self.release_snapshot(trusted=False)
        self.git(self.work, "update-ref", RELEASE_REF, self.git(self.work, "rev-parse", "main"))
        self.change_source()
        self.dry_run(success=False)

    def test_port_confirmation_allows_reviewed_public_changes(self):
        release = self.release_snapshot()
        self.public_change(release)
        self.change_source()
        self.assertIn("confirmed as ported", self.dry_run("--ported"))

    def test_matching_trees_are_a_successful_noop(self):
        self.release_snapshot()
        self.assertIn("nothing to publish", self.dry_run())

    def test_matching_trees_do_not_hide_dirty_worktree(self):
        self.release_snapshot()
        (self.work / "untracked.txt").write_text("Uncommitted\n")
        output = self.dry_run(success=False)
        self.assertIn("uncommitted or untracked", output)
        self.assertNotIn("nothing to publish", output)

    def test_matching_trees_do_not_hide_unsynchronized_source(self):
        self.commit({"new.txt": "Unpushed\n"}, "Unpushed source")
        self.release_snapshot()
        self.assertIn("main differs from origin/main", self.dry_run(success=False))

    def test_matching_trees_do_not_skip_tracked_file_checks(self):
        self.commit({".env": "FIXTURE=value\n", "notes.txt": "private-source\n"}, "Unsafe fixture")
        self.sync_source()
        self.release_snapshot()
        output = self.dry_run(success=False)
        self.assertIn("private repository name", output)
        self.assertIn("credential-like files", output)
        self.assertIn("dry run found 2 problem(s)", output)


if __name__ == "__main__":
    unittest.main(verbosity=2)
