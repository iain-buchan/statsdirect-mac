#!/usr/bin/python3
"""Local script-assistant transport fixture; no credentials or external calls."""
import json, os, sys, time
from pathlib import Path
home=Path(os.environ['CODEX_HOME'])
assert home.name=='chatgpt-mock'
assert 'OPENAI_API_KEY' not in os.environ
signed=False
threads={}
pending={}
sequence=0
def send(value): print(json.dumps(value),flush=True)
def notify(method,params): send({'method':method,'params':params})
def finish(thread,text):
 notify('item/agentMessage/delta',{'threadId':thread,'turnId':'turn','itemId':'answer','delta':text})
 notify('item/completed',{'threadId':thread,'turnId':'turn','item':{'id':'answer','type':'agentMessage','text':text}})
 notify('turn/completed',{'threadId':thread,'turn':{'id':'turn','status':'completed'}})
for line in sys.stdin:
 request=json.loads(line)
 with (home/'requests.jsonl').open('a') as f: f.write(json.dumps(request)+'\n')
 method=request.get('method');params=request.get('params',{})
 if method=='initialized':continue
 if method is None:
  thread=pending.pop(request['id']); assert request['result']['success'],request
  data=json.loads(request['result']['contentItems'][0]['text'])
  assert data['rowCount']==3 and [c['values'] for c in data['columns']]==[['10','20','30'],['8','17','25']],data
  finish(thread,'I read the three approved worksheet rows. Suggested code:\n```r\nmean(c(10, 20, 30))\n```\nReview and run this code yourself.');continue
 result={}
 if method=='initialize':pass
 elif method=='account/read':result={'account':{'type':'chatgpt','email':'fixture@example.invalid','planType':'plus'} if signed else None}
 elif method=='account/login/start':
  signed=True;result={'type':'chatgpt','loginId':'login','authUrl':'https://auth.openai.com/authorize?state=fixture'}
 elif method=='account/logout':signed=False
 elif method=='thread/start':
  assert params['sandbox']=='read-only' and params['ephemeral'] and params['environments']==[]
  assert params['serviceName']=='statsdirect-script-assistant' and 'R and statistical analysis assistant' in params['baseInstructions']
  names=[t['name'] for t in params['dynamicTools']];assert not set(names)&{'statsdirect_run_analysis','statsdirect_open_analysis'}
  sequence+=1;thread='script-'+str(sequence);threads[thread]=params;result={'thread':{'id':thread},'model':'script-fixture'}
 elif method=='turn/start':
  assert params['sandboxPolicy']=={'type':'readOnly','networkAccess':False}
  thread=params['threadId'];payload=json.loads(params['input'][0]['text'].split('\n',1)[1]);context=json.loads(payload['referenceContext'])
  assert all(set(m)=={'role','text'} for m in payload['conversation']), 'Local export metadata was sent to AI'
  question=payload['conversation'][-1]['text'];result={'turn':{'id':'turn'}}
  send({'id':request['id'],'result':result})
  if question=='PEFR_CONTEXT':
   assert 'before <- c(312' in context['currentScript']['script']
   code=Path(__file__).with_name('ai-pefr.R').read_text()
   finish(thread,'```r\nd <- before - after\n```\nThen analyse:\n```r\n'+code+'\n```');continue
  if question=='PEFR_FOLLOWUP':
   assert context['documents']==[] and 'currentScript' not in context
   finish(thread,'```r\nstopifnot(length(d)==9)\nmean(d)\n```');continue
  if question=='CANCEL_TEST':continue
  if question=='STREAM_TEST':
   assert context['documents']==[] and 'currentScript' not in context
   answer='Earlier reading and copying should stay stable.\n'+''.join(f'Paragraph {i}: Paired measurements, 95% confidence intervals, and Unicode α 🧪.\n' for i in range(180))+'```r\nmean(c(1, 2, 3))\n```\n'
   for step in range(5):
    chunk=(answer if step==0 else '')+f'STREAM_STEP_{step}\n'
    if step>0:answer+=chunk
    else:answer+=f'STREAM_STEP_{step}\n'
    notify('item/agentMessage/delta',{'threadId':thread,'turnId':'turn','itemId':'answer','delta':chunk})
    gate=home/f'stream-step-{step}'
    deadline=time.monotonic()+25
    while not gate.exists():
     assert time.monotonic()<deadline, f'Stream step {step} was not acknowledged'
     time.sleep(.01)
   notify('item/completed',{'threadId':thread,'turnId':'turn','item':{'id':'answer','type':'agentMessage','text':answer}})
   notify('turn/completed',{'threadId':thread,'turn':{'id':'turn','status':'completed'}})
   continue
  if question=='NO_SHARING':
   assert context['documents']==[] and 'currentScript' not in context
   assert 'PRIVATE_SCRIPT' not in json.dumps(payload) and 'PRIVATE_WORKBOOK' not in json.dumps(payload)
   finish(thread,'General R guidance without reading any open documents.');continue
  if question=='DATA_TEST':
   assert context['currentScript']['script']=='PRIVATE_SCRIPT <- c(1, 2, 3)'
   workbook=next(d for d in context['documents'] if d['kind']=='grid');assert workbook['title']=='PRIVATE_WORKBOOK'
   pending['read-'+thread]=thread
   send({'id':'read-'+thread,'method':'item/tool/call','params':{'threadId':thread,'turnId':'turn','callId':'cells','tool':'statsdirect_read_data','arguments':{'documentId':workbook['documentId'],'columns':[0,1],'firstRow':2,'lastRow':4}}});continue
  finish(thread,'A scoped R assistance reply.');continue
 elif method in ['turn/interrupt','thread/unsubscribe','account/login/cancel']:pass
 else:raise AssertionError(method)
 send({'id':request['id'],'result':result})
