#!/usr/bin/env python3
"""Import a committed Windows desktop-help bundle without changing the engine pin."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import xml.etree.ElementTree as ET

base = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("revision", help="Published statsdirect commit containing Assets/Help")
parser.add_argument("--repository", type=Path, default=base / "FullEngine/Upstream")
args = parser.parse_args()
def git(*arguments):
    return subprocess.check_output(["git", "-C", str(args.repository), *arguments])
revision = git("rev-parse", args.revision + "^{commit}").decode().strip()
source = "StatsDirectUI/Assets/Help"
archive = git("archive", revision, source)
with tempfile.TemporaryDirectory(prefix="statsdirect-help-") as temporary:
    with tarfile.open(fileobj=io.BytesIO(archive)) as bundle:
        # This is a git archive of the chosen subtree; reject links and traversal.
        for member in bundle.getmembers():
            if not (member.isfile() or member.isdir()) or ".." in Path(member.name).parts or member.name.startswith("/"):
                raise SystemExit("Unsafe help archive entry: " + member.name)
        bundle.extractall(temporary)
    folder = Path(temporary) / source
    aliases = ET.parse(folder / "Data/Alias.xml").getroot().findall("Map")
    for alias in aliases:
        if not (folder / alias.attrib["Link"].split("#")[0]).is_file():
            raise SystemExit("Missing topic: " + alias.attrib["Link"])
    for required in ["index.html", "Data/Search.js", "resources/stylesheets/desktop.css"]:
        if not (folder / required).is_file():
            raise SystemExit("Incomplete desktop help: " + required)
    manifest = {
        "repository": "https://github.com/iain-buchan/statsdirect",
        "commit": revision, "source": source, "target": "DesktopHelp (offline HTML5)",
        "topics": len(set(a.attrib["Link"] for a in aliases)),
        "sha256": {p.relative_to(folder).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                   for p in sorted(folder.rglob("*")) if p.is_file()},
    }
    destination = base / "Content/Help"
    if destination.exists():
        shutil.rmtree(destination)
    shutil.copytree(folder, destination)
    (base / "Content/help-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
print(f'Imported {len(manifest["sha256"])} desktop help files at {revision}; engine pin unchanged.')
