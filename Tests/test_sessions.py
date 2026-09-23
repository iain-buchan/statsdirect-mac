"""Independent forms share the original engine without sharing prompts or results."""
import uuid
from test_menu import Session, columns, near

s = Session()
def answer_for(p, answers):
    if p.get('name') in answers: return answers[p['name']]
    if p.get('prompt') in answers: return answers[p['prompt']]
    if p['kind'] == 'options': return {o['value']: o['selected'] for o in p['options']}
    if p['kind'] == 'fields': return {o['name']: o['defaultValue'] for o in p['fields']}
    if p['kind'] == 'boolean': return False
    if p.get('defaultValue') is not None: return p['defaultValue']
    if p.get('skip'): return {'skip': True}
    raise AssertionError(p)

def advance(id, state, answers):
    assert state['state'] == 'input' and not state['prompt'].get('error'), state
    result = s.request(action='answer', id=id, token=state['token'], value=answer_for(state['prompt'], answers))
    assert not result.get('error'), result
    return s.wait(id)

try:
    fixtures = [
        ('ExactSign', {'n': 11, 'r': 9}),
        ('ExactSign', {'n': 20, 'r': 15}),
        ('TPaired', {'data': columns([312,242,340,388,296,254,391,402,290], [300,201,232,312,220,256,328,330,231]), 'doAgreement': True}),
        ('TPaired', {'data': columns([6,9,7,12,15], [2,4,5,6,8]), 'doAgreement': True}),
        ('RandomPairs', {'pairs': 6, 'seed': 31415, 'balance': True}),
        ('FillSeries', {'rows': 5, 'startval': 10, 'formula': 'X+2', 'title': 'Independent series'}),
    ]
    expected = [s.run(name, answers) for name, answers in fixtures]
    jobs = [s.start(name) for name, _ in fixtures]
    # Cancelling a seventh open form must not disturb any of the six others.
    cancelled, _ = s.start('TPaired')
    before = [(id, state['token'], state['prompt']) for id, state in jobs]
    s.close(cancelled)
    for id, token, prompt in before:
        state = s.request(action='poll', id=id)
        assert state['state'] == 'input' and state['token'] == token and state['prompt'] == prompt
    # Duplicate IDs and stale input still fail even with multiple forms open.
    id, state = jobs[0]
    assert s.request(action='start', id=id, operation='ExactSign').get('error')
    token = state['token']
    s.request(action='answer', id=id, token=token, value='NaN')
    invalid = s.wait(id)
    assert invalid['state'] == 'input' and invalid['prompt']['error']
    assert s.request(action='answer', id=id, token=token, value=11).get('error')
    s.request(action='answer', id=id, token=invalid['token'], value=11)
    jobs[0] = (id, s.wait(id))
    # Advance round-robin, retaining each suspended stack, and compare with
    # independent serial runs of the same statistical / SVG / data operations.
    for _ in range(100):
        pending = False
        for i, (id, state) in enumerate(jobs):
            if state['state'] == 'input':
                pending = True
                jobs[i] = (id, advance(id, state, fixtures[i][1]))
        if not pending: break
    for i, (id, state) in enumerate(jobs):
        assert state['state'] == 'complete', state
        assert state['values'] == expected[i]['values'], fixtures[i][0]
        assert state['frames'] == expected[i]['frames'], fixtures[i][0]
        assert state['history'] == expected[i]['history'], fixtures[i][0]
        if fixtures[i][0] == 'TPaired':
            assert '<svg' in state['html'] and 'Error rendering' not in state['html']
        s.close(id)
    near(jobs[0][1]['values']['prop'], 9/11)
    near(jobs[1][1]['values']['prop'], 15/20)
    print('PASS: six interleaved forms, duplicate analyses, independent cancellation, validation, seeded output, SVG and reports')
finally:
    s.finish()
