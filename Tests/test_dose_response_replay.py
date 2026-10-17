"""Mac saved-record dose-response replay, checked against an independent likelihood.

The reference uses a generic optimiser and a Fisher-matrix/Fieller-polynomial
calculation, rather than the production working-response algorithm. Exercise
both links, controls supplied either way, missing/reordered rows, heterogeneity,
selected confidence levels, raw/log doses and every native follow-on.
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


def vector(values):
    return 'c(' + ','.join('NA_real_' if v is None else str(v) for v in values) + ')'


def column(title, values):
    return {'source': 'Dose-response replay test', 'preserveRows': True,
            'columns': [{'title': title, 'values': values}]}


def plain(value):
    return html.unescape(re.sub('<[^>]*>', ' ', value))


def near(actual, expected, label, tolerance=3e-6):
    assert len(actual) == len(expected), (label, actual, expected)
    assert all(math.isclose(a, b, rel_tol=tolerance, abs_tol=tolerance)
               for a, b in zip(actual, expected)), (label, actual, expected)


PRELUDE = r'''
.pages <- 0L; .marks <- list(); .tables <- list()
invisible(trace("plot.new",tracer=quote(.pages <<- .pages+1L),print=FALSE,where=asNamespace("graphics")))
invisible(trace("plot.xy",tracer=quote(.marks <<- c(.marks,list(list(x=xy$x,y=xy$y,type=type)))),print=FALSE,where=asNamespace("graphics")))
invisible(trace("print.data.frame",tracer=quote(.tables <<- c(.tables,list(x))),print=FALSE,where=asNamespace("base")))
.near <- function(actual, expected, tolerance=3e-6) {
  stopifnot(length(actual)==length(expected), all(is.finite(actual)),
            max(abs(actual-expected)/pmax(1,abs(expected)))<tolerance)
}
'''

session = Session()
writer = subprocess.Popen([str(ROOT/'Tests/engine-driver'),
    os.environ.get('STATSDIRECT_TEST_ENGINE', str(ROOT/'FullEngine/publish/StatsDirectEngine.dylib')),
    'statsdirect_r_script'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
work = Path(tempfile.mkdtemp(prefix='dose-response-replay-', dir=ROOT/'.build'))
count = 0


def replay(label, state, assertion):
    global count
    # Use only the saved record, as after reopening a report. No live worksheet.
    record = json.loads(json.dumps(json.loads(state['record'])))
    writer.stdin.write(json.dumps({'record': record, 'frames': []})+'\n')
    writer.stdin.flush()
    reply = json.loads(writer.stdout.readline())
    assert reply.get('hasRecipe') and not reply.get('dataUnavailable'), (label, reply)
    script = PRELUDE + '\noptions(device=function(...) grDevices::pdf(' + \
             json.dumps(str(work/(label+'.pdf'))) + ',...))\n' + reply['text'] + '\n' + assertion
    path = work/(label+'.R'); path.write_text(script)
    result = subprocess.run([rscript(), '--vanilla', str(path)], cwd=work,
                            capture_output=True, text=True, timeout=60)
    (work/(label+'.txt')).write_text(result.stdout+result.stderr)
    assert result.returncode == 0, (label, result.stdout, result.stderr, str(path))
    count += 1
    return result.stdout


def check_printed(output, values, label):
    for text, key in [('constant', 'a'), ('slope', 'b'), ('Median \\* Dose', 'mxd'),
                      ('\\* Dose for centile [\\d.]+', 'doseq')]:
        match = re.search(text + r'\s*=\s*([-+.\deE]+)', output)
        assert match, (label, text, output)
        near([float(match[1])], [values[key]], label+' '+key)
    bounds = re.findall(r'Confidence interval \((?:No Heterogeneity|Heterogeneity)\)\s*=\s*([-+.\deE]+)\s+to\s+([-+.\deE]+)', output)
    assert len(bounds) == 2, (label, output)
    near([float(x) for pair in bounds for x in pair],
         [values[k] for k in ('from', 'to', 'from_cent', 'to_cent')], label+' intervals')


try:
    for operation, model in [('Probit', 'probit'), ('Logit', 'logit')]:
        for heterogeneous in (False, True):
            subjects = [80,100,120,100,80,120,100,100]
            percentages = [8,24,22,59,58,85,85,98] if heterogeneous else [12,18,30,50,70,85,94,98]
            responses = [round(n*p/100) for n, p in zip(subjects, percentages)]
            for control_mode in ('none', 'zero', 'separate', 'embedded'):
                nc, nrc = (0, 0) if control_mode == 'none' else (200, 0 if control_mode == 'zero' else 20)
                for logged in (False, True):
                    dose = [10**(i/4) for i in range(1,9)] if logged else list(range(1,9))
                    # Distinct counts detect row misalignment even if doses are reordered.
                    order = [4,0,6,2,7,1,5,3]
                    selected = [[v[i] for i in order] for v in (dose, subjects, responses)]
                    if control_mode == 'embedded':
                        for values, control in zip(selected, (0, nc, nrc)): values.insert(3, control)
                        for values, missing in zip(selected, (None, 100, 42)): values.insert(6, missing)
                    for confidence in (80, 95, 99):
                        label = f'{operation}-{heterogeneous}-{control_mode}-{logged}-{confidence}'
                        result = session.run(operation, {
                            'dose': column('Dose selected', selected[0]),
                            'subjects': column('Subjects selected', selected[1]),
                            'responders': column('Responses selected', selected[2]),
                            'nc': nc if control_mode in ('separate', 'zero') else 0, 'nrc': nrc,
                            'calc-log10-doses': logged, 'conf': confidence, 'qld': 80},
                            preferences={'use-default-ci': False}, keep=True)
                        values = result['values']; record = json.loads(result['record'])
                        assert record['rootOperation'] == operation
                        assert record['parameters']['doseResponseModel'] == model
                        x = [math.log10(v) for v in dose] if logged else dose
                        scale = 2 if model == 'logit' else 1
                        reference = f'''
source({json.dumps(str(ROOT/'Tests/dose_response_reference.R'))})
.ref <- dose_reference({vector(x)},{vector(subjects)},{vector(responses)},"{model}",{nc},{nrc})
.back <- {'function(x) 10^x' if logged else 'identity'}
.near(.ref$beta/{scale},c({values['a']},{values['b']}))
.near(c(a,b),.ref$beta/{scale})
.near(natural_response,.ref$background)
.near(as.numeric(selected_covariance),as.numeric(.ref$covariance[1:2,1:2]*.ref$phi/{scale**2}))
.near(.ref$chi,{values['dev']})
.near(.ref$df,{values['df']})
.near(pchisq(.ref$chi,.ref$df,lower.tail=FALSE),{values['p']})
.near(.ref$beta[2]/sqrt(.ref$covariance[2,2]*.ref$phi),{values['t_slope']})
stopifnot(.ref$heterogeneous == {'TRUE' if heterogeneous else 'FALSE'})
.near(.back(dose_reference_interval(.ref,.5,{confidence/100})),c({values['from']},{values['to']}))
.near(.back(dose_reference_interval(.ref,.8,{confidence/100})),c({values['from_cent']},{values['to_cent']}))
'''
                        check_printed(replay(label, result, reference), values, label)
                        # All follow-ons at the customary level; 80/99 also check both CIs.
                        if confidence == 95:
                            for child, settings in [('ProbitMore', {}), ('ProbitPlot', {}),
                                    ('ProbitInterpolateX', {'newx': dose[3]}),
                                    ('ProbitInterpolateY', {'newy': .65})]:
                                follow = session.run(child, settings, parent=result['id'])
                                follow_record = json.loads(follow['record'])
                                assert follow_record['rootOperation'] == operation
                                assert follow_record['parameters']['doseResponseModel'] == model
                                assertion = reference
                                if child == 'ProbitMore':
                                    cells = re.findall(r'<tr>\s*<td>(.*?)</td>\s*</tr>', follow['html'], re.S)
                                    rows = [[float(plain(v)) for v in re.split(r'</td>\s*<td>', row)] for row in cells]
                                    assert len(rows) == 8 and all(len(row) == 5 for row in rows), (label, rows)
                                    # More retains selected worksheet order, excluding controls/missing rows.
                                    near([row[1] for row in rows], [subjects[i] for i in order], label+' native subjects')
                                    near([row[2] for row in rows], [responses[i] for i in order], label+' native responses')
                                    assertion += f'''
.order <- {vector([i+1 for i in order])}
.near((.ref$probability*{vector(subjects)})[.order], {vector([row[3] for row in rows])})
.near(.ref$covariance[2,2]*.ref$phi/{scale**2}, {follow['values']['var_b']})
.near(sqrt(.ref$covariance[2,2]*.ref$phi)/{scale}, {follow['values']['seb']})
.replay_tables <- Filter(function(t) all(c("subjects","responses","expected","deviation") %in% names(t)),.tables)
stopifnot(length(.replay_tables)==1L)
.near(.replay_tables[[1]]$subjects,{vector(subjects)}[.order])
.near(.replay_tables[[1]]$responses,{vector(responses)}[.order])
.near(.replay_tables[[1]]$expected,(.ref$probability*{vector(subjects)})[.order])
'''
                                    if nrc:
                                        natural = re.search(r'Estimated natural response rate \(C\)\s*=\s*([-+.\deE]+)', plain(follow['html']))
                                        assert natural, follow['html']
                                        assert "Standard error of C" in plain(follow['html']), follow['html']
                                        assertion += f'.near(.ref$background,{float(natural[1])})\n'
                                elif child == 'ProbitPlot':
                                    assert follow['html'].count('<svg') == 1 and 'Chart not drawn' not in follow['html'], label
                                    assertion += f'''
stopifnot(.pages==1L)
.observed <- ({vector(responses)}/{vector(subjects)}-.ref$background)/(1-.ref$background)
stopifnot(any(vapply(.marks,function(m) length(m$x)==8L &&
  max(abs(m$x-{vector(dose)}))<1e-6 && max(abs(m$y-.observed))<3e-6,logical(1))))
stopifnot(any(vapply(.marks,function(m) length(m$x)>20L && m$type=="l" &&
  max(abs(m$y-make.link("{model}")$linkinv(.ref$beta[1]+.ref$beta[2]*
    {'log10(m$x)' if logged else 'm$x'})))<3e-6,logical(1))))
.critical <- if(.ref$heterogeneous) qt({(1+confidence/100)/2},.ref$df) else qnorm({(1+confidence/100)/2})
for(.side in c(-1,1)) stopifnot(any(vapply(.marks,function(m) {{
  if(length(m$x)<=20L || m$type!="l") return(FALSE)
  xx <- {'log10(m$x)' if logged else 'm$x'}
  vv <- .ref$covariance[1:2,1:2]*.ref$phi
  se <- sqrt(pmax(0,vv[1,1]+2*xx*vv[1,2]+xx^2*vv[2,2]))
  expected <- make.link("{model}")$linkinv(.ref$beta[1]+.ref$beta[2]*xx+.side*.critical*se)
  max(abs(m$y-expected))<3e-6
}},logical(1))))
'''
                                elif child == 'ProbitInterpolateX':
                                    assertion += f'.near(.ref$excess[4],{follow["values"]["resp"]})\n.near(predicted_observed_response,.ref$probability[4])\n'
                                    if nrc:
                                        observed = re.search(r'proportional response = ([-+.\deE]+)', follow['values']['mort'])
                                        assert observed, follow['values']
                                        assertion += f'.near(.ref$probability[4],{float(observed[1])})\n'
                                else:
                                    assertion += f'.near(.back((make.link("{model}")$linkfun(.65)-.ref$beta[1])/.ref$beta[2]),{follow["values"]["x"]})\n'
                                output = replay(label+'-'+child, follow, assertion)
                                if child in ('ProbitInterpolateX', 'ProbitInterpolateY'):
                                    term, key = ('proportional response(?: above natural response)?', 'resp') if child == 'ProbitInterpolateX' else ('dose', 'x')
                                    match = re.search('Predicted '+term+r'\s*=\s*([-+.\deE]+)', output)
                                    assert match, output
                                    near([float(match[1])], [follow['values'][key]], label+' printed '+child)
                                if child == 'ProbitPlot':
                                    assert (work/(label+'-'+child+'.pdf')).stat().st_size > 1000
                        session.close(result['id'])
            print(f'PASS: {operation}, heterogeneity={heterogeneous}, controls, 80/95/99% CIs, raw/log doses and all follow-ons', flush=True)
    # A distant low-dose group can inform background response even when its
    # derivative with respect to the slope is numerically zero. Keep its df and
    # background information in both the native fit and the portable R replay.
    for operation, model in [('Probit', 'probit'), ('Logit', 'logit')]:
        for logged in (False, True):
            doses = [1,100,101,102,103,104,105,106]
            x = [math.log10(v) for v in doses] if logged else doses
            scale = 2 if model == 'logit' else 1
            for confidence in (80,95,99):
                label = f'{operation}-lower-asymptote-{logged}-{confidence}'
                root = session.run(operation, {
                    'dose': column('Widely spaced doses', doses),
                    'subjects': column('Subjects', [100]*8),
                    'responders': column('Responses', [10,18,30,50,70,85,94,98]),
                    'nc': 200, 'nrc': 20, 'calc-log10-doses': logged,
                    'conf': confidence, 'qld': 80}, preferences={'use-default-ci': False}, keep=True)
                values = root['values']
                assertion = f'''
source({json.dumps(str(ROOT/'Tests/dose_response_reference.R'))})
.ref <- dose_reference({vector(x)},rep(100,8),c(10,18,30,50,70,85,94,98),"{model}",200,20)
.back <- {'function(x) 10^x' if logged else 'identity'}
.near(c(a,b),.ref$beta/{scale})
.near(c({values['a']},{values['b']}),.ref$beta/{scale})
.near(natural_response,.ref$background)
.near(as.numeric(selected_covariance),as.numeric(.ref$covariance[1:2,1:2]*.ref$phi/{scale**2}))
.near(chi,.ref$chi); .near({values['dev']},.ref$chi)
stopifnot(df==6L,{values['df']}==6L)
.near(.back(dose_reference_interval(.ref,.5,{confidence/100})),c({values['from']},{values['to']}))
.near(.back(dose_reference_interval(.ref,.8,{confidence/100})),c({values['from_cent']},{values['to_cent']}))
'''
                check_printed(replay(label,root,assertion),values,label)
                if confidence == 95:
                    for child in ('ProbitMore','ProbitPlot'):
                        follow = session.run(child,{},parent=root['id'])
                        extra = assertion
                        if child == 'ProbitMore':
                            extra += '.near(dose_response_table$expected,.ref$probability*100)\n'
                            extra += f'.near({follow["values"]["var_b"]},.ref$covariance[2,2]*.ref$phi/{scale**2})\n'
                        else:
                            assert follow['html'].count('<svg')==1 and 'Chart not drawn' not in follow['html']
                            extra += 'stopifnot(.pages==1L)\n'
                        replay(label+'-'+child,follow,extra)
                session.close(root['id'])
    print('PASS: distant low-dose groups retain background information, residual df and follow-ons', flush=True)

    # A fitted curve can be valid while its inverse interval is unbounded. Native
    # analysis explains that; replay of an older saved run must not invent limits.
    for operation, model in [('Probit', 'probit'), ('Logit', 'logit')]:
        answers = {'dose': column('Dose', list(range(1,9))),
                   'subjects': column('Subjects', [100]*8),
                   'responders': column('Responses', [10,30,15,70,45,85,70,98]),
                   'nc': 200, 'nrc': 20, 'calc-log10-doses': False, 'conf': 95, 'qld': 80}
        bounded = session.run(operation, answers, preferences={'use-default-ci': False})
        answers['conf'] = 99
        try:
            session.run(operation, answers, preferences={'use-default-ci': False})
        except AssertionError as failure:
            assert 'Slope insignificant' in str(failure), str(failure)
        else:
            raise AssertionError(operation+' should reject a selected unbounded native interval')
        record = json.loads(bounded['record'])
        record['parameters']['conf'] = .99
        replay(operation+'-unbounded', {'record': json.dumps(record)}, f'''
source({json.dumps(str(ROOT/'Tests/dose_response_reference.R'))})
.ref <- dose_reference(1:8,rep(100,8),c(10,30,15,70,45,85,70,98),"{model}",200,20)
stopifnot(qt(.995,.ref$df)^2*.ref$covariance[2,2]*.ref$phi/.ref$beta[2]^2>1)
stopifnot(all(heterogeneity_interval_status %in% c("disjoint","unbounded")))
stopifnot(all(!is.finite(fieller(.5))))
''')
    print('PASS: native unbounded-interval explanation and honest R confidence sets', flush=True)
    print(f'PASS: {count} Mac dose-response saved-record R replays against independent likelihood and Fieller calculations', flush=True)
finally:
    session.finish()
    writer.stdin.close(); writer.wait()
