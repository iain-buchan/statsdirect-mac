"""Weighted multiple linear regression keeps its prior weights when it refits without collinear predictors (Windows 5.3.8).

A port of Windows's tests/RScript/PosthocWeighted537.cs (f24edb13) to the Mac operation host and real R. Before 5.3.8, x_glin
(Builtins/Regress.cs) refitted after glsqr had dropped a collinear predictor with the weight column index of the first fit (iwtcol),
which in the shortened design matrix no longer names the weights: with one predictor dropped it names the outcome. The Windows
fixtures are used as they are: a predictor duplicated at twice its scale, two predictors duplicated, and a full set of group dummies
beside the intercept. (With two dropped, the old index names a leftover copy of the weights from the first fit, so that fixture
passes on 5.3.7 too; it fails a fix that moves the index back by one column only.) Each fixture is a worksheet titled in its first
row (Y in column A, W in B, the predictors from C, the retained before the dropped), selected as the Mac form sends it: the outcome,
the weights and the predictors as worksheet frames read NumericPreserveRows, as the Windows check acquires them, into
MultipleLinearRegression with weights and an intercept at 95% confidence; the follow-ons run from the kept run, as the Windows check
runs them from its bag. Checked as Windows checks: the report warns that each duplicate was dropped from the model; the reduced
model's coefficient labels are the constant and the retained predictors; the refit gives a fit and a residual for every observation;
and lm(Y ~ retained, weights = W), constructed in R from the fixture alone, agrees at all.equal tolerance 1e-9 with the coefficients
and their standard errors, the ANOVA follow-on's reg_sum, reg_df, res_sum, res_df, mse (the root MSE, s$sigma), f, r2, ra2 and
Durbin-Watson statistic, and the fitted values and residuals.

Checked otherwise, because the Mac host returns only a run's finite scalar outputs (the snapshot's values), not its blocks:
- The coefficients and standard errors are read from the parameter detail follow-on's report, printed to 12 decimal places (decp 12,
  the most Analysis Options allow), where Windows reads the full-precision "v" block. That rounding (at most 5e-13 here) is far
  inside the 1e-9 tolerance, which is kept; each printed figure is also checked on its own, within half a unit of its last printed
  place plus 1e-9 of R's figure, and the parent's report must print the same coefficients under the same labels.
- The fitted values and residuals are read from the output frame the residuals follow-on saves when "Fitted Y, SD of fitted Y and
  residual" is ticked (the snapshot's frames, written at full precision), where Windows, which saves nothing, reads the "yfit"
  block; the report's own table of them must list every observation, in the worksheet's order.
- The warnings are read from the parent's report, where Windows reads the "warn" block; the names a warning gives as dropped must be
  exactly the duplicates.
The run record must show the three frames read NumericPreserveRows from their worksheet columns, and the report the weighted fit.
"""
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

from r_runtime import rscript
from test_menu import ROOT, Session
from test_pr6_replay import sheet
from test_shared_engine_update import ReportText


PREFS = {'use-default-ci': True, 'default-ci': '95', 'decp': '12', 'pdecp': '7'}
PLACES = int(PREFS['decp'])
DROPPED = ' dropped from the model'
ANOVA = ['reg_sum', 'reg_df', 'res_sum', 'res_df', 'mse', 'f', 'r2', 'ra2', 'dw']
FITS = ['Y Fit', 'SD Y Fit', 'Residual']

# The fixtures of PosthocWeighted537.cs, value for value.
Y = [8.73, 8.83, 14.58, 9.89, 9.16, 11.35, 5.24, 7.19, 13.24, 7.65, 8.36, 7.69, 12.42, 5.96, 12.51, 10.52, 5.53, 11.18, 14.38]
W = [1, 1, 4, 2, 4, 4, 3, 2, 3, 1, 3, 1, 4, 1, 2, 4, 2, 3, 4]
X1 = [7.55, 5.12, 7.15, 5.93, 3.56, 4.63, 2.06, 2.18, 9.42, 7.08, .55, 2.28, 2.73, .07, 7.53, 5.75, .42, 9.61, 8.74]
X2 = [1, 0, 1, 1, 0, 1, 0, 1, 1, 0, 1, 1, 1, 1, 0, 1, 1, 0, 0]
PREDICTORS = [('X1', X1), ('X2', X2)]
TWICE = ('TwiceX1', [2 * x for x in X1])
THRICE = ('ThreeX2', [3 * x for x in X2])
SBP = [72.9, 68.4, 83, 63.2, 65.5, 71.9, 68.4, 72.2, 80, 69.9, 68, 72.4, 62.5, 76.4, 70, 63.6, 63.7, 79.4, 66.8, 64.8, 79.3, 67.7,
       65, 80.5, 67.5, 76.5, 72.5, 67.7, 65.2, 62.5]
PRIOR = [3, 2, 1, 2, 3, 1, 2, 3, 1, 1, 3, 1, 2, 3, 1, 2, 1, 1, 3, 1, 1, 1, 3, 3, 1, 1, 3, 1, 1, 2]
AGE = [63.6, 25.6, 55, 24.4, 27.8, 44.6, 55.1, 63.9, 60.3, 43, 21.5, 40.7, 30.7, 39.6, 47.5, 27.4, 28.7, 60.6, 30.3, 41.8, 58.5,
       51.5, 28.7, 60.1, 40.2, 48.1, 34.3, 53, 59.3, 26.5]


def dummy(group):
    return [1 if i % 3 == group else 0 for i in range(len(SBP))]


FIXTURES = [
    ('scaled-duplicate', Y, W, PREDICTORS, [TWICE]),
    ('two-duplicates', Y, W, PREDICTORS, [TWICE, THRICE]),
    ('full-dummy-set', SBP, PRIOR, [('Age', AGE), ('GroupA', dummy(0)), ('GroupB', dummy(1))], [('GroupC', dummy(2))]),
]


def check(ok, what, detail=None):
    if not ok:
        raise AssertionError(what if detail is None else f'{what}: {detail}')
    print('PASS:', what, flush=True)


def worksheet(first, columns):
    """Adjacent columns of the fixture's worksheet from column index `first`, titled in its first row, as the form selects them."""
    answer = sheet([title for title, _ in columns], [values for _, values in columns])
    answer['range']['columns'] = list(range(first, first + len(columns)))
    return answer


class Paragraphs(HTMLParser):
    """The text of each paragraph of a native report."""
    def __init__(self, source):
        super().__init__()
        self.items, self.current = [], None
        self.feed(source)

    def handle_starttag(self, tag, attrs):
        if tag == 'p':
            self.current = []

    def handle_data(self, data):
        if self.current is not None:
            self.current.append(data)

    def handle_endtag(self, tag):
        if tag == 'p' and self.current is not None:
            self.items.append(' '.join(''.join(self.current).split()))
            self.current = None


def block(rows, header):
    """The rows of a report table under its header row (`header`, the header's leading cells), up to the next header or table."""
    start = next((i for i, row in enumerate(rows) if row[:len(header)] == header), None)
    assert start is not None, ('no table headed', header, rows)
    found = []
    for row in rows[start + 1:]:
        if not row or not re.fullmatch(r'[-+]?(\d+(\.\d*)?|\.\d+)([Ee][-+]?\d+)?', row[1] if len(row) > 1 else ''):
            break
        found.append(row)
    return found


def frame_columns(result, titles, n):
    """The columns of the one output frame a follow-on saved, by cell coordinates, each of which must hold n numbers."""
    frames = result['frames']
    assert len(frames) == 1, ('output frames', frames)
    frame = frames[0]
    cells = {(cell['col'], cell['row']): cell['text'] for cell in frame['cells']}
    found = [cells.get((col, 0)) for col in range(frame['columns'])]
    assert found == titles and frame['lengths'] == [n] * len(titles), ('output frame', found, frame['lengths'])
    absent = [(col, row) for col in range(len(titles)) for row in range(1, n + 1) if (col, row) not in cells]
    assert not absent, ('output frame cells left out as missing', absent)
    return [[float(cells[(col, row)]) for row in range(1, n + 1)] for col in range(len(titles))]


def vector(values):
    return 'c(' + ', '.join(repr(float(v)) for v in values) + ')'


def run_r(script, folder):
    folder.mkdir(parents=True, exist_ok=True)
    path = folder / 'script.R'
    path.write_text(script)
    result = subprocess.run([rscript(), '--vanilla', '--encoding=UTF-8', str(path)], cwd=folder, text=True, capture_output=True, timeout=60)
    (folder / 'output.txt').write_text(result.stdout + result.stderr)
    return result


def check_fit(session, label, outcome, weights, retained, dropped, folder):
    columns = [('Y', outcome), ('W', weights)] + retained + dropped
    n = len(outcome)
    answers = {'ci': 95, 'calculateIntercept': True, 'useWeights': True,
               'outcome': worksheet(0, columns[:1]), 'weights': worksheet(1, columns[1:2]), 'predictors': worksheet(2, columns[2:])}
    model = session.run('MultipleLinearRegression', answers, PREFS, keep=True)
    try:
        evidence = folder / label
        evidence.mkdir(parents=True, exist_ok=True)
        (evidence / 'model.html').write_text(model['html'])
        # Every prompt answered as given (the 95% level may come from the preferences unasked): a fallback answer would change the
        # model silently. The predictors are asked in the form's dummy-coding mode, which keeps these columns (two values at most) as
        # they are, so the coding question is not asked and they are recorded NumericPreserveRows, as Windows acquires them.
        asked = [entry['name'] for entry in model['history']]
        check(all(name in answers for name in asked) and [name for name in asked if name != 'ci'] == list(answers)[1:],
              label + ' asks only for the confidence level, intercept, weights and the three selections', asked)
        record = json.loads(model['record'])
        inputs = {item['name']: item for item in record['inputs']}
        frames = [inputs.get(name, {}) for name in ('outcome', 'weights', 'predictors')]
        read = [(c['title'], c['column'], c['rows'], f.get('kind'), f.get('mode')) for f in frames for c in f.get('columns', [])]
        settings = [inputs.get(name, {}).get('value') for name in ('ci', 'calculateIntercept', 'useWeights')]
        check(read == [(title, i + 1, [1, n + 1], 'frame', 'NumericPreserveRows') for i, (title, _) in enumerate(columns)]
              and settings == [0.95, True, True] and 'Y (weighted by W) = ' in ReportText(model['html']).text,
              label + ' reads Y, W and the predictors as worksheet frames NumericPreserveRows and fits the weighted model with an intercept at 95%',
              (read, settings))

        warnings = [p[len('WARNING: '):] for p in Paragraphs(model['html']).items if p.startswith('WARNING: ')]
        named = [w.split(DROPPED)[0].split(', ') for w in warnings if DROPPED in w]
        check(all(any(title in w and 'dropped from the model' in w for w in warnings) for title, _ in dropped)
              and named == [[title for title, _ in dropped]],
              label + ' drops the specified collinear predictors', warnings)

        detail = session.run('MultipleLinearRegressionParameterDetail', {}, PREFS, parent=model['id'])
        anova = session.run('MultipleLinearRegressionAnova', {'ci': 95}, PREFS, parent=model['id'])
        residuals = session.run('MultipleLinearRegressionResiduals',
                                {'options': {'saveFittedY': True, 'saveStudentised': False, 'saveJackknife': False}}, PREFS, parent=model['id'])
        for name, result in (('detail', detail), ('anova', anova), ('residuals', residuals)):
            (evidence / (name + '.html')).write_text(result['html'])
            (evidence / (name + '.json')).write_text(json.dumps({'values': result['values'], 'frames': result['frames']}, indent=1))

        coefficients = block(ReportText(detail['html']).rows, ['', 'Coefficient', 'Standard Error'])
        check([row[0] for row in coefficients] == ['constant'] + [title for title, _ in retained],
              label + ' retains the intended reduced model', [row[0] for row in coefficients])
        # The parent's own report is the same reduced model: b0 for the intercept, then b1... for the retained, as printed in the detail.
        parent = [(row[0], re.fullmatch(r'b(\d+) = (\S+)', row[1])) for row in ReportText(model['html']).rows if len(row) > 1 and row[1].startswith('b')]
        check([(title, int(match[1]), match[2]) for title, match in parent if match]
              == [('Intercept' if i == 0 else row[0], i, row[1]) for i, row in enumerate(coefficients)] and len(parent) == len(coefficients),
              label + ' reports the same coefficients under the same labels as its parameter detail', parent)

        fitted, _, residual = frame_columns(residuals, FITS, n)
        listed = block(ReportText(residuals['html']).rows, ['Index', 'Y', 'Fitted Y'])
        check([(int(row[0]), float(row[1])) for row in listed] == [(i + 1, float(v)) for i, v in enumerate(outcome)],
              label + ' reports every residual from the refit', (len(listed), n))

        missing = [key for key in ANOVA if key not in anova['values']]
        check(not missing, label + ' ANOVA follow-on returns every figure the Windows check compares', missing)

        # The reduced model constructed independently from the fixture, with the actual prior weights (the Windows oracle, as written there).
        data = ', '.join(f'{title} = {vector(values)}' for title, values in columns[:len(retained) + 2])
        oracle = ('d <- data.frame(' + data + ')\n'
                  'm <- lm(Y ~ ' + ' + '.join(title for title, _ in retained) + ', data = d, weights = W)\n'
                  's <- summary(m)\na <- anova(m)\ne <- residuals(m)\n'
                  'expect <- function(actual, expected) {\n'
                  '  comparison <- all.equal(as.double(actual), as.double(expected), tolerance = 1e-9)\n'
                  "  if (!isTRUE(comparison)) stop(deparse(substitute(actual)), ': ', comparison)\n"
                  '}\n'
                  # The Mac reads the coefficients and their standard errors as printed: each within half a unit of its last place,
                  # plus the Windows tolerance of R's figure.
                  'printed <- function(actual, expected) {\n'
                  '  name <- deparse(substitute(actual))\n'
                  '  actual <- as.double(actual)\n'
                  f'  far <- abs(actual - expected) > 0.5 * 10^-{PLACES} + 1e-9 * abs(actual)\n'
                  "  if (any(far)) stop(name, ': printed ', toString(expected[far]), ' against ', toString(sprintf('%.17g', actual[far])))\n"
                  '}\n'
                  'margin <- function(actual, expected) { actual <- as.double(actual); mean(abs(actual - expected)) / mean(abs(actual)) }\n')
        figures = {
            'coef(m)': [float(row[1]) for row in coefficients],
            's$coefficients[, 2]': [float(row[2]) for row in coefficients],
            "c(sum(head(a$'Sum Sq', -1)), sum(head(a$Df, -1)), tail(a$'Sum Sq', 1), m$df.residual, s$sigma, s$fstatistic[1], "
            "100 * s$r.squared, 100 * s$adj.r.squared, sum(diff(e)^2) / sum(e^2))": [anova['values'][key] for key in ANOVA],
            'fitted(m)': fitted,
            'e': residual,
        }
        for expression, values in figures.items():
            oracle += f'expect({expression}, {vector(values)})\n'
        for expression in ('coef(m)', 's$coefficients[, 2]'):
            oracle += f'printed({expression}, {vector(figures[expression])})\n'
        oracle += "cat('MARGINS', " + ', '.join(f"sprintf('%.1e', margin({expression}, {vector(values)}))" for expression, values in figures.items()) + ", '\\n')\n"
        oracle += "cat('WEIGHTED_REFIT_OK\\n')\n"
        result = run_r(oracle, evidence)
        margins = next((line.split()[1:] for line in result.stdout.splitlines() if line.startswith('MARGINS')), [])
        check(result.returncode == 0 and 'WEIGHTED_REFIT_OK' in result.stdout,
              label + ' coefficients, SE, ANOVA, Durbin-Watson and residuals agree with independent weighted lm'
              + (' (mean relative differences: coefficients %s, SE %s, ANOVA %s, fitted %s, residuals %s)' % tuple(margins) if len(margins) == 5 else ''),
              (result.stdout + result.stderr).strip())
    finally:
        session.close(model['id'])


if __name__ == '__main__':
    (ROOT / '.build').mkdir(exist_ok=True)
    folder = Path(tempfile.mkdtemp(prefix='weighted-refit-', dir=ROOT / '.build'))
    session = Session()
    failures = []
    try:
        for label, outcome, weights, retained, dropped in FIXTURES:
            try:
                check_fit(session, label, outcome, weights, retained, dropped, folder)
            except Exception as error:
                failures.append(label)
                print('FAIL:', label, str(error)[:4000], flush=True)
    finally:
        session.finish()
    print(f'WEIGHTED REFIT: {len(FIXTURES) - len(failures)} fixtures passed, {len(failures)} failed', flush=True)
    if failures:
        print('Retained test artifacts:', folder, flush=True)
        sys.exit(1)
    shutil.rmtree(folder)
