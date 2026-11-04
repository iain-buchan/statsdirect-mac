"""Focused consumer-contract checks; fixtures never replace committed Content."""
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
spec = importlib.util.spec_from_file_location("help_import", ROOT / "Scripts/import-desktop-help.py")
help_import = importlib.util.module_from_spec(spec)
spec.loader.exec_module(help_import)
SOURCE = "b" * 40
PRODUCER = "c" * 40
REPOSITORY = "https://github.com/iain-buchan/statisticalhelp"


def write(folder, name, data):
    path = folder / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(data, encoding="utf-8")


def editor_fixture(folder):
    contexts = [{"name": "PairedT", "link": "parametric_methods/paired_t.htm", "resolvedId": "1239"}]
    for name in help_import.EDITOR_REQUIRED:
        write(folder, name, "fixture")
    write(folder, "parametric_methods/paired_t.htm", "<!doctype html><h1>Paired t test</h1>")
    write(folder, "Data/Alias.xml", '<CatapultAliasFile><Map Name="PairedT" Link="parametric_methods/paired_t.htm" ResolvedId="1239"/></CatapultAliasFile>')
    write(folder, "build-info.json", json.dumps({"Builder": "StatsDirectHelpEditor prototype", "Target": "Desktop", "TopicCount": 1, "SearchDocumentCount": 1, "Warnings": []}))
    write(folder, "search-index.js", 'window.StatsDirectSearch=' + json.dumps({"documents": [{"url": "parametric_methods/paired_t.htm", "title": "Paired t test", "excerpt": "Paired differences"}], "terms": {"paired": [[0, 10]]}}) + ';')
    write(folder, "contents-data.js", 'window.StatsDirectContents=' + json.dumps([{"title": "Methods", "link": None, "children": [{"title": "Paired t", "link": "parametric_methods/paired_t.htm", "children": []}]}]) + ';')
    write(folder, ".statsdirect-help-output.json", json.dumps({"files": sorted(help_import.inventory(folder))}))
    receipt = {"schemaVersion": 1, "format": "statsdirect-desktop-help-v1", "entryPage": "index.html", "sourceSha256": "a" * 64,
               "publicationSnapshotSha256": "d" * 64, "aliasSourceSha256": "e" * 64, "contextHeaderSha256": "f" * 64,
               "topicCount": 1, "searchDocumentCount": 1, "contexts": contexts}
    reseal(folder, receipt)
    return receipt


def reseal(folder, receipt=None):
    if receipt is None:
        receipt = json.loads((folder / help_import.RECEIPT).read_text())
    receipt["files"] = [{"path": name, **data} for name, data in help_import.inventory(folder).items() if name != help_import.RECEIPT]
    write(folder, help_import.RECEIPT, json.dumps(receipt))
    return receipt


def legacy_fixture(folder):
    for name in ["index.html", "Data/Search.js", "resources/stylesheets/desktop.css", "paired.htm"]:
        write(folder, name, "legacy")
    write(folder, "Data/Alias.xml", '<CatapultAliasFile><Map Name="PairedT" Link="paired.htm" ResolvedId="1239"/></CatapultAliasFile>')


def snapshot(folder):
    return {p.relative_to(folder).as_posix(): p.read_bytes() for p in folder.rglob("*") if p.is_file()}


class DesktopHelpImportTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="statsdirect-help-import-check-")
        self.root = Path(self.temporary.name)
        self.addCleanup(self.temporary.cleanup)
        self.source = self.root / "source"
        editor_fixture(self.source)
        self.destination = self.root / "committed/Help"
        self.manifest = self.root / "committed/help-manifest.json"

    def metadata(self):
        return help_import.prepare_manifest(self.source, REPOSITORY, SOURCE, "HelpEditor/HelpSource", "published-directory", PRODUCER)

    def install(self):
        result = self.metadata()
        help_import.install_bundle(self.source, self.destination, self.manifest, result)
        return result

    def test_editor_receipt_roundtrip_preserves_provenance_without_legacy_search(self):
        expected = self.install()
        actual = help_import.verify_import(self.destination, self.manifest)
        self.assertEqual(actual, expected)
        self.assertEqual(actual["producer"]["commit"], PRODUCER)
        self.assertEqual(actual["producer"]["publicationSnapshotSHA256"], "d" * 64)
        self.assertFalse((self.destination / "Data/Search.js").exists())
        self.assertEqual(snapshot(self.source), snapshot(self.destination))

    def test_legacy_hash_manifest_and_pinned_git_import_remain_supported(self):
        repository = self.root / "legacy-repo"
        bundle = repository / "StatsDirectUI/Assets/Help"
        legacy_fixture(bundle)
        subprocess.run(["git", "init", "-q", str(repository)], check=True)
        subprocess.run(["git", "-C", str(repository), "add", "."], check=True)
        subprocess.run(["git", "-C", str(repository), "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-qm", "Published fixture"], check=True)
        revision = subprocess.check_output(["git", "-C", str(repository), "rev-parse", "HEAD"], text=True).strip()
        help_import.main([revision, "--repository", str(repository), "--source-path", "StatsDirectUI/Assets/Help", "--source-repository", "https://github.com/iain-buchan/statsdirect", "--destination", str(self.destination), "--manifest", str(self.manifest)])
        result = help_import.verify_import(self.destination, self.manifest)
        self.assertEqual(result["format"], "legacy-flare")
        self.assertEqual(result["commit"], revision)
        result.pop("schemaVersion")
        self.manifest.write_text(json.dumps(result))
        help_import.verify_import(self.destination, self.manifest)
        with self.assertRaises(help_import.InvalidHelp):
            help_import.main(["main", "--repository", str(repository)])
        write(repository, help_import.PENDING, '{}')
        subprocess.run(["git", "-C", str(repository), "add", "."], check=True)
        subprocess.run(["git", "-C", str(repository), "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-qm", "Interrupted publication"], check=True)
        revision = subprocess.check_output(["git", "-C", str(repository), "rev-parse", "HEAD"], text=True).strip()
        with tempfile.TemporaryDirectory(dir=self.root) as out:
            with self.assertRaisesRegex(help_import.InvalidHelp, "incomplete"):
                help_import.read_git_bundle(repository, revision, "StatsDirectUI/Assets/Help", out)

    def test_partial_or_tampered_delivery_never_changes_existing_import(self):
        self.install()
        previous, manifest = snapshot(self.destination), self.manifest.read_bytes()
        for file in ["search-index.js", "parametric_methods/paired_t.htm", help_import.RECEIPT]:
            with self.subTest(file=file):
                saved = (self.source / file).read_bytes()
                (self.source / file).unlink()
                with self.assertRaises(help_import.InvalidHelp):
                    self.metadata()
                (self.source / file).write_bytes(saved)
        write(self.source, "parametric_methods/paired_t.htm", "changed after publication")
        with self.assertRaisesRegex(help_import.InvalidHelp, "receipt"):
            self.metadata()
        self.assertEqual(previous, snapshot(self.destination))
        self.assertEqual(manifest, self.manifest.read_bytes())

    def test_invalid_receipt_schema_hash_size_duplicate_and_alias_map_rejected(self):
        original = json.loads((self.source / help_import.RECEIPT).read_text())
        mutations = [lambda r: r.update(schemaVersion=2), lambda r: r.update(schemaVersion=True),
                     lambda r: r.update(format="public-help-v1"), lambda r: r.update(sourceSha256="bad"),
                     lambda r: r["files"][0].update(bytes=-1), lambda r: r["files"].append(deepcopy(r["files"][0])),
                     lambda r: r["files"][0].update(path="../outside.htm"), lambda r: r["contexts"][0].update(resolvedId="999"),
                     lambda r: r.update(topicCount=2)]
        for mutate in mutations:
            value = deepcopy(original);mutate(value)
            write(self.source, help_import.RECEIPT, json.dumps(value))
            with self.subTest(receipt=value):
                with self.assertRaises(help_import.InvalidHelp):self.metadata()
        write(self.source, help_import.RECEIPT, json.dumps(original))

    def test_reader_schema_target_missing_topic_and_postings_rejected_even_with_new_hashes(self):
        variants = [
            ("build-info.json", '{"Target":"Public","TopicCount":1,"SearchDocumentCount":1}'),
            ("search-index.js", 'window.StatsDirectSearch={"documents":[],"terms":{}};'),
            ("search-index.js", 'window.StatsDirectSearch={"documents":[{"url":"../outside.htm","title":"Bad","excerpt":""}],"terms":{}};'),
            ("search-index.js", 'window.StatsDirectSearch={"documents":[{"url":"parametric_methods/paired_t.htm","title":"Paired","excerpt":""}],"terms":{"bad":[[99,1]]}};'),
            ("contents-data.js", 'window.StatsDirectContents=[{"title":"Missing","link":"missing.htm","children":[]}];'),
            ("Data/Alias.xml", '<CatapultAliasFile><Map Name="Bad" Link="https://example.org/topic"/></CatapultAliasFile>')]
        original = snapshot(self.source)
        for file, value in variants:
            with self.subTest(file=file, value=value):
                for name, data in original.items():(self.source / name).write_bytes(data)
                write(self.source, file, value);reseal(self.source)
                with self.assertRaises(help_import.InvalidHelp):self.metadata()

    def test_paths_symlinks_and_pending_import_guard_fail_closed(self):
        self.install()
        for name in ["../escape", "/absolute", "A/../B", "A\\B", "C:drive", "A//B"]:
            with self.assertRaises(help_import.InvalidHelp):help_import.relative_path(name)
        (self.source / "linked.htm").symlink_to(self.source / "index.html")
        with self.assertRaisesRegex(help_import.InvalidHelp, "links"):
            self.metadata()
        (self.source / "linked.htm").unlink()
        write(self.source, "INDEX.HTML", "case collision")
        with self.assertRaises(help_import.InvalidHelp):
            self.metadata()
        (self.source / "INDEX.HTML").unlink()
        help_import.pending_marker(self.manifest).write_text('{}')
        with self.assertRaisesRegex(help_import.InvalidHelp, "incomplete"):
            help_import.verify_import(self.destination, self.manifest)

    def test_manifest_publish_failure_restores_previous_bundle_and_manifest(self):
        self.install(); previous = snapshot(self.destination); old_manifest = self.manifest.read_bytes()
        write(self.source, "parametric_methods/paired_t.htm", "<h1>New reviewed wording</h1>");reseal(self.source)
        manifest = self.metadata(); real = help_import.os.replace
        def fail_manifest(src, dst):
            if Path(dst) == self.manifest:raise OSError("simulated manifest I/O failure")
            return real(src, dst)
        with patch.object(help_import.os, "replace", side_effect=fail_manifest):
            with self.assertRaisesRegex(OSError, "simulated"):
                help_import.install_bundle(self.source, self.destination, self.manifest, manifest)
        self.assertEqual(snapshot(self.destination), previous)
        self.assertEqual(self.manifest.read_bytes(), old_manifest)
        self.assertFalse(help_import.pending_marker(self.manifest).exists())

    def test_offline_guard_detects_modified_bytes_or_producer_provenance(self):
        self.install(); metadata=json.loads(self.manifest.read_text())
        metadata["producer"]["sourceSHA256"]="0"*64;self.manifest.write_text(json.dumps(metadata))
        with self.assertRaisesRegex(help_import.InvalidHelp, "provenance"):
            help_import.verify_import(self.destination, self.manifest)
        self.manifest.write_text(json.dumps(self.metadata()))
        write(self.destination, "index.html", "changed")
        with self.assertRaises(help_import.InvalidHelp):help_import.verify_import(self.destination, self.manifest)

    def test_existing_uncommitted_help_is_preserved_and_not_silently_replaced(self):
        self.install()
        write(self.destination, "index.html", "User's unpublished edits")
        before = snapshot(self.destination)
        with self.assertRaises(help_import.InvalidHelp):
            help_import.install_bundle(self.source, self.destination, self.manifest, self.metadata())
        self.assertEqual(snapshot(self.destination), before)

    def test_rollback_failure_retains_original_files_and_blocks_normal_builds(self):
        self.install(); previous = snapshot(self.destination)
        write(self.source, "parametric_methods/paired_t.htm", "New reviewed topic");reseal(self.source)
        real = help_import.os.replace
        def activation_and_recovery_fail(src, dst):
            if Path(dst) in (self.manifest, self.destination) and Path(src).name != "incoming":
                raise OSError("simulated destination failure")
            return real(src, dst)
        with patch.object(help_import.os, "replace", side_effect=activation_and_recovery_fail):
            with self.assertRaisesRegex(help_import.InvalidHelp, "retained for recovery"):
                help_import.install_bundle(self.source, self.destination, self.manifest, self.metadata())
        journal=json.loads(help_import.pending_marker(self.manifest).read_text())
        self.assertEqual(snapshot(Path(journal["previous"])), previous)
        with self.assertRaisesRegex(help_import.InvalidHelp, "incomplete"):
            help_import.verify_import(self.destination, self.manifest)

    def test_reader_only_contract_rejects_private_and_executable_files(self):
        original = snapshot(self.source)
        for name in ["credentials.json", "Project/source.xml", ".env", "unrelated.exe"]:
            with self.subTest(name=name):
                write(self.source, name, "Private author state");reseal(self.source)
                with self.assertRaisesRegex(help_import.InvalidHelp, "private/source"):
                    self.metadata()
                (self.source / name).unlink()
                for path,data in original.items():(self.source / path).write_bytes(data)

    def test_shared_directory_checks_cannot_activate_an_unverified_whole_publication(self):
        with self.assertRaisesRegex(help_import.InvalidHelp, "selected artifact"):
            help_import.main([SOURCE, "--source", str(self.source), "--source-repository", REPOSITORY,
                              "--source-path", "Published/DesktopHelp", "--producer-revision", PRODUCER,
                              "--destination", str(self.destination), "--manifest", str(self.manifest)])
        self.assertFalse(self.destination.exists())


if __name__ == "__main__":
    unittest.main()
