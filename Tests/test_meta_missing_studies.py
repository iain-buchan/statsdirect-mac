"""Incomplete studies in the meta-analyses through the Mac operation host and real R, as Windows's tests/RScript/MetaMissingStudies.cs
(5.3.10) checks them.

Each analysis runs with one study incomplete, either as a whole blank worksheet row without a column of study names or as one typed *
cell with the names given as a Text frame, at the session preference meta-exact false and then true (Windows's MetaExact). The native
report must omit only that study and keep the acquired label of each of the others; the script written from the run's record by
statsdirect_r_script (the Mac's RScriptWriter entry, given the worksheet's cells as Windows's checks give cells.Read) must run in R, say
"(1 other rows not used)", and reproduce the native k, labels, Cochran's Q, I-squared with its interval and every study's limits.

Mirrored from Windows: the fixtures, the study names, the incomplete third study, both patterns at both exact settings, the R assertions
(the same expressions, all.equal at tolerance 2e-7) and the four checks of each run. Where the Mac host gives the figures otherwise:
- The native ParameterBag is not returned: the run's finite scalar outputs ('values') give Q, I-squared and its limits at full
  precision (Constant.MISSING, double.MinValue, kept there as a finite number, and an absent NaN are NA, as Windows's Number() makes
  them); the per-study blocks are read from the report, which prints 12 decimal places here (decp 12, the most Analysis Options
  allow), so the rounding, at most 5e-13, is far inside Windows's tolerance. The effect size analysis keeps its pooled figures in a
  block (*poolok) that 'values' leaves out: its Q is read from the report at 12 decimal places, and its I-squared and limits, which the
  report prints to one decimal place, are compared to that precision (half a unit in the last place printed, plus 2e-7 relative).
- The Windows test host fills a parameter without the picker's validators. The Mac host applies them, as the Windows picker does
  (SdApplication.FillParameter calls the same shared ValidationProcessor). A missing value is refused for the summary statistic
  of a ratio type (Positive) and the confidence limits (NoMissingData). Those runs must be refused with exactly that validator's
  message at that frame. ProportionMeta keeps missing totals and counts aligned so its analysis can omit the incomplete study.
  Since 5.3.9 Windows puts each
  selection through the picker's validators too (RunAtPicker) and asserts the verdict both ways: a selection the picker refuses is
  "record-only" (it reaches a replay only in a stored record), every other selection must be accepted, and each run has one check of
  that, with Windows's flags (the label of a record-only run ends "-record-only"). Windows still replays the record-only selections,
  since its checking host runs on after a refusal; the Mac host stops at the refusal, as the picker does, so each refused run is
  covered instead by the same analysis of the five complete studies (the incomplete row deleted, so nothing is missing and R drops
  nothing) and, for the summary statistic of a ratio, by the same pattern with the "other difference" type, whose estimate has no
  domain validator (its confidence limits are still refused, as Windows's comment on the picker says).
The worksheet is the test workbook's "Modes" sheet, as Windows's RecordCells names it, with its titles in row 1 (the Mac grid keeps titles
for the whole sheet, so the numeric columns are titled "Column 1" and so on, as Windows titles its untitled columns).
"""
from concurrent.futures import ThreadPoolExecutor
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time

from r_runtime import rscript
from test_menu import ROOT, Session
from test_pr6_replay import RWriter
from test_shared_engine_update import NUMBER, ReportText


WORKBOOK = ROOT / 'Content/Examples/test.xlsx'   # Windows Record.cs: the test workbook, whose sheet RecordCells calls "Modes"
SHEET = 'Modes'
NAMES = ['Alpha trial', 'Beta trial', 'Incomplete trial', 'Delta trial', 'Epsilon trial', 'Zeta trial']
OMITTED = 2
MISSING = -1.7976931348623157e308   # Constant.MISSING
TOLERANCE = '2e-7'

EXPOSED = [100, 150, 110, 80, 200, 120]
EVENTS = [20, 35, 23, 10, 60, 50]
CONTROL = [100, 140, 125, 90, 210, 115]
CONTROL_EVENTS = [12, 20, 18, 12, 30, 15]
ESTIMATES = [1.5, .8, 1.7, 2, 1.15, 2.6]
ERRORS = [.12, .18, .22, .21, .15, .25]
DIFFERENCES = [.05, -.02, .10, .03, .08, -.04]
DIFFERENCE_ERRORS = [.03, .04, .05, .02, .06, .03]
PROPORTION_EVENTS = [0, 35, 23, 10, 60, 50]
TABLES = [('sn', EXPOSED), ('sr', EVENTS), ('xn', CONTROL), ('xr', CONTROL_EVENTS)]
RATES = [('pt1', EXPOSED), ('a', EVENTS), ('pt2', CONTROL), ('b', CONTROL_EVENTS)]
EN = [34, 50, 39, 24, 41, 28]
CN = [39, 44, 35, 29, 48, 36]
MEANS = [('en', EN), ('cn', CN), ('em', [11, 8, 9, 10, 14, 13]), ('es', [2.1, 2.5, 2.8, 3.4, 2.2, 2.6]),
         ('cm', [8, 10, 9, 8, 11, 8]), ('cs', [1.8, 2, 3.1, 3.2, 2.9, 2.4])]

# The checks in Windows's order: (operation, columns, the input missing in the typed-cell pattern, settings, Windows's recordOnly
# flags: whether the picker refuses the whole blank row and the typed * cell)
ACCEPTED = (False, False)
CASES = [(operation, TABLES, 'xr', {}, ACCEPTED) for operation in ('RelativeRiskMeta', 'RiskDifference', 'PetoMeta', 'Mantel')]
CASES += [(operation, RATES, 'pt2', {}, ACCEPTED) for operation in ('MetaIncidenceRateRatio', 'MetaIncidenceRateDifference')]
CASES += [# A ratio's estimate must be positive, so the picker refuses a blank one; a blank standard error it takes.
          ('MetaSummary', [('y', ESTIMATES), ('se_y', ERRORS)], 'se_y', {'type': 'oddsRatio', 'use_ci': 'false'}, (True, False)),
          # The picker also requires complete confidence-limit columns: a ratio with limits has no reachable blank.
          ('MetaSummary', [('y', ESTIMATES), ('ll_y', [1.2, .55, 1.1, 1.3, .85, 1.6]), ('ul_y', [1.9, 1.2, 2.2, 3.1, 1.6, 4.2])], 'y',
           {'type': 'oddsRatio', 'use_ci': 'true'}, (True, True)),
          # A difference may be negative or blank: a blank estimate, standard error or whole row reaches the analysis from the
          # picker, apart from a whole row with blank limits (the two cases Windows added at 5.3.9).
          ('MetaSummary', [('y', DIFFERENCES), ('se_y', DIFFERENCE_ERRORS)], 'se_y', {'type': 'riskDifference', 'use_ci': 'false'}, ACCEPTED),
          ('MetaSummary', [('y', DIFFERENCES), ('ll_y', [v - .06 for v in DIFFERENCES]), ('ul_y', [v + .06 for v in DIFFERENCES])], 'y',
           {'type': 'riskDifference', 'use_ci': 'true'}, (True, False)),
          ('Effect', [('en', EN), ('cn', CN), ('g', [.42, -.1, .3, .22, .85, 1.1])], 'g', {'type': 'g'}, ACCEPTED)]
CASES += [('Effect', MEANS, 'cs', {'type': kind}, ACCEPTED) for kind in ('d', 'm')]
# Missing totals and counts stay aligned so the analysis can omit the incomplete study.
# fudge is answered as Windows answers it; ProportionMeta.xml no longer asks it (#893), on either platform
CASES += [('ProportionMeta', [('sn', EXPOSED), ('sr', PROPORTION_EVENTS)], 'sr', {'fudge': .5, 'method': 'doubleArcsine'}, ACCEPTED)]

# Windows's switch: the block of each study's figures, the R label vector, its default label, R's Q, R's per-study limits and the
# block's lower and upper keys; for the Mac, the report table that prints that block (its heading, a cell's prefix or None for any)
# and the table's columns of the two limits.
SPEC = {
    'RelativeRiskMeta': ('*risks', 'study', 'Study', 'q', 'ci[,1],ci[,2]', ('Stratum', 'Relative risk', '95% CI'), 2, 3),
    'RiskDifference': ('*differences', 'study', 'Study', 'q', 'ci[,1],ci[,2]', ('Stratum', 'Risk difference', '95% CI'), 2, 3),
    'PetoMeta': ('*odds', 'study', 'Trial', 'Q', 'lower,upper', ('Stratum', 'O-E', 'Odds ratio', '95% CI'), 3, 4),
    'Mantel': ('*or', 'strata', 'stratum', 'q', 'lci,uci', ('Stratum', 'Odds ratio', '95% CI'), 2, 3),
    'MetaSummary': ('*studies', 'study', 'Study', 'q', 'lower,upper', ('Study', None, 'SE', 'Approximate 95% CI'), 3, 4),
    'Effect': ('*approximate', 'trial', 'Trial', 'Q', 'lcid,ucid', ('Stratum', 'N (exptl.)', 'N (ctrl.)', None, 'Approximate 95% CI'), 4, 5),
    'ProportionMeta': ('*proportions', 'trial', 'Trial', 'q', 'ci[,1],ci[,2]', ('Stratum', 'Proportion', '95% CI'), 2, 3),
    'MetaIncidenceRateRatio': ('*ir', 'strata', 'Stratum', 'res_r$q', 'exact[1,],exact[2,]', ('Stratum', 'IRR', '95% CI'), 2, 3),
    'MetaIncidenceRateDifference': ('*ir', 'strata', 'Stratum', 'res$q', 'ird-z*se_ird,ird+z*se_ird', ('Stratum', 'IRD', '95% CI'), 2, 3),
}
# the recipes that bind the recorded exact preference (Tests/test_run_record.py's binding list; the incidence rate recipes do not)
EXACT_BOUND = {'RelativeRiskMeta', 'RiskDifference', 'PetoMeta', 'Mantel', 'MetaSummary', 'Effect', 'ProportionMeta'}

# The frame refused and the validator's message, keyed by (operation, type, use_ci, pattern).
POSITIVE = 'Data must be positive non-zero numbers'
NO_MISSING = 'Data with missing values cannot be used here'
REFUSED = {
    ('MetaSummary', 'oddsRatio', 'false', 'row'): ('y', POSITIVE),          # MetaSummary.xml: y is Positive when use_ratio
    ('MetaSummary', 'oddsRatio', 'true', 'row'): ('y', POSITIVE),
    ('MetaSummary', 'oddsRatio', 'true', 'cell'): ('y', POSITIVE),
    ('MetaSummary', 'otherDifference', 'true', 'row'): ('ll_y', NO_MISSING),  # ll_y and ul_y are NoMissingData for every type
    ('MetaSummary', 'riskDifference', 'true', 'row'): ('ll_y', NO_MISSING),
}
SUBSTITUTE_TYPE = 'otherDifference'

checks = 0
failures = []


def check(ok, what, detail=''):
    global checks
    if not ok:
        raise AssertionError('FAIL ' + what + (': ' + str(detail) if detail else ''))
    checks += 1
    print('PASS: ' + what, flush=True)


def cell(value):
    """A number as the worksheet cell shows it, and as the Mac form sends it."""
    return str(int(value)) if float(value).is_integer() else repr(float(value))


def worksheet(title, texts, column):
    """A one-column worksheet answer as the form sends it (Grid/operation-data.mjs worksheetInputFrom), with the workbook's path."""
    last = len(texts) + 1
    return {'source': f'{WORKBOOK.name} / {SHEET} · rows 2–{last}', 'range': {'firstRow': 2, 'lastRow': last, 'columns': [column]},
            'preserveRows': True, 'columns': [{'title': title, 'values': list(texts)}],
            'worksheet': {'workbook': WORKBOOK.name, 'workbookPath': str(WORKBOOK), 'sheet': 0, 'sheetName': SHEET,
                          'hasTitle': True, 'titles': [title]}}


def r_vector(values):
    """RScriptWriter.Vector: numbers in their shortest round-trip form and a missing one as NA, else quoted text."""
    if all(v is None or isinstance(v, float) for v in values):
        def number(v):
            if v is None:
                return 'NA'
            if math.isnan(v):
                return 'NaN'
            if math.isinf(v):
                return 'Inf' if v > 0 else '-Inf'
            return repr(v)
        return 'c(' + ', '.join(number(v) for v in values) + ')'
    return 'c(' + ', '.join('NA' if v is None else json.dumps(v) for v in values) + ')'


def equal(expression, expected):
    """Windows's Equal: R's figures and the native ones, all.equal at 2e-7."""
    return ('stopifnot(isTRUE(all.equal(unname(c(' + expression + ')), ' + r_vector(expected) +
            ', tolerance=' + TOLERANCE + ', check.attributes=FALSE)))\n')


def decimals(text):
    return len(text.split('.', 1)[1]) if '.' in text else 0


def printed(expression, texts):
    """R's figures and the report's, to the precision the report prints them: within half a unit of its last decimal place,
    with Windows's tolerance beyond that."""
    values = [float(t) for t in texts]
    allowance = [0.5 * 10 ** -decimals(t) for t in texts]
    return ('stopifnot(isTRUE(all(abs(c(' + expression + ') - ' + r_vector(values) + ') <= ' + r_vector(allowance) +
            ' + ' + TOLERANCE + ' * abs(' + r_vector(values) + '))))\n')


def native_number(values, key):
    """Windows's Number(): a missing value or NaN is null (NA). The Mac's scalar outputs keep MISSING and leave NaN out."""
    value = values.get(key)
    if value is None or isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    value = float(value)
    return None if value == MISSING or math.isnan(value) else value


def run(session, operation, answers, preferences):
    """The operation through the Mac host with the answers, as Windows's Host answers its parameters: a prompt the answers do not
    name fails the run. Returns (snapshot, None) for a finished run, (None, (prompt, message)) when the host refuses an answer."""
    ident, state = session.start(operation, preferences)
    try:
        for _ in range(100):
            if state.get('state') != 'input':
                break
            prompt = state['prompt']
            if prompt.get('error'):
                return None, (prompt.get('name'), prompt['error'])
            if prompt.get('name') not in answers:
                raise AssertionError(f'{operation} asked for {prompt.get("name")} ({prompt["kind"]}), which these checks do not answer')
            session.request(action='answer', id=ident, token=state['token'], value=answers[prompt['name']])
            state = session.wait(ident)
        assert state.get('state') == 'complete', (operation, state.get('state'), state.get('error'))
        return state, None
    finally:
        session.close(ident)


def study_tables(html):
    """The report's tables of one row per study: (the heading row, whose first cell is Stratum or Study, and the numbered rows)."""
    tables = []
    for part in html.split('<table')[1:]:
        rows = ReportText('<table' + part.split('</table>', 1)[0] + '</table>').rows
        if rows and rows[0] and rows[0][0] in ('Stratum', 'Study'):
            tables.append((rows[0], [row for row in rows[1:] if row and row[0].isdigit()]))
    return tables


def heading_matches(heading, expected):
    return len(heading) >= len(expected) and all(e is None or h.startswith(e) for h, e in zip(heading, expected))


def label_of(operation, settings, exact, whole_row, record_only=False):
    """Windows's label: the operation, its first setting (else default), use_ci, MetaExact, the pattern and, for a selection the
    picker refuses, "-record-only"."""
    first = str(next(iter(settings.values()))) if settings else 'default'
    return (f'{operation}-{first}-{settings.get("use_ci", "")}-{exact}-{"row" if whole_row else "cell"}' +
            ('-record-only' if record_only else ''))


def verify(session, writer, folder, operation, columns, missing_input, settings, whole_row, labelled, exact, deleted=False, label=None):
    """Windows's Verify through the Mac host. Returns the R job for a finished run, or ('refused', prompt, message)."""
    label = label or label_of(operation, settings, exact, whole_row)
    count = len(columns[0][1])
    raw = [[cell(v) for v in values] for _, values in columns]
    names = list(NAMES)
    if deleted:   # the five complete studies alone: the incomplete row deleted from the worksheet
        raw = [texts[:OMITTED] + texts[OMITTED + 1:] for texts in raw]
        names = names[:OMITTED] + names[OMITTED + 1:]
        n = count - 1
        rows = n
    else:
        for i, (name, _) in enumerate(columns):
            if whole_row or name == missing_input:
                raw[i][OMITTED] = '' if whole_row else '*'
        n = count - 1
        rows = count
    answers = dict(settings)
    answers['gamma'] = 95   # .95, which the Mac's confidence prompt takes as a percentage
    label_input = 'studies' if operation == 'MetaSummary' else 'strata'
    answers[label_input] = worksheet('Study names', names, len(columns)) if labelled else {'skip': True}
    for i, (name, _) in enumerate(columns):
        answers[name] = worksheet(f'Column {i + 1}', raw[i], i)
    state, refusal = run(session, operation, answers, {'use-default-ci': False, 'decp': '12', 'meta-exact': exact})
    if refusal:
        return ('refused',) + refusal
    block, label_vector, default_label, q, limits, heading, low, high = SPEC[operation]
    report = ReportText(state['html'])
    tables = study_tables(state['html'])
    expected_names = [name for i, name in enumerate(NAMES) if i != OMITTED] if labelled else [f'{default_label} {i}' for i in range(1, n + 1)]

    # Windows counts the block's rows; the Mac reads the table that prints the block, and every other table of studies the report has
    found = [rows_of for heading_row, rows_of in tables if heading_matches(heading_row, heading)]
    check(len(found) == 1 and len(found[0]) == n and all(len(t[1]) == n for t in tables) and all(len(r) > high for r in found[0]),
          label + (' native analysis keeps the five complete studies' if deleted else ' native analysis omits only the incomplete study'),
          (block, [(t[0], len(t[1])) for t in tables]))
    studies = found[0]
    if labelled:
        # as Windows compares lb of the block's rows (a prefix: a study may carry a note); every table of studies labels its rows, and
        # the omitted study's label appears nowhere in the report, its plots included
        check(all(r[-1].startswith(name) for _, rows_of in tables for r, name in zip(rows_of, expected_names))
              and NAMES[OMITTED] not in report.text,
              label + ' native report keeps the acquired label of each complete study', [[r[-1] for r in rows_of] for _, rows_of in tables])

    values = state['values']
    if operation == 'Effect':
        # the pooled block *poolok is not among the scalar outputs: the report's line of each, as printed
        q_line = re.findall(r'Cochran Q = (' + NUMBER + r')\s+\(df = \d+\)', report.text)
        i2_line = re.findall(r'I² \(inconsistency\) = (' + NUMBER + r')% \(\s*\d+% CI = (' + NUMBER + r')% to (' + NUMBER + r')%\s*\)', report.text)
        assert len(q_line) == 1 and len(i2_line) == 1, (label, 'pooled lines', q_line, i2_line)
        q_native, i2_texts = [float(q_line[0])], list(i2_line[0])
    else:
        q_native = [native_number(values, 'qc')]
    r_checks = 'stopifnot(k == ' + str(n) + ', identical(' + label_vector + ', ' + r_vector(expected_names) + '))\n'
    r_checks += equal(q, q_native)
    if operation in ('MetaIncidenceRateDifference', 'MetaIncidenceRateRatio'):
        r_checks += equal(f'max(0, 100 * (1-(k-1)/({q})))', [native_number(values, 'isq')])
    elif operation == 'Effect':
        r_checks += printed('i2,i2_ci', i2_texts)
    else:
        r_checks += equal('i2,i2_ci', [native_number(values, key) for key in ('isq', 'llisq', 'ulisq')])
    r_checks += equal(limits, [float(r[low]) for r in studies] + [float(r[high]) for r in studies])
    if operation == 'ProportionMeta':
        r_checks += 'stopifnot(adherent[1] == 0, p[1] == 0, ci[1,1] == 0)\n'
    r_checks += "cat('META_MISSING_STUDIES_OK\\n')\n"

    record = json.loads(state['record'])
    texts = {name: raw[i] for i, (name, _) in enumerate(columns)}
    places = {name: i for i, (name, _) in enumerate(columns)}
    if labelled:
        texts[label_input], places[label_input] = names, len(columns)
    # every frame is recorded as a pointer to the cells selected (1-based column, rows counted from the title row), and the writer is
    # given the worksheet's cells of each, as Windows gives it cells.Read
    pointers = [item for item in record['inputs'] if item.get('kind') == 'frame' and item.get('columns')]
    selected = sorted(item['name'] for item in pointers) == sorted(texts) and all(
        len(item['columns']) == 1 and item['columns'][0].get('column') == places[item['name']] + 1 and
        item['columns'][0].get('rows') == [1, rows + 1] and item['columns'][0].get('hasTitle') and item['columns'][0].get('hash')
        for item in pointers)
    frames = [{'name': item['name'], 'columns': [{'title': c.get('title'), 'values': texts[item['name']]} for c in item['columns']]}
              for item in pointers if item['name'] in texts]
    try:
        script = writer.write(record, frames)   # hasRecipe, not dataUnavailable, nothing to relocate, no cell marked changed
    except AssertionError as error:
        raise AssertionError('FAIL ' + label + ' replays the acquired worksheet selection: ' + str(error)[:2000])
    exact_kept = operation not in EXACT_BOUND or record['parameters'].get('metaExact') is exact   # 5.3.8: read once, recorded
    check(selected and exact_kept, label + ' replays the acquired worksheet selection', (record['parameters'], pointers))
    return {'label': label, 'code': script['text'] + '\n' + r_checks, 'folder': folder / re.sub(r'[^A-Za-z0-9.-]+', '_', label),
            'dropped': not deleted}


def run_r(job):
    """Windows's DeferredR538: Rscript --vanilla in the run's own folder, within 60 seconds, its output kept beside the script."""
    folder = job['folder']
    folder.mkdir(parents=True)
    (folder / 'script.R').write_text(job['code'])
    environment = {k: v for k, v in os.environ.items() if not (k in ('LC_ALL', 'LC_CTYPE') and v == 'C.UTF-8')}
    started = time.monotonic()
    try:
        result = subprocess.run([rscript(), '--vanilla', '--encoding=UTF-8', str(folder / 'script.R')], cwd=folder, env=environment,
                                text=True, capture_output=True, timeout=60)
    except subprocess.TimeoutExpired:
        return job, None, 'FAIL R exceeded 60 seconds in ' + str(folder)
    (folder / 'elapsed-ms.txt').write_text(str(round(1000 * (time.monotonic() - started))))
    (folder / 'stdout.txt').write_text(result.stdout)
    (folder / 'stderr.txt').write_text(result.stderr)
    if result.returncode != 0:
        return job, None, 'FAIL R in ' + str(folder) + ':\n' + result.stdout[-1500:] + '\n' + result.stderr[-2500:]
    return job, result.stdout, None


def attempt(what, step):
    try:
        return step()
    except Exception as error:
        failures.append(what)
        print(str(error) if str(error).startswith('FAIL') else 'FAIL: ' + what + ': ' + repr(error)[:3000], flush=True)
        return None


if __name__ == '__main__':
    (ROOT / '.build').mkdir(exist_ok=True)
    folder = Path(tempfile.mkdtemp(prefix='meta-missing-studies-', dir=ROOT / '.build'))
    session, writer = Session(), RWriter()
    jobs = []
    try:
        for operation, columns, missing_input, settings, record_only_flags in CASES:
            for exact in (False, True):
                for whole_row, labelled in ((True, False), (False, True)):
                    record_only = record_only_flags[0 if whole_row else 1]
                    label = label_of(operation, settings, exact, whole_row, record_only)
                    outcome = attempt(label, lambda: verify(session, writer, folder, operation, columns, missing_input, settings,
                                                            whole_row, labelled, exact, label=label))
                    key = (operation, settings.get('type') if operation == 'MetaSummary' else None, settings.get('use_ci'),
                           'row' if whole_row else 'cell')
                    if outcome is None:
                        continue
                    # Windows's check of the picker's verdict (5.3.9), both ways: a record-only selection must be refused, and
                    # every other selection accepted
                    refused = not isinstance(outcome, dict)
                    if record_only:
                        verdict = ': the picker refuses this selection' + (' (%s: %s)' % outcome[1:] if refused else '') + ', so it is record-only'
                    else:
                        verdict = ': the picker accepts this selection' + (', but it refused %s: %s' % outcome[1:] if refused else '')
                    attempt(label, lambda: check(refused == record_only, label + verdict))
                    if not refused:
                        jobs.append(outcome)   # an accepted selection was checked in full, whatever its flag
                        continue
                    _, prompt, message = outcome
                    if not attempt(label, lambda: check(REFUSED.get(key) == (prompt, message),
                                                        f'{label} is refused at {prompt} by the shared validator ("{message}"), '
                                                        'as the Windows picker refuses it', (prompt, message)) or True):
                        continue
                    # covered instead: the summary statistic's pattern with a type whose estimate has no domain validator ...
                    if operation == 'MetaSummary' and prompt == 'y':
                        substitute = dict(settings, type=SUBSTITUTE_TYPE)
                        other = label + ' (' + SUBSTITUTE_TYPE + ' instead of ' + settings['type'] + ')'
                        sub_key = (operation, SUBSTITUTE_TYPE, settings.get('use_ci'), key[3])
                        result = attempt(other, lambda: verify(session, writer, folder, operation, columns, missing_input, substitute,
                                                               whole_row, labelled, exact, label=other))
                        if isinstance(result, dict):
                            jobs.append(result)
                        elif result is not None:   # expected only for blank confidence limits, which no type accepts
                            attempt(other, lambda: check(REFUSED.get(sub_key) == result[1:],
                                                         f'{other} is refused at {result[1]} by the shared validator ("{result[2]}"), '
                                                         'as the Windows picker refuses it', result[1:]))
                    # ... and the five complete studies, the incomplete row deleted: the same validators must accept them, which also
                    # shows the refusal was for the missing value (a value out of the validator's domain gives the same message)
                    complete = label + ' (incomplete row deleted)'
                    result = attempt(complete, lambda: verify(session, writer, folder, operation, columns, missing_input, settings,
                                                              whole_row, labelled, exact, deleted=True, label=complete))
                    if isinstance(result, dict):
                        jobs.append(result)
                    elif result is not None:
                        failures.append(complete)
                        print('FAIL: ' + complete + ' refused at ' + str(result[1:]), flush=True)
        # the scripts in R, several at a time; each in its own folder
        with ThreadPoolExecutor(max_workers=max(2, min(8, os.cpu_count() or 2))) as pool:
            outputs = list(pool.map(run_r, jobs))
        for job, output, error in outputs:
            def replayed():
                if error:
                    raise AssertionError(error)
                note = '(1 other rows not used)' in output
                check('META_MISSING_STUDIES_OK' in output and (note if job['dropped'] else 'other rows not used' not in output),
                      job['label'] + (' preserves study order, labels and native results in R' if job['dropped'] else
                                      ' gives the native results in R, which drops no study'), output[-1500:])
            attempt(job['label'] + ' in R', replayed)
    finally:
        writer.close()
        session.finish()
    print(f'META MISSING STUDIES: {checks} checks passed, {len(failures)} failed, {len(jobs)} R replays', flush=True)
    if failures:
        print('Retained test artifacts: ' + str(folder), flush=True)
        raise SystemExit(1)
    shutil.rmtree(folder)
