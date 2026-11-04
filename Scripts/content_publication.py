"""Validate the Help Editor's pinned, shared help/tutor publication offline.

Root inventories describe all public artifacts. Imports verify every Git blob
before activation; offline checks verify the committed consumed copies.
No function fetches, checks out, executes, repairs or publishes source content.
"""
from datetime import datetime, timedelta
import hashlib
import json
import re
import subprocess
import uuid

MANIFEST_PATH = "Published/content-manifest.json"
ARTIFACT_PATHS = {"website": "Docs", "desktopHelp": "Published/DesktopHelp", "tutor": "Published/Tutor"}
READER_FILES = {"index.html", "contents-data.js", "search-index.js", "help-viewer.js",
                "help-viewer.css", "Data/Alias.xml", "build-info.json"}
REQUIRED_FILES = {"website": READER_FILES,
                  "desktopHelp": READER_FILES | {".statsdirect-desktop-help.json"},
                  "tutor": {"manifest.json", "lessons.json", "questions.json", "tracks.json", "bank.mjs", "README.md"}}
HASH = re.compile(r"[0-9a-fA-F]{64}\Z")
REVISION = re.compile(r"[0-9a-fA-F]{40}\Z")


class InvalidPublication(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise InvalidPublication(message)


def path_name(value):
    require(isinstance(value, str) and value and not value.startswith("/")
            and not any(c in value for c in "\\:") and not any(ord(c) < 32 for c in value)
            and all(part not in ("", ".", "..") for part in value.split("/")),
            "Unsafe published content path: " + repr(value))
    parts = value.lower().split("/")
    require(not any(part == ".authoredtutor.publishing" or
                    part.startswith(".statsdirect-") and any(token in part for token in ("publishing", "journal", ".lock"))
                    for part in parts), "Published content contains a pending/private marker: " + value)
    return value


def _document(raw):
    require(isinstance(raw, bytes) and len(raw) <= 20_000_000, "Missing or oversized shared publication manifest")
    def unique(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result, "Duplicate shared publication property: " + key)
            result[key] = value
        return result
    def bad_constant(value):
        raise InvalidPublication("Invalid shared publication number: " + value)
    try:
        text = raw.decode("utf-8")
        document = json.loads(text.lstrip("\ufeff"), object_pairs_hook=unique, parse_constant=bad_constant)
    except (ValueError, UnicodeError) as error:
        raise InvalidPublication("Malformed shared publication manifest: " + str(error)) from error
    require(isinstance(document, dict) and type(document.get("schemaVersion")) is int
            and document["schemaVersion"] == 1 and document.get("format") == "statsdirect-published-content-v1"
            and document.get("publisher") == "StatsDirectHelpEditor", "Unsupported shared publication schema")
    publication_id = document.get("publicationId")
    require(isinstance(publication_id, str) and len(publication_id) == 36, "Invalid publication ID")
    try:
        require(str(uuid.UUID(publication_id)) == publication_id, "Publication ID must be a canonical lowercase GUID")
        timestamp = document["publishedAtUtc"]
        require(isinstance(timestamp, str) and re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?(?:Z|\+00:00)", timestamp),
                "Publication timestamp must be ISO UTC")
        # Preserve the raw manifest; truncate only the parser input for Python
        # versions whose datetime parser supports at most six fractional digits.
        parse_timestamp = re.sub(r"(\.\d{6})\d(?=Z|\+00:00$)", r"\1", timestamp)
        stamp = datetime.fromisoformat(parse_timestamp.replace("Z", "+00:00"))
        require(stamp.utcoffset() == timedelta(0), "Publication timestamp must be UTC")
    except (ValueError, KeyError, AttributeError) as error:
        raise InvalidPublication("Invalid publication ID/timestamp") from error
    producer = document.get("producer")
    require(isinstance(producer, dict) and "sourceCommit" in producer and isinstance(producer.get("version"), str)
            and re.fullmatch(r"\d+\.\d+\.\d+(?:\.\d+)?(?:[-+][A-Za-z0-9.-]+)?", producer["version"])
            and (producer.get("sourceCommit") is None or isinstance(producer["sourceCommit"], str)
                 and REVISION.fullmatch(producer["sourceCommit"])), "Invalid content producer version/revision")
    for key in ("helpSourceSha256", "tutorSourceSha256"):
        require(isinstance(document.get(key), str) and HASH.fullmatch(document[key]), "Invalid publication source hash: " + key)
    artifacts = document.get("artifacts")
    require(isinstance(artifacts, dict) and set(artifacts) == set(ARTIFACT_PATHS), "All three published artifacts must be declared")
    inventories = {}
    for name, prefix in ARTIFACT_PATHS.items():
        item = artifacts[name]
        require(isinstance(item, dict) and item.get("path") == prefix, "Unexpected published artifact path: " + name)
        files = item.get("files")
        require(isinstance(files, list) and files and type(item.get("fileCount")) is int
                and item["fileCount"] == len(files), "Published artifact file count differs: " + name)
        counts = ("lessonCount", "questionCount", "trackCount") if name == "tutor" else ("topicCount", "searchDocumentCount")
        if name == "desktopHelp":
            counts += ("contextCount",)
        for key in counts:
            require(type(item.get(key)) is int and item[key] >= (0 if key == "searchDocumentCount" else 1),
                    "Invalid published artifact count: " + name + "/" + key)
        if name == "tutor":
            require(isinstance(item.get("bankVersion"), str) and item["bankVersion"].strip(), "Missing published question bank version")
            require(item.get("reviewProofBinding") == "authoring-source-before-generated-sync-v1", "Unsupported published tutor review proof binding")
        else:
            require(item["searchDocumentCount"] <= item["topicCount"], "Search count exceeds published topic count")
        inventory, seen = {}, set()
        for file in files:
            require(isinstance(file, dict), "Invalid published artifact file record")
            relative = path_name(file.get("path"))
            require(relative.casefold() not in seen, "Duplicate/case-colliding published file: " + relative)
            require(type(file.get("bytes")) is int and 0 <= file["bytes"] <= 100_000_000
                    and isinstance(file.get("sha256"), str) and HASH.fullmatch(file["sha256"]),
                    "Invalid published file size/hash: " + relative)
            seen.add(relative.casefold())
            inventory[relative] = {"bytes": file["bytes"], "sha256": file["sha256"].lower()}
        require(REQUIRED_FILES[name] <= set(inventory), "Published artifact required files are missing: " + name)
        inventories[name] = inventory
    return document, inventories, text


def validate_publication(raw_bytes, artifact_name, child_file_inventory):
    """Validate all root declarations and the selected committed/imported tree."""
    document, inventories, text = _document(raw_bytes)
    require(artifact_name in ARTIFACT_PATHS, "Unknown published artifact: " + str(artifact_name))
    require(child_file_inventory == inventories[artifact_name],
            "Consumed " + artifact_name + " files differ from the shared publication manifest")
    return {"publicationManifestSHA256": hashlib.sha256(raw_bytes).hexdigest(),
            "publicationManifestPath": MANIFEST_PATH, "publicationManifestText": text,
            "publicationProducer": document["producer"],
            "publicationArtifact": {key: value for key, value in document["artifacts"][artifact_name].items() if key != "files"},
            "publicationTutorReviewProofBinding": document["artifacts"]["tutor"]["reviewProofBinding"]}


def verify_git_publication(repository, revision, raw_manifest):
    """Hash every website/help/tutor blob at one exact local Git commit."""
    require(isinstance(revision, str) and REVISION.fullmatch(revision), "Pin a full shared publication commit")
    revision = revision.lower()
    _, inventories, _ = _document(raw_manifest)
    def git(*args):
        return subprocess.check_output(["git", "-C", str(repository), *args])
    actual = git("rev-parse", revision + "^{commit}").decode().strip()
    require(actual == revision, "Shared publication revision changed")
    top = git("ls-tree", "-z", revision)
    for record in top.split(b"\0"):
        if record:
            name = record.split(b"\t", 1)[1].decode("utf-8")
            require(not (name.startswith(".statsdirect-") and
                         any(token in name.lower() for token in ("publishing", "journal", ".lock"))),
                    "Pinned content has an incomplete/private publication marker: " + name)
    expected = {prefix + "/" + name: value for artifact, prefix in ARTIFACT_PATHS.items()
                for name, value in inventories[artifact].items()}
    tree = git("ls-tree", "-r", "-z", revision, "--", "Docs", "Published")
    entries = {}
    for record in tree.split(b"\0"):
        if not record:
            continue
        fields, encoded = record.split(b"\t", 1)
        mode, kind, oid = fields.decode("ascii").split()
        name = path_name(encoded.decode("utf-8"))
        require(kind == "blob" and mode in ("100644", "100755"), "Published links/submodules are not allowed: " + name)
        require(name not in entries, "Duplicate published Git path")
        entries[name] = oid
    allowed = set(expected) | {MANIFEST_PATH, "Published/.gitattributes"}
    require(set(expected) | {MANIFEST_PATH} <= set(entries) and set(entries) <= allowed,
            "Incomplete/unexpected shared Git publication files: " + repr(sorted(set(entries).symmetric_difference(set(expected) | {MANIFEST_PATH}) - {"Published/.gitattributes"})[:12]))
    hashes, total = {}, 0
    # One local object reader, including the root manifest's own pinned bytes.
    with subprocess.Popen(["git", "-C", str(repository), "cat-file", "--batch"], stdin=subprocess.PIPE, stdout=subprocess.PIPE) as process:
        try:
            for name in sorted(entries):
                process.stdin.write((entries[name] + "\n").encode("ascii"));process.stdin.flush()
                header = process.stdout.readline().decode("ascii").split()
                require(len(header) == 3 and header[1] == "blob", "Cannot read pinned publication blob: " + name)
                size = int(header[2]);require(size <= 100_000_000, "Oversized published blob: " + name)
                data = process.stdout.read(size)
                require(len(data) == size and process.stdout.read(1) == b"\n", "Truncated publication blob: " + name)
                if name == MANIFEST_PATH:
                    require(data == raw_manifest, "Shared root manifest does not match the pinned Git revision")
                elif name in expected:
                    value = {"bytes": size, "sha256": hashlib.sha256(data).hexdigest()}
                    require(value == expected[name], "Published Git bytes/hash differ: " + name)
                    hashes[name] = value;total += size
            process.stdin.close();require(process.wait() == 0, "Git object reader failed")
        finally:
            if process.poll() is None:
                process.terminate();process.wait()
    return {"schemaVersion": 1, "commit": revision,
            "publicationManifestSHA256": hashlib.sha256(raw_manifest).hexdigest(),
            "artifacts": {name: {"files": len(inventory), "bytes": sum(item["bytes"] for item in inventory.values())}
                          for name, inventory in inventories.items()},
            "verifiedFiles": len(hashes), "verifiedBytes": total, "complete": True}
