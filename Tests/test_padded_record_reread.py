"""Mac mirror of the Windows saved-run reread tests, updated for 5.3.10.

Windows test mirrored: tests/Learning/SavedRunRereads.cs, the groups "Saved frequency, longer range first",
"Saved kappa, unequal ranges", "Saved paired t, padded by 5.3.6" and "Saved one way, two columns padded by 5.3.6", with the reader rule
(StatsDirectUI/UI/FrameReader.cs, Windows commit 4722fd56), which the Mac's reader carries in FullEngine/RScriptIO.cs.

A record is pointer-only above 5,000 values, so the data are the Windows test's own: 6,000 and 15 values for the pairs,
3,000 and 2,600 responses, 2,597 ratings a rater. The Mac's form gives every column of a selection one range, so the
record Windows writes of the same data is made from the Mac's native record by giving each column its own recorded rows
(and, for the 2,600 responses, the hash of its own values, as the Windows per-column category reader takes them). The
hashes of the padded pair are the literals the Windows test asserts (072508da8fc71fc2 and 2ee352f51ee9c6a9). The frames
are supplied as the Swift host supplies them (Sources/RunRecordR.swift): each column over its own recorded rows, as text.

Checks that need the Mac reader's two rules in RScriptIO.cs say so in their line: "[5.3.9 reader]" for the padding rule
ported from FrameReader.cs, "[own rows]" for a category column ending with its own recorded rows as Windows reads it.
The rest are non-regression checks, which hold with or without them. Every check is run and reported; the exit status
is 1 if any failed.

Not mirrored here: "Saved paired t, padded and filtered" (hidden rows). The Mac's grid does not skip hidden rows when a
selection is read or reread (Tests/test_pr6_replay.py says the same of its fixtures), and its record carries no row map,
so there is no hidden-row reread to pin. "Kappa, padded raters" and "Kappa, three padded raters" are entered records,
which the reader of pointer frames does not touch.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

from r_runtime import rscript
from test_menu import ROOT, Session
from test_pr6_replay import PREFS, acquisition, sheet, vector


BEFORE = [200.0 + 3 * k + k % 4 * 0.25 for k in range(6000)]
AFTER = [195.0 + 2.5 * k + k % 3 * 0.5 for k in range(15)]
BEFORE_HASH, AFTER_PADDED_HASH = '072508da8fc71fc2', '2ee352f51ee9c6a9'   # the Windows test's literals
RESPONSE_ONE = [str(1 + k * 7 % 5) for k in range(3000)]
RESPONSE_TWO = [str(1 + k * 3 % 4) for k in range(2600)]
FIRST_RATER = [str(1 + k * 7 % 3) for k in range(2597)]
SECOND_RATER = [str(1 + (k * 7 + (1 if k % 4 == 0 else 0)) % 3) for k in range(2597)]
CHANGE_NOTE = 'has changed in the workbook'
failures = []
passed = []


def check(condition, label, detail=None):
    if condition:
        passed.append(label)
        print('PASS: ' + label, flush=True)
    else:
        failures.append(label)
        print('FAIL: ' + label + ('' if detail is None else ' :: ' + str(detail)[:900]), flush=True)
    return bool(condition)


def attempt(label, action):
    """A check whose body raises when it fails (an R run, a notebook export)."""
    try:
        action()
    except Exception as error:   # reported as this check's failure, with the others still run
        return check(False, label, error)
    return check(True, label)


def net(value):
    """A cell as the grid's text: a number in .NET round-trip form (200.0 is "200"), nothing for a blank."""
    if value is None or value == '':
        return ''
    if isinstance(value, str):
        return value
    return str(int(value)) if float(value).is_integer() else repr(float(value))


def record_hash(values):
    """RunRecord.Hash: SHA-256 of the values as text joined by line feeds, the first 16 hexadecimal characters."""
    return hashlib.sha256('\n'.join(net(v) for v in values).encode()).hexdigest()[:16]


def supplied(name, columns):
    """A frame as the Swift host supplies it: each column's cells over its own recorded rows, as the grid's text."""
    return {'name': name, 'columns': [{'title': title, 'values': [net(v) for v in values],
                                       'kinds': ['blank' if net(v) == '' else 'number' for v in values]} for title, values in columns]}


class Engine:
    """The statsdirect_r_script entry, which Continue in R, the notebook export and the conversation's replay all call."""
    def __init__(self):
        self.process = subprocess.Popen([
            str(ROOT / 'Tests/engine-driver'),
            os.environ.get('STATSDIRECT_TEST_ENGINE', str(ROOT / 'FullEngine/publish/StatsDirectEngine.dylib')),
            'statsdirect_r_script'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)

    def ask(self, request):
        self.process.stdin.write(json.dumps(request) + '\n')
        self.process.stdin.flush()
        return json.loads(self.process.stdout.readline())

    def script(self, record, title, frames):
        result = self.ask({'record': record, 'title': title, 'frames': frames})
        assert 'error' not in result and isinstance(result.get('text'), str), result
        return result

    def notebook(self, record, title, pointer, frame):
        """The notebook export of one saved run, as Windows NotebookSnapshot builds it: {"notebook"}, {"relocate"} or {"error"}."""
        snapshot = {'version': 1, 'engineVersion': 'test', 'reportHtml': '<p>' + title + '</p>',
                    'entries': [{'id': 'saved-run', 'title': title, 'operation': record['operation'], 'html': '<p>' + title + '</p>',
                                 'cells': [{'source': title}], 'record': record}]}
        return self.ask({'notebook': snapshot, 'title': title, 'appVersion': 'test', 'frames': [{'pointer': pointer, 'frame': frame}]})

    def close(self):
        self.process.stdin.close()
        assert self.process.wait(timeout=15) == 0


VECTOR = re.compile(r'^(\w+) <- c\((.*)\)\s+# (.*), column (\d+), rows (\d+) to (\d+)$', re.M)


def vectors(text):
    """The data vectors of a script's head, in order: title -> the items as written."""
    return {m[3]: m[2].split(', ') if m[2] else [] for m in VECTOR.finditer(text)}


def numbers(items):
    return [None if item == 'NA' else float(item) for item in items]


def texts(items):
    return [None if item == 'NA' else json.loads(item) for item in items]


def notebook_code(response):
    assert 'notebook' in response, {k: (v if k != 'notebook' else '...') for k, v in response.items()}
    cells = json.loads(response['notebook'])['cells']
    code = '\n'.join(c['source'] if isinstance(c['source'], str) else ''.join(c['source']) for c in cells if c['cell_type'] == 'code')
    assert 'local({' in code, code[:400]
    return code


def run_r(code, marker):
    """Runs a script in R (the arbiter) in a temporary folder and gives what it printed."""
    (ROOT / '.build').mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='padded-reread-', dir=ROOT / '.build') as folder:
        path = Path(folder) / 'replay.R'
        path.write_text(code + '\ncat("' + marker + '\\n")\n')
        result = subprocess.run([rscript(), '--vanilla', str(path)], cwd=folder, text=True, capture_output=True, timeout=120)
        assert result.returncode == 0 and marker in result.stdout, (result.stdout[-1500:], result.stderr[-1500:])
        return result.stdout


def quiet(result):
    """What a reread says of the data: nothing unavailable, no column to look for, no change note."""
    return bool(result.get('hasRecipe')) and not result.get('dataUnavailable') and not result.get('relocate') and CHANGE_NOTE not in result['text']


def brief(result):
    return {'hasRecipe': result.get('hasRecipe'), 'dataUnavailable': result.get('dataUnavailable'), 'relocate': result.get('relocate'),
            'notes': [line for line in result.get('text', '').split('\n') if 'NOTE:' in line],
            'lengths': {title: len(items) for title, items in vectors(result.get('text', '')).items()}}


def padded_pairs(session, engine):
    """Saved paired t, padded by 5.3.6."""
    native = session.run('TPaired', {'data': sheet(['Before', 'After'], [BEFORE, AFTER + [''] * (len(BEFORE) - len(AFTER))]),
                                     'gamma': 0.95, 'doAgreement': False}, PREFS)
    record = json.loads(native['record'])
    pointer = acquisition(record)
    own = json.loads(json.dumps(record))   # the Mac's own record of the selection: both columns over rows 1 to 6001
    pointer['columns'][1]['rows'] = [1, 16]   # the record 5.3.6 wrote: each column's own range, the After hash over the padded column
    columns = pointer['columns']
    check(pointer['kind'] == 'frame' and 'data' not in record and columns[0]['rows'] == [1, 6001] and columns[1]['rows'] == [1, 16]
          and columns[0]['hash'] == BEFORE_HASH and columns[1]['hash'] == AFTER_PADDED_HASH
          and record_hash(BEFORE) == BEFORE_HASH and record_hash(AFTER + [None] * 5985) == AFTER_PADDED_HASH,
          'the padded pair is saved as the 5.3.6 pointer record: rows 1 to 6001 and 1 to 16, the After hash over 6,000 values',
          json.dumps(pointer)[:600])
    values = native['values']
    check(values['n'] == 15, 'native paired t uses the 15 complete pairs', values.get('n'))

    # the Mac's own record: its host supplies both columns over rows 1 to 6001, the blanks under After with them
    result = engine.script(own, 'Paired t test', [supplied('data', [('Before', BEFORE), ('After', AFTER + [''] * 5985)])])
    read = vectors(result['text'])
    check(quiet(result) and len(read.get('Before', [])) == 6000 and numbers(read.get('After', [])) == AFTER + [None] * 5985,
          "the Mac's own record of the blank-padded selection rereads unchanged, as before", brief(result))

    # (a) the 5.3.6 record: the host supplies 6,000 and 15 values, each column over its own recorded rows
    frames = [supplied('data', [('Before', BEFORE), ('After', AFTER)])]
    result = engine.script(record, 'Paired t test', frames)
    read = vectors(result['text'])
    check(result.get('asked') == ['data'] and not result.get('relocate'),
          '[5.3.9 reader] the padded record asks the host to look for no column', brief(result))
    check(numbers(read.get('Before', [])) == BEFORE and numbers(read.get('After', [])) == AFTER + [None] * 5985,
          '[5.3.9 reader] the actual reread pads the shorter column back to its recorded hash, without a false change', brief(result))
    check(quiet(result), '[5.3.9 reader] the padded record replays without a change note', brief(result))
    expected = vector([values[key] for key in ['n', 'mean', 'sd', 'df', 't', 'tail_2', 'from', 'to']])
    assertion = ('\nstopifnot(n == 15, isTRUE(all.equal(unname(c(n, mean(d), sd(d), r$parameter, r$statistic, r$p.value, r$conf.int)), '
                 + expected + ', tolerance = 1e-10, check.attributes = FALSE)))')
    attempt('[5.3.9 reader] the padded record replays in R with n = 15 and the native t, P and interval',
            lambda: run_r(result['text'] + assertion, 'SAVED_PADDED_OK'))

    def notebook():
        printed = run_r(notebook_code(engine.notebook(record, 'Paired t test', pointer, frames[0])), 'SAVED_PADDED_NOTEBOOK_OK')
        interval = '95% CI = {:.6f} to {:.6f}'.format(values['from'], values['to'])
        assert '(n = 15)' in printed and interval in printed, (interval, printed[-1500:])
    attempt('[5.3.9 reader] the notebook export accepts the padded record, and its replay prints the native pairs and interval', notebook)

    # (b) An edit to the shorter column is still a change: padding never hides it, and the notebook refuses the edited values.
    edited = list(AFTER)
    edited[3] = 1000.0   # the Windows test's cell: grid row 4 (from 0, under the title), column B
    frames = [supplied('data', [('Before', BEFORE), ('After', edited)])]
    first = engine.script(record, 'Paired t test', frames)
    asked = first.get('relocate') or []
    check(len(asked) == 1 and asked[0].get('name') == 'data' and asked[0].get('column') == 1 and asked[0].get('place') == 2
          and asked[0].get('firstRow') == 1 and asked[0].get('lastRow') == 16,
          'an edited cell of the padded column is asked for once, by its own recorded place', asked)
    # the host's second call: the same cells with the band either side of the column, for the engine to look for it there
    again = [dict(frames[0], index=0, candidates=[
        {'column': 1, 'title': 'Before', 'values': [net(v) for v in BEFORE[:15]], 'kinds': ['number'] * 15},
        {'column': 3, 'title': '', 'values': [''] * 15, 'kinds': ['blank'] * 15},
        {'column': 4, 'title': '', 'values': [''] * 15, 'kinds': ['blank'] * 15}])]
    second = engine.script(record, 'Paired t test', again)
    read = vectors(second['text'])
    check(not second.get('relocate') and not second.get('dataUnavailable')
          and numbers(read.get('Before', [])) == BEFORE and numbers(read.get('After', [])) == edited,
          'an edited cell of the padded column is reported as changed and is not padded', brief(second))
    check(second['text'].count('NOTE: "After" ' + CHANGE_NOTE) == 1 and second['text'].count(CHANGE_NOTE) == 1
          and first['text'].count(CHANGE_NOTE) == 1,
          'the edited padded column keeps its change note, once, and the unedited column has none', brief(second))
    refused = engine.notebook(record, 'Paired t test', pointer, frames[0])
    refused_again = engine.notebook(record, 'Paired t test', pointer, again[0])
    check('notebook' not in refused and len(refused.get('relocate') or []) == 1 and 'notebook' not in refused_again and 'error' in refused_again,
          'the notebook export refuses the edited padded column', (str(refused)[:300], str(refused_again)[:300]))
    restored = list(edited)
    restored[3] = 195.0 + 2.5 * 3
    result = engine.script(record, 'Paired t test', [supplied('data', [('Before', BEFORE), ('After', restored)])])
    check(quiet(result) and len(vectors(result['text']).get('After', [])) == 6000,
          "[5.3.9 reader] restoring the edited cell restores the padded record's values", brief(result))

    # The Mac's first call names the columns to look for: with the longer column edited, the padded one is not among them, and the
    # second call, which carries the band either side of the longer column, still reads the padded one as recorded.
    changed = list(BEFORE)
    changed[100] = -1.0
    frames = [supplied('data', [('Before', changed), ('After', AFTER)])]
    first = engine.script(record, 'Paired t test', frames)
    asked = first.get('relocate') or []
    again = [dict(frames[0], index=0, candidates=[
        {'column': 2, 'title': 'After', 'values': [net(v) for v in AFTER] + [''] * 5985, 'kinds': ['number'] * 15 + ['blank'] * 5985},
        {'column': 3, 'title': '', 'values': [''] * 6000, 'kinds': ['blank'] * 6000}])]
    second = engine.script(record, 'Paired t test', again)
    read = vectors(second['text'])
    check(len(asked) == 1 and asked[0].get('column') == 0 and asked[0].get('place') == 1 and asked[0].get('lastRow') == 6001
          and not second.get('relocate') and second['text'].count(CHANGE_NOTE) == 1 and second['text'].count('NOTE: "Before" ' + CHANGE_NOTE) == 1
          and numbers(read.get('Before', [])) == changed and numbers(read.get('After', [])) == AFTER + [None] * 5985,
          '[5.3.9 reader] an edit to the longer column is the only change: the padded column is not looked for and is read as recorded',
          (asked, brief(second)))

    # (c) control: a shorter column recorded with the hash of its own 15 values is read as it is, and is not padded
    control = json.loads(json.dumps(record))
    acquisition(control)['columns'][1]['hash'] = record_hash(AFTER)
    result = engine.script(control, 'Paired t test', [supplied('data', [('Before', BEFORE), ('After', AFTER)])])
    read = vectors(result['text'])
    check(quiet(result) and numbers(read.get('Before', [])) == BEFORE and numbers(read.get('After', [])) == AFTER,
          'control: a shorter column that has the hash of its own 15 values reads unchanged and unpadded', brief(result))


def frequency_bins(html, title):
    """The native report's table of one variable: its total and each value with its frequency."""
    text = re.sub(r'<[^>]+>', ' ', html)
    section = text.split('Frequency analysis for ' + title, 1)[1].split('Frequency analysis for', 1)[0]
    total = int(re.search(r'Total = (\d+)', section)[1])
    rows = re.findall(r'(\S+)\s+(\d+)\s+[\d.]+\s+\d+\s+[\d.]+', section.split('Cumulative Relative %', 1)[1])
    return total, [(value, int(count)) for value, count in rows]


def atomic_padding(session, engine):
    """Saved one way, two columns padded by 5.3.6."""
    columns = [('Group one', [10.0 + k % 17 * .5 for k in range(3000)]),
               ('Group two', [11.0 + k % 13 * .25 for k in range(2400)]),
               ('Group three', [12.0 + k % 7 * .75 for k in range(40)])]
    titles = [title for title, _ in columns]
    native = session.run('OneWay', {'data': sheet(titles, [v + [''] * (3000 - len(v)) for _, v in columns])}, PREFS)
    record = json.loads(native['record'])
    pointer = acquisition(record)
    for column, (_, values) in zip(pointer['columns'], columns):
        column['rows'] = [1, len(values) + 1]
    check('data' not in record and pointer['kind'] == 'frame' and pointer['mode'] == 'NumericReplaceMissing'
          and [column['hash'] for column in pointer['columns']] == ['e69e1717ffb9ae6c', 'a51ae29acc5c03fe', 'cc605a61a19f8ced'],
          'the saved one-way record has the three Windows padded hashes', pointer)

    def replay_lengths(text, lengths, assertion=''):
        # The recipe drops missing values at this line. Check the reread before it does.
        before, binding, after = text.partition('\ngroups <- lapply(')
        assert binding, 'missing one-way groups'
        check_lengths = '\nstopifnot(identical(as.numeric(lengths(groups)), ' + vector(lengths) + '))\n'
        run_r(before + check_lengths + binding + after + assertion, 'ONE_WAY_PADDED_OK')

    original = engine.script(record, 'One way', [supplied('data', columns)])
    check(quiet(original), 'both shorter one-way columns recover their recorded padding', brief(original))
    native_figures = vector(native['values'][key] for key in ('f', 'b_sum', 'w_sum', 'w_df'))
    attempt('the two padded columns replay to the native ANOVA and the Windows reference', lambda:
            replay_lengths(original['text'], [3000, 3000, 3000],
                           '\nexpected <- ' + native_figures +
                           '\nstopifnot(isTRUE(all.equal(c(a$"F value"[1], a$"Sum Sq"[1], a$"Sum Sq"[2], a$Df[2]), expected, tolerance=1e-10)), '
                           'isTRUE(all.equal(expected, c(405.5196746169783, 3011.5213463541654, 20188.46752083341, 5437), tolerance=1e-10)))'))

    for index, row in ((2, 5), (1, 7)):
        edited = [(title, list(values)) for title, values in columns]
        edited[index][1][row] = 777
        frame = supplied('data', edited)
        result = engine.script(record, 'One way', [frame])
        changed = ['NOTE: "' + title + '" ' + CHANGE_NOTE for title in titles[1:]]
        check([c['place'] for c in result.get('relocate', [])] == [2, 3]
              and result['text'].count(CHANGE_NOTE) == 2 and all(note in result['text'] for note in changed),
              f'editing {titles[index]} flags both short columns and leaves the long one unchanged', brief(result))
        attempt(f'editing {titles[index]} prevents padding either short column',
                lambda: replay_lengths(result['text'], [3000, 2400, 40]))

    legacy = json.loads(json.dumps(record))
    acquisition(legacy)['columns'][2]['hash'] = None
    result = engine.script(legacy, 'One way', [supplied('data', columns)])
    check(quiet(result), 'the hashless shorter column does not block the other padding', brief(result))
    attempt('the hashless shorter column retains only its own rows',
            lambda: replay_lengths(result['text'], [3000, 3000, 40]))


def r_strings(values):
    return 'c(' + ', '.join(json.dumps(value) for value in values) + ')'


def frequency_replay(text, columns, native_bins):
    """Check the complete vectors and the printed table of every selected column in R."""
    code = 'output <- capture.output({\n' + text + '\n})\n'
    titles = [title for title, _ in columns]
    code += 'stopifnot(identical(names(samples), ' + r_strings(titles) + '))\n'
    for index, (_, values) in enumerate(columns, 1):
        code += f'stopifnot(identical(samples[[{index}L]], ' + r_strings(values) + '))\n'
    code += r"""
check_column <- function(title, total, labels, frequencies) {
  first <- match(title, output)
  header <- first + match("Value  Frequency  Relative %  Cumulative  Cumulative Relative %",
                          output[seq.int(first + 1L, length(output))])
  stopifnot(identical(output[header - 1L], paste("Total =", total)))
  rows <- strsplit(trimws(output[header + seq_along(labels)]), "[[:space:]]+")
  stopifnot(identical(vapply(rows, `[`, "", 1L), labels),
            identical(as.numeric(vapply(rows, `[`, "", 2L)), frequencies))
}
"""
    for title in titles:
        total, bins = native_bins[title]
        labels = r_strings(value for value, _ in bins)
        counts = vector(count for _, count in bins)
        code += f'\ncheck_column({json.dumps(title)}, {total}, {labels}, {counts})'
    run_r(code, 'SAVED_FREQUENCY_OK')


def frequency(session, engine):
    """Saved frequency, longer range first."""
    columns = [('Response one', RESPONSE_ONE), ('Response two', RESPONSE_TWO)]
    native = session.run('Frequency', {'data': sheet(['Response one', 'Response two'], [RESPONSE_ONE, RESPONSE_TWO + [''] * 400]),
                                       'sortBy': 'value', 'sortOrder': 'asc'}, PREFS)
    record = json.loads(native['record'])
    pointer = acquisition(record)
    one_hash = pointer['columns'][0]['hash']
    # the record Windows writes of "A1:A3001,B1:B2601": the second column over its own rows, with the hash of its own 2,600 values
    pointer['columns'][1]['rows'] = [1, 2601]
    pointer['columns'][1]['hash'] = record_hash(RESPONSE_TWO)
    check('data' not in record and pointer['kind'] == 'frame' and pointer['columns'][0]['rows'][1] == 3001 and pointer['columns'][1]['rows'][1] == 2601
          and one_hash == record_hash(RESPONSE_ONE),
          'frequency of 5,600 categories is saved pointer-only, the longer range first', json.dumps(pointer)[:600])
    frames = [supplied('data', columns)]
    result = engine.script(record, 'Frequency', frames)
    check(quiet(result), '[own rows] the frequency replay reads its pointer-only data without a change note', brief(result))
    # Mac selections use one range for all columns. Run each native column at the saved
    # range length so the shorter column's total reflects its 2,600 selected rows.
    native_bins = {}
    for title, values in columns:
        single = session.run('Frequency', {'data': sheet([title], [values]), 'sortBy': 'value', 'sortOrder': 'asc'}, PREFS)
        total, bins = frequency_bins(single['html'], title)
        assert total == len(values) and sum(count for _, count in bins) == len(values), (title, total, bins)
        native_bins[title] = (total, bins)
    attempt('[own rows] the frequency replay retains both full vectors and gives both native tables and totals in R',
            lambda: frequency_replay(result['text'], columns, native_bins))
    attempt('[own rows] the frequency notebook export accepts the reread values', lambda: notebook_code(engine.notebook(record, 'Frequency', pointer, frames[0])))

    # the longer range last rereads the same values
    last = json.loads(json.dumps(record))
    acquisition(last)['columns'].reverse()
    columns.reverse()
    result = engine.script(last, 'Frequency', [supplied('data', columns)])
    check(quiet(result), '[own rows] the longer range last also rereads both recorded hashes', brief(result))
    attempt('[own rows] the longer range last retains both vectors and tables in the requested order',
            lambda: frequency_replay(result['text'], columns, native_bins))


def kappa(session, engine):
    """Saved kappa, unequal ranges."""
    native = session.run('Kappa', {'ci': 0.95, 'responses': sheet(['First rater', 'Second rater'], [FIRST_RATER + [''] * 3, SECOND_RATER + [''] * 3]),
                                   'method': '1'}, PREFS)
    record = json.loads(native['record'])
    pointer = acquisition(record, 'responses')
    pointer['columns'][1]['rows'] = [1, 2598]   # the record Windows writes of "A1:A2601,B1:B2598"
    check('data' not in record and pointer['columns'][0]['rows'][1] == 2601
          and [c['hash'] for c in pointer['columns']] == [record_hash(FIRST_RATER), record_hash(SECOND_RATER)],
          "kappa of 2,597 paired ratings is saved pointer-only with the first rater's longer range", json.dumps(pointer)[:600])
    frames = [supplied('responses', [('First rater', FIRST_RATER + [''] * 3), ('Second rater', SECOND_RATER)])]
    result = engine.script(record, 'Kappa', frames)
    read = vectors(result['text'])
    check(quiet(result) and texts(read.get('First rater', [])) == FIRST_RATER and texts(read.get('Second rater', [])) == SECOND_RATER,
          "the actual reread of the raters' unequal ranges gives 2,597 ratings each with their recorded hashes", brief(result))
    values = native['values']
    expected = vector([values[key] for key in ['kappa', 'se', 'seci', 'kappaw', 'sekw', 'sekwci', 'spi']])
    assertion = ('\nstopifnot(n == 2597, isTRUE(all.equal(unname(c(kappa, se0, se, kappaw, se0w, sew, (po - spe) / (1 - spe))), '
                 + expected + ', tolerance = 1e-10, check.attributes = FALSE)))')
    attempt('the kappa replay reads its pointer-only data and gives the native statistics in R', lambda: run_r(result['text'] + assertion, 'SAVED_KAPPA_OK'))
    attempt('the kappa notebook export accepts the reread values', lambda: notebook_code(engine.notebook(record, 'Kappa', pointer, frames[0])))


if __name__ == '__main__':
    session, engine = Session(), Engine()
    try:
        for label, group in [('Saved paired t, padded by 5.3.6', padded_pairs), ('Saved one way, two columns padded by 5.3.6', atomic_padding),
                             ('Saved frequency, longer range first', frequency),
                             ('Saved kappa, unequal ranges', kappa)]:
            try:
                group(session, engine)
            except Exception as error:   # a group that could not be run through is a failure of its own
                check(False, label + ': the group ran to its end', repr(error))
    finally:
        engine.close()
        session.finish()
    print(f'PADDED RECORD REREAD: {len(passed)} passed, {len(failures)} failed', flush=True)
    if failures:
        raise SystemExit('FAILED: ' + '; '.join(failures))
