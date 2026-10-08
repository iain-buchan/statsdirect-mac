#!/usr/bin/python3
"""A split-frame stdio protocol fixture. No OpenAI calls or credentials."""
import json, os, sys, time, threading
assert os.environ['CODEX_HOME'].endswith('chatgpt-mock')
assert 'OPENAI_API_KEY' not in os.environ
assert 'CODEX_APP_SERVER_URL' not in os.environ
signed_in = False
sequence = 0
tool_pending = {}
tool_modes = {}
lock = threading.Lock()
def send(value):
    raw = json.dumps(value) + '\n'
    # Split within JSON: the reader must buffer bytes until the terminating newline.
    with lock:
        sys.stdout.write(raw[:13]); sys.stdout.flush()
        time.sleep(.003)
        sys.stdout.write(raw[13:]); sys.stdout.flush()
def notify(method, params): send({'method': method, 'params': params})
def login():
    global signed_in
    time.sleep(.1); signed_in = True
    notify('account/login/completed', {'loginId':'fixture-login', 'success':True, 'error':None})
for line in sys.stdin:
    request = json.loads(line); method = request.get('method'); params = request.get('params', {})
    if method == 'initialized': continue
    if 'id' not in request: continue
    result = {}
    if method is None:
        kind, thread, turn = tool_pending.pop(request['id'])
        success = request.get('result',{}).get('success',False)
        assert success == (kind == 'valid'), (kind,request)
        if kind == 'valid': assert json.loads(request['result']['contentItems'][0]['text'])['rows'] == 9
        if not tool_pending:
            notify('item/completed',{'threadId':thread,'turnId':turn,'item':{'id':'answer','type':'agentMessage','text':'Tool returned nine actual rows.'}})
            notify('turn/completed',{'threadId':thread,'turn':{'id':turn,'status':'completed'}})
        continue
    if method == 'initialize':
        assert params['clientInfo']['name'] == 'statsdirect_tutor'
    elif method == 'account/read':
        result = {'account':{'type':'chatgpt', 'email':'learner@example.invalid', 'planType':'plus'} if signed_in else None}
    elif method == 'account/login/start':
        assert params == {'type':'chatgpt','useHostedLoginSuccessPage':True,'appBrand':'chatgpt'}
        result = {'type':'chatgpt','loginId':'fixture-login','authUrl':'https://auth.openai.com/authorize?state=fixture'}
        threading.Thread(target=login).start()
    elif method == 'account/logout': signed_in = False
    elif method == 'thread/start':
        assert params['ephemeral'] and params['approvalPolicy'] == 'never' and params['sandbox'] == 'read-only'
        assert "biostatistics tutor" in params['baseInstructions']
        assert params['environments'] == []
        assert 'model' not in params and params['cwd'].endswith('/Workspace')
        if params.get('dynamicTools'):
            assert params['dynamicTools'][0]['type'] == 'function'
            assert params['dynamicTools'][0]['inputSchema']['additionalProperties'] is False
        sequence += 1; result = {'thread':{'id':str(sequence)},'model':'fixture-model'}
    elif method == 'turn/start':
        assert signed_in
        assert params['environments'] == []
        assert params['sandboxPolicy'] == {'type':'readOnly','networkAccess':False}
        text = params['input'][0]['text']; thread = params['threadId']; turn = 'turn-' + thread
        latest = json.loads(text.split('\n',1)[1])['conversation'][-1]['text']
        if 'LIBRARY_TEST' in latest:
            context = json.loads(text.split('\n',1)[1])['referenceContext']
            marker = 'CURATED STATSDIRECT LESSON (original teaching material; references are editorial links, not pages fetched during this conversation):\n'
            lesson = json.loads(context.split(marker,1)[1].split('\n',1)[0])
            assert lesson['id'] == 'missing' and lesson['contentVersion'] == '2026-10-01'
            assert len(lesson['keyConcepts']) == 3 and len(lesson['teachingPrompts']) == 2
            assert lesson['practiceQuestions'][0]['correct'] == 'D'
            assert '17.5' in lesson['workedExample']['interpretation']
            assert lesson['sources'][0]['url'] == 'https://stefvanbuuren.name/fimd/sec-MCAR.html'
            assert 'METHOD CATALOGUE:' in context and len(context) < 32000
        if 'RESOURCE_TEST' in latest:
            context = json.loads(text.split('\n',1)[1])['referenceContext']
            assert 'https://example.org/course-cohort' in context
            assert 'retrieved-cohort-evidence' in context
            assert 'Learner statisticalSkills: advanced' in context
            assert 'Assessment preference: AI supported self-assessment' in context
            assert 'retired-resource-must-not-leak' not in context
            assert 'Example training provider' in context
            assert 'disabled-source-must-not-leak' not in context
            assert 'private-learner-identity' not in context
            overview=json.loads(context.split('CURRENT STATSDIRECT WORKSPACE (metadata, not cell values):\n',1)[1].split('\nMETHOD CATALOGUE:',1)[0])
            assert overview['documents'] == [] and overview['focusedDocumentId'] == ''
        if 'CANCEL_TEST' in text: time.sleep(.5)
        if 'DISCONNECT_TEST' in text: os._exit(0)
        # Unrelated events must never appear in the learner's reply.
        notify('item/completed',{'threadId':'some-other-thread','turnId':turn,'item':{'id':'foreign','type':'agentMessage','text':'WRONG THREAD'}})
        send({'id':request['id'],'result':{'turn':{'id':turn,'status':'inProgress'}}})
        if 'CANCEL_TEST' in text: continue
        if 'TOOL_TEST' in text:
            for kind in ['valid','duplicate','foreign','wrongturn','unknown']:
                tool_id = thread + '-' + kind
                tool_pending[tool_id] = (kind,thread,turn)
            for kind in ['valid','duplicate','foreign','wrongturn','unknown']:
                tool_id = thread + '-' + kind
                send({'id':tool_id,'method':'item/tool/call','params':{'threadId':'foreign' if kind=='foreign' else thread,'turnId':'wrong' if kind=='wrongturn' else turn,'callId':'same-call' if kind in ['valid','duplicate'] else kind,'tool':'shell' if kind=='unknown' else 'statsdirect_read_data','arguments':{'documentId':'worksheet'},'namespace':None}})
            continue
        if 'TOOL_CANCEL' in text:
            send({'id':'cancel-tool','method':'item/tool/call','params':{'threadId':thread,'turnId':turn,'callId':'cancel-call','tool':'statsdirect_read_data','arguments':{'documentId':'worksheet'}}})
            continue
        if 'LIMIT_TEST' in text:
            notify('turn/completed',{'threadId':thread,'turn':{'id':turn,'status':'failed','error':{'message':'Usage limit SECRET TOKEN'}}}); continue
        notify('item/agentMessage/delta',{'threadId':thread,'turnId':turn,'itemId':'answer','delta':'Analyse within-person '})
        notify('item/agentMessage/delta',{'threadId':thread,'turnId':turn,'itemId':'answer','delta':'differences.'})
        notify('item/completed',{'threadId':thread,'turnId':turn,'item':{'id':'answer','type':'agentMessage','text':'Analyse within-person differences.'}})
        notify('turn/completed',{'threadId':thread,'turn':{'id':turn,'status':'completed'}}); continue
    elif method in ['turn/interrupt','thread/unsubscribe','account/login/cancel']: pass
    else: raise AssertionError('Unexpected call: ' + str(method))
    send({'id':request['id'],'result':result})
