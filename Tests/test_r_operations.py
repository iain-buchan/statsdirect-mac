"""The engine's R script steps on the Mac. LOESS curve fitting is defined as an R script, as on Windows: the engine writes
the inputs as R variables, the Mac host runs Rscript in a folder of its own, reads the results back and puts R's chart
(a PNG from the quartz device, in place of the Windows metafile) and the script into the HTML report. The figures are
checked against R called directly on the same data, the help example against its printed values, and the host's own
paths: missing values, several predictors, R not installed, an R error, and cancelling while R runs."""
import json, math, os, re, shutil, subprocess, sys, tempfile, time
from pathlib import Path
ARGS = sys.argv[1:]; sys.argv = sys.argv[:1]
from test_menu import Session
from r_runtime import rscript
from test_help_examples import column, frame_answer

work = tempfile.mkdtemp(prefix='statsdirect-r-')
os.environ['STATSDIRECT_R_FOLDER'] = work   # the engine's R runs and package library, kept out of Application Support
RUNS = Path(work) / 'R Operations'
# The packages the program's R runs install (svglite for the charts, mcr for method comparison regression) are in the program's own
# library when it has run them before: the runs here share it, so that nothing is downloaded again; a fresh machine installs as the
# program does.
SHARED_LIBRARY = Path('~/Library/Application Support/StatsDirect Viewer/R Library').expanduser()
if SHARED_LIBRARY.is_dir(): (Path(work) / 'R Library').symlink_to(SHARED_LIBRARY)
R_ENV = dict(os.environ, R_LIBS=str(Path(work) / 'R Library'))

def answer(s, operation, answers):
    id, st = s.start(operation); prompts = []
    while st.get('state') == 'input':
        p = st['prompt']; name = p.get('name'); prompts.append(name)
        assert not p.get('error'), (name, p['error'])
        if name in answers: v = answers[name]
        elif p['kind'] == 'boolean': v = False
        elif p['kind'] == 'options': v = {o['value']: o['selected'] for o in p['options']}   # the form's defaults
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
    # The script draws six by four inches through R's svg device, svglite here: the SVG goes into the report inline, as the engine's own charts do.
    svg = re.search(r'<svg\b[^>]*>', st['html']); assert svg and '<?xml' not in st['html'] and 'data:image/png' not in st['html'], st['html'][:300]
    assert re.search(r"width=['\"]432(\.00)?pt['\"]", svg[0]) and re.search(r"height=['\"]432(\.00)?pt['\"]", svg[0]) and 'viewBox' in svg[0], svg[0]
    assert st['html'].count('<svg') == 1 and '</svg>' in st['html'] and st['html'].count('<circle') >= 800 and st['html'].count('<polyline') >= 3, 'the scatter, the fit and the band'
    script = st['html'].split('R script to reproduce this result')[1]   # shown as text with line breaks, as on Windows
    assert 'loess(model,span=span,degree=degree)' in script and 'hgb &lt;- c(' in script and '<br />' in script and 'returning.to.statsdirect &lt;- TRUE' not in script and 'win.metafile &lt;- function' not in script, script[:300]
    assert text.index('R script to reproduce this result') < text.index('userdir'), 'the script is shown under its heading'
    (fit_title, fit), (se_title, se) = (frame_values(f) for f in st['frames'])
    assert (fit_title, se_title) == ('LOESS fit', 'LOESS fit SE') and [f['placement'] for f in st['frames']] == ['AfterSelection'] * 2 and [f['lengths'] for f in st['frames']] == [[804], [804]], st['frames'][0].keys()
    assert len(fit) == 804 and all(close(fit[i], fits[i]) and close(se[i], ses[i]) for i in range(804))
    print('PASS: the LOESS help example runs through R from the Mac form: its four printed figures, the fits and standard errors written back agree with R called directly; the chart is R\'s SVG inline and the script is shown')

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
    assert '<svg' in st['html'], 'with one predictor the script always draws the scatter, with the fit and band only when asked'
    print('PASS: rows with a missing outcome are left out of the fit and left blank in the written fits, as the R script pads them')

    # Several predictors: the formula names them all, the plot prompts are not asked and no chart is drawn.
    z = [1, 2, 1, 3, 2, 2, 1, 3, 3, 2, 1, 1, 2, 3, 2, 1]
    st, prompts = answer(s, 'LOESS', {'outcome': frame(Hgb=y), 'predictors': frame(eGFR=x, Age=z), 'span': 0.9, 'degree': '1'})
    assert st['state'] == 'complete', st.get('error')
    assert prompts == ['outcome', 'predictors', 'model', 'title', 'span', 'degree', 'saveFitsAndSe', 'saveRScript'], prompts
    stats, _, _ = direct(y, [x, z], span=0.9, degree=1)
    assert close(st['values']['parameters'], stats[1]) and close(st['values']['residualse'], stats[2]) and 'Polynomial degree: 1, Span: 0.9' in re.sub(r'\s+', ' ', re.sub(r'<[^>]+>', ' ', st['html']))
    assert '<svg' not in st['html'] and '<img' not in st['html'] and not st.get('frames')
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
    assert st['state'] == 'failed' and st['error'].startswith('R is not installed. Choose File ▸ New R Script, then Install R…'), st
    print('PASS: without R the form says how to install it')
finally:
    s.finish()

# Method comparison regression runs through R's mcr package, as on Windows (the operation's own script installs the package into
# the program's library when it is missing; the Mac controller answers the definition's precondition with the installed R's version).
# The help example: Deming regression with jackknife intervals of plasma against serum creatinine in 108 subjects, with the test
# against reference plot square (equal axes, the line of identity at 45 degrees) and the difference plot wider, the figures the help
# prints, R called directly through the package for the same, the script shown, and the record of the run for Continue in R.
os.environ.pop('STATSDIRECT_RSCRIPT', None)   # R found again after the section without it
s = Session()
try:
    serum, plasma = column('Serum Creatinine', 'Agreement'), column('Plasma Creatinine', 'Agreement')
    METHODS = ['do.deming.jackknife', 'do.deming.bootstrap', 'do.deming.analytical', 'do.wdeming.jackknife', 'do.wdeming.nestedbootstrap', 'do.paba', 'do.paba.nestedbootstrap', 'do.pabalarge', 'do.pabalarge.nestedbootstrap']
    CHARTS = ['plot.testvsreference', 'plot.modelcomparison', 'plot.bland.altman', 'plot.residuals', 'plot.bias']
    st, prompts = answer(s, 'MethodComparisonRegression', {'testData': frame_answer([plasma]), 'referenceData': frame_answer([serum]),
        'methods': {m: m == 'do.deming.jackknife' for m in METHODS}, 'desired-charts': {c: c in ('plot.testvsreference', 'plot.bland.altman') for c in CHARTS}, 'saveRScript': True})
    assert st['state'] == 'complete', st.get('error')
    assert prompts == ['testData', 'referenceData', 'methods', 'error-ratio', 'seed', 'desired-charts', 'saveRScript'], prompts
    html = st['html']; svgs = re.findall(r'<svg\b[^>]*>', html)
    assert len(svgs) == 2 and html.count('</svg>') == 2 and '<img' not in html and 'data:image/png' not in html, html[:300]
    assert re.search(r"width=['\"]432(\.00)?pt['\"]", svgs[0]) and re.search(r"height=['\"]432(\.00)?pt['\"]", svgs[0]) and 'viewBox' in svgs[0], svgs[0]
    assert re.search(r"width=['\"]432(\.00)?pt['\"]", svgs[1]) and re.search(r"height=['\"]288(\.00)?pt['\"]", svgs[1]), svgs[1]
    text = re.sub(r'\s+', ' ', re.sub(r'<[^>]+>', ' ', html))
    assert 'Test method: Plasma Creatinine' in text and 'Reference method: Serum Creatinine' in text and 'Sample size: 108' in text and 'Error ratio: 1' in text and 'Deming (jackknife CI)' in text, text[:400]
    figures = re.search(r'Slope (\S+) (\S+) (\S+) to (\S+) Proportional differences Intercept (\S+) (\S+) (\S+) to (\S+) Systematic differences', text)
    assert figures and figures.groups() == ('1.054539', '0.024883', '1.005207', '1.103872', '-0.058913', '0.034375', '-0.127066', '0.009239'), figures and figures.groups()   # the help's figures
    # R through the package on the same data: the estimates, standard errors and limits to the six places the report shows
    code = ('suppressPackageStartupMessages(library(mcr)); x <- c(%s); y <- c(%s); m <- mcreg(x, y, error.ratio = 1, alpha = 0.05, method.reg = "Deming", method.ci = "jackknife", na.rm = TRUE);'
            ' cat(sprintf("%%.6f", c(m@para[2, ], m@para[1, ])), "\\n")') % (','.join(repr(float(v)) for v in serum['values']), ','.join(repr(float(v)) for v in plasma['values']))
    direct_figures = subprocess.check_output([rscript(), '--vanilla', '-e', code], text=True, env=R_ENV, stderr=subprocess.DEVNULL).split()[-8:]   # after the package's note on the jackknife
    assert direct_figures == list(figures.groups()), (direct_figures, figures.groups())
    assert 'mcreg(' in html and 'userdir &lt;-' in html and 'R script to reproduce this result' in text, 'the script is shown with the result'
    # the script shown runs again as it is (its run folder is made again by its head, since the program removes it after the run): R prints the
    # package's summary of the Deming fit
    shown = Path(work) / 'shown.R'; shown.write_text(st['values']['formattedRScript'])
    rerun = subprocess.run([rscript(), '--vanilla', str(shown)], text=True, env=R_ENV, capture_output=True, cwd=work)
    assert rerun.returncode == 0 and re.search(r'Slope\s+1\.0545393', rerun.stdout) and 'JACKKNIFE SUMMARY' in rerun.stdout, (rerun.returncode, rerun.stdout[-400:], rerun.stderr[-400:])
    for folder in RUNS.iterdir(): shutil.rmtree(folder)   # the rerun made its run folder again; the program's own runs are gone
    record = json.loads(st['record'])
    assert [i['name'] for i in record['inputs']][:2] == ['testData', 'referenceData'] and record['parameters']['error-ratio'] == 1 and record['parameters']['ci'] == 0.95 and record['parameters']['do.deming.jackknife'] is True and st['recipe'] is True, (record['inputs'][:2], record['parameters'])
    print('PASS: method comparison regression runs through R from the Mac form: the help example gives the help\'s figures and R\'s own, the test against reference plot is square and the difference plot wider, both inline SVG, the script is shown and the run is recorded with its recipe')
    # The form's defaults: Deming with jackknife intervals and Passing-Bablok with bootstrap intervals, each with its test against reference plot;
    # the form offers a fresh seed each time, and a run given the seed of an earlier one repeats its bootstrap intervals
    first, _ = answer(s, 'MethodComparisonRegression', {'testData': frame_answer([plasma]), 'referenceData': frame_answer([serum])})
    second, _ = answer(s, 'MethodComparisonRegression', {'testData': frame_answer([plasma]), 'referenceData': frame_answer([serum]), 'seed': json.loads(first['record'])['parameters']['seed']})
    for st in (first, second):
        assert st['state'] == 'complete', st.get('error')
        text = re.sub(r'\s+', ' ', re.sub(r'<[^>]+>', ' ', st['html']))
        assert 'Deming (jackknife CI)' in text and 'Passing-Bablok (bootstrap CI)' in text and st['html'].count('<svg') == 2 and 'R script to reproduce' not in text, text[:300]
    assert re.sub(r'<svg.*?</svg>', '', first['html'], flags=re.S) == re.sub(r'<svg.*?</svg>', '', second['html'], flags=re.S), 'the bootstrap intervals differ between two runs from the same seed'
    print('PASS: the form\'s default methods, Deming and Passing-Bablok, each give their estimates and plot, and a run repeats from its seed')
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
