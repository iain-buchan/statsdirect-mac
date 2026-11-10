"""Kappa of raters whose columns are unequal, through the Mac operation host and real R: the native halves of "Kappa, padded raters" and
"Kappa, three padded raters" in Windows's tests/Learning/SavedRunRereads.cs at v5.3.9 (f41aad46).

The rows a shorter rater's column is padded with are missing ratings, not ratings of that column's first category. Two raters with 12
and 7 ratings are then the 7 subjects both rated, whose kappa is 11/32 as base R computes it from those pairs alone; three raters
with 8, 8 and 5 ratings have 2 to 3 ratings per subject, and the kappa of Fleiss and Cuzick (1979) for unequal numbers of ratings is
that of the ratings given.

Mirrored from Windows, with its ratings, titles, answers (95% confidence, method "1" for two raters; three raters are not asked a
method), R reference code, tolerances and markers (6 checks):
- "native kappa of padded raters tabulates the 7 subjects both rated, not the 12 rows of the padded frame";
- "the record keeps the padded rows of the second rater as missing values": the responses are recorded as entered, the second
  rater's 12 values ending in 5 nulls;
- "the padded kappa replays from its record": the script written from the record has a recipe and its data;
- saved-kappa-padded: R runs that script, then Windows's reference (N == 7, n == 7, kappa_ref == 11/32, the native kappa and
  observed agreement against base R at 1e-12, and the script's kappa, se0, se, weighted kappa, its two standard errors and Scott's
  pi against the native figures at 1e-10) and prints SAVED_KAPPA_PADDED_OK;
- "native kappa of three padded raters counts 2 to 3 ratings per subject": categories 2 and r "2 to 3 (median 3)";
- saved-kappa-three-padded: R computes the Fleiss-Cuzick kappa of the ratings given (m == 3, 3, 3, 3, 3, 2, 2, 2), equal to the
  native one at 1e-12, and prints SAVED_KAPPA_THREE_OK (as on Windows, without a saved script: the recipe is of two raters).
The other groups of that Windows file, its rereads of saved records, are not mirrored here.

Where the Mac host gives the evidence otherwise:
- On Windows the user selects the ranges A1:A13,B1:B8 and accepts the warning that the jagged ends will be padded. The Mac's selection
  is one rectangle, and its host pads a category frame itself (FullEngine/HostParameters.cs), with no warning. Each run is therefore
  made in both of the Mac's forms of unequal columns: entered columns of 12 and 7 values, which carry every Windows check as
  written, and a worksheet selection of rows 2 to 13 whose second column ends in five blank cells. The Mac records that selection
  (of a workbook never saved) as a pointer to its cells, both columns rows 1 to 13, with the values the analysis used held beside
  it, not as entered data, so Windows's check of the record is made on the entered columns only; the script of the worksheet run
  is written from the values its record holds, and must give the same figures in R.
- The native ParameterBag is not returned: the run's scalar outputs ('values') give kappa, po, se, seci, kappaw, sekw, sekwci, spi,
  categories, r and k at full precision, and the pairs are counted in the report's cross tabulation (Windows's *y and *tot blocks).
- The script is written from the record by statsdirect_r_script, the Mac's RScriptWriter entry, and run by Rscript --vanilla in its
  own folder under .build, as Windows's RunConversationR runs it: exit code 0, the marker, and no "Error" in the output.
Windows's fix here (ClassifierVariable pads with the missing code) is in the shared engine; the Mac's own reader already padded with
missing values at 5.3.8, so on the Mac these checks guard the behaviour rather than show a change at the pin.
"""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

from r_runtime import rscript
from test_menu import ROOT, Session


ENGINE = Path(os.environ.get('STATSDIRECT_TEST_ENGINE', str(ROOT / 'FullEngine/publish/StatsDirectEngine.dylib')))
PREFS = {'use-default-ci': False}   # the confidence level is asked and answered, as Windows answers ci
WORKBOOK = 'Kappa.xlsx'             # never opened: the answers carry their cells
FIRST = [1, 2, 3, 2, 1, 3, 2, 2, 1, 3, 3, 1]
SECOND = [1, 2, 2, 2, 3, 3, 1]
RATERS = [[1, 2, 1, 1, 2, 2, 1, 2], [1, 2, 2, 1, 2, 1, 1, 2], [1, 1, 2, 1, 2]]
WORKSHEET = ' (worksheet selection ending in blank cells)'

checks = 0
failures = []


def check(ok, what, detail=''):
    global checks
    if not ok:
        raise AssertionError('FAIL ' + what + (': ' + str(detail) if detail else ''))
    checks += 1
    print('PASS: ' + what, flush=True)


def attempt(what, step):
    try:
        return step()
    except Exception as error:
        failures.append(what)
        print(str(error) if str(error).startswith('FAIL') else 'FAIL: ' + what + ': ' + repr(error)[:3000], flush=True)
        return None


def entered(titles, columns):
    """Columns typed into the Mac's data entry form, each as long as its own values: the host pads the shorter."""
    return {'source': 'Entered data', 'columns': [{'title': t, 'values': list(v)} for t, v in zip(titles, columns)]}


def texts(columns):
    """The worksheet's cells under the titles, every column to the last used row: a blank cell is empty text."""
    rows = max(len(v) for v in columns)
    return [[str(x) for x in v] + [''] * (rows - len(v)) for v in columns]


def selection(titles, columns):
    """The rectangle of those columns as the form sends a worksheet selection."""
    last = max(len(v) for v in columns) + 1
    return {'source': f'{WORKBOOK} / Data · rows 2–{last}', 'range': {'firstRow': 2, 'lastRow': last, 'columns': list(range(len(titles)))},
            'preserveRows': True, 'columns': [{'title': t, 'values': v} for t, v in zip(titles, texts(columns))],
            'worksheet': {'workbook': WORKBOOK, 'workbookPath': '/nonexistent/' + WORKBOOK, 'sheet': 0, 'sheetName': 'Data',
                          'hasTitle': True, 'titles': list(titles)}}


def run(session, answers):
    """Kappa through the Mac host with exactly these answers: a prompt they do not name, or a refused answer, fails the run."""
    ident, state = session.start('Kappa', PREFS)
    try:
        for _ in range(100):
            if state.get('state') != 'input':
                break
            prompt = state['prompt']
            if prompt.get('error'):
                raise AssertionError(f'Kappa refused {prompt.get("name")}: {prompt["error"]}')
            if prompt.get('name') not in answers:
                raise AssertionError(f'Kappa asked for {prompt.get("name")} ({prompt["kind"]}), which these checks do not answer')
            session.request(action='answer', id=ident, token=state['token'], value=answers[prompt['name']])
            state = session.wait(ident)
        assert state.get('state') == 'complete', ('Kappa', state.get('state'), state.get('error'))
        return state
    finally:
        session.close(ident)


class Writer:
    """statsdirect_r_script through Tests/engine-driver: the script of a record that holds its values (no worksheet is re-read)."""
    def __init__(self):
        self.process = subprocess.Popen([str(ROOT / 'Tests/engine-driver'), str(ENGINE), 'statsdirect_r_script'],
                                        stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)

    def write(self, record):
        self.process.stdin.write(json.dumps({'record': record, 'frames': []}) + '\n')
        self.process.stdin.flush()
        return json.loads(self.process.stdout.readline())

    def close(self):
        self.process.stdin.close()
        assert self.process.wait(timeout=15) == 0


def crosstab(html):
    """The cells of the report's cross tabulation of the two raters, without its row and column labels."""
    part = html.split('<h1>Crosstabs</h1>', 1)[1].split('<h1>', 1)[0]
    table = [[re.sub(r'<[^>]+>', '', c).strip() for c in re.findall(r'<td[^>]*>(.*?)</td>', row, re.S)]
             for row in re.findall(r'<tr[^>]*>(.*?)</tr>', part.split('<table')[2], re.S)]
    assert table and table[0][0] == '' and all(len(row) == len(table[0]) for row in table), table
    return [[int(c) for c in row[1:]] for row in table[1:]]


def number(value):
    """A double as .NET's "R" format and R read it back: the shortest text that round-trips."""
    return repr(float(value))


def vector(values):
    return 'c(' + ', '.join(str(v) if isinstance(v, int) else number(v) for v in values) + ')'


def run_r(folder, name, code, marker):
    """Windows's RunConversationR: the code as check.R in its own folder, Rscript --vanilla, its output kept beside it."""
    folder = folder / name
    folder.mkdir(parents=True)
    (folder / 'check.R').write_text(code)
    environment = {k: v for k, v in os.environ.items() if not (k in ('LC_ALL', 'LC_CTYPE') and v == 'C.UTF-8')}
    result = subprocess.run([rscript(), '--vanilla', '--encoding=UTF-8', str(folder / 'check.R')], cwd=folder, env=environment,
                            text=True, capture_output=True, timeout=60)
    output = result.stdout + result.stderr
    (folder / 'output.txt').write_text(output)
    return result.returncode == 0 and marker in output and 'Error' not in output, output.strip()[-1500:]


def two_raters(session, writer, folder, worksheet):
    titles, columns = ['First rater', 'Second rater'], [FIRST, SECOND]
    suffix = WORKSHEET if worksheet else ''
    state = run(session, {'ci': 95, 'responses': selection(titles, columns) if worksheet else entered(titles, columns), 'method': '1'})
    k = state['values']
    table = crosstab(state['html'])
    pairs = sum(sum(row) for row in table)
    check(pairs == 7, 'native kappa of padded raters tabulates the 7 subjects both rated, not the 12 rows of the padded frame' + suffix,
          (pairs, table))
    record = json.loads(state['record'])
    if not worksheet:
        responses = next(item for item in record['inputs'] if item['name'] == 'responses')
        padded = responses.get('columns', [{}, {}])[1].get('values', [])
        check(responses.get('kind') == 'entered' and len(padded) == 12 and all(v is None for v in padded[7:]),
              'the record keeps the padded rows of the second rater as missing values', responses)
    script = writer.write(record)
    check(script.get('hasRecipe') and not script.get('dataUnavailable'), 'the padded kappa replays from its record' + suffix,
          {key: value for key, value in script.items() if key != 'text'})
    reference = ('first <- ' + vector(FIRST[:7]) + '\nsecond <- ' + vector(SECOND) + '\n'
                 'tab <- table(factor(first, 1:3), factor(second, 1:3))\nN <- sum(tab)\npo_ref <- sum(diag(tab)) / N\n'
                 'pe_ref <- sum(rowSums(tab) * colSums(tab)) / N^2\nkappa_ref <- (po_ref - pe_ref) / (1 - pe_ref)\n')
    assertions = (reference + 'stopifnot(N == 7, n == 7, isTRUE(all.equal(kappa_ref, 11 / 32)), isTRUE(all.equal(c('
                  + number(k['kappa']) + ', ' + number(k['po'] / 100) + '), c(kappa_ref, po_ref), tolerance = 1e-12)), '
                  'isTRUE(all.equal(unname(c(kappa, se0, se, kappaw, se0w, sew, (po - spe) / (1 - spe))), '
                  + vector([float(k[key]) for key in ('kappa', 'se', 'seci', 'kappaw', 'sekw', 'sekwci', 'spi')])
                  + ", tolerance = 1e-10, check.attributes = FALSE)))\ncat('SAVED_KAPPA_PADDED_OK\\n')")
    name = 'saved-kappa-padded' + ('-worksheet' if worksheet else '')
    ok, output = run_r(folder, name, script['text'] + '\n' + assertions, 'SAVED_KAPPA_PADDED_OK')
    check(ok, name + ': real R executes the exported script and validates the original data', output)


def three_raters(session, folder, worksheet):
    titles = ['Rater 1', 'Rater 2', 'Rater 3']
    suffix = WORKSHEET if worksheet else ''
    state = run(session, {'ci': 95, 'responses': selection(titles, RATERS) if worksheet else entered(titles, RATERS)})
    k = state['values']
    check(int(k.get('categories', -1)) == 2 and k.get('r') == '2 to 3 (median 3)',
          'native kappa of three padded raters counts 2 to 3 ratings per subject' + suffix, (k.get('categories'), k.get('r')))
    reference = ('X <- cbind(' + ', '.join('c(' + ', '.join([str(v) for v in rater] + ['NA'] * (8 - len(rater))) + ')' for rater in RATERS) + ')\n'
                 'm <- rowSums(!is.na(X))\nx <- rowSums(X == 1, na.rm = TRUE)\nn <- length(m)\nmbar <- mean(m)\npbar <- sum(x) / sum(m)\n'
                 'B <- sum((x - m * pbar)^2 / m) / n\nW <- sum(x * (m - x) / m) / (n * (mbar - 1))\nkappa_ref <- (B - W) / (B + (mbar - 1) * W)\n')
    assertions = (reference + 'stopifnot(identical(as.vector(m), c(3, 3, 3, 3, 3, 2, 2, 2)), isTRUE(all.equal(' + number(k['k'])
                  + ", kappa_ref, tolerance = 1e-12)))\ncat('SAVED_KAPPA_THREE_OK\\n')")
    name = 'saved-kappa-three-padded' + ('-worksheet' if worksheet else '')
    ok, output = run_r(folder, name, '\n' + assertions, 'SAVED_KAPPA_THREE_OK')
    check(ok, name + ': real R executes the exported script and validates the original data', output)


if __name__ == '__main__':
    (ROOT / '.build').mkdir(exist_ok=True)
    folder = Path(tempfile.mkdtemp(prefix='kappa-padded-raters-', dir=ROOT / '.build'))
    session, writer = Session(), Writer()
    try:
        for worksheet in (False, True):
            attempt('Kappa, padded raters' + (WORKSHEET if worksheet else ''), lambda: two_raters(session, writer, folder, worksheet))
        for worksheet in (False, True):
            attempt('Kappa, three padded raters' + (WORKSHEET if worksheet else ''), lambda: three_raters(session, folder, worksheet))
    finally:
        writer.close()
        session.finish()
    print(f'KAPPA PADDED RATERS: {checks} checks passed, {len(failures)} failed', flush=True)
    if failures:
        print('Retained test artifacts: ' + str(folder), flush=True)
        raise SystemExit('FAIL: ' + '; '.join(failures))
    shutil.rmtree(folder)
