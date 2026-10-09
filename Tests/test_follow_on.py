"""Suggested follow-on operations: every engine operation the Windows menu reaches only through a
parent analysis is reachable on the Mac, and follow-ons run on the parent's inputs."""
from test_menu import Session, columns
import glob, json, uuid
from pathlib import Path
from xml.etree import ElementTree as ET
ROOT = Path(__file__).resolve().parents[1]

def local(tag): return tag.split('}')[-1]
definitions = {}
for path in glob.glob(str(ROOT/'FullEngine/Upstream/StatsDirectUI/Assets/Operations/*.xml')):
    root = ET.parse(path).getroot()
    name = next(e.text.strip() for e in root if local(e.tag) == 'name')
    definitions[name] = [(s.text or '').strip() for s in root.iter() if local(s.tag) == 'suggested-operation']
menu = set(json.loads((ROOT/'Content/analysis-menu.json').read_text())['operations'])
reachable, frontier = set(menu), list(menu)
while frontier:
    for s in definitions.get(frontier.pop(), []):
        if s in definitions and s not in reachable: reachable.add(s); frontier.append(s)
follow_on_only = sorted(o for o in reachable if o not in menu)
unreachable = sorted(set(definitions) - reachable)
assert len(definitions) == 277 and len(menu) == 208 and len(follow_on_only) == 67, (len(definitions), len(menu), len(follow_on_only))
# Neither a menu command nor a suggestion of any operation: the worksheet import and export commands,
# which the Windows worksheet window reaches by other means. The seven operations that no menu reached
# and no help topic described were retired upstream on 2026-10-08. Recorded, not hidden.
assert unreachable == ['ExportWorksheet', 'ImportWorksheet'], unreachable
print('PASS: 275 of 277 engine operations are reachable: 208 from the menu and 67 as follow-ons; the 2 others are listed')

s = Session()
def complete(operation, answers, parent=None):
    """Runs an operation to completion through the real prompt/answer boundary and keeps its session open."""
    id = str(uuid.uuid4())
    state = s.request(action='start', id=id, operation=operation, **({'parent': parent} if parent else {}))
    assert 'error' not in state or state['error'] is None, state
    state = s.wait(id); prompts = []
    for _ in range(100):
        if state.get('state') != 'input': break
        p = state['prompt']; name = p.get('name'); prompts.append(name)
        if name in answers: value = answers[name]
        elif p['kind'] == 'options': value = {o['value']: o['selected'] for o in p['options']}
        elif p['kind'] in ('fields', 'settings'): value = {o['name']: o['defaultValue'] for o in p['fields']}
        elif p['kind'] == 'boolean': value = False
        elif p['kind'] == 'confidence': value = p['defaultValue']
        elif p.get('defaultValue') is not None: value = p['defaultValue']
        elif p['kind'] == 'option': value = p['options'][0]['value']
        elif p['kind'] == 'selectList': value = [int(o['value']) for o in p['options']] if p.get('multiple') else [int(p['options'][0]['value'])]
        else: raise AssertionError(f'{operation}: unanswered {p}')
        assert not p.get('error'), (operation, p['error'])
        s.request(action='answer', id=id, token=state['token'], value=value); state = s.wait(id)
    assert state.get('state') == 'complete', (operation, state.get('error'), prompts)
    return id, state, prompts
try:
    anova_id, anova, prompts = complete('OneWay', {'data': columns([1, 2, 3, 4], [3, 5, 6, 8], [7, 8, 9, 11])})
    names = [x['operation'] for x in anova['suggestions']]
    assert names == ['Bonferroni', 'Tukey', 'Scheffe', 'NewmanKeuls', 'Dunnett', 'EqualityOfVariance'], names
    assert all(x['title'] for x in anova['suggestions']) and anova['parent'] is None
    # Post-hoc tests declare no help topic of their own (the Swift host then keeps the parent's help page).
    tukey = next(x for x in anova['suggestions'] if x['operation'] == 'Tukey'); assert 'help' in tukey and tukey['help'] is None, tukey
    # The follow-on inherits the ANOVA data: it asks only for what it adds.
    tukey_id, tukey_state, tukey_prompts = complete('Tukey', {}, parent=anova_id)
    assert 'data' not in tukey_prompts and tukey_state['parent'] == anova_id, tukey_prompts
    assert 'Tukey' in tukey_state['html'], tukey_state['html'][:200]
    # After a post-hoc test the parent's remaining suggestions are offered again, as on Windows.
    assert [x['operation'] for x in tukey_state['suggestions']] == ['Bonferroni', 'Scheffe', 'NewmanKeuls', 'Dunnett', 'EqualityOfVariance']
    # Bonferroni compares one pair of groups at a time: the ANOVA's groups are offered and two are chosen.
    bonf_id, bonf, bonf_prompts = complete('Bonferroni', {'variables': [0, 2]}, parent=tukey_id)
    assert 'data' not in bonf_prompts and 'variables' in bonf_prompts, bonf_prompts
    # The follow-on's record of inputs starts with the parent's, so its report and R script are reproducible.
    assert [h.get('name') for h in tukey_state['history']][:1] == ['data'] and 'data' in [h.get('name') for h in bonf['history']], tukey_state['history']
    # Dunnett asks for one control group through a single-choice list.
    dunnett_id, dunnett, dunnett_prompts = complete('Dunnett', {}, parent=anova_id)
    assert 'Dunnett' in dunnett['html'] and 'data' not in dunnett_prompts, dunnett_prompts
    assert 'Bonferroni' in bonf['html'] and [x['operation'] for x in bonf['suggestions']] == ['Tukey', 'Scheffe', 'NewmanKeuls', 'Dunnett', 'EqualityOfVariance']
    print('PASS: one-way ANOVA suggests its post-hoc tests; Tukey and then Bonferroni run on the ANOVA data through a two-step chain')
    # Without a parent, a follow-on is not a menu command; with the wrong parent it names its prerequisite.
    bad = s.request(action='start', id=str(uuid.uuid4()), operation='Tukey'); assert 'Unknown menu command' in bad.get('error', ''), bad
    slr_id, slr, _ = complete('SimpleLinearRegression', {'y': columns([3, 4, 5, 7, 9, 11]), 'x': columns([1, 2, 3, 4, 5, 6])})
    # A parent that never suggested the operation does not open it either (the suggestion list is the
    # only gate for follow-ons, as on Windows; prerequisite declarations guard direct starts only).
    wrong = s.request(action='start', id=str(uuid.uuid4()), operation='Tukey', parent=slr_id); assert 'Unknown menu command' in wrong.get('error', ''), wrong
    # Polynomial regression suggests the general-regression ANOVA, whose declared prerequisite it never ran.
    poly_id, poly, _ = complete('PolynomialRegression', {'y': columns([1, 4, 9, 16, 25, 36, 49]), 'x': columns([1, 2, 3, 4, 5, 6, 7])})
    assert 'MultipleLinearRegressionAnova' in [x['operation'] for x in poly['suggestions']], poly['suggestions']
    panova_id, panova, _ = complete('MultipleLinearRegressionAnova', {}, parent=poly_id)
    assert 'nalysis of variance' in panova['html'], panova['html'][:300]
    assert [x['operation'] for x in slr['suggestions']] == ['InterpolateXY', 'InterpolateYX', 'Ranv', 'PlotSimpleLinearRegression', 'PlotResidualsSimple', 'CiMeanY', 'PlotSeCi', 'PlotPredictionInterval', 'SimpleLinearRegressionCI'], slr['suggestions']
    plot_id, plot, plot_prompts = complete('PlotSimpleLinearRegression', {}, parent=slr_id)
    assert 'x' not in plot_prompts and 'y' not in plot_prompts and '<svg' in plot['html'], (plot_prompts, plot['html'][:200])
    released = s.request(action='release', id=anova_id); assert released.get('ok')
    gone = s.request(action='start', id=str(uuid.uuid4()), operation='Tukey', parent=anova_id); assert 'no longer open' in gone.get('error', ''), gone
    for id in (tukey_id, bonf_id, dunnett_id, slr_id, plot_id, poly_id, panova_id): assert s.request(action='release', id=id).get('ok')
    print('PASS: follow-ons are refused without a parent or from a parent that did not suggest them; regression follow-ons plot on the regression data; a suggested follow-on runs even when its declared prerequisite was never run; released parents are reported clearly')
finally:
    s.finish()
