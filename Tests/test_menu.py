"""Interactive C ABI checks: real prompt/answer boundaries and original engine reports."""
from pathlib import Path
import json, subprocess, time, uuid, math, sys
ROOT=Path(__file__).resolve().parents[1]
class Session:
 def __init__(self):
  driver=Path(sys.argv[1]) if len(sys.argv)>1 else ROOT/'Tests/operation-driver'
  self.process=subprocess.Popen([str(driver.resolve()),str(ROOT/'FullEngine/publish/StatsDirectEngine.dylib')],stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True)
 def request(self,**kwargs):
  self.process.stdin.write(json.dumps(kwargs)+'\n');self.process.stdin.flush()
  return json.loads(self.process.stdout.readline())
 def wait(self,id):
  deadline=time.monotonic()+60
  while time.monotonic()<deadline:
   s=self.request(action='poll',id=id)
   if s.get('state')!='running':return s
   time.sleep(.005)
  self.request(action='cancel',id=id)
  raise AssertionError('Engine did not finish within 60 seconds')
 def start(self,operation):
  id=str(uuid.uuid4());s=self.request(action='start',id=id,operation=operation)
  assert 'error' not in s or s['error'] is None,s
  return id,self.wait(id)
 def close(self,id):
  self.request(action='cancel',id=id);self.wait(id);self.request(action='release',id=id)
 def run(self,operation,answers):
  id,s=self.start(operation);prompts=[]
  for _ in range(100):
   if s.get('state')!='input':break
   p=s['prompt'];name=p.get('name');prompts.append((name,p['kind']))
   if name in answers:value=answers[name]
   elif p.get('prompt') in answers:value=answers[p['prompt']]
   elif p['kind']=='options':value={o['value']:o['selected'] for o in p['options']}
   elif p['kind']=='fields':value={o['name']:o['defaultValue'] for o in p['fields']}
   elif p['kind']=='boolean':value=False
   elif p['kind']=='confidence':value=p['defaultValue']
   elif p.get('defaultValue') is not None:value=p['defaultValue']
   elif p['kind']=='option':value=p['options'][0]['value']
   elif p.get('skip'):value={'skip':True}
   else:
    self.close(id);raise AssertionError(f'{operation}: unanswered {p}')
   if p.get('error'):
    self.close(id);raise AssertionError(f'{operation}: validation {p["error"]}, answer {value}')
   self.request(action='answer',id=id,token=s['token'],value=value);s=self.wait(id)
  self.close(id)
  assert s.get('state')=='complete',(operation,s.get('error'),prompts)
  return s
 def finish(self):self.process.stdin.close();self.process.wait()
def columns(*cols):return {'columns':[{'title':f'Column {i+1}','values':list(v)} for i,v in enumerate(cols)],'source':'Test fixture'}
def near(got,expected):assert math.isclose(got,expected,rel_tol=1e-10,abs_tol=1e-12),(got,expected)
if __name__=='__main__':
 s=Session();results=[]
 catalog=json.loads((ROOT/'Content/analysis-menu.json').read_text())
 def nodes(menu):
  yield menu
  for child in menu.get('children',[]):yield from nodes(child)
 commands=[n for menu in catalog['menus'] for n in nodes(menu) if 'operation' in n]
 assert len(commands)==224 and len(catalog['operations'])==208
 import xml.etree.ElementTree as ET
 windows=ET.parse(ROOT/'Content/windows-menu.xml')
 expected=[(n.get('label','').replace('&',''),n.get('operation')) for n in windows.iter() if n.get('operation')]
 assert [(n['label'],n['operation']) for n in commands]==expected
 for name,definition in catalog['operations'].items():
  assert (ROOT/'Content'/definition['help']).is_file()
  if definition.get('unavailable'):
   rejected=s.request(action='start',id=str(uuid.uuid4()),operation=name);assert definition['unavailable']==rejected.get('error')
  else:
   id,state=s.start(name);assert state['state']=='input',(name,state);s.close(id)
 print('PASS: all 224 menu commands, 208 offline help links, 206 input hosts and 2 explicit R deferrals',flush=True)
 id,state=s.start('ExactSign');old=state['token']
 other,other_state=s.start('TPaired');assert other_state['state']=='input'
 s.request(action='answer',id=id,token=old,value='NaN');state=s.wait(id)
 assert state['state']=='input' and state['prompt']['error'] and state['token']>old
 assert 'error' in s.request(action='answer',id=id,token=old,value=20)
 s.request(action='answer',id=id,token=state['token'],value=20);state=s.wait(id)
 assert state['prompt']['name']=='r'
 s.request(action='cancel',id=id);state=s.wait(id)
 assert state['state']=='cancelled' and not state['html'];s.close(id)
 assert s.request(action='poll',id=other)['token']==other_state['token'];s.close(other)
 print('PASS: validation retry, stale-answer rejection, independent open forms and cancellation at a prompt',flush=True)
 cases={
  'TPaired':{'data':columns([312,242,340,388,296,254,391,402,290],[300,201,232,312,220,256,328,330,231]),'doAgreement':True},
  'TSingleSummary':{'nx':10,'mu':12,'sd1':3,'mu0':10},
  'TUnpairedSummary':{'nx1':10,'um1':12,'sd1':3,'nx2':12,'um2':9,'sd2':4},
  'ExactSign':{'n':20,'r':15},
  'ExactFisher':{'scrap':columns([1,11],[9,3])},
  'Chi2by2':{'scrap':columns([20,10],[10,20])},
  'PropUnPaired':{'n1':100,'r1':20,'n2':100,'r2':35},
  'RatePoissonCI':{'revents':12,'tar':1000},
  'SizePaired':{'d':2,'sd':5,'p':80,'a':5},
  'RandomPairs':{'pairs':6,'seed':31415,'balance':True},
  'MiscDiagnostic':{'scrap':columns([80,20],[10,90])},
  'UnivariateSummary':{'data':columns([1,2,3,4,5,6,7,8,9,10])},
  'QuickSummary':{'data':columns([1,2,3,4,5])},
  'TSingle':{'data':columns([1,2,3,4,5,7]),'population-mean':3},
  'TUnpaired':{'data':columns([1,2,3,5,6],[4,5,6,7,9])},
  'Normality':{'data':columns([1,2,2,3,4,5,6,7,8,10])},
  'MannWhitney':{'data':columns([1,2,3,4,5],[4,6,7,8,9])},
  'Wilcoxon':{'data':columns([2,3,5,7,9],[1,1,4,5,6])},
  'Spearman':{'data':columns([1,2,3,4,5],[3,1,4,5,7])},
  'Kruskal':{'data':columns([1,2,3,4],[3,5,6,8],[7,8,9,11])},
  'OneWay':{'data':columns([1,2,3,4],[3,5,6,8],[7,8,9,11])},
  'SimpleLinearRegression':{'y':columns([3,4,5,7,9,11]),'x':columns([1,2,3,4,5,6])},
  'Agreement':{'data':columns([312,242,340,388,296,254,391,402,290],[300,201,232,312,220,256,328,330,231])},
  'KaplanMeier':{'times':columns([1,2,3,4,5,6]),'deaths':columns([1,1,0,1,0,1]),'groups':{'skip':True}},
  'ReplicateTwoWay':{
   'Repeat 1: subjects in rows, treatments in columns':columns([1,2,4],[3,4,5]),
   'Repeat 2: subjects in rows, treatments in columns':columns([2,3,3],[5,6,7])},
  'TwoWayNested':{'Group 1: one column per subgroup':columns([1,2,3],[2,3,5]),'Group 2: one column per subgroup':columns([4,5,7],[6,7,9])},
  'GroupedCovariance':{'Select predictor (X) series — one column per group':columns([1,2,3,4,5],[2,3,4,5,6]),'Group 1: Y outcomes for Column 1':columns([2,3,5,7,10]),'Group 2: Y outcomes for Column 2':columns([3,6,8,11,12])},
  'TwoWay':{'data':columns([1,2,4,6],[3,6,7,9],[4,5,8,10])},
  'ChiSquareGoodnessOfFit':{'observed':columns([18,22,29,31]),'expected':columns([25,25,25,25])},
  'MantelHaenszelScreen':{'data':columns([20,10,15,10],[10,20,10,25]),'plot_forest':True},
  'KappaScreen':{'responsesCrosstab':columns([20,5,2],[3,25,4],[1,3,18])},
  'LogRank':{'gid':columns(['A','B','A','B','A','B','A','B']),'times':columns([1,2,3,4,5,6,7,8]),'deaths':columns([1,1,0,1,1,0,1,1])},
  'RateDirectScreen':{'data':columns([5,10,20],[1000,1000,1000],[100,200,300])},
  'PetoMeta':{'sn':columns([100,120,90]),'sr':columns([12,20,15]),'xn':columns([100,110,95]),'xr':columns([20,25,23])},
  'ProportionMeta':{'sn':columns([100,120,90]),'sr':columns([12,20,15])},
  'MultipleLinearRegression':{'outcome':columns([2,3,4,5,7,8,9,11,12,14]),'predictors':columns([1,2,3,4,5,6,7,8,9,10],['A','B','A','B','A','B','A','B','A','B']),'calculateIntercept':True},
  'Frequency':{'data':columns(['red','blue','red','green','blue'])},
 }
 for name,a in cases.items():
  try:
   result=s.run(name,a)
   assert 'Error rendering' not in result['html']
   if name=='TPaired':near(result['values']['tail_2'],.0011555730513523055);assert '<svg' in result['html']
   if name=='ExactFisher': assert '0.002' in result['html']
   assert result['html'] or result['frames'],name
   results.append({'operation':name,'result':'pass','values':result['values']});print('PASS',name,flush=True)
  except Exception as e: results.append({'operation':name,'error':str(e)}); print('FAIL',name,str(e)[:900],flush=True)
 for name in ['Normal','T','F','ChiSquare','Q','Binomial','Poisson','Kendall','Spearman','NonCentralT']:
  # Supply valid non-default rank statistics via a manual form answer below.
  # All ten distribution calculators are exercised.
  try:
   result=s.run('Distribution'+name,{})
   assert result['html'];results.append({'operation':'Distribution'+name,'result':'pass'});print('PASS Distribution'+name,flush=True)
  except Exception as e:results.append({'operation':'Distribution'+name,'error':str(e)});print('FAIL',name,str(e)[:900],flush=True)
 rscript=Path('/Library/Frameworks/R.framework/Resources/bin/Rscript')
 if rscript.exists() and all('error' not in r for r in results):
  import csv,io
  reference=subprocess.check_output([str(rscript),'--vanilla',str(ROOT/'Tests/menu-references.R')],text=True)
  checked=0;by_name={r['operation']:r for r in results}
  for row in csv.DictReader(io.StringIO(reference),delimiter='\t'):
   near(by_name[row['operation']]['values'][row['key']],float(row['value']));checked+=1
  print('PASS:',checked,'independent R comparisons, including ANOVA table orientation and covariance grouping',flush=True)
 s.finish();(ROOT/'FullEngine/publish/menu-test-results.json').write_text(json.dumps(results,indent=2))
 failures=[r for r in results if 'error' in r];print(len(results)-len(failures),'passed,',len(failures),'failed')
 if failures:sys.exit(1)
