"""Verify actual Word drawing paragraphs, including after HTML reopening."""
from pathlib import Path
from zipfile import ZipFile
from xml.etree import ElementTree as E
import sys

folder=Path(sys.argv[1])
ns={'w':'http://schemas.openxmlformats.org/wordprocessingml/2006/main',
    'wp':'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing'}
expected={'Left chart':'left','Centre chart':'center','Right chart':'right','Right picture':'right'}
for name in ['chart-alignment','chart-alignment-reopened']:
    with ZipFile(folder/(name+'.docx')) as archive:
        root=E.fromstring(archive.read('word/document.xml'))
        actual={}
        for paragraph in root.findall('.//w:p',ns):
            drawing=paragraph.find('.//wp:docPr',ns)
            if drawing is not None:
                actual[drawing.get('descr')]=paragraph.find('w:pPr/w:jc',ns).get('{'+ns['w']+'}val')
        assert actual==expected,(name,actual)
        assert sum(p.endswith('.svg') for p in archive.namelist())==3
        assert sum(p.endswith('.png') for p in archive.namelist())>=4
    print('PASS:',name,'DOCX preserves left/centre/right picture paragraphs and SVG/PNG fallbacks')
