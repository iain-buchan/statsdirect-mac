#!/usr/bin/python3
"""Report-assistant fixture: synthetic local protocol only, no account or network."""
import json, os, sys
from pathlib import Path
home=Path(os.environ['CODEX_HOME'])
assert home.name=='chatgpt-mock' and 'OPENAI_API_KEY' not in os.environ
signed=False
threads={}
pending={}
def send(value): print(json.dumps(value),flush=True)
def finish(thread,text):
 send({'method':'item/agentMessage/delta','params':{'threadId':thread,'turnId':'turn','itemId':'answer','delta':text}})
 send({'method':'turn/completed','params':{'threadId':thread,'turn':{'id':'turn','status':'completed'}}})
def tool(thread,name,args):
 ident=name+'-'+thread;pending[ident]=(thread,name)
 send({'id':ident,'method':'item/tool/call','params':{'threadId':thread,'turnId':'turn','callId':ident,'tool':name,'arguments':args}})
for line in sys.stdin:
 request=json.loads(line)
 with (home/'requests.jsonl').open('a') as f:f.write(json.dumps(request)+'\n')
 method=request.get('method');params=request.get('params',{})
 if method=='initialized':continue
 if method is None:
  thread,name=pending.pop(request['id']);assert request['result']['success'],request
  data=json.loads(request['result']['contentItems'][0]['text'])
  if name=='statsdirect_read_document':
   assert data==threads[thread]['report']
   tool(thread,'statsdirect_method_help',{'operation':'TPaired'})
  else:
   assert data['operation']=='TPaired' and 'paired' in data['text'].lower()
   finish(thread,'The mean paired difference is about 56.1. Interpret its confidence interval separately from the limits of agreement. Pairing comes from the study design. What difference would matter in practice?\n\n**Interpretation**\n\n| Estimate | Meaning |\n| --- | --- |\n| 56.1 | Mean difference |\n\nMean notation: $\\bar{x}$\n\nExample to review:\n```r\nx <- c(1, 2, 3)\nmean(x)\n```')
  continue
 result={}
 if method=='initialize':pass
 elif method=='account/read':result={'account':{'type':'chatgpt','email':'fixture@example.invalid','planType':'plus'} if signed else None}
 elif method=='account/login/start':signed=True;result={'loginId':'fixture','authUrl':'https://auth.openai.com/authorize?state=fixture'}
 elif method=='thread/start':
  assert params['serviceName']=='statsdirect-report-assistant'
  assert 'report interpretation and statistical methods assistant' in params['baseInstructions']
  assert params['sandbox']=='read-only' and params['environments']==[] and params['ephemeral']
  assert not {t['name'] for t in params['dynamicTools']}&{'statsdirect_run_analysis','statsdirect_open_analysis'}
  thread='report-'+str(len(threads));threads[thread]={};result={'thread':{'id':thread},'model':'report-fixture'}
 elif method=='turn/start':
  assert params['sandboxPolicy']=={'type':'readOnly','networkAccess':False}
  thread=params['threadId'];payload=json.loads(params['input'][0]['text'].split('\n',1)[1]);context=json.loads(payload['referenceContext'])
  assert all(set(row)=={'role','text'} for row in payload['conversation'])
  assert not any(s in json.dumps(payload) for s in ['HIDDEN_RECORD_SECRET','UNSHARED_SCRIPT','UNSHARED_WORKBOOK','UNRELATED_REPORT'])
  question=payload['conversation'][-1]['text']
  send({'id':request['id'],'result':{'turn':{'id':'turn'}}})
  if question=='NO_SHARING':
   assert context['documents']==[] and 'currentReport' not in context
   assert 'PRIVATE_REPORT' not in json.dumps(payload)
   finish(thread,'A confidence interval describes uncertainty in an estimate; share the report to discuss its particular results.');continue
  if question=='REPORT_TEST':
   report=context['currentReport'];threads[thread]['report']=report
   assert report['kind']=='report' and report['snapshot'] and report['title']=='PRIVATE_REPORT'
   assert report['focusedResult']['operation']=='TPaired' and '56.111' in report['text']
   assert report['chartCount']>0 and report['chartImagesIncluded'] is False
   assert len(context['documents'])==1 and context['documents'][0]['kind']=='report'
   tool(thread,'statsdirect_read_document',{'documentId':report['documentId']});continue
  if question=='CANCEL_TEST':continue
  finish(thread,'A conceptual follow-up based on our conversation.');continue
 elif method in ['thread/unsubscribe','turn/interrupt','account/login/cancel']:pass
 else:raise AssertionError(method)
 send({'id':request['id'],'result':result})
