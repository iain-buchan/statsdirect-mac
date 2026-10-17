"""Selected survival, forest and ROC data are the data actually drawn in R.

Exercise the Mac forms, saved records and real R graphics calls, including times
outside the help example, signed effects and either ROC score direction.
"""
import html
import json
import math
import os
import re
import subprocess
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

from test_menu import ROOT, Session
from r_runtime import rscript


def column(title, values):
    return {'source': 'Selected chart checks', 'columns': [{'title': title, 'values': values}]}


session = Session()
writer = subprocess.Popen([str(ROOT/'Tests/engine-driver'),
    os.environ.get('STATSDIRECT_TEST_ENGINE', str(ROOT/'FullEngine/publish/StatsDirectEngine.dylib')),
    'statsdirect_r_script'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
work = Path(tempfile.mkdtemp(prefix='chart-recipe-regressions-', dir=ROOT/'.build'))
count = 0


def acquire(operation, answers, title, confidence=95, fields=None):
    job, state = session.start(operation, preferences={'default-ci': confidence})
    counters = {}
    for _ in range(60):
        if state['state'] != 'input': break
        prompt = state['prompt']; kind = prompt['kind']; name = prompt.get('name')
        assert not prompt.get('error'), (operation, prompt)
        if name in answers:
            value = answers[name]
            if isinstance(value, list):
                index = counters.get(name, 0); counters[name] = index + 1; value = value[index]
        elif kind in ('fields', 'settings'):
            value = {f['name']: f['defaultValue'] for f in prompt['fields']}
            if 'title' in value: value['title'] = title
            value.update((fields or {}).get(prompt.get('title'), {}))
        elif kind == 'options': value = {o['value']: o['selected'] for o in prompt['options']}
        elif prompt.get('skip'): value = {'skip': True}
        elif prompt.get('defaultValue') is not None: value = prompt['defaultValue']
        elif kind == 'boolean': value = False
        else: raise AssertionError((operation, 'unanswered prompt', prompt))
        session.request(action='answer', id=job, token=state['token'], value=value)
        state = session.wait(job)
    session.close(job)
    assert state['state'] == 'complete' and state['html'].count('<svg') == 1, (operation, state)
    assert 'Chart not drawn' not in state['html'] and title in state['html'], operation
    return state


PRELUDE = r'''
.pages <- 0L; .marks <- list(); .segments <- list(); .windows <- list()
trace("plot.new", tracer=quote(.pages <<- .pages+1L), print=FALSE, where=asNamespace("graphics"))
trace("plot.xy", tracer=quote(.marks <<- c(.marks, list(list(x=xy$x,y=xy$y,type=type)))), print=FALSE, where=asNamespace("graphics"))
trace("segments", tracer=quote(.segments <<- c(.segments,list(list(x0=x0,y0=y0,x1=x1,y1=y1)))), print=FALSE, where=as.environment("package:graphics"))
trace("plot.window", exit=quote(.windows <<- c(.windows,list(par(c("usr","xlog"))))), print=FALSE, where=asNamespace("graphics"))
has_points <- function(x,y) {
  .marks <- c(.marks, lapply(.segments,function(d) list(x=d$x1,y=d$y1)))
  all(vapply(seq_along(x),function(i) any(vapply(.marks,function(d) any(abs(d$x-x[i])<1e-9 & abs(d$y-y[i])<1e-9),logical(1))),logical(1)))
}
has_limits <- function(x,lo,hi) all(vapply(seq_along(x),function(i) any(vapply(.segments,function(d) any(abs(d$x0-x[i])<1e-9 & abs(d$x1-x[i])<1e-9 & ((abs(d$y0-lo[i])<1e-9 & abs(d$y1-hi[i])<1e-9) | (abs(d$y1-lo[i])<1e-9 & abs(d$y0-hi[i])<1e-9))),logical(1))),logical(1)))
'''


def replay(label, state, assertions):
    global count
    writer.stdin.write(json.dumps({'record': json.loads(state['record']), 'frames': []})+'\n'); writer.stdin.flush()
    reply = json.loads(writer.stdout.readline())
    assert reply.get('hasRecipe') and not reply.get('dataUnavailable'), reply
    path = work/(label+'.R')
    path.write_text(PRELUDE+'\npdf('+json.dumps(label+'.pdf')+')\n'+reply['text']+'\n'+assertions+'\nstopifnot(.pages==1L); dev.off()\n')
    result = subprocess.run([rscript(), '--vanilla', str(path)], cwd=work, capture_output=True, text=True, timeout=60)
    (work/(label+'.txt')).write_text(result.stdout+result.stderr)
    assert result.returncode == 0, (label, result.stdout, result.stderr)
    count += 1
    return result.stdout


try:
    for groups in (1, 2):
        state = acquire('SurvivalPlot', {'group-count': groups,
            'xdatNew': [column('Times A', [1,2,3,4]), column('Times B', [2,3,5,7])],
            'cdatNew': [column('Events A', [1,1,0,1]), column('Events B', [0,1,1,1])],
            'ydatNew': [column('Survival A', [.95,.8,.7,.55]), column('Survival B', [.99,.9,.85,.75])],
            'ydatlNew': [column('Lower A', [.85,.7,.6,.4]), column('Lower B', [.9,.8,.7,.65])],
            'ydatuNew': [column('Upper A', [1,.9,.8,.7]), column('Upper B', [1,.98,.95,.85])]}, 'Selected survival')
        assertion = 'stopifnot(has_points(c(1,2,3,4),c(.95,.8,.7,.55)))\n'
        if groups == 2: assertion += 'stopifnot(has_points(c(2,3,5,7),c(.99,.9,.85,.75)))\n'
        assertion += 'stopifnot(any(vapply(.windows,function(w) w$usr[1]<2 && w$usr[2]<20,logical(1))))\n'
        replay('Survival-'+str(groups), state, assertion)
    print('PASS: survival replays the supplied S values for one and two groups at their selected times', flush=True)

    for with_limits in (0,1):
        state = acquire('SurvivalPlot', {'group-count':2,
            'xdatNew':[column('Times A',[1,2,3,4]),column('Times B',[2,3,5,7])],
            'cdatNew':[column('Events A',[1,1,0,1]),column('Events B',[0,1,1,1])],
            'ydatNew':[column('Survival A',[.95,.8,.7,.55]),column('Survival B',[.99,.9,.85,.75])],
            'ydatlNew':[column('Lower',[[.85,.7,.6,.4],[.9,.8,.7,.65]][i]) if i==with_limits else {'skip':True} for i in range(2)],
            'ydatuNew':column('Upper',[[1,.9,.8,.7],[1,.98,.95,.85]][with_limits])}, 'Survival with optional limits')
        svg = ET.fromstring(re.search(r'<svg\b[\s\S]*?</svg>',state['html'])[0])
        ci_bars = [e for e in svg.iter() if e.tag.endswith('line') and 'stroke-dasharray' in e.get('style','') and e.get('x1')==e.get('x2')]
        assert len(ci_bars)==3, (with_limits,'Native chart lost the supplied group confidence limits',len(ci_bars))
        assertion = ('stopifnot(has_limits(c(1,2,4),c(.85,.7,.4),c(1,.9,.7)))' if with_limits==0 else
                     'stopifnot(has_limits(c(3,5,7),c(.8,.7,.65),c(.98,.95,.85)))')
        replay('Survival-optional-'+str(with_limits), state, assertion)
    print('PASS: optional survival limits stay with the correct group in both native SVG and R/PDF', flush=True)

    # Beyond the small-curve snapshot threshold, replay must still use the
    # selected survival column rather than reconstructing it from event counts.
    size = 5001
    state = acquire('SurvivalPlot', {'group-count':1,
        'xdatNew':column('Long times',list(range(1,size+1))),
        'cdatNew':column('Long events',[i%2 for i in range(size)]),
        'ydatNew':column('Long supplied survival',[1-i/(2*size) for i in range(size)]),
        'ydatlNew':{'skip':True}}, 'Long selected survival')
    assert 'curves' not in json.loads(state['record'])['parameters']['chartSettings']
    replay('Survival-long', state, f'stopifnot(has_points(c(1,2501,{size}),c(1,1-2500/(2*{size}),1-5000/(2*{size}))))')
    print('PASS: large survival input replays selected values without a small-curve snapshot', flush=True)

    size = 1001
    second = [.95-i/(4*size) for i in range(size)]
    state = acquire('SurvivalPlot', {'group-count':2,
        'xdatNew':[column('Long times A',list(range(1,size+1))),column('Long times B',list(range(2,size+2)))],
        'cdatNew':[column('Long events A',[1]*size),column('Long events B',[1]*size)],
        'ydatNew':[column('Long S A',[1-i/(2*size) for i in range(size)]),column('Long S B',second)],
        'ydatlNew':[{'skip':True},column('Long lower B',[y-.05 for y in second])],
        'ydatuNew':column('Long upper B',[y+.05 for y in second])}, 'Long survival with optional limits')
    settings = json.loads(state['record'])['parameters']['chartSettings']
    assert 'curves' not in settings and [s['hasLower'] for s in settings['curveShapes']] == [False,True]
    replay('Survival-long-optional',state, f'''stopifnot(has_points(c(1,501,1001),c(1,1-500/(2*{size}),1-1000/(2*{size}))))
expected <- c(.95,.95-500/(4*{size}),.95-1000/(4*{size}))
stopifnot(has_points(c(2,502,1002),expected),has_limits(c(2,502,1002),expected-.05,expected+.05))''')
    print('PASS: large mixed-group survival limits stay aligned without embedded curves', flush=True)

    for title, estimates, lower, upper in [('Mean difference', [-2,.5,1.2], [-3,-.5,.2], [-1,1.5,2.2]),
                                         ('Risk ratio', [.5,1.2,2.1], [.2,.8,1.1], [.9,1.8,3.1])]:
        state = acquire('CochranePlot', {'odds': column(title, estimates), 'lci': column('Lower', lower),
            'uci': column('Upper', upper), 'gn': {'skip':True}, 'pg': {'skip':True},
            'title': column('Studies', ['North','South','West'])}, 'Selected forest')
        scale = json.loads(state['record'])['parameters']['chartSettings']['x']['scale']
        assert (scale != 0) == (title == 'Risk ratio')
        expected = 'TRUE' if scale != 0 else 'FALSE'
        assertion = f'stopifnot(any(vapply(.windows,function(w) identical(w$xlog,{expected}),logical(1))))\n'
        assertion += 'stopifnot(has_points(c('+','.join(map(str,estimates))+'),c(3,2,1)))'
        output = replay('Forest-'+title.replace(' ','-'), state, assertion)
        assert all(name in output for name in ['North','South','West']), output
    print('PASS: forest charts preserve signed effects on a linear axis and ratios on a log axis', flush=True)

    for present, absent, direction, confidence, cutoff in [([1,2,3,4,5], [3,4,5,6,7], 'lower', 80, None),
                                                          ([1,2,3,4,5], [3,4,5,6,7], 'lower', 99, None),
                                                          ([8,9,10,11,12], [3,4,5,8,9], 'higher', 80, None),
                                                          ([8,9,10,11,12], [3,4,5,8,9], 'higher', 99, None),
                                                          ([1,2,3,4,5], [3,4,5,6,7], 'lower', 99, 3.5)]:
        label = direction+'-'+str(confidence)+('-manual' if cutoff is not None else '')
        state = acquire('ROCPlot', {'series-count':1, 'P1':column('Condition present',present),
            'A1':column('Condition absent',absent)}, 'Selected ROC', confidence,
            {'ROC cutoff': {'cutoff':cutoff}} if cutoff is not None else None)
        text = html.unescape(re.sub('<[^>]*>', ' ', state['html']))
        cut = float(re.search(r'Optimum cut-off point selected\s*=\s*([-+.\d]+)',text)[1])
        if cutoff is not None: assert cut == cutoff
        comparison = '<=' if direction == 'lower' else '>='
        assertion = f'''selected_present <- c({','.join(map(str,present))}); selected_absent <- c({','.join(map(str,absent))})
selected_cuts <- sort(unique(c(selected_present,selected_absent)))
expected_fpr <- vapply(selected_cuts,function(k) mean(selected_absent {comparison} k),numeric(1))
expected_sensitivity <- vapply(selected_cuts,function(k) mean(selected_present {comparison} k),numeric(1))
stopifnot(has_points(expected_fpr,expected_sensitivity))'''
        output = replay('ROC-'+label, state, assertion)
        r_cut = float(re.search(r'Selected cutoff\s*=\s*([-+.\d]+)',output)[1])
        assert r_cut == cut, (label,r_cut,cut)
        for native_pattern, r_pattern in [
            (r'Area under ROC curve by extended trapezoidal rule\s*=\s*([-+.\d]+)', r'AUC\s*=\s*([-+.\d]+)'),
            (r'Wilcoxon estimate of area under ROC curve\s*=\s*([-+.\d]+)', r'rank estimate\s*=\s*([-+.\d]+)'),
            (r'DeLong standard error\s*=\s*([-+.\d]+):\s*[\d.]+% CI\s*=\s*([-+.\d]+)\s+to\s+([-+.\d]+)',
             r'DeLong SE\s*=\s*([-+.\d]+)\s*;\s*[\d.]+\s*% CI\s*=\s*([-+.\d]+)\s+to\s+([-+.\d]+)')]:
            native = re.search(native_pattern,text); exported = re.search(r_pattern,output)
            assert native and exported, (label,native_pattern,text,output)
            assert all(math.isclose(float(a),float(b),abs_tol=2e-6,rel_tol=2e-6) for a,b in zip(native.groups(),exported.groups())), (label,native.groups(),exported.groups())
        assert json.loads(state['record'])['parameters']['chartSettings']['confidence'] == confidence/100
    print('PASS: ROC directions, default/manual cutoffs, AUC and 80/99% limits match native results', flush=True)
    print(f'PASS: {count} Mac chart records replay selected observations in R/PDF', flush=True)
finally:
    session.finish()
    writer.stdin.close(); writer.wait()
