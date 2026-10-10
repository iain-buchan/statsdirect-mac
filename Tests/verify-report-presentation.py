"""Check styles in real Word packages and the native Office clipboard payload."""
from pathlib import Path
from zipfile import ZipFile
from xml.etree import ElementTree as E
from html.parser import HTMLParser
import sys

folder=Path(sys.argv[1])
ns={'w':'http://schemas.openxmlformats.org/wordprocessingml/2006/main'}
w='{'+ns['w']+'}'
def val(el,name='val'):
    assert el is not None
    return el.get(w+name)
def text(el): return ''.join(el.itertext())
def run(doc,label): return next(r for r in doc.findall('.//w:r',ns) if label in text(r))
def para(doc,label): return next(p for p in doc.findall('.//w:p',ns) if label in text(p))
def cell(doc,label): return next(c for c in doc.findall('.//w:tc',ns) if text(c)==label)
for name in ['presentation-report','presentation-reopened']:
    with ZipFile(folder/(name+'.docx')) as archive: doc=E.fromstring(archive.read('word/document.xml'))
    tables=doc.findall('.//w:tbl',ns)
    assert len(tables)==2
    for edge in ['top','bottom','left','right','insideH','insideV']:
        assert val(tables[0].find('w:tblPr/w:tblBorders/w:'+edge,ns))=='none', (name,edge,'invented table border')
    for c in tables[0].findall('w:tr/w:tc',ns):
        for edge in ['top','bottom','left','right']:
            assert val(c.find('w:tcPr/w:tcBorders/w:'+edge,ns))=='none'
        for r in c.findall('.//w:r',ns):
            assert val(r.find('w:rPr/w:rFonts',ns),'ascii')=='Arial'
            assert val(r.find('w:rPr/w:sz',ns))=='20'
            assert val(r.find('w:rPr/w:b',ns)) in {'false','0','off'}
        assert val(c.find('w:p/w:pPr/w:jc',ns))=='left', (name,text(c),'alignment changed')
        assert c.find('w:tcPr/w:shd',ns) is None, (name,'invented header/cell shading')
    assert run(doc,'Plain heading').find('w:rPr/w:u',ns) is not None
    custom=cell(doc,'Custom cell')
    props=run(doc,'Custom cell').find('w:rPr',ns)
    assert val(props.find('w:rFonts',ns),'ascii')=='Georgia'
    assert val(props.find('w:sz',ns))=='36'
    assert val(props.find('w:color',ns))=='663399'
    assert val(custom.find('w:tcPr/w:shd',ns),'fill')=='FFFF00'
    assert val(custom.find('w:tcPr/w:vAlign',ns))=='center'
    assert val(custom.find('w:p/w:pPr/w:jc',ns))=='center'
    for edge,style,size,color in [('top','single','12','CC0000'),('bottom','dashed','18','0000CC'),('left','dotted','6','660066')]:
        border=custom.find('w:tcPr/w:tcBorders/w:'+edge,ns)
        assert (val(border),val(border,'sz'),val(border,'color'))==(style,size,color), (name,edge,E.tostring(border))
    assert val(custom.find('w:tcPr/w:tcBorders/w:right',ns))=='none'
    for side,size in [('top','90'),('bottom','90'),('left','150'),('right','150')]:
        assert val(custom.find('w:tcPr/w:tcMar/w:'+side,ns),'w')==size
    assert val(cell(doc,'Row fill').find('w:tcPr/w:shd',ns),'fill')=='DDFFEE'
    for edge in ['top','bottom','left','right']:
        border=tables[1].find('w:tblPr/w:tblBorders/w:'+edge,ns)
        assert (val(border),val(border,'sz'),val(border,'color'))==('single','12','008000')
    pre=para(doc,'Preformatted  spaces')
    assert pre.find('.//w:br',ns) is not None, 'Lost preformatted newline'
    assert val(run(doc,'Preformatted  spaces').find('w:rPr/w:rFonts',ns),'ascii')=='Georgia'
    assert val(run(doc,'Preformatted  spaces').find('w:rPr/w:sz',ns))=='28'
    assert val(run(doc,'Bold second line').find('w:rPr/w:color',ns))=='CC0000'
    assert run(doc,'Bold second line').find('w:rPr/w:b',ns).get(w+'val') not in {'false','0','off'}
    assert val(run(doc,'Explicit code font').find('w:rPr/w:rFonts',ns),'ascii')=='Arial'
    heading=run(doc,'Custom heading')
    assert val(heading.find('w:rPr/w:sz',ns))=='32'
    assert val(heading.find('w:rPr/w:b',ns)) in {'false','0','off'}
    spacing=para(doc,'Custom heading').find('w:pPr/w:spacing',ns)
    assert (val(spacing,'before'),val(spacing,'after'))==('180','120')
    spacing=para(doc,'Custom paragraph').find('w:pPr/w:spacing',ns)
    assert (val(spacing,'before'),val(spacing,'after'),val(spacing,'line'))==('120','180','360')
print('PASS: original/reopened Word packages preserve cell/run styles, no invented borders/shading, independent borders, padding, row fills, preformatted runs and heading/paragraph spacing')

class Clipboard(HTMLParser):
    def __init__(self): super().__init__();self.cells=[];self.current=None;self.cols=[]
    def handle_starttag(self,tag,attrs):
        if tag in {'td','th'}: self.current=[dict(attrs),''];self.cells.append(self.current)
        if tag=='col': self.cols.append(dict(attrs))
    def handle_data(self,data):
        if self.current is not None: self.current[1]+=data
    def handle_endtag(self,tag):
        if tag in {'td','th'}: self.current=None
for name in ['presentation-clipboard','presentation-direct']:
    parsed=Clipboard();parsed.feed((folder/(name+'.html')).read_text())
    cells={t.strip():a for a,t in parsed.cells}
    for label,value,fmt in [('12.500','12.5','0.000'),('95.00%','0.95','0.00%'),('1.20e-7','1.2e-7','0.00E+00'),('−2.50','-2.5','0.00')]:
        assert cells[label]['x:num']==value,(name,label)
        assert 'mso-number-format:"'+fmt+'"' in cells[label]['style'],(name,label,'lost numeric format')
        assert 'text-align: left' in cells[label]['style']
    for label in ['0012','1234567890123456','=1+1']:
        assert cells[label]['x:str']==label and 'x:num' not in cells[label]
        assert 'mso-number-format:"\\@"' in cells[label]['style']
    assert 'font-size: 10pt' in cells['Plain heading']['style']
    assert 'text-decoration:underline' in cells['Plain heading']['style']
    assert 'font-size: 18pt' in cells['Custom cell']['style']
    assert 'border-bottom:2.25pt dashed rgb(0, 0, 204)' in cells['Custom cell']['style']
    assert any('220px' in c.get('style','') for c in parsed.cols), 'Explicit column width lost'
print('PASS: both Office copy paths retain number precision, percentages/exponents and text identifiers with literal Excel format hints, original alignment and column widths')
