#!/usr/bin/env python3
"""Representative Windows 5.3.10 fixes through the Mac host and real R.

The polynomial, kappa and incidence-rate fixtures come from Models5310.cs,
Recipes5310.cs, KappaRaters5310.cs and MetaReview5310.cs. The Mac report
exposes scalars and rendered HTML, while the Windows tests inspect its bags.
This suite tests the packaged engine too when STATSDIRECT_TEST_ENGINE is set.
"""

import json
import math
import re
import struct

from test_combined_forms import Forms, run as run_form
from test_menu import Session
from test_padded_record_reread import notebook_code
from test_pr6_replay import sheet
from test_recipes_539 import PREFS, Writer, equal, figure, num, run_r, select
from test_shared_engine_update import ReportText


def replay(writer, run):
    record = json.loads(run['record'])
    script = writer.write(record)
    assert script.get('hasRecipe') and not script.get('dataUnavailable') and not script.get('relocate'), {
        key: value for key, value in script.items() if key != 'text'
    }
    assert 'has changed in the workbook' not in script['text']
    return record, script['text']


def exact_replay(session, writer):
    # These shortest decimals include values that R on Apple Silicon rounded
    # by one unit in the last place when read from the old generated script.
    differences = [0.10000000000000053, 0.09999999999999964,
                   1.1000000000000005, 1.0999999999999996, 0.2, 0.3]
    run = session.run('TPaired', {'data': sheet(['Differences'], [differences]),
                                  'gamma': 95, 'doAgreement': False}, PREFS)
    record, script = replay(writer, run)
    expected = struct.pack('<' + 'd' * len(differences), *differences).hex()
    probe = ('\ncat("REPLAY_BITS:", paste(as.character(writeBin(as.double(d), raw(), '
             'size=8, endian="little")), collapse=""), "\\n", sep="")\n')

    def compare_bits(code, label):
        printed = run_r('pdf(NULL)\n' + code, label, 60)
        actual = re.findall(r'^REPLAY_BITS:([0-9a-f]+)$', printed, re.M)
        assert actual == [expected], (label, actual, expected)
        assert re.search(r'^\s*before <- c\([^\n]*0x[0-9a-f.]+p[-+]?\d+', code, re.M | re.I), label
        assert re.search(r'^\s*# before <- c\([^\n]*0\.10000000000000053', code, re.M), label
        print('PASS: ' + label + ' preserves every input bit and shows the decimal comment', flush=True)

    compare_bits(script + probe, 'Continue in R')
    title = 'Exact paired differences'
    snapshot = {'version': 1, 'engineVersion': '5.3.10', 'reportHtml': run['html'],
                'entries': [{'id': 'exact-paired', 'title': title, 'operation': 'TPaired',
                             'html': run['html'], 'cells': [], 'record': record}]}
    code = notebook_code(writer.call({'notebook': snapshot, 'title': title, 'appVersion': '1.1.1', 'frames': []}))
    body, closing, tail = code.rpartition('\n})')
    assert closing and not tail.strip(), code[-300:]
    # Inspect the vector inside the exported cell's own local scope.
    compare_bits(body + probe + closing + tail, 'Jupyter notebook R cell')


def polynomial(session, writer):
    cells = sheet(['Y', 'X'], [[3, 1, 7], [1, 2, 4]])
    answers = {'y': select(cells, 0), 'x': select(cells, 1)}
    run = session.run('PolynomialRegression', {**answers, 'degree': '2'}, PREFS, keep=True)
    try:
        assert 'saturated model' in run['html'].lower() and 'SVD' not in run['html'], run['html'][:1500]
        _, script = replay(writer, run)
        code = equal('coef(fit)', [25 / 3, -7, 5 / 3], 1e-10) + 'stopifnot(fit$df.residual == 0)\n'
        output = run_r('pdf(NULL)\n' + script + '\n' + code, 'saturated polynomial', 60)
        assert output.count('t = *  P = *') == 3 and 'Root MSE = *' in output, output[-1500:]
        area = session.run('PolynomialAreaUnderCurve', answers, PREFS, parent=run['id'])
        assert math.isclose(num(area['values'], 'poly_auc'), 7.5, abs_tol=1e-10), area['values']
        assert math.isclose(num(area['values'], 'trap_auc'), 10, abs_tol=1e-10), area['values']
    finally:
        session.close(run['id'])
    print('PASS: saturated quadratic retains its exact fit, R replay and native area follow-on', flush=True)


def kappa(session, writer):
    cells = sheet(['First', 'Second'], [[1, 2, 3, 2, 1, 3], [2, 2, 3, 1, 1, 3]])
    run = session.run('Kappa', {'responses': cells, 'ci': 95, 'method': '1'}, PREFS)
    _, script = replay(writer, run)
    assert num(run['values'], 'x2') == 0 and num(run['values'], 'df') == 1, run['values']
    output = run_r(script + '\nstopifnot(x2 == 0)\n', 'disconnected Maxwell grades', 60)
    assert re.search(r'Marginal homogeneity \(Maxwell\) chi-square = 0\s+df = 1\b', output), output[-1200:]
    print('PASS: two-rater kappa replays Maxwell on connected grades when the full covariance is singular', flush=True)

    columns = [[1, 1, 2, 2, 1, 2, 1, 1, 2, 1, 2, 2, 1, 2],
               [1, 2, 2, 2, 1, 1, 1, 2, 2, 1, 2, 1, 1, 2],
               [1, 1, 2, 1, 1, 2, 2, 1, 2, 1, 2, 2, 2, 2]]
    cells = sheet(['Rater 1', 'Rater 2', 'Rater 3'], columns)
    run = session.run('Kappa', {'responses': cells, 'ci': 95}, PREFS)
    _, script = replay(writer, run)
    # Fleiss–Cuzick's published formula using x ratings in a category out of m.
    counts = [sum(v == 2 for v in ratings) for ratings in zip(*columns)]
    n, m = len(counts), len(columns)
    proportion = sum(counts) / (n * m)
    expected = 1 - sum(x * (m - x) / m for x in counts) / (n * (m - 1) * proportion * (1 - proportion))
    assert math.isclose(num(run['values'], 'k'), expected, abs_tol=1e-12), run['values']
    output = run_r(script + '\n' + equal('kappa', [expected], 1e-12), 'three-rater kappa', 60)
    assert 'General agreement over all (2) categories with 3 raters per subject' in output, output[-1200:]
    print('PASS: three-rater kappa uses all ratings and matches the published formula in the report and R', flush=True)

    table = [[9, 3, 1, 0], [2, 8, 4, 1], [0, 5, 7, 2], [1, 0, 3, 6]]
    titles = [f'Grade {grade}' for grade in 'ABCD']
    form = Forms()
    try:
        run, form_count = run_form(form, 'KappaScreen', {
            'responsesCrosstab': sheet(titles, list(zip(*table))),
            'ci': 95, 'method': '1', 'doExactP': True, 'iterations': 1000, 'seed': 1,
        })
    finally:
        form.finish()
    assert form_count and '95% CI:' in run['html'] and '95% confidence interval' in run['html'], run['html'][-1200:]
    record, script = replay(writer, run)
    expected_kappa = num(run['values'], 'kappa')
    check = equal('kappa', [expected_kappa], 1e-8) + 'stopifnot(sum(counts) == 52, confidence == .95)\n'
    run_r(script + '\n' + check, 'typed kappa table', 60)

    # Older saved standalone simulations can carry the typed parent frame.
    record['operation'] = 'KappaSimulateExactP'
    record['rootOperation'] = 'KappaScreen'
    record['parameters']['ci'] = .99
    for legacy in (False, True):
        if legacy:
            record.pop('rootOperation')
        script = writer.write(record)
        assert script['hasRecipe'] and not script['dataUnavailable']
        run_r(script['text'] + '\n' + check, f'typed kappa saved simulation (legacy={legacy})', 60)
    print('PASS: typed kappa tables replay with their original confidence level, including legacy simulation records', flush=True)


def incidence_meta(session, writer):
    names = ['pt1', 'a', 'pt2', 'b']
    pt1, a, pt2, b = [300, 410, 520], [0, 5, 9], [310, 400, 505], [4, 3, 7]
    cells = sheet(names + ['Age band'], [pt1, a, pt2, b, ['A', '', 'C']])
    answers = {name: select(cells, i) for i, name in enumerate(names)}
    answers.update(gamma=90, strata=select(cells, 4))
    prefs = {**PREFS, 'meta-cc': .01, 'meta-exact': False, 'meta-delay': False}
    run = session.run('MetaIncidenceRateDifference', answers, prefs)
    record, script = replay(writer, run)
    assert record['parameters']['metaCC'] == .01 and record['parameters']['metaExact'] is False, record['parameters']
    # Only the first stratum has a zero event count, and its correction
    # belongs in the variance rather than the observed rate difference.
    variance = [.01 / 300**2 + 4.01 / 310**2,
                5 / 410**2 + 3 / 400**2, 9 / 520**2 + 7 / 505**2]
    estimates = [av / ta - bv / tb for ta, av, tb, bv in zip(pt1, a, pt2, b)]
    pooled = sum(x / v for x, v in zip(estimates, variance)) / sum(1 / v for v in variance)
    code = (equal('v_ird', variance, 1e-12) + equal('res$fixed', [pooled], 1e-12) +
            'stopifnot(identical(strata, c("A", "stratum 2", "C")), !exact_meta, continuity == .01)\n')
    run_r('pdf(NULL)\n' + script + '\n' + code, 'incidence-rate difference meta-analysis', 60)
    print('PASS: incidence-rate replay keeps the selected correction, eligible estimates and fallback label', flush=True)


def royston(session, writer):
    # n=800 puts the adjusted deviate just above 30, where the older truncated
    # asymptotic expansion differs from R's independent log-tail evaluation.
    n = 800
    values = [400 + i % 13 if i % 97 == 0 else 10 + math.sin(i * .37) + i % 7 * .1
              for i in range(1, n + 1)]
    run = session.run('Normality', {'data': sheet(['Skewed'], [values])}, PREFS)
    _, script = replay(writer, run)
    k2 = figure(ReportText(run['html']), 'Royston chi-sq')
    code = f'\nstopifnot(n == {n}, zr > 30, zr < 32, abs(-2 * pnorm(-zr, log.p=TRUE) - {k2!r}) < 5e-10)\n'
    run_r('pdf(NULL)\n' + script + code, 'Royston large-deviate log tail', 60)
    print('PASS: the large-deviate native Royston tail agrees with log-scale R to 5e-10 in K2', flush=True)


if __name__ == '__main__':
    session = Session()
    writer = Writer()
    try:
        for test in (exact_replay, polynomial, kappa, incidence_meta, royston):
            test(session, writer)
    finally:
        session.finish()
        writer.close()
