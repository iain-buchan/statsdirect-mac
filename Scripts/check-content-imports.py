#!/usr/bin/env python3
"""Verify bundled help and tutor publications together, entirely offline."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import sys

BASE = Path(__file__).resolve().parents[1]
PENDING = ".statsdirect-content-build.publishing.json"
PUBLISHED = "https://github.com/iain-buchan/statisticalhelp"
LEGACY = "https://github.com/iain-buchan/statsdirect"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def read_json(path):
    def pairs(items):
        result = {}
        for key, value in items:
            require(key not in result, "Duplicate content metadata property: " + key)
            result[key] = value
        return result
    require(path.is_file() and not path.is_symlink(), "Missing regular content metadata: " + str(path))
    return json.loads(path.read_bytes(), object_pairs_hook=pairs)


def shared_pin(help_manifest, tutor_manifest):
    """New publications are a pair; legacy engine-independent imports remain valid."""
    for item in (help_manifest, tutor_manifest):
        require(isinstance(item, dict) and isinstance(item.get("commit"), str)
                and re.fullmatch(r"[0-9a-f]{40}", item["commit"]), "Invalid pinned content revision")
    repositories = (help_manifest.get("repository"), tutor_manifest.get("repository"))
    if repositories == (PUBLISHED, PUBLISHED):
        require(help_manifest.get("source") == "Published/DesktopHelp"
                and tutor_manifest.get("source") == "Published/Tutor", "Unexpected published content paths")
        require(help_manifest["commit"] == tutor_manifest["commit"],
                "Help and tutor content come from different published revisions")
        require(all(item.get("publicationManifestPath") == "Published/content-manifest.json"
                    for item in (help_manifest, tutor_manifest)), "Unexpected publication-manifest path")
        hashes = [item.get("publicationManifestSHA256") for item in (help_manifest, tutor_manifest)]
        require(all(isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value) for value in hashes),
                "Missing publication-manifest SHA-256 in help or tutor provenance")
        require(hashes[0] == hashes[1], "Help and tutor content refer to different publication manifests")
        return {"revision": help_manifest["commit"], "publicationManifestSHA256": hashes[0]}
    require(repositories == (LEGACY, LEGACY), "Mixed legacy and published content imports")
    require(help_manifest.get("source") == "StatsDirectUI/Assets/Help"
            and tutor_manifest.get("source") == "Learning/AuthoredTutor", "Unexpected legacy content paths")
    return {"revision": None, "publicationManifestSHA256": None}


def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, BASE / "Scripts" / filename)
    loaded = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(loaded)
    return loaded


def verify(root, allow_pending=False):
    root = Path(root)
    require(allow_pending or not (root / PENDING).exists(),
            "A content build import was interrupted; recover its journal before building")
    help_import = module("statsdirect_build_help_import", "import-desktop-help.py")
    tutor_import = module("statsdirect_build_tutor_import", "import-authored-tutor.py")
    help_manifest = help_import.verify_import(root / "Content/Help", root / "Content/help-manifest.json")
    tutor = tutor_import.verify(root)
    tutor_manifest = read_json(root / "Content/learning-manifest.json")
    pin = shared_pin(help_manifest, tutor_manifest)
    if pin["revision"] is not None:
        raw = root / "Content/learning-source-manifest.json"
        require(raw.is_file() and not raw.is_symlink() and raw.stat().st_size <= 20_000_000,
                "Missing regular shared publication manifest")
        require(hashlib.sha256(raw.read_bytes()).hexdigest() == pin["publicationManifestSHA256"],
                "Bundled shared publication manifest hash differs from the content pair")
    return {**pin, "helpRevision": help_manifest["commit"], "tutorRevision": tutor_manifest["commit"],
            "helpFiles": len(help_manifest["sha256"]), "lessons": tutor["lessonCount"],
            "questions": tutor["questionCount"], "tracks": tutor["trackCount"]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=BASE)
    args = parser.parse_args()
    result = verify(args.root)
    print("Verified bundled help and tutor content: " + (result["revision"] or "legacy independent pins"))
    print(json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError) as error:
        raise SystemExit("Content verification refused: " + str(error))
