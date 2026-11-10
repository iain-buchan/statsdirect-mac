"""Regression edge cases of Windows 5.3.9, native and replayed in R.

A port of Windows's tests/RScript/Models539.cs at v5.3.9 (f41aad46) to the Mac operation host and real R. Each Windows fixture is
used value for value: a worksheet titled in its first row, its columns selected as the Mac form sends them and read
NumericPreserveRows, as Models539Select acquires them (a missing value is a blank cell). Each check prints the Windows wording.
As on Windows, a fixture's replay is the script the engine writes for the run's record (statsdirect_r_script, through
Tests/engine-driver), which must have its recipe and its data ("exports the acquired data and settings for replay"), run by
Rscript --vanilla with the Windows assertions after it: it must exit 0 and reach MODELS_539_OK ("replays in R and agrees with the
native figures"). Models539Equal is all.equal at the Windows tolerance, unchanged.

Checked otherwise, because the Mac host returns a run's scalar outputs (the snapshot's values, where an unavailable figure is the
engine's missing value) but not its blocks, and validates each answer as the form does:
- Warnings are the report's paragraphs (multiple regression prints them after "WARNING: "), where Windows reads the "warn" block.
- Coefficients, standard errors and Wald figures are read from the report, printed to 12 decimal places (decp 12, the most
  Analysis Options allow), where Windows reads the block at full precision; the rounding (5e-13) is far inside every tolerance
  used with them, which are kept. A statistic Windows requires to be NaN or missing in a block must be printed as "*".
- A P that Windows reads from a block is known here to the 7 places the report prints; R's figure must round to it.
- The Poisson and logistic precision answer ".00000000001" also fits the 12-character limit of the 5.3.9 definition.
  The engine reads 1e-11 (the model follow-on's acc), which is asserted.
- Confidence comes from the default interval of Analysis Options (95%), as the Mac form supplies it; the Windows answers are .95.
  The Cox hazard ratios of item 12 are the exception: there the interval is asked for and answered 90, Windows's gamma .9.
- A refusal is the failed run's message.
- An unanswered question fails the check. Since 5.3.10, an extra predictor level found only in a row with a missing time or event
  does not introduce a coding prompt for an otherwise binary Cox predictor.
- The Cox plots (item 8): Windows reads the chart options the follow-on returns (the split, the series, the labels), which the
  Mac host does not return. Here the split is read from the charts the report draws: split by a predictor it draws three (the
  individual survival, its confidence band and the log-log plot), each with one series labelled <title>=0 and one <title>=1,
  and no stratum label; unsplit it draws the baseline pair. Two predictors titled Z give the same labels whichever is chosen,
  so the second is told from the first by the drawing: it must be the drawing of the same fit split by its second predictor
  when the first is titled Q instead, and not that of the split by the first.
- LOESS (item 9) is fitted by R through the Mac host, as in test_r_operations.py: its run folders are a temporary
  STATSDIRECT_R_FOLDER. The default formula is the default of the model question, and the script the program wrote is the
  run's formattedRScript.
- The times and events of item 12 are drawn from .NET's Random(539) by a C# user script in the engine, as the Windows check
  draws them. Its reread path supplies the worksheet's cells for a record too large to hold its values, as the Mac host does
  when the record is opened again (test_duplicate_predictor_replay.py).

MODELS_539_COLLECT=1 reports every failing check and goes on (to see which checks an older engine fails); without it a group
stops at its first failure, the other groups still run, and the exit status is 1 if anything failed.
"""
from html.parser import HTMLParser
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

from r_runtime import rscript
from test_menu import ROOT, Session
from test_pr6_replay import RWriter, managed, sheet
from test_shared_engine_update import ReportText


PREFS = {'use-default-ci': True, 'default-ci': '95', 'decp': '12', 'pdecp': '7'}
MISSING = -sys.float_info.max          # Constant.MISSING (double.MinValue)
PRECISION = '.00000000001'             # 1e-11, also accepted by the 5.3.9 form
COLLECT = os.environ.get('MODELS_539_COLLECT', '') not in ('', '0')
PASSED, FAILED = [], []

Y = [8.73, 8.83, 14.58, 9.89, 9.16, 11.35, 5.24, 7.19, 13.24, 7.65]
X1 = [7.55, 5.12, 7.15, 5.93, 3.56, 4.63, 2.06, 2.18, 9.42, 7.08]
X2 = [1, 0, 1, 1, 0, 1, 0, 1, 1, 0]
COUNTS = [2, 5, 9, 14, 20, 11, 6, 4, 8, 7, 12, 16]
EXPOSURES = [100, 120, 140, 160, 180, 150, 110, 90, 130, 120, 150, 170]
DOSE = [1.5 + i for i in range(12)]


def check(ok, what, detail=None):
    if ok:
        PASSED.append(what)
        print('PASS:', what, flush=True)
        return True
    message = what if detail is None else f'{what}: {detail}'
    if not COLLECT:
        raise AssertionError(message)
    FAILED.append(what)
    print('FAIL:', ' '.join(message[:3000].split()), flush=True)
    return False


class Refused(AssertionError):
    """A run that ended without a report; the message is the host's."""


class ScriptWriter(RWriter):
    """The R script entry as the Mac host calls it ({record, title, frames}); its answer is returned as it is, for the check to judge."""
    def write(self, record, frames=()):
        self.process.stdin.write(json.dumps({'record': record, 'title': None, 'frames': list(frames)}) + '\n')
        self.process.stdin.flush()
        return json.loads(self.process.stdout.readline())


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


def ask(session, operation, answers, parent=None, keep=False, prefs=PREFS):
    """Run an operation with exactly these answers; a question they do not answer, or an answer the form refuses, fails.
    An answer that is a function is given the question, as a Windows answer that is one is (the default offered)."""
    ident, state = session.start(operation, prefs, parent)
    for _ in range(60):
        if state.get('state') != 'input':
            break
        prompt = state['prompt']
        name = prompt.get('name') or prompt.get('prompt')   # a question of the host's own has no name: its wording
        if prompt.get('error') or name not in answers:
            session.close(ident)
            raise AssertionError(f'{operation}: {name!r} ' + (f'refused its answer: {prompt["error"]}' if prompt.get('error') else 'is asked but not answered'))
        value = answers[name](prompt) if callable(answers[name]) else answers[name]
        session.request(action='answer', id=ident, token=state['token'], value=value)
        state = session.wait(ident)
    if state.get('state') != 'complete':
        session.close(ident)
        raise Refused(str(state.get('error')))
    if not keep:
        session.close(ident)
    return state


def select(columns, *indexes):
    """Columns of the fixture's worksheet by index, titled in its first row, as the form selects them (Models539Select)."""
    frame = sheet([columns[i][0] for i in indexes], [['' if v is None else v for v in columns[i][1]] for i in indexes])
    frame['range']['columns'] = list(indexes)
    return frame


def warnings(state):
    return [p[len('WARNING: '):] if p.startswith('WARNING: ') else p for p in Paragraphs(state['html']).items]


def vector(values):
    return 'c(' + ', '.join(repr(float(v)) for v in values) + ')'


def equal(expression, expected, tolerance='1e-8'):
    """Models539Equal."""
    return f'stopifnot(isTRUE(all.equal(unname(c({expression})),{vector(expected)},tolerance={tolerance},check.attributes=FALSE)))\n'


def printed(value):
    """Models539R: a figure as the replay prints it, to 6 places with trailing zeros dropped."""
    text = format(round(float(value), 6), '.6f').rstrip('0').rstrip('.')
    return '0' if text in ('-0', '') else text


def invariant(value):
    return str(int(value)) if float(value).is_integer() else repr(float(value))


def verify(writer, folder, label, record, assertions):
    """Models539Verify: R's run of the replay of the recorded run, with the given checks after it; its output."""
    script = writer.write(record)
    check(bool(script.get('hasRecipe')) and not script.get('dataUnavailable'), label + ' exports the acquired data and settings for replay',
          {key: script.get(key) for key in ('hasRecipe', 'dataUnavailable', 'error')})
    result = run_r(folder / label, (script.get('text') or '') + '\n' + assertions + "\ncat('MODELS_539_OK\\n')\n")
    check(result.returncode == 0 and 'MODELS_539_OK' in result.stdout, label + ' replays in R and agrees with the native figures',
          (result.returncode, result.stderr[-1500:]))
    return result.stdout


def run_r(target, text):
    """RunR: the script run by Rscript in a folder of its own, where the script and its output are kept."""
    target.mkdir()
    (target / 'script.R').write_text(text, encoding='utf-8')
    result = subprocess.run([rscript(), '--vanilla', '--encoding=UTF-8', str(target / 'script.R')], cwd=target, capture_output=True,
                            encoding='utf-8', errors='replace', timeout=120)
    (target / 'output.txt').write_text(result.stdout + '\n--- stderr ---\n' + result.stderr, encoding='utf-8')
    return result


def linear(session, columns, outcome, weights, predictors, intercept, keep=True):
    """Models539Linear."""
    answers = {'ci': 95, 'calculateIntercept': intercept, 'useWeights': weights >= 0,
               'outcome': select(columns, outcome), 'predictors': select(columns, *predictors)}
    if weights >= 0:
        answers['weights'] = select(columns, weights)
    return ask(session, 'MultipleLinearRegression', answers, keep=keep)


def anova(session, model):
    return ask(session, 'MultipleLinearRegressionAnova', {'ci': 95}, parent=model['id'])['values']


def coefficients(model):
    """The coefficient rows of the multiple regression report: (cells, b)."""
    rows = []
    for cells in ReportText(model['html']).rows:
        match = len(cells) > 1 and re.fullmatch(r'b(\d+) = (\S+)', cells[1])
        if match:
            assert int(match.group(1)) == len(rows) or int(match.group(1)) == len(rows) + 1, cells
            rows.append((cells, float(match.group(2))))
    return rows


def fewer_rows(session, writer, folder):
    """Item 1: rows left out for missing values or zero weights must not leave fewer rows than parameters; both routes are refused."""
    two, one = [1, 1] + [0] * 8, [1] + [0] * 9
    gappy = [Y[0]] + [None] * 8 + [Y[9]]
    columns = [('Y', Y), ('Two', two), ('One', one), ('X1', X1), ('X2', X2), ('Gappy', gappy)]
    for label, outcome, weights, predictors in [('zero weights', 0, 1, [3, 4]), ('missing outcomes', 5, -1, [3, 4]), ('one positive weight', 0, 2, [3])]:
        try:
            linear(session, columns, outcome, weights, predictors, True, keep=False)
            check(False, 'multiple regression with ' + label + ' must refuse fewer usable rows than parameters')
        except Refused as refusal:
            check('fewer complete observations with positive prior weight than parameters' in str(refusal),
                  'multiple regression with ' + label + ' refuses fewer usable rows than parameters', str(refusal))

    # Not refused: predictors that the others account for leave fewer parameters than rows.
    w5 = [1, 2, 0, 1, 0, 3, 0, 1, 0, 0]
    gappy5 = [v if w > 0 else None for v, w in zip(Y, w5)]
    aliased = [('Y', Y), ('W', w5), ('A', X1), ('B', X2), ('A2', [2 * v for v in X1]), ('B3', [3 * v for v in X2]), ('Acopy', list(X1)), ('Gappy', gappy5)]
    used = [i for i in range(10) if w5[i] > 0]
    for label, outcome, weighted in [('zero-weights', 0, True), ('missing-outcomes', 7, False)]:
        model = linear(session, aliased, outcome, 1 if weighted else -1, [2, 3, 4, 5, 6], True)
        try:
            check(any(w.startswith('A2, B3, Acopy dropped from the model') for w in warnings(model)),
                  'aliased predictors with ' + label + ': fewer rows than parameters, but the three aliased predictors are dropped and the model refitted', warnings(model))
            rows = coefficients(model)
            table = anova(session, model)
            data = ('Y <- ' + vector(Y[i] for i in used) + '\nA <- ' + vector(X1[i] for i in used) + '\nB <- ' + vector(X2[i] for i in used) +
                    '\nA2 <- 2 * A\nB3 <- 3 * B\nAcopy <- A\nW <- ' + vector((w5[i] if weighted else 1.0) for i in used) + '\n')
            oracle = (data + 'm <- lm(Y ~ A + B + A2 + B3 + Acopy, weights = W)\nms <- summary(m)\nstopifnot(m$rank == 3L, m$df.residual == 2L)\n' +
                      equal('coef(m)[1:3]', [b for _, b in rows], '1e-9') +
                      equal('m$df.residual, ms$sigma, 100 * ms$r.squared, 100 * ms$adj.r.squared', [table[key] for key in ('res_df', 'mse', 'r2', 'ra2')], '1e-9') +
                      'stopifnot(fit$rank == 3L)\n')
            check(len(rows) == 3 and table['res_df'] == 2, 'aliased predictors with ' + label + ': three parameters on five rows, with 2 residual df', (rows, table))
            verify(writer, folder, 'aliased-fewer-rows-' + label, model['record'], oracle)
        finally:
            session.close(model['id'])


def lone_predictor(session, writer, folder):
    """Item 2: a lone aliased predictor is dropped and refitted; residual df, root MSE and adjusted R squared are lm's without it."""
    weights = [1, 2, 1, 3, 2, 1, 2, 3, 1, 2]
    columns = [('Y', Y), ('W', weights), ('C', [3.0] * 10), ('Z', [0.0] * 10)]
    for label, weighted, predictor, intercept in [('constant', False, 2, True), ('weighted-constant', True, 2, True), ('zeros-no-intercept', False, 3, False)]:
        model = linear(session, columns, 0, 1 if weighted else -1, [predictor], intercept)
        try:
            title = 'C' if predictor == 2 else 'Z'
            check(any(w.startswith(title + ' dropped from the model') for w in warnings(model)), label + ': the aliased predictor is dropped with a warning', warnings(model))
            rows = coefficients(model)
            check(len(rows) == (1 if intercept else 0), label + ': the refit has the intercept alone, or nothing without one', rows)
            table = anova(session, model)
            check(table['reg_df'] == 0 and table['f'] == MISSING and table['p'] == MISSING and table['reg_mean'] == MISSING,
                  label + ': no regression df, so no regression mean square, F or P', table)
            data = 'Y <- ' + vector(Y) + '\nW <- ' + vector(weights if weighted else [1.0] * 10) + '\n'
            oracle = (data + 'm <- lm(Y ~ ' + ('1' if intercept else '0') + ', weights = W)\nms <- summary(m)\n' +
                      equal('m$df.residual, ms$sigma, 100 * ms$r.squared, 100 * ms$adj.r.squared, sum(W * residuals(m)^2), m$df.residual',
                            [table[key] for key in ('res_df', 'mse', 'r2', 'ra2', 'res_sum', 'tot_df')], '1e-10') +
                      (equal('coef(m)', [rows[0][1]], '1e-12') if intercept and rows else ''))
            output = verify(writer, folder, 'lone-' + label, model['record'], oracle)
            check(re.search(r'^Residual ' + re.escape(printed(table['res_sum'])) + ' ' + re.escape(invariant(table['res_df'])) + ' ', output, re.M) is not None and
                  re.search(r'^Root MSE = ' + re.escape(printed(table['mse'])) + r'\s*$', output, re.M) is not None,
                  label + ': the replay prints the native residual line and root MSE', output[-1500:])
        finally:
            session.close(model['id'])


def no_predictor_left(session, writer, folder):
    """Item 3: with every predictor dropped beside the intercept the ANOVA has no regression df; its follow-ons run."""
    for rows in (10, 3):
        y = Y[:rows]
        columns = [('Y', y), ('C1', [3.0] * rows), ('C2', [5.0] * rows)]
        model = linear(session, columns, 0, -1, [1, 2], True)
        try:
            check(any(w.startswith('C1, C2 dropped from the model') for w in warnings(model)), f'{rows} rows: both constants are dropped beside the intercept', warnings(model))
            table = anova(session, model)
            check(table['reg_df'] == 0 and table['res_df'] == rows - 1 and table['f'] == MISSING and table['r2'] == 0,
                  f'{rows} rows: the ANOVA of the intercept alone has no regression df and no F', table)
            oracle = ('Y <- ' + vector(y) + '\nm <- lm(Y ~ 1)\nms <- summary(m)\n' +
                      equal('ms$sigma, 100 * ms$adj.r.squared, deviance(m), sum((Y - mean(Y))^2)', [table[key] for key in ('mse', 'ra2', 'res_sum', 'tot_sum')], '1e-10'))
            verify(writer, folder, f'no-predictor-left-{rows}', model['record'], oracle)
            if rows != 10:
                continue
            # The Mac form's answers for the Windows ones: no value to enter for prediction (no predictor is left), nothing saved.
            for name, answers in [('MultipleLinearRegressionParameterDetail', {}), ('MultipleLinearRegressionPrediction', {'candidatePredictors': {}}),
                                  ('MultipleLinearRegressionResiduals', {'options': {'saveFittedY': False, 'saveStudentised': False, 'saveJackknife': False}}),
                                  ('PlotMultipleLinearRegressionResiduals', {}), ('Xxi', {'outputToGrid': False})]:
                try:
                    ask(session, name, answers, parent=model['id'])
                    check(True, "the intercept-only model's " + name + ' follow-on runs')
                except AssertionError as error:
                    check(False, "the intercept-only model's " + name + ' follow-on runs', error)
            try:
                ask(session, 'MultipleLinearRegressionBestSubset', {'selectedPredictors': [], 'selector': 'minimumMallows'}, parent=model['id'])
                check(False, 'best subset selection must refuse a model with no predictors left')
            except Refused as refusal:
                check('No subset of the predictors can be chosen' in str(refusal), 'best subset selection says a model with no predictors left has no subset to choose', str(refusal))
        finally:
            session.close(model['id'])


def zero_residual_df(session, writer, folder):
    """Items 14 and 10: as many usable rows as parameters is an exact fit; what needs residual df is unavailable, natively and in R."""
    y, x1, x2 = Y[:7], X1[:7], X2[:7]
    weights = [1, 2, 1, 0, 0, 0, 0]
    gappy = [None if i in (1, 3, 4, 5) else v for i, v in enumerate(y)]
    columns = [('Y', y), ('W', weights), ('X1', x1), ('X2', x2), ('Gappy', gappy)]
    for label, outcome, weighted, used in [('zero-weights', 0, True, [0, 1, 2]), ('missing-values', 4, False, [0, 2, 6])]:
        model = linear(session, columns, outcome, 1 if weighted else -1, [2, 3], True)
        try:
            check(any(w.startswith('saturated model') for w in warnings(model)) and not any('SVD' in w for w in warnings(model)),
                  label + ': the exact fit is kept, with a warning that it is saturated', warnings(model))
            rows = coefficients(model)
            # NaN is not a figure the host returns: the report prints * for each (t, P, and the partial correlation of each predictor).
            check(len(rows) == 3 and all('t = *' in cells and 'P = *' in cells for cells, _ in rows) and all('r = *' in cells for cells, _ in rows[1:]),
                  label + ': no t, P or partial correlation without residual df', [cells for cells, _ in rows])
            table = anova(session, model)
            check(all(table[key] == MISSING for key in ('res_mean', 'mse', 'f', 'p', 'ra2', 'dw')) and table['res_df'] == 0,
                  label + ': no residual mean square, root MSE, F, P, adjusted R squared or Durbin-Watson without residual df', table)
            check(abs(table['res_sum']) <= 1e-9 * table['tot_sum'] and abs(table['r2'] - 100) <= 1e-7,
                  label + ': the exact fit has no residual sum of squares and R squared of 100%', table)
            data = ('Y <- ' + vector(y[i] for i in used) + '\nX1 <- ' + vector(x1[i] for i in used) + '\nX2 <- ' + vector(x2[i] for i in used) +
                    '\nW <- ' + vector((weights[i] if weighted else 1.0) for i in used) + '\n')
            oracle = (data + 'm <- lm(Y ~ X1 + X2, weights = W)\n' + equal('coef(m)', [b for _, b in rows], '1e-9') +
                      equal('sum((W * (fitted(m) - weighted.mean(Y, W)))^2 / W), m$df.residual', [table['reg_sum'], 0], '1e-9'))
            output = verify(writer, folder, 'zero-df-' + label, model['record'], oracle)
            check(len(re.findall(r't = \*  P = \*', output)) == 3 and 'Root MSE = *' in output and re.search(r'F = \* +P = \*', output) is not None and 'Ra2 = *%' in output,
                  label + ': the replay prints * for each statistic that needs residual df', output[-1500:])
        finally:
            session.close(model['id'])


SCALED = ['Parameter', 'Scaled Standard Error', 'Scaled Wald z', '']
UNSCALED = ['Parameter', 'Coefficient', 'Standard Error']
PARAMETERS = ['Parameter', 'Coefficient', 'Standard Error', 'Z Value', 'P(>|Z|)']
ODDS = ['Parameter', 'Odds Ratio', '95% Conf. Int.', 'Z Value', 'P (>|Z|)']


def close(a, b, relative):
    """Close of the Windows checks (Script.cs)."""
    return abs(a - b) <= relative * max(abs(a), abs(b)) + 1e-12


def table(state, header):
    """The rows of the report's table under this header row (a block of the Windows bag), as the report prints them."""
    rows, found = [], False
    for cells in ReportText(state['html']).rows:
        if cells == header:
            rows, found = [], True
        elif found and (len(cells) != len(header) or cells[0] == 'Parameter'):
            break
        elif found:
            rows.append(cells)
    assert found, (header, ReportText(state['html']).rows[:30])
    return rows


def printed_p(cell):
    """A P the report prints to 7 places: its relation and figure, or None for anything else (such as "P = *")."""
    match = re.fullmatch(r'P ([=<>]) (\d*\.?\d+)', cell)
    return (match.group(1), float(match.group(2))) if match and 0 <= float(match.group(2)) <= 1 else None


def p_agrees(expression, cells):
    """R's P for each native P the report prints: it must round to the printed figure (see the module note)."""
    lines = f'p539 <- unname(c({expression}))\nstopifnot(length(p539) == {len(cells)}L)\n'
    for index, cell in enumerate(cells, 1):
        if cell is None:
            lines += "stop('the native report prints no P here')\n"
        elif cell[0] == '=':
            lines += f'stopifnot(abs(p539[{index}] - {cell[1]!r}) <= 5.0001e-8)\n'
        else:
            lines += f'stopifnot(p539[{index}] {cell[0]} {cell[1]!r})\n'
    return lines


def poisson_answers(columns, predictors, intercept, exposed, weighted):
    """Models539PoissonAnswers, as the Mac form asks them."""
    answers = {'response': select(columns, 0), 'predictors': select(columns, *predictors), 'grouping': 'individual', 'accuracy': PRECISION,
               'intercept': intercept, 'weights': weighted, 'has-exposure': 'true' if exposed else 'false'}
    if weighted:
        answers['weight'] = select(columns, 1)
    if exposed:
        answers['exposure'] = select(columns, 2)
    return answers


def logistic_answers(columns, predictors, intercept=True, grouped=True):
    """Models539LogisticAnswers, as the Mac form asks them."""
    answers = {'response': select(columns, 0), 'predictors': select(columns, *predictors), 'grouping': 'grouped' if grouped else 'individual',
               'accuracy': PRECISION, 'intercept': intercept, 'weights': True}
    if grouped:
        answers['total'], answers['weight'] = select(columns, 1), select(columns, 2)
    else:
        answers['weight'] = select(columns, 1)
    return answers


def fit(session, operation, answers):
    """The regression and its model follow-on (PoissonRegressionModel, LogisticRegressionModel), run from the kept run."""
    parent = ask(session, operation, answers, keep=True)
    try:
        model = ask(session, operation + 'Model', {}, parent=parent['id'])
    finally:
        session.close(parent['id'])
    assert model['values'].get('acc') == 1e-11, ('the precision answered is not 1e-11', model['values'].get('acc'))
    return parent, model


def scaled_wald(session, writer, folder):
    """Item 4: a scaled Wald z that cannot be had (no scale at zero residual df, or a standard error of 0) has no P."""
    saturated = [('Outcome', [2, 5, 8, 13, 7, 11]), ('Prior', [1, 1, 1, 1, 0, 0]), ('Exposure', [1] * 6),
                 ('X1', [0, 1, 0, 0, 1, 1]), ('X2', [0, 0, 1, 0, 1, 1]), ('X3', [0, 0, 0, 1, 1, 1])]
    parent, model = fit(session, 'PoissonRegression', poisson_answers(saturated, [3, 4, 5], True, False, True))
    scaled = table(model, SCALED)
    check(model['values']['idf'] == 0 and model['values']['sp'] == MISSING and len(scaled) == 4 and all(row[2] == '*' and row[3] == 'P = *' for row in scaled),
          'saturated Poisson: no scale, so no scaled Wald z or P', (model['values'], scaled))
    rendered = verify(writer, folder, 'scaled-wald-saturated', parent['record'], 'stopifnot(fit$df.residual == 0L, is.na(scale))\n')
    check(len(re.findall(r'^(?:Intercept|X\d)(?: +[-+0-9.eE*]+){4} +P = \*\s*$', rendered, re.M)) == 4,
          "saturated Poisson: the replay's scaled Wald P is * for each parameter", rendered[-1500:])

    aliased = [('Outcome', COUNTS), ('Prior', [1] * 12), ('Exposure', EXPOSURES), ('Dose', DOSE), ('Zero', [0] * 12)]
    parent, model = fit(session, 'PoissonRegression', poisson_answers(aliased, [3, 4], True, True, False))
    scaled = table(model, SCALED)
    ps = [printed_p(row[3]) for row in scaled[:2]]
    check(model['values']['idf'] == 10 and len(scaled) == 3 and scaled[2][2] == '*' and scaled[2][3] == 'P = *' and all(p is not None for p in ps),
          'Poisson with a column of zeros: its scaled Wald z and P are unavailable, not the P of the predictor before', (model['values'], scaled))
    verify(writer, folder, 'scaled-wald-aliased', parent['record'],
           p_agrees('2 * pnorm(-abs(s[1:2, 1] / (s[1:2, 2] * sqrt(scale))))', ps) + 'stopifnot(is.na(coef(fit)[3]))\n')


def schwarz(session, writer, folder):
    """Item 5: the logistic Schwarz criterion counts the covariate patterns that have a positive prior weight."""
    total = [41, 14, 17, 54, 15, 46, 25, 45, 43, 30, 57, 9, 38]
    responders = [7, 6, 13, 30, 7, 28, 23, 28, 23, 16, 32, 1, 11]
    weight = [3, 2, 4, 2, 0, 1, 2, 0, 2, 4, 0, 4, 3]
    dose = [0.7, 1.5, 6, 4.6, 1.3, 4.4, 2.6, 0.9, 3.9, 3.9, 4.1, 2.1, 2.3]
    male = [0, 0, 1, 0, 1, 1, 1, 1, 0, 1, 1, 0, 0]
    age = [51.5, 41.5, 52.5, 21.5, 44.5, 35.5, 58.5, 58.5, 28.5, 30.5, 54.5, 23.5, 46.5]
    kept = [i for i in range(13) if weight[i] > 0]

    def keep(values):
        return [values[i] for i in kept]

    with_zeros = [('Responders', responders), ('Total', total), ('Prior weight', weight), ('Dose', dose), ('Male', male), ('Age', age)]
    deleted = [(title, keep(values)) for title, values in with_zeros]
    parent, zero = fit(session, 'LogisticRegression', logistic_answers(with_zeros, [3, 4, 5]))
    _, removed = fit(session, 'LogisticRegression', logistic_answers(deleted, [3, 4, 5]))
    zero, removed = zero['values'], removed['values']
    check(close(zero['sch'], removed['sch'], 1e-12) and close(zero['aka'], removed['aka'], 1e-12),
          'logistic zero prior weights: the Schwarz criterion is that of the run without those rows', (zero['sch'], removed['sch'], zero['aka'], removed['aka']))
    oracle = ('r <- ' + vector(keep(responders)) + '\nn <- ' + vector(keep(total)) + '\nw <- ' + vector(keep(weight)) +
              '\nd <- ' + vector(keep(dose)) + '\nm <- ' + vector(keep(male)) + '\na <- ' + vector(keep(age)) + '\n' +
              'g <- glm(cbind(r, n - r) ~ d + m + a, family = binomial, weights = w, control = glm.control(epsilon = 1e-12, maxit = 100))\n' +
              equal('deviance(g) + length(coef(g)) * log(nobs(g))', [zero['sch']], '1e-8'))
    rendered = verify(writer, folder, 'schwarz-zero-weights', parent['record'], oracle)
    check('Schwarz information criterion = ' + printed(zero['sch']) in rendered, 'logistic zero prior weights: the replay prints the native Schwarz criterion',
          (printed(zero['sch']), rendered[-1500:]))


def hosmer_lemeshow_cuts(session, writer, folder):
    """Item 6: Hosmer-Lemeshow cuts are decided within 1e-9 of the total: ten groups and 8 df in any row order."""
    first = ([0, 1, 0, 1, 0, 0, 1, 1, 1, 1, 0, 1, 1, 1, 1, 0, 0, 0, 1, 0, 0, 0, 0, 1, 1, 0, 1, 0, 1, 1, 0, 1, 0, 1, 1, 0, 0, 0, 1, 0],
             [2.5, 4.5, 1.5, 7.5, 4.5, 5.5, 6.5, 9.5, 7.5, 8.5, 4.5, 8.5, 5.5, 7.5, 9.5, 1.5, 2.5, 6.5, 2.5, 6.5, 2.5, 8.5, 1.5, 6.5, 5.5, 1.5, 7.5, 3.5, 10.5,
              10.5, 8.5, 3.5, 3.5, 9.5, 10.5, 3.5, 5.5, 4.5, 10.5, 9.5],
             [0.2, 0.4, 0.3, 0.2, 0.2, 0.3, 0.1, 0.1, 0.3, 0.3, 0.1, 0.2, 0.4, 0.1, 0.3, 0.1, 0.3, 0.2, 0.4, 0.4, 0.1, 0.4, 0.4, 0.3, 0.1, 0.2, 0.4, 0.1, 0.2,
              0.4, 0.1, 0.3, 0.2, 0.4, 0.3, 0.4, 0.2, 0.3, 0.1, 0.2])
    second = ([1, 1, 1, 0, 1, 1, 1, 0, 1, 0, 0, 0, 0, 1, 0, 0, 1, 0, 1, 0, 1, 0, 1, 0, 0, 0, 0, 1, 1, 0, 0, 1, 1, 1, 1, 1, 0, 0, 1, 0],
              [6.5, 9.5, 7.5, 6.5, 10.5, 10.5, 5.5, 1.5, 2.5, 4.5, 4.5, 9.5, 3.5, 9.5, 1.5, 1.5, 9.5, 3.5, 8.5, 1.5, 6.5, 5.5, 4.5, 2.5, 8.5, 6.5, 3.5, 7.5, 7.5,
               8.5, 2.5, 10.5, 3.5, 8.5, 7.5, 10.5, 4.5, 2.5, 5.5, 5.5],
              [0.1, 0.4, 0.1, 0.4, 0.3, 0.2, 0.4, 0.3, 0.4, 0.2, 0.1, 0.2, 0.2, 0.1, 0.4, 0.2, 0.3, 0.1, 0.3, 0.1, 0.3, 0.2, 0.4, 0.3, 0.4, 0.2, 0.4, 0.3, 0.2,
               0.1, 0.2, 0.1, 0.3, 0.2, 0.4, 0.4, 0.3, 0.1, 0.1, 0.3])
    check(all(len(column) == 40 for column in first + second) and sorted(zip(*first)) == sorted(zip(*second)), 'the two Hosmer-Lemeshow fixtures hold the same forty records')
    first_hl = None
    for label, (response, dose, weight) in [('first', first), ('second', second)]:
        columns = [('Outcome', response), ('Prior weight', weight), ('Dose', dose)]
        parent, model = fit(session, 'LogisticRegression', logistic_answers(columns, [2], grouped=False))
        hl = model['values']['hl']
        check(model['values']['df_hl'] == 8 and (first_hl is None or close(hl, first_hl, 1e-9)),
              'Hosmer-Lemeshow in the ' + label + ' row order has ten groups and 8 df, whatever the order of the rows', (model['values']['df_hl'], hl, first_hl))
        if first_hl is None:
            first_hl = hl
        # Each dose totals exactly 1 of the 10: the documented rule puts each in a group of its own.
        oracle = ("oracle <- rowsum(cbind(observed = responders * weight, expected = fitted(fit) * total * weight, total = total * weight), predictors[[1]])\n" +
                  "stopifnot(isTRUE(all.equal(unname(oracle[, 'total']), rep(1, 10))))\n" +
                  "oracle_hl <- sum((oracle[, 'observed'] - oracle[, 'expected'])^2 / (oracle[, 'expected'] * (1 - oracle[, 'expected'] / oracle[, 'total'])))\n" +
                  equal('oracle_hl, hl, hldf', [hl, hl, 8], '1e-9'))
        rendered = verify(writer, folder, 'hl-cuts-' + label, parent['record'], oracle)
        check('Hosmer-Lemeshow test = ' + printed(hl) + '  df = 8 ' in rendered, 'the ' + label + " order's replay prints the native Hosmer-Lemeshow test",
              (printed(hl), rendered[-1500:]))


def constant_predictor(session, writer, folder):
    """Item 7: with an intercept, a nonzero constant predictor is aliased: rank 1 and n - 1 residual df, the fit of the intercept alone."""
    for c in (0.7, 1.3, 2, 3):
        for exposed in (False, True):
            columns = [('Outcome', COUNTS), ('Prior', [1] * 12), ('Exposure', EXPOSURES), ('Constant', [c] * 12)]
            label = 'poisson-constant-' + invariant(c) + ('-exposed' if exposed else '')
            parent, model = fit(session, 'PoissonRegression', poisson_answers(columns, [3], True, exposed, False))
            values, unscaled = model['values'], table(model, UNSCALED)
            intercept = math.log(sum(COUNTS) / (sum(EXPOSURES) if exposed else 12.0))
            # The constant's coefficient and standard error are 0 as the report prints them, to 12 places.
            check(values['rank'] == 1 and values['idf'] == 11 and len(unscaled) == 2 and close(float(unscaled[0][1]), intercept, 1e-9) and
                  unscaled[1][1] == '0' and unscaled[1][2] == '0',
                  label + ': rank 1, 11 residual df and the intercept log(sum y / sum t), with no coefficient for the constant', (values, unscaled, intercept))
            oracle = ('y <- ' + vector(COUNTS) + '\nt <- ' + vector(EXPOSURES if exposed else [1.0] * 12) + '\n' +
                      'g <- glm(y ~ 1, offset = log(t), family = poisson, control = glm.control(epsilon = 1e-14, maxit = 100))\n' +
                      equal('deviance(g), g$df.residual, coef(g), sqrt(vcov(g)[1, 1])', [values['dev'], values['idf'], float(unscaled[0][1]), float(unscaled[0][2])], '1e-8') +
                      equal('fit$rank, fit$df.residual, coef(fit)[1]', [1, 11, float(unscaled[0][1])], '1e-8') + 'stopifnot(is.na(coef(fit)[2]))\n')
            verify(writer, folder, label, parent['record'], oracle)
    response, weights = [2, 3, 4, 5, 6, 8, 10, 11, 12, 14, 15, 17], [1, 2, 3, 1, 2, 3, 1, 2, 3, 1, 2, 3]
    for c in (0.7, 2):
        columns = [('Outcome', response), ('Total', [20] * 12), ('Prior', weights), ('Constant', [c] * 12)]
        label = 'logistic-constant-' + invariant(c)
        parent, model = fit(session, 'LogisticRegression', logistic_answers(columns, [3]))
        values, parameters = model['values'], table(model, PARAMETERS)
        check(values['rank'] == 1 and values['idf'] == 2 and len(parameters) == 2 and parameters[1][1] == '0',
              label + ': the three weight patterns give rank 1 and 2 residual df, with no coefficient for the constant', (values, parameters))
        # the records stacked into their three patterns of prior weight, as the native analysis stacks them
        r = [sum(v for v, w in zip(response, weights) if w == pattern) for pattern in (1, 2, 3)]
        oracle = ('r <- ' + vector(r) + '\nn <- ' + vector([80.0] * 3) + '\nw <- c(1, 2, 3)\n' +
                  'g <- glm(cbind(r, n - r) ~ 1, family = binomial, weights = w, control = glm.control(epsilon = 1e-14, maxit = 100))\n' +
                  equal('deviance(g), g$df.residual, coef(g)', [values['dev'], values['idf'], float(parameters[0][1])], '1e-8') +
                  'stopifnot(fit$rank == 1L, is.na(coef(fit)[2]))\n')
        verify(writer, folder, label, parent['record'], oracle)


def no_intercept_lr_df(session, writer, folder):
    """Item 11: without an intercept the likelihood ratio df is the report's, counted from the intercept-only model."""
    response, weights = [2, 3, 4, 5, 6, 8, 10, 11, 12, 14, 15, 17], [1, 2] * 6
    square = [v * v / 10 for v in DOSE]
    logistic = [('Outcome', response), ('Total', [20] * 12), ('Prior', weights), ('Dose', DOSE), ('Square', square)]
    parent, model = fit(session, 'LogisticRegression', logistic_answers(logistic, [3, 4], intercept=False))
    check(parent['values'].get('df_lr') == 1 and model['values']['x2df'] == 1 and model['values']['rank'] == 2, 'logistic without intercept: native LR df is rank - 1',
          (parent['values'], model['values']))
    rendered = verify(writer, folder, 'lr-df-logistic-no-intercept', parent['record'], equal('df_lr', [1.0]))
    check(re.search(r'Deviance \(likelihood ratio\) chi-square = \* +df = 1 +P = \*', rendered) is not None,
          'logistic without intercept: the replay prints the native LR df', rendered[-1500:])

    poisson = [('Outcome', COUNTS), ('Prior', weights), ('Exposure', EXPOSURES), ('Dose', DOSE), ('Square', square)]
    parent, model = fit(session, 'PoissonRegression', poisson_answers(poisson, [3, 4], False, True, True))
    check(parent['values'].get('df_x2') == 1 and model['values']['x2df'] == 1 and model['values']['rank'] == 2, 'Poisson without intercept: native LR df is rank - 1',
          (parent['values'], model['values']))
    rendered = verify(writer, folder, 'lr-df-poisson-no-intercept', parent['record'], equal('df_lr', [1.0]))
    check(re.search(r'Deviance \(likelihood ratio\) chi-square = \* +df = 1 +P = \*', rendered) is not None and
          re.search(r'Scaled G2 = \* +df = 1 +P = \*', rendered) is not None,
          'Poisson without intercept: the replay prints the native LR df in both lines', rendered[-1500:])


def missing_predictor_stack(session, writer, folder):
    """Item 13: logistic rows that lack the same predictor value are each counted as dropped; the fit is that of the complete rows."""
    response = [2, 3, 4, 5, 6, 8, 6, 10, 11, 12, 14, 6, 15, 17]
    dose = [1.5, 2.5, 3.5, 4.5, 5.5, 6.5, None, 7.5, 8.5, 9.5, 10.5, None, 11.5, 12.5]
    columns = [('Outcome', response), ('Total', [20] * 14), ('Prior', [1] * 14), ('Dose', dose)]
    complete = [i for i in range(14) if dose[i] is not None]
    parent, model = fit(session, 'LogisticRegression', logistic_answers(columns, [3]))
    check(any(w.startswith('2 observations dropped due to missing data') for w in warnings(parent)), 'logistic: two rows lacking the same dose are both counted as dropped',
          warnings(parent))
    fewer = [(title, [values[i] for i in complete]) for title, values in columns]
    expected, _ = fit(session, 'LogisticRegression', logistic_answers(fewer, [3]))
    # The odds ratios are compared as the two reports print them, to 12 places, where Windows compares their logarithms exactly.
    ratios, wanted = [row[1] for row in table(parent, ODDS)[1:]], [row[1] for row in table(expected, ODDS)[1:]]
    check(parent['values']['dev'] == expected['values']['dev'] and parent['values']['df'] == expected['values']['df'] and
          len(ratios) == 1 and ratios == wanted and math.isfinite(float(ratios[0])), 'logistic: the fit is that of the complete rows',
          (parent['values'], expected['values'], ratios, wanted))
    parameters = table(model, PARAMETERS)
    verify(writer, folder, 'logistic-missing-predictor', parent['record'],
           equal('coef(fit), fit$df.residual', [float(row[1]) for row in parameters] + [model['values']['idf']], '1e-8') + 'stopifnot(length(responders) == 12L)\n')


def loess_titles(session, writer, folder):
    """Item 9: LOESS with two predictors of one title: the formula offered and the variables written for R are the record's keys."""
    lx = [i / 5 for i in range(1, 61)]
    lz = [math.sin(v * .7) for v in lx]
    ly = [10 + v + 2 * lz[i] + math.cos(i) for i, v in enumerate(lx)]
    columns = [('Y', ly), ('X', lx), ('X', lz)]
    offered = []

    def by_default(prompt):
        """The formula offered, as the dialog offers it, from the acquired frames."""
        offered.append(prompt.get('defaultValue'))
        return prompt.get('defaultValue')

    run = ask(session, 'LOESS', {'outcome': select(columns, 0), 'predictors': select(columns, 1, 2), 'model': by_default, 'title': 'Y vs. X + X',
                                 'span': .8, 'degree': '2', 'saveFitsAndSe': False, 'saveRScript': True})
    values = run['values']
    recorded = [entry.get('value') for entry in json.loads(run['record'])['inputs'] if entry.get('name') == 'model']
    check(offered == ['y~x+x_2'] and recorded == ['y~x+x_2'],
          'the default LOESS formula names the two X columns x and x_2, as the record keys them (' + str(offered[0] if offered else None) + ')', (offered, recorded))
    check('x_2 <- c(' in str(values.get('formattedRScript')), 'the program writes the second X column for R under its own name', str(values.get('formattedRScript'))[-1500:])
    figures = [values['observations'], values['parameters'], values['residualse']]
    oracle = ('dd <- data.frame(y = ' + vector(ly) + ', a = ' + vector(lx) + ', b = ' + vector(lz) + ')\n' +
              'mm <- loess(y ~ a + b, data = dd, span = 0.8, degree = 2)\n' +
              equal('mm$n, mm$enp, mm$s', figures, '1e-7') + equal('m$n, m$enp, m$s, ncol(m$x)', figures + [2], '1e-7'))
    verify(writer, folder, 'loess-duplicate-titles', run['record'], "plot <- function(...) stop('two predictors have no one-dimensional chart')\n" + oracle)


def cox_answers(columns, predictors):
    """Models539CoxAnswers, as the Mac form asks them (no strata: the question is skipped)."""
    return {'times': select(columns, 0), 'events': select(columns, 1), 'predictors': select(columns, *predictors), 'strata': {'skip': True},
            'accuracy': 1e-11, 'centre-continuous-covariates': True, 'useTimesAdjustment': False}


def charts(state):
    """The report's charts in their order, each as (its SVG, the labels drawn in it)."""
    return [(svg, [label.strip() for label in re.findall(r'>([^<>]*)</tspan>', svg)]) for svg in re.findall(r'<svg.*?</svg>', state['html'], re.S)]


def cox_plots(session, columns, predictors, choice):
    """The Cox fit and its survival plots split by the choice in this place of the list offered: the plots' run, the titles offered."""
    offered = []

    def by_place(prompt):
        offered.extend(option['label'] for option in prompt['options'])
        return [choice]

    fitted = ask(session, 'CoxRegression', cox_answers(columns, predictors), keep=True)
    try:
        plots = ask(session, 'CoxHazardPlots', {'use-tics': True, 'use-markers': True, 'group': by_place}, parent=fitted['id'])
    finally:
        session.close(fitted['id'])
    return plots, offered


def split_by(plots, title):
    """Whether the report's three charts are the survival, hazard and log-log plots of the two groups of the predictor with this title,
    and not of strata: what the chart options (grouped, groupid, stratified) decide on Windows, as the charts show it."""
    drawn = charts(plots)
    return (len(drawn) == 3 and 'Survival Probability (individual)' in drawn[0][1] and '-log(-log(Survival))' in drawn[2][1] and
            all([label for label in labels if '=' in label] == [title + '=0', title + '=1'] and not any(label.startswith('Stratum') for label in labels)
                for _, labels in drawn))


def cox_split(session, writer, folder):
    """Item 8: the survival plots are split by the choice in its place in the list: a predictor titled "None" or "Strata" is split by,
    and of two predictors with one title the one chosen; natively and in the replay."""
    times, events = [6, 7, 10, 15, 19, 25, 2, 4, 8, 12, 14, 20, 23, 30], [1, 1, 1, 1, 0, 1, 1, 1, 1, 0, 1, 1, 1, 0]
    treated, female = [0, 1] * 7, [1, 1, 0, 0, 1, 0, 1, 1, 0, 0, 0, 1, 1, 0]
    age = [51, 63, 47, 58, 66, 49, 71, 55, 60, 44, 68, 52, 57, 62]
    cases = [('none-title-split', [('None', treated), ('Age', age)], 0, 1),
             ('none-title-no-split', [('None', treated), ('Age', age)], 1, 0),
             ('strata-title-split', [('Age', age), ('Strata', treated)], 0, 2),
             ('duplicate-title-second', [('Z', treated), ('Z', female), ('Age', age)], 1, 2)]
    for label, predictors, choice, expected in cases:
        columns = [('Time', times), ('Event', events)] + predictors
        chosen = list(range(2, 2 + len(predictors)))
        plots, offered = cox_plots(session, columns, chosen, choice)
        drawn = charts(plots)
        if expected > 0:
            native = split_by(plots, predictors[expected - 1][0])
        else:
            native = (len(drawn) == 2 and 'Survival Probability (baseline)' in drawn[0][1] and
                      not any('=' in text or text.startswith('Stratum') for _, labels in drawn for text in labels))
        if label == 'duplicate-title-second':
            # Both predictors are drawn as "Z": which one the charts are split by is told from the charts of the same fit with the other
            # predictor under another title. They must be those split by the second (Female), and not those split by the first (Treated).
            second, _ = cox_plots(session, [('Time', times), ('Event', events), ('Q', treated), ('Z', female), ('Age', age)], chosen, 1)
            first, _ = cox_plots(session, [('Time', times), ('Event', events), ('Z', treated), ('Q', female), ('Age', age)], chosen, 0)
            mine, theirs, others = ([svg for svg, _ in charts(run)] for run in (plots, second, first))
            native = native and split_by(second, 'Z') and split_by(first, 'Z') and mine == theirs and mine != others
        check(native, label + ': the native plots are split by choice ' + str(choice) + ' of ' + str(len(offered)) +
              (', predictor ' + str(expected) if expected > 0 else ', not at all'), (offered, [labels for _, labels in drawn]))
        g = str(expected)
        assertions = ('stopifnot(grouped, curve_count == 2L, identical(unname(baseline_rows[[' + g + ']]), sort(unique(predictor_frame[[' + g + ']]))), all(unlist(baseline_rows[-' + g + ']) == 0))\n'
                      if expected > 0 else 'stopifnot(!grouped, curve_count == 1L)\n')
        verify(writer, folder, 'cox-split-' + label, plots['record'], assertions)

    # Incomplete time/event rows may contain a third numeric level or text. Neither belongs in
    # the predictor coding prompt, and both are excluded from the fit and its replay.
    for label, time, event, treated_value in [('missing-time', None, 1, 2), ('missing-event', 35, None, 'excluded')]:
        incomplete = [('Time', times + [time]), ('Event', events + [event]), ('Treated', treated + [treated_value]),
                      ('Female', female + [1]), ('Age', age + [50])]
        plots, offered = cox_plots(session, incomplete, [2, 3, 4], 0)
        check(offered == ['Treated', 'Female', 'None'], label + ': Cox predictors stay binary without an extra coding prompt', offered)
        check(split_by(plots, 'Treated'), label + ': the native plots are split by Treated', [labels for _, labels in charts(plots)])
        verify(writer, folder, 'cox-split-' + label, plots['record'],
               "stopifnot(identical(split_choices, c('Treated', 'Female', 'None')), grouped, split_by == 'Treated', curve_count == 2L, identical(unname(baseline_rows[[1]]), c(0, 1)), all(unlist(baseline_rows[-1]) == 0))\n")


# CheckModels539CoxNames's times and events, drawn from .NET's Random(539) by the engine's own runtime (a C# user script), draw for draw
# as the Windows check draws them: no other generator gives its figures.
COX_NAMES_DRAWS = r"""
foreach (int n in new[] { 14, 1100 })
{
    System.Random random = new(539);
    double[] time = new double[n], events = new double[n];
    for (int i = 0; i < n; i++)
    {
        double treated = i % 2, female = i / 3 % 2, age = 40 + i * 7 % 35;
        time[i] = Math.Ceiling(-Math.Log(1 - random.NextDouble()) / Math.Exp(.6 * treated - .4 * female + .02 * (age - 57)) * 20);
        events[i] = random.NextDouble() < .75 ? 1 : 0;
    }
    Console.WriteLine("time" + n + " [" + string.Join(",", time.Select(v => v.ToString("R", System.Globalization.CultureInfo.InvariantCulture))) + "]");
    Console.WriteLine("events" + n + " [" + string.Join(",", events.Select(v => v.ToString("R", System.Globalization.CultureInfo.InvariantCulture))) + "]");
}
"""


def entered(series):
    """Columns typed into the form under these titles: an entered frame."""
    return {'source': 'Test fixture', 'columns': [{'title': title, 'values': list(values)} for title, values in series]}


def grid_text(value):
    """A number as the grid shows it: a whole number without a point; these fixtures need no exponent."""
    text = str(int(value)) if float(value).is_integer() else repr(float(value))
    assert 'e' not in text, text
    return text


def grid_frames(record, worksheet):
    """The frames the Mac host supplies when it reads a record's values again from its worksheet (as test_duplicate_predictor_replay.py
    supplies them): each frame the record does not hold, by its index, each pointer column's cells over its recorded rows below the
    title row, as the grid's texts and kinds, under the record's title."""
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


def cox_names(session, writer, folder):
    """Item 12: the replay's unique predictor names for Cox regression and its hazard ratio follow-on, from each of the record's paths:
    values held in the record, a reread of the worksheet (above the 5,000 values a record holds), and values entered without one."""
    draws = managed(session, COX_NAMES_DRAWS)
    for path, n in [('held', 14), ('reread', 1100), ('entered', 14)]:
        time, events = draws['time' + str(n)], draws['events' + str(n)]
        assert len(time) == len(events) == n and set(events) <= {0, 1} and all(t >= 1 and float(t).is_integer() for t in time), (time[:20], events[:20])
        treated, female, age = [i % 2 for i in range(n)], [i // 3 % 2 for i in range(n)], [40 + i * 7 % 35 for i in range(n)]
        columns = [('Time', time), ('Event', events), ('Z', treated), ('Z', female), ('Age', age)]

        def frame(*selected):
            return entered([columns[c] for c in selected]) if path == 'entered' else select(columns, *selected)

        # The Mac asks how to code Age, of five values: as a number, which is how the Windows check fits it.
        fitted = ask(session, 'CoxRegression', {'times': frame(0), 'events': frame(1), 'predictors': frame(2, 3, 4), 'strata': {'skip': True}, 'accuracy': 1e-11,
                                                 'centre-continuous-covariates': True, 'useTimesAdjustment': False,
                                                 'Choose the reference category for Age': '-2'}, keep=True)
        try:
            # The 90% interval is asked for and answered, as the Windows check answers gamma .9, where the other fits take the default.
            ratios = ask(session, 'CoxHazardRatios', {'gamma': 90}, parent=fitted['id'], prefs=dict(PREFS, **{'use-default-ci': False}))
        finally:
            session.close(fitted['id'])
        b = [value for _, value in coefficients(fitted)]
        hazard = table(ratios, ['Parameter', 'Hazard Ratio', '90% CI'])
        limits = [re.fullmatch(r'(\S+) to (\S+)', row[2]) for row in hazard]
        assert len(b) == len(hazard) == 3 and all(limits), (coefficients(fitted), hazard)
        figures = [float(row[1]) for row in hazard] + [float(m.group(1)) for m in limits] + [float(m.group(2)) for m in limits]
        for label, state in [('model', fitted), ('ratios', ratios)]:
            record = json.loads(state['record'])
            predictors = next(item for item in record['inputs'] if item['name'] == 'predictors')
            check(predictors.get('kind') == ('entered' if path == 'entered' else 'frame') and ('data' in record) == (path == 'held'),
                  'Cox ' + label + ' record keeps its predictors as ' + path + ' values', (predictors.get('kind'), 'data' in record))
            script = writer.write(state['record'], grid_frames(record, columns) if path == 'reread' else ())
            check(bool(script.get('hasRecipe')) and not script.get('dataUnavailable'), 'Cox ' + label + ' from ' + path + ' values exports its data for replay',
                  {key: script.get(key) for key in ('hasRecipe', 'dataUnavailable', 'error')})
            assertions = "stopifnot(identical(names(predictors), c('Z', 'Z_2', 'Age')))\n" + (
                equal('coef(fit)', b, '1e-7') if label == 'model' else
                equal('exp(coef(fit)), exp(coef(fit) - qnorm(0.95) * sqrt(diag(vcov(fit)))), exp(coef(fit) + qnorm(0.95) * sqrt(diag(vcov(fit))))', figures, '1e-7'))
            result = run_r(folder / ('cox-names-' + path + '-' + label), (script.get('text') or '') + '\n' + assertions + "cat('MODELS_539_OK\\n')\n")
            check(result.returncode == 0 and 'MODELS_539_OK' in result.stdout,
                  'Cox ' + label + ' from ' + path + ' values replays Z and Z_2 as two predictors, with the native figures', (result.returncode, result.stderr[-1500:]))


GROUPS = [
    ('fewer rows than parameters', fewer_rows),
    ('lone aliased predictor', lone_predictor),
    ('no predictor left', no_predictor_left),
    ('zero residual df', zero_residual_df),
    ('Poisson scaled Wald', scaled_wald),
    ('logistic Schwarz criterion', schwarz),
    ('Hosmer-Lemeshow cuts', hosmer_lemeshow_cuts),
    ('constant predictor', constant_predictor),
    ('Cox split', cox_split),
    ('Cox names', cox_names),
    ('LOESS with two predictors of one title', loess_titles),
    ('no-intercept likelihood ratio df', no_intercept_lr_df),
    ('missing predictor stack', missing_predictor_stack),
]


if __name__ == '__main__':
    (ROOT / '.build').mkdir(exist_ok=True)
    folder = Path(tempfile.mkdtemp(prefix='models-539-', dir=ROOT / '.build'))
    # LOESS is run by R: its run folders and package library are kept out of Application Support, as test_r_operations.py keeps them.
    r_folder = Path(tempfile.mkdtemp(prefix='models-539-r-'))
    os.environ['STATSDIRECT_R_FOLDER'] = str(r_folder)
    shared_library = Path('~/Library/Application Support/StatsDirect Viewer/R Library').expanduser()
    if shared_library.is_dir():
        (r_folder / 'R Library').symlink_to(shared_library)
    session, writer = Session(), ScriptWriter()
    stopped = []
    try:
        for name, group in GROUPS:
            try:
                group(session, writer, folder)
            except Exception as error:
                stopped.append(name)
                print('FAIL:', name, 'stopped:', ' '.join(f'{type(error).__name__}: {error}'[:4000].split()), flush=True)
    finally:
        writer.close()
        session.finish()
        shutil.rmtree(r_folder, ignore_errors=True)
    print(f'MODELS 539: {len(PASSED)} checks passed, {len(FAILED) + len(stopped)} failed', flush=True)
    if FAILED or stopped:
        print('Retained test artifacts:', folder, flush=True)
        sys.exit(1)
    shutil.rmtree(folder)
