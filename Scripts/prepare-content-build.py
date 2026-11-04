#!/usr/bin/env python3
"""Refresh a build's published help/tutor pair, or verify a pinned/offline copy.

Only latest mode accesses the network. It resolves one published content commit
before either importer runs. No application, installer or authoring draft is built.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import uuid

BASE = Path(__file__).resolve().parents[1]
ORIGIN = "https://github.com/iain-buchan/statisticalhelp"
PUBLICATION = "Published/content-manifest.json"
MANAGED = ("Content/Help", "Content/help-manifest.json", "Learn/AuthoredTutor", "Learn/lessons.json",
           "Content/Learn/lessons.json", "Content/learning-source-manifest.json", "Content/learning-manifest.json")
spec = importlib.util.spec_from_file_location("statsdirect_content_guard", BASE / "Scripts/check-content-imports.py")
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)
require = guard.require


def git(repository, *args):
    return subprocess.check_output(["git", "-C", str(repository), *args], stderr=subprocess.PIPE).decode().strip()


def cache(repository, create=False):
    repository = Path(repository).absolute()
    require(not repository.is_symlink(), "Content Git cache cannot be a symbolic link")
    if not repository.exists():
        require(create, "Pinned content cache is missing; prepare latest content explicitly first")
        repository.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["git", "init", "--bare", "--quiet", str(repository)], check=True)
        subprocess.run(["git", "-C", str(repository), "remote", "add", "origin", ORIGIN], check=True)
    require(git(repository, "rev-parse", "--is-bare-repository") == "true", "Content cache must be a bare Git repository")
    require(git(repository, "remote", "get-url", "origin").removesuffix(".git") == ORIGIN,
            "Content cache origin must be the official statisticalhelp HTTPS repository")
    lazy = subprocess.run(["git", "-C", str(repository), "config", "--get-regexp",
                           r"^(extensions\.partialclone|remote\..*\.(promisor|partialclonefilter))$"],
                          capture_output=True)
    require(lazy.returncode == 1, "Partial/promisor content caches are not supported; pinned mode must never lazy-fetch")
    return repository


def fetch_origin(repository):
    args = ["fetch", "--no-tags"]
    if git(repository, "rev-parse", "--is-shallow-repository") == "true":
        args.append("--unshallow")
    # A private cache ref avoids reading a changing FETCH_HEAD between imports.
    args += ["origin", "+HEAD:refs/content-build/latest"]
    git(repository, *args)


def choose_revision(repository, mode, revision):
    if mode == "latest":
        require(revision is None, "Use pinned mode when supplying a revision")
        fetch_origin(repository)
        tip = git(repository, "rev-parse", "--verify", "refs/content-build/latest^{commit}")
        revision = git(repository, "log", "-1", "--format=%H", tip, "--", PUBLICATION)
        require(revision, "Remote HEAD has no published content manifest; cached content will not be substituted")
    require(isinstance(revision, str) and re.fullmatch(r"[0-9a-fA-F]{40}", revision),
            "Pinned mode requires a complete 40-character content revision")
    actual = git(repository, "rev-parse", "--verify", revision + "^{commit}")
    require(actual == revision.lower(), "Pinned content revision is not available in this cache")
    size = int(git(repository, "cat-file", "-s", actual + ":" + PUBLICATION))
    require(0 < size <= 20_000_000, "Missing or oversized root publication manifest")
    raw = subprocess.check_output(["git", "-C", str(repository), "show", actual + ":" + PUBLICATION])
    # Child importers validate the producer schema and inventories. Here the
    # exact raw blob binds both imports, without rewriting its serialization.
    value = json.loads(raw, object_pairs_hook=strict_pairs)
    require(isinstance(value, dict), "Malformed root publication manifest")
    digest = hashlib.sha256(raw).hexdigest()
    proof = publication_proof(repository, actual, raw)
    require(isinstance(proof, dict) and proof.get("complete") is True and proof.get("commit") == actual
            and proof.get("publicationManifestSHA256") == digest
            and set(proof.get("artifacts", {})) == {"website", "desktopHelp", "tutor"},
            "The complete website/help/tutor publication has not been verified")
    return actual, digest, proof


def publication_proof(repository, revision, raw_manifest):
    """Validate all three source artifacts, including the unbundled website."""
    spec = importlib.util.spec_from_file_location("statsdirect_content_publication", BASE / "Scripts/content_publication.py")
    loaded = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = loaded
    spec.loader.exec_module(loaded)
    return loaded.verify_git_publication(repository, revision, raw_manifest)


def strict_pairs(items):
    result = {}
    for key, value in items:
        require(key not in result, "Duplicate publication metadata property: " + key)
        result[key] = value
    return result


def snapshot(path):
    """Hash content and metadata without following any symbolic links."""
    path = Path(path)
    if not path.exists() and not path.is_symlink():
        return None
    require(not path.is_symlink(), "Managed content cannot be a symbolic link: " + str(path))
    if path.is_file():
        return ("file", path.stat().st_mode & 0o777, hashlib.sha256(path.read_bytes()).hexdigest())
    require(path.is_dir(), "Managed content has an unsupported type: " + str(path))
    return ("directory", path.stat().st_mode & 0o777,
            tuple((p.name, snapshot(p)) for p in sorted(path.iterdir())))


def managed_snapshot(root):
    return {name: snapshot(Path(root) / name) for name in MANAGED}


def verify_inputs(root, allow_pending=False):
    return guard.verify(root, allow_pending=allow_pending)


def atomic_json(path, value, exclusive=False):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    if exclusive:
        with path.open("x") as stream:
            json.dump(value, stream, indent=2); stream.write("\n"); stream.flush(); os.fsync(stream.fileno())
    else:
        fd, temporary = tempfile.mkstemp(prefix="." + path.name + "-", dir=path.parent)
        try:
            with os.fdopen(fd, "w") as stream:
                json.dump(value, stream, indent=2); stream.write("\n"); stream.flush(); os.fsync(stream.fileno())
            os.replace(temporary, path)
        finally:
            Path(temporary).unlink(missing_ok=True)
    descriptor = os.open(path.parent, os.O_RDONLY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def stage_inputs(repository, revision, stage, expected_hash):
    subprocess.run([sys.executable, str(BASE / "Scripts/import-desktop-help.py"), revision,
                    "--repository", str(repository), "--source-path", "Published/DesktopHelp",
                    "--source-repository", ORIGIN, "--destination", str(stage / "Content/Help"),
                    "--manifest", str(stage / "Content/help-manifest.json")], check=True)
    subprocess.run([sys.executable, str(BASE / "Scripts/import-authored-tutor.py"), revision,
                    "--repository", str(repository), "--source-path", "Published/Tutor",
                    "--output-root", str(stage)], check=True)
    prepared = verify_inputs(stage)
    require(prepared["revision"] == revision and prepared["publicationManifestSHA256"] == expected_hash,
            "Staged content does not match the one selected publication revision")


def remove_owned(path):
    if path.is_dir() and not path.is_symlink():
        shutil.rmtree(path)
    elif path.exists() or path.is_symlink():
        path.unlink()


def activate(root, stage, work, before, revision, publication_hash):
    """Journal a multi-path activation; retain old files if rollback cannot finish."""
    root, stage, work = map(Path, (root, stage, work))
    verify_inputs(root)
    require(managed_snapshot(root) == before, "Content changed during preparation; local edits have been preserved")
    marker = root / guard.PENDING
    journal = {"schemaVersion": 1, "token": uuid.uuid4().hex, "revision": revision,
               "publicationManifestSHA256": publication_hash, "staging": str(work.resolve()), "paths": []}
    atomic_json(marker, journal, exclusive=True)
    changes, safe_cleanup = [], False
    try:
        for name in MANAGED:
            target, incoming, backup = root / name, stage / name, work / "previous" / name
            require(incoming.exists() and not incoming.is_symlink(), "Incomplete staged content: " + name)
            target.parent.mkdir(parents=True, exist_ok=True); backup.parent.mkdir(parents=True, exist_ok=True)
            item = {"path": name, "hadOriginal": target.exists(), "backedUp": False, "activated": False}
            changes.append((item, target, incoming, backup, snapshot(incoming)))
            journal["paths"].append(item); atomic_json(marker, journal)
            if item["hadOriginal"]:
                os.replace(target, backup); item["backedUp"] = True
            os.replace(incoming, target); item["activated"] = True
            atomic_json(marker, journal)
        prepared = verify_inputs(root, allow_pending=True)
        require(prepared["revision"] == revision and prepared["publicationManifestSHA256"] == publication_hash,
                "Activated content lost its publication identity")
        marker.unlink()
        safe_cleanup = True
    except BaseException:
        try:
            for item, target, incoming, backup, expected_new in reversed(changes):
                if item["activated"]:
                    require(snapshot(target) == expected_new,
                            "Activated content was edited; preserving it and the previous content for recovery")
                    remove_owned(target)
                if item["backedUp"]:
                    require(not target.exists(), "Cannot restore content over an unexpected file")
                    os.replace(backup, target)
            require(managed_snapshot(root) == before, "Content rollback needs manual recovery")
            marker.unlink()
            safe_cleanup = True
        except BaseException as error:
            raise ValueError("Content rollback needs recovery; journal and backups retained at " + str(work)) from error
        raise
    finally:
        if safe_cleanup:
            shutil.rmtree(work)


def prepare(root=BASE, mode="latest", revision=None, repository=None, record=None):
    root = Path(root).absolute()
    record = Path(record) if record else root / ".build/content-build-input.json"
    require(mode in ("latest", "pinned", "offline"), "Unsupported content build mode")
    current = verify_inputs(root)
    if mode == "offline":
        require(revision is None, "Offline mode verifies committed imports; use pinned mode for a revision")
        result = {"schemaVersion": 1, "mode": mode, **current, "changed": False}
    else:
        before = managed_snapshot(root)
        repository = cache(repository or root / ".build/statisticalhelp.git", create=mode == "latest")
        selected, publication_hash, proof = choose_revision(repository, mode, revision)
        temporary = root / ".build"
        temporary.mkdir(exist_ok=True)
        require(not temporary.is_symlink() and temporary.stat().st_dev == root.stat().st_dev,
                "Content staging must be on the repository filesystem")
        work = Path(tempfile.mkdtemp(prefix="content-build-", dir=temporary))
        stage = work / "new"; stage.mkdir()
        try:
            stage_inputs(repository, selected, stage, publication_hash)
            changed = managed_snapshot(stage) != before
            if changed:
                activate(root, stage, work, before, selected, publication_hash)
            else:
                require(managed_snapshot(root) == before, "Content changed during preparation")
                shutil.rmtree(work)
        except BaseException:
            if not (root / guard.PENDING).exists() and work.exists():
                shutil.rmtree(work)
            raise
        result = {"schemaVersion": 1, "mode": mode, "revision": selected,
                  "publicationManifestSHA256": publication_hash, "changed": changed,
                  "publicationArtifacts": proof["artifacts"]}
    result["repository"] = ORIGIN
    result["preparedUTC"] = datetime.now(timezone.utc).isoformat()
    atomic_json(record, result)
    print("Content build: " + mode + " · " + (result["revision"] or "legacy independent pins")
          + " · " + ("updated" if result["changed"] else "unchanged"), flush=True)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=("latest", "pinned", "offline"), default="latest")
    parser.add_argument("--revision")
    parser.add_argument("--repository", type=Path)
    parser.add_argument("--output-root", type=Path, default=BASE)
    parser.add_argument("--record", type=Path)
    args = parser.parse_args()
    prepare(args.output_root, args.mode, args.revision, args.repository, args.record)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit("Content build preparation refused: " + str(error))
