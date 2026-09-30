"""Replay upstream forward-calculator fixtures through actual Mac forms/reports.

The Mac form takes a statistic, not inverse probabilities or rank-score input.
Those Windows-only input routes are counted as unsupported, not reported passed.
The unchanged upstream numerical inverse/range tests run in UpstreamSuites.
"""
from collections import Counter
import math
from pathlib import Path
from test_menu import Session

ROOT = Path(__file__).resolve().parents[1]
fixtures = ROOT / 'FullEngine/Upstream/tests/Distributions/benchmarks'
expected = {}
for line in (fixtures / 'expected.txt').read_text().splitlines():
    key, value, *room = line.split('\t')
    case, box = key.rsplit('|', 1)
    expected.setdefault(case, {})[box] = (value, float(room[0]) if room else None)

def number(text):
    try:
        value = float(text)
    except ValueError:
        return text  # Invalid-text fixtures must reach the actual form validator.
    return value if math.isfinite(value) else text

def agrees(kind, actual, reference, room):
    if reference == 'below 1e-15':
        return 0 <= actual <= 1e-15
    value = float(reference)
    # These are the upstream calculator's stated tolerances, including the
    # precision of its printed numbers and the series for the studentized range.
    if room is None:
        if kind == 'Q':
            room = 6e-8
        elif 0 < abs(value) < 1e-15:
            room = abs(value) if abs(value) < 2.3e-308 else abs(value) * 1e-9
        else:
            room = 2e-15 + abs(value) * 1e-9
    return math.isfinite(actual) and abs(actual - value) <= room

session = Session()
counts = Counter()
failures = []
try:
    for line in (fixtures / 'cases.txt').read_text().splitlines():
        kind, case, action, x, df, df2 = line.split('\t')
        if action != 'p' or (x == '-' and kind in ('Rho', 'Kendall')):
            counts['unsupported Windows input route'] += 1
            continue
        operation = 'Distribution' + {'Z': 'Normal', 'ChiSq': 'ChiSquare', 'Rho': 'Spearman'}.get(kind, kind)
        inputs = {name: number(text) for name, text in [('x', x), ('df', df), ('df2', df2)] if text != '-'}
        wanted = expected[kind + '|' + case]
        ident, state = session.start(operation)
        try:
            session.request(action='answer', id=ident, token=state['token'], value=inputs)
            result = session.wait(ident)
            if any(value == 'error' for value, _ in wanted.values()):
                ok = result['state'] != 'complete' and bool(result.get('error') or result.get('prompt', {}).get('error'))
                if not ok:
                    failures.append((line, 'expected input rejection', result))
                counts['rejections'] += 1
                continue
            if result['state'] != 'complete':
                failures.append((line, 'expected a result', result))
                continue
            values = result['values']
            boxes = {'txtUp': values['upper']}
            if kind in ('Binomial', 'Poisson'):
                boxes.update(txtLp=values['mass'], txt2p=values['lower'])
            elif kind not in ('Rho', 'Kendall'):
                boxes['txtLp'] = values['lower']
                if kind in ('Z', 'T'):
                    boxes['txt2p'] = 2 * min(values['lower'], values['upper'])
            for box, (value, room) in wanted.items():
                if box not in boxes:
                    continue  # Windows-only score/value display, not a probability.
                counts['probabilities'] += 1
                if not agrees(kind, boxes[box], value, room):
                    failures.append((line, box, boxes[box], value, room))
            counts['completed cases'] += 1
        finally:
            session.close(ident)
    print(dict(counts), flush=True)
    for failure in failures[:20]:
        print('FAIL', failure, flush=True)
    assert not failures, f'{len(failures)} calculator fixture failures'
    print('PASS: all supported forward fixtures and input rejections through Mac forms', flush=True)
finally:
    session.finish()
