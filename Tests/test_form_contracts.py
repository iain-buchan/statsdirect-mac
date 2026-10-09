"""Exercise later data-entry branches, not just the first prompt of each menu item.

The inventory comes from the Windows operation definitions. New explicitly
embedded tables must acquire a fixture here rather than silently escaping coverage.
These are host/engine contract tests; native rendering is checked separately.
"""
import xml.etree.ElementTree as ET
import uuid
from test_menu import Session, columns, ROOT

NS = {'s': 'http://www.statsdirect.com/schemas/Operation.xsd'}
EXPECTED = {
    ('Cuzick', 'scores'), ('KappaScreen', 'weights'),
    ('ExactChiRbyCScreen', 'data'), ('ExactFisherRbyC', 'data'),
    ('ChiWoolfScreen', 'data'), ('MantelHaenszelScreen', 'data'),
}
inventory = set()
for path in (ROOT / 'FullEngine/Upstream/StatsDirectUI/Assets/Operations').glob('*.xml'):
    xml = ET.parse(path)
    for parameter in xml.findall('.//s:parameters/*', NS):
        if parameter.findtext('s:can-select', namespaces=NS) == 'false':
            inventory.add((xml.findtext('s:name', namespaces=NS), parameter.findtext('s:name', namespaces=NS)))
assert inventory == EXPECTED, ('Update embedded-form fixtures for changed Windows definitions', inventory ^ EXPECTED)

s = Session()
seen = set()

def advance(job, state, value):
    result = s.request(action='answer', id=job, token=state['token'], value=value)
    assert not result.get('error'), result
    return s.wait(job)

def embedded(operation, prompt):
    seen.add((operation, prompt['name']))
    assert prompt['kind'] == 'grid' and prompt.get('screen') is True, (operation, prompt)

def finish(job, state, answers=None, keep=False):
    for _ in range(30):
        if state['state'] != 'input':
            break
        p = state['prompt']
        assert not p.get('error'), p
        if answers and p.get('name') in answers:
            value = answers[p['name']]
        elif p['kind'] == 'boolean':
            value = False  # Do not run optional million-iteration simulations.
        elif p.get('defaultValue') is not None:
            value = p['defaultValue']
        else:
            raise AssertionError(('Unexpected untested branch', p))
        state = advance(job, state, value)
    assert state['state'] == 'complete' and state['html'] and 'Error rendering' not in state['html'], state
    if not keep:
        s.close(job)
    return state

try:
    # Two open analyses must retain their own group counts and prepared scores.
    pending = []
    for count in (3, 5):
        job, state = s.start('Cuzick')
        state = advance(job, state, columns(*([i+1, i+2, i+4, i+6] for i in range(count))))
        p = state['prompt']; embedded('Cuzick', p)
        assert p['rows'] == count and p['initial']['columns'][0]['values'] == list(range(1, count+1)), p
        pending.append((job, state))
    job, state = pending[0]
    state = advance(job, state, columns([-1, 2, 3]))
    assert state['state'] == 'input' and state['prompt']['error'], state
    assert state['prompt']['initial']['columns'][0]['values'] == [1, 2, 3]
    result = finish(job, advance(job, state, columns([1, 2, 4])))
    assert next(h['value'] for h in result['history'] if h.get('name') == 'scores')['columns'][0]['values'] == [1, 2, 4]
    job, state = pending[1]
    assert s.request(action='poll', id=job)['token'] == state['token']
    s.close(job)
    job, state = s.start('Cuzick')
    state = advance(job, state, columns([1, 2, 4, 6], [2, 3, 5, 7]))
    assert state['prompt']['initial']['columns'][0]['values'] == [1, 2]
    finish(job, advance(job, state, state['prompt']['initial']))
    print('PASS Cuzick: 2/3/5 groups, defaults, custom scores, rejection, independent forms and cancel/reopen')

    job, state = s.start('KappaScreen')
    state = advance(job, state, columns([20, 5, 2], [3, 25, 4], [1, 3, 18]))
    state = advance(job, state, '3')  # User-defined weights, missed by default-path tests.
    state = advance(job, state, False)
    p = state['prompt']; embedded('KappaScreen', p)
    assert p['length'] == 3 and p['minColumns'] == p['maxColumns'] == 3, p
    state = advance(job, state, columns([1, .5], [.5, 1], [0, .5]))
    assert state['state'] == 'input' and state['prompt']['error'], state
    finish(job, advance(job, state, columns([1, .5, 0], [.5, 1, .5], [0, .5, 1])))
    print('PASS user-defined kappa weights: embedded table, 3×3 contract, short-table rejection and correction')

    for operation in ('ChiWoolfScreen', 'MantelHaenszelScreen'):
        job, state = s.start(operation); embedded(operation, state['prompt'])
        assert state['prompt']['minColumns'] == state['prompt']['maxColumns'] == 2
        state = advance(job, state, columns([20, 10, 15], [10, 20, 10]))
        assert state['state'] == 'input' and state['prompt']['error'], state
        values = columns([20, 10, 15, 10], [10, 20, 10, 25])
        finish(job, advance(job, state, values), keep=True)
        child = str(uuid.uuid4())
        reply = s.request(action='start', id=child, operation=operation, parent=job)
        assert not reply.get('error'), reply
        state = s.wait(child); p = state['prompt']; embedded(operation, p)
        assert [c['values'] for c in p.get('initial', {}).get('columns', [])] == [c['values'] for c in values['columns']], p
        finish(child, advance(child, state, p['initial']))
        s.close(job)
    print('PASS Woolf and Mantel–Haenszel: embedded tables, rejection/correction and retained data in follow-on forms')

    for operation in ('ExactChiRbyCScreen', 'ExactFisherRbyC'):
        job, state = s.start(operation); embedded(operation, state['prompt'])
        state = advance(job, state, columns([10, 12, 8], [9, 11, 15]))
        for _ in range(20):
            if state['state'] != 'input' or state['prompt']['kind'] == 'fields':
                break
            p = state['prompt']; assert not p.get('error'), p
            assert p['kind'] == 'boolean', p
            state = advance(job, state, p['name'] == 'specify_scores')
        p = state['prompt']
        assert p['kind'] == 'fields' and [f['defaultValue'] for f in p['fields']] == [1, 2, 3, 1, 2], p
        finish(job, advance(job, state, {f['name']: f['defaultValue'] for f in p['fields']}))
    print('PASS both R×C forms and their later row/column trend-score defaults')

    job, state = s.start('LogRank')
    for name, value in [('gid', columns(['A', 'B', 'C']*4)), ('times', columns(range(1, 13))),
                        ('deaths', columns([1, 1, 0]*4)), ('strata', {'skip': True}), ('wt_method', '1')]:
        assert state['prompt']['name'] == name, state
        state = advance(job, state, value)
    p = state['prompt']
    assert p['name'] == 'group_scores' and p['screen'] and p['fixedRows'] and p['rows'] == 3, p
    assert p['initial']['columns'][0]['values'] == [1, 2, 3]
    finish(job, advance(job, state, p['initial']))
    print('PASS three-group log-rank: later trend-score table has three initialized rows')
    assert seen == inventory, ('Untested embedded forms', inventory - seen)
    print('PASS every explicitly embedded entry table in the Windows XML inventory exercised')
finally:
    s.finish()
