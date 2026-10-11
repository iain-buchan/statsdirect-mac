"""Windows-style grouped prompts preserve the sequential engine's results."""
import json, time
from test_menu import Session, columns
from form_branch_cases import CASES, VARIANTS

class Forms(Session):
 def request(self, **request):
  if request.get('action') == 'start': request['interactiveForms'] = True
  return super().request(**request)

def answer(p, answers):
 name=p.get('name')
 if name in answers:return answers[name]
 if p.get('prompt') in answers:return answers[p['prompt']]
 if p['kind']=='options':return {o['value']:o['selected'] for o in p['options']}
 if p['kind'] in ('fields','settings'):return {o['name']:o['defaultValue'] for o in p['fields']}
 if p['kind']=='boolean':return False
 if p.get('defaultValue') is not None:return p['defaultValue']
 if p['kind']=='option':return p['options'][0]['value']
 if p.get('skip'):return {'skip':True}
 raise AssertionError(f'Unanswered {p}')

def run(s, op, answers):
 id,state=s.start(op); count=0
 try:
  for _ in range(200):
   if state['state']!='input':break
   p=state['prompt']; assert not p.get('error'),(op,p)
   if p['kind']=='form':
    count+=1
    # Preview until dependent fields have appeared; previews cannot run a
    # builtin, add history or publish a report.
    prior=len(state['history'])
    for _ in range(10):
     values={f['name']:answer(f,answers) for f in p['fields']}
     names=[f['name'] for f in p['fields']]
     s.request(action='answer',id=id,token=state['token'],value={'values':values,'preview':True})
     state=s.wait(id);p=state['prompt']
     assert state['state']=='input' and p['kind']=='form' and len(state['history'])==prior and not state.get('html'),(op,state)
     if names==[f['name'] for f in p['fields']]:break
    value={'values':{f['name']:answer(f,answers) for f in p['fields']}}
   else:value=answer(p,answers)
   s.request(action='answer',id=id,token=state['token'],value=value);state=s.wait(id)
  assert state['state']=='complete',(op,state.get('error'),state.get('prompt'))
  return state,count
 finally:s.close(id)

if __name__=='__main__':
 base=Session();grouped=Forms();results=[]
 cases=[(op,op,a) for op,a in CASES.items()]+[(op+'/'+label,op,{**CASES[op],**changes}) for op,label,changes in VARIANTS]
 cases += [('Chi2by2','Chi2by2',{'scrap':columns([12,3],[8,17]),'study_type':'neither','doFisher':True}),
  ('TUnpaired','TUnpaired',{'data':columns([1,3,4,7,8],[4,7,9,11,13])}),
  ('TPaired','TPaired',{'data':columns([1,3,4,7,8],[4,7,9,11,13]),'doAgreement':True})]
 try:
  catalog=json.loads((__import__('test_menu').ROOT/'Content/analysis-menu.json').read_text())
  for op,definition in catalog['operations'].items():
   if definition.get('unavailable'):continue
   id,state=grouped.start(op)
   try:assert state['state']=='input',(op,state)
   finally:grouped.close(id)
  print('PASS: all available commands open with Windows-style grouping',flush=True)
  for label,op,answers in cases:
   try:
    expected=base.run(op,answers);actual,count=run(grouped,op,answers)
    # This operation uses an unseeded Monte Carlo confidence interval.
    # Compare every deterministic output, and check both simulated bounds.
    stochastic={'elb_mc_lci','elb_mc_uci'} if op=='AbridgedLifetable' else set()
    assert {k:v for k,v in actual['values'].items() if k not in stochastic}=={k:v for k,v in expected['values'].items() if k not in stochastic},(label,'numeric outputs changed')
    if stochastic:assert 350<actual['values']['elb_mc_lci']<actual['values']['elb_mc_uci']<600
    assert actual['frames']==expected['frames'],(label,'worksheet output changed')
    if actual.get('record') or expected.get('record'):
     a,e=json.loads(actual['record']),json.loads(expected['record'])
     assert a.get('operation')==e.get('operation'),(label,'run record changed','operation')
     # The shared processor records defaults for disabled controls in combined
     # forms, just as it does on Windows. They must never displace an accepted
     # input or enable simulation; all enabled inputs still match exactly.
     actual_inputs=a.get('inputs',[]); expected_inputs=e.get('inputs',[])
     extras=[i for i in actual_inputs if i['name'] not in {j['name'] for j in expected_inputs}]
     if extras:
      assert op in ('Chi2byNLinearTrend','Chi2byNWithTrend','Crosstabs','ExactChiRbyC'),(label,extras)
      toggle='doExactP' if op.startswith('Chi2byN') else 'doMonteCarlo'
      assert any(i['name']==toggle and i['value'] is False for i in expected_inputs),(label,extras)
      assert {i['name'] for i in extras}=={'iterations','seed','ci'},(label,extras)
      assert next(i['value'] for i in extras if i['name']=='iterations')==1000000
      assert next(i['value'] for i in extras if i['name']=='ci')==0.99
      assert isinstance(next(i['value'] for i in extras if i['name']=='seed'),int)
     assert [i for i in actual_inputs if i not in extras]==expected_inputs,(label,'run record changed','inputs')
     parameters=dict(a.get('parameters',{}))
     for i in extras:
      assert parameters.pop(i['name'])==i['value'],(label,'inactive default differs from its input',i['name'])
     assert parameters==e.get('parameters',{}),(label,'run record changed','parameters')

    results.append(True);print('PASS',label,'grouped forms:',count,flush=True)
   except Exception as e:results.append(False);print('FAIL',label,str(e)[:1200],flush=True)
  assert all(results),f'{sum(not r for r in results)} / {len(results)} grouped workflows failed'
  print(f'PASS: {len(results)} grouped workflows match sequential engine results; previews leave history/output unchanged',flush=True)
 finally:base.finish();grouped.finish()
