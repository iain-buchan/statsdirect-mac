"""Check the actual Word package, not merely that export returned ZIP bytes."""
from pathlib import Path
from zipfile import ZipFile
from xml.etree import ElementTree as E
import sys
folder=Path(sys.argv[1])
ns={'w':'http://schemas.openxmlformats.org/wordprocessingml/2006/main'}
key='{'+ns['w']+'}val'

def package(name):
    with ZipFile(folder/(name+'.docx')) as archive:
        return E.fromstring(archive.read('word/document.xml')),archive.namelist()

def run_for(document,text):
    return next(run for run in document.findall('.//w:r',ns) if text in ''.join(run.itertext()))

edited,files=package('edited-report')
run=run_for(edited,'Edited interpretation')
assert run.find('w:rPr/w:b',ns) is not None and run.find('w:rPr/w:u',ns) is not None
aligned=next(p for p in edited.findall('.//w:p',ns) if 'Aligned note' in ''.join(p.itertext()))
assert aligned.find('w:pPr/w:jc',ns).get(key)=='center'
heading=next(p for p in edited.findall('.//w:p',ns) if 'Editable heading' in ''.join(p.itertext()))
assert heading.find('w:pPr/w:pStyle',ns).get(key)=='Heading2'
assert next(p for p in edited.findall('.//w:p',ns) if 'Interpretation bullet' in ''.join(p.itertext())).find('w:pPr/w:numPr',ns) is not None
assert next(p for p in edited.findall('.//w:p',ns) if 'Interpretation step' in ''.join(p.itertext())).find('w:pPr/w:numPr',ns) is not None
assert len(edited.findall('.//w:tbl',ns))==4
assert sum(name.endswith('.svg') for name in files)==1
legacy,files=package('legacy-converted')
for text,tag in [('Legacy statistical report','b'),('Paired measurements','i'),('Reviewed','u')]:
    style=run_for(legacy,text).find('w:rPr/w:'+tag,ns)
    assert style is not None and style.get(key)!='false'
assert len(legacy.findall('.//w:tbl',ns))==1
assert sum(name.endswith('.svg') for name in files)==2
assert sum(name.endswith('.png') for name in files)>=2
assert '12.5' in ''.join(legacy.itertext()) and '!!help!' not in ''.join(legacy.itertext())
print('PASS: DOCX bold/underline/italic, alignment, headings, lists, tables and SVG charts with PNG fallbacks')
layout,_=package('legacy-layout')
table=layout.find('.//w:tbl',ns)
assert table.find('w:tr/w:tc[2]/w:tcPr/w:gridSpan',ns).get(key)=='3'
assert run_for(layout,'Body at').find('w:rPr/w:sz',ns).get(key)=='24'
assert run_for(layout,'12.5').find('w:rPr/w:sz',ns).get(key)=='21'
print('PASS: DOCX retains the restored spanning header and readable body/table font sizes')

font=run_for(edited,'Formatting sample').find('w:rPr',ns)
assert font.find('w:rFonts',ns).get('{'+ns['w']+'}ascii')=='Times New Roman'
assert font.find('w:sz',ns).get(key)=='37'
assert font.find('w:color',ns).get(key)=='C00000'
assert font.find('w:shd',ns).get('{'+ns['w']+'}fill')=='FFFF00'
assert font.find('w:strike',ns) is not None and font.find('w:i',ns) is not None
paragraph=next(p for p in edited.findall('.//w:p',ns) if 'Formatting sample' in ''.join(p.itertext()))
assert paragraph.find('w:pPr/w:spacing',ns).get('{'+ns['w']+'}line')=='480'
for text,value in [('Superscript sample','superscript'),('Subscript sample','subscript')]:
    assert run_for(edited,text).find('w:rPr/w:vertAlign',ns).get(key)==value
assert run_for(edited,'Larger typing').find('w:rPr/w:sz',ns).get(key)=='40'
cleared_bold=run_for(edited,'Clear sample').find('w:rPr/w:b',ns)
assert cleared_bold is None or cleared_bold.get(key) in {'false','0','off'}
print('PASS: DOCX exact point sizes, fonts, colours, highlighting, strike, super/subscript, line spacing and true editable lists')

indented=next(p for p in edited.findall('.//w:p',ns) if 'Indented interpretation' in ''.join(p.itertext()))
assert int(indented.find('w:pPr/w:ind',ns).get('{'+ns['w']+'}left'))>=600
nested=next(p for p in edited.findall('.//w:p',ns) if 'Nested bullet' in ''.join(p.itertext()))
assert nested.find('w:pPr/w:numPr/w:ilvl',ns).get(key)=='1'
print('PASS: DOCX preserves paragraph indentation and nested lists')

original_svg_extent=None
for name in ['resized-report','resized-reopened-report']:
    resized,_=package(name)
    drawing='{http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing}'
    pictures=resized.findall('.//'+drawing+'inline')
    extents=[(p.find(drawing+'docPr').get('descr'),p.find(drawing+'extent')) for p in pictures]
    raster=next(e for d,e in extents if d=='Raster resize check')
    assert int(raster.get('cx'))==200*9525 and int(raster.get('cy'))==100*9525
    # The other two pictures are SVG: the engine chart resized to 320px and the LOESS chart R drew at six by four inches (432 by 288 points).
    vectors=sorted((e for d,e in extents if d!='Raster resize check'),key=lambda e:int(e.get('cx')))
    assert len(pictures)==3 and [int(e.get('cx')) for e in vectors]==[320*9525,576*9525] and int(vectors[1].get('cy'))==384*9525, (name,[(d,e.attrib) for d,e in extents])
    svg_extent=vectors[0].attrib
    if original_svg_extent is None: original_svg_extent=svg_extent
    else: assert svg_extent==original_svg_extent, 'HTML reopening changed the SVG aspect ratio'
print('PASS: DOCX uses the selected SVG/raster sizes and retains the LOESS chart before and after HTML reopen')

moved,files=package('moved-report')
assert sum(name.endswith('.svg') for name in files)==1
assert len(moved.findall('.//w:tbl',ns))==1
assert moved.find('.//w:tbl/w:tr/w:tc/w:tcPr/w:gridSpan',ns).get(key)=='2'
assert 'formatted finding' in ''.join(moved.itertext()) and 'Unselected ending' in ''.join(moved.itertext())
extent=moved.find('.//{http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing}extent')
assert int(extent.get('cx'))==240*9525
assert run_for(moved,'formatted finding').find('w:rPr/w:rFonts',ns).get('{'+ns['w']+'}ascii')=='Times New Roman'
print('PASS: moved content exports with its font, merged table and 240px vector chart intact')

wrappers=['main','header','footer','aside','nav','figure','figcaption','address','report-output']
for name in ['semantic-containers','semantic-containers-reopened']:
    semantic,files=package(name)
    tables=semantic.findall('.//w:tbl',ns)
    drawings=semantic.findall('.//{http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing}inline')
    assert len(tables)==len(wrappers), (name,'lost semantic-container tables',len(tables))
    assert len(drawings)==len(wrappers), (name,'lost semantic-container charts',len(drawings))
    assert sum(path.endswith('.svg') for path in files)==len(wrappers)
    assert sum(path.endswith('.png') for path in files)==len(wrappers)
    paragraphs=semantic.findall('.//w:p',ns)
    texts=[''.join(p.itertext()) for p in paragraphs]
    for tag,table in zip(wrappers,tables):
        assert tag+' merged heading' in ''.join(table.itertext())
        assert table.find('w:tr/w:tc/w:tcPr/w:gridSpan',ns).get(key)=='2'
        assert table.find('w:tr[2]/w:tc/w:tcPr/w:vMerge',ns).get(key)=='restart'
        assert table.find('w:tr[3]/w:tc/w:tcPr/w:vMerge',ns).get(key)=='continue'
        heading=next(p for p in paragraphs if ''.join(p.itertext())==tag+' heading')
        assert heading.find('w:pPr/w:pStyle',ns).get(key)=='Heading2'
        step=next(p for p in paragraphs if ''.join(p.itertext())==tag+' first step')
        assert step.find('w:pPr/w:numPr',ns) is not None
        assert texts.index(tag+' before bold and help link.')<texts.index(tag+' merged heading')<texts.index(tag+' first step')<texts.index(tag+' after')
    assert len(semantic.findall('.//w:hyperlink',ns))==len(wrappers)
print('PASS: DOCX semantic/custom containers preserve real tables and merges, SVG/PNG drawings, headings, lists, links and order, including after HTML import')

for name in ['stylesheet-report','stylesheet-reopened']:
    styled,files=package(name)
    for text,color in [('CSS confidence interval','0000FF'),('CSS P value','008000'),('CSS warning','FF0000')]:
        value=run_for(styled,text).find('w:rPr/w:color',ns)
        assert value is not None and value.get(key)==color, (name,text,'lost stylesheet colour')
    for text,font,size in [('New report default font','Arial',None),('Custom Georgia face','Georgia','27'),('Inline font override','Times New Roman','37')]:
        properties=run_for(styled,text).find('w:rPr',ns)
        assert properties.find('w:rFonts',ns).get('{'+ns['w']+'}ascii')==font,(name,text)
        if size: assert properties.find('w:sz',ns).get(key)==size,(name,text)
    with ZipFile(folder/(name+'.docx')) as archive:
        chart=archive.read(next(path for path in files if path.endswith('.svg'))).decode()
        assert 'Georgia' in chart and 'Custom chart face' in chart
print('PASS: fresh and reopened DOCX preserve stylesheet colours, Arial defaults, custom font/point-size overrides and the existing chart font')

deleted,files=package('selection-deleted')
text=''.join(deleted.itertext())
assert 'First result' in text and 'Last finding retained' in text and 'Keep these notes' in text
assert 'Middle finding' not in text and 'Middle result' not in text
tables=deleted.findall('.//w:tbl',ns)
assert len(tables)==1 and tables[0].find('w:tr/w:tc/w:tcPr/w:gridSpan',ns).get(key)=='2'
assert sum(path.endswith('.svg') for path in files)==1
assert len(deleted.findall('.//{http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing}inline'))==2
print('PASS: DOCX omits the deleted result while preserving surviving text, notes, merged table and SVG/raster drawings')

# The focused presentation verifier also runs with the full native report suite.
import runpy
runpy.run_path(str(Path(__file__).with_name('verify-report-presentation.py')))
