"""Verify native Creole report exports independently of browser CSS."""
from pathlib import Path
from zipfile import ZipFile
from xml.etree import ElementTree as E
from html.parser import HTMLParser
import sys

folder = Path(sys.argv[1])
ns = {'w': 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'}
w = '{' + ns['w'] + '}'
palette = {'Confidence interval': '0000FF', 'P value': '007F00', 'Test score': '007F7F',
           'Warning': 'FF0000', 'Subtotal': '7F0000', 'Model': '00007F', 'Grand total': '00007F'}
for name in ['creole-report', 'creole-reopened']:
    with ZipFile(folder / (name + '.docx')) as archive:
        doc = E.fromstring(archive.read('word/document.xml'))
    runs = {''.join(r.itertext()): r for r in doc.findall('.//w:r', ns)}
    def prop(text, tag, attr='val'):
        el = runs[text].find('w:rPr/w:' + tag, ns)
        return None if el is None else el.get(w + attr)
    def enabled(text, tag):
        el = runs[text].find('w:rPr/w:' + tag, ns)
        return el is not None and el.get(w + 'val') not in {'false', '0', 'off'}
    for label, color in palette.items():
        assert prop(label, 'color') == color, (name, label, prop(label, 'color'))
    for label in ['Creole title', 'Creole subtitle', 'Creole body', 'Creole table header', '12.500']:
        assert prop(label, 'sz') == '20', (name, label, '10pt')
        assert prop(label, 'rFonts', 'ascii') == 'Arial', (name, label, 'Arial')
    assert prop('Creole body', 'color') == '000000'
    assert enabled('Creole title', 'b')
    for label in ['Creole title', 'Creole subtitle', 'Creole table header']:
        assert enabled(label, 'u'), (name, label, 'underline')
    for label in ['Creole subtitle', 'Creole table header']:
        assert not enabled(label, 'b')
    assert prop('Preformatted  text', 'rFonts', 'ascii') == 'Courier New'
    assert prop('User override', 'color') == '663399'
    assert prop('User override', 'rFonts', 'ascii') == 'Georgia'
    assert prop('User override', 'sz') == '36'
    table = doc.find('.//w:tbl', ns)
    for edge in ['top', 'bottom', 'left', 'right', 'insideH', 'insideV']:
        assert table.find('w:tblPr/w:tblBorders/w:' + edge, ns).get(w + 'val') == 'none'
    for cell in table.findall('w:tr/w:tc', ns):
        assert cell.find('w:p/w:pPr/w:jc', ns).get(w + 'val') == 'left'
        assert cell.find('w:tcPr/w:shd', ns) is None

class Clipboard(HTMLParser):
    def __init__(self):
        super().__init__(); self.cells = []; self.current = None
    def handle_starttag(self, tag, attrs):
        if tag in {'td', 'th'}:
            self.current = [dict(attrs), '']; self.cells.append(self.current)
    def handle_data(self, data):
        if self.current is not None: self.current[1] += data
    def handle_endtag(self, tag):
        if tag in {'td', 'th'}: self.current = None

clipboard = Clipboard()
clipboard.feed((folder / 'creole-clipboard.html').read_text())
cell = next(attrs for attrs, text in clipboard.cells if text.strip() == '12.500')
assert cell['x:num'] == '12.5'
assert 'mso-number-format:0.000' in cell['style'].replace(' ', '').replace('"', '')
print('PASS: Creole Word palette, 10pt typography, plain tables, user overrides, HTML round trip and Excel numeric formatting')
