"""Replay every follow-on form using synthetic data and actual parent results.

Check the ordered prompts as well as completion: a newly added or silently
skipped question needs an explicit fixture update, not an automatic answer.
Numerical reference comparisons remain in the engine/R regression suites.
"""
import json
import xml.etree.ElementTree as ET
from test_menu import Session, ROOT

# Read the namespace from the documents so the inventory follows the source.
definitions = []
for path in (ROOT / 'FullEngine/Upstream/StatsDirectUI/Assets/Operations').glob('*.xml'):
    root = ET.parse(path).getroot()
    namespace = root.tag.partition('}')[0] + '}' if root.tag.startswith('{') else ''
    definitions.append(root.findtext(namespace + 'name'))
menu = json.loads((ROOT / 'Content/analysis-menu.json').read_text())['operations']
follow_ons = set(definitions) - set(menu) - {'ImportWorksheet', 'ExportWorksheet'}
fixtures = json.loads((ROOT / 'Tests/form-follow-on-fixtures.json').read_text())['fixtures']
assert {f['operation'] for f in fixtures if 'parent' in f} == follow_ons, 'Update follow-on fixtures for changed Windows definitions'
assert len({f['operation'] for f in fixtures}) == len(fixtures), 'Duplicate fixture'

s = Session()
parents = {}
results = []
try:
    for fixture in fixtures:
        operation = fixture['operation']
        parent = parents.get(fixture.get('parent'))
        if 'parent' in fixture:
            assert parent, ('Missing parent fixture', fixture)
            assert operation in {item['operation'] for item in parent['suggestions']}, (operation, 'Not offered by parent')
        job, state = s.start(operation, parent=parent['id'] if parent else None)
        for index, step in enumerate(fixture['steps']):
            assert state['state'] == 'input', (operation, index, state.get('state'), state.get('error'))
            prompt = state['prompt']
            assert not prompt.get('error'), (operation, prompt)
            for field in ('name', 'kind', 'prompt'):
                assert prompt.get(field) == step[field], (operation, index, field, prompt.get(field), step[field])
            response = s.request(action='answer', id=job, token=state['token'], value=step['value'])
            assert not response.get('error'), (operation, response)
            state = s.wait(job)
        assert state['state'] == 'complete', (operation, state.get('state'), state.get('error'), state.get('prompt'))
        assert state['html'] or state['frames'], (operation, 'No output')
        assert 'Error rendering' not in state['html'], operation
        parents[operation] = state
        results.append({'operation': operation, 'parent': fixture.get('parent'), 'prompts': len(fixture['steps']), 'status': 'pass'})
        print('PASS follow-on replay', operation, flush=True)
    (ROOT / '.build/form-follow-ons.json').write_text(json.dumps(results, indent=2) + '\n')
    print(f'PASS: {len(follow_ons)} follow-on operations and {len(fixtures) - len(follow_ons)} supporting parent calculations')
finally:
    s.finish()
