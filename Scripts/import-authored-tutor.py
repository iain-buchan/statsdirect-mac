#!/usr/bin/env python3
"""Explicitly import pinned Help Editor tutor output; verify offline during builds.

The engine checkout is only an object cache: importing never fetches, checks out
or changes its pin. Published JavaScript is validated as data, never executed.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

BASE = Path(__file__).resolve().parents[1]
REPOSITORY = "https://github.com/iain-buchan/statisticalhelp"
SOURCE = "Published/Tutor"
LEGACY_REPOSITORY = "https://github.com/iain-buchan/statsdirect"
LEGACY_SOURCE = "Learning/AuthoredTutor"
REQUIRED = {"manifest.json", "README.md", "lessons.json", "questions.json", "tracks.json", "bank.mjs"}
PAYLOAD = {"lessons.json", "questions.json", "tracks.json", "bank.mjs"}
MARKER = "Published/.Tutor.publishing"
LOCAL_MARKER = "Learn/.AuthoredTutor.importing"
PROVENANCE = "Content/learning-manifest.json"
PUBLICATION_PATH = "Published/content-manifest.json"
PUBLICATION_COPY = "Content/learning-source-manifest.json"
SOURCE_REVIEW_PROOF = "authoring-source-before-generated-sync-v1"
ID = re.compile(r"[A-Za-z0-9_-]{1,100}\Z")
SHA = re.compile(r"[0-9a-f]{64}\Z")
GOALS = {"undergraduateMedicine", "undergraduateHealthScience", "postgraduateMedicine", "postgraduateAlliedHealth",
         "publicHealth", "healthcareBusinessAnalyst", "mastersStatistics", "usMedicalBoards"}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


class RawNumber:
    def __init__(self, token):
        self.token = token


def load_json(data, preserve_numbers=False):
    def pairs(items):
        result = {}
        for key, value in items:
            require(key not in result, "Duplicate JSON property: " + key)
            result[key] = value
        return result
    def constant(value):
        raise ValueError("Non-finite JSON number: " + value)
    number_options = {"parse_int": RawNumber, "parse_float": RawNumber} if preserve_numbers else {}
    return json.loads(data, object_pairs_hook=pairs, parse_constant=constant, **number_options)


def fingerprint_string(value):
    """Utf8JsonWriter's default BasicLatin/HTML-safe encoder, not Python JSON."""
    output = ['"']
    escapes = {8: r"\b", 9: r"\t", 10: r"\n", 12: r"\f", 13: r"\r", 92: r"\\"}
    for character in value:
        point = ord(character)
        require(not 0xD800 <= point <= 0xDFFF, "Unpaired surrogate in tutor content")
        if point in escapes:
            output.append(escapes[point])
        elif 32 <= point <= 126 and character not in '"&\'+<>`':
            output.append(character)
        elif point <= 0xFFFF:
            output.append(r"\u%04X" % point)
        else:
            point -= 0x10000
            output.append(r"\u%04X\u%04X" % (0xD800 + (point >> 10), 0xDC00 + (point & 1023)))
    return ''.join(output) + '"'


def fingerprint_value(value, root=False):
    # TutorContentFingerprint.cs at Help Editor b33e7130: StringComparer.Ordinal
    # orders UTF-16 units; authoring is omitted at every depth, review and
    # verification only at the record root. JsonElement numbers retain spelling.
    if isinstance(value, dict):
        keys = sorted(value, key=lambda key: key.encode('utf-16-be'))
        return '{' + ','.join(fingerprint_string(key) + ':' + fingerprint_value(value[key]) for key in keys
                              if key != 'authoring' and not (root and key in ('review', 'verification'))) + '}'
    if isinstance(value, list):
        return '[' + ','.join(fingerprint_value(item) for item in value) + ']'
    if isinstance(value, RawNumber):
        return value.token
    if value is None:
        return 'null'
    if type(value) is bool:
        return 'true' if value else 'false'
    require(isinstance(value, str), "Unexpected tutor fingerprint value")
    return fingerprint_string(value)


def record_fingerprint(record):
    return digest(fingerprint_value(record, root=True).encode('utf-8'))


def text(value):
    return isinstance(value, str) and bool(value.strip())


def integer(value):
    return type(value) is int and value >= 0


def rows(value, label):
    require(isinstance(value, list) and value, label + " must be a nonempty array")
    identifiers = set()
    for item in value:
        require(isinstance(item, dict) and isinstance(item.get("id"), str) and ID.fullmatch(item["id"]), label + " has an invalid stable ID")
        require(item["id"] not in identifiers, label + " has duplicate ID " + item["id"])
        identifiers.add(item["id"])
    return identifiers


def generated_bank(data):
    # The publisher emits exactly these JSON-valued declarations. Do not import
    # or evaluate an upstream JavaScript module while refreshing content.
    source = data.decode("utf-8")
    source = re.sub(r"\A//[^\r\n]*(?:\r?\n)", "", source, count=1)
    values = {}
    for name in ("bankVersion", "tracks", "questions"):
        match = re.match(r"\s*export const " + name + r"\s*=\s*", source)
        require(match is not None, "Unexpected generated bank declaration: " + name)
        start = match.end()
        # Use the strict JSON reader too, so duplicate keys/non-finite numbers
        # in module literals cannot silently disagree with the JSON files.
        _, end = json.JSONDecoder().raw_decode(source, start)
        values[name] = load_json(source[start:end])
        source = source[end:]
        require(source.startswith(";"), "Generated bank declaration lacks terminator")
        source = source[1:]
    require(not source.strip(), "Unexpected executable code in generated bank")
    return values


def publication_context(raw, files):
    from content_publication import validate_publication
    inventory = {name: {"bytes": len(data), "sha256": digest(data)} for name, data in files.items()}
    validated = validate_publication(raw, "tutor", inventory)
    require(validated["publicationManifestPath"] == PUBLICATION_PATH, "Unexpected shared publication manifest path")
    artifact = load_json(raw)["artifacts"]["tutor"]
    producer = load_json(files["manifest.json"])
    require(load_json(raw)["tutorSourceSha256"] == producer.get("sourceFileSha256"),
            "Shared publication tutor source hash differs from its child manifest")
    require(all(artifact.get(field) == producer.get(field) for field in ("lessonCount", "questionCount", "trackCount", "bankVersion")),
            "Shared publication tutor counts/version disagree with its child manifest")
    return {"publicationManifestSHA256": validated["publicationManifestSHA256"],
            "publicationManifestPath": validated["publicationManifestPath"], "publicationManifestBytes": raw,
            "publicationTutorReviewProofBinding": validated["publicationTutorReviewProofBinding"]}


def validate_bundle(files, review_binding=SOURCE_REVIEW_PROOF):
    require(review_binding in (SOURCE_REVIEW_PROOF, "published-record-v1"), "Unsupported tutor review proof binding")
    require(set(files) == REQUIRED, "Incomplete or unexpected AuthoredTutor files: " + repr(sorted(set(files) ^ REQUIRED)))
    for name, data in files.items():
        require(len(data) <= 5 * 1024 * 1024, "AuthoredTutor file is too large: " + name)
    manifest = load_json(files["manifest.json"])
    require(isinstance(manifest, dict) and manifest.get("schemaVersion") == 1 and type(manifest.get("schemaVersion")) is int,
            "Unsupported tutor manifest schema")
    require(manifest.get("format") == "statsdirect-builtin-tutor" and manifest.get("publisher") == "StatsDirectHelpEditor",
            "Unexpected tutor publisher or format")
    require(manifest.get("reviewGatePassed") is True, "Tutor publication did not pass its changed-item review gate")
    require(isinstance(manifest.get("unreviewedChangedItems"), list) and not manifest["unreviewedChangedItems"],
            "Tutor publication has unreviewed changed items")
    require(isinstance(manifest.get("reviewedChangedItems"), list), "Missing changed-item review metadata")
    for field in ("bankVersion", "sourceCourseId", "sourceCourseVersion", "publishedAtUtc"):
        require(text(manifest.get(field)), "Missing tutor provenance field: " + field)
    for field in ("sourceCourseSha256", "readmeSha256"):
        require(isinstance(manifest.get(field), str) and SHA.fullmatch(manifest[field]), "Invalid tutor provenance hash: " + field)
    require(manifest.get("sourceFileName") is None and manifest.get("sourceFileSha256") is None or
            text(manifest.get("sourceFileName")) and isinstance(manifest.get("sourceFileSha256"), str) and SHA.fullmatch(manifest["sourceFileSha256"]),
            "Invalid tutor source-file provenance pair")
    require(isinstance(manifest.get("reviewIssues"), list) and integer(manifest.get("reviewWarningCount")), "Missing tutor review issues")
    require(manifest["reviewWarningCount"] == sum(issue.get("severity") == "Warning" for issue in manifest["reviewIssues"] if isinstance(issue, dict)),
            "Tutor warning count disagrees with review issues")
    require(not any(not isinstance(issue, dict) or issue.get("severity") not in ("Warning", "Information") for issue in manifest["reviewIssues"]),
            "Tutor publication contains an error or invalid review issue")
    declared = manifest.get("files")
    require(isinstance(declared, list) and len(declared) == len(PAYLOAD), "Invalid tutor file manifest")
    seen = set()
    for entry in declared:
        require(isinstance(entry, dict) and entry.get("path") in PAYLOAD and entry["path"] not in seen,
                "Unsafe, unexpected or duplicate tutor manifest path")
        name = entry["path"]; seen.add(name)
        require(integer(entry.get("bytes")) and entry["bytes"] == len(files[name]), "Tutor byte count mismatch: " + name)
        require(entry.get("sha256") == digest(files[name]), "Tutor SHA-256 mismatch: " + name)
    require(seen == PAYLOAD and manifest["readmeSha256"] == digest(files["README.md"]), "Tutor file or README hash mismatch")
    lessons, questions, tracks = [load_json(files[name + ".json"]) for name in ("lessons", "questions", "tracks")]
    lesson_ids = rows(lessons, "Lessons"); question_ids = rows(questions, "Questions")
    for name in ("lessons.json", "questions.json"):
        for record in load_json(files[name], preserve_numbers=True):
            review = record.get('review')
            if review is None:
                review = {}
            require(isinstance(review, dict), "Invalid review metadata")
            content_hash = review.get('contentSha256')
            reviewed = str(review.get('status', '')).strip().lower().startswith('reviewed')
            if reviewed or content_hash is not None:
                require(isinstance(content_hash, str) and SHA.fullmatch(content_hash), "Invalid source review proof: " + str(record.get('id')))
                # The published v1 contract approves source BEFORE embedded-MCQ
                # synchronisation/contentVersion suffixes. Its proof must stay
                # verbatim; claiming it binds the transformed record is false.
                if review_binding == "published-record-v1":
                    require(content_hash == record_fingerprint(record), "Review content SHA-256 mismatch: " + str(record.get('id')))
            if reviewed:
                require(text(review.get('reviewer')) and text(review.get('notes')) and
                        isinstance(review.get('date'), str) and re.fullmatch(r'\d{4}-\d{2}-\d{2}', review['date']),
                        "Reviewed record needs its reviewer, notes and date: " + str(record.get('id')))
    require(isinstance(tracks, dict) and tracks, "Tracks must be a nonempty object")
    for key, track in tracks.items():
        require(ID.fullmatch(key) and isinstance(track, dict) and text(track.get("title")) and
                (track.get("description") is None or isinstance(track["description"], str)), "Invalid tutor track")
    require({"foundation", "medicine", "publicHealth", "analyst", "researcher"} <= tracks.keys(), "Publication removed an existing learner pathway")
    for lesson in lessons:
        require(all(text(lesson.get(k)) for k in ("title", "objective", "summary")), "Incomplete lesson: " + lesson["id"])
        require(all(lesson.get(k) is None or isinstance(lesson[k], str) for k in ("topic", "challenge", "steps", "r", "help")), "Invalid optional lesson text: " + lesson["id"])
        require(lesson.get("columns") is None or isinstance(lesson["columns"], list), "Invalid lesson columns: " + lesson["id"])
        require(lesson.get("review") is None or isinstance(lesson["review"], dict), "Invalid lesson review metadata: " + lesson["id"])
        require(all(lesson.get(k) is None or isinstance(lesson[k], list) and all(isinstance(v, str) for v in lesson[k]) for k in ("prerequisites", "assessmentIds")), "Invalid lesson references: " + lesson["id"])
        require(set(lesson.get("prerequisites") or []) <= lesson_ids, "Unknown lesson prerequisite: " + lesson["id"])
        require(set(lesson.get("assessmentIds") or []) <= question_ids, "Unknown lesson assessment: " + lesson["id"])
    for question in questions:
        require(type(question.get("version")) is int and question["version"] >= 1, "Invalid question version: " + question["id"])
        require(isinstance(question.get("track"), str) and (question["track"] in tracks or question["track"] == "core"), "Unknown question track: " + question["id"])
        require(all(text(question.get(k)) for k in ("stem", "correct", "explanation")) and
                all(isinstance(question.get(k), str) for k in ("topic", "hint", "lesson", "help")), "Incomplete question: " + question["id"])
        options = question.get("options"); option_ids = rows(options, "Question options")
        require(2 <= len(options) <= 8 and all(o["id"] in "ABCDEFGH" and len(o["id"]) == 1 and text(o.get("text")) and isinstance(o.get("feedback"), str) for o in options) and question["correct"] in option_ids,
                "Invalid options or answer key: " + question["id"])
        require(not question.get("lessonId") or question["lessonId"] in lesson_ids, "Unknown question lesson: " + question["id"])
        require(question.get("difficulty") is None or question["difficulty"] in ("beginner", "intermediate", "advanced"), "Invalid question difficulty: " + question["id"])
        goals = question.get("learnerGoals")
        require(goals is None or isinstance(goals, list) and all(isinstance(g, str) and g in GOALS for g in goals) and len(goals) == len(set(goals)),
                "Invalid or duplicate learner goals: " + question["id"])
        require(question.get("learnerGoalNotes") is None or isinstance(question["learnerGoalNotes"], str) and len(question["learnerGoalNotes"].encode('utf-16-le')) <= 6000,
                "Invalid learner goal notes: " + question["id"])
    for name, value in (("lessonCount", lessons), ("questionCount", questions), ("trackCount", tracks)):
        require(type(manifest.get(name)) is int and manifest[name] == len(value), "Tutor count mismatch: " + name)
    by_question = {item['id']: item for item in questions}
    for lesson in lessons:
        embedded = lesson.get('practiceQuestions')
        require(embedded is None or isinstance(embedded, list), "Invalid embedded question collection: " + lesson['id'])
        if embedded is not None:
            require(all(isinstance(item, dict) and isinstance(item.get('id'), str) and item['id'] in by_question and item == by_question[item['id']] for item in embedded),
                    "Embedded questions differ from the authoritative flat collection: " + lesson['id'])
    bank = generated_bank(files["bank.mjs"])
    require(bank == {"bankVersion": manifest["bankVersion"], "tracks": tracks, "questions": questions}, "Generated tutor bank disagrees with JSON inputs")
    return manifest


def read_git(repository, revision, source_path=SOURCE):
    require(re.fullmatch(r"[0-9a-fA-F]{40}", revision) is not None, "Choose a full pinned 40-character commit, not a moving branch")
    def git(*args):
        return subprocess.check_output(["git", "-C", str(repository), *args], stderr=subprocess.PIPE)
    resolved = git("rev-parse", "--verify", revision + "^{commit}").decode().strip()
    require(resolved == revision.lower(), "The requested revision is not the pinned commit")
    origin = git("remote", "get-url", "origin").decode().strip().removesuffix(".git")
    if origin.startswith("git@github.com:"):
        origin = "https://github.com/" + origin.removeprefix("git@github.com:")
    require((origin, source_path) in ((REPOSITORY, SOURCE), (LEGACY_REPOSITORY, LEGACY_SOURCE)), "Tutor repository origin/source is not a supported published contract")
    marker = str(Path(source_path).parent / ("." + Path(source_path).name + ".publishing"))
    require(not git("ls-tree", resolved, "--", marker).strip(), "Tutor publication is incomplete (publishing marker present)")
    entries = git("ls-tree", "-r", "-z", resolved, "--", source_path).split(b"\0")
    files = {}
    for record in entries:
        if not record:
            continue
        info, path = record.split(b"\t", 1)
        mode, kind, object_id = info.decode().split()
        relative = path.decode().removeprefix(source_path + "/")
        require(mode in ("100644", "100755") and kind == "blob" and relative in REQUIRED and relative not in files,
                "Unsafe or unexpected tutor source file: " + relative)
        size = int(git("cat-file", "-s", object_id))
        require(size <= 5 * 1024 * 1024, "Tutor source file is too large: " + relative)
        files[relative] = git("cat-file", "blob", object_id)
    context = {"repository": origin, "source": source_path}
    if source_path == SOURCE:
        shared = git("ls-tree", resolved, "--", PUBLICATION_PATH).decode().split()
        require(len(shared) == 4 and shared[:2] == ["100644", "blob"], "Missing or unsafe shared content manifest")
        require(int(git("cat-file", "-s", shared[2])) <= 20_000_000, "Shared content manifest is too large")
        raw = git("cat-file", "blob", shared[2])
        context.update(publication_context(raw, files))
        from content_publication import verify_git_publication
        verify_git_publication(repository, resolved, raw)
    return resolved, files, context


def imported_files(files, revision, producer, context):
    result = {"Learn/AuthoredTutor/" + name: data for name, data in files.items()}
    result.update({"Learn/lessons.json": files["lessons.json"], "Content/Learn/lessons.json": files["lessons.json"]})
    if context["source"] == SOURCE:
        result[PUBLICATION_COPY] = context["publicationManifestBytes"]
    manifest = {"schemaVersion": 1, "format": "statsdirect-builtin-tutor-import", "repository": context["repository"],
                "commit": revision, "source": context["source"], "publisher": producer["publisher"],
                "producerSchemaVersion": producer["schemaVersion"], "producerManifestSHA256": digest(files["manifest.json"]),
                "sourceCourseId": producer["sourceCourseId"], "sourceCourseVersion": producer["sourceCourseVersion"],
                "bankVersion": producer["bankVersion"], "reviewGatePassed": producer["reviewGatePassed"],
                "reviewWarningCount": producer["reviewWarningCount"], "sha256": {name: digest(data) for name, data in sorted(result.items())}}
    if context["source"] == SOURCE:
        manifest.update({key: context[key] for key in ("publicationManifestSHA256", "publicationManifestPath", "publicationTutorReviewProofBinding")})
    result[PROVENANCE] = (json.dumps(manifest, indent=2, ensure_ascii=False) + "\n").encode()
    return result


def verify(output):
    require(not (output / LOCAL_MARKER).exists(), "Tutor import is incomplete (local import marker present)")
    folder = output / "Learn/AuthoredTutor"
    require(folder.is_dir() and not folder.is_symlink(), "No committed authored tutor bundle; run an explicit pinned import first")
    require({p.name for p in folder.iterdir()} == REQUIRED, "Authored tutor directory is incomplete or contains unexpected files")
    require(all(p.is_file() and not p.is_symlink() for p in folder.iterdir()), "Authored tutor bundle contains a link or special file")
    files = {p.name: p.read_bytes() for p in folder.iterdir()}
    producer = validate_bundle(files)
    provenance = load_json((output / PROVENANCE).read_bytes())
    require(isinstance(provenance, dict), "Invalid tutor provenance object")
    require(isinstance(provenance.get("commit"), str) and re.fullmatch(r"[0-9a-f]{40}", provenance["commit"]), "Invalid pinned tutor provenance")
    context = {"repository": provenance.get("repository"), "source": provenance.get("source")}
    require((context["repository"], context["source"]) in ((REPOSITORY, SOURCE), (LEGACY_REPOSITORY, LEGACY_SOURCE)), "Unsupported tutor provenance source")
    if context["source"] == SOURCE:
        path = output / PUBLICATION_COPY
        require(path.is_file() and not path.is_symlink(), "Missing retained shared content publication manifest")
        context.update(publication_context(path.read_bytes(), files))
    expected = imported_files(files, provenance["commit"], producer, context)
    for relative, data in expected.items():
        path = output / relative
        require(path.is_file() and not path.is_symlink() and path.read_bytes() == data, "Committed tutor content differs from provenance: " + relative)
    return producer


def publish(output, files):
    if (output / "Learn/AuthoredTutor").exists() or (output / PROVENANCE).exists():
        require((output / "Learn/AuthoredTutor").is_dir() and (output / PROVENANCE).is_file(),
                "Existing tutor publication is partial; preserve and repair it before importing")
        verify(output)
    output.mkdir(parents=True, exist_ok=True)
    marker = output / LOCAL_MARKER
    marker.parent.mkdir(parents=True, exist_ok=True)
    # A failed publication remains visible to the normal offline build verifier.
    with marker.open("x") as handle:
        handle.write("Authored tutor import in progress\n")
    temporary = Path(tempfile.mkdtemp(prefix=".tutor-import-", dir=output))
    changes = []
    rollback_ok = True
    try:
        for relative, data in files.items():
            staged = temporary / "new" / relative
            staged.parent.mkdir(parents=True, exist_ok=True); staged.write_bytes(data)
        target_paths = ["Learn/AuthoredTutor", "Learn/lessons.json", "Content/Learn/lessons.json", PROVENANCE]
        if PUBLICATION_COPY in files:
            target_paths.append(PUBLICATION_COPY)
        for index, relative in enumerate(target_paths):
            target, staged = output / relative, temporary / "new" / relative
            require(not target.is_symlink(), "Refusing to replace a tutor content symlink: " + relative)
            target.parent.mkdir(parents=True, exist_ok=True)
            backup = temporary / ("backup-" + str(index))
            had_original = target.exists()
            if had_original:
                os.replace(target, backup)
            changes.append((target, backup, had_original))
            os.replace(staged, target)
    except BaseException:
        for target, backup, had_original in reversed(changes):
            try:
                if target.is_dir() and not target.is_symlink():
                    shutil.rmtree(target)
                elif target.exists() or target.is_symlink():
                    target.unlink()
                if had_original:
                    os.replace(backup, target)
            except OSError:
                rollback_ok = False
        raise
    finally:
        if rollback_ok:
            shutil.rmtree(temporary)
            marker.unlink()
        else:
            print("Tutor rollback needs attention; preserved backup: " + str(temporary), file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("revision", nargs="?", help="Full published statisticalhelp content commit")
    parser.add_argument("--repository", type=Path, default=BASE / ".build/statisticalhelp.git")
    parser.add_argument("--source-path", choices=(SOURCE, LEGACY_SOURCE), default=SOURCE)
    parser.add_argument("--output-root", type=Path, default=BASE)
    parser.add_argument("--verify", action="store_true", help="Verify committed content offline; no Git or network access")
    args = parser.parse_args()
    try:
        if args.verify:
            require(args.revision is None, "--verify uses committed provenance; do not supply a revision")
            producer = verify(args.output_root)
            print("Verified offline tutor inputs: %d lessons, %d questions, %d pathways; %d retained producer review warnings." %
                  tuple(producer[k] for k in ("lessonCount", "questionCount", "trackCount", "reviewWarningCount")))
        else:
            require(args.revision is not None, "Supply a full pinned content commit, or --verify")
            revision, files, context = read_git(args.repository, args.revision, args.source_path)
            producer = validate_bundle(files)
            publish(args.output_root, imported_files(files, revision, producer, context))
            verify(args.output_root)
            print("Imported tutor content at %s: %d lessons, %d questions; %d retained producer review warnings. Engine pin unchanged." %
                  (revision, producer["lessonCount"], producer["questionCount"], producer["reviewWarningCount"]))
        return 0
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print("Tutor import failed: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
