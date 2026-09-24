"""Verify Windows-compatible CI defaults and the single Analysis Options form."""
import json
import xml.etree.ElementTree as ET
from test_menu import Session, columns, ROOT

DEFAULTS={'use-default-ci':True,'default-ci':'95','selectGroupsByIdentifier':False,'decp':'6','pdecp':'4','use-scientific-notation-for-small-p-values':False}
s=Session()
def advance(id,state,value):
 result=s.request(action='answer',id=id,token=state['token'],value=value)
 assert not result.get('error'),result
 return s.wait(id)
def options(preferences=None):
 id,state=s.start('AnalysisOptions',preferences)
 assert state['prompt']['kind']=='settings',state
 fields=state['prompt']['fields']
 assert len(fields)==6 and next(f for f in fields if f['name']=='selectGroupsByIdentifier')['disabled']
 return id,state,{f['name']:f['defaultValue'] for f in fields}
def save(value):
 id,state,_=options();state=advance(id,state,value)
 assert state['state']=='complete' and state['analysisOptions']==value,state
 s.close(id)
def paired(id=None,state=None,expected=95,manual=None):
 if id is None:id,state=s.start('TPaired')
 assert state['prompt']['name']=='data'
 state=advance(id,state,columns([10,20,30,40],[8,17,25,32]))
 if manual is not None:
  assert state['prompt']['kind']=='confidence',state
  state=advance(id,state,manual)
 assert state['prompt']['name']=='doAgreement',state
 state=advance(id,state,False)
 assert state['state']=='complete',state
 assert state['values']['pc']==expected,state['values']
 assert next(h['value'] for h in state['history'] if h['name']=='gamma')==expected
 s.close(id)
 return state
try:
 id,state,defaults=options();assert defaults==DEFAULTS
 xml=ET.parse(ROOT/'FullEngine/Upstream/StatsDirectUI/Assets/Operations/AnalysisOptions.xml')
 ns={'s':'http://www.statsdirect.com/schemas/Operation.xsd'}
 names=[p.findtext('s:name',namespaces=ns) for p in xml.findall('.//s:parameters/*',ns)]
 assert [f['name'] for f in state['prompt']['fields']]==names
 invalid=advance(id,state,{**defaults,'decp':'99'})
 assert invalid['state']=='input' and invalid['prompt']['error']
 s.close(id)
 id,state,current=options();assert current==DEFAULTS;s.close(id)
 paired()
 print('PASS one form matches all Windows Analysis Options; invalid/cancelled edits do not change defaults')
 pending,state=s.start('TPaired')
 changed={**DEFAULTS,'default-ci':'90','decp':'5','pdecp':'6','use-scientific-notation-for-small-p-values':True}
 save(changed)
 id,current,values=options();assert values==changed;s.close(id)
 paired(pending,state,95)
 paired(expected=90)
 print('PASS saved 90% default is automatic, recorded in the report, and leaves an already-open 95% analysis unchanged')
 save({**changed,'use-default-ci':False})
 paired(expected=99,manual=99)
 save(DEFAULTS)
 print('PASS disabling automatic confidence restores the per-analysis question')
 id,state=s.start('Quantile')
 # This method explicitly forbids defaulting its confidence interval in Windows.
 if state['prompt']['kind']=='grid':state=advance(id,state,columns([1,2,3,4,5,6,7,8,9,10]))
 assert state['state']=='input' and state['prompt']['kind']=='confidence',state
 s.close(id)
 print('PASS operation-specific non-defaultable confidence still asks for input')
 # Simulate values supplied by native persistent settings to a fresh engine process.
 second=Session()
 try:
  id,state=second.start('AnalysisOptions',changed)
  assert {f['name']:f['defaultValue'] for f in state['prompt']['fields']}==changed
  second.close(id)
  result=second.run('TPaired',{'data':columns([10,20,30,40],[8,17,25,32])},changed)
  assert result['values']['pc']==90
 finally:second.finish()
 print('PASS native saved defaults restore in a fresh engine process')
finally:s.finish()
