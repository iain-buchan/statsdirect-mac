"""The local check behind AI Assist's distribution cards (Windows 5.3.22, pull requests 40-42), through the built
statsdirect_measurement_check entry (FullEngine/MeasurementChecks.cs) and the line driver.

- Codex's base-R fixtures (Tests/Fixtures/distribution: 26 paired and 5 independent cases), each sent as the pane sends it. The count,
  Shapiro-Wilk W and P, variation, the quartiles, far-out count, skewness and excess kurtosis Windows keeps above 100 pairs, the fence,
  skew and heavy-tail warnings and the suggested branch are compared with the tolerance of the preflight's own driver (2e-10 relative
  to the expected value, absolute below 1). The branches the pane may accept follow from the size the reply reports, with its conflict
  text; the card's lines and recommendation are rendered here from the reply's values with the Windows texts; and a paired case gives
  the same reply from the grid's snapshot file as inline.
- The oracle's overflow refusal, and a difference that is the missing marker or beyond the range of a double.
- PEFR's card, and a card with the shape lines of more than 100 pairs, in en-GB and de-DE; a culture .NET does not know; a selection
  the grid could not read; requests in no recognised form.
- A full worksheet column of differences through a snapshot.
- Each block copied from Windows is still the lines it cites in FullEngine/Upstream, and the fixtures' fence table is the pinned one.
- When R is installed, the oracle regenerates its four tables byte for byte.
"""
import csv
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'Tests'))
from r_runtime import rscript

DRIVER = ROOT / 'Tests/engine-driver'   # compiled by test.sh
LIBRARY = Path(os.environ.get('STATSDIRECT_TEST_ENGINE', str(ROOT / 'FullEngine/publish/StatsDirectEngine.dylib')))
FIXTURES = ROOT / 'Tests/Fixtures/distribution'
TABLES = ('paired-input.tsv', 'paired-expected.tsv', 'independent-input.tsv', 'independent-expected.tsv')
COPIES = ROOT / 'FullEngine/MeasurementChecks.cs'
UPSTREAM = ROOT / 'FullEngine/Upstream'

# The Windows texts (StatsDirectUI/UI/frmSpreadsheetGear.MeasurementDiagnostics.cs and UI/Learning/ScriptAIPane.WorksheetAnalysis.cs).
TOO_LARGE = 'A paired difference is too large to check. Rescale the measurements and try again.'
CONFLICT = {  # (paired, more than 100)
    (True, True): 'The local check found more than 100 complete pairs. Choose the large-sample route for the mean difference or the non-normal route for Wilcoxon signed ranks.',
    (True, False): 'The local check found at most 100 complete pairs. Choose the branch for the distribution of the differences.',
    (False, True): 'The local check found more than 100 observations in each sample. Review their distributions before choosing a method.',
    (False, False): 'The local check found at most 100 observations in at least one sample. Choose the branch for the distributions within groups.'}
METHODS = {True: {'large': 'TPaired', 'normal': 'TPaired', 'non-normal': 'Wilcoxon'},
           False: {'large': 'ZUnpaired', 'normal': 'TUnpaired', 'non-normal': 'MannWhitney'}}
ADVICE = {
    True: {'large': 'The large-sample branch recommends the paired t test for the mean difference.',
           'normal': 'The paired t test addresses the mean difference. This branch assumes approximately normal differences.',
           'non-normal': 'The signed-rank test concerns a shift in location and assumes roughly symmetric differences. If the aim is specifically to estimate or test the mean difference, consider whether this answers your question.'},
    False: {'large': 'The Help routes large, well-behaved samples to the two-sample Z test for the difference in means.',
            'normal': 'The unpaired t test compares means. Consider the spread in each group before using an equal-variance result.',
            'non-normal': 'Mann–Whitney compares relative ordering between groups. Use that question to decide whether it fits your goal.'}}
NORMAL = 'A paired t test answers the question about the mean difference. Shapiro–Wilk found no clear departure from normality, and the shape checks flagged no unusual differences. With this sample, those checks provide limited evidence.'
# The Mac's own refusal of a request the pane never sends.
UNRECOGNISED = 'The measurements to check are not in a recognised form.'

checks = 0
def check(ok, what):
    global checks
    if not ok: raise AssertionError('FAIL ' + what)
    checks += 1; print('PASS', what, flush=True)

def not_json(constant): raise AssertionError('FAIL the reply holds %s, which JSON cannot' % constant)
class Entry:
    """statsdirect_measurement_check through Tests/engine-driver: one request per line, one reply per line."""
    def __init__(self):
        self.p = subprocess.Popen([str(DRIVER), str(LIBRARY.resolve()), 'statsdirect_measurement_check'],
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, encoding='utf-8')
    def text(self, line):
        self.p.stdin.write(line + '\n'); self.p.stdin.flush()
        reply = self.p.stdout.readline()
        if not reply: raise AssertionError('FAIL the engine driver stopped (exit %s)' % self.p.wait())
        return json.loads(reply, parse_constant=not_json)
    def __call__(self, request): return self.text(json.dumps(request, allow_nan=False))
    def card(self, request):
        reply = self(request)
        if 'error' in reply: raise AssertionError('FAIL the entry refused %s: %s' % (json.dumps(request)[:300], reply['error']))
        return reply
    def close(self): self.p.stdin.close(); self.p.wait()

def paired(differences, culture='en-GB'):
    return {'design': 'paired', 'culture': culture, 'separateSamples': False, 'read': {'differences': differences}}
def from_snapshot(path, pairs):
    return {'design': 'paired', 'culture': 'en-GB', 'separateSamples': False, 'read': {'snapshot': str(path), 'pairs': pairs}}
def independent(first, second, separate):
    sample = lambda values: {'count': len(values), 'values': values if len(values) <= 100 else []}
    return {'design': 'independent', 'culture': 'en-GB', 'separateSamples': separate, 'read': {'samples': [sample(first), sample(second)]}}
def snapshot(path, differences):
    """The differences as the grid posts them: a snapshot (FullEngine/WorkbookIO.cs:83-95) of one sheet with one column of numbers."""
    pad = lambda data, size: data + b'\0' * (-len(data) % size)
    name, n = b'Differences', len(differences)
    data = pad(struct.pack('<5I', 0x4C4F4353, 1, 1, 0, len(name)) + name, 4) + struct.pack('<5I', 1, 0, n, 0, 0)
    data = pad(data + struct.pack('<%dI' % n, *range(n)) + bytes([1]) * n, 8) + struct.pack('<%dd' % n, *differences)
    path.write_bytes(data)
    return path

def table(name):
    with open(FIXTURES / name, newline='', encoding='utf-8') as file: return list(csv.DictReader(file, delimiter='\t'))
def number(text): return float(text) if text else None
def columns(name):
    """Each case's rows as (first, second), None for an empty cell (missing in R)."""
    cases = {}
    for row in table(name): cases.setdefault(row['case'], []).append((number(row['first']), number(row['second'])))
    return cases
def near(actual, expected):
    """The comparison of the preflight's engine driver: both unavailable, or within 2e-10 of the expected value relative to it."""
    if actual is None or expected is None: return actual is None and expected is None
    return abs(actual - expected) <= 2e-10 * max(1.0, abs(expected))
def allowed(reply):
    """The branches the pane accepts: all three while the size is unknown; otherwise not the branch of the other size, which shows the
    conflict text instead. Non-normal is always accepted."""
    if reply['largeSample'] is None: return {'large', 'normal', 'non-normal'}
    return {'large', 'non-normal'} if reply['largeSample'] else {'normal', 'non-normal'}

# The card's text rendered from the reply's values, as Windows' AddDetails and SuggestPairedBranch write it
# (ScriptAIPane.WorksheetAnalysis.cs:88-148), in the invariant number format.
def g(x, digits):
    """.NET's G3 and G4 for these values: C's %G, the shorter of fixed and E notation with at least two exponent digits."""
    return '%.*G' % (digits, x)
def paired_lines(v):
    n, large = v['count'], v['count'] > 100
    line = 'Local check found 1 complete pair' if n == 1 else 'Local check found %d complete pairs' % n
    if v['w'] is not None and v['p'] is not None: line += '. Shapiro–Wilk W = %s, P = %s.' % (g(v['w'], 4), g(v['p'], 4))
    elif not large: line += '. Shapiro–Wilk needs at least three finite differences with some variation.'
    lines, shape = [line], v['shape']
    if large and shape:
        lines.append('Shape check · %d beyond the 3× IQR fences' % shape['farOutCount'])
        if shape['skewness'] is not None and shape['excessKurtosis'] is not None:
            lines.append('Skewness %s · Excess kurtosis %s' % (g(shape['skewness'], 3), g(shape['excessKurtosis'], 3)))
    return lines
def sample_lines(v, separate):
    lines = [] if separate else ['Selected columns, if they hold the two samples separately:']
    for number, sample in ((1, v['first']), (2, v['second'])):
        normality = '. Shapiro–Wilk W = %s, P = %s.' % (g(sample['w'], 4), g(sample['p'], 4)) if sample['w'] is not None and sample['p'] is not None else ''
        lines.append('Column %d: n = %d' % (number, sample['count']) + normality)
    return lines
def recommendation(v):
    n, shape = v['count'], v['shape']
    if n < 3: return None, 'There are too few complete pairs to assess the distribution. Check the selected measurements before choosing.'
    if not v['hasVariation']: return None, 'All the paired differences are the same, leaving zero variation for the test. Check the selected measurements.'
    if n > 100:
        signals = [signal for signal, shown in (('far-out differences', v['hasPotentialOutlier']), ('pronounced skew', v['hasSkewSignal']),
                                                ('heavy tails', bool(shape and shape['hasHeavyTails']))) if shown]
        if not signals: return 'large', 'There are more than 100 complete pairs and the shape checks found no substantial departure. A paired t test answers the question about the mean difference.'
        signed_ranks = ('Wilcoxon signed ranks addresses a shift in location and assumes roughly symmetric differences. Pronounced skew makes that assumption doubtful.'
                        if v['hasSkewSignal'] else 'Consider Wilcoxon signed ranks for a shift in location if the differences look roughly symmetric.')
        return None, 'The shape checks flagged ' + ', '.join(signals) + '. ' + signed_ranks + ' A paired t test still answers the question about the mean difference. Review any influential differences before choosing.'
    if v['hasPotentialOutlier']: return None, 'The box-plot check flagged an unusually distant difference. Review whether it reflects a data error or strongly affects the mean before choosing.'
    if v['hasSkewSignal']: return None, 'The skewness check flagged an uneven shape. Examine the differences before choosing. Signed-rank inference about a shift in location requires roughly symmetric differences.'
    if v['p'] is None: return None, 'The normality check could not assess these differences. Look at their shape before choosing.'
    if v['p'] < 0.05: return 'non-normal', 'Shapiro–Wilk found evidence of non-normal differences. Consider Wilcoxon signed-rank if the differences look roughly symmetric and a shift in location answers your question.'
    return 'normal', NORMAL
def quartile(ordered, fraction):
    """InterpolatedQuartile (frmSpreadsheetGear.MeasurementDiagnostics.cs:162-173), R's type 6."""
    position = min(max(fraction * (len(ordered) + 1) - 1.0, 0.0), len(ordered) - 1)
    lower = int(position); remainder = position - lower
    return ordered[lower] if remainder == 0.0 else ordered[lower] + remainder * (ordered[lower + 1] - ordered[lower])
def mismatches(comparisons, reply):
    wrong = [what for what, ok in comparisons.items() if not ok]
    return ': ' + ', '.join(wrong) + ' differ in ' + json.dumps(reply, ensure_ascii=False) if wrong else ''

(ROOT / '.build').mkdir(exist_ok=True)
entry = Entry()
with tempfile.TemporaryDirectory(prefix='measurement-check-', dir=ROOT / '.build') as scratch:
    folder = Path(scratch)
    # --- The paired fixtures: the complete pairs' differences, first column minus second, inline and from a snapshot
    differences = {name: [a - b for a, b in rows if a is not None and b is not None] for name, rows in columns('paired-input.tsv').items()}
    for row in table('paired-expected.tsv'):
        name, n = row['case'], int(row['n'])
        reply = entry.card(paired(differences[name]))
        typed = entry.card(from_snapshot(snapshot(folder / (name + '.snapshot'), differences[name]), len(differences[name])))
        v, large = reply['values'], n > 100
        shape = v['shape']
        comparisons = {
            'n': v['count'] == n, 'W': near(v['w'], number(row['W'])), 'P': near(v['p'], number(row['P'])),
            'variation': v['hasVariation'] == (row['varying'] == 'TRUE'),
            'fence warning': v['hasPotentialOutlier'] == (row['fenceWarning'] == 'TRUE'),
            'skew warning': v['hasSkewSignal'] == (row['skewWarning'] == 'TRUE'),
            'heavy-tail warning': bool(shape and shape['hasHeavyTails']) == (row['heavyTailWarning'] == 'TRUE'),
            'shape': (shape is not None) == (row['Q1'] != ''),
            'suggested branch': reply['suggestedBranch'] == (row['suggestedBranch'] or None),
            'allowed branches': reply['largeSample'] == large and allowed(reply) == set(row['allowed'].split(',')) and reply['conflict'] == CONFLICT[True, large],
            'card': reply['kind'] == 'paired-interval' and reply['sizeKnown'] is True and reply['canCheck'] is False
                    and reply['methods'] == METHODS[True] and reply['advice'] == ADVICE[True],
            'lines': reply['diagnostics'] == paired_lines(v),
            'recommendation': (reply['suggestedBranch'], reply['recommendation']) == recommendation(v),
            'snapshot reply': typed == reply}
        if shape and row['Q1'] != '':
            comparisons.update({'Q1': near(shape['lowerQuartile'], number(row['Q1'])), 'Q3': near(shape['upperQuartile'], number(row['Q3'])),
                                'far out': shape['farOutCount'] == int(row['farOut']), 'skewness': near(shape['skewness'], number(row['skewness'])),
                                'excess kurtosis': near(shape['excessKurtosis'], number(row['excessKurtosis']))})
        check(not mismatches(comparisons, reply), 'paired %s (n = %d) agrees with R, inline and from a snapshot; its card is Windows\'%s'
              % (name, n, mismatches(comparisons, reply)))

    # --- The independent fixtures: each column's usable values, before and after the user confirms them as separate samples
    independent_cases = columns('independent-input.tsv')
    for row in table('independent-expected.tsv'):
        name, large = row['case'], row['large'] == 'TRUE'
        first, second = [a for a, _ in independent_cases[name] if a is not None], [b for _, b in independent_cases[name] if b is not None]
        before, after = entry.card(independent(first, second, False)), entry.card(independent(first, second, True))
        a, b = after['values']['first'], after['values']['second']
        comparisons = {
            'n1': a['count'] == int(row['n1']), 'W1': near(a['w'], number(row['W1'])), 'P1': near(a['p'], number(row['P1'])),
            'n2': b['count'] == int(row['n2']), 'W2': near(b['w'], number(row['W2'])), 'P2': near(b['p'], number(row['P2'])),
            'unconfirmed size': before['largeSample'] is None and before['conflict'] is None and before['sizeKnown'] is False and before['canCheck'] is True
                                and allowed(before) == {'large', 'normal', 'non-normal'},
            'separate samples': after['largeSample'] == large and after['conflict'] == CONFLICT[False, large] and after['sizeKnown'] is True
                                and after['canCheck'] is False and allowed(after) == set(row['allowedWhenSeparate'].split(',')),
            'lines': before['diagnostics'] == sample_lines(before['values'], False) and after['diagnostics'] == sample_lines(after['values'], True),
            'values': before['values'] == after['values'],
            'card': all(r['kind'] == 'independent-interval' and r['methods'] == METHODS[False] and r['advice'] == ADVICE[False]
                        and 'suggestedBranch' not in r and 'recommendation' not in r for r in (before, after))}
        check(not mismatches(comparisons, after), 'independent %s (%d and %d values) agrees with R, before and after the columns are confirmed as separate samples%s'
              % (name, len(first), len(second), mismatches(comparisons, after)))

    # --- Differences the Windows check refuses as too large: the oracle's overflow, the missing marker and a number beyond a double
    for what, reply in (('the oracle\'s 1e308 minus -1e308, from a snapshot', entry(from_snapshot(snapshot(folder / 'overflow.snapshot', [1e308 - -1e308]), 1))),
                        ('a difference equal to the missing marker (double.MinValue)', entry(paired([12.0, -1.7976931348623157e308]))),
                        ('1e400, beyond the range of a double', entry.text('{"design":"paired","culture":"en-GB","read":{"differences":[1,2,1e400]}}'))):
        check(reply == {'error': TOO_LARGE}, 'refused with the Windows text: ' + what)

    # --- Cards in the user's culture
    for culture, w, p in (('en-GB', '0.9393', '0.5746'), ('de-DE', '0,9393', '0,5746')):
        reply = entry.card(paired(differences['pefr'], culture))
        check(reply['diagnostics'] == ['Local check found 9 complete pairs. Shapiro–Wilk W = %s, P = %s.' % (w, p)]
              and reply['suggestedBranch'] == 'normal' and reply['recommendation'] == NORMAL,
              'PEFR\'s card in %s: W = %s, P = %s (G4), the normal branch suggested, with the Windows reason' % (culture, w, p))
    for culture, skewness, kurtosis in (('en-GB', '8.46', '77.9'), ('de-DE', '8,46', '77,9')):
        reply = entry.card(paired(differences['late_outlier_102'], culture))
        check(reply['diagnostics'] == ['Local check found 102 complete pairs', 'Shape check · 1 beyond the 3× IQR fences',
                                       'Skewness %s · Excess kurtosis %s' % (skewness, kurtosis)]
              and reply['suggestedBranch'] is None and reply['recommendation'] == 'The shape checks flagged far-out differences, pronounced skew, heavy tails. Wilcoxon signed ranks addresses a shift in location and assumes roughly symmetric differences. Pronounced skew makes that assumption doubtful. A paired t test still answers the question about the mean difference. Review any influential differences before choosing.',
              'late_outlier_102\'s card in %s: the shape lines of more than 100 pairs (G3), no suggested branch, the three signals' % culture)
    reference = entry.card(paired(differences['pefr'], ''))
    check(all(entry.card(paired(differences['pefr'], culture)) == reference for culture in ('!!', 'not a culture'))
          and reference['diagnostics'][0].endswith('W = 0.9393, P = 0.5746.'),
          'a culture .NET does not know, or none, formats as the invariant culture')

    # --- Five finite differences whose range overflows a double: Shapiro-Wilk cannot run, so Windows' normality reason applies
    reply = entry.card(paired([1e308, -1e308, 0.0, 5e307, -5e307]))
    check(reply['diagnostics'] == ['Local check found 5 complete pairs. Shapiro–Wilk needs at least three finite differences with some variation.']
          and reply['suggestedBranch'] is None and reply['recommendation'] == 'The normality check could not assess these differences. Look at their shape before choosing.',
          'five differences spanning more than a double: no Shapiro-Wilk, and the normality check cannot assess them')

    # --- A selection the grid could not read: Windows' unread decision, whatever the confirmation says
    for design, is_paired in (('paired', True), ('independent', False)):
        reply = entry.card({'design': design, 'culture': 'en-GB', 'separateSamples': True, 'read': None})
        check(reply == {'kind': design + '-interval', 'sizeKnown': False, 'canCheck': True, 'largeSample': None, 'methods': METHODS[is_paired],
                        'advice': ADVICE[is_paired], 'conflict': None, 'values': None},
              'an unread %s selection gives the card with the check button and no evidence' % design)

    # --- Requests the pane never sends
    for what, request, error in (
            ('a design other than paired or independent', {'design': 'Paired', 'read': None}, 'Set design to paired or independent.'),
            ('samples for paired measurements', {'design': 'paired', 'read': {'samples': [{'count': 0, 'values': []}] * 2}}, UNRECOGNISED),
            ('a snapshot holding fewer differences than the pairs counted', from_snapshot(folder / 'pefr.snapshot', 10), UNRECOGNISED),
            ('a column of 3 values counted as 4', {'design': 'independent', 'read': {'samples': [{'count': 4, 'values': [1, 2, 3]}, {'count': 0, 'values': []}]}}, UNRECOGNISED),
            ('values sent for a column of more than 100', {'design': 'independent', 'read': {'samples': [{'count': 101, 'values': [1]}, {'count': 0, 'values': []}]}}, UNRECOGNISED)):
        check(entry(request) == {'error': error}, 'refused: ' + what)

    # --- Every row of a worksheet, from one snapshot as the grid posts it
    column = [((i * 7919) % 10007) / 100 for i in range(1048576)]
    path = snapshot(folder / 'full-height.snapshot', column)
    start = time.monotonic()
    reply = entry.card(from_snapshot(path, len(column)))
    elapsed = time.monotonic() - start
    v, ordered = reply['values'], sorted(column)
    check(v['count'] == len(column) and v['shape']['lowerQuartile'] == quartile(ordered, 0.25) and v['shape']['upperQuartile'] == quartile(ordered, 0.75)
          and v['shape']['farOutCount'] == 0 and reply['suggestedBranch'] == 'large' and reply['diagnostics'] == paired_lines(v) and elapsed < 30,
          '%d differences from one snapshot: the quartiles, no far-out values and the large-sample branch, in %.1f s' % (len(column), elapsed))
entry.close()

# --- The Windows code copied into FullEngine/MeasurementChecks.cs: each block between "// windows-copy begin <file>:<first>-<last>" and
# "// windows-copy end" is those lines of the pinned Windows source, line for line with leading and trailing white space trimmed, so a
# change on Windows shows here at the next engine pin.
MARK = re.compile(r'\s*// windows-copy begin (\S+):(\d+)(?:-(\d+))?\s*$')
blocks, block = [], None
for at, line in enumerate(COPIES.read_text(encoding='utf-8').split('\n'), 1):
    if block is None:
        if (m := MARK.match(line)): block = {'file': m.group(1), 'first': int(m.group(2)), 'last': int(m.group(3) or m.group(2)), 'at': at, 'lines': []}
    elif line.strip() == '// windows-copy end': blocks.append(block); block = None
    elif MARK.match(line): check(False, 'FullEngine/MeasurementChecks.cs:%d opens a copied block before the one at line %d is closed' % (at, block['at']))
    else: block['lines'].append(line.strip())
check(block is None and len(blocks) > 0, 'FullEngine/MeasurementChecks.cs marks %d blocks copied from Windows, each closed' % len(blocks))
for b in blocks:
    source = [line.strip() for line in (UPSTREAM / b['file']).read_text(encoding='utf-8').split('\n')]
    cited, copied = source[b['first'] - 1:b['last']], b['lines']
    where = 'FullEngine/MeasurementChecks.cs:%d, %s:%d-%d' % (b['at'], b['file'], b['first'], b['last'])
    if copied == cited:
        check(True, where + ' is the Windows source unchanged')
        continue
    moved = [i + 1 for i in range(len(source) - len(copied) + 1) if source[i:i + len(copied)] == copied]
    if moved: detail = 'the copied lines are now %s:%d-%d on Windows; cite those' % (b['file'], moved[0], moved[0] + len(copied) - 1)
    else:
        k = next((i for i, (x, y) in enumerate(zip(copied, cited)) if x != y), min(len(copied), len(cited)))
        detail = ('Windows line %d reads %r, the copy %r' % (b['first'] + k, cited[k], copied[k]) if k < min(len(copied), len(cited))
                  else 'the copy has %d lines, the cited range %d' % (len(copied), len(cited)))
        detail += '; copy the changed Windows code again and check its tests'
    check(False, where + ': ' + detail)
inside = '\n'.join(line for b in blocks for line in b['lines'])
members = ('record MeasurementDistributionDiagnostics(', 'record IndependentSampleDiagnostics(', 'record PairedDifferenceDiagnostics(',
           'record PairedDifferenceShape(', 'class MeasurementAccumulator', 'PairedDifferenceDiagnostics SummarizePaired(', 'double InterpolatedQuartile(',
           'record IntervalDecision(', 'string Method(string branch)', 'string Advice(string branch)', 'string Conflict(bool large)',
           'void AddDetails(JsonObject card)', 'SuggestPairedBranch(PairedDifferenceDiagnostics pairs)', 'string NormalityText(',
           'IntervalDecision.SuggestPairedBranch(pairs);', 'if (RunRecord.Missing(difference))')
check(all(member in inside for member in members), 'the records, summaries, row check and card logic the entry runs are all inside copied blocks')
check((FIXTURES / 'paired-outlier-fence.csv').read_bytes() == (UPSTREAM / 'tests/Learning/paired-outlier-fence.csv').read_bytes(),
      'the oracle\'s fence table is the pinned Windows tests/Learning/paired-outlier-fence.csv')

# --- The oracle itself: base R regenerates the four tables exactly. The script finds the fence table beside itself through Rscript's
# --file argument, which cannot hold a space, so it runs by its bare name in its own folder, writing to a folder named relative to it.
try:
    r = rscript()
except SystemExit as missing:
    print('SKIP regenerating the fixtures in R:', missing, flush=True)
else:
    with tempfile.TemporaryDirectory(prefix='measurement-oracle-', dir=ROOT / '.build') as scratch:
        out = Path(scratch) / 'tables'
        run = subprocess.run([r, '--vanilla', 'distribution-oracle.R', os.path.relpath(out, FIXTURES)], cwd=FIXTURES, capture_output=True, text=True, timeout=300)
        check(run.returncode == 0 and 'PASS: 26 paired and 5 independent fixtures, plus paired-overflow rejection.' in run.stdout,
              'the oracle\'s own checks pass in %s%s' % (r, '' if run.returncode == 0 else ':\n' + run.stdout + run.stderr))
        differing = [name for name in TABLES if not (out / name).is_file() or (out / name).read_bytes() != (FIXTURES / name).read_bytes()]
        check(not differing, 'R regenerates the four fixture tables byte for byte' + (': ' + ', '.join(differing) + ' differ' if differing else ''))
print('PASS: %d measurement check checks' % checks, flush=True)
