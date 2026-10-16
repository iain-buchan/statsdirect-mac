"""Mac chart-options contract, through real engine prompts and report output.

Exercises every method/orientation/fence choice, custom labels and axis limits,
validation retries, independent forms, cancellation and text-chart compatibility.
Shared record/Continue in R assertions are below these Mac-specific checks.
"""
import json, re, os, subprocess, tempfile, hashlib
from pathlib import Path
from r_runtime import rscript
from test_menu import ROOT
from test_menu import Session, columns

s = Session()
data = columns([1, 2, 3, 4, 5, 6, 7, 8, 20], [2, 3, 4, 5, 6])

def answer(job, state, value):
    reply = s.request(action='answer', id=job, token=state['token'], value=value)
    assert not reply.get('error'), reply
    return s.wait(job)

def form(operation='BoxWhiskerPlot', preferences=None):
    job, state = s.start(operation, preferences)
    state = answer(job, state, data)
    assert state['prompt']['kind'] == 'fields', state
    defaults = {f['name']: f['defaultValue'] for f in state['prompt']['fields']}
    return job, state, defaults

try:
    results = []
    for method in range(1, 7):
        for orientation in ('Horizontal', 'Vertical'):
            for inner, outer in ((False, False), (True, False), (False, True), (True, True)):
                job, state, a = form()
                assert a['confidence'] == 95
                a.update(method=str(method), orientation=orientation, innerFence=inner, outerFence=outer,
                         markMeanAndMedian=True, title='Measurements <1> & 2', automaticAxisTitle=False,
                         x='Measurement units', series0='First group', series1='Second group')
                result = answer(job, state, a)
                assert result['state'] == 'complete', result
                html = result['html']
                assert html.count('<svg') == 1 and 'Chart not drawn' not in html, html
                assert 'Measurements &lt;1&gt; &amp; 2' in html and 'Measurement units' in html, html
                assert 'First group' in html and 'Second group' in html, html
                results.append((a, result))
                s.close(job)
    print('PASS: 48 box plots cover all six methods, both orientations and four fence combinations with mean/median and custom labels', flush=True)

    first, state, a = form(preferences={'default-ci':'99'})
    assert a['confidence'] == 99
    second, other, b = form()
    assert b['confidence'] == 95
    a.update(method='3', confidence=100, title='Retain this title')
    bad = answer(first, state, a)
    assert bad['state'] == 'input' and 'Confidence' in bad['prompt']['error'] and bad['prompt']['initial']['title'] == a['title']
    for change in ({'confidence':99, 'minimum':10, 'maximum':1}, {'minimum':1,'maximum':''}, {'minimum':'NaN','maximum':10}, {'minimum':'','maximum':'','method':'99'}):
        a.update(change); bad = answer(first, bad, a)
        assert bad['state'] == 'input' and bad['prompt']['error'] and bad['prompt']['initial'] == a, bad
    a.update(method='3', minimum=0, maximum=25, confidence=99, valueGrid=True, valueMarker=10, boxAxes=True)
    complete = answer(first, bad, a)
    assert complete['state'] == 'complete' and '99%' in complete['html'], complete
    assert s.request(action='poll', id=second)['token'] == other['token']
    s.close(first); s.close(second)
    job, state, a = form()
    assert a['title'] != 'Retain this title' and a['confidence'] == 95
    s.close(job)
    print('PASS: saved confidence, validation and retained edits, explicit axes, independent forms and cancellation/reopen', flush=True)

    job, state, a = form('BoxWhiskerPlotText')
    assert set(a) == {'title', 'x', 'y'}  # graphical recipe/options are separate from the existing text chart
    result = answer(job, state, a)
    assert result['state'] == 'complete' and '<pre>' in result['html'] and 'Chart not drawn' not in result['html'], result
    s.close(job)
    print('PASS: existing text box plot remains available unchanged', flush=True)

    # The original reported problem: only Michelson, not neighbouring worksheet data.
    import openpyxl
    workbook = openpyxl.load_workbook(ROOT / 'Content/Examples/test.xlsx', read_only=True, data_only=True)
    sheet = workbook['Parametric']; rows = list(sheet.values); index = list(rows[0]).index('Michelson')
    michelson = [r[index] for r in rows[1:] if r[index] is not None]
    assert len(michelson) == 100
    job, state = s.start('BoxWhiskerPlot')
    state = answer(job, state, {'source':'test.xlsx / Parametric', 'columns':[{'title':'Michelson','values':michelson}]})
    a = {f['name']:f['defaultValue'] for f in state['prompt']['fields']}
    a.update(title='Michelson selected data', method='3', confidence=99, minimum=299.5, maximum=300.2, boxAxes=True, valueGrid=True, valueMarker=299.8)
    result = answer(job, state, a); assert result['state'] == 'complete', result
    results.append((a,result)); s.close(job); workbook.close()

    values = list(range(5001, 0, -1))
    frame = {'title':'Descending', 'values':values}
    worksheet = {'source':'Big.xlsx / Data', 'columns':[frame], 'range':{'firstRow':2,'lastRow':5002,'columns':[0]},
                 'worksheet':{'workbook':'Big.xlsx','workbookPath':'/tmp/Big.xlsx','sheet':0,'sheetName':'Data','hasTitle':True,'titles':['Descending']}}
    job, state = s.start('BoxWhiskerPlot'); state = answer(job, state, worksheet)
    a = {f['name']:f['defaultValue'] for f in state['prompt']['fields']}
    result = answer(job, state, a); assert result['state'] == 'complete', result
    record = json.loads(result['record'])
    expected_hash = hashlib.sha256('\n'.join(map(str,values)).encode()).hexdigest()[:16]
    assert record['inputs'][0]['columns'][0]['hash'] == expected_hash, 'opening chart options must not sort the values before hashing the selected worksheet'
    result['_testFrames'] = [{'name':'data','columns':[frame]}]
    results.append((a,result)); s.close(job)
finally:
    s.finish()

# Saved records go through the real shared script writer, then R's PDF device.
# Counting plot.new calls checks actual plotted pages, not occurrences of code.
writer = subprocess.Popen([str(ROOT/'Tests/engine-driver'), str(ROOT/'FullEngine/publish/StatsDirectEngine.dylib'), 'statsdirect_r_script'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
work = Path(tempfile.mkdtemp(prefix='box-whisker-', dir=ROOT/'.build'))
runs = ['trace("plot.new", tracer=quote(.box_pages <<- .box_pages + 1L), print=FALSE, where=asNamespace("graphics"))']
try:
    for i, (a, result) in enumerate(results):
        record = json.loads(result['record']); settings = record['parameters']['boxWhisker']
        assert settings['method'] == int(a['method']) and settings['horizontal'] == (a['orientation']=='Horizontal'), settings
        assert settings['innerFence'] == a['innerFence'] and settings['outerFence'] == a['outerFence'] and settings['markMeanAndMedian'] == a['markMeanAndMedian'], settings
        assert settings['title'] == a['title'] and settings['confidence'] == (a['confidence']/100 if a['method']=='3' else .95), settings
        if not a['automaticAxisTitle']: assert settings['axisTitle'] == a['x']
        assert settings['seriesTitles'] == [a['series'+str(n)] for n in range(len(settings['seriesTitles']))]
        if i == 48:
            assert record['inputs'][0]['columns'] == [{'title':'Michelson','values':michelson}]
            assert settings['boxAxes'] and settings['valueGrid'] and settings['valueMarker']==299.8
            assert settings['valueMinimum'] <= 299.5 and settings['valueMaximum'] >= 300.2
        # JSON round trip mirrors reopening a saved report.
        writer.stdin.write(json.dumps({'record':json.loads(json.dumps(record)), 'frames':result.get('_testFrames',[])})+'\n'); writer.stdin.flush()
        reply = json.loads(writer.stdout.readline()); assert reply['hasRecipe'] and not reply['dataUnavailable'], reply
        script = reply['text']; assert 'has changed in the workbook' not in script
        assert 'box_settings <- list(' in script and 'Number of metastases' not in script
        path = work/f'case-{i}.R'; path.write_text(script)
        runs.append('.box_pages <- 0L; grDevices::pdf('+json.dumps(str(work/f'case-{i}.pdf'))+')')
        runs.append('local({ source('+json.dumps(str(path))+', local=TRUE) }); grDevices::dev.off(); stopifnot(.box_pages == 1L)')
    script = work/'run.R'; script.write_text('\n'.join(runs))
    run = subprocess.run([rscript(),'--vanilla',str(script)], cwd=work, text=True, capture_output=True, timeout=120)
    assert run.returncode == 0, (run.stdout,run.stderr)
    assert len(list(work.glob('case-*.pdf'))) == len(results)
    print('PASS: 50 saved engine records preserve selected inputs/settings and each generated R script draws exactly one PDF page, including Michelson and an unchanged 5001-row worksheet', flush=True)
finally:
    writer.stdin.close(); writer.wait()
