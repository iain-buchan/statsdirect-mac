"""Groups by identifier: long data (one data column plus identifier columns) gives the same
results as the same groups in separate columns, as on Windows."""
from test_menu import Session
import glob, re, uuid
from pathlib import Path
from xml.etree import ElementTree as ET
ROOT = Path(__file__).resolve().parents[1]

# Wide layouts with digit-free titles, so the reports compare number for number.
def columns(*cols): return {'columns': [{'title': 'group ' + 'abcdefgh'[i], 'values': list(v)} for i, v in enumerate(cols)], 'source': 'Test fixture'}
def long_input(values, groups, block=None, titles=('value', 'group', 'block')):
    d = {'source': 'Long data', 'preserveRows': True, 'layout': 'long', 'columns': [{'title': titles[0], 'values': list(values)}],
         'groupIdentifiers': [{'title': titles[1], 'values': list(groups)}]}
    if block is not None: d['blockIdentifiers'] = [{'title': titles[2], 'values': list(block)}]
    return d
def numbers(html):
    text = re.sub(r'<[^>]+>', ' ', html)
    return re.findall(r'-?\d+\.\d+(?:e-?\d+)?|-?\b\d+\b', text)
def same_numbers(a, b, what):
    na, nb = numbers(a['html']), numbers(b['html'])
    assert na and na == nb, (what, na[:12], nb[:12])

# Every frame that Windows lets the user pivot is described that way to the Mac form.
def local(tag): return tag.split('}')[-1]
askers = [Path(f).stem for f in glob.glob(str(ROOT/'FullEngine/Upstream/StatsDirectUI/Assets/Operations/*.xml'))
          if any(local(e.tag) == 'ask-for-group-id' and (e.text or '').strip() == 'true' for e in ET.parse(f).getroot().iter())]
assert len(askers) == 40, len(askers)

s = Session()
try:
    id, state = s.start('OneWay'); p = state['prompt']
    assert p['kind'] == 'grid' and p['groupIdentifiers'] == 'single' and p['groupsByIdentifier'] is False, p
    s.close(id)
    id, state = s.start('TwoWay'); assert state['prompt']['groupIdentifiers'] == 'treatmentAndBlock'; s.close(id)
    id, state = s.start('TPaired'); assert state['prompt']['groupIdentifiers'] == 'single'; s.close(id)
    print('PASS: frames that Windows pivots are described with their identifier mode (single, or treatment and block)')

    wide = s.run('OneWay', {'data': columns([1, 2, 3, 4], [3, 5, 6, 8], [7, 8, 9, 11])})
    rows = [1, 3, 7, 2, 5, 8, 3, 6, 9, 4, 8, 11]; groups = ['a', 'b', 'c'] * 4
    long = s.run('OneWay', {'data': long_input(rows, groups)})
    same_numbers(wide, long, 'one-way ANOVA')
    assert 'value_group_a' in long['html'] and 'value_group_c' in long['html'], long['html'][:400]
    # The record of inputs holds the pivoted groups, so the report and R script show what was analysed.
    data_record = next(h for h in long['history'] if h.get('name') == 'data')
    assert [c['title'] for c in data_record['value']['columns']] == ['value_group_a', 'value_group_b', 'value_group_c'] and data_record['value']['columns'][2]['values'] == [7, 8, 9, 11], data_record
    # A missing observation inside a group is recorded as '*', with the worksheet provenance, like a wide answer.
    gap = s.run('OneWay', {'data': long_input([1, 3, 7, 2, '*', 8, 3, 6, 9, 4, 8, 11], groups)})
    gap_record = next(h for h in gap['history'] if h.get('name') == 'data')['value']
    assert gap_record['columns'][1]['values'] == [3, '*', 6, 8] and gap_record['layout'] == 'long' and gap_record['source'] == 'Long data' and gap_record['identifiers'] == ['group'], gap_record
    # Groups appear in order of first appearance, not sorted; numeric identifiers are labels.
    reordered = s.run('OneWay', {'data': long_input([7, 8, 9, 11] + [1, 2, 3, 4] + [3, 5, 6, 8], ['3'] * 4 + ['1'] * 4 + ['2'] * 4)})
    assert ['value_group_3', 'value_group_1', 'value_group_2'] == [c['title'] for c in next(h for h in reordered['history'] if h.get('name') == 'data')['value']['columns']]
    # Several identifier columns combine into one label, joined with a comma.
    combined = s.run('OneWay', {'data': dict(long_input(rows, ['x'] * 6 + ['y'] * 6), groupIdentifiers=[{'title': 'site', 'values': ['x'] * 6 + ['y'] * 6}, {'title': 'arm', 'values': ['1', '2'] * 6}])})
    assert 'value_site, arm_x, 1' in combined['html'] and 'value_site, arm_y, 2' in combined['html'], combined['html'][:600]
    print('PASS: one-way ANOVA from long data matches separate columns; groups keep first-appearance order and combined labels')

    wide_mw = s.run('MannWhitney', {'data': columns([1, 2, '*', 4, 5], [4, 6, 7, 8, 9])})
    long_mw = s.run('MannWhitney', {'data': long_input([1, 4, 2, 6, '*', 7, 4, 8, 5, 9], ['p', 'q'] * 5)})
    same_numbers(wide_mw, long_mw, 'Mann-Whitney with a missing value skipped')
    wide_k = s.run('Kruskal', {'data': columns([1, 2, 3, 4], [3, 5, 6, 8], [7, 8, 9, 11])})
    long_k = s.run('Kruskal', {'data': long_input(rows, groups)})
    same_numbers(wide_k, long_k, 'Kruskal-Wallis')
    print('PASS: Mann-Whitney (missing values skipped) and Kruskal-Wallis agree between layouts')

    wide_tw = s.run('TwoWay', {'data': columns([1, 2, 4, 6], [3, 6, 7, 9], [4, 5, 8, 10])})
    treatments, blocks, values = [], [], []
    wide_cols = [[1, 2, 4, 6], [3, 6, 7, 9], [4, 5, 8, 10]]
    for b in range(4):
        for t in range(3): treatments.append(f'T{t + 1}'); blocks.append(f'B{b + 1}'); values.append(wide_cols[t][b])
    long_tw = s.run('TwoWay', {'data': long_input(values, treatments, blocks, titles=('score', 'treatment', 'block'))})
    same_numbers(wide_tw, long_tw, 'two-way ANOVA by treatment and block identifiers')
    assert 'score_treatment_T1' in long_tw['html']
    wide_fr = s.run('Friedman', {'data': columns([1, 2, 4, 6], [3, 6, 7, 9], [4, 5, 8, 10])})
    long_fr = s.run('Friedman', {'data': long_input(values, treatments, blocks, titles=('score', 'treatment', 'block'))})
    same_numbers(wide_fr, long_fr, 'Friedman by treatment and block identifiers')
    print('PASS: two-way ANOVA and Friedman from treatment and block identifiers match separate columns')

    # A follow-on runs on the pivoted groups.
    anova_id = str(uuid.uuid4()); st = s.request(action='start', id=anova_id, operation='OneWay'); st = s.wait(anova_id)
    s.request(action='answer', id=anova_id, token=st['token'], value=long_input(rows, groups)); st = s.wait(anova_id)
    assert st['state'] == 'complete' and 'Tukey' in [x['operation'] for x in st['suggestions']]
    tukey_id = str(uuid.uuid4()); tk = s.request(action='start', id=tukey_id, operation='Tukey', parent=anova_id); tk = s.wait(tukey_id)
    while tk['state'] == 'input':
        s.request(action='answer', id=tukey_id, token=tk['token'], value=tk['prompt'].get('defaultValue')); tk = s.wait(tukey_id)
    assert tk['state'] == 'complete' and 'value_group_a' in tk['html'], tk.get('error')
    for i in (tukey_id, anova_id): assert s.request(action='release', id=i).get('ok')
    print('PASS: a post-hoc follow-on runs on the groups pivoted from long data')

    def refused(operation, answer, fragment):
        id, st = s.start(operation)
        s.request(action='answer', id=id, token=st['token'], value=answer); st = s.wait(id)
        assert st['state'] == 'input' and fragment in (st['prompt'].get('error') or ''), (operation, st.get('state'), st.get('prompt', {}).get('error'))
        s.close(id)
    refused('OneWay', long_input(rows, ['a'] * 12), 'needs at least 2')
    refused('TUnpaired', long_input(rows, groups), 'needs exactly 2')
    refused('OneWay', long_input(rows, ['a', 'b', ''] * 4), 'no group identifier')
    refused('TwoWay', long_input(values, treatments[:-1] + ['T1'], blocks, titles=('score', 'treatment', 'block')), 'same size')
    refused('TwoWay', long_input(values, treatments, ['B1'] * 12, titles=('score', 'treatment', 'block')), 'one observation per block')
    # Balanced marginal counts can conceal duplicate treatment/block pairs. Previously these
    # silently overwrote values and reported results using the remaining complete blocks.
    duplicate_treatments = ['A', 'A', 'B', 'B', 'A', 'B', 'A', 'B']
    duplicate_blocks = ['X', 'X', 'Y', 'Y', 'Z', 'Z', 'W', 'W']
    for operation in ('TwoWay', 'Friedman'):
        for first in (1, '*'):
            refused(operation, long_input([first, 2, 3, 4, 5, 7, 8, 11], duplicate_treatments, duplicate_blocks), 'more than one observation')
    print('PASS: duplicate treatment/block combinations are refused even with balanced marginal counts or missing values')
    refused('OneWay', dict(long_input(rows, groups), columns=[{'title': 'a', 'values': rows}, {'title': 'b', 'values': rows}]), 'one data column')
    refused('BoxWhiskerPlot', long_input([1, '*', 2, '*', 3, '*'], ['a', 'b'] * 3), 'no numeric observations')
    # Frames that take categories or text keep separate columns: no identifier layout is offered.
    id, st = s.start('BarPlotFrequency'); assert 'groupIdentifiers' not in st['prompt'], st['prompt']; s.close(id)
    # A paired frame needs equal lengths: unequal groups are padded with missing values once accepted, as on Windows.
    id, st = s.start('TPaired')
    s.request(action='answer', id=id, token=st['token'], value=long_input([1, 2, 3, 4, 5, 6, 7], ['x', 'y'] * 3 + ['x'])); st = s.wait(id)
    assert st['state'] == 'input' and st['prompt']['kind'] == 'boolean' and 'unequal length' in st['prompt']['prompt'], st.get('prompt')
    s.request(action='answer', id=id, token=st['token'], value=False); st = s.wait(id)
    assert st['state'] == 'input' and 'different numbers of observations' in (st['prompt'].get('error') or ''), st.get('prompt')
    s.request(action='answer', id=id, token=st['token'], value=long_input([1, 2, 3, 4, 5, 6, 7], ['x', 'y'] * 3 + ['x'])); st = s.wait(id)
    s.request(action='answer', id=id, token=st['token'], value=True); st = s.wait(id)
    assert st['state'] != 'failed' and (st['state'] == 'complete' or st['prompt']['name'] != 'data'), st.get('error')
    padded = next(h for h in st['history'] if h.get('name') == 'data') if st['state'] == 'complete' else None
    s.close(id)
    print('PASS: a paired frame from unequal groups is padded with missing values after the Windows warning, or refused when declined')
    print('PASS: wrong group counts, blank identifiers, unequal treatments and repeated blocks are refused with clear messages')

    # The Analysis options form offers the setting, and it changes the form's default layout.
    id, st = s.start('AnalysisOptions')
    field = next(f for f in st['prompt']['fields'] if f['name'] == 'selectGroupsByIdentifier')
    assert not field.get('disabled') and not field.get('note'), field
    values_ = {f['name']: f['defaultValue'] for f in st['prompt']['fields']}; values_['selectGroupsByIdentifier'] = True
    reply = s.request(action='answer', id=id, token=st['token'], value=values_); st = s.wait(id); assert st['state'] == 'complete', (st.get('state'), st.get('error'), (st.get('prompt') or {}).get('error'), (st.get('prompt') or {}).get('name'))
    defaults = st['analysisOptions']; s.close(id); assert defaults['selectGroupsByIdentifier'] is True
    id, st = s.start('OneWay', defaults); assert st['prompt']['groupsByIdentifier'] is True, st['prompt']; s.close(id)
    print('PASS: the groups-by-identifier setting is offered and makes identifiers the default layout')
finally:
    s.finish()
