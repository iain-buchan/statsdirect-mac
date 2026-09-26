"""Selected worksheet rectangle -> actual form payload -> original engine and R."""
import json, os, subprocess, math, xml.etree.ElementTree as ET
from pathlib import Path
from test_menu import Session
ROOT=Path(__file__).resolve().parents[1]
node=os.environ.get('NODE','node')
payload=subprocess.check_output([node,'--input-type=module','-e','''
import {initialGrid,enteredInput} from './Grid/operation-data.mjs';
const source={name:'Selected C5:D6',firstRow:1,rows:20,columns:['A','B','C','D'],selection:[2,3],range:{first:5,last:6},cells:[{col:0,row:0,text:'999'},{col:2,row:4,text:'12'},{col:3,row:4,text:'3'},{col:2,row:5,text:'8'},{col:3,row:5,text:'17'}]};
const prompt={screen:true,rows:2,fixedRows:true,minColumns:2,maxColumns:2,labels:['Present','Absent']};
const g=initialGrid(prompt,source);
console.log(JSON.stringify(enteredInput(g.matrix,g.titles,true)));
'''],cwd=ROOT,text=True)
s=Session()
try:
 result=s.run('Chi2by2',dict(scrap=json.loads(payload),study_type='neither',doFisher=False))
 values=result['values']
 assert [values[k] for k in ['tab3_a1','tab3_b1','tab3_a2','tab3_b2']]==[12,3,8,17]
 r=subprocess.check_output(['/Library/Frameworks/R.framework/Resources/bin/Rscript','--vanilla','-e', 'a<-chisq.test(matrix(c(12,3,8,17),nrow=2,byrow=TRUE),correct=FALSE);cat(sprintf("%.17g",c(a$statistic,a$p.value)),sep=",")'],text=True)
 for actual,expected in zip([values['chi'],values['chi_p']],map(float,r.split(','))):assert math.isclose(actual,expected,rel_tol=1e-12)
 print('PASS: selected C5:D6 -> embedded grid -> original engine matches R, with unrelated data excluded')
finally:s.finish()
ns={'s':'http://www.statsdirect.com/schemas/Operation.xsd'}
for name,entry in json.loads((ROOT/'Content/analysis-menu.json').read_text())['operations'].items():
 definition=ET.parse(ROOT/'FullEngine/Upstream/StatsDirectUI/Assets/Operations'/f'{name}.xml')
 assert entry['instant']==any(e.text==name for e in definition.findall('s:suggested-operations/s:suggested-operation',ns)),name
print('PASS: instant-answer classification matches Windows for every menu operation')
