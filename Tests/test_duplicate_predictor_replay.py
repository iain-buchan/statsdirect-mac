"""Predictors that share a title stay distinct terms of the model when a regression is replayed in R (Windows PR #8, e7fbfee1).

A port of Windows's tests/RScript/DuplicatePredictorReplay.cs (e7fbfee1) to the Mac operation host, the engine's R script entry
(statsdirect_r_script, through Tests/engine-driver) and real R. Up to 5.3.8 the shared RScriptWriter wrote a regression's predictor
list under each column's title as it had it: when the predictors were typed in or read again from their workbook, two columns of one
title were one name in the list and one term of the model formula (R fits `X` + `X` as the first X alone); the values a record holds
already had distinct keys (RunRecord.UniqueTitle: X, X_2), but an untitled column's key was "", and list("" = ...), on any path,
is a script R refuses to parse. Since e7fbfee1 the writer names every model predictor by the held keys' rule (which leaves held keys
as they are) and an untitled one Column, made distinct after every stored key is reserved.

Each fixture is fitted natively through the Mac host twice, its predictors typed in and selected from a worksheet (rows 2 to n + 1
under a title row, NumericPreserveRows as the form sends them), and replayed in R by the three paths Windows checks:
- entered: the record of the typed run;
- held: the record of the worksheet run, which holds the values the analysis used (the embedded data);
- reread: that record without its data block, with the frames the Mac host supplies when it reads the values again from the open
  grid or the closed workbook (RunRecordR.requests, then either reader): for each frame the record does not hold, by its index,
  each pointer column's cells over its recorded rows below the title row, as the grid's texts and kinds, under the record's title.
The fixtures:
- windows-titles: DuplicatePredictorReplay.cs's, value for value: 16 observations of Y, typed, and six indicator predictors titled
  outcome, outcome_2, outcome, (none), "" and Column, so two distinct predictors are titled outcome (the recipe's own name for the
  response) and two are untitled. A typed column or a worksheet cell has no null title: the Windows null is blank here, as
  RunRecord writes a null title (""), so the record holds the same titles on both. The worksheet run must hold its values under the
  Windows storedTitles (outcome, outcome_2, outcome_3, "", _2, Column), every path must name the predictors as the Windows
  expectedTitles (outcome, outcome_2, outcome_3, Column_2, _2, Column), and the coefficients are c(7, 1:6), as constructed.
- same-title-pair: the Windows weighted fixture's Y, X1 and X2 (PosthocWeighted537.cs), unweighted, X1 and X2 both titled X, the
  outcome selected from the worksheet beside them, so the reread path reads both frames; the predictors must be named X and X_2.
Checked as Windows checks, for each path: the script has its recipe and the predictor data are available for it; in R, after the
replay, names(predictors) are the expected names in order, the fit's rank is the native rank, the coefficients agree with the native
at all.equal tolerance 1e-10 (for windows-titles also with c(7, 1:6), as there) and, where a predictor is titled outcome, the
response is not that predictor (sd_own[1] is not outcome).
Checked otherwise, because the Mac host returns only a run's finite scalar outputs: the native coefficients are read from the
report, printed to 12 decimal places (decp 12), under Intercept and each predictor's title with none dropped, and each must also
agree with R's within half a unit of its last printed place plus 1e-10 of it; the native rank is their number, which must be the
ANOVA follow-on's regression degrees of freedom plus one. The model's response must be the outcome, value for value, and the reread
script must find every column as recorded (no column changed or moved, nothing to look for along the sheet).
"""
import copy
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

from r_runtime import rscript
from test_menu import ROOT, Session, columns
from test_pr6_replay import RWriter, sheet
from test_shared_engine_update import ReportText


PREFS = {'use-default-ci': True, 'default-ci': '95', 'decp': '12', 'pdecp': '7'}
PLACES = int(PREFS['decp'])
OK = 'DUPLICATE_PREDICTORS_OK'

# DuplicatePredictorReplay.cs: predictor j is 1 in observations 2j and 2j + 1 and 0 elsewhere; Y is 7 + j + 1 in those two and 7 in
# the last four, each pair 0.25 below and above, so the intercept is 7 and the coefficients 1 to 6.
ROWS = range(16)
WINDOWS_TITLES = ['outcome', 'outcome_2', 'outcome', '', '', 'Column']   # the fourth is null in the Windows check
WINDOWS_X = [[1 if i // 2 == j else 0 for i in ROWS] for j in range(len(WINDOWS_TITLES))]
WINDOWS_Y = [7 + ((i // 2 + 1) if i // 2 < len(WINDOWS_TITLES) else 0) + (-.25 if i % 2 == 0 else .25) for i in ROWS]

# PosthocWeighted537.cs's Y, X1 and X2, value for value.
Y = [8.73, 8.83, 14.58, 9.89, 9.16, 11.35, 5.24, 7.19, 13.24, 7.65, 8.36, 7.69, 12.42, 5.96, 12.51, 10.52, 5.53, 11.18, 14.38]
X1 = [7.55, 5.12, 7.15, 5.93, 3.56, 4.63, 2.06, 2.18, 9.42, 7.08, .55, 2.28, 2.73, .07, 7.53, 5.75, .42, 9.61, 8.74]
X2 = [1, 0, 1, 1, 0, 1, 0, 1, 1, 0, 1, 1, 1, 1, 0, 1, 1, 0, 0]

FIXTURES = [
    {'label': 'windows-titles', 'outcome': ('Y', WINDOWS_Y), 'predictors': list(zip(WINDOWS_TITLES, WINDOWS_X)), 'outcome_in_sheet': False,
     'stored': ['outcome', 'outcome_2', 'outcome_3', '', '_2', 'Column'],
     'names': ['outcome', 'outcome_2', 'outcome_3', 'Column_2', '_2', 'Column'],
     'constructed': [7, 1, 2, 3, 4, 5, 6]},
    {'label': 'same-title-pair', 'outcome': ('Y', Y), 'predictors': [('X', X1), ('X', X2)], 'outcome_in_sheet': True,
     'stored': ['X', 'X_2'], 'names': ['X', 'X_2'], 'constructed': None},
]


# The script's Data line for the predictors on each path: none for typed values, the held values, or the cells read again now.
NOTES = {'entered': lambda text: 'Data:' not in text,
         'held': lambda text: 'the values the analysis used.' in text and ', read on ' not in text,
         'reread': lambda text: ', read on ' in text and 'the values the analysis used.' not in text}


def check(ok, what, detail=None):
    if not ok:
        raise AssertionError(what if detail is None else f'{what}: {detail}')
    print('PASS:', what, flush=True)


class ScriptWriter(RWriter):
    """The R script entry as the Mac host calls it ({record, title, frames}); its answer is returned as it is, for the checks to judge."""
    def write(self, record, frames=()):
        self.process.stdin.write(json.dumps({'record': record, 'title': None, 'frames': list(frames)}) + '\n')
        self.process.stdin.flush()
        return json.loads(self.process.stdout.readline())


def typed(series):
    """Columns typed into the form under the given titles: an entered frame."""
    answer = columns(*[values for _, values in series])
    for column, (title, _) in zip(answer['columns'], series):
        column['title'] = title
    return answer


def selection(first, series):
    """Adjacent columns of the fixture's worksheet from column index `first`, titled in its first row, as the form selects them."""
    answer = sheet([title for title, _ in series], [values for _, values in series])
    answer['range']['columns'] = list(range(first, first + len(series)))
    return answer


def grid_text(value):
    """A number as the grid shows it (Snapshot.jsNumber): a whole number without a point; these fixtures need no exponent."""
    text = str(int(value)) if float(value).is_integer() else repr(float(value))
    assert 'e' not in text, text
    return text


def grid_frames(record, worksheet):
    """The frames the Mac host supplies for a record (RunRecordR.requests and its grid and workbook readers): each frame input whose
    values the record does not hold, in the record's order with its index, each pointer column's cells over its recorded rows (below
    the title row when it has one; the worksheet's first row is its titles) as the grid's texts and kinds, under the record's title."""
    held = record.get('data', {})
    frames = []
    for item in record['inputs']:
        if item.get('kind') != 'frame' or item.get('held', item['name']) in held:
            continue
        read = []
        for pointer in item['columns']:
            first, last = pointer['rows']
            first += 1 if pointer['hasTitle'] else 0
            cells = worksheet[pointer['column'] - 1][1][first - 2:last - 1]
            read.append({'title': pointer['title'], 'values': [grid_text(v) for v in cells], 'kinds': ['number'] * len(cells)})
        frames.append({'index': len(frames), 'name': item['name'], 'columns': read})
    return frames


def r_string(text):
    return '"' + text.replace('\\', '\\\\').replace('"', '\\"') + '"'


def r_vector(values):
    return 'c(' + ', '.join(repr(float(v)) for v in values) + ')'


def run_r(script, folder):
    folder.mkdir(parents=True, exist_ok=True)
    path = folder / 'script.R'
    path.write_text(script)
    result = subprocess.run([rscript(), '--vanilla', '--encoding=UTF-8', str(path)], cwd=folder, text=True, capture_output=True, timeout=60)
    (folder / 'output.txt').write_text(result.stdout + result.stderr)
    return result


def inputs(record):
    return {item['name']: item for item in record['inputs']}


def native_fit(session, answers, titles, evidence, label):
    """The native fit: its record, its coefficients as the report prints them (b0 the intercept, then each predictor under its title)
    and its rank, the number of coefficients, which must be the ANOVA follow-on's regression degrees of freedom plus one."""
    model = session.run('MultipleLinearRegression', answers, PREFS, keep=True)
    try:
        anova = session.run('MultipleLinearRegressionAnova', {'ci': 95}, PREFS, parent=model['id'])
    finally:
        session.close(model['id'])
    evidence.mkdir(parents=True, exist_ok=True)
    (evidence / 'model.html').write_text(model['html'])
    (evidence / 'record.json').write_text(model['record'])
    (evidence / 'anova.json').write_text(json.dumps(anova['values'], indent=1))
    # Every prompt answered as given (the 95% level may come from the preferences unasked): a fallback answer would change the model.
    asked = [entry['name'] for entry in model['history']]
    check(all(name in answers for name in asked) and {'outcome', 'predictors'} <= set(asked) and 'weights' not in asked,
          label + ' run asks only for the confidence level, intercept, weights choice and the two selections', asked)
    found = [(row[0], re.fullmatch(r'b(\d+) = (\S+)', row[1])) for row in ReportText(model['html']).rows if len(row) > 1]
    printed = [(title, int(match[1]), match[2]) for title, match in found if match]
    rank = len(printed)
    reg_df = anova['values'].get('reg_df')
    check([title for title, _, _ in printed] == ['Intercept'] + titles and [i for _, i, _ in printed] == list(range(rank))
          and 'dropped from the model' not in model['html'] and reg_df == rank - 1 == len(titles),
          label + f' fit keeps every predictor under its own title: rank {rank}, the ANOVA regression df {reg_df} plus one', (printed, reg_df))
    return json.loads(model['record']), [float(b) for _, _, b in printed], rank


def assertions(fixture, native, rank):
    """What R must find after the replay (DuplicatePredictorReplay.cs's stopifnot, with the native rank and coefficients)."""
    conditions = [f'identical(names(predictors), c({", ".join(r_string(name) for name in fixture["names"])}))',
                  f'fit$rank == {rank}L',
                  'identical(as.numeric(model.response(model.frame(fit))), as.numeric(outcome))',
                  'isTRUE(all.equal(unname(coef(fit)), native_coefficients, tolerance = 1e-10))',
                  # each figure as printed: within half a unit of its last place, plus 1e-10 of it
                  f'all(abs(unname(coef(fit)) - native_coefficients) <= 0.5 * 10^-{PLACES} + 1e-10 * abs(native_coefficients))']
    if 'outcome' in [title for title, _ in fixture['predictors']]:
        conditions.append("sd_own[1] != 'outcome'")
    if fixture['constructed']:
        conditions.append(f'isTRUE(all.equal(unname(coef(fit)), {r_vector(fixture["constructed"])}, tolerance = 1e-10))')
    return ('\n'
            f'native_coefficients <- {r_vector(native)}\n'
            "cat('NAMES', encodeString(names(predictors), quote = '\"'), '\\n')\n"
            "cat('RANK', fit$rank, '\\n')\n"
            "cat('COEFFICIENTS', sprintf('%.17g', coef(fit)), '\\n')\n"
            "if (length(coef(fit)) == length(native_coefficients))\n"
            "  cat('DIFFERENCE', sprintf('%.1e', max(abs(unname(coef(fit)) - native_coefficients))), '\\n')\n"
            'stopifnot(' + ',\n  '.join(conditions) + ')\n'
            f"cat('{OK}\\n')\n")


def check_fixture(session, writer, fixture, folder, failures):
    label = fixture['label']
    evidence = folder / label
    titles = [title for title, _ in fixture['predictors']]
    values = [list(v) for _, v in fixture['predictors']]
    n = len(fixture['outcome'][1])
    # the worksheet: the outcome in column A when it is selected from it, then the predictors
    worksheet = ([fixture['outcome']] if fixture['outcome_in_sheet'] else []) + fixture['predictors']
    first = 1 if fixture['outcome_in_sheet'] else 0
    common = {'ci': 95, 'calculateIntercept': True, 'useWeights': False}
    typed_record, typed_native, typed_rank = native_fit(
        session, {**common, 'outcome': typed([fixture['outcome']]), 'predictors': typed(fixture['predictors'])},
        titles, evidence / 'typed', label + ' typed')
    sheet_record, sheet_native, sheet_rank = native_fit(
        session, {**common, 'outcome': selection(0, [fixture['outcome']]) if fixture['outcome_in_sheet'] else typed([fixture['outcome']]),
                  'predictors': selection(first, fixture['predictors'])},
        titles, evidence / 'worksheet', label + ' worksheet')
    check(typed_native == sheet_native and typed_rank == sheet_rank
          and (fixture['constructed'] is None or typed_native == [float(b) for b in fixture['constructed']]),
          label + ' typed and selected fits give the same native coefficients'
          + (', c(7, 1:6) as constructed' if fixture['constructed'] else ''), (typed_native, sheet_native))

    entered = inputs(typed_record)['predictors']
    check(entered.get('kind') == 'entered' and [c['title'] for c in entered['columns']] == titles
          and [c['values'] for c in entered['columns']] == values and 'data' not in typed_record,
          label + ' typed predictors are recorded as entered under the titles typed, with their values', entered)
    pointer = inputs(sheet_record)['predictors']
    held = sheet_record.get('data', {})
    read = [(c['title'], c['column'], c['rows'], c['hasTitle']) for c in pointer.get('columns', [])]
    outcome = inputs(sheet_record)['outcome']
    check(pointer.get('kind') == 'frame' and pointer.get('mode') == 'NumericPreserveRows'
          and read == [(title, first + i + 1, [1, n + 1], True) for i, title in enumerate(titles)]
          and list(held.get('predictors', {})) == fixture['stored'] and list(held['predictors'].values()) == values
          and (outcome.get('kind') == 'frame' and held.get('outcome') == {fixture['outcome'][0]: list(fixture['outcome'][1])}
               if fixture['outcome_in_sheet'] else outcome.get('kind') == 'entered' and 'outcome' not in held),
          label + ' selected predictors are recorded as worksheet pointers, their values held under '
          + ', '.join(json.dumps(key) for key in fixture['stored']), (read, held))

    reread = copy.deepcopy(sheet_record)
    reread.pop('data')
    frames = grid_frames(reread, worksheet)
    paths = [('entered', typed_record, [], typed_native, typed_rank),
             ('held', sheet_record, [], sheet_native, sheet_rank),
             ('reread', reread, frames, sheet_native, sheet_rank)]
    for path, record, supplied, native, rank in paths:
        name = f'{label} {path}'
        place = evidence / path
        try:
            place.mkdir(parents=True, exist_ok=True)
            (place / 'frames.json').write_text(json.dumps(supplied, indent=1))
            replay = writer.write(record, supplied)
            (place / 'replay.json').write_text(json.dumps({key: value for key, value in replay.items() if key != 'text'}, indent=1))
            text = replay.get('text', '')
            check(replay.get('hasRecipe') and not replay.get('dataUnavailable') and not replay.get('error')
                  and replay.get('asked') == [frame['name'] for frame in supplied] and not replay.get('relocate')
                  and 'has changed in the workbook' not in text and 'has moved along the sheet' not in text
                  and NOTES[path](text),
                  name + ' predictor data are available for model replay', {key: value for key, value in replay.items() if key != 'text'})
            result = run_r(text + assertions(fixture, native, rank), place)
            shown = {line.split(' ', 1)[0]: line.split(' ', 1)[1].strip() for line in result.stdout.splitlines()
                     if line.startswith(('NAMES ', 'RANK ', 'DIFFERENCE '))}
            check(result.returncode == 0 and OK in result.stdout,
                  name + ' replays every predictor with stable names, order and coefficients'
                  + (f' (names {shown.get("NAMES")}, rank {shown.get("RANK")}, largest difference from the native {shown.get("DIFFERENCE")})'
                     if result.returncode == 0 else ''),
                  (result.stdout[-1500:] + result.stderr[-1500:]).strip())
        except Exception as error:
            failures.append(name)
            print('FAIL:', name, str(error)[:4000], flush=True)


if __name__ == '__main__':
    (ROOT / '.build').mkdir(exist_ok=True)
    folder = Path(tempfile.mkdtemp(prefix='duplicate-predictors-', dir=ROOT / '.build'))
    session, writer = Session(), ScriptWriter()
    failures = []
    try:
        for fixture in FIXTURES:
            try:
                check_fixture(session, writer, fixture, folder, failures)
            except Exception as error:
                failures.append(fixture['label'])
                print('FAIL:', fixture['label'], str(error)[:4000], flush=True)
    finally:
        writer.close()
        session.finish()
    print(f'DUPLICATE PREDICTOR REPLAY: {len(FIXTURES)} fixtures, 3 paths each, {len(failures)} failed', flush=True)
    if failures:
        print('Failed:', ', '.join(failures), flush=True)
        print('Retained test artifacts:', folder, flush=True)
        sys.exit(1)
    shutil.rmtree(folder)
