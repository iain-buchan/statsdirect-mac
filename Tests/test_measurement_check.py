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
- Each block copied from Windows is still the lines it cites in FullEngine/Upstream; each segment of the Windows code the Mac rewrote
  instead (MIRRORS) still stands, line for line, in its pinned Windows file; and the fixtures' fence table is the pinned one.
- When R is installed, the oracle regenerates its four tables with the committed cases, rows, counts, flags and branches and every other
  number within the same tolerance; in R 4.6.1, which wrote them, byte for byte.
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
# change to a copied line, or the lines moving, shows here at the next engine pin. MIRRORS below covers the code the Mac rewrote.
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

# --- The Windows code the Mac rewrote rather than copied: each segment is whole lines of the pinned Windows file it is listed under,
# with the Mac code that mirrors it. A segment must still stand in that file, its lines together and each as listed once leading and
# trailing white space is trimmed (as the copied blocks are compared), wherever it now is. Lines moving and edits elsewhere in the file
# pass; a change to a segment fails here at the next engine pin, naming the Mac code to review. After that review, copy the segment's
# new Windows lines into MIRRORS.
MIRRORS = {
    'StatsDirectUI/UI/frmSpreadsheetGear.MeasurementDiagnostics.cs': (
        ('LargeSampleThreshold', "Grid/measurement-columns.mjs LARGE_SAMPLE_THRESHOLD, up to which the grid sends a column's values", r'''
            internal sealed record MeasurementDistributionDiagnostics(int Count, double? ShapiroWilkW, double? ShapiroWilkP)
            {
                internal const int LargeSampleThreshold = 100;
            }
            '''),
        ('CheckSelectedPairedDifferences',
         'Grid/measurement-columns.mjs measurementColumns (paired: the rows with both values, the first column minus the '
         'second, the overflow refusal) with SELECTION.paired and TOO_LARGE, and FullEngine/MeasurementChecks.cs '
         'MeasurementDiagnostics.CheckPairedDifferences', r'''
            internal PairedDifferenceDiagnostics CheckSelectedPairedDifferences()
            {
                var differences = new List<double>();
                double minimum = double.PositiveInfinity, maximum = double.NegativeInfinity;
                ReadSelectedMeasurementRows("Select two adjacent, visible columns of matched measurements in one worksheet range.", (before, after) =>
                {
                    if (RunRecord.Missing(before) || RunRecord.Missing(after)) return;
                    double difference = before - after;
                    if (RunRecord.Missing(difference))
                        throw new InvalidOperationException("A paired difference is too large to check. Rescale the measurements and try again.");
                    differences.Add(difference);
                    minimum = Math.Min(minimum, difference);
                    maximum = Math.Max(maximum, difference);
                });
                return SummarizePaired(differences, minimum, maximum);
            }
            '''),
        ('CheckSelectedIndependentSamples',
         "Grid/measurement-columns.mjs measurementColumns (independent: each column's usable values on their own) with "
         'SELECTION.independent, and FullEngine/MeasurementChecks.cs Samples', r'''
            internal IndependentSampleDiagnostics CheckSelectedIndependentSamples()
            {
                var first = new MeasurementAccumulator();
                var second = new MeasurementAccumulator();
                ReadSelectedMeasurementRows("Select the two adjacent, visible sample columns in one worksheet range.", (left, right) =>
                {
                    if (!RunRecord.Missing(left)) first.Add(left);
                    if (!RunRecord.Missing(right)) second.Add(right);
                });
                return new IndependentSampleDiagnostics(first.Summarize(), second.Summarize());
            }
            '''),
        ('ReadSelectedMeasurementRows',
         'Grid/measurement-columns.mjs selectedPair (one area two columns wide), measurementColumns (its first and last '
         "rows, both columns in one pass) and cellValue (a cell as the Mac's analysis reads it)", r'''
            private void ReadSelectedMeasurementRows(string selectionError, Action<double, double> collect) => workbookView.WithLock(() =>
            {
                CheckWorksheetAnalysisReady();
                IRange selection = workbookView.RangeSelection;
                if (selection.AreaCount != 1 || selection.ColumnCount != 2
                    || IsHiddenColumn(selection.Column) || IsHiddenColumn(selection.Column + 1))
                    throw new InvalidOperationException(selectionError);

                IRange used = workbookView.ActiveWorksheet.UsedRange;
                int first = Math.Max(selection.Row, used.Row);
                int last = Math.Min(selection.Row + selection.RowCount, used.Row + used.RowCount) - 1;
                IGetCells grid = this;

                // Both columns use the native numeric reader and the same visible row bounds.
                // A missing value in either column cannot shift the other column for paired calculations.
                const int batchSize = 8192;
                for (int start = first; start <= last; start += batchSize)
                {
                    int end = Math.Min(last, start + batchSize - 1);
                    var (left, rows) = grid.GetCellValues(selection.Column, start, end);
                    var (right, _) = grid.GetCellValues(selection.Column + 1, start, end);
                    for (int row = 0; row < rows; row++)
                        collect(left[row], right[row]);
                }
            });
            '''),
        ('MeasurementAccumulator',
         "Grid/measurement-columns.mjs measurementColumns (independent: a column's values while it has at most 100), and "
         'FullEngine/MeasurementChecks.cs Sample and MeasurementDiagnostics.SummarizeSample', r'''
            private sealed class MeasurementAccumulator
            {
                private readonly List<double> smallSample = new(MeasurementDistributionDiagnostics.LargeSampleThreshold);
                private int count;

                internal void Add(double value)
                {
                    count++;
                    if (count <= MeasurementDistributionDiagnostics.LargeSampleThreshold)
                        smallSample.Add(value);
                }

                internal MeasurementDistributionDiagnostics Summarize()
                {
                    var normality = count <= MeasurementDistributionDiagnostics.LargeSampleThreshold
                        ? Parametric.ShapiroWilkDiagnostics(smallSample.ToArray()) : null;
                    return new MeasurementDistributionDiagnostics(count, normality?.W, normality?.P);
                }
            }
            '''),
    ),
    'StatsDirectUI/UI/frmSpreadsheetGear.WorksheetAnalysis.cs': (
        ('CaptureWorksheetAnalysisTarget',
         "Sources/WorksheetAIAnalysis.swift prepareWorksheetAIAnalysis (an offer's workbook, version and selection, with "
         "the fingerprint of the same moment) and Sources/WorksheetAIPane.swift issueGuidanceToken (a card's "
         'fingerprint)', r'''
            internal WorksheetAnalysisTarget CaptureWorksheetAnalysisTarget(bool workbookShared = false) => workbookView.WithLock(() =>
            {
                CheckWorksheetAnalysisReady();
                if (workbookView.ActiveWorkbook is not IWorkbook book || workbookView.ActiveWorksheet is not IWorksheet sheet)
                    throw new InvalidOperationException("Select a worksheet before asking for an analysis.");
                return new WorksheetAnalysisTarget(this, book, sheet, Text, sheet.Name,
                    workbookView.RangeSelection.Address, LearningVersion, workbookShared);
            });
            '''),
        ('ResolveWorksheetAnalysisTarget (the version and selection compared, and its refusals)',
         'Sources/WorksheetAIAnalysis.swift prepareWorksheetAIAnalysis and continueWorksheetAIAnalysis (an offer only '
         "for its workbook, version and selection, or its card's reading, refused with one text), and "
         'Sources/WorksheetAIPane.swift prepareAnalysis(_:from:), continueAnalysis and cancelAnalysis (a refused offer '
         "goes), answerCard and answerClarification (a card's choices only for its own selection) and readCard (Check "
         'reads the live selection)', r'''
            internal (frmMain Main, WorksheetAnalysisTarget Source) ResolveWorksheetAnalysisTarget(
                WorksheetAnalysisTarget target, bool allowSelectionChanges) => workbookView.WithLock(() =>
            {
                var main = CheckWorksheetAnalysisReady();
                if (target.Grid != this || target.Workbook != workbookView.ActiveWorkbook ||
                    target.Worksheet != workbookView.ActiveWorksheet || target.WorksheetName != target.Worksheet.Name ||
                    target.WorkbookName != Text)
                    throw new InvalidOperationException("The workbook or worksheet changed. Choose the method again.");

                string selection = workbookView.RangeSelection.Address;
                if (target.Version == LearningVersion && target.Selection == selection) return (main, target);
                if (allowSelectionChanges && !target.WorkbookShared)
                    return (main, target with { Selection = selection, Version = LearningVersion });

                string reason = target.WorkbookShared
                    ? "The shared worksheet or selection changed. Ask for a new analysis suggestion."
                    : "The worksheet or selection changed. Choose the method again.";
                throw new InvalidOperationException(reason);
            });
            '''),
        ('CheckWorksheetAnalysisReady',
         'Sources/WorksheetAIPane.swift prepareAnalysis(_:from:) (the workbook in front) and '
         'Sources/WorksheetAIAnalysis.swift continueWorksheetAIAnalysis (no other workbook in front, and no sheet or '
         'modal window open; a cell edit refuses nothing, design D13)', r'''
            private frmMain CheckWorksheetAnalysisReady()
            {
                if (IsDisposed || Disposing || MdiParent is not frmMain main || main.ActiveMdiChild != this)
                    throw new InvalidOperationException("Open the worksheet you asked about before starting an analysis.");
                if (main.InOperation || main.LearningCalculationRunning || workbookView.IsEditing)
                    throw new InvalidOperationException("Finish the current analysis or cell edit before starting an analysis.");
                return main;
            }
            '''),
    ),
    'StatsDirectUI/UI/Learning/ScriptAIPane.WorksheetAnalysis.cs': (
        ('IntervalDecision.ReadSelection',
         'FullEngine/MeasurementChecks.cs Execute (the decision from what the grid read) and '
         "Sources/WorksheetAIPane.swift readCard (separate samples only for the user's Check)", r'''
            internal IntervalDecision ReadSelection(frmSpreadsheetGear grid, bool confirmSeparateSamples = false) => Paired
                ? this with { Pairs = grid.CheckSelectedPairedDifferences() }
                : this with { Columns = grid.CheckSelectedIndependentSamples(), SeparateSamples = confirmSeparateSamples };
            '''),
        ('WorksheetAction.Display up to the feedback',
         'FullEngine/MeasurementChecks.cs IntervalCard.Display (the card without its token, which the pane keeps), and '
         'Sources/WorksheetAIPane.swift drawDistribution (the feedback) and WorksheetAIClarification', r'''
            internal JsonObject Display()
            {
                var card = new JsonObject { ["token"] = Token, ["kind"] = Kind };
                if (Clarification != null)
                {
                    card["dimension"] = Clarification.Dimension;
                    card["question"] = Clarification.Question;
                    card["options"] = new JsonArray(Clarification.Options.Select(option => (JsonNode)new JsonObject
                    {
                        ["id"] = option.Id, ["label"] = option.Label
                    }).ToArray());
                }
                Interval?.AddDetails(card);
                if (Kind == "paired-interval" && Interval?.Pairs is { } pairs)
                {
                    var (branch, reason) = IntervalDecision.SuggestPairedBranch(pairs);
                    card["suggestedBranch"] = branch;
                    card["recommendation"] = reason;
                }
                if (Feedback != null) card["feedback"] = Feedback;
            '''),
        ("Display's interval advice", 'Sources/WorksheetAIPane.swift prepareAnalysis(_:from:) (offerDetails)', r'''
            if (Interval is { } interval) card["intervalAdvice"] = interval.Advice(IntervalBranch);
            '''),
        ('VisibleWorksheetAction', 'Sources/WorksheetAIPane.swift renderGuidance and answerCard (no card while a reply runs or AI is disabled)', r'''
            private WorksheetAction VisibleWorksheetAction =>
                WorksheetMode && pending == null && !service.Tutor.Disabled
                    ? workbookHasData ? worksheetAction ?? chooseMethod : emptyWorkbook
                    : null;
            '''),
        ("RefreshWorksheetContents' emptied workbook", 'Sources/WorksheetAIPane.swift render (an emptied workbook drops its card)', r'''
            if (workbookHasData == hasData) return false;
            workbookHasData = hasData;
            if (!hasData) ClearWorksheetAnalysis();
            return true;
            '''),
        ('QueueWorksheetRefresh, on each selection and content change',
         'Grid/main.tsx (the page posts its AI state once a change settles) and Sources/WorksheetAIPane.swift '
         'worksheetStateChanged', r'''
            private void WorkbookContentsChanged(object sender, EventArgs e) => QueueWorksheetRefresh(contentsChanged: true);
            private void WorkbookSelectionChanged(object sender, EventArgs e) => QueueWorksheetRefresh(contentsChanged: false);

            private void QueueWorksheetRefresh(bool contentsChanged)
            {
                if (disposed || !IsOpen || !view.IsHandleCreated) return;
                workbookContentsDirty |= contentsChanged;
                if (worksheetRefreshQueued) return;
                worksheetRefreshQueued = true;
                view.BeginInvoke(new Action(() =>
                {
                    worksheetRefreshQueued = false;
                    bool refreshContents = workbookContentsDirty;
                    workbookContentsDirty = false;
                    if (disposed || !IsOpen || !WorksheetMode) return;

                    UpdateWorksheetSelection();
                    if (pending != null) return;
                    bool changed = refreshContents && RefreshWorksheetContents();
                    if (RefreshWorksheetGuidance() || changed) Render();
                }));
            }
            '''),
        ('RefreshWorksheetGuidance', 'Sources/WorksheetAIPane.swift worksheetStateChanged and issueGuidanceToken', r'''
            private bool RefreshWorksheetGuidance()
            {
                var updated = WithCurrentWorksheetSelection(worksheetAction);
                if (ReferenceEquals(updated, worksheetAction)) return false;
                worksheetAction = updated;
                return true;
            }
            '''),
        ('ConfirmWorksheetAnalysis',
         "Sources/WorksheetAIPane.swift prepareAnalysis(_:from:) and OfferOrigin (the offer keeps the card's decision "
         'and branch)', r'''
            private static WorksheetAction ConfirmWorksheetAnalysis(WorksheetAnalysisTarget source, WorksheetCommand command,
                IntervalDecision interval = null, string intervalBranch = null)
            {
                var proposal = source.Propose(command);
                string design = command.Operation switch
                {
                    "TPaired" => "paired",
                    "TUnpaired" => "independent",
                    _ => null
                };
                return new WorksheetAction("confirm", proposal.Source, proposal, design, Interval: interval, IntervalBranch: intervalBranch);
            }
            '''),
        ('WithCurrentWorksheetSelection',
         'Sources/WorksheetAIPane.swift worksheetStateChanged and issueGuidanceToken (the card refresh: a new token, no '
         'feedback, an interval card read again)', r'''
            private static WorksheetAction WithCurrentWorksheetSelection(WorksheetAction action, bool newCard = false)
            {
                // Guidance is still a question. A specific proposal keeps the cells and version the user saw.
                if (action?.Kind is not ("choose" or "clarify" or "paired-interval" or "independent-interval"))
                    return action;
                WorksheetAnalysisTarget current;
                try { current = CaptureCurrentGuidanceTarget(action.Source); }
                catch (InvalidOperationException) { return action; }

                if (!newCard && current == action.Source) return action;
                // A delayed click belongs to the selection and evidence the user saw.
                var updated = action with { Source = current, Feedback = null, Token = Guid.NewGuid().ToString("N") };
                if (action.Interval == null) return updated;

                var interval = new IntervalDecision(action.Interval.Paired);
                try { interval = interval.ReadSelection(current.Grid); }
                catch (InvalidOperationException) { /* The user can describe the layout if it cannot be read as two columns. */ }
                return updated with { Interval = interval };
            }
            '''),
        ("ChooseWorksheetAction's token check", 'Sources/WorksheetAIPane.swift answerCard (the token and the live fingerprint, compared first)', r'''
            UpdateWorksheetSelection();
            bool changed = RefreshWorksheetContents();
            if (RefreshWorksheetGuidance() || changed) Render();
            var action = VisibleWorksheetAction;
            if (action == null || action.Token != token) return;
            '''),
        ("ChooseWorksheetAction's paired and independent case", 'Sources/WorksheetAIPane.swift answerCard (paired, independent)', r'''
            case ("choose", "paired" or "independent"):
                grid.ResolveWorksheetAnalysisTarget(action.Source, allowSelectionChanges: false);
                var interval = new IntervalDecision(choice == "paired");
                worksheetAction = WithCurrentWorksheetSelection(
                    new WorksheetAction(interval.Kind, action.Source, Interval: interval), newCard: true);
                break;
            '''),
        ("ChooseWorksheetAction's check case", 'Sources/WorksheetAIPane.swift answerCard (check) and readCard', r'''
            case ("paired-interval" or "independent-interval", "check") when action.Interval.CanCheck:
                try
                {
                    var selected = grid.ResolveWorksheetAnalysisTarget(action.Source, allowSelectionChanges: true).Source;
                    worksheetAction = new WorksheetAction(action.Kind, selected, Interval: action.Interval.ReadSelection(grid, confirmSeparateSamples: true));
                }
                catch (InvalidOperationException ex)
                {
                    ShowIntervalFeedback(action, ex.Message);
                    return;
                }
                break;
            '''),
        ("ChooseWorksheetAction's branch case (the conflict rule)",
         'Sources/WorksheetAIPane.swift answerCard (large, normal, non-normal), FullEngine/MeasurementChecks.cs Execute '
         '(conflict) and allowed() in this test', r'''
            case ("paired-interval" or "independent-interval", "large" or "normal" or "non-normal"):
                grid.ResolveWorksheetAnalysisTarget(action.Source, allowSelectionChanges: false);
                var decision = action.Interval;
                if (decision.LargeSample is bool large && large != (choice == "large") && choice != "non-normal")
                {
                    ShowIntervalFeedback(action, decision.Conflict(large));
                    return;
                }
                worksheetAction = ConfirmWorksheetAnalysis(action.Source,
                    FindWorksheetCommand(main, decision.Method(choice)), decision, choice);
                break;
            '''),
        ("ChooseWorksheetAction's back case", 'Sources/WorksheetAIPane.swift answerCard (back)', r'''
            case ("paired-interval" or "independent-interval", "back"):
                worksheetAction = new WorksheetAction("choose", action.Source);
                break;
            '''),
        ("ChooseWorksheetAction's sample case", 'Sources/WorksheetAIPane.swift changeSample', r'''
            case ("confirm", "sample") when action.Interval is { } previous:
                worksheetAction = WithCurrentWorksheetSelection(new WorksheetAction(previous.Kind, action.Source, Interval: previous));
                break;
            '''),
        ("ChooseWorksheetAction's clarify case",
         "Sources/WorksheetAIPane.swift answerClarification (an answer only for the card's selection, sent by submit, "
         'which retires the card)', r'''
            case ("clarify", _):
                var answer = action.Clarification.Options.FirstOrDefault(option => option.Id == choice);
                if (answer == null || service.Tutor.DataSharingDisabled) return;
                grid.ResolveWorksheetAnalysisTarget(action.Source, allowSelectionChanges: false);
                ClearWorksheetAnalysis();
                Render();
                _ = SendAsync(answer.Answer, isClarificationReply: true);
                return;
            '''),
        ("ChooseWorksheetAction's change case",
         "Sources/WorksheetAIPane.swift cancelAnalysis (the Mac's offer has Cancel in place of Change design)", r'''
            case ("confirm", "change") when action.Design != null:
                worksheetAction = WithCurrentWorksheetSelection(new WorksheetAction("choose", action.Source));
                break;
            '''),
        ("ChooseWorksheetAction's continue case",
         'Sources/WorksheetAIPane.swift continueAnalysis and cancelAnalysis (the offer retired as the method opens) and '
         'Sources/WorksheetAIAnalysis.swift continueWorksheetAIAnalysis (an offer used once)', r'''
            case ("confirm", "continue"):
                // Retire the token before native controls can open a modal message loop.
                ClearWorksheetAnalysis();
                Render();
                action.Proposal.Open();
                return;
            '''),
        ("ChooseWorksheetAction's other choices, and the status line after a choice",
         'Sources/WorksheetAIPane.swift answerCard (a choice the card does not show is ignored; the notice line after a '
         'choice)', r'''
                    default:
                        return;
                }
                status.Text = "";
                Render();
            }
            '''),
        ("ChooseWorksheetAction's error handler",
         'Sources/WorksheetAIPane.swift answerCard (an unavailable method), prepareAnalysis(_:from:) (an offer that '
         'cannot be prepared) and continueAnalysis and cancelAnalysis (an offer refused at Continue)', r'''
            catch (InvalidOperationException ex)
            {
                ClearWorksheetAnalysis();
                status.Text = ex.Message;
                Render();
            }
            '''),
        ('ShowIntervalFeedback', 'Sources/WorksheetAIPane.swift showCardFeedback (the card keeps its token)', r'''
            private void ShowIntervalFeedback(WorksheetAction action, string message)
            {
                worksheetAction = action with { Feedback = message };
                status.Text = "";
                Render();
            }
            '''),
        ('FindWorksheetCommand', "Sources/WorksheetAIPane.swift answerCard (the branch's method in viewer.worksheetAIMethods)", r'''
            private static WorksheetCommand FindWorksheetCommand(frmMain main, string operation) =>
                main.WorksheetCommands().FirstOrDefault(method => method.Operation == operation && method.CanRun);
            '''),
        ('ClearWorksheetAnalysis',
         'Sources/WorksheetAIPane.swift cancelAnalysis, and select, documentClosed, hide, newConversation and submit '
         '(each clears the card and any offer)', r'''
            private bool ClearWorksheetAnalysis()
            {
                if (worksheetAction == null) return false;
                worksheetAction = null;
                status.Text = "";
                return true;
            }
            '''),
    ),
    'StatsDirectUI/UI/Learning/ScriptAIPane.cs': (
        ("Open's switch to another document", 'Sources/WorksheetAIPane.swift select (another workbook clears the card; the same one keeps it)', r'''
            if (script != document)
            {
                SaveDraft(); Stop(); ClearWorksheetAnalysis(); status.Text = "";
            '''),
        ("Open's refresh of the card", 'Sources/WorksheetAIPane.swift open and refreshWorksheetState', r'''
            RefreshWorksheetContents();
            UpdateWorksheetSelection();
            if (pending == null) RefreshWorksheetGuidance();
            '''),
        ("SendAsync's condition for the worksheet tools", 'Sources/WorksheetAIPane.swift submit (cardReady)', r'''
            if (workbookHasData && grid.MdiParent is frmMain main && ReferenceEquals(main.ActiveMdiChild, grid)
                && !main.InOperation && !main.LearningCalculationRunning)
            {
                try { analysisTarget = grid.CaptureWorksheetAnalysisTarget(worksheetShared); }
                catch (InvalidOperationException) { /* The question can proceed without a local analysis target. */ }
            '''),
        ("SendAsync's definition of the card's tool (and of the clarifying question's)",
         'Sources/WorksheetAIPane.swift WorksheetAIDistribution.definition, WorksheetAIClarification.definition and '
         'submit (its tools), and the copy in Tests/mock-worksheet-ai-server.py', r'''
            tools.Add(QuestionContext.Tool(ChatGPTTutor.WorksheetTTestChoiceTool,
                "Open the Help decision tree for a quantitative comparison. Omit design when the study design is unclear. Use paired for matched pairs and independent for two independent samples. The card considers the relevant counts and distributions locally. This tool shares no diagnostic data and runs no analysis.",
                new() { ["design"] = new JsonObject { ["type"] = "string", ["enum"] = new JsonArray("paired", "independent") } }));
            if (!guidanceOnly)
                tools.Add(QuestionContext.Tool(ChatGPTTutor.WorksheetClarificationTool,
                    "Show a fixed set of clickable answers for the next missing detail: goal, outcome scale or study design. Wait for the user's answer before proposing a method. Does not inspect the worksheet or run an analysis.",
                    new() { ["dimension"] = new JsonObject { ["type"] = "string", ["enum"] = new JsonArray("goal", "scale", "design") } }, "dimension"));
            '''),
        ("CallTool for the card's tool", 'Sources/WorksheetAIPane.swift submit (stageCard), and the copies in Tests/mock-worksheet-ai-server.py', r'''
            if (worksheetMode && name == ChatGPTTutor.WorksheetTTestChoiceTool)
            {
                context.Check();
                if (analysisTarget == null || service.Tutor.Disabled)
                    throw new InvalidOperationException("Choose an active worksheet before offering a study-design choice.");
                if (stagedAnalysis != null) throw new InvalidOperationException("A worksheet action is already waiting.");
                IntervalDecision interval = null;
                if (args.Count != 0)
                {
                    if (args.Count != 1 || args["design"] is not JsonValue designValue
                        || !designValue.TryGetValue<string>(out var design) || design is not ("paired" or "independent"))
                        throw new ArgumentException("Omit design or set it to paired or independent.");
                    interval = new IntervalDecision(design == "paired");
                }
                stagedAnalysis = new WorksheetAction(interval?.Kind ?? "choose", CaptureCurrentGuidanceTarget(analysisTarget), Interval: interval);
                return Task.FromResult<JsonNode>(new JsonObject
                {
                    ["state"] = interval == null ? "awaiting_design" : "awaiting_distribution",
                    ["message"] = interval == null
                        ? "Ask the user to choose “Same people or units” or “Separate groups” in the chat."
                        : "The decision card lets the user check their selection locally and choose a branch. Ask them to review the card."
                });
            }
            '''),
        ("SendAsync's staged card after the reply", 'Sources/WorksheetAIPane.swift submit (the card drawn once the reply completes)', r'''
            if (chat == current && script == origin && IsOpen)
            {
                worksheetAction = WithCurrentWorksheetSelection(stagedAnalysis, newCard: true);
                Render();
            '''),
    ),
    'StatsDirectUI/UI/Learning/ChatGPTTutor.cs': (
        ('WorksheetTTestChoiceTool', 'Sources/WorksheetAIPane.swift WorksheetAIDistribution.tool and Sources/ChatGPTTutor.swift diagnosticTools', r'''
            internal const string WorksheetTTestChoiceTool = "statsdirect_choose_worksheet_t_test";
            '''),
        ('RestrictedWorksheetClarification', 'Content/Tutor/worksheet-instructions.txt (the paragraph for a question sent alone)', r'''
            private const string RestrictedWorksheetClarification = "You receive only the current question and cannot see earlier messages. When clarification is needed, ask for all missing non-confidential details together before naming or staging a test. Ask the user to restate the full question with those details in one message. If the current message depends on earlier messages, ask for a self-contained question. Use the study-design buttons if the current question establishes a quantitative outcome and a comparison of means and pairing is unclear. If matched quantitative measurements are already established and the user asks which method to choose, pass design paired to the same tool. For two known independent quantitative samples, pass design independent. The buttons collect the next details locally, so ask the user to select a button instead of sending an answer that depends on an earlier message.";
            '''),
        ("WorksheetInstructions on the card's tool", 'Content/Tutor/worksheet-instructions.txt', r'''
            When a quantitative scale and a comparison of means are established and matching is unclear, use statsdirect_choose_worksheet_t_test without arguments to offer Same people or units and Separate groups. If the user asks which method to choose and the quantitative design is clear, set design to paired or independent for the corresponding decision card when size or distribution remains uncertain. The card can check a suitable selection locally. If the user seeks inference about the mean, explain that a rank-based method addresses a different question. The usual signed-rank location interpretation assumes symmetric differences. If the outcome scale or comparison goal is still unclear, follow the clarification instructions.
            '''),
        ("ToolCallAsync's gate, inside the try",
         "Sources/ChatGPTTutor.swift toolCall (the gate's conditions; in a guidance-only reply, reject gives its "
         "refusals of the worksheet tools the reply's text)", r'''
            try
            {
                string name = args.S("tool"), call = args.S("callId");
                if (current == null || current.Token.IsCancellationRequested || args.S("threadId") != current.Thread || current.Turn != null && args.S("turnId") != current.Turn || args["namespace"] != null || !current.Tools.Contains(name) || call.Length == 0 || current.Calls.Count >= 16 || !current.Calls.Add(call) || args["arguments"] is not JsonObject arguments)
                    throw new InvalidOperationException("This request is not available for this question.");
            '''),
        ("ToolCallAsync's text for a guidance-only error",
         'Sources/WorksheetAIPane.swift submit (the question-only handler) and Sources/ChatGPTTutor.swift toolCall (its '
         'refusals)', r'''
            catch (Exception ex)
            {
                string error = ex is OperationCanceledException ? "Request stopped."
                    : current?.GuidanceOnly == true
                        ? args.S("tool") is WorksheetAnalysisTool or WorksheetTTestChoiceTool or WorksheetClarificationTool ? "The analysis proposal could not be staged." : "This help request could not be completed."
                        : ex.Message;
                result = ToolResult(false, error);
            '''),
        ("ConverseAsync's guidance-only tools and instructions",
         "Sources/WorksheetAIPane.swift submit (question only offers the card's tool alone) and "
         'Content/Tutor/worksheet-instructions.txt (the sentence, for the one tool)', r'''
            if (guidanceOnly)
            {
                tools = new JsonArray(tools.Where(tool => tool.S("name") == "statsdirect_method_help"
                    || (worksheet && tool.S("name") is (WorksheetAIHelp.SearchTool or WorksheetAIHelp.ReadTopicTool or WorksheetMethodSearchTool or WorksheetAnalysisTool or WorksheetTTestChoiceTool))).Select(tool => tool.DeepClone()).ToArray());
                instructions += GuidanceInstructions;
                if (worksheet)
                    instructions += "\nThe worksheet analysis tools can offer a study-design choice or propose a method for the user to confirm locally. They do not share workbook data or results.";
            }
            '''),
    ),
    'Learning/conversation.mjs': (
        ("updateWorksheetAction's focus inside the old card",
         'Sources/WorksheetAIPane.swift drawDistribution (focus on a card drawn again stays on the card)', r'''
            const transferFocus = worksheetActionElement?.contains(document.activeElement);
            '''),
        ("the cards' aria labels", 'Sources/WorksheetAIPane.swift WorksheetAIDistribution.accessibilityLabel and renderGuidance', r'''
            section.setAttribute('aria-label', action.kind === 'confirm' ? 'Proposed worksheet method'
              : action.kind === 'empty' ? 'Getting started with a workbook'
              : action.kind === 'choose' ? 'Study design'
              : action.kind === 'paired-interval' ? 'Paired interval measurements'
              : action.kind === 'independent-interval' ? 'Independent interval measurements'
              : action.kind === 'clarify' ? 'Analysis question' : 'Choose a worksheet method');
            '''),
        ("button()'s suggested branch", 'Sources/WorksheetAIPane.swift WorksheetAIDistribution.buttons and drawDistribution', r'''
            const suggested = choice === action.suggestedBranch;
            option.textContent = suggested ? 'Suggested · ' + label : label;
            if (suggested) option.dataset.recommended = 'true';
            '''),
        ('the study-design and interval cards',
         'Sources/WorksheetAIPane.swift WorksheetAIDistribution (question, lines, buttons) and drawDistribution, and the '
         'texts in Tests/worksheet-ai-driver.swift', r'''
            } else if (action.kind === 'choose') {
              const question = document.createElement('p');
              question.textContent = 'Were these measurements taken from the same people or units?';
              section.append(question);
              button('Same people or units', 'paired');
              button('Separate groups', 'independent');
            } else if (action.kind === 'paired-interval' || action.kind === 'independent-interval') {
              const paired = action.kind === 'paired-interval';
              const {sizeKnown, diagnostics = []} = action;
              for (const line of diagnostics) paragraph(line);
              if (!sizeKnown && !diagnostics.length)
                paragraph(paired ? 'How many complete pairs are there?' : 'How many observations are there in each group?');
              if (action.recommendation) {
                const explanation = paragraph(action.recommendation);
                explanation.className = 'worksheet-analysis-recommendation';
                const heading = document.createElement('strong');
                heading.textContent = action.suggestedBranch ? 'Suggested branch' : 'Review the differences';
                explanation.prepend(heading, document.createElement('br'));
              } else {
                paragraph(paired ? 'How are the within-pair differences distributed?' : 'How are the observations distributed within each group?');
                paragraph('Look at the shape and any influential points. A large Shapiro–Wilk P value is inconclusive.');
              }
              if (action.feedback) {
                const feedback = paragraph(action.feedback);
                feedback.className = 'worksheet-analysis-feedback';
                feedback.setAttribute('role', 'status');
              }
              if (action.canCheck)
                button(paired ? 'Check selected pairs' : diagnostics.length ? 'Use these as separate samples' : 'Check two sample columns', 'check');
              button(paired ? 'Large sample (more than 100 complete pairs)' : 'Large samples (more than 100 in each group)', 'large');
              button(paired ? 'Small or medium · Approximately normal differences' : 'Small or medium · Approximately normal within groups', 'normal');
              button(paired ? 'Non-normal differences' : 'Non-normal distributions within groups', 'non-normal');
              button('Change design', 'back');
            '''),
        ('the method offer from a card', 'Sources/WorksheetAIPane.swift prepareAnalysis(_:from:) (offerDetails) and changeSample', r'''
            for (const line of action.diagnostics ?? []) paragraph(line);
            if (action.intervalAdvice) paragraph(action.intervalAdvice);
            button('Continue to analysis', 'continue');
            if (action.intervalAdvice) button('Change sample choice', 'sample');
            '''),
        ("updateWorksheetAction's focus on the new card's first button",
         'Sources/WorksheetAIPane.swift drawDistribution (focus on a card drawn again stays on the card)', r'''
            if (transferFocus) actions.querySelector('button')?.focus({ preventScroll: true });
            '''),
    ),
    'StatsDirectUI/UI/Learning/WorksheetAnalysisProposal.cs': (
        ('WorksheetAnalysisTarget (its equality ties a card to its selection)',
         'Grid/ai-selection.mjs selectionFingerprint and Sources/WorksheetAIPane.swift answerCard', r'''
            internal sealed record WorksheetAnalysisTarget(
                frmSpreadsheetGear Grid, IWorkbook Workbook, IWorksheet Worksheet,
                string WorkbookName, string WorksheetName, string Selection, int Version, bool WorkbookShared)
            '''),
        ("WorksheetAnalysisProposal's target, resolved as the method is proposed",
         "Sources/WorksheetAIPane.swift prepareAnalysis(_:from:) (an offer from a card only for the card's reading) and "
         'Sources/WorksheetAIAnalysis.swift prepareWorksheetAIAnalysis', r'''
            internal WorksheetAnalysisProposal(WorksheetAnalysisTarget target, WorksheetCommand command)
            {
                var (main, source) = target.Grid.ResolveWorksheetAnalysisTarget(target, allowSelectionChanges: false);
            '''),
        ('the text for an unavailable method', 'Sources/WorksheetAIPane.swift answerCard', r'''
            if (command == null || !command.CanRun)
                throw new InvalidOperationException("That method is unavailable. Choose another method in Analyse.");
            '''),
        ('WorksheetAnalysisProposal.Open (the target and the report destination checked again)',
         'Sources/WorksheetAIAnalysis.swift continueWorksheetAIAnalysis (the selection, version and report destination '
         'checked again before the method opens) and Sources/WorksheetAIPane.swift continueAnalysis', r'''
            internal void Open()
            {
                var (main, _) = Source.Grid.ResolveWorksheetAnalysisTarget(Source, allowSelectionChanges: false);
                if (DestinationTitle != null)
                {
                    var currentDestination = main.ExistingReportDestination;
                    if (!ReferenceEquals(currentDestination, destination) || (destination != null && destination.Text != DestinationTitle))
                        throw new InvalidOperationException("The report destination changed. Choose the method again.");
                }
                main.OpenReviewedWorksheetCommand(command);
            }
            '''),
    ),
    'StatsDirectUI/Templates/RunRecord.cs': (
        ('RunRecord.Missing',
         'Grid/measurement-columns.mjs MISSING, cellValue and measurementColumns (a difference that is not finite or is '
         'double.MinValue is refused)', r'''
            public static bool Missing(double x) => Constant.MISSING == x || double.IsNaN(x) || double.IsInfinity(x);
            '''),
    ),
}
absent = []
for file, segments in MIRRORS.items():
    path = UPSTREAM / file
    source = [line.strip() for line in path.read_text(encoding='utf-8').split('\n')] if path.is_file() else []
    for what, mac, text in segments:
        lines = [line.strip() for line in text.strip().split('\n')]
        if any(source[i:i + len(lines)] == lines for i in range(len(source) - len(lines) + 1)):
            check(True, '%s still holds %s, mirrored in %s' % (file, what, mac))
            continue
        if not source: why = 'the file is not in the pinned source'
        elif (gone := next((line for line in lines if line not in source), None)) is None: why = 'its lines are no longer together'
        else: why = 'its line "%s" is not in the file' % (gone if len(gone) <= 160 else gone[:160] + '…')
        absent.append('%s: %s: %s. Review %s' % (file, what, why, mac))
if absent:
    check(False, 'the pinned Windows source no longer holds, as listed, %s the Mac mirrors. Review the Mac code each names against the '
          'new Windows code, then copy the new Windows lines into MIRRORS in Tests/test_measurement_check.py:\n  %s'
          % ('1 segment' if len(absent) == 1 else '%d segments' % len(absent), '\n  '.join(absent)))

# --- The oracle itself: base R regenerates the four tables. The script finds the fence table beside itself through Rscript's --file
# argument, which cannot hold a space, so it runs by its bare name in its own folder, writing to a folder named relative to it. The
# tables must agree with the committed ones field by field: the identifiers, counts, flags and branches exactly, and every other number
# within the engine comparisons' tolerance (near), which absorbs noise-level values such as a skewness of 1e-16, whose digits another
# R's arithmetic can change. Only the R that wrote the tables must regenerate them byte for byte; any other R lists the fields whose
# text differs, for information.
RECORDED_R = 'R version 4.6.1 (2026-06-24)'   # R.version.string of the R that wrote the tables (Tests/Fixtures/distribution/README.md)
EXACT = {'case', 'row', 'n', 'n1', 'n2', 'farOut', 'varying', 'fenceWarning', 'skewWarning', 'heavyTailWarning', 'large',
         'suggestedBranch', 'allowed', 'allowedWhenSeparate'}
NUMBERS = {'first', 'second', 'W', 'P', 'Q1', 'Q3', 'skewness', 'excessKurtosis', 'W1', 'P1', 'W2', 'P2'}
def regenerated(out, name):
    """The table R wrote to out against the committed one: the fields that disagree, and every field whose text differs."""
    def rows(path):
        with open(path, newline='', encoding='utf-8') as file: return list(csv.reader(file, delimiter='\t'))
    def agree(new, old):
        try: return near(number(new), number(old))
        except ValueError: return False
    if not (out / name).is_file(): return [name + ' was not written'], []
    new, old = rows(out / name), rows(FIXTURES / name)
    header = old[0]
    if unknown := [field for field in header if field not in EXACT | NUMBERS]:
        return ['%s has columns this test does not compare: %s' % (name, ', '.join(unknown))], []
    if not new or new[0] != header or len(new) != len(old) or any(len(row) != len(header) for row in new):
        return ['%s has %d rows of %s, the committed table %d rows of %s'
                % (name, len(new) - 1, ', '.join(new[0]) if new else 'nothing', len(old) - 1, ', '.join(header))], []
    wrong, changed = [], []
    for fresh, committed in zip(new[1:], old[1:]):
        record = dict(zip(header, committed))
        where = name + ' ' + record['case'] + (' row ' + record['row'] if 'row' in record else '')
        for field, x, y in zip(header, fresh, committed):
            if x == y: continue
            changed.append('%s %s: %s committed, %s regenerated' % (where, field, y or '(empty)', x or '(empty)'))
            if field in EXACT or not agree(x, y): wrong.append(changed[-1])
    return wrong, changed
try:
    r = rscript()
except SystemExit as missing:
    print('SKIP regenerating the fixtures in R:', missing, flush=True)
else:
    version = subprocess.run([r, '--vanilla', '-e', 'cat(R.version.string)'], capture_output=True, text=True, timeout=60).stdout.strip()
    with tempfile.TemporaryDirectory(prefix='measurement-oracle-', dir=ROOT / '.build') as scratch:
        out = Path(scratch) / 'tables'
        run = subprocess.run([r, '--vanilla', 'distribution-oracle.R', os.path.relpath(out, FIXTURES)], cwd=FIXTURES, capture_output=True, text=True, timeout=300)
        check(run.returncode == 0 and 'PASS: 26 paired and 5 independent fixtures, plus paired-overflow rejection.' in run.stdout,
              'the oracle\'s own checks pass in %s%s' % (r, '' if run.returncode == 0 else ':\n' + run.stdout + run.stderr))
        wrong, changed = [], []
        for name in TABLES:
            disagree, differ = regenerated(out, name)
            wrong += disagree; changed += differ
        check(not wrong, '%s regenerates the four fixture tables with their cases, rows, counts, flags and branches, and every other number '
              'within 2e-10 relative (absolute below 1)%s' % (version or r, ':\n  ' + '\n  '.join(wrong) if wrong else ''))
        identical = all((out / name).read_bytes() == (FIXTURES / name).read_bytes() for name in TABLES)
        if version == RECORDED_R:
            check(identical, '%s, which wrote the four tables, regenerates them byte for byte%s'
                  % (version, '' if identical else ': ' + ('; '.join(changed) if changed else 'their fields are the same, laid out differently')))
        else:
            if identical: detail = 'they are identical'
            elif changed: detail = '%d fields differ in their text, each within the comparison above:' % len(changed)
            else: detail = 'their fields are the same, laid out differently'
            print('INFO %s is not %s, which wrote the four tables, so their bytes are compared for information only: %s'
                  % (version or 'this R (it reports no version)', RECORDED_R, detail), flush=True)
            for field in changed: print('INFO   ' + field, flush=True)
print('PASS: %d measurement check checks' % checks, flush=True)
