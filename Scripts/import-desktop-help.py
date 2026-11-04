#!/usr/bin/env python3
"""Explicitly import pinned offline help; normal builds only verify committed files.

Legacy Windows/Flare bundles remain supported. Help Editor deliveries additionally
need the publisher's complete receipt, Desktop target and reader data. No command
fetches a remote revision or changes the calculation-engine checkout.
"""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
from urllib.parse import unquote, urlsplit
import uuid
import xml.etree.ElementTree as ET

BASE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BASE / "Scripts"))
from content_publication import InvalidPublication, MANIFEST_PATH, validate_publication, verify_git_publication

RECEIPT = ".statsdirect-desktop-help.json"
PENDING = ".statsdirect-desktop-help.publishing.json"
EDITOR_REQUIRED = ("index.html", "contents-data.js", "search-index.js", "help-viewer.js",
                   "help-viewer.css", "Data/Alias.xml", "build-info.json")
HASH = re.compile(r"[0-9a-fA-F]{64}\Z")
REVISION = re.compile(r"[0-9a-fA-F]{40}\Z")


class InvalidHelp(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise InvalidHelp(message)


def relative_path(value):
    require(isinstance(value, str) and value and "\\" not in value and ":" not in value
            and not value.startswith("/") and not any(ord(c) < 32 for c in value),
            "Unsafe help path: " + repr(value))
    require(all(part not in ("", ".", "..") for part in value.split("/")),
            "Unsafe help path: " + repr(value))
    return value


def topic_path(value):
    require(isinstance(value, str), "Invalid help topic link")
    require(not urlsplit(value).scheme and not urlsplit(value).netloc, "External help topic: " + value)
    return relative_path(unquote(value.split("#", 1)[0].split("?", 1)[0]))


def inventory(folder):
    require(folder.is_dir() and not folder.is_symlink(), "Missing regular help directory")
    files = {}
    seen = set()
    for directory, subdirs, names in os.walk(folder, followlinks=False):
        parent = Path(directory)
        for name in subdirs + names:
            path = parent / name
            require(not path.is_symlink(), "Help links are not allowed: " + str(path))
            relative = relative_path(path.relative_to(folder).as_posix())
            require(relative.casefold() not in seen, "Case-colliding help paths: " + relative)
            seen.add(relative.casefold())
        for name in names:
            path = parent / name
            require(path.is_file(), "Unsupported help file: " + str(path))
            require(path.stat().st_size <= 100_000_000, "Oversized help asset: " + str(path))
            files[path.relative_to(folder).as_posix()] = {
                "bytes": path.stat().st_size, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
    require(files, "Empty desktop help")
    return dict(sorted(files.items()))


def json_document(text):
    def unique(pairs):
        value = {}
        for key, item in pairs:
            require(key not in value, "Duplicate help metadata property: " + key)
            value[key] = item
        return value
    def invalid_constant(value):
        raise InvalidHelp("Non-finite help metadata number: " + value)
    return json.loads(text, object_pairs_hook=unique, parse_constant=invalid_constant)


def read_json(path):
    require(path.is_file() and not path.is_symlink() and path.stat().st_size <= 20_000_000,
            "Missing or oversized help metadata: " + path.name)
    try:
        return json_document(path.read_text(encoding="utf-8-sig"))
    except (ValueError, UnicodeError) as error:
        raise InvalidHelp("Malformed help metadata: " + path.name) from error


def reader_data(folder, filename, prefix):
    try:
        text = (folder / filename).read_text(encoding="utf-8-sig").strip()
        require(text.startswith(prefix) and text.endswith(";"), "Incomplete reader data: " + filename)
        return json_document(text[len(prefix):-1])
    except (ValueError, UnicodeError) as error:
        raise InvalidHelp("Malformed reader data: " + filename) from error


def public_asset(relative):
    """Match the publisher's reader-only contract, including its two receipts."""
    parts = relative.split("/")
    private = {".git", ".svn", ".hg", ".codex", "settings", "project", "content", "tutorsource", "chatgpt"}
    profiles = (".editor-profile", ".tutor-preview-profile", ".app-help-preview-profile",
                ".browser-preview-profile", ".help-editor-recovery")
    if any(part.lower() in private or part.lower().startswith(profiles) for part in parts):
        return False
    name = parts[-1].lower()
    if name in {".statsdirect-help-editor.json", "authoring-preferences.json", "auth.json",
                "credentials.json", "account-state.json"} or name.startswith(".env"):
        return False
    if relative in (".statsdirect-help-output.json", RECEIPT):
        return True
    if name in ("license", "notice"):
        return True
    extension = PurePosixPath(name).suffix
    if extension in (".txt", ".md"):
        return name.startswith(("license", "notice", "third-party"))
    if extension == ".props":
        return name.endswith(".js.props")
    return extension in {".htm", ".html", ".js", ".css", ".map", ".xml", ".json", ".mcwebhelp",
                         ".png", ".gif", ".jpg", ".jpeg", ".svg", ".ico", ".bmp", ".webp", ".cur",
                         ".woff", ".woff2", ".ttf", ".eot"}


def aliases(folder, files):
    path = folder / "Data/Alias.xml"
    require(path.is_file() and path.stat().st_size <= 20_000_000, "Missing context aliases")
    text = path.read_bytes()
    require(not re.search(br"<!\s*(?:DOCTYPE|ENTITY)\b", text, re.I), "Help alias DTD/entities are not allowed")
    try:
        maps = ET.fromstring(text).findall("Map")
    except ET.ParseError as error:
        raise InvalidHelp("Malformed help alias XML") from error
    require(maps, "Help aliases are empty")
    names, ids, result = set(), set(), []
    for item in maps:
        name, link, number = item.get("Name"), item.get("Link"), item.get("ResolvedId")
        require(isinstance(name, str) and name and name not in names, "Missing/duplicate help alias name")
        names.add(name)
        require(topic_path(link) in files, "Missing context topic: " + str(link))
        if number is not None:
            require(number.isascii() and number.isdecimal() and number not in ids,
                    "Invalid/duplicate numeric help alias: " + number)
            ids.add(number)
        result.append({"name": name, "link": link, "resolvedId": number})
    return result


def validate_bundle(folder):
    """Validate complete output without executing its JavaScript or copying files."""
    folder = Path(folder)
    files = inventory(folder)
    require(PENDING not in files, "Desktop help publication is incomplete")
    contexts = aliases(folder, files)
    editor = any(name in files for name in (RECEIPT, "build-info.json", "search-index.js", "contents-data.js"))
    metadata = {"format": "legacy-flare", "contexts": len(contexts),
                "topics": len({item["link"] for item in contexts})}
    if not editor:
        for name in ("index.html", "Data/Search.js", "resources/stylesheets/desktop.css"):
            require(name in files, "Incomplete legacy desktop help: " + name)
        return files, metadata
    for name in EDITOR_REQUIRED + (RECEIPT,):
        require(name in files, "Incomplete published Help Editor desktop help: " + name)
    require(all(public_asset(name) for name in files), "Desktop output contains private/source or unsupported files")
    receipt = read_json(folder / RECEIPT)
    require(isinstance(receipt, dict) and type(receipt.get("schemaVersion")) is int
            and receipt["schemaVersion"] == 1 and receipt.get("format") == "statsdirect-desktop-help-v1"
            and receipt.get("entryPage") == "index.html", "Unsupported desktop delivery receipt")
    require(isinstance(receipt.get("sourceSha256"), str) and HASH.fullmatch(receipt["sourceSha256"]),
            "Invalid desktop source hash")
    for name in ("publicationSnapshotSha256", "aliasSourceSha256", "contextHeaderSha256"):
        require(receipt.get(name) is None or isinstance(receipt[name], str) and HASH.fullmatch(receipt[name]),
                "Invalid desktop provenance hash: " + name)
    recorded = receipt.get("files")
    require(isinstance(recorded, list) and recorded, "Missing desktop delivery inventory")
    expected, case_paths = {}, set()
    for item in recorded:
        require(isinstance(item, dict), "Invalid desktop delivery inventory item")
        name = relative_path(item.get("path"))
        require(name != RECEIPT and name.casefold() not in case_paths,
                "Duplicate/reserved receipt file: " + name)
        require(type(item.get("bytes")) is int and 0 <= item["bytes"] <= 100_000_000
                and isinstance(item.get("sha256"), str) and HASH.fullmatch(item["sha256"]),
                "Invalid desktop delivery size/hash: " + name)
        expected[name] = {"bytes": item["bytes"], "sha256": item["sha256"].lower()}
        case_paths.add(name.casefold())
    require(expected == {name: item for name, item in files.items() if name != RECEIPT},
            "Desktop files differ from the complete publisher receipt")
    info = read_json(folder / "build-info.json")
    require(isinstance(info, dict) and info.get("Target") == "Desktop", "Help target must be Desktop")
    for key in ("TopicCount", "SearchDocumentCount"):
        require(type(info.get(key)) is int and info[key] >= (1 if key == "TopicCount" else 0),
                "Invalid desktop build count: " + key)
    require(type(receipt.get("topicCount")) is int and receipt["topicCount"] == info["TopicCount"]
            and type(receipt.get("searchDocumentCount")) is int
            and receipt["searchDocumentCount"] == info["SearchDocumentCount"],
            "Desktop receipt/build counts differ")
    require(receipt.get("contexts") == contexts, "Desktop receipt aliases differ from Data/Alias.xml")
    search = reader_data(folder, "search-index.js", "window.StatsDirectSearch=")
    require(isinstance(search, dict) and isinstance(search.get("documents"), list)
            and isinstance(search.get("terms"), dict), "Invalid desktop search schema")
    documents = search["documents"]
    require(len(documents) == info["SearchDocumentCount"], "Desktop search count differs from receipt")
    require(len(documents) <= info["TopicCount"], "Desktop search exceeds its topic count")
    seen_documents = set()
    for item in documents:
        require(isinstance(item, dict) and isinstance(item.get("title"), str)
                and isinstance(item.get("excerpt"), str) and topic_path(item.get("url")) in files,
                "Invalid/missing desktop search topic")
        require(item["url"] not in seen_documents, "Duplicate desktop search topic")
        seen_documents.add(item["url"])
    for term, postings in search["terms"].items():
        require(isinstance(term, str) and term and isinstance(postings, list), "Invalid search postings")
        for entry in postings:
            require(isinstance(entry, list) and len(entry) == 2 and all(type(n) is int for n in entry)
                    and 0 <= entry[0] < len(documents) and entry[1] > 0, "Invalid search posting target")
    contents = reader_data(folder, "contents-data.js", "window.StatsDirectContents=")
    def check_contents(nodes, depth=0):
        require(isinstance(nodes, list) and depth < 100, "Invalid desktop contents schema")
        for node in nodes:
            require(isinstance(node, dict) and isinstance(node.get("title"), str)
                    and isinstance(node.get("children"), list), "Invalid desktop contents item")
            require(node.get("link") is None or topic_path(node["link"]) in files,
                    "Missing desktop contents topic")
            check_contents(node["children"], depth + 1)
    check_contents(contents)
    metadata.update(format="help-editor-desktop-v1", topics=info["TopicCount"],
                    searchDocuments=len(documents), producer={
                        "name": "StatsDirect Help Editor", "receipt": RECEIPT,
                        "receiptSHA256": files[RECEIPT]["sha256"],
                        "sourceSHA256": receipt["sourceSha256"].lower(),
                        "publicationSnapshotSHA256": receipt.get("publicationSnapshotSha256")})
    return files, metadata


def repository_url(value):
    require(isinstance(value, str) and re.fullmatch(r"https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", value),
            "Choose an HTTPS GitHub repository without credentials, query or fragment")
    return value


def desktop_publication(raw, files, metadata):
    publication = validate_publication(raw, "desktopHelp", files)
    counts = publication["publicationArtifact"]
    require(metadata["format"] == "help-editor-desktop-v1" and counts["topicCount"] == metadata["topics"]
            and counts["searchDocumentCount"] == metadata["searchDocuments"]
            and counts["contextCount"] == metadata["contexts"], "Shared help counts differ from the actual published reader")
    return publication


def prepare_manifest(folder, repository, revision, source, source_kind="git-tree", producer_revision=None, publication_bytes=None):
    require(isinstance(revision, str) and REVISION.fullmatch(revision), "Pin a full 40-character content commit")
    files, metadata = validate_bundle(folder)
    manifest = {"schemaVersion": 2, "repository": repository_url(repository), "commit": revision.lower(),
                "source": relative_path(source), "sourceKind": source_kind,
                "target": "DesktopHelp (offline HTML5)", **metadata,
                "sha256": {name: item["sha256"] for name, item in files.items()}}
    if producer_revision is not None:
        require(REVISION.fullmatch(producer_revision), "Pin a full 40-character producer revision")
        require(metadata["format"] == "help-editor-desktop-v1", "Producer revision requires a published Help Editor delivery")
        manifest["producer"]["commit"] = producer_revision.lower()
    if publication_bytes is not None:
        publication = desktop_publication(publication_bytes, files, metadata)
        manifest.update(publication)
        declared_producer = publication["publicationProducer"].get("sourceCommit")
        if declared_producer is not None:
            require(producer_revision is None or producer_revision.lower() == declared_producer.lower(),
                    "Requested producer revision differs from the shared publication")
            manifest["producer"]["commit"] = declared_producer.lower()
    return manifest


def pending_marker(manifest_path):
    return manifest_path.with_name(manifest_path.stem + ".publishing.json")


def verify_import(destination, manifest_path):
    """Verify committed help offline, including its producer receipt if present."""
    destination, manifest_path = Path(destination), Path(manifest_path)
    require(not pending_marker(manifest_path).exists(), "Help import is incomplete; finish or recover it before building")
    manifest = read_json(manifest_path)
    require(isinstance(manifest, dict) and manifest.get("schemaVersion", 1) in (1, 2)
            and type(manifest.get("schemaVersion", 1)) is int, "Unsupported imported help manifest schema")
    repository_url(manifest.get("repository"))
    require(isinstance(manifest.get("commit"), str) and REVISION.fullmatch(manifest["commit"]), "Invalid content pin")
    relative_path(manifest.get("source"))
    require(manifest.get("target") == "DesktopHelp (offline HTML5)", "Invalid help target")
    files, metadata = validate_bundle(destination)
    require(manifest.get("sha256") == {name: item["sha256"] for name, item in files.items()},
            "Committed help differs from its complete import manifest")
    require(manifest.get("topics") == metadata["topics"], "Imported help topic count differs")
    if manifest.get("schemaVersion") == 2:
        require(manifest.get("sourceKind") in ("git-tree", "published-directory"), "Invalid content source kind")
        require(manifest.get("format") == metadata["format"], "Imported help format differs")
        if metadata.get("producer"):
            expected = dict(metadata["producer"])
            producer = manifest.get("producer")
            require(isinstance(producer, dict), "Missing producer provenance")
            if "commit" in producer:
                require(isinstance(producer["commit"], str) and REVISION.fullmatch(producer["commit"]), "Invalid producer pin")
                expected["commit"] = producer["commit"]
            require(producer == expected, "Producer provenance differs from desktop receipt")
            require(manifest.get("searchDocuments") == metadata["searchDocuments"], "Imported search count differs")
            if manifest["sourceKind"] == "published-directory":
                require("commit" in producer, "Published-directory help needs a producer revision")
        shared = manifest.get("repository") == "https://github.com/iain-buchan/statisticalhelp" and manifest.get("source") == "Published/DesktopHelp"
        if shared or "publicationManifestSHA256" in manifest:
            require(isinstance(manifest.get("publicationManifestText"), str), "Missing retained shared publication manifest")
            publication = desktop_publication(manifest["publicationManifestText"].encode("utf-8"), files, metadata)
            require(all(manifest.get(key) == value for key, value in publication.items()), "Shared help publication provenance differs")
    return manifest


def install_bundle(source, destination, manifest_path, manifest):
    """Stage both outputs, guard builds, and retain backups if rollback fails."""
    source, destination, manifest_path = Path(source), Path(destination), Path(manifest_path)
    require(not destination.is_symlink() and not manifest_path.is_symlink(), "Import destination cannot be a link")
    require(source.resolve() != destination.resolve()
            and source.resolve() not in destination.resolve().parents
            and destination.resolve() not in source.resolve().parents, "Import source and destination overlap")
    marker = pending_marker(manifest_path)
    require(not marker.exists(), "A previous help import needs recovery before replacement")
    require(destination.exists() == manifest_path.exists(), "Existing help has no matching import manifest; preserve and review it first")
    if destination.exists():
        verify_import(destination, manifest_path)
    previous_manifest = manifest_path.read_bytes() if manifest_path.exists() else None
    previous_files = inventory(destination) if destination.exists() else None
    destination.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix=".help-import-", dir=destination.parent))
    staged, previous = work / "incoming", work / "previous"
    temporary_manifest = None
    moved, activated, safe_cleanup = False, False, True
    try:
        shutil.copytree(source, staged)
        require(inventory(staged) == inventory(source), "Help input changed while staging")
        require(manifest["sha256"] == {name: item["sha256"] for name, item in inventory(staged).items()},
                "Staged help differs from validated input")
        fd, name = tempfile.mkstemp(prefix=".help-manifest-", dir=manifest_path.parent)
        temporary_manifest = Path(name)
        with os.fdopen(fd, "w") as stream:
            stream.write(json.dumps(manifest, indent=2) + "\n");stream.flush();os.fsync(stream.fileno())
        token = uuid.uuid4().hex
        with marker.open("x") as stream:
            json.dump({"schemaVersion": 1, "token": token, "destination": str(destination.resolve()),
                       "previous": str(previous.resolve()), "staged": str(staged.resolve())}, stream)
        try:
            require((manifest_path.read_bytes() if manifest_path.exists() else None) == previous_manifest
                    and (inventory(destination) if destination.exists() else None) == previous_files,
                    "Existing help changed while the import was staged; no current files were replaced")
            if destination.exists():
                os.replace(destination, previous);moved = True;safe_cleanup = False
            os.replace(staged, destination);activated = True
            os.replace(temporary_manifest, manifest_path)
        except BaseException:
            try:
                if activated:
                    shutil.rmtree(destination)
                if moved:
                    os.replace(previous, destination)
                marker.unlink()
                safe_cleanup = True
            except (OSError, InvalidHelp) as recovery_error:
                raise InvalidHelp("Help activation failed; original files and pending marker are retained for recovery: " + str(work)) from recovery_error
            raise
        marker.unlink()
        safe_cleanup = True
    finally:
        if temporary_manifest is not None:
            temporary_manifest.unlink(missing_ok=True)
        if safe_cleanup:
            shutil.rmtree(work)


def read_git_bundle(repository, revision, source, temporary):
    def git(*args):
        return subprocess.check_output(["git", "-C", str(repository), *args])
    require(REVISION.fullmatch(revision), "Pin a full 40-character content commit")
    actual = git("rev-parse", revision + "^{commit}").decode().strip()
    require(actual == revision.lower(), "Content revision differs from requested pin")
    relative_path(source)
    pending = subprocess.run(["git", "-C", str(repository), "cat-file", "-e", actual + ":" + PENDING],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    require(pending.returncode != 0, "Pinned desktop-help publication is incomplete")
    archive = git("archive", actual, source)
    with tarfile.open(fileobj=io.BytesIO(archive)) as bundle:
        seen = set()
        for member in bundle.getmembers():
            name = relative_path(member.name.rstrip("/"))
            require(name.casefold() not in seen, "Duplicate/case-colliding help archive paths")
            seen.add(name.casefold())
            require((member.isfile() or member.isdir()) and
                    (name == source or name.startswith(source + "/") or
                     member.isdir() and source.startswith(name + "/")),
                    "Unsafe help archive entry: " + member.name)
        bundle.extractall(temporary)
    return Path(temporary) / source


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("revision", nargs="?", help="Full published source commit (no network fetch)")
    parser.add_argument("--repository", type=Path, default=BASE / ".build/statisticalhelp.git")
    parser.add_argument("--source", type=Path, help="A separately supplied published Help Editor desktop directory")
    parser.add_argument("--source-repository", help="GitHub repository containing the pinned authored source")
    parser.add_argument("--source-path", help="Logical source subtree at the pinned revision")
    parser.add_argument("--producer-revision", help="Full published Help Editor producer revision")
    parser.add_argument("--destination", type=Path, default=BASE / "Content/Help")
    parser.add_argument("--manifest", type=Path, default=BASE / "Content/help-manifest.json")
    parser.add_argument("--verify", action="store_true", help="Only verify committed content/manifest offline")
    parser.add_argument("--check-only", action="store_true", help="Validate an explicit refresh without replacing outputs")
    args = parser.parse_args(argv)
    if args.verify:
        require(not args.revision and not args.source and not args.check_only, "--verify only reads committed help")
        manifest = verify_import(args.destination, args.manifest)
        print(f'Verified {len(manifest["sha256"])} offline help files at {manifest["commit"]}.')
        return
    require(args.revision is not None, "Supply a full pinned content revision")
    source_path = args.source_path or "Published/DesktopHelp"
    source_repo = args.source_repository or "https://github.com/iain-buchan/statisticalhelp"
    with tempfile.TemporaryDirectory(prefix="statsdirect-help-") as temporary:
        if args.source:
            require(args.source_repository and args.source_path and args.producer_revision,
                    "Directory input requires explicit source repository/path and producer revision")
            for parent in [args.source, *list(args.source.parents)[:3]]:
                require(not (parent / PENDING).exists(), "Desktop help publication is incomplete")
            folder, kind = args.source, "published-directory"
        else:
            folder = read_git_bundle(args.repository, args.revision, source_path, temporary)
            kind = "git-tree"
        publication_bytes = None
        if source_repo == "https://github.com/iain-buchan/statisticalhelp" and source_path == "Published/DesktopHelp":
            if args.source:
                require(args.check_only, "Directory input checks only the selected artifact; use a pinned Git publication to activate all-three-verified shared content")
                publication_path = args.source.parent / "content-manifest.json"
                require(publication_path.is_file() and not publication_path.is_symlink(), "Missing shared publication manifest beside DesktopHelp")
                publication_bytes = publication_path.read_bytes()
            else:
                publication_bytes = subprocess.check_output(["git", "-C", str(args.repository), "show", args.revision + ":" + MANIFEST_PATH])
                verify_git_publication(args.repository, args.revision, publication_bytes)
        manifest = prepare_manifest(folder, source_repo, args.revision, source_path, kind, args.producer_revision, publication_bytes)
        if args.source:
            require(manifest["format"] == "help-editor-desktop-v1", "Directory input requires a published Help Editor delivery")
        if not args.check_only:
            install_bundle(folder, args.destination, args.manifest, manifest)
    print(f'{"Validated" if args.check_only else "Imported"} {len(manifest["sha256"])} desktop help files at {manifest["commit"]}; engine pin unchanged.')


if __name__ == "__main__":
    try:
        main()
    except (InvalidHelp, InvalidPublication, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit("Help import refused: " + str(error))
