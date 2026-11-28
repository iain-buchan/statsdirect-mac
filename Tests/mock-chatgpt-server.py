#!/usr/bin/python3
"""A split-frame stdio protocol fixture. No OpenAI calls or credentials."""
import json, os, re, sys, time, threading
from pathlib import Path
assert os.environ['CODEX_HOME'].endswith('chatgpt-mock')
assert 'OPENAI_API_KEY' not in os.environ
assert 'CODEX_APP_SERVER_URL' not in os.environ
signed_in = False
sequence = 0
tool_pending = {}
tool_modes = {}
# The tutor's refusals: its own texts, and the two a question-only worksheet reply gives every failed call, as Windows' guidance-only
# replies do (ChatGPTTutor.cs:365-370): one for Windows' worksheet tools and one for any other tool; a stopped call is Request stopped.
UNAVAILABLE = 'This request is not available in the current learning question.'
REPEATED = 'Repeated request or tool limit reached. Continue with the results already supplied.'
MASKED = 'The analysis proposal could not be staged.'
HELP = 'This help request could not be completed.'
REFUSALS = {'duplicate': REPEATED, 'foreign': UNAVAILABLE, 'wrongturn': UNAVAILABLE, 'unknown': UNAVAILABLE,
            'masked-duplicate': MASKED, 'masked-wrongturn': MASKED, 'masked-clarify': MASKED, 'masked-propose': MASKED,
            'masked-read': HELP, 'masked-unknown': HELP,
            'masked-card-error': MASKED, 'masked-read-error': HELP, 'masked-stopped': 'Request stopped.'}
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

def bundled_lesson(lesson_id):
    lessons = json.loads((Path(__file__).resolve().parents[1]/'Content/Learn/lessons.json').read_text())
    return next(lesson for lesson in lessons if lesson['id'] == lesson_id)

def compact(value): return json.dumps(value, ensure_ascii=False, separators=(',', ':'), sort_keys=True)

def curated_fields():
    """The fields LearningLibrary sends, read from its source so that the two lists cannot drift apart."""
    source = (Path(__file__).resolve().parents[1]/'Sources/LearningLibrary.swift').read_text()
    return re.findall(r'"(\w+)"', re.search(r'static let fields = \[(.*?)\]', source, re.S)[1])

def method_catalogue():
    operations = json.loads((Path(__file__).resolve().parents[1]/'Content/analysis-menu.json').read_text())['operations']
    return '\n'.join(key + ': ' + (operations[key].get('title') or key) for key in sorted(operations))

def lesson_allowance(context):
    """What LearnHost allows the curated record: what the learner's own text, the workspace summary (6,000 at most), the
    method catalogue and the headings leave of the 32,000-character reference context; 9,000 at most, 6,500 at least."""
    heading = 'COURSE, LESSON AND LEARNING CONTEXT (separate from open data):\n'
    assert context.startswith(heading)
    learner = len(context.split('\nCURATED STATSDIRECT LESSON (', 1)[0]) - len(heading)
    return min(9000, max(6500, 32000 - (learner + 6000 + len(method_catalogue()) + 600)))

def curated_lesson(context):
    marker = 'CURATED STATSDIRECT LESSON (original teaching material; references are editorial links, not pages fetched during this conversation):\n'
    payload = next(line for line in context.split(marker, 1)[1].splitlines() if line.startswith('{'))
    assert len(payload) <= lesson_allowance(context), (len(payload), lesson_allowance(context))
    # The reference context is cut at 32,000 characters: the method catalogue, which comes last, must have arrived whole.
    assert len(context) < 32000 and context.split('\nMETHOD CATALOGUE:\n', 1)[1] == method_catalogue()
    return json.loads(payload)

for line in sys.stdin:
    request = json.loads(line); method = request.get('method'); params = request.get('params', {})
    if method == 'initialized': continue
    if 'id' not in request: continue
    result = {}
    if method is None:
        kind, thread, turn = tool_pending.pop(request['id'])
        success = request.get('result',{}).get('success',False)
        assert success == (kind in ('valid','slow','masked-valid')), (kind,request)
        if kind == 'valid': assert json.loads(request['result']['contentItems'][0]['text'])['rows'] == 9
        if kind == 'masked-valid': assert json.loads(request['result']['contentItems'][0]['text'])['state'] == 'awaiting_design', request
        if kind in REFUSALS: assert request['result']['contentItems'][0]['text'] == REFUSALS[kind], (kind, request)
        if kind == 'large': assert 'too large' in request['result']['contentItems'][0]['text'], request
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
        text = params['input'][0]['text']; thread = params['threadId']; turn = 'turn-' + thread; checked = ''
        latest = json.loads(text.split('\n',1)[1])['conversation'][-1]['text']
        if 'PRIVATE_EVENT_TEST' in latest:
            notify('PRIVATE_SENTINEL_event_name',{'private':'PRIVATE_SENTINEL_body'})
            notify('thread/status/changed',{'private':'PRIVATE_SENTINEL_known_body'})
        if 'PRIVATE_PARSE_TEST' in latest:
            sys.stdout.write('{"PRIVATE_SENTINEL_malformed": not-json}\n'); sys.stdout.flush(); continue
        if 'PRIVATE_ERROR_TEST' in latest:
            send({'id':request['id'],'error':{'code':-32000,'message':'PRIVATE_SENTINEL_exception','data':'PRIVATE_SENTINEL_data'}}); continue
        if 'RISK_METHOD_TEST' in latest:
            context = json.loads(text.split('\n',1)[1])['referenceContext']
            lesson = bundled_lesson('risk')
            assert lesson['r'] in context  # Includes the complete helper and its actual call.
            assert lesson['workedExample']['interpretation'] in context
            assert curated_lesson(context)['contentVersion'] == lesson['contentVersion']
        if 'LIBRARY_TEST' in latest:
            context = json.loads(text.split('\n',1)[1])['referenceContext']
            lesson = curated_lesson(context)
            assert lesson['id'] == 'missing' and lesson['contentVersion'] == bundled_lesson('missing')['contentVersion']
            assert len(lesson['keyConcepts']) == 3 and len(lesson['teachingPrompts']) == 2
            assert lesson['practiceQuestions'][0]['correct'] == 'D'
            assert '17.5' in lesson['workedExample']['interpretation']
            assert lesson['sources'][0]['url'] == 'https://stefvanbuuren.name/fimd/sec-MCAR.html'
        # The page puts '[Lesson context: <title>]' before the learner's words, so the mark is looked for inside the message.
        for mark in ('LONG_LESSON_CONTEXT_TEST ', 'TIGHT_LESSON_CONTEXT_TEST '):
            if mark not in latest: continue
            context = json.loads(text.split('\n',1)[1])['referenceContext']
            expected = bundled_lesson(latest.split(mark, 1)[1].split()[0])
            whole = {key: expected[key] for key in curated_fields() if key in expected}
            lesson = curated_lesson(context)
            assert expected['r'] in context
            if mark.startswith('LONG'):
                # As on Windows, the tutor is given the whole lesson: a record longer than the 6,500 characters of
                # StatsDirect 1.1.3 keeps its embedded practice question and its review notes.
                assert len(compact(whole)) > 6500 and lesson == whole, sorted(set(whole) - set(lesson))
                assert 'omitted for length' not in context
            else:
                # The learner's own text is long here, so the lesson has less room than it needs: the embedded practice
                # question and the review notes go first, then the teaching prompts if it is still too long.
                allowance = lesson_allowance(context)
                assert len(compact(whole)) > allowance + 100, (len(compact(whole)), allowance)
                shortened = {key: value for key, value in whole.items() if key != 'practiceQuestions'}
                shortened['review'] = {key: value for key, value in whole['review'].items() if key != 'notes'}
                if len(compact(shortened)) > allowance: del shortened['teachingPrompts']
                assert lesson == shortened, sorted(set(shortened) ^ set(lesson))
                assert 'Embedded practice questions and detailed review notes have been omitted for length.' in context
            # The reply says which check ran, so that the driver can tell a check that passed from one that was skipped.
            checked = ' Checked %s %s.' % (mark.split('_')[0], expected['id'])
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
        if 'TOOL_MASKED' in text:
            # A question-only worksheet reply: the card's tool once, then calls the tutor refuses before any handler sees them, and
            # calls whose handler fails (with a private reason, or stopped). Whatever the reason, Windows' three worksheet tools get
            # the masked text and any other tool the help text; a stopped call gets Request stopped.
            calls = [('masked-valid', turn, 'card-call', 'statsdirect_choose_worksheet_t_test', {}),
                     ('masked-duplicate', turn, 'card-call', 'statsdirect_choose_worksheet_t_test', {}),
                     ('masked-wrongturn', 'wrong', 'card-other-turn', 'statsdirect_choose_worksheet_t_test', {}),
                     ('masked-clarify', turn, 'clarify-call', 'statsdirect_clarify_worksheet_analysis', {}),
                     ('masked-propose', turn, 'propose-call', 'statsdirect_propose_worksheet_analysis', {}),
                     ('masked-read', 'wrong', 'read-other-turn', 'statsdirect_read_data', {}),
                     ('masked-unknown', turn, 'shell-call', 'shell', {}),
                     ('masked-card-error', turn, 'card-error-call', 'statsdirect_choose_worksheet_t_test', {'mode': 'fail'}),
                     ('masked-read-error', turn, 'read-error-call', 'statsdirect_read_data', {'mode': 'fail'}),
                     ('masked-stopped', turn, 'card-stop-call', 'statsdirect_choose_worksheet_t_test', {'mode': 'stop'})]
            for kind, *_ in calls: tool_pending[thread + '-' + kind] = (kind,thread,turn)
            for kind, call_turn, call_id, tool, arguments in calls:
                send({'id':thread + '-' + kind,'method':'item/tool/call','params':{'threadId':thread,'turnId':call_turn,'callId':call_id,'tool':tool,'arguments':arguments,'namespace':None}})
            continue
        if 'TOOL_CANCEL' in text:
            send({'id':'cancel-tool','method':'item/tool/call','params':{'threadId':thread,'turnId':turn,'callId':'cancel-call','tool':'statsdirect_read_data','arguments':{'documentId':'worksheet'}}})
            continue
        if 'TOOL_WRITE_FAIL' in text:
            # Stop reading once the tool call is out: the app's result is queued, then its pipe write fails (EPIPE).
            send({'id':thread + '-writefail','method':'item/tool/call','params':{'threadId':thread,'turnId':turn,'callId':'write-fail-call','tool':'statsdirect_read_data','arguments':{'documentId':'worksheet'}}})
            os.close(0)
            time.sleep(30)
            os._exit(0)
        if 'TOOL_SLOW_WRITE' in text:
            # Read nothing for a while: the app's large result fills the pipe and its write waits on this side.
            tool_pending[thread + '-slow'] = ('slow',thread,turn)
            send({'id':thread + '-slow','method':'item/tool/call','params':{'threadId':thread,'turnId':turn,'callId':'slow-call','tool':'statsdirect_read_data','arguments':{'documentId':'worksheet'}}})
            time.sleep(1.5)
            continue
        if 'TOOL_LARGE' in text:
            tool_pending[thread + '-large'] = ('large',thread,turn)
            send({'id':thread + '-large','method':'item/tool/call','params':{'threadId':thread,'turnId':turn,'callId':'large-call','tool':'statsdirect_read_data','arguments':{'documentId':'worksheet'}}})
            continue
        if 'LIMIT_TEST' in text:
            notify('turn/completed',{'threadId':thread,'turn':{'id':turn,'status':'failed','error':{'message':'Usage limit SECRET TOKEN'}}}); continue
        notify('item/agentMessage/delta',{'threadId':thread,'turnId':turn,'itemId':'answer','delta':'Analyse within-person '})
        notify('item/agentMessage/delta',{'threadId':thread,'turnId':turn,'itemId':'answer','delta':'differences.' + checked})
        notify('item/completed',{'threadId':thread,'turnId':turn,'item':{'id':'answer','type':'agentMessage','text':'Analyse within-person differences.' + checked}})
        notify('turn/completed',{'threadId':thread,'turn':{'id':turn,'status':'completed'}}); continue
    elif method in ['turn/interrupt','thread/unsubscribe','account/login/cancel']: pass
    else: raise AssertionError('Unexpected call: ' + str(method))
    send({'id':request['id'],'result':result})
