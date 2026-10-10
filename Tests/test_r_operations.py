"""The engine's R script steps on the Mac. LOESS curve fitting is defined as an R script, as on Windows: the engine writes
the inputs as R variables, the Mac host runs Rscript in a folder of its own, reads the results back and puts R's chart
(a PNG from the quartz device, in place of the Windows metafile) and the script into the HTML report. The figures are
checked against R called directly on the same data, the help example against its printed values, and the host's own
paths: missing values, several predictors, R not installed, an R error, and cancelling while R runs."""
import base64, math, os, re, subprocess, sys, tempfile, time
from pathlib import Path
ARGS = sys.argv[1:]; sys.argv = sys.argv[:1]
from test_menu import Session
from r_runtime import rscript
from test_help_examples import column, frame_answer

work = tempfile.mkdtemp(prefix='statsdirect-r-')
os.environ['STATSDIRECT_R_FOLDER'] = work   # the engine's R runs and package library, kept out of Application Support
RUNS = Path(work) / 'R Operations'

def answer(s, operation, answers):
    id, st = s.start(operation); prompts = []
    while st.get('state') == 'input':
        p = st['prompt']; name = p.get('name'); prompts.append(name)
        assert not p.get('error'), (name, p['error'])
        if name in answers: v = answers[name]
        elif p['kind'] == 'boolean': v = False
        elif p.get('defaultValue') is not None: v = p['defaultValue']
        elif p['kind'] == 'option': v = p['options'][0]['value']
        else: raise AssertionError(('unanswered', p))
        s.request(action='answer', id=id, token=st['token'], value=v); st = s.wait(id)
    s.request(action='release', id=id)
    return st, prompts

def direct(y, xs, span=0.75, degree=2):
    """R on the same data: n, equivalent parameters, residual standard error, residual df, then the fits and their standard errors."""
    with tempfile.NamedTemporaryFile('w', suffix='.csv', delete=False) as f:
        f.write(','.join(['y'] + [f'x{i}' for i in range(len(xs))]) + '\n')
        for row in zip(y, *xs): f.write(','.join('NA' if v is None else repr(float(v)) for v in row) + '\n')
    code = (f'd<-read.csv("{f.name}");m<-loess(y~{"+".join(f"x{i}" for i in range(len(xs)))},data=d,span={span},degree={degree});p<-predict(m,se=TRUE);'
            'cat(sprintf("%.15g",c(m$n,m$enp,m$s,p$df)),"\\n");cat(sprintf("%.15g",m$fitted),"\\n");cat(sprintf("%.15g",p$se.fit),"\\n")')
    out = subprocess.check_output([rscript(), '--vanilla', '-e', code], text=True, stderr=subprocess.DEVNULL).strip().split('\n')
    os.unlink(f.name)
    return [float(v) for v in out[0].split()], [float(v) for v in out[1].split()], [float(v) for v in out[2].split()]

def frame(**named):
    """Fixture columns by title. R names each variable after its column title, as on Windows, so the titles must differ."""
    return {'source': 'Test fixture', 'columns': [{'title': t, 'values': list(v)} for t, v in named.items()]}

def frame_values(frame):
    """A written frame's title and its values by worksheet row (missing rows absent)."""
    cells = frame['cells']; title = next(c['text'] for c in cells if c['row'] == 0)
    return title, {c['row'] - 1: float(c['text']) for c in cells if c['row'] > 0}

def close(a, b, rel=1e-9): return math.isclose(a, b, rel_tol=rel, abs_tol=1e-12)

s = Session()
try:
    # The help example: Hgb against eGFR in 804 diabetics, with the plot, the fits written back and the script shown.
    hgb, egfr = column('Hgb', 'Nonparametric'), column('eGFR', 'Nonparametric')
    st, prompts = answer(s, 'LOESS', {'outcome': frame_answer([hgb]), 'predictors': frame_answer([egfr]), 'title': 'Anaemia vs. Kidney Function in Diabetics',
                                      'plotFitsAndCi': True, 'saveFitsAndSe': True, 'saveRScript': True})
    assert st['state'] == 'complete', st.get('error')
    assert prompts == ['outcome', 'predictors', 'model', 'title', 'ylab', 'xlab', 'span', 'degree', 'plotFits', 'plotFitsAndCi', 'saveFitsAndSe', 'saveRScript'], prompts
    text = re.sub(r'\s+', ' ', re.sub(r'<[^>]+>', ' ', st['html']))
    for figure in ['Number of Observations: 804', 'Polynomial degree: 2, Span: 0.75', 'Equivalent Number of Parameters: 5.464141', 'Residual Standard Error: 15.159968']:
        assert figure in text, (figure, text[:400])
    values = st['values']
    stats, fits, ses = direct([float(v) for v in hgb['values']], [[float(v) for v in egfr['values']]])
    assert values['observations'] == stats[0] == 804 and close(values['parameters'], stats[1]) and close(values['residualse'], stats[2]) and close(values['df'], stats[3]), (values, stats)
    img = re.search(r'<img alt="R chart"[^>]*>', st['html']); assert img, st['html'][:300]
    assert 'width="576" height="384"' in img[0], img[0][:200]   # the script draws 864 by 576 pixels at 144 dots per inch; the PNG records the resolution
    png = base64.b64decode(re.search(r'base64,([A-Za-z0-9+/=]+)', img[0])[1])
    assert png[:8] == b'\x89PNG\r\n\x1a\n' and int.from_bytes(png[16:20], 'big') == 864 and int.from_bytes(png[20:24], 'big') == 576 and len(png) > 20000, len(png)
    script = st['html'].split('R script to reproduce this result')[1]   # shown as text with line breaks, as on Windows
    assert 'loess(model,span=span,degree=degree)' in script and 'hgb &lt;- c(' in script and '<br />' in script and 'returning.to.statsdirect &lt;- TRUE' not in script and 'win.metafile &lt;- function' not in script, script[:300]
    assert text.index('R script to reproduce this result') < text.index('userdir'), 'the script is shown under its heading'
    (fit_title, fit), (se_title, se) = (frame_values(f) for f in st['frames'])
    assert (fit_title, se_title) == ('LOESS fit', 'LOESS fit SE') and [f['placement'] for f in st['frames']] == ['AfterSelection'] * 2 and [f['lengths'] for f in st['frames']] == [[804], [804]], st['frames'][0].keys()
    assert len(fit) == 804 and all(close(fit[i], fits[i]) and close(se[i], ses[i]) for i in range(804))
    print('PASS: the LOESS help example runs through R from the Mac form: its four printed figures, the fits and standard errors written back agree with R called directly; the chart is R\'s PNG and the script is shown')

    # Missing values: loess leaves the row out, the fits are padded back to the worksheet rows, and the count is of complete rows.
    y = [12, 13, 11, 15, 14, 13, 12, 16, 15, 14, 13, 12, 11, 11, 13, 14]; x = [90, 85, 60, 95, 80, 70, 65, 99, 92, 88, 75, 55, 50, 48, 77, 83]
    gaps = {3, 9}
    st, _ = answer(s, 'LOESS', {'outcome': frame(Hgb=['*' if i in gaps else v for i, v in enumerate(y)]), 'predictors': frame(eGFR=x), 'saveFitsAndSe': True})
    assert st['state'] == 'complete', st.get('error')
    stats, fits, ses = direct([None if i in gaps else v for i, v in enumerate(y)], [x])
    assert st['values']['observations'] == 14 == stats[0] and close(st['values']['parameters'], stats[1]) and close(st['values']['residualse'], stats[2])
    (_, fit), (_, se) = (frame_values(f) for f in st['frames'])
    assert set(fit) == set(se) == set(range(16)) - gaps and [f['lengths'] for f in st['frames']] == [[16], [16]]
    kept = [i for i in range(16) if i not in gaps]
    assert all(close(fit[i], fits[k]) and close(se[i], ses[k]) for k, i in enumerate(kept))
    assert '<img alt="R chart"' in st['html'], 'with one predictor the script always draws the scatter, with the fit and band only when asked'
    print('PASS: rows with a missing outcome are left out of the fit and left blank in the written fits, as the R script pads them')

    # Several predictors: the formula names them all, the plot prompts are not asked and no chart is drawn.
    z = [1, 2, 1, 3, 2, 2, 1, 3, 3, 2, 1, 1, 2, 3, 2, 1]
    st, prompts = answer(s, 'LOESS', {'outcome': frame(Hgb=y), 'predictors': frame(eGFR=x, Age=z), 'span': 0.9, 'degree': '1'})
    assert st['state'] == 'complete', st.get('error')
    assert prompts == ['outcome', 'predictors', 'model', 'title', 'span', 'degree', 'saveFitsAndSe', 'saveRScript'], prompts
    stats, _, _ = direct(y, [x, z], span=0.9, degree=1)
    assert close(st['values']['parameters'], stats[1]) and close(st['values']['residualse'], stats[2]) and 'Polynomial degree: 1, Span: 0.9' in re.sub(r'\s+', ' ', re.sub(r'<[^>]+>', ' ', st['html']))
    assert '<img' not in st['html'] and not st.get('frames')
    print('PASS: two predictors fit with the chosen span and degree, without the single-predictor plot')

    # An error inside R reaches the form as R's own message.
    st, _ = answer(s, 'LOESS', {'outcome': frame(Hgb=y), 'predictors': frame(eGFR=x), 'span': 0.01})
    assert st['state'] == 'failed' and st['error'].startswith('R reported: Error in') and 'loess' in st['error'], st
    print('PASS: an error raised inside R is reported with its text')
    assert not any(RUNS.iterdir()) if RUNS.exists() else True, 'run folders are removed after reading'
finally:
    s.finish()

# R not installed: the operation stops with the advice to install it, before anything runs.
os.environ['STATSDIRECT_RSCRIPT'] = os.path.join(work, 'no-such-Rscript')
s = Session()
try:
    st, _ = answer(s, 'LOESS', {'outcome': frame(Hgb=y), 'predictors': frame(eGFR=x)})
    assert st['state'] == 'failed' and st['error'].startswith('R is not installed. Choose R ▸ Install R…'), st
    print('PASS: without R the form says how to install it')
finally:
    s.finish()

# Cancelling while R runs kills it, the form reports the cancellation and the run folder goes.
slow = Path(work) / 'slow-Rscript'; slow.write_text(f'#!/bin/sh\nsleep 30\nexec "{rscript()}" "$@"\n'); slow.chmod(0o755)
os.environ['STATSDIRECT_RSCRIPT'] = str(slow)
s = Session()
try:
    id, st = s.start('LOESS')
    while st.get('state') == 'input':
        p = st['prompt']; name = p.get('name')
        v = {'outcome': frame(Hgb=y), 'predictors': frame(eGFR=x)}.get(name, False if p['kind'] == 'boolean' else p.get('defaultValue') if p.get('defaultValue') is not None else p['options'][0]['value'] if p['kind'] == 'option' else None)
        s.request(action='answer', id=id, token=st['token'], value=v)
        if name == 'saveRScript': break
        st = s.wait(id)
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline and s.request(action='poll', id=id).get('progress') != 'Running R script': time.sleep(0.05)
    started = time.monotonic(); s.request(action='cancel', id=id); st = s.wait(id)
    assert st['state'] == 'cancelled' and time.monotonic() - started < 5, (st.get('state'), st.get('error'))
    s.request(action='release', id=id)
    time.sleep(0.5)
    assert not (RUNS.exists() and any(RUNS.iterdir())), 'the cancelled run folder was not removed'
    print('PASS: cancelling while R runs stops it within the moment and clears its folder')
finally:
    s.finish()
    del os.environ['STATSDIRECT_RSCRIPT']
