"""Inspect the exported Word package for all five independent R chart pictures."""
from pathlib import Path
from zipfile import ZipFile
from xml.etree import ElementTree as E
import re
import sys

folder = Path(sys.argv[1])
with ZipFile(folder / 'r-charts-roundtrip.docx') as archive:
    files = archive.namelist()
    vectors = [path for path in files if path.endswith('.svg')]
    rasters = [path for path in files if path.endswith('.png')]
    document = E.fromstring(archive.read('word/document.xml'))
    drawings = document.findall('.//{http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing}inline')
    assert len(drawings) == len(vectors) == 5
    # The repeated chart legitimately shares its identical PNG fallback.
    assert len(rasters) == 4
    relationships = E.fromstring(archive.read('word/_rels/document.xml.rels'))
    targets = {item.get('Id'): 'word/' + item.get('Target') for item in relationships}
    for drawing in drawings:
        blip = drawing.find('.//{http://schemas.openxmlformats.org/drawingml/2006/main}blip')
        picture = targets[blip.get('{http://schemas.openxmlformats.org/officeDocument/2006/relationships}embed')]
        assert picture in rasters, 'Every drawing must have a packaged PNG fallback'
    seen = set()
    labels = []
    glyphs = 0
    for path in vectors:
        root = E.fromstring(archive.read(path))
        ids = {node.attrib['id'] for node in root.iter() if 'id' in node.attrib}
        assert not seen.intersection(ids), 'Chart identifiers overlap between exported vectors'
        seen.update(ids)
        for node in root.iter():
            for name, value in node.attrib.items():
                refs = re.findall(r'''url\(\s*["']?\#([^\s"'()<>]+)["']?\s*\)''', value)
                if name.split('}')[-1] == 'href' and value.startswith('#'):
                    refs.append(value[1:])
                assert all(ref in ids for ref in refs), (path, 'Missing chart definition', refs)
            if node.tag.endswith('}use'):
                glyphs += 1
        assert not root.findall('.//{http://www.w3.org/2000/svg}style'), 'Chart CSS must be scoped and inlined'
        labels.append(''.join(root.itertext()))
    assert sum('BEFORE 123' in label for label in labels) == 2
    assert sum('AFTER 789' in label for label in labels) == 1
    assert glyphs == 2, 'Cairo-style glyph references must remain vector drawings'
print('PASS: DOCX retains five separate SVG charts and PNG fallbacks, including repeated R charts and local glyph/clip/gradient references')
