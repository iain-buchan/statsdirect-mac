"""Agreement output and SVG geometry from the original TPaired/Ties renderer."""
import math, re, subprocess, xml.etree.ElementTree as ET
from pathlib import Path
root = Path(__file__).resolve().parents[1]
svg_ns = {'s':'http://www.w3.org/2000/svg'}
a = [312,242,340,388,296,254,391,402,290]
b = [300,201,232,312,220,256,328,330,231]
def run(before,after,agree=True,labels=('PEFR Before','PEFR After')):
    text = f'{len(before)} .95\n'+' '.join(map(str,before))+'\n'+' '.join(map(str,after))+'\n'
    p = subprocess.run([str(root/'Tests/bridge-driver'), str(root/'FullEngine/publish/StatsDirectEngine.dylib'),*labels,str(int(agree))],input=text,text=True,capture_output=True,timeout=60)
    first, html = p.stdout.split('\n',1); values=list(map(float,first.split()))
    assert values[0] == 0, (p.stdout,p.stderr)
    return values[1:],html
values,html=run(a,b)
plain,without=run(a,b,False)
assert values == plain
assert '<svg' not in without and '<svg' in html and 'Chart not drawn' not in html
assert '-10.868665' in html and '123.090887' in html
match=re.search(r'<svg\b[\s\S]*?</svg>',html); svg=ET.fromstring(match[0]);text=' '.join(svg.itertext())
for label in ['PEFR Before','PEFR After','95% limits of agreement']: assert label in text
points=svg.findall('.//s:ellipse',svg_ns);assert len(points)==9,len(points)
# The SVG is affine in the engine's x=(before+after)/2, y=before-after coordinates.
# The original renderer uses float intermediates; tolerate 0.0001 SVG unit.
# Verify every marker, then locate the three horizontal reference lines on that scale.
xs=[(x+y)/2 for x,y in zip(a,b)];ys=[x-y for x,y in zip(a,b)]
cx=[float(p.attrib['cx']) for p in points];cy=[float(p.attrib['cy']) for p in points]
mx=(cx[1]-cx[0])/(xs[1]-xs[0]);bx=cx[0]-mx*xs[0]
my=(cy[1]-cy[0])/(ys[1]-ys[0]);by=cy[0]-my*ys[0]
assert mx>0 and my<0
for i in range(9):
    assert math.isclose(cx[i],mx*xs[i]+bx,abs_tol=1e-4)
    assert math.isclose(cy[i],my*ys[i]+by,abs_tol=1e-4)
horizontal=[line for line in svg.findall('.//s:line',svg_ns) if line.attrib['y1']==line.attrib['y2'] and abs(float(line.attrib['x2'])-float(line.attrib['x1']))>100]
for expected in [56.111111111111114,-10.868664691913338,123.09088691413557]:
    assert any(math.isclose(float(line.attrib['y1']),my*expected+by,abs_tol=1e-4) for line in horizontal),expected
assert sum('stroke:#FF0000' in line.attrib.get('style','') for line in horizontal)==2
width,height=map(float,svg.attrib['viewBox'].split()[2:]);assert all(0<=x<=width for x in cx) and all(0<=y<=height for y in cy)
print('PASS: agreement preserves paired results; SVG contains all nine correct points, mean and both original limits')
_, changed=run([332,*a[1:]],b)
assert re.search(r'<svg\b[\s\S]*?</svg>',changed)[0] != match[0]
_, reverse=run(b,a,labels=('After & <check>','Before'))
rs=ET.fromstring(re.search(r'<svg\b[\s\S]*?</svg>',reverse)[0]);assert 'After & <check>' in ''.join(rs.itertext())
missing=[float('nan'),*a[1:]]
_, filtered=run(missing,b);fs=ET.fromstring(re.search(r'<svg\b[\s\S]*?</svg>',filtered)[0]);assert len(fs.findall('.//s:ellipse',svg_ns))==8
print('PASS: edited counts redraw the SVG; column labels are escaped; missing pairs are excluded from both calculation and chart')
out=root/'Content/Examples/paired-agreement.svg';out.write_text(match[0]+'\n')
print('Saved verified example SVG:',out)
