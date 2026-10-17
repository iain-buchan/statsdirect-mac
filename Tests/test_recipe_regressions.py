"""Real Mac selections and follow-ons survive saved-record R replay.

Use small, unrelated datasets and more than one confidence level. Numerical
expectations come from the native calculation or an independent R fit, never
from the example a recipe was originally written around.
"""
import html
import json
import math
import os
import re
import subprocess
import tempfile
from pathlib import Path

from test_menu import ROOT, Session
from r_runtime import rscript


def columns(*items):
    return {'source': 'Selected regression checks', 'columns': [
        {'title': title, 'values': values} for title, values in items]}


def plain(result):
    return html.unescape(re.sub('<[^>]*>', ' ', result['html']))


def numbers(text):
    return [float(v) for v in re.findall(r'[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?', text)]


def near(actual, expected, label, tolerance=2e-6):
    assert len(actual) == len(expected), (label, actual, expected)
    assert all(math.isclose(a, b, rel_tol=tolerance, abs_tol=tolerance)
               for a, b in zip(actual, expected)), (label, actual, expected)


session = Session()
writer = subprocess.Popen([str(ROOT/'Tests/engine-driver'),
    os.environ.get('STATSDIRECT_TEST_ENGINE', str(ROOT/'FullEngine/publish/StatsDirectEngine.dylib')),
    'statsdirect_r_script'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
work = Path(tempfile.mkdtemp(prefix='recipe-regressions-', dir=ROOT/'.build'))
count = 0


def replay(label, result, assertions=''):
    global count
    record = json.loads(result['record'])
    # A JSON round trip represents closing/reopening the report before Continue in R.
    writer.stdin.write(json.dumps({'record': json.loads(json.dumps(record)), 'frames': []}) + '\n')
    writer.stdin.flush()
    reply = json.loads(writer.stdout.readline())
    assert reply.get('hasRecipe') and not reply.get('dataUnavailable'), (label, reply)
    script = reply['text']
    path = work/(label+'.R')
    path.write_text('.test_pages <- 0L\ninvisible(trace("plot.new",tracer=quote(.test_pages <<- .test_pages+1L),print=FALSE,where=asNamespace("graphics")))\n' +
                    'options(device=function(...) grDevices::pdf("'+label+'.pdf", ...))\n' +
                    script + '\n' + assertions + '\n')
    run = subprocess.run([rscript(), '--vanilla', str(path)], cwd=work,
                         text=True, capture_output=True, timeout=60)
    (work/(label+'.txt')).write_text(run.stdout + run.stderr)
    assert run.returncode == 0, (label, run.stdout, run.stderr)
    count += 1
    return run.stdout


def run(operation, answers, parent=None, keep=False):
    return session.run(operation, answers, preferences={'use-default-ci': False}, parent=parent, keep=keep)


try:
    for operation, link in [('Probit', 'probit'), ('Logit', 'logit')]:
        for confidence in (80, 99):
            for logged in (False, True):
                dose = [1, 2, 4, 8, 16] if logged else [1, 2, 3, 4, 5]
                answers = {'dose': columns(('Dose', dose)), 'subjects': columns(('Subjects', [20]*5)),
                           'responders': columns(('Responders', [2, 5, 10, 15, 19])), 'nc': 0,
                           'calc-log10-doses': logged, 'conf': confidence, 'qld': 80}
                result = run(operation, answers, keep=True)
                record = json.loads(result['record'])
                assert record['parameters']['conf'] == confidence/100
                assert record['rootOperation'] == operation and record['parameters']['doseResponseModel'] == link
                label = f'{operation}-{confidence}-{logged}'
                # glm's logit coefficients are twice Finney's convention used by StatsDirect.
                scale = 2 if link == 'logit' else 1
                assertion = f'''stopifnot(fit$family$link == "{link}")
stopifnot(max(abs(unname(coef(fit))/{scale} - c({result['values']['a']},{result['values']['b']}))) < 2e-6)
'''
                # Independently solve the Fieller quadratic from glm's covariance;
                # this verifies the native reference as well as the printed recipe.
                assertion += f'''test_b <- coef(fit); test_v <- vcov(fit); test_z <- qnorm((1+{confidence/100})/2)
test_q <- fit$family$linkfun(.5)
test_ci <- sort(Re(polyroot(c((test_b[1]-test_q)^2-test_z^2*test_v[1,1],
    2*(test_b[1]-test_q)*test_b[2]-2*test_z^2*test_v[1,2],test_b[2]^2-test_z^2*test_v[2,2]))))
'''
                if logged: assertion += 'test_ci <- 10^test_ci\n'
                assertion += f'stopifnot(max(abs(test_ci-c({result["values"]["from"]},{result["values"]["to"]}))) < 2e-6)\n'
                output = replay(label, result, assertion)
                intervals = re.findall(r'Confidence interval \(No Heterogeneity\)\s*=\s*([^\n]+)', output)
                assert len(intervals) == 2, (label, output)
                near(numbers(intervals[0]), [result['values'][k] for k in ('from', 'to')], label+' median CI')
                near(numbers(intervals[1]), [result['values'][k] for k in ('from_cent', 'to_cent')], label+' centile CI')
                # The same follow-on has two valid parents; both must preserve the fitted link.
                if confidence == 99:
                    for child, settings in [('ProbitMore', {}), ('ProbitPlot', {}),
                                            ('ProbitInterpolateX', {'newx': 3}), ('ProbitInterpolateY', {'newy': .65})]:
                        follow = run(child, settings, parent=result['id'])
                        follow_record = json.loads(follow['record'])
                        assert follow_record['rootOperation'] == operation and follow_record['parameters']['doseResponseModel'] == link
                        check = assertion
                        if child == 'ProbitInterpolateX':
                            x = math.log10(3) if logged else 3
                            check += f'stopifnot(abs(fit$family$linkinv(sum(coef(fit)*c(1,{x}))) - {follow["values"]["resp"]}) < 2e-6)\n'
                        elif child == 'ProbitInterpolateY':
                            check += f'predicted <- (fit$family$linkfun(.65)-coef(fit)[1])/coef(fit)[2]\n'
                            if logged: check += 'predicted <- 10^predicted\n'
                            check += f'stopifnot(abs(predicted - {follow["values"]["x"]}) < 2e-6)\n'
                        elif child == 'ProbitPlot':
                            check += 'stopifnot(.test_pages == 1L)\n'
                        child_output = replay(label+'-'+child, follow, check)
                        if child in ('ProbitInterpolateX', 'ProbitInterpolateY'):
                            term, value = ('proportional response(?: above natural response)?', 'resp') if child == 'ProbitInterpolateX' else ('dose', 'x')
                            printed = re.search(r'Predicted '+term+r'\s*=\s*([-+.\d]+)', child_output)
                            assert printed, child_output
                            near([float(printed[1])], [follow['values'][value]], label+' '+child+' printed prediction')
                        if child == 'ProbitPlot':
                            assert (work/(label+'-'+child+'.pdf')).stat().st_size > 1000, 'The plot follow-on must actually draw a chart'
                session.close(result['id'])
        print('PASS:', operation, '80/99% intervals, raw/logged doses and all four follow-ons use the native model', flush=True)

    regression_parents = []
    for index, (x, y) in enumerate([
            ([1, 2, 3, 4, 5, 6], [3, 4, 5, 7, 9, 11]),
            ([1, 2, None, 4, 5, 6, 7, 8], [18, 16, 9, None, 11, 8, 6, 5])]):
        parent = run('SimpleLinearRegression', {'x': columns(('Selected X', x)), 'y': columns(('Selected Y', y))}, keep=True)
        regression_parents.append((index, parent))
    for index, parent in regression_parents:
        follow = run('Ranv', {}, parent=parent['id'])
        assert json.loads(follow['record'])['rootOperation'] == 'SimpleLinearRegression'
        assertion = f'stopifnot(abs(unname(summary(fit)$fstatistic[1]) - {follow["values"]["f"]}) < 1e-7)'
        replay(f'Ranv-simple-{index}', follow, assertion)
        session.close(parent['id'])
    print('PASS: two open regression ANOVA follow-ons retain their own parent data, including paired missing rows', flush=True)

    for confidence in (80, 95, 99):
        result = run('NonparametricLinearRegression', {'predictor': columns(('Exposure', [1, 2, 3, 4, 5, 6, 7, 8])),
            'outcome': columns(('Response', [2, 4, 3, 5, 8, 7, 9, 10])), 'gamma': confidence})
        text = plain(result)
        native = re.search(r'Median slope.*?=\s*([-+.\d]+)\s*\(\s*([-+.\d]+)\s+to\s+([-+.\d]+)', text, re.S)
        assert native, text
        output = replay(f'Nonparametric-{confidence}', result)
        bounds = re.search(r'CI for the slope\s*=\s*([^\n]+)', output)
        assert bounds, output
        near(numbers(bounds[1]), [float(native[2]), float(native[3])], f'Nonparametric {confidence}% bounds')
    print('PASS: nonparametric slope intervals follow the selected 80/95/99% confidence', flush=True)

    data = columns(('North clinic', [3, 8, 2, 6, 9, 11, 13, 4, 5, 10]),
                   ('South clinic', [17, 28, 12, 26, 29, 31, 33, 14, 15, 30]))
    for confidence, quantile, conservative in [(80, .25, False), (95, .5, True), (99, .9, False)]:
        result = run('Quantile', {'data': data, 'gamma': confidence, 'quantile': quantile, 'conservative-ci': conservative})
        output = replay(f'Quantile-{confidence}', result)
        native_quantiles = re.findall(r'Quantile\s*\([^)]*\)\s*=\s*([-+.\d]+)', plain(result))
        r_quantiles = re.findall(r'Quantile\s*\([^)]*\)\s*=\s*([-+.\d]+)', output)
        near(list(map(float, r_quantiles)), list(map(float, native_quantiles)), 'both quantile columns')
        assert len(r_quantiles) == 2 and all(c['title'] in output for c in data['columns']), output
        interval = r'Approximate\s+[\d.]+%\s+CI\s*\(([^)]+)\)\s*=\s*\*?\s*([-+.\d]+)\s+to\s*\*?\s*([-+.\d]+)'
        native_limits = re.findall(interval, plain(result))
        r_limits = re.findall(interval, output)
        assert len(native_limits) == len(r_limits) == 2, (native_limits, r_limits, output)
        for wanted, actual in zip(native_limits, r_limits):
            assert actual[0] == wanted[0], (actual, wanted)
            near(list(map(float, actual[1:])), list(map(float, wanted[1:])), 'quantile selected CI method')
        coverage = r'Exact confidence level\s*=\s*([\d.]+)'
        near(list(map(float,re.findall(coverage,output))), list(map(float,re.findall(coverage,plain(result)))), 'quantile actual coverage')
    print('PASS: both quantile columns, names and selected confidence limits (including capped bounds)', flush=True)

    for operation, data in [('Friedman', columns(('A', [2,7,5,8,4,9]), ('B', [3,6,7,4,5,8]), ('C', [5,8,6,9,7,10]))),
                            ('CochranQ', columns(('A', [1,0,1,0,1,0]), ('B', [1,1,0,0,1,1]), ('C', [0,1,0,1,1,1])))]:
        result = run(operation, {'data': data}, keep=True)
        output = replay(operation, result, f"stopifnot(abs(unname(friedman_result['t1'])-{result['values']['t1']})<1e-8)")
        assert ('Cochran Q test' in output) == (operation == 'CochranQ'), output
        if operation == 'Friedman':
            for confidence in (80, 99):
                for sided in ('1', '2'):
                    follow = run('FriedmanMulti', {'confidence': confidence, 'sided': sided}, parent=result['id'])
                    output = replay(f'FriedmanMulti-{confidence}-{sided}', follow, f"stopifnot(abs(critical_t-{follow['values']['t']})<1e-9)")
                    critical = re.search(r'critical t\s*=\s*([-+.\d]+)', output)
                    assert critical, output
                    near([float(critical[1])], [follow['values']['t']], 'Friedman multiple comparison confidence/sidedness')
        session.close(result['id'])
    print('PASS: Friedman and Cochran Q use only the selected data; multiple comparisons retain confidence', flush=True)
    print(f'PASS: {count} real Mac saved-record R regression replays', flush=True)
finally:
    session.finish()
    writer.stdin.close(); writer.wait()
