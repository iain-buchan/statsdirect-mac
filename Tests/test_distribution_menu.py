"""Replay upstream forward-calculator fixtures through actual Mac forms/reports.

The Mac form takes a statistic, not inverse probabilities or rank-score input.
Those Windows-only input routes are counted as unsupported, not reported passed.
The unchanged upstream numerical inverse/range tests run in UpstreamSuites.
"""
from collections import Counter
from decimal import Decimal, ROUND_HALF_UP
from html.parser import HTMLParser
import json
import math
import re
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


class Text(HTMLParser):
    def __init__(self, source):
        super().__init__()
        self.parts = []
        self.feed(source.split('<svg')[0])
        self.text = ' '.join(' '.join(self.parts).split())

    def handle_data(self, value):
        self.parts.append(value)


def tails(result):
    """The probabilities the report line gives to 15 significant figures (the calculation's only result, as on Windows)."""
    text = Text(result['html']).text
    found = {}
    for key, label in [('upper', 'Upper tail'), ('lower', 'Lower tail'), ('mass', 'Probability of exactly this count'), ('two_sided', 'Two-sided P')]:
        match = re.search(label + r' = (\S+)', text)
        if match:
            found[key] = float(match.group(1))
    return found


# The Windows calculator records its boxes as inputs of the run (ctlPDF.Fill through Box), each with the number the box shows: a value
# to 15 figures (Xval15), a probability to 15 decimal places or to 15 figures below 1e-15 (Pval15; "< 1E-15" where a probability of 0
# cannot be shown, read back as the machine epsilon; 1 from 0.999999999999999), the studentized range's tails to 7 places (PFromQ).
# These mirror that rounding, allowing one unit in the last place for a tie rounded the other way.
EPSILON = 2.220446049250313e-16


def rounded(x, places):
    return float(Decimal(x).quantize(Decimal(1).scaleb(-places), rounding=ROUND_HALF_UP))


def significant(x, figures):
    d = Decimal(x)
    return float(d.quantize(Decimal(1).scaleb(d.adjusted() - figures + 1), rounding=ROUND_HALF_UP)) if x != 0 else 0.0


def shown_probability(p, allow_zero=True):
    if p < 1e-15:
        return (significant(p, 15), abs(p) * 1e-14) if allow_zero else (EPSILON, 0)
    if p >= 0.999999999999999:
        return 1.0, 0
    return rounded(p, 15), 1.5e-15


def shown_value(x):
    return (significant(x, 7), abs(x) * 1e-6) if abs(x) > 1e15 else (significant(x, 15), abs(x) * 1e-14)


def shown_seven(p):
    if p == 0:
        return 0.0, 0
    if abs(p) < 1e-7 or abs(p) > 1e15:
        return significant(p, 7), abs(p) * 1e-6
    return rounded(significant(p, 15), 7), 1.5e-7


def windows_boxes(kind, inputs, shown):
    """The settings the Windows calculator's record holds for this distribution (ctlPDF.SetVisibility shows the boxes), with the value each shows."""
    boxes = {}
    if kind != 'Poisson':
        boxes['value'] = shown_value(inputs['x'])
    if kind != 'Z':
        boxes['df'] = shown_value(inputs['df'])
    if kind in ('F', 'Q', 'Binomial', 'Poisson', 'NonCentralT'):
        boxes['df2'] = shown_value(inputs['df2'])
    elif kind == 'Kendall':
        boxes['df2'] = (float(round(inputs['x'] * inputs['df'] * (inputs['df'] - 1) / 2)), 0)   # S, worked out of tau as Convert.ToInt32 does
    elif kind == 'Rho':
        boxes['df2'] = (float(round((1 - inputs['x']) * inputs['df'] * (inputs['df'] ** 2 - 1) / 3 / 2)), 0)   # Hotelling-Pabst T out of rho
    zero_shown = kind not in ('Rho', 'Kendall')
    if kind in ('Z', 'T'):
        boxes.update(lower=shown_probability(shown['lower']), upper=shown_probability(shown['upper']), two_sided=shown_probability(shown['two_sided']))
    elif kind == 'NonCentralT':
        boxes.update(lower=shown_probability(shown['lower']), upper=shown_probability(shown['upper']))
    elif kind == 'Q':
        boxes.update(lower=shown_seven(shown['lower']), upper=shown_seven(shown['upper']))
    elif kind in ('Binomial', 'Poisson'):   # the boxes hold the probabilities of exactly, at least and at most the count
        boxes.update(lower=shown_probability(shown['mass']), upper=shown_probability(shown['upper']), two_sided=shown_probability(shown['lower']))
    else:
        boxes['upper'] = shown_probability(shown['upper'], zero_shown)
    return boxes


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
            # The probabilities to the engine's precision come from the report line, the calculation's only result (as on Windows).
            shown = tails(result)
            boxes = {'txtUp': shown['upper']}
            if kind in ('Binomial', 'Poisson'):
                boxes.update(txtLp=shown['mass'], txt2p=shown['lower'])
            elif kind not in ('Rho', 'Kendall'):
                boxes['txtLp'] = shown['lower']
                if kind in ('Z', 'T'):
                    boxes['txt2p'] = shown['two_sided']
            for box, (value, room) in wanted.items():
                if box not in boxes:
                    continue  # Windows-only score/value display, not a probability.
                counts['probabilities'] += 1
                if not agrees(kind, boxes[box], value, room):
                    failures.append((line, box, boxes[box], value, room))
            # The record of the run holds the boxes as the Windows calculator records them: the same names, each with the number the box shows.
            recorded = json.loads(result['record'])['parameters']
            expected_boxes = windows_boxes(kind, inputs, shown)
            if set(recorded) != set(expected_boxes) | {'asked'} or recorded['asked'] != 'calculate':
                failures.append((line, 'recorded boxes', sorted(recorded), sorted(expected_boxes) + ['asked']))
            for name, (value, room) in expected_boxes.items():
                if name in recorded and not (math.isfinite(recorded[name]) and abs(recorded[name] - value) <= room):
                    failures.append((line, 'recorded ' + name, recorded[name], value, room))
            counts['recorded boxes'] += len(expected_boxes)
            counts['completed cases'] += 1
        finally:
            session.close(ident)
    print(dict(counts), flush=True)
    for failure in failures[:20]:
        print('FAIL', failure, flush=True)
    assert not failures, f'{len(failures)} calculator fixture failures'
    print('PASS: all supported forward fixtures and input rejections through Mac forms; every run\'s record holds the boxes as the Windows calculator records them', flush=True)
finally:
    session.finish()
