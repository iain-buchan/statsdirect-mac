"""Additional complete menu paths and branch choices, through the real C ABI."""
import json, math
from test_menu import Session, ROOT
from form_branch_cases import CASES, VARIANTS
s=Session();results=[]
try:
 for name,op,answers in [(op,op,a) for op,a in CASES.items()]+[(op+'/'+label,op,{**CASES[op],**changes}) for op,label,changes in VARIANTS]:
  try:
   result=s.run(op,answers)
   assert result['html'] or result['frames'],name
   assert 'Error rendering' not in result['html'],name
   if op=='UniversalAgreement':
    suggestions=[p['operation'] for p in result['suggestions']]
    assert ('UniversalAgreementSimulateExactP' in suggestions)==(answers['reference']==[]),suggestions
    if answers['reference']:assert 'Observer '+('A' if answers['reference']==[0] else 'Z') in result['html']
   results.append({'case':name,'operation':op,'status':'pass'});print('PASS',name,flush=True)
  except Exception as e:
   results.append({'case':name,'operation':op,'status':'fail','error':str(e)});print('FAIL',name,str(e)[:500],flush=True)
 (ROOT/'.build/form-branches.json').write_text(json.dumps(results,indent=2)+'\n')
 assert all(r['status']=='pass' for r in results),[r['case'] for r in results if r['status']=='fail']
 # Refitting must rebuild the engine's stripped working context from the original
 # data, and must not mutate the parent fit held by another open Mac form.
 parent=s.run('LinearizedEstimates',{**CASES['LinearizedEstimates'],'model':'0'},keep=True)
 before=s.run('LinearizedEstimateInterpolation',{'newx':2.5},parent=parent['id'])
 for model in ('1','2','0'):
  id,prompt=s.start('LinearizedEstimatesWithModel',parent=parent['id'])
  assert prompt['prompt']['name']=='model' and prompt['prompt']['defaultValue']=='0',prompt
  s.close(id)
  changed=s.run('LinearizedEstimatesWithModel',{'model':model},parent=parent['id'])
  direct=s.run('LinearizedEstimates',{**CASES['LinearizedEstimates'],'model':model})
  for key in ('a','b','r','r2','ste'):assert math.isclose(changed['values'][key],direct['values'][key],rel_tol=1e-12,abs_tol=1e-12),(model,key)
 after=s.run('LinearizedEstimateInterpolation',{'newx':2.5},parent=parent['id'])
 assert before['values']==after['values']
 s.close(parent['id'])
 print('PASS linearized model changes match fresh fits for all three models and leave parent interpolation unchanged')
finally:s.finish()
