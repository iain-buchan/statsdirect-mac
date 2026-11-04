"""Pinned Help Editor publication/consumer contract; no network or R execution."""
from copy import deepcopy
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "Scripts"))
SPEC = importlib.util.spec_from_file_location("authored_tutor_import", ROOT / "Scripts/import-authored-tutor.py")
IMPORT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(IMPORT)


def publication():
    return {p.name: p.read_bytes() for p in (ROOT / "Learn/AuthoredTutor").iterdir()}


def source_context():
    provenance = json.loads((ROOT / IMPORT.PROVENANCE).read_bytes())
    context = {"repository": provenance["repository"], "source": provenance["source"]}
    if context["source"] == IMPORT.SOURCE:
        context.update(IMPORT.publication_context((ROOT / IMPORT.PUBLICATION_COPY).read_bytes(), publication()))
    return context


def republish(files, mutate):
    """Fixture edit with a fully re-hashed manifest and regenerated data module."""
    result = dict(files)
    values = {name: json.loads(result[name + ".json"]) for name in ("lessons", "questions", "tracks")}
    manifest = json.loads(result["manifest.json"])
    mutate(values, manifest)
    for name, value in values.items():
        result[name + ".json"] = (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode()
    result["bank.mjs"] = ("// Generated StatsDirect built-in tutor source.\n" +
        "export const bankVersion = " + json.dumps(manifest["bankVersion"]) + ";\n" +
        "export const tracks = " + json.dumps(values["tracks"], ensure_ascii=False) + ";\n" +
        "export const questions = " + json.dumps(values["questions"], ensure_ascii=False) + ";\n").encode()
    manifest["files"] = [{"path": name, "bytes": len(result[name]), "sha256": IMPORT.digest(result[name])} for name in sorted(IMPORT.PAYLOAD)]
    result["manifest.json"] = (json.dumps(manifest, indent=2) + "\n").encode()
    return result


def tree(folder):
    return {p.relative_to(folder).as_posix(): p.read_bytes() for p in folder.rglob("*") if p.is_file()}


def shared_publication(files):
    """Actual Tutor bytes plus complete minimal reader/receipt inventories."""
    producer = json.loads(files['manifest.json'])
    contexts = [{'name':'PairedT','link':'paired.htm','resolvedId':'1239'}]
    reader = {
        'index.html': b'<!doctype html><title>Help fixture</title>',
        'paired.htm': b'<!doctype html><h1>Paired t test</h1>',
        'contents-data.js': b'window.StatsDirectContents=[{"title":"Paired t","link":"paired.htm","children":[]}];',
        'search-index.js': b'window.StatsDirectSearch={"documents":[{"url":"paired.htm","title":"Paired t","excerpt":"Paired differences"}],"terms":{"paired":[[0,10]]}};',
        'help-viewer.js': b'// Reader fixture; no external scripts.\n',
        'help-viewer.css': b'body { font-family: sans-serif; }\n',
        'Data/Alias.xml': b'<CatapultAliasFile><Map Name="PairedT" Link="paired.htm" ResolvedId="1239"/></CatapultAliasFile>',
        'build-info.json': json.dumps({'Builder':'StatsDirectHelpEditor prototype','Target':'Website','TopicCount':1,'SearchDocumentCount':1,'Warnings':[]}).encode(),
    }
    desktop = dict(reader)
    desktop['build-info.json'] = json.dumps({'Builder':'StatsDirectHelpEditor prototype','Target':'Desktop','TopicCount':1,'SearchDocumentCount':1,'Warnings':[]}).encode()
    desktop['.statsdirect-help-output.json'] = json.dumps({'files':sorted(desktop)}).encode()
    receipt = {'schemaVersion':1,'format':'statsdirect-desktop-help-v1','entryPage':'index.html','sourceSha256':'1'*64,'publicationSnapshotSha256':'2'*64,'aliasSourceSha256':'3'*64,'contextHeaderSha256':'4'*64,'topicCount':1,'searchDocumentCount':1,'contexts':contexts,
               'files':[dict(path=path,bytes=len(data),sha256=IMPORT.digest(data)) for path,data in sorted(desktop.items())]}
    desktop['.statsdirect-desktop-help.json'] = json.dumps(receipt).encode()
    trees = {'website': reader, 'desktopHelp': desktop, 'tutor': files}
    paths = {'website': 'Docs', 'desktopHelp': 'Published/DesktopHelp', 'tutor': IMPORT.SOURCE}
    artifacts = {}
    for name, entries in trees.items():
        item = {'path': paths[name], 'fileCount': len(entries), 'files': [dict(path=path,bytes=len(data),sha256=IMPORT.digest(data)) for path,data in sorted(entries.items())]}
        if name == 'tutor':
            item.update({key: producer[key] for key in ['lessonCount','questionCount','trackCount','bankVersion']})
            item['reviewProofBinding'] = IMPORT.SOURCE_REVIEW_PROOF
        else:
            item.update(topicCount=1,searchDocumentCount=1)
            if name == 'desktopHelp': item['contextCount']=1
        artifacts[name] = item
    manifest = {'schemaVersion':1,'format':'statsdirect-published-content-v1','publisher':'StatsDirectHelpEditor','publicationId':'0f49b920-2321-47cd-a377-b446e74c4c59','publishedAtUtc':'2026-11-04T15:00:00.1234567+00:00','producer':{'version':'1.0.0','sourceCommit':'b33e71300c12ad5fcc178267e734974cf62e7241'},'helpSourceSha256':'1'*64,'tutorSourceSha256':producer['sourceFileSha256'],'artifacts':artifacts}
    raw = (json.dumps(manifest,indent=2)+'\n').encode()
    return raw,{paths[name]+'/'+path:data for name,entries in trees.items() for path,data in entries.items()}


class AuthoredTutorImportTests(unittest.TestCase):
    def setUp(self):
        self.files = publication()

    def test_actual_published_bundle_retains_original_ids_tracks_and_review_metadata(self):
        manifest = IMPORT.validate_bundle(self.files)
        self.assertEqual(manifest["format"], "statsdirect-builtin-tutor")
        self.assertEqual((manifest["lessonCount"], manifest["questionCount"], manifest["trackCount"]), (12, 35, 5))
        self.assertTrue(manifest["reviewGatePassed"])
        self.assertEqual(manifest["reviewWarningCount"], 47)
        self.assertEqual(manifest["sourceCourseVersion"], "2026-11-03-draft")
        self.assertIn('"id": "UG-SENS-01"', self.files["questions.json"].decode())
        self.assertNotIn('"id": "course:', self.files["questions.json"].decode())

    def test_primary_shared_publication_checks_all_three_git_trees_before_import(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo=Path(tmp)/'repo';repo.mkdir()
            def git(*args):return subprocess.check_output(['git','-C',str(repo),*args],stderr=subprocess.PIPE).decode().strip()
            git('init','--quiet');git('config','user.name','Content fixture');git('config','user.email','fixture@example.invalid');git('remote','add','origin',IMPORT.REPOSITORY+'.git')
            raw,files=shared_publication(self.files)
            for name,data in {**files,IMPORT.PUBLICATION_PATH:raw}.items():
                path=repo/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data)
            git('add','.');git('commit','--quiet','-m','Joint published content fixture')
            sha,loaded,context=IMPORT.read_git(repo,git('rev-parse','HEAD'))
            self.assertEqual(loaded,self.files);self.assertEqual(context['publicationManifestSHA256'],IMPORT.digest(raw));self.assertEqual(context['publicationTutorReviewProofBinding'],IMPORT.SOURCE_REVIEW_PROOF)
            target=Path(tmp)/'consumer';IMPORT.publish(target,IMPORT.imported_files(loaded,sha,IMPORT.validate_bundle(loaded),context))
            self.assertEqual((target/IMPORT.PUBLICATION_COPY).read_bytes(),raw)
            with patch.object(IMPORT.subprocess,'check_output',side_effect=AssertionError('Offline verifier called Git')):IMPORT.verify(target)
            before=tree(target)
            (repo/'Docs/index.html').write_text('Corrupted website, while Tutor is intact');git('add','.');git('commit','--quiet','-m','Partial joint content publication')
            with self.assertRaisesRegex(ValueError,'Git bytes/hash differ'):IMPORT.read_git(repo,git('rev-parse','HEAD'))
            self.assertEqual(tree(target),before)

    def test_shared_root_counts_and_hashes_must_match_child_publication(self):
        raw,_=shared_publication(self.files)
        for edit,expected in [(lambda d:d['artifacts']['tutor'].update(questionCount=999),'counts/version'),(lambda d:d['artifacts']['tutor']['files'][0].update(sha256='0'*64),'differ'),(lambda d:d['artifacts']['tutor'].update(reviewProofBinding='guessed-approval'),'review'),(lambda d:d.update(tutorSourceSha256='0'*64),'source hash')]:
            data=json.loads(raw);edit(data)
            with self.subTest(expected=expected),self.assertRaisesRegex(ValueError,expected):IMPORT.publication_context(json.dumps(data).encode(),self.files)

    def test_full_git_import_is_pinned_and_does_not_change_repository_head(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp) / "repo"; repo.mkdir()
            def git(*args):
                return subprocess.check_output(["git", "-C", str(repo), *args], stderr=subprocess.PIPE).decode().strip()
            git("init", "--quiet"); git("config", "user.name", "Content fixture"); git("config", "user.email", "fixture@example.invalid")
            git("remote", "add", "origin", IMPORT.LEGACY_REPOSITORY + ".git")
            source = repo / IMPORT.LEGACY_SOURCE; source.mkdir(parents=True)
            for name, data in self.files.items():
                (source / name).write_bytes(data)
            git("add", "."); git("commit", "--quiet", "-m", "Actual published content fixture")
            revision = git("rev-parse", "HEAD")
            sha, loaded, context = IMPORT.read_git(repo, revision, IMPORT.LEGACY_SOURCE)
            self.assertEqual((sha, loaded), (revision, self.files))
            self.assertEqual(context, {"repository": IMPORT.LEGACY_REPOSITORY, "source": IMPORT.LEGACY_SOURCE})
            self.assertEqual(git("rev-parse", "HEAD"), revision)
            with self.assertRaisesRegex(ValueError, "pinned"):
                IMPORT.read_git(repo, "HEAD", IMPORT.LEGACY_SOURCE)
            marker = "Learning/.AuthoredTutor.publishing"
            (repo / marker).write_text("incomplete")
            git("add", "."); git("commit", "--quiet", "-m", "Interrupted producer")
            with self.assertRaisesRegex(ValueError, "publishing marker"):
                IMPORT.read_git(repo, git("rev-parse", "HEAD"), IMPORT.LEGACY_SOURCE)
            git("rm", marker); (source / "bank.mjs").unlink(); (source / "bank.mjs").symlink_to("questions.json")
            git("add", "."); git("commit", "--quiet", "-m", "Unsafe source link")
            with self.assertRaisesRegex(ValueError, "Unsafe"):
                IMPORT.read_git(repo, git("rev-parse", "HEAD"), IMPORT.LEGACY_SOURCE)

    def test_missing_partial_wrong_hash_and_executable_bank_are_rejected(self):
        for name in IMPORT.REQUIRED:
            missing = dict(self.files); missing.pop(name)
            with self.assertRaisesRegex(ValueError, "Incomplete"):
                IMPORT.validate_bundle(missing)
        corrupt = dict(self.files); corrupt["questions.json"] += b" "
        with self.assertRaisesRegex(ValueError, "count mismatch"):
            IMPORT.validate_bundle(corrupt)
        for edit, expected in [
            (lambda v, m: m.update(schemaVersion=2), "schema"),
            (lambda v, m: m.update(reviewGatePassed=False), "review gate"),
            (lambda v, m: m.update(unreviewedChangedItems=["UG-SENS-01"]), "unreviewed"),
            (lambda v, m: m.update(questionCount=999), "count mismatch"),
            (lambda v, m: v["questions"][0].update(correct="Z"), "answer key"),
            (lambda v, m: v["questions"][1].update(id=v["questions"][0]["id"]), "duplicate ID"),
            (lambda v, m: v["tracks"].pop("foundation"), "learner pathway"),
        ]:
            with self.subTest(expected=expected), self.assertRaisesRegex(ValueError, expected):
                IMPORT.validate_bundle(republish(self.files, edit))
        malicious = republish(self.files, lambda v, m: None)
        malicious["bank.mjs"] += b"process.exit(99);"
        manifest = json.loads(malicious["manifest.json"])
        for item in manifest["files"]:
            if item["path"] == "bank.mjs": item.update(bytes=len(malicious["bank.mjs"]), sha256=IMPORT.digest(malicious["bank.mjs"]))
        malicious["manifest.json"] = json.dumps(manifest).encode()
        with self.assertRaisesRegex(ValueError, "executable code"):
            IMPORT.validate_bundle(malicious)

    def test_offline_verification_mirrors_and_atomic_rollback(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            manifest = IMPORT.validate_bundle(self.files)
            files = IMPORT.imported_files(self.files, "a" * 40, manifest, source_context())
            IMPORT.publish(root, files)
            before = tree(root)
            with patch.object(IMPORT.subprocess, "check_output", side_effect=AssertionError("Offline verification called Git/network")):
                self.assertEqual(IMPORT.verify(root), manifest)
            replace = IMPORT.os.replace
            def fail_once(source, target):
                if Path(source).name == "learning-manifest.json" and "new" in Path(source).parts:
                    raise OSError("Injected final-file failure")
                return replace(source, target)
            with patch.object(IMPORT.os, "replace", side_effect=fail_once), self.assertRaisesRegex(OSError, "Injected"):
                IMPORT.publish(root, files)
            self.assertEqual(tree(root), before)
            self.assertFalse((root / IMPORT.LOCAL_MARKER).exists())
            (root / "Learn/lessons.json").write_text("[]")
            with self.assertRaisesRegex(ValueError, "differs from provenance"):
                IMPORT.verify(root)
            edited = tree(root)
            with self.assertRaisesRegex(ValueError, "differs from provenance"):
                IMPORT.publish(root, files)
            self.assertEqual(tree(root), edited, "A new import must not discard local edits")
            (root / IMPORT.PROVENANCE).unlink()
            partial = tree(root)
            with self.assertRaisesRegex(ValueError, "partial"):
                IMPORT.publish(root, files)
            self.assertEqual(tree(root), partial)

    def test_all_reviewed_metadata_and_targeting_are_preserved_without_execution(self):
        def edited(values, manifest):
            lesson = values["lessons"][0]
            lesson.update(difficulty="advanced", learnerGoals=["publicHealth", "mastersStatistics"], customMetadata={"retain": True})
            raw = IMPORT.load_json(json.dumps(lesson), preserve_numbers=True)
            lesson["review"] = {"status": "Reviewed by course author", "reviewer": "Example Tutor", "date": "2026-11-04", "notes": "Teaching review only", "contentSha256": IMPORT.record_fingerprint(raw)}
        published = republish(self.files, edited)
        manifest = IMPORT.validate_bundle(published)
        # This mutation fixture uses the explicitly supported legacy contract;
        # the actual new shared publication inventory is immutable test input.
        imported = IMPORT.imported_files(published, "b" * 40, manifest, {"repository": IMPORT.LEGACY_REPOSITORY, "source": IMPORT.LEGACY_SOURCE})
        for name in IMPORT.REQUIRED:
            self.assertEqual(imported["Learn/AuthoredTutor/" + name], published[name])
        lesson = json.loads(imported["Content/Learn/lessons.json"])[0]
        self.assertEqual(lesson["learnerGoals"], ["publicHealth", "mastersStatistics"])
        self.assertEqual(lesson["review"]["reviewer"], "Example Tutor")
        stale = republish(published, lambda values, _: values["lessons"][0].update(summary="Changed after review"))
        # Source-bound approvals intentionally precede generated lesson changes;
        # retaining such a proof does not claim approval of the generated row.
        self.assertEqual(IMPORT.validate_bundle(stale)["reviewGatePassed"], True)
        with self.assertRaisesRegex(ValueError, "Review content SHA-256 mismatch"):
            IMPORT.validate_bundle(stale, review_binding="published-record-v1")

    def test_producer_canonical_fingerprints_match_fixed_dotnet_oracle_vectors(self):
        # Exact output from TutorContentFingerprint.cs via Utf8JsonWriter on
        # .NET10, including its default HTML/Unicode escaping and raw numbers.
        vectors = [
            (json.dumps({"s": ''.join(chr(x) for x in range(128)) + "éβ😀\u2028\u0085", "a": 1.0}),
             "8edd25c3153fd94d39690fbef4c54e3789c2d84405595ed76d6605464ecb1885"),
            ('{"f":1.00,"a":1e+02,"b":-0.0,"review":{"x":1},"nested":{"authoring":{},"review":{"x":1}}}',
             "f15ee16e10505db96f1be79711de2352b8e1b7134f4a9d6d14bd9943ec340167"),
        ]
        for source, expected in vectors:
            self.assertEqual(IMPORT.record_fingerprint(IMPORT.load_json(source, preserve_numbers=True)), expected)
        astral = IMPORT.load_json(r'{"\ud800\udc00":"astral","\ue000":"BMP"}', preserve_numbers=True)
        self.assertLess(IMPORT.fingerprint_value(astral).index('astral'), IMPORT.fingerprint_value(astral).index('BMP'))
        for invalid in ['{"x":1,"x":2}', '{"x":NaN}']:
            with self.assertRaises(ValueError): IMPORT.load_json(invalid)
        with self.assertRaises(ValueError): IMPORT.fingerprint_string("\ud800")


if __name__ == "__main__":
    unittest.main()
