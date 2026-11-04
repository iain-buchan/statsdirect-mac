"""Focused orchestration tests: local Git only, no app build or network access."""
from copy import deepcopy
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("prepare_content_test", ROOT / "Scripts/prepare-content-build.py")
PREPARE = importlib.util.module_from_spec(spec)
spec.loader.exec_module(PREPARE)
GUARD = PREPARE.guard


def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data if isinstance(data, bytes) else data.encode())


def fixture(root, revision="a" * 40, publication_hash="1" * 64, payload="old"):
    """Tiny coordinator inputs; each child importer's format has its own tests."""
    lesson = json.dumps([{"id": "stable-lesson", "title": payload}]).encode()
    help_bytes = ("<h1>" + payload + "</h1>").encode()
    common = {"repository": GUARD.PUBLISHED, "commit": revision,
              "publicationManifestPath": PREPARE.PUBLICATION,
              "publicationManifestSHA256": publication_hash}
    h = {**common, "source": "Published/DesktopHelp",
         "sha256": {"Content/Help/index.html": hashlib.sha256(help_bytes).hexdigest()}}
    t = {**common, "source": "Published/Tutor",
         "sha256": {"Learn/lessons.json": hashlib.sha256(lesson).hexdigest(),
                    "Content/Learn/lessons.json": hashlib.sha256(lesson).hexdigest()}}
    write(root / "Content/Help/index.html", help_bytes)
    write(root / "Content/help-manifest.json", json.dumps(h))
    write(root / "Learn/AuthoredTutor/manifest.json", '{"fixture":true}')
    write(root / "Learn/lessons.json", lesson)
    write(root / "Content/Learn/lessons.json", lesson)
    write(root / "Content/learning-source-manifest.json", '{"fixture":true}')
    write(root / "Content/learning-manifest.json", json.dumps(t))


def fixture_verify(root, allow_pending=False):
    """Substitute only child-format checks; exercise real pairing/activation."""
    root = Path(root)
    GUARD.require(allow_pending or not (root / GUARD.PENDING).exists(), "Interrupted content import")
    h = GUARD.read_json(root / "Content/help-manifest.json")
    t = GUARD.read_json(root / "Content/learning-manifest.json")
    for manifest in (h, t):
        for name, expected in manifest["sha256"].items():
            GUARD.require(hashlib.sha256((root / name).read_bytes()).hexdigest() == expected,
                          "Existing imported content was changed")
    return {**GUARD.shared_pin(h, t), "helpRevision": h["commit"], "tutorRevision": t["commit"]}


class ContentBuildTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="statsdirect-content-build-check-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.consumer = self.root / "consumer"; self.consumer.mkdir()
        fixture(self.consumer)
        write(self.consumer / "learner-progress.json", '{"keep":"all learner work"}')
        self.repository = self.root / "source"
        subprocess.run(["git", "init", "--quiet", str(self.repository)], check=True)
        self.git("config", "user.name", "Content fixture")
        self.git("config", "user.email", "fixture@example.invalid")
        write(self.repository / PREPARE.PUBLICATION, '{"schemaVersion":1,"release":"first"}\n')
        self.commit("Publish content")
        self.published = self.git("rev-parse", "HEAD")
        self.raw = (self.repository / PREPARE.PUBLICATION).read_bytes()
        self.publication_hash = hashlib.sha256(self.raw).hexdigest()
        write(self.repository / "HelpSource/unsaved-draft.txt", "not published content")
        self.commit("Unrelated authoring work")
        self.tip = self.git("rev-parse", "HEAD")
        self.cache = self.root / "cache.git"
        PREPARE.cache(self.cache, create=True)
        self.addCleanup(patch.stopall)
        patch.object(PREPARE, "verify_inputs", side_effect=fixture_verify).start()
        self.stage = patch.object(PREPARE, "stage_inputs", side_effect=self.stage_fixture).start()
        self.proof = patch.object(PREPARE, "publication_proof", side_effect=self.proof_fixture).start()

    def git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.repository), *args], stderr=subprocess.PIPE).decode().strip()

    def commit(self, message):
        self.git("add", ".")
        self.git("commit", "--quiet", "-m", message)

    def fetch_local(self, repository):
        # The cache's identity stays official; only this test fetch is redirected
        # to a disposable local producer repository, never an external server.
        subprocess.run(["git", "-C", str(repository), "fetch", "--quiet", "--no-tags",
                        str(self.repository), "+HEAD:refs/content-build/latest"], check=True)

    def proof_fixture(self, repository, revision, raw):
        return {"schemaVersion": 1, "commit": revision, "publicationManifestSHA256": hashlib.sha256(raw).hexdigest(),
                "complete": True, "artifacts": {key: {"files": 1, "bytes": 10}
                                               for key in ("website", "desktopHelp", "tutor")}}

    def stage_fixture(self, repository, revision, stage, publication_hash):
        fixture(stage, revision, publication_hash, payload="published")

    def run_prepare(self, mode="latest", revision=None):
        return PREPARE.prepare(self.consumer, mode, revision, self.cache)

    def test_latest_resolves_publication_once_not_later_authoring_commit(self):
        with patch.object(PREPARE, "fetch_origin", side_effect=self.fetch_local) as fetch:
            result = self.run_prepare()
        self.assertNotEqual(self.tip, self.published)
        self.assertEqual(result["revision"], self.published)
        self.assertEqual(result["publicationManifestSHA256"], self.publication_hash)
        self.assertTrue(result["changed"])
        fetch.assert_called_once_with(self.cache)
        self.stage.assert_called_once()
        self.proof.assert_called_once()
        self.assertEqual(set(result["publicationArtifacts"]), {"website", "desktopHelp", "tutor"})
        self.assertEqual((self.consumer / "learner-progress.json").read_text(), '{"keep":"all learner work"}')
        self.assertFalse((self.consumer / GUARD.PENDING).exists())

    def test_pinned_reads_existing_git_objects_without_fetch(self):
        self.fetch_local(self.cache)
        with patch.object(PREPARE, "fetch_origin", side_effect=AssertionError("Network must not be used")) as fetch:
            result = self.run_prepare("pinned", self.published)
        self.assertEqual(result["revision"], self.published)
        self.assertEqual(result["mode"], "pinned")
        fetch.assert_not_called()

    def test_repeated_pinned_preparation_keeps_unchanged_content(self):
        self.fetch_local(self.cache)
        self.run_prepare("pinned", self.published)
        before = PREPARE.managed_snapshot(self.consumer)
        result = self.run_prepare("pinned", self.published)
        self.assertFalse(result["changed"])
        self.assertEqual(PREPARE.managed_snapshot(self.consumer), before)

    def test_offline_only_validates_committed_pair_and_writes_record(self):
        before = PREPARE.managed_snapshot(self.consumer)
        with patch.object(PREPARE, "cache", side_effect=AssertionError("No Git cache access in offline mode")):
            result = self.run_prepare("offline")
        self.assertEqual(result["revision"], "a" * 40)
        self.assertFalse(result["changed"])
        self.assertEqual(PREPARE.managed_snapshot(self.consumer), before)
        self.stage.assert_not_called(); self.proof.assert_not_called()
        saved = json.loads((self.consumer / ".build/content-build-input.json").read_text())
        self.assertEqual(saved["mode"], "offline")

    def test_fetch_failure_stops_without_silent_stale_fallback(self):
        before = PREPARE.managed_snapshot(self.consumer)
        with patch.object(PREPARE, "fetch_origin", side_effect=OSError("server unavailable")):
            with self.assertRaisesRegex(OSError, "server unavailable"):
                self.run_prepare()
        self.assertEqual(PREPARE.managed_snapshot(self.consumer), before)
        self.stage.assert_not_called()
        self.assertFalse((self.consumer / ".build/content-build-input.json").exists())

    def test_deleted_or_incomplete_publication_does_not_fall_back(self):
        before = PREPARE.managed_snapshot(self.consumer)
        self.git("rm", PREPARE.PUBLICATION); self.commit("Remove publication")
        with patch.object(PREPARE, "fetch_origin", side_effect=self.fetch_local):
            with self.assertRaises(subprocess.CalledProcessError):
                self.run_prepare()
        self.assertEqual(PREPARE.managed_snapshot(self.consumer), before)
        self.stage.assert_not_called()

    def test_all_three_artifact_proof_is_required_before_importing(self):
        self.fetch_local(self.cache)
        bad = self.proof_fixture(self.cache, self.published, self.raw)
        del bad["artifacts"]["website"]
        self.proof.side_effect = None; self.proof.return_value = bad
        with self.assertRaisesRegex(ValueError, "complete website"):
            self.run_prepare("pinned", self.published)
        self.stage.assert_not_called()

    def test_partial_staging_never_replaces_current_imports(self):
        self.fetch_local(self.cache); before = PREPARE.managed_snapshot(self.consumer)
        def partial(repository, revision, stage, publication_hash):
            write(stage / "Content/Help/index.html", "partial")
            raise ValueError("missing published tutor")
        self.stage.side_effect = partial
        with self.assertRaisesRegex(ValueError, "missing published tutor"):
            self.run_prepare("pinned", self.published)
        self.assertEqual(PREPARE.managed_snapshot(self.consumer), before)
        self.assertFalse((self.consumer / GUARD.PENDING).exists())

    def test_activation_io_failure_restores_both_previous_imports(self):
        self.fetch_local(self.cache); before = PREPARE.managed_snapshot(self.consumer)
        real = PREPARE.os.replace
        def fail_last(src, dst):
            if Path(dst) == self.consumer / "Content/learning-manifest.json" and "new" in Path(src).parts:
                raise OSError("simulated activation I/O failure")
            return real(src, dst)
        with patch.object(PREPARE.os, "replace", side_effect=fail_last):
            with self.assertRaisesRegex(OSError, "simulated activation"):
                self.run_prepare("pinned", self.published)
        self.assertEqual(PREPARE.managed_snapshot(self.consumer), before)
        self.assertFalse((self.consumer / GUARD.PENDING).exists())

    def test_failed_rollback_retains_journal_and_original_backup(self):
        self.fetch_local(self.cache)
        real = PREPARE.os.replace
        def fail_activation_and_restore(src, dst):
            src, dst = Path(src), Path(dst)
            if dst == self.consumer / "Content/learning-manifest.json" and "new" in src.parts:
                raise OSError("activation failed")
            if dst == self.consumer / "Content/Help" and "previous" in src.parts:
                raise OSError("restore failed")
            return real(src, dst)
        with patch.object(PREPARE.os, "replace", side_effect=fail_activation_and_restore):
            with self.assertRaisesRegex(ValueError, "backups retained"):
                self.run_prepare("pinned", self.published)
        marker = self.consumer / GUARD.PENDING
        self.assertTrue(marker.is_file())
        journal = json.loads(marker.read_text())
        backup = Path(journal["staging"]) / "previous/Content/Help/index.html"
        self.assertEqual(backup.read_text(), "<h1>old</h1>")
        with self.assertRaisesRegex(ValueError, "Interrupted"):
            fixture_verify(self.consumer)

    def test_edited_existing_import_is_preserved_before_any_fetch(self):
        write(self.consumer / "Content/Help/index.html", "another session's edit")
        with patch.object(PREPARE, "fetch_origin") as fetch:
            with self.assertRaisesRegex(ValueError, "was changed"):
                self.run_prepare()
        self.assertEqual((self.consumer / "Content/Help/index.html").read_text(), "another session's edit")
        fetch.assert_not_called()

    def test_content_edited_during_staging_is_preserved(self):
        self.fetch_local(self.cache)
        def concurrent(repository, revision, stage, publication_hash):
            self.stage_fixture(repository, revision, stage, publication_hash)
            write(self.consumer / "Content/Learn/lessons.json", "new unsaved edit")
        self.stage.side_effect = concurrent
        with self.assertRaisesRegex(ValueError, "was changed"):
            self.run_prepare("pinned", self.published)
        self.assertEqual((self.consumer / "Content/Learn/lessons.json").read_text(), "new unsaved edit")
        self.assertFalse((self.consumer / GUARD.PENDING).exists())

    def test_joint_guard_rejects_mixed_revisions_hashes_and_sources(self):
        h = GUARD.read_json(self.consumer / "Content/help-manifest.json")
        t = GUARD.read_json(self.consumer / "Content/learning-manifest.json")
        self.assertEqual(GUARD.shared_pin(h, t)["revision"], "a" * 40)
        for field, bad in (("commit", "b" * 40), ("publicationManifestSHA256", "2" * 64),
                           ("source", "authoring-drafts"), ("repository", GUARD.LEGACY)):
            changed = deepcopy(t); changed[field] = bad
            with self.subTest(field=field), self.assertRaises(ValueError):
                GUARD.shared_pin(h, changed)
        legacy_h = {**h, "repository": GUARD.LEGACY, "source": "StatsDirectUI/Assets/Help"}
        legacy_t = {**t, "repository": GUARD.LEGACY, "source": "Learning/AuthoredTutor", "commit": "b" * 40}
        self.assertIsNone(GUARD.shared_pin(legacy_h, legacy_t)["revision"])

    def test_interrupted_journal_blocks_the_real_joint_guard(self):
        write(self.consumer / GUARD.PENDING, "{}")
        with self.assertRaisesRegex(ValueError, "interrupted"):
            GUARD.verify(self.consumer)

    def test_pinned_requires_exact_revision_and_cache_identity(self):
        self.fetch_local(self.cache)
        with self.assertRaisesRegex(ValueError, "40-character"):
            self.run_prepare("pinned", "HEAD")
        subprocess.run(["git", "-C", str(self.cache), "remote", "set-url", "origin", "https://example.invalid/not-content"], check=True)
        with self.assertRaisesRegex(ValueError, "official"):
            self.run_prepare("pinned", self.published)

    def test_promisor_cache_cannot_introduce_implicit_pinned_network_fetches(self):
        subprocess.run(["git", "-C", str(self.cache), "config", "remote.origin.promisor", "true"], check=True)
        with self.assertRaisesRegex(ValueError, "never lazy-fetch"):
            self.run_prepare("pinned", "a" * 40)


if __name__ == "__main__":
    unittest.main()
