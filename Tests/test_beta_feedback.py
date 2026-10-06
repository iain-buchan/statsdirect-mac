"""Regression cases from the October Mac beta feedback, through the real engine bridge."""
from test_menu import Session, columns
s=Session()
try:
 for op,param,bad,good in [('RndPoisson','xm',-1,2),('RndNormal','sd',-1,1),('RndBeta','a',0,2),('RndGeometric','p',0,.3)]:
  id,state=s.start(op)
  while state['state']=='input' and state['prompt']['name']!=param:
   p=state['prompt'];value=2 if p['name'] in ['cols','rows'] else p['defaultValue']
   s.request(action='answer',id=id,token=state['token'],value=value);state=s.wait(id)
  assert state['prompt']['name']==param
  s.request(action='answer',id=id,token=state['token'],value=bad);state=s.wait(id)
  assert state['state']=='input' and state['prompt']['error'],(op,state)
  s.request(action='answer',id=id,token=state['token'],value=good);state=s.wait(id)
  assert not state.get('prompt',{}).get('error'),(op,state)
  s.close(id)
 print('PASS: invalid random-number arguments stay in a correctable input form')
 out=s.run('SearchAndReplaceAdvanced',{'search-type':'text','search-rule':'equal','search-expression':'old','action':'count','data':columns(['old','old','new'])})
 assert '2 cells match' in out['html'],out
 print('PASS: advanced search count uses the Mac information host')
 out=s.run('SearchAndReplace',{'search-expression':'old','replace-expression':'new','data':columns(['old','old','new'])})
 assert [c['text'] for c in out['frames'][0]['cells'] if c['row']>0]==['new','new','new'],out
 print('PASS: basic search uses only find, replace and data prompts')
 out=s.run('FillSeries',{'rows':5,'start':1,'step':1,'expression':'X+1','new_column_name':'Sequence','title':'Sequence'})
 assert out['frames'][0]['headerRow'] is True
 print('PASS: generated worksheet declares its heading row')
 defaults=None
 for operation in ['MetaCalculationOptions','MetaPlotOptions']:
  id,state=s.start(operation,defaults)
  assert state['prompt']['kind']=='settings'
  fields=state['prompt']['fields'];values={f['name']:f['defaultValue'] for f in fields}
  if operation=='MetaCalculationOptions':values.update({'meta-exact':False,'meta-delay':True,'meta-cc':'0.01'})
  else:values.update({'meta-plot-ci':False,'meta-plot-method':'4'})
  s.request(action='answer',id=id,token=state['token'],value=values);state=s.wait(id)
  assert state['state']=='complete',state
  defaults=state['analysisOptions'];s.close(id)
 assert defaults['meta-cc']==.01 and defaults['meta-plot-method']==4 and defaults['meta-plot-ci'] is False
 id,state=s.start('MetaCalculationOptions',defaults)
 assert next(f['defaultValue'] for f in state['prompt']['fields'] if f['name']=='meta-cc')=='0.01';s.close(id)
 print('PASS: meta-analysis options use complete forms and round-trip saved defaults')
 id,state=s.start('HistogramPlot');s.request(action='answer',id=id,token=state['token'],value=columns([1,2,2,3,4,5,6,7,8,9,10]));state=s.wait(id)
 assert state['prompt']['kind']=='fields'
 values={f['name']:f['defaultValue'] for f in state['prompt']['fields']};assert 'bins' in values
 values['bins']=4;s.request(action='answer',id=id,token=state['token'],value=values);state=s.wait(id)
 assert state['state']=='complete' and '<svg' in state['html'];s.close(id)
 print('PASS: histogram exposes and applies explicit bin count')
finally:s.finish()
