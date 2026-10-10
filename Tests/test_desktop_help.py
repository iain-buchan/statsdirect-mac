"""Check the complete offline bundle and every operation's historical help ID."""
import hashlib
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET

base = Path(__file__).resolve().parents[1]
root = base / "Content/Help"
manifest = json.loads((base / "Content/help-manifest.json").read_text())
actual = {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
          for p in sorted(root.rglob("*")) if p.is_file()}
assert actual == manifest["sha256"], "Bundled files differ from the imported desktop-help manifest"
assert manifest["target"] == "DesktopHelp (offline HTML5)"
aliases = ET.parse(root / "Data/Alias.xml").getroot().findall("Map")
numeric, named = {}, {}
for alias in aliases:
    link = alias.attrib["Link"]
    assert (root / link.split("#")[0]).is_file(), link
    numeric[alias.attrib["ResolvedId"]] = link
    named[alias.attrib["Name"]] = link
assert numeric["1239"] == "parametric_methods/paired_t.htm"
assert numeric["1020"] == "basics/calculator.htm"
calculator = (root / numeric["1020"]).read_text()
for command in ["Tools &gt; Calculator", "Pop out", "Shift+Enter", "Recall", "Insert", "Copy result", "Copy saved"]:
    assert command in calculator, f"Calculator help lacks {command}"
print(f"PASS: {len(actual)} files match source hashes; {len(numeric) + len(named)} numeric/named aliases resolve")
contexts = set()
for file in (base / "FullEngine/Upstream/StatsDirectUI/Assets/Operations").glob("*.xml"):
    contexts.update(re.findall(r'chm-id="(\d+)"', file.read_text()))
assert contexts <= numeric.keys(), contexts - numeric.keys()
for operation in json.loads((base / "Content/analysis-menu.json").read_text())["operations"].values():
    if operation.get("help"):
        assert (base / "Content" / operation["help"]).is_file(), operation
print(f"PASS: all {len(contexts)} engine context IDs and Mac menu help links resolve")
for page in [*root.rglob("*.htm"), *root.rglob("*.html")]:
    assert not re.search(r"googletagmanager|google-analytics|gtag\(", page.read_text()), page
print("PASS: desktop HTML contains no website analytics")
