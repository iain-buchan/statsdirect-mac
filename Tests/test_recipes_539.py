#!/usr/bin/env python3
"""The Continue in R recipes of the 5.3.9 review, on the Mac.

A mirror of CheckRecipes539 in FullEngine/Upstream/tests/RScript/Recipes539.cs of Windows v5.3.9 (f41aad46): scripts that
stopped where the report completed, replayed another analysis, or did not take the report's confidence fallback, and the
native Royston K2. Each case gives the Windows case's own data and options to the Mac operation host as a worksheet
selection, takes the record the completed run leaves, has the engine write its R script (the statsdirect_r_script entry,
as Continue in R does), runs the script in R within the Windows time limit with the Windows assertions after it, and
compares R's figures with the native report. One PASS line is printed for each Windows case.

What the Mac does differently, and why (nothing is compared more loosely than on Windows):
  * Windows reads the native figures from the operation's output bag. The Mac host gives the top-level figures of the bag
    as the run's values; figures inside a list of the bag (the expected frequencies, the interval for a Mann-Whitney or
    Wilcoxon difference, the normality tests of each variable, the hazard ratios and the like) are read from the native
    report at 12 decimal places, the most the analysis options allow, and compared at the Windows tolerance.
  * Windows asks RRecipes.Find for the recipe's file. The Mac's entry gives the script and whether it has a recipe, not
    the file's name, so the file is told by the script: it holds the body of the expected recipe and of none of the
    other analyses' recipes. (The label's own answers for such records are test_recipe_by_record.py's.)
  * The replicated two way analysis is asked repeat by repeat, as the Mac asks it; the frame it builds is the one the
    Windows check builds by hand. The change of a polynomial's degree is a follow-on of the degree 2 fit, as in the app.
  * Confidence is typed as a percentage (95); the record keeps the fraction (0.95), as on Windows.
  * A confidence level typed as 0% or 100% is refused by the Mac's host ("Confidence must be greater than 0 and less
    than 100 percent"), where the Windows host records 0 or 1 and the report takes 95%. Such a record reaches a Mac
    only in a result saved on Windows, so those cases run the report at 95% and give the writer its record with the
    level Windows would have recorded (0 or 1): the script must then reproduce the 95% report, as on Windows.
    What those cases cannot show on a Mac is the report's own fallback (the Cox hazard ratios' is new in 5.3.9),
    because the Mac's host never hands the engine such a level.
  * The quick summary reports through its builtin and leaves no record, on the Mac as on Windows. The Windows check
    writes its record by hand (RunRecord.Write, from the frame the grid acquired and the recorded level); the Mac's is
    written by hand too: the frame entry is the one the Mac's host records for the same selection in another analysis.
  * The 5.3.10 writer's hexadecimal literals let the paired differences at shifts 0.1 and 1.1 run on Apple Silicon
    at the original tolerance, which decimal literals could not reliably meet.

STATSDIRECT_RECIPES539_CONTINUE=1, as on Windows, notes a failing case with R's last words and runs the others, to show
what fails before a fix; the run still fails at its end. STATSDIRECT_RECIPES539_ONLY names one part to run.
"""
import json
import math
import os
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path

from r_runtime import rscript
from test_menu import ROOT, Session
from test_pr6_replay import sheet
from test_shared_engine_update import ReportText

ENGINE = os.environ.get('STATSDIRECT_TEST_ENGINE', str(ROOT / 'FullEngine/publish/StatsDirectEngine.dylib'))
# The recipes the engine itself reads (FullEngine/Exports.cs): beside the library in the source tree (FullEngine/publish); in the app,
# whose engine library is in Contents/Frameworks, in Contents/Resources/Engine (as published_recipe of test_posthoc_meta.py looks).
BESIDE = Path(ENGINE).resolve().parent
RECIPES = next((folder / 'R' / 'recipes' for folder in (BESIDE, BESIDE.parent / 'Resources/Engine') if (folder / 'R' / 'recipes').is_dir()),
               BESIDE / 'R' / 'recipes')
PREFS = {'use-default-ci': False, 'default-ci': '95', 'decp': '12', 'pdecp': '7'}   # every confidence level is asked for, and answered as the Windows case answers it
PARTS = ['gof', 'kendall', 'mann-whitney', 'routing', 'agreement', 'fallback', 'paired', 'pca', 'k2']
CONTINUE = os.environ.get('STATSDIRECT_RECIPES539_CONTINUE') == '1'
ONLY = os.environ.get('STATSDIRECT_RECIPES539_ONLY') or None
UNIDENTIFIED = 'does not identify its original analysis'
NUMBER = re.compile(r'[-+]?(?:\d+\.?\d*|\.\d+)(?:[Ee][-+]?\d+)?')
FIGURE = r'(-?[0-9]+(?:\.[0-9]+)?(?:[eE][-+]?[0-9]+)?)'
FAILED = []
PASSED = []


class Failure(Exception):
    pass


def check(condition, message):
    if not condition:
        raise Failure('FAIL ' + message)


def case(label, body):
    """One Windows case (Case539): the first failure stops the run unless STATSDIRECT_RECIPES539_CONTINUE=1."""
    if not CONTINUE:
        body()
    else:
        try:
            body()
        except (Failure, AssertionError, subprocess.TimeoutExpired, KeyError, ValueError) as error:
            lines = [line for line in str(error).replace('\r', '').split('\n') if line.strip()] or [type(error).__name__]
            said = lines[0] + (' ... ' + ' / '.join(lines[max(1, len(lines) - 2):]) if len(lines) > 1 else '')
            FAILED.append(label + ': ' + said)
            print('FAILED CASE ' + label + ': ' + said, flush=True)
            return
    PASSED.append(label)
    print('PASS: ' + label, flush=True)


class Writer:
    """The R script entry as the Mac host calls it ({record, title, frames}); its answer is returned as it is, for the checks to judge."""
    def __init__(self):
        self.process = subprocess.Popen([str(ROOT / 'Tests/engine-driver'), ENGINE, 'statsdirect_r_script'],
                                        stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)

    def call(self, request):
        self.process.stdin.write(json.dumps(request) + '\n')
        self.process.stdin.flush()
        return json.loads(self.process.stdout.readline())

    def write(self, record, frames=()):
        return self.call({'record': record, 'title': None, 'frames': list(frames)})

    def close(self):
        self.process.stdin.close()
        assert self.process.wait(timeout=15) == 0


def body_of(file):
    """The body of a recipe, after its header, as RScriptWriter.Parse reads it."""
    lines = (RECIPES / file).read_text(encoding='utf-8').replace('\r\n', '\n').split('\n')
    last = -1
    i = 0
    while i < len(lines) and (lines[i].strip() == '' or lines[i].startswith('#')):
        if re.match(r'^#\s*(data|table|matrix|nested|settings|recipe|repeat|titles):', lines[i], re.I) or re.match(r'^# (StatsDirect recipe|From the help|hand-edited)', lines[i], re.I):
            last = i
        i += 1
    body = '\n'.join(lines[last + 1:]).strip('\n')
    assert len(body) > 200, file
    return body


ROUTED = ['one-way-anova.R', 'two-way.R', 'replicate-two-way.R', 'polynomial-regression.R', 'multiple-linear-regression.R']


def recipes_in(text):
    """Which of the routed analyses' recipes the script holds."""
    return [file for file in ROUTED if body_of(file) in (text or '').replace('\r\n', '\n')]


def number(value):
    """Num539: a number, or the first number of a text."""
    if isinstance(value, str):
        return float(NUMBER.search(value).group(0))
    return float(value)


def num(values, key):
    return number(values[key])


def figure(report, label):
    """The first figure of the report row with this label."""
    found = [row for row in report.rows if row and row[0] == label and len(row) > 1]
    check(len(found) == 1, 'the native report has one row "' + label + '": ' + repr(found)[:300])
    return number(found[0][1])


def vector(values):
    return 'c(' + ', '.join('NA' if v is None or (isinstance(v, float) and math.isnan(v)) else format(float(v), '.17g') for v in values) + ')'


def strings(values):
    return 'c(' + ', '.join(json.dumps(v, ensure_ascii=False) for v in values) + ')'


def equal(expression, expected, tolerance=1e-9):
    """Equal539."""
    return 'stopifnot(isTRUE(all.equal(unname(c(' + expression + ')), ' + vector(expected) + ', tolerance = ' + repr(float(tolerance)) + ', check.attributes = FALSE)))\n'


def select(cells, *chosen):
    """The answer to a frame prompt: the chosen columns of the worksheet (Select539)."""
    answer = json.loads(json.dumps(cells))
    answer['columns'] = [answer['columns'][c] for c in chosen]
    answer['range']['columns'] = list(chosen)
    return answer


def run_r(code, label, timeout):
    """DeferredR538: the script run in R within the time limit; its output."""
    with tempfile.TemporaryDirectory(prefix='recipes-539-') as folder:
        path = Path(folder) / 'replay.R'
        path.write_text(code, encoding='utf-8')
        try:
            result = subprocess.run([rscript(), '--vanilla', '--encoding=UTF-8', str(path)], cwd=folder, text=True, capture_output=True, timeout=timeout)
        except subprocess.TimeoutExpired:
            raise Failure('FAIL ' + label + ': R did not finish within ' + str(timeout) + ' s')
        if result.returncode != 0:
            raise Failure('FAIL ' + label + ': R stopped (exit ' + str(result.returncode) + ')\n' + (result.stdout[-600:] + '\n' + result.stderr[-900:]).strip())
        return result.stdout


def replay(record, assertion, label, frames=(), setup='', timeout=120):
    """Replay539: the script of the run's record, run in R within the time limit with the assertions after it."""
    script = WRITER.write(record, frames)
    check(script.get('hasRecipe') is True and not script.get('dataUnavailable') and not script.get('relocate') and 'has changed in the workbook' not in script.get('text', ''),
          label + ': the record keeps or rereads the selected data and has its recipe: ' + json.dumps({k: v for k, v in script.items() if k != 'text'})[:400])
    output = run_r(setup + script['text'] + '\n' + assertion + "\ncat('RECIPES_539_OK\\n')\n", label, timeout)
    check('RECIPES_539_OK' in output, label + ': R reproduces the native report')
    return output


def native(operation, answers, parent=None, keep=False):
    return SESSION.run(operation, answers, PREFS, parent=parent, keep=keep)


def legacy(record):
    """Legacy539: the record as saved before 5.2.3, which did not name the root analysis of a follow-on."""
    return {key: value for key, value in record.items() if key != 'rootOperation'}


def permutation(n, inversions):
    """Permutation539: an ordering of 1..n with the given number of inversions (greedy Lehmer code)."""
    available = list(range(1, n + 1))
    values = []
    for j in range(n):
        k = int(min(inversions, n - 1 - j))
        values.append(available.pop(k))
        inversions -= k
    return values


# 4. The multiple comparisons continue a one way, two way or replicated two way analysis of variance, and the regression
#    analysis of variance a multiple linear or polynomial regression: each follow-on replays the analysis it continues,
#    whose residual mean square and degrees of freedom are those the native comparisons use.
def check_routing():
    comparisons = ['Tukey', 'Bonferroni', 'Scheffe', 'NewmanKeuls', 'Dunnett']

    def answers(operation):
        if operation == 'Bonferroni':
            return {'gamma': 95, 'variables': [0, 1], 'comparisons': 6}
        if operation == 'Dunnett':
            return {'gamma': 95, 'indexvariable': [0]}
        return {'gamma': 95}

    def compare(root, parent, file, table, mean_square, df):
        for operation in comparisons:
            def body(operation=operation):
                run = native(operation, answers(operation), parent=parent['id'])
                record = json.loads(run['record'])
                now = WRITER.write(record)
                check(record.get('rootOperation') == root and now.get('hasRecipe') is True and recipes_in(now.get('text')) == [file],
                      operation + ' after ' + root + ' is replayed by ' + file)
                old = WRITER.write(legacy(record))
                check(old.get('hasRecipe') is False and recipes_in(old.get('text')) == [] and UNIDENTIFIED in (old.get('detail') or ''),
                      operation + ' after ' + root + ' saved without its root analysis (before 5.2.3) asks for a rerun rather than guessing the analysis')
                b = run['values']
                error = ''
                if operation == 'Tukey':
                    error = equal("sqrt(anova(fit)['Residuals', 'Mean Sq'])", [num(b, 'psd')])
                elif operation == 'Bonferroni':
                    error = equal("anova(fit)['Residuals', 'Df']", [num(b, 'df')])
                replay(record, table + equal("anova(fit)['Residuals', 'Mean Sq'], anova(fit)['Residuals', 'Df']", [mean_square, df]) + error,
                       root + '-' + operation, setup='pdf(NULL)\n')
            case('routing ' + operation + ' after ' + root, body)

    # Clotting times of plasma from eight subjects treated in four ways (Armitage and Berry 1994), the help's two way example.
    treatments = [[8.4, 12.8, 9.6, 9.8, 8.4, 8.6, 8.9, 7.9], [9.4, 15.2, 9.1, 8.8, 8.2, 9.9, 9.0, 8.1],
                  [9.8, 12.9, 11.2, 9.9, 8.5, 9.8, 9.2, 8.2], [12.2, 14.4, 9.8, 12.0, 8.5, 10.9, 10.4, 10.0]]
    cells = sheet(['Treatment ' + letter for letter in 'ABCD'], treatments)
    one_way = native('OneWay', {'data': select(cells, 0, 1, 2, 3)}, keep=True)
    try:
        o = one_way['values']
        compare('OneWay', one_way, 'one-way-anova.R', equal("a$'Sum Sq', a$Df", [num(o, k) for k in ('b_sum', 'w_sum', 'b_df', 'w_df')]), num(o, 'w_mean'), num(o, 'w_df'))
    finally:
        SESSION.close(one_way['id'])
    two_way = native('TwoWay', {'data': select(cells, 0, 1, 2, 3)}, keep=True)
    try:
        t2 = two_way['values']
        compare('TwoWay', two_way, 'two-way.R', equal("anova(fit)$'Sum Sq', anova(fit)$Df", [num(t2, k) for k in ('sub_sum', 'grp_sum', 'res_sum', 'sub_df', 'grp_df', 'res_df')]), num(t2, 'res_mean'), num(t2, 'res_df'))
    finally:
        SESSION.close(two_way['id'])
    # The replicated two-way example (three subjects, three treatments, three repeats). Windows gives its two-level frame
    # as the grid builds it; the Mac asks it repeat by repeat (subjects in rows, treatments in columns) and builds the same frame.
    blocks = [[[9.8, 10.1, 9.8], [9.9, 9.5, 10.0], [11.3, 10.7, 10.7]],
              [[9.2, 8.6, 9.2], [9.1, 9.1, 9.4], [10.3, 10.7, 10.2]],
              [[8.4, 7.9, 8.0], [8.6, 8.0, 8.0], [9.8, 10.1, 10.1]]]
    asked = {'layout2d': 'columns', 'Number of repeats': {'n': 3}}
    for r in range(3):
        asked['Repeat %d: subjects in rows, treatments in columns' % (r + 1)] = {
            'columns': [{'title': '', 'values': [block[c][r] for block in blocks]} for c in range(3)], 'source': 'Test fixture'}
    replicate = native('ReplicateTwoWay', asked, keep=True)
    try:
        frame = next(item for item in json.loads(replicate['record'])['inputs'] if item['name'] == 'data2d')
        check([[column['values'] for column in block] for block in frame['value']['frames']] == blocks, 'the replicated two way frame asked repeat by repeat is the frame of the Windows check')
        r2 = replicate['values']
        compare('ReplicateTwoWay', replicate, 'replicate-two-way.R', equal("anova(fit)$'Sum Sq', anova(fit)$Df", [num(r2, k) for k in ('sub_sum', 'grp_sum', 'int_sum', 'res_sum', 'sub_df', 'grp_df', 'int_df', 'res_df')]), num(r2, 'res_mean'), num(r2, 'res_df'))
    finally:
        SESSION.close(replicate['id'])

    # The regression analysis of variance after a polynomial regression (the help's example, degree 2 and then 3)
    size = [1290, 1350, 1470, 1600, 1710, 1840, 1980, 2230, 2400, 2930]
    kwh = [1182, 1172, 1264, 1493, 1571, 1711, 1804, 1840, 1956, 1954]
    poly = sheet(['Size', 'kWh'], [size, kwh])

    def anova(a):
        return equal('ssreg, degree, ssreg / degree, ssres, df, ssres / df, ssreg + ssres, df + degree, sqrt(ssres / df), f[1], pf(f[1], f[2], f[3], lower.tail = FALSE), 100 * summary(fit)$r.squared, 100 * summary(fit)$adj.r.squared, sum(diff(e)^2) / sum(e^2)',
                     [num(a, k) for k in ('reg_sum', 'reg_df', 'reg_mean', 'res_sum', 'res_df', 'res_mean', 'tot_sum', 'tot_df', 'mse', 'f', 'p', 'r2', 'ra2', 'dw')])

    for root in ('PolynomialRegression', 'PolynomialRegressionChangeDegree'):
        def body(root=root):
            kept = []
            try:
                fitted = native('PolynomialRegression', {'y': select(poly, 1), 'x': select(poly, 0), 'degree': '2'}, keep=True)
                kept.append(fitted['id'])
                if root != 'PolynomialRegression':   # on the Mac the change of degree continues the fit, as in the app
                    fitted = native(root, {'degree': '3'}, parent=fitted['id'], keep=True)
                    kept.append(fitted['id'])
                run = native('MultipleLinearRegressionAnova', {'ci': 95}, parent=fitted['id'])
            finally:
                for id in reversed(kept):
                    SESSION.close(id)
            record = json.loads(run['record'])
            check(num(run['values'], 'reg_df') == (2 if root == 'PolynomialRegression' else 3), 'the regression ANOVA after ' + root + ' is of the degree fitted')
            now = WRITER.write(record)
            check(record.get('rootOperation') == root and now.get('hasRecipe') is True and recipes_in(now.get('text')) == ['polynomial-regression.R'],
                  'the regression ANOVA after ' + root + ' is replayed by polynomial-regression.R')
            old = WRITER.write(legacy(record))
            check(old.get('hasRecipe') is True and recipes_in(old.get('text')) == ['polynomial-regression.R'],
                  'a regression ANOVA after ' + root + ' saved without its root analysis is known by its y and x frames')
            replay(record, anova(run['values']), root + '-anova')
        case('routing regression ANOVA after ' + root, body)

    # ... and after the multiple linear regression it continues, as before
    def linear():
        x1 = [2.26, 1.81, 1.78, 1.54, 2.06, 1.74, 2.56, 2.29, 1.80, 2.32, 2.04, 1.88]
        x2 = [66.2, 52.7, 72.1, 67.4, 69.9, 71.3, 88.6, 68.2, 59.5, 73.8, 68.4, 58.1]
        y = [7, 10, 18, 4, 10, 13, 21, 12, 9, 65, 20, 31]
        mlr = sheet(['Outcome', 'First', 'Second'], [y, x1, x2])
        model = native('MultipleLinearRegression', {'outcome': select(mlr, 0), 'predictors': select(mlr, 1, 2), 'ci': 95, 'calculateIntercept': True, 'useWeights': False}, keep=True)
        try:
            run = native('MultipleLinearRegressionAnova', {'ci': 95}, parent=model['id'])
        finally:
            SESSION.close(model['id'])
        record = json.loads(run['record'])
        now, old = WRITER.write(record), WRITER.write(legacy(record))
        check(record.get('rootOperation') == 'MultipleLinearRegression' and now.get('hasRecipe') is True and recipes_in(now.get('text')) == ['multiple-linear-regression.R']
              and old.get('hasRecipe') is True and recipes_in(old.get('text')) == ['multiple-linear-regression.R'],
              'the regression ANOVA after a multiple linear regression keeps its recipe, with or without its saved root analysis')
        replay(record, equal('ssreg, k, ssres, df, sqrt(ssres / df), summary(fit)$fstatistic[1], 100 * summary(fit)$r.squared, 100 * summary(fit)$adj.r.squared',
                             [num(run['values'], k) for k in ('reg_sum', 'reg_df', 'res_sum', 'res_df', 'mse', 'f', 'r2', 'ra2')]), 'MultipleLinearRegression-anova')
    case('routing regression ANOVA after MultipleLinearRegression', linear)


# 9. Royston's adjustment of K2 when the raw K2 is 1,400 or more: the report's normal deviate of exp(-K2 / 2) was the
#    leading term of the tail's expansion only, so its adjusted K2 differed from R's in the 7th figure.
def check_k2():
    for n in (400, 2001, 4000, 5200):
        def body(n=n):
            # a long right tail: a few very large values among small ones
            values = [400 + i % 13 if i % 97 == 0 else 10 + math.sin(i * .37) + (i % 7) * .1 for i in range(1, n + 1)]
            run = native('Normality', {'data': sheet(['Skewed'], [values])})
            report = ReportText(run['html'])
            check(figure(report, 'Sample size') == n, 'n = %d: the native report is of every value' % n)
            k2 = figure(report, 'Royston chi-sq')
            record = json.loads(run['record'])
            assertion = ('stopifnot(n == %d, (z1^2 + z2^2 >= 1400) == %s)\n' % (n, 'TRUE' if n > 400 else 'FALSE')
                         + equal('-2 * log_pk', [k2], 1e-12) + equal('skew, kurt', [figure(report, 'Skewness'), figure(report, 'Kurtosis')], 1e-12))
            # Windows gives the worksheet's reader to the writer for every n. A Mac record holds the values of up to 5,000
            # observations; above that the app is asked for the frame and rereads it from the worksheet.
            frames = []
            first = WRITER.write(record)
            if first.get('asked') or first.get('dataUnavailable'):
                check(n > 5000 and first.get('asked') == ['data'], 'n = %d: only a record of more than 5,000 values asks for its worksheet data: %s' % (n, json.dumps({k: v for k, v in first.items() if k != 'text'})[:300]))
                frames = [{'name': 'data', 'columns': [{'title': 'Skewed', 'values': values}]}]
            else:
                check(n <= 5000, 'n = %d: the record of more than 5,000 values keeps a pointer to them, not the values' % n)
            text = replay(record, assertion, 'skewed-%d' % n, frames=frames, setup='pdf(NULL)\n', timeout=180)
            printed = re.findall(r'^Royston chi-sq ' + FIGURE + ',', text, re.M)
            check(len(printed) == 1 and abs(float(printed[0]) - k2) <= 5.1e-7, 'n = %d: the replay prints the report\'s adjusted K2 (%r)' % (n, k2))
        case('k2 skewed %d' % n, body)


def typed_level(record, name, level):
    """The record Windows leaves when the confidence is typed as 0% or 100% (recorded 0 or 1) and the report takes 95%:
    the Mac's host refuses such a level, so this is the 95% run's record with the level as Windows would have recorded it."""
    edited = json.loads(json.dumps(record))
    check(edited['parameters'][name] == 0.95, 'the record of the 95% run keeps its level')
    edited['parameters'][name] = level
    entries = [item for item in edited['inputs'] if item['name'] == name and item.get('kind') == 'confidence']
    check(len(entries) == 1 and entries[0]['value'] == 0.95, 'the record of the 95% run keeps the level asked for')
    entries[0]['value'] = level
    return edited


def confidence_run(operation, answers, name, confidence, parent=None):
    """The native run at the confidence the report uses (its fallback for 0 and 1 is 95%), and the record of the level typed."""
    used = confidence if 0 < confidence < 1 else .95
    run = native(operation, dict(answers, **{name: round(used * 100, 10)}), parent=parent)
    record = json.loads(run['record'])
    check(record['parameters'][name] == used, operation + ': the confidence asked for is the confidence recorded')
    return run, (record if used == confidence else typed_level(record, name, confidence)), used


# 1. Expected counts (or percentages, or proportions that do not add up to 1) are scaled to the observed total by the
#    report; chisq.test needs rescale.p = TRUE to do the same. A category whose observed or expected cell is empty is
#    left out by the report, where chisq.test stopped on the missing value.
def check_gof():
    def one(label, observed, expected, simulate=False):
        def body():
            names = ['Group ' + chr(ord('A') + i) for i in range(len(observed))]
            kept = [name for i, name in enumerate(names) if observed[i] is not None and expected[i] is not None]
            cells = sheet(['Observed', 'Expected', 'Category'], [['' if v is None else v for v in observed], ['' if v is None else v for v in expected], names])
            run = native('ChiSquareGoodnessOfFit', {'observed': select(cells, 0), 'expected': select(cells, 1), 'names': select(cells, 2)}, keep=True)
            try:
                bag = run['values']
                # the rows of the bag's list of frequencies, read from the report's table (category, observed, expected)
                rows = ReportText(run['html']).rows
                check(rows[:1] == [['Count', 'Observed frequency', 'Expected frequency']] and all(len(row) == 3 for row in rows), label + ': the report has its table of frequencies')
                frequencies = rows[1:]
                check(len(frequencies) == len(kept) and [row[0] for row in frequencies] == kept, label + ': the report uses the %d categories with both counts' % len(kept))
                assertion = (equal('sum(observed), test$parameter', [num(bag, 'n'), num(bag, 'df')])
                             + equal('test$expected', [number(row[2]) for row in frequencies])
                             + ('stopifnot(abs(test$statistic) < 1e-12, abs(test$p.value - 1) < 1e-12)\n' if num(bag, 'chi2') == 0
                                else equal('test$statistic, test$p.value', [num(bag, 'chi2'), num(bag, 'p')]))
                             + 'stopifnot(identical(names(observed), ' + strings(kept) + '))\n')
                replay(json.loads(run['record']), assertion, label)
                if not simulate:
                    return
                follow = native('ChiGFSimulateExactP', {'iterations': 2000, 'seed': 11, 'ci': 99}, parent=run['id'])
                check(json.loads(follow['record'])['parameters'] == {'iterations': 2000, 'seed': 11, 'ci': 0.99}, label + ': the simulation is run as asked')
                replay(json.loads(follow['record']), assertion, label + '-simulated')
            finally:
                SESSION.close(run['id'])
        case('gof ' + label, body)

    one('counts-equal-total', [10, 20, 30, 25, 15], [10, 20, 30, 25, 15], simulate=True)
    one('counts-other-total', [12, 18, 33, 22, 15], [20, 40, 60, 50, 30])
    one('percentages', [67, 83, 29, 8], [44, 45, 8, 3])
    one('proportions-below-one', [9, 21, 28, 30, 12], [.1, .2, .3, .25, .1])
    one('proportions-help', [67, 83, 29, 8], [.44, .45, .08, .03])
    one('missing-counts', [10, 20, None, 25, 15, 12], [10, 20, 30, 25, None, 18], simulate=True)


# 2. Kendall's rank correlation: the replay used to stop on any tie, gave R's normal approximation as the exact test from
#    50 pairs, and did not keep tau's limits within -1 and 1. The report's exact P counts the orderings without ties
#    through 1,000 pairs and uses its Edgeworth series above (kendp), whether or not there are ties.
def check_kendall():
    def one(label, x, y, confidence=.95, timeout=120):
        def body():
            cells = sheet(['First ranking', 'Second ranking'], [x, y])
            run, record, used = confidence_run('Kendall', {'data': select(cells, 0, 1)}, 'gamma', confidence)
            b = run['values']
            ties = num(b, 'tie') > 0
            check(num(b, 'pc') == used * 100, label + ': the native report uses its confidence fallback')
            assertion = ('stopifnot(n == %d, confidence == %r)\n' % (num(b, 'obs'), used)
                         + equal('concordant, discordant, tied, score', [num(b, k) for k in ('con', 'dis', 'tie', 's')])
                         + equal('se, score / (concordant + discordant), tau, limits', [num(b, k) for k in ('ses', 'gam', 'tau', 'll', 'ul')])
                         + equal('upper', [num(b, 'p_uexact')]) + equal('lower', [num(b, 'p_lexact')])
                         + equal('min(1, 2 * min(upper, lower))', [num(b, 'p_2exact')]))
            text = replay(record, assertion, label, timeout=timeout)
            check(("Kendall's tau b =" in text) == ties and ("Kendall's tau =" in text) == (not ties), label + ': tau b is named when there are ties, as in the report')
            z = re.findall(r'^z = ([-0-9.]+)\s+Upper side P = ([0-9.]+)\s+Lower side P = ([0-9.]+)\s+Two sided P = ([0-9.]+)', text, re.M)

            def near(m, z_key, upper_key, lower_key, two_key):
                return (abs(float(m[0]) - num(b, z_key)) <= 5.1e-7 * max(1, abs(num(b, z_key)))
                        and all(abs(float(m[g]) - num(b, key)) <= 5.1e-5 for g, key in ((1, upper_key), (2, lower_key), (3, two_key))))
            check(len(z) == 2 and near(z[0], 'kz', 'p_u', 'p_l', 'p_2') and near(z[1], 'kzcc', 'p_ucc', 'p_lcc', 'p_2cc'),
                  label + ': the normal approximations, with and without the continuity correction, are the report\'s')
        case('kendall ' + label, body)

    career = [4, 10, 3, 1, 9, 2, 6, 7, 8, 5]
    psychology = [5, 8, 6, 2, 10, 3, 9, 4, 7, 1]
    one('help-example', career, psychology)
    for n in (49, 50, 80, 171, 400, 1000, 1001, 1500):
        pairs = n * (n - 1) // 2
        order = permutation(n, int(pairs * .48))
        one('untied-%d' % n, [100 + 2.5 * i for i in range(1, n + 1)], [float(v) for v in order], .9, timeout=240)
    one('ties-x', [1, 2, 2, 3, 4, 4, 4, 5, 6, 7, 8, 8], [3, 1, 4, 2, 6, 5, 9, 7, 8, 12, 10, 11])
    one('ties-y', [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15], [2, 1, 1, 3, 5, 5, 4, 7, 7, 7, 9, 8, 10, 10, 12])
    one('ties-in-both', [1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10], [1, 1, 3, 2, 2, 4, 4, 4, 6, 5, 5, 7, 9, 9, 8, 8, 10, 12, 11, 11])
    one('ties-heavy-60', [float(i % 6) for i in range(60)], [float((i * 7 + i // 6) % 5) for i in range(60)], .99)
    one('ties-1100', [float(i // 3) for i in range(1100)], [float(v // 2) for v in permutation(1100, 1100 * 1099 // 2 * 47 // 100)], timeout=240)
    one('clamped-upper', [1, 2, 3, 4, 5, 6, 7, 8], [1, 2, 3, 4, 5, 6, 8, 7])
    one('clamped-lower', [1, 2, 3, 4, 5, 6, 7, 8], [8, 7, 6, 5, 4, 3, 1, 2])
    for confidence in (0, 1):
        one('confidence-%d' % confidence, career, psychology, confidence)
    clamped = native('Kendall', {'data': select(sheet(['x', 'y'], [[1, 2, 3, 4, 5, 6, 7, 8], [1, 2, 3, 4, 5, 6, 8, 7]]), 0, 1), 'gamma': 95})
    check(num(clamped['values'], 'ul') == 1, 'the clamped case reaches the report\'s upper bound of tau')


# 3. Mann-Whitney: the report uses the normal approximation when both samples are above 100 or the exact distribution would
#    need more than a million cells, and K for the difference from the normal approximation when the exact distribution
#    of U would be too large; the replay always built the dense exact table (200 + 200 took 47 s and 3.2 GB).
def check_mann_whitney():
    # the report's line of the interval for the difference: the bag's list (conf) of pc, k, median, from and to
    interval = re.compile(r'([0-9.]+)% confidence interval for difference between medians or means: K = (\d+)( \(approx\))?\s+Median difference = '
                          + FIGURE + r' \(CI: ' + FIGURE + ' to ' + FIGURE + r'\)')

    def samples(x, y):
        rows = max(len(x), len(y))
        return select(sheet(['First sample', 'Second sample'], [list(x) + [''] * (rows - len(x)), list(y) + [''] * (rows - len(y))]), 0, 1)

    def one(label, x, y, confidence, normal, approximate, timeout=90):
        def body():
            check(len(set(x + y)) == len(x) + len(y) or label.startswith('ties') or label.startswith('confidence'), label + ': an untied case has no ties')
            run, record, used = confidence_run('MannWhitney', {'data': samples(x, y)}, 'gamma', confidence)
            b = run['values']
            check(str(b['stats']).startswith('Normalised statistic') == normal, label + ': the case exercises the report\'s ' + ('normal approximation' if normal else 'exact distribution'))
            found = interval.findall(ReportText(run['html']).text)
            check(len(found) == 1, label + ': the report gives its interval for the difference')
            pc, k, approx, median, low, high = found[0]
            check(bool(approx) == approximate, label + ': the case exercises the report\'s ' + ('approximate' if approximate else 'exact') + ' K')
            assertion = ('stopifnot(confidence == %r, K == %s)\n' % (used, k)
                         + equal('lower', [num(b, 'p_l')]) + equal('upper', [num(b, 'p_u')]) + equal('min(1, 2 * min(lower, upper))', [num(b, 'p_2')])
                         + equal('theta, ci', [num(b, key) for key in ('theta', 'tll', 'tul')], 1e-8)
                         + equal('median(d), d[K], rev(d)[K]', [float(median), float(low), float(high)], 1e-12))
            text = replay(record, assertion, label, timeout=timeout)
            coverage = re.search(r'^([0-9.]+)% confidence interval for the difference: K = (\d+)( \(approx\))?\s*$', text, re.M)
            check(coverage and abs(float(coverage.group(1)) - float(pc)) < .0051 and bool(coverage.group(3)) == approximate,
                  label + ': the coverage and K of the interval are printed as the report has them')
            check(('Normalised statistic' in text) == normal, label + ': the P values say whether they are exact or from the normal approximation')
        case('mann-whitney ' + label, body)

    def values(n, offset, ties):
        return [float(round(20 + 8 * math.sin(i * .7 + offset) + i * 7 % 5)) if ties else 20 + 8 * math.sin(i * .7 + offset) + i / 997.0 + offset / 1e5 for i in range(n)]

    one('ties-200-200', values(200, 0, True), values(200, 1.3, True), .95, normal=True, approximate=False)
    one('untied-200-200', values(200, 0, False), values(200, 1.3, False), .95, normal=True, approximate=False)
    one('ties-60-300', values(60, 0, True), values(300, 2.1, True), .9, normal=True, approximate=False)
    one('untied-exact-120-60', values(120, 0, False), values(60, .4, False), .95, normal=False, approximate=False)
    # inside the report's exact range, where the dense table of the rank sums would need over 5 GB
    one('untied-exact-100-2500', values(100, 0, False), values(2500, .9, False), .95, normal=False, approximate=True)
    one('untied-101-2000', values(101, 0, False), values(2000, .9, False), .9, normal=True, approximate=True)
    # with ties, a small first sample beside a large one is still inside the report's exact count
    one('ties-exact-20-1000', [float(round(20 + 8 * math.sin(i * 3.1) + i * 7 % 5)) for i in range(20)], values(1000, 1.7, True), .95, normal=False, approximate=False)
    farm = [14.8, 7.3, 5.6, 6.3, 9, 4.2, 10.6, 12.5, 12.9, 16.1, 11.4, 2.7]
    town = [12.7, 14.2, 12.6, 2.1, 17.7, 11.8, 16.9, 7.9, 16, 10.6, 5.6, 5.6, 7.6, 11.3, 8.3, 6.7, 3.6, 1, 2.4, 6.4, 9.1, 6.7, 18.6, 3.2, 6.2, 6.1, 15.3, 10.6, 1.8, 5.9, 9.9, 10.6, 14.8, 5, 2.6, 4]
    for confidence in (0, 1):
        one('confidence-%d' % confidence, farm, town, confidence, normal=False, approximate=False)
    # The report gives no interval for the difference, and says why, with fewer than 4 values in a sample or when even
    # the widest interval falls short of the confidence asked for (4 + 4 at 99%, K = 0); the replay printed an interval
    # for the first and a "100.00% ... K = 0" line for the second.
    for label, x, y, confidence in (('no-interval-3-6', [1.2, 3.4, 2.2], [4.4, 6.1, 5.5, 7.3, 8.8, 2.9], 95),
                                    ('no-interval-4-4-at-99', [1.2, 3.4, 2.2, 5.1], [4.4, 6.1, 5.5, 7.3], 99)):
        def body(label=label, x=x, y=y, confidence=confidence):
            run = native('MannWhitney', {'data': samples(x, y), 'gamma': confidence})
            b = run['values']
            # the bag has no list of the interval (conf) and one row saying why (noconf): the report's paragraph after theta's
            paragraphs = [ReportText(paragraph).text for paragraph in re.findall(r'<p>(.*?)</p>', run['html'], re.S)]
            theta = [i for i, paragraph in enumerate(paragraphs) if paragraph.startswith('Theta')]
            whole = ReportText(run['html']).text
            check(len(theta) == 1 and len(paragraphs) == theta[0] + 2 and not interval.search(whole) and 'K =' not in whole and 'Median difference' not in whole,
                  label + ': the report gives no interval for the difference')
            reason = paragraphs[-1]
            text = replay(json.loads(run['record']), equal('lower', [num(b, 'p_l')]) + equal('upper', [num(b, 'p_u')])
                          + equal('theta, ci', [num(b, key) for key in ('theta', 'tll', 'tul')], 1e-8), label)
            check(reason in text and 'confidence interval for the difference: K =' not in text and 'median difference =' not in text,
                  label + ': the replay gives no interval either, and says why as the report does (' + reason + ')')
        case('mann-whitney ' + label, body)


def printed(text, pattern, flags=re.M):
    """Printed539: the figures of the first place in the text that the pattern finds."""
    found = re.search(pattern, text, flags)
    return [float(group) for group in found.groups()] if found else []


def reported(run, pattern, count, label):
    """Figures the Windows check reads from a list of the output bag, read from the native report (12 decimal places)."""
    figures = printed(ReportText(run['html']).text, pattern)
    check(len(figures) == count, label + ': the native report gives its figures (' + pattern + ')')
    return figures


# 6. A confidence level typed as 100% (recorded 1) or 0% is taken as 95% by every one of these reports (XLevel); their
#    recipes replayed the typed level, halted (Mann-Whitney), or printed 0 to infinity. The Cox hazard ratios had no
#    fallback in the report either and printed a point interval labelled 100%.
def check_fallback():
    x = [8, 12, 15, 11, 19, 14, 9, 16, 21, 18, 13, 17]
    y = [9, 10, 13, 12, 17, 16, 14, 18, 22, 19, 15, 20]
    two = sheet(['First', 'Second'], [x, y])
    longer = [50 + 9 * math.sin(i * 1.3) + i * .37 for i in range(1, 31)]
    partner = [v + 4 * math.cos(i * .9) - .6 for i, v in enumerate(longer)]
    pairs = sheet(['Before', 'After'], [longer, partner])
    weights = [1.0 + i % 4 for i in range(1, 31)]
    weighted = sheet(['Value', 'Weight'], [longer, weights])
    used_95 = 'stopifnot(confidence == 0.95)\n'

    for confidence in (0, 1):
        level = str(confidence)

        def wilcoxon(confidence=confidence, label='Wilcoxon-' + level):
            run, record, _ = confidence_run('Wilcoxon', {'data': select(pairs, 0, 1)}, 'gamma', confidence)
            k, median, low, high = reported(run, r'95% confidence interval for difference between population medians: K = ([0-9]+)\s+Median difference = '
                                            + FIGURE + r' \(\s*' + FIGURE + ' to ' + FIGURE + r'\s*\)', 4, label)
            replay(record, used_95 + 'stopifnot(K == %d)\n' % k + equal('median(a), a[K], rev(a)[K]', [median, low, high]), label)
        case('fallback Wilcoxon ' + level, wilcoxon)

        def spearman(confidence=confidence, label='Spearman-' + level):
            run, record, _ = confidence_run('Spearman', {'data': select(two, 0, 1)}, 'gamma', confidence)
            limits = reported(run, r"95% CI for rho \(Fisher's Z transformed\) = " + FIGURE + ' to ' + FIGURE, 2, label)
            replay(record, used_95 + equal('ci', limits), label)
        case('fallback Spearman ' + level, spearman)

        def z_unpaired(confidence=confidence, label='ZUnpaired-' + level):
            run, record, _ = confidence_run('ZUnpaired', {'data': select(two, 0, 1)}, 'gamma', confidence)
            replay(record, used_95 + equal('d - qnorm((1 + confidence) / 2) * se, d + qnorm((1 + confidence) / 2) * se', [num(run['values'], 'from'), num(run['values'], 'to')]), label)
        case('fallback ZUnpaired ' + level, z_unpaired)

        def reference_range(confidence=confidence, label='ReferenceRange-' + level):
            run, record, _ = confidence_run('ReferenceRange', {'data': select(pairs, 0), 'reference-interval': 90, 'do_conservative': True}, 'gamma', confidence)
            check(record['parameters']['reference-interval'] == .9 and record['parameters']['do_conservative'] is True, label + ': the reference range is run as asked')
            b = run['values']
            text = replay(record, used_95, label)
            lower = printed(text, r'^95% confidence interval for lower range limit = ' + FIGURE + ' to ' + FIGURE)
            upper = printed(text, r'^95% confidence interval for upper range limit = ' + FIGURE + ' to ' + FIGURE)
            check(len(lower) == 2 and len(upper) == 2 and all(abs(got - num(b, key)) <= 5.1e-7 for got, key in zip(lower + upper, ('lx_l', 'ux_l', 'lx_u', 'ux_u'))),
                  'ReferenceRange at a recorded ' + level + ': the replay gives the report\'s 95% limits of the range limits')
        case('fallback ReferenceRange ' + level, reference_range)

        def quantile(confidence=confidence, label='Quantile-' + level):
            run, record, _ = confidence_run('Quantile', {'data': select(pairs, 0), 'conservative-ci': False, 'quantile': .5}, 'gamma', confidence)
            check(record['parameters']['conservative-ci'] is False and record['parameters']['quantile'] == .5, label + ': the quantile is run as asked')
            limits = reported(run, r'Approximate 95% CI \([^)]*\) = ' + FIGURE + ' to ' + FIGURE, 2, label)
            text = replay(record, 'stopifnot(conf == 0.95)\n', label)
            got = printed(text, r'^Approximate 95% CI \([^)]*\) = ' + FIGURE + ' to ' + FIGURE)
            check(len(got) == 2 and abs(got[0] - limits[0]) <= 5.1e-6 * abs(got[0]) and abs(got[1] - limits[1]) <= 5.1e-6 * abs(got[1]),
                  'Quantile at a recorded ' + level + ': the replay gives the report\'s 95% interval')
        case('fallback Quantile ' + level, quantile)

        def quick_summary(confidence=confidence, label='QuickSummary-' + level):
            # The quick summary is shown in a dialog rather than the report and leaves no record, so its record is written
            # here by hand, as the Windows check writes one: the frame the host records for this selection (taken from the
            # record of another analysis of the same selection) under the quick summary's prompt, and the recorded level.
            run = native('QuickSummary', {'data': select(pairs, 0), 'gamma': 95})
            sibling = json.loads(native('Quantile', {'data': select(pairs, 0), 'gamma': 95})['record'])
            frames = [entry for entry in sibling['inputs'] if entry['kind'] == 'frame']
            check(len(frames) == 1 and frames[0]['name'] == 'data' and list(sibling['data']) == ['data'], label + ': the host records the selection of the one column')
            record = {'version': sibling['version'], 'operation': 'QuickSummary', 'rootOperation': 'QuickSummary', 'title': 'Quick summary', 'run': sibling['run'], 'source': sibling['source'],
                      'inputs': [dict(frames[0], prompt='Select data for quick summary'), {'name': 'gamma', 'prompt': 'gamma', 'kind': 'confidence', 'value': confidence}],
                      'parameters': {'gamma': confidence}, 'values': {}, 'data': sibling['data']}
            summary = ReportText(run['html']).text
            text = replay(record, used_95, label)
            native_upper, native_lower = printed(summary, r'95% Upper CL of mean\s+' + FIGURE), printed(summary, r'95% Lower CL of mean\s+' + FIGURE)
            replay_upper, replay_lower = printed(text, r'^95% Upper CL of mean ' + FIGURE), printed(text, r'^95% Lower CL of mean ' + FIGURE)
            check(len(native_upper) == 1 and len(native_lower) == 1 and len(replay_upper) == 1 and len(replay_lower) == 1
                  and abs(native_upper[0] - replay_upper[0]) <= 5.1e-7 and abs(native_lower[0] - replay_lower[0]) <= 5.1e-7,
                  'QuickSummary at a recorded ' + level + ': the replay gives the report\'s 95% limits of the mean')
        case('fallback QuickSummary ' + level, quick_summary)

        def gini(confidence=confidence, label='Gini-' + level):
            run, record, _ = confidence_run('Gini', {'data': select(pairs, 0), 'boots': 200, 'seed': 7}, 'gamma', confidence)
            check(record['parameters']['boots'] == 200 and record['parameters']['seed'] == 7, label + ': the bootstrap is run as asked')
            report = ReportText(run['html']).text
            check(report.count('Percentile 95% CI') == 2 and report.count('BCa 95% CI') == 2 and '100%' not in report, 'the native Gini report takes ' + level + ' as 95%')
            text = replay(record, used_95, label)
            check('100%' not in text and not re.search(r'(^|\s)0% ', text), 'Gini at a recorded ' + level + ': the replay labels its intervals 95%')
        case('fallback Gini ' + level, gini)

        def crossover(confidence=confidence, label='Crossover-' + level):
            d1 = [8, 14, 8, 9, 11, 3, 6, 0, 13, 10, 7, 13, 8, 7]
            p1 = [5, 10, 0, 7, 6, 5, 0, 0, 12, 2, 5, 13, 10, 7]
            d2 = [12, 6, 13, 8, 8, 4, 8, 2, 8, 9, 7, 7, 10]
            p2 = [11, 8, 9, 8, 9, 8, 14, 4, 13, 7, 10, 6, 7]
            # the Windows selection is of 15 rows (the heading and 14), so the second group's columns end with an empty cell
            cells = sheet(['Drug 1', 'Placebo 1', 'Drug 2', 'Placebo 2'], [d1, p1, d2 + [''], p2 + ['']])
            run, record, _ = confidence_run('Crossover', {'group1drug': select(cells, 0), 'group1placebo': select(cells, 1), 'group2drug': select(cells, 2), 'group2placebo': select(cells, 3)}, 'gamma', confidence)
            b = run['values']
            text = replay(record, used_95, label)
            effect = printed(text, r'^effect magnitude = ' + FIGURE + ' 95% CI = ' + FIGURE + ' to ' + FIGURE)
            check(len(effect) == 3 and abs(effect[1] - num(b, 'treatment_from')) <= 5.1e-7 and abs(effect[2] - num(b, 'treatment_to')) <= 5.1e-7,
                  'Crossover at a recorded ' + level + ': the replay gives the report\'s 95% interval of the treatment effect')
        case('fallback Crossover ' + level, crossover)

        def nonparametric(confidence=confidence, label='NonparametricLinearRegression-' + level):
            run, record, _ = confidence_run('NonparametricLinearRegression', {'outcome': select(pairs, 1), 'predictor': select(pairs, 0)}, 'gamma', confidence)
            _, low, high = reported(run, r'Median slope \( 95% CI \) = ' + FIGURE + r' \(\s*' + FIGURE + ' to ' + FIGURE + r'\s*\)', 3, label)
            replay(record, used_95 + equal('np_result$lower, np_result$upper', [low, high]), label)
        case('fallback NonparametricLinearRegression ' + level, nonparametric)

        def t_single(confidence=confidence, label='TSingleSummary-' + level):
            run, record, _ = confidence_run('TSingleSummary', {'nx': 20, 'mu': 130.05, 'sd1': 9.79, 'mu0': 120.0}, 'gamma', confidence)
            replay(record, used_95 + equal('r$conf.int - mu0', [num(run['values'], 'from'), num(run['values'], 'to')]), label)
        case('fallback TSingleSummary ' + level, t_single)

        def t_unpaired(confidence=confidence, label='TUnpairedSummary-' + level):
            run, record, _ = confidence_run('TUnpairedSummary', {'nx1': 12, 'um1': 120.0, 'sd1': 21.6, 'nx2': 7, 'um2': 101.0, 'sd2': 18.3}, 'gamma', confidence)
            replay(record, used_95 + equal('equal$conf.int', [num(run['values'], 'from'), num(run['values'], 'to')]), label)
        case('fallback TUnpairedSummary ' + level, t_unpaired)

        def weighted_summary(confidence=confidence, label='WeightedUnivariateSummary-' + level):
            # the two centiles are typed as percentages on the Mac (5 and 95) and recorded as Windows records them (.05 and .95)
            run, record, _ = confidence_run('WeightedUnivariateSummary', {'data': select(weighted, 0), 'weights': select(weighted, 1), 'report-centile-type': '1',
                                                                          'report-udca': 5, 'report-udcb': 95, 'output-to-frame': False}, 'gamma', confidence)
            asked = record['parameters']
            check(asked['report-centile-type'] == '1' and asked['report-udca'] == .05 and asked['report-udcb'] == .95 and asked['output-to-frame'] is False, label + ': the summary is run as asked')
            report = ReportText(run['html'])
            text = replay(record, used_95, label)
            limits = printed(text, r'^Upper 95% CL of mean ' + FIGURE + r'\s+Lower 95% CL of mean ' + FIGURE)
            check(len(limits) == 2 and abs(limits[0] - figure(report, 'Upper 95% CL of mean')) <= 5.1e-7 and abs(limits[1] - figure(report, 'Lower 95% CL of mean')) <= 5.1e-7,
                  'WeightedUnivariateSummary at a recorded ' + level + ': the replay gives the report\'s 95% limits of the mean')
        case('fallback WeightedUnivariateSummary ' + level, weighted_summary)

        def time_series(confidence=confidence, label='TimeSeriesSummary-' + level):
            times = [0, 1, 2, 4, 0, 1, 2, 4, 0, 1, 2, 4, 0, 1, 2, 4]
            levels = [0, 3.1, 4.2, 2.0, 0, 2.6, 3.9, 2.4, 0, 3.8, 5.1, 2.2, 0, 2.2, 3.3, 1.7]
            series = sheet(['Time', 'Level', 'Patient'], [times, levels, ['P%d' % (i // 4 + 1) for i in range(16)]])
            run, record, _ = confidence_run('TimeSeriesSummary', {'times': select(series, 0), 'observations': select(series, 1), 'subjectIds': select(series, 2),
                                                                  'addZeroObservationAtZeroTime': False, 'doExactP': False, 'iterations': 1000, 'seed': 1}, 'ci', confidence)
            check(record['parameters']['doExactP'] is False and num(run['values'], 'ciOutput') == 95, 'the native time series summary takes ' + level + ' as 95%')
            low, high = reported(run, r'95% t-interval for mean AUC: ' + FIGURE + ' to ' + FIGURE, 2, label)
            text = replay(record, used_95, label)
            auc = printed(text, r'^95% t-interval for mean AUC: ' + FIGURE + ' to ' + FIGURE)
            check(len(auc) == 2 and abs(auc[0] - low) <= .0051 and abs(auc[1] - high) <= .0051,
                  'TimeSeriesSummary at a recorded ' + level + ': the replay gives the report\'s 95% t-interval of the mean AUC')
        case('fallback TimeSeriesSummary ' + level, time_series)

    # The Cox hazard ratios: the report now takes 0% or 100% as 95%, as its other reports do; R's coxph limits at 95%
    # are the independent reference for the native limits at a recorded 100%.
    cox_times = [6, 6, 6, 7, 10, 13, 16, 22, 23, 6, 9, 10, 11, 17, 19, 20, 25, 32, 32, 34, 35, 1, 1, 2, 2, 3, 4, 4, 5, 5, 8, 8, 8, 8, 11, 11, 12, 12, 15, 17, 22, 23]
    cox_events = [0.0 if i % 5 == 4 else 1.0 for i in range(len(cox_times))]
    cox_group = [1.0 if i < 21 else 0.0 for i in range(len(cox_times))]
    cox = sheet(['Time', 'Event', 'Treated'], [cox_times, cox_events, cox_group])
    fit = native('CoxRegression', {'times': select(cox, 0), 'events': select(cox, 1), 'predictors': select(cox, 2), 'accuracy': 1e-9, 'centre-continuous-covariates': True}, keep=True)
    try:
        fitted = json.loads(fit['record'])['parameters']
        check(fitted['accuracy'] == 1e-9 and fitted['centre-continuous-covariates'] is True, 'the Cox regression is fitted as asked')
        hazard = r'Treated ' + FIGURE + ' ' + FIGURE + ' to ' + FIGURE
        reference = reported(native('CoxHazardRatios', {'gamma': 95}, parent=fit['id']), hazard, 3, 'CoxHazardRatios at 95%')
        for confidence in (0, 1, .9):
            level = str(confidence)

            def ratios(confidence=confidence, level=level, label='CoxHazardRatios-' + level):
                run, record, used = confidence_run('CoxHazardRatios', {}, 'gamma', confidence, parent=fit['id'])
                figures = reported(run, hazard, 3, label)
                check(num(run['values'], 'pc2') == used * 100 and (used != .95 or figures == reference),
                      'the native Cox hazard ratios at a recorded %s use %g%%' % (level, used * 100))
                text = replay(record, 'stopifnot(confidence == %r)\n' % used
                              + equal('exp(coef(fit)), exp(coef(fit) - qnorm((1 + confidence) / 2) * sqrt(diag(vcov(fit)))), exp(coef(fit) + qnorm((1 + confidence) / 2) * sqrt(diag(vcov(fit))))', figures, 1e-6),
                              label, setup='pdf(NULL)\n')
                check(' %g%% CI =' % (used * 100) in text, 'the replayed Cox hazard ratios are labelled %g%%' % (used * 100))
            case('fallback CoxHazardRatios ' + level, ratios)
    finally:
        SESSION.close(fit['id'])


MISSING = -1.7976931348623157e308   # Constant.MISSING, the engine's value for a figure it cannot give


# 5. Agreement: Kendall's tau of the subjects' SDs against their means is undefined when every subject has the same SD
#    (or mean), which stopped the replay; above 1,000 untied subjects the report's P is its Edgeworth series (kendp).
def check_agreement():
    def one(label, raters, confidence=95, timeout=120):
        def body():
            cells = sheet(['Rater %d' % (i + 1) for i in range(len(raters))], raters)
            run = native('Agreement', {'data': select(cells, *range(len(raters))), 'ci': confidence})
            record = json.loads(run['record'])
            check(record['parameters']['ci'] == confidence / 100, label + ': the confidence asked for is the confidence recorded')
            b = run['values']
            undefined = num(b, 'tau') == MISSING
            assertion = equal('sqrt(2) * qnorm((1 + confidence) / 2) * sw, sw', [num(b, 'rep'), num(b, 'wssd')], 1e-8) + (
                'stopifnot(is.na(kt$estimate), is.na(kt$p.value))\n' if undefined else equal('kt$estimate', [num(b, 'tau')]) + equal('kt$p.value', [num(b, 'p2')], 1e-12))
            text = replay(record, assertion, label, setup='pdf(NULL)\n', timeout=timeout)
            if undefined:
                check(re.search(r"Kendall's tau b = \*\s+two sided P = \*", text), label + ': tau and its P are shown as undefined, as the report shows them')
            repeatability = re.search(r'Repeatability \(for alpha = [0-9.]+\) = ' + FIGURE, text)
            check(repeatability and abs(float(repeatability.group(1)) - num(b, 'rep')) <= 5.1e-7, label + ': the repeatability line is printed')
        case('agreement ' + label, body)

    first = [12, 15, 9, 20, 17, 11, 14, 18, 10, 16]
    one('perfect-agreement', [first, list(first)])
    one('constant-offset', [first, [v + 2 for v in first]])
    one('three-offsets', [first, [v + 1 for v in first], [v + 2 for v in first]], 90)
    for n, share in ((1001, .4925), (1001, .495), (1100, .497), (1500, .499)):
        d = permutation(n, int(n * (n - 1) // 2 * share))
        mean = [1000.0 + 10 * i for i in range(n)]
        one('untied-%d-%s' % (n, share), [[m + d[i] for i, m in enumerate(mean)], [m - d[i] for i, m in enumerate(mean)]], timeout=240)
    tied = [500.0 + 3 * i for i in range(1200)]
    one('tied-1200', [[m + 1 + i % 37 for i, m in enumerate(tied)], [m - 1 - i % 37 for i, m in enumerate(tied)]], timeout=240)


# 7. Paired t: R's t.test refuses differences whose standard error is below 10 eps times their mean ("data are essentially
#    constant"), such as decimal data with a constant shift, where the report still gives t, P and the interval.
def check_paired():
    for shift in (.1, .3, 1.1):
        for paired in (True, False):
            for agreement in ((False, True) if paired else (False,)):
                def body(shift=shift, paired=paired, agreement=agreement):
                    # typed decimals, as in a worksheet: 5.1, 6.2 ... and 5.1 - shift, 6.2 - shift ... each the double nearest its decimal
                    first = [round(5.1 + 1.1 * i, 10) for i in range(6)]
                    second = [round(v - shift, 10) for v in first]
                    cells = sheet(['First', 'Second'], [first, second]) if paired else sheet(['Differences'], [[v - second[i] for i, v in enumerate(first)]])
                    run = native('TPaired', {'data': select(cells, 0, 1) if paired else select(cells, 0), 'gamma': 95, 'doAgreement': agreement})
                    b = run['values']
                    check(num(b, 'sd') > 0, 'the shift of %s leaves differences that are not exactly constant' % shift)
                    assertion = (equal('n, mean(d), sd(d), r$parameter', [num(b, k) for k in ('n', 'mean', 'sd', 'df')], 1e-12)
                                 + equal('r$statistic', [num(b, 't')], 1e-6) + equal('r$p.value', [num(b, 'tail_2')], 1e-5)
                                 + equal('r$conf.int', [num(b, 'from'), num(b, 'to')], 1e-12))
                    replay(json.loads(run['record']), assertion, 'shift-%s-%s-%s' % (shift, paired, agreement), setup='pdf(NULL)\n')
                case('paired shift %s %s %s' % (shift, paired, agreement), body)


# 8. PCA: worksheet titles that repeat are kept apart in the record by held keys ("dup", "dup_2"); the replay printed the
#    key where the report prints the title in the line of reversed items.
def check_pca():
    items = [[1.2, .4, -.3, 2.1, .8, -1, .2, 1.5, -.6, .9, .1, -.2], [-1, -.7, .1, -1.8, -.6, 1.3, -.5, -1.2, .4, -1.1, .2, 0],
             [1.5, .2, -.6, 2.4, .6, -.8, 0, 1.9, -.9, .6, .3, -.5], [.9, .5, .1, 1.7, 1, -1.1, .4, 1.4, -.3, 1.2, 0, .1],
             [-.8, -.6, .2, -1.6, -1.1, .9, -.2, -1.3, .5, -.7, -.1, .3]]
    for titles in (['A', 'dup', 'C', 'D', 'dup'], ['Same', 'Same', 'Same', 'Other', 'Same']):
        for operation in ('PCRCorrelation', 'PCRCovariance', 'PCRCovarianceNoFollowOns'):
            def body(titles=titles, operation=operation):
                cells = sheet(titles, items)
                answers = {'data': select(cells, 0, 1, 2, 3, 4), 'correctForReversal': True}
                if operation != 'PCRCorrelation':
                    answers['ci'] = 95
                run = native(operation, answers, keep=True)
                try:
                    # the line of reversed items, which Windows reads from the bag (warn) and the Mac from the native report
                    warned = re.findall(r'<p>(Sign was reversed for:[^<]*)</p>', run['html'])
                    check(len(warned) == 1 and '&' not in warned[0], operation + ': the native report reverses items')
                    reversed_items = warned[0]
                    label = operation + '-' + '-'.join(dict.fromkeys(titles))
                    names = 'stopifnot(identical(names(q), ' + strings(titles) + '))\n'
                    text = replay(json.loads(run['record']), names, label)
                    check(reversed_items in text, label + ': the replay names the reversed items by their worksheet titles, as the report does')
                    if operation != 'PCRCovariance':
                        return
                    follow = native('Cronbach', {'ci': 90}, parent=run['id'])
                    text = replay(json.loads(follow['record']), names, label + '-cronbach')
                    check(reversed_items in text, label + ': the reliability follow-on keeps the worksheet titles')
                finally:
                    SESSION.close(run['id'])
            case('pca ' + operation + ' ' + '-'.join(titles), body)


CHECKS = {'gof': check_gof, 'kendall': check_kendall, 'mann-whitney': check_mann_whitney, 'routing': check_routing, 'agreement': check_agreement, 'fallback': check_fallback, 'paired': check_paired, 'pca': check_pca, 'k2': check_k2}

if __name__ == '__main__':
    if ONLY is not None and ONLY not in PARTS:
        raise SystemExit('Unknown 5.3.9 recipe check: ' + ONLY)
    started = time.time()
    SESSION = Session()
    WRITER = Writer()
    try:
        for part in PARTS:
            if part in CHECKS and ONLY in (None, part):
                CHECKS[part]()
    except Failure as error:
        print(str(error), file=sys.stderr, flush=True)
        raise SystemExit(1)
    finally:
        SESSION.finish()
        WRITER.close()
    if FAILED:
        print('FAIL ' + str(len(FAILED)) + ' of the 5.3.9 recipe cases: ' + ' | '.join(FAILED), file=sys.stderr)
        raise SystemExit(1)
    print('PASS: %d cases of the 5.3.9 recipe review reproduce the native reports in R (%s) in %.0f s' % (
        len(PASSED), ', '.join(part for part in PARTS if part in CHECKS and ONLY in (None, part)), time.time() - started))
