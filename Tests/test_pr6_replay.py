"""Actual Mac-host/R regressions for the 5.3.7 record and replay contract (Windows PR #6 with the deferred fixes).

Prepared by Codex against PR #6 (its Mac review comments on iain-buchan/statsdirect#6) and adapted to the
released v5.3.7: a run embeds its values by the observations it holds, not the cells it selected
(tests/RScript/RecordPadding.cs expectedHeld). Run --baseline once before integrating the verified upstream target. The mapped
origin test is skipped there because 5.3.5 has no DataRowIndices API. Padding
fixtures use genuinely blank worksheet cells; they make no assertion that an
explicitly entered missing observation may be removed from independent data.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import uuid

from r_runtime import rscript
from test_menu import ROOT, Session, columns


BASELINE = '--baseline' in sys.argv
sys.argv = [arg for arg in sys.argv if arg != '--baseline']
PREFS = {'use-default-ci': True, 'default-ci': '95', 'decp': '12', 'pdecp': '7'}
BEFORE = [312, 242, 340, 388, 296, 254, 391, 402, 290]
AFTER = [300, 201, 232, 312, 220, 256, 328, 330, 231]
STAGGERED = [[10, None, 15, 77, 21, 24, None, 30, None, None],
             [9, 55, 12, None, 17, 20, None, 25, 66, None]]


def sheet(titles, values):
    assert len(titles) == len(values) and len({len(v) for v in values}) == 1
    return {'source': 'Replay.xlsx / Data', 'preserveRows': True,
            'columns': [{'title': title, 'values': list(v)} for title, v in zip(titles, values)],
            'range': {'firstRow': 2, 'lastRow': len(values[0]) + 1, 'columns': list(range(len(titles)))},
            'worksheet': {'workbook': 'Replay.xlsx', 'workbookPath': '/tmp/Replay.xlsx',
                          'sheet': 0, 'sheetName': 'Data', 'hasTitle': True, 'titles': titles}}


def acquisition(record, name='data'):
    return next(item for item in record['inputs'] if item['name'] == name)


def digest(values):
    return hashlib.sha256('\n'.join('' if v is None else str(v) for v in values).encode()).hexdigest()[:16]


def vector(values):
    return 'c(' + ','.join('NA' if v is None else format(v, '.17g') for v in values) + ')'


class RWriter:
    def __init__(self):
        self.process = subprocess.Popen([
            str(ROOT / 'Tests/engine-driver'),
            os.environ.get('STATSDIRECT_TEST_ENGINE', str(ROOT / 'FullEngine/publish/StatsDirectEngine.dylib')),
            'statsdirect_r_script'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)

    def write(self, record, frames=()):
        self.process.stdin.write(json.dumps({'record': record, 'frames': list(frames)}) + '\n')
        self.process.stdin.flush()
        result = json.loads(self.process.stdout.readline())
        assert result.get('hasRecipe') and not result.get('dataUnavailable'), result
        assert not result.get('relocate') and 'has changed in the workbook' not in result['text'], result
        return result

    def close(self):
        self.process.stdin.close()
        assert self.process.wait(timeout=15) == 0


def run_r(script, assertions, plot_count=None):
    with tempfile.TemporaryDirectory(prefix='pr6-replay-', dir=ROOT / '.build') as folder:
        prefix = ''
        if plot_count is not None:
            # The base PDF device needs no optional Cairo/X11 installation.
            # This suite checks numerical/plot semantics; native report SVG is
            # asserted separately, without adding a graphics codec dependency.
            prefix = '''pdf("agreement.pdf")
plot_count <- 0L
plot <- function(x,y,...) {
  plot_count <<- plot_count+1L
  plotted <<- list(x=x,y=y,...)
  graphics::plot(x,y,...)
}
'''
        code = prefix + script + '\n' + assertions
        if plot_count is not None:
            code += '\nstopifnot(plot_count == ' + str(plot_count) + 'L)\ndev.off()\n'
        code += '\ncat("PR6_REPLAY_OK\\n")\n'
        path = Path(folder) / 'replay.R'
        path.write_text(code)
        result = subprocess.run([rscript(), '--vanilla', str(path)], cwd=folder,
                                text=True, capture_output=True, timeout=60)
        assert result.returncode == 0 and 'PR6_REPLAY_OK' in result.stdout, (result.stdout, result.stderr)
        if plot_count:
            assert (Path(folder) / 'agreement.pdf').read_bytes().startswith(b'%PDF-')


def paired_assertions(native, expected_before, expected_after=None):
    keys = ['n', 'mean', 'sd', 'sem', 'df', 't', 'tail_2', 'from', 'to']
    expected = [native['values'][key] for key in keys]
    differences = expected_before if expected_after is None else [x-y for x, y in zip(expected_before, expected_after)]
    code = '''
actual <- c(n,mean(d),sd(d),sd(d)/sqrt(n),unname(r$parameter),unname(r$statistic),r$p.value,r$conf.int[1:2])
stopifnot(isTRUE(all.equal(actual, EXPECTED, tolerance=2e-9, check.attributes=FALSE)))
stopifnot(identical(as.numeric(d), DIFFERENCES))
expected_power <- power.t.test(n=length(d),delta=mean(d),sd=sd(d),sig.level=1-confidence,type="paired",strict=TRUE)$power
stopifnot(isTRUE(all.equal(pw$power,expected_power,tolerance=1e-10)))
'''.replace('EXPECTED', vector(expected)).replace('DIFFERENCES', vector(differences))
    power = native['values']['pwr']
    number = re.search(r'= ([0-9.]+)%', power)
    if number:
        code += 'stopifnot(abs(100*pw$power-' + number[1] + ') < 0.0051)\n'
    elif '> 99.99%' in power:
        code += 'stopifnot(pw$power > .9999)\n'
    elif '< 0.01%' in power:
        code += 'stopifnot(pw$power < .0001)\n'
    else:
        raise AssertionError(('unrecognised native power', power))
    if expected_after is not None:
        code += 'stopifnot(identical(as.numeric(before),' + vector(expected_before) + '),identical(as.numeric(after),' + vector(expected_after) + '))\n'
    return code


def padded_pairs(session, writer, selected):
    source = sheet(['Selected before', 'Selected after'],
                   [BEFORE + [''] * (selected-len(BEFORE)), AFTER + [''] * (selected-len(AFTER))])
    result = session.run('TPaired', {'data': source, 'doAgreement': True}, PREFS)
    assert '<svg' in result['html'], 'native agreement report lost its SVG chart'
    record = json.loads(result['record'])
    pointer = acquisition(record)
    assert all(c['rows'] == [1, 10] for c in pointer['columns']), ('blank padding bounds', [c['rows'] for c in pointer['columns']])
    assert [c['hash'] for c in pointer['columns']] == [digest(BEFORE), digest(AFTER)], pointer
    held = len(BEFORE) + len(AFTER) <= 5000   # 5.3.7 embeds by the observations held, not the cells selected (RecordPadding.cs expectedHeld)
    assert ('data' in record) == held, ('embedding threshold', selected, held)
    if held:
        assert list(record['data']['data'].values()) == [BEFORE, AFTER]
    frames = [{'name': 'data', 'columns': [{'title': title, 'values': values}
               for title, values in zip(['Selected before', 'Selected after'], [BEFORE, AFTER])]}]
    replay = writer.write(record, frames)
    assert replay['asked'] == ([] if held else ['data']), replay['asked']
    run_r(replay['text'], paired_assertions(result, BEFORE, AFTER), plot_count=1)


def large_real_sample(session, writer):
    x = list(range(1, 3002))
    y = [v - (1 if i % 2 else 3) for i, v in enumerate(x)]
    source = sheet(['Selected before', 'Selected after'], [x + [''] * 1099, y + [''] * 1099])
    result = session.run('TPaired', {'data': source, 'doAgreement': False}, PREFS)
    record = json.loads(result['record'])
    pointer = acquisition(record)
    assert 'data' not in record and all(c['rows'] == [1, 3002] for c in pointer['columns']), pointer
    assert [c['hash'] for c in pointer['columns']] == [digest(x), digest(y)], pointer
    frames = [{'name': 'data', 'columns': [{'title': 'Selected before', 'values': x}, {'title': 'Selected after', 'values': y}]}]
    replay = writer.write(record, frames)
    assert replay['asked'] == ['data'], replay['asked']
    run_r(replay['text'], paired_assertions(result, x, y) + '\nstopifnot(n==3001L,tail(before,1)==3001)\n', plot_count=0)


def managed(session, code):
    ident = str(uuid.uuid4())
    try:
        response = session.request(action='start', id=ident, operation='UserScript', language='CSharp', script=code)
        assert not response.get('error'), response
        state = session.wait(ident)
        assert state['state'] == 'complete', (state['state'], state.get('error'), state.get('console'))
        return {line.split(' ', 1)[0]: json.loads(line.split(' ', 1)[1])
                for line in state['console'].splitlines() if ' ' in line}
    finally:
        session.close(ident)


def immutable_acquisition(session):
    records = managed(session, r'''
double[] a=Enumerable.Repeat(Constant.MISSING,3000).ToArray();
double[] b=Enumerable.Repeat(Constant.MISSING,3000).ToArray();
Array.Copy(new double[]{1,2,3},a,3);Array.Copy(new double[]{4,5,6,7,8},b,5);
var originA=new WorksheetOrigin("/tmp/Replay.xlsx","Original",0,0,3001,DataAcquisitionMode.NumericPreserveRows,true,false,1);
var originB=new WorksheetOrigin("/tmp/Replay.xlsx","Original",1,0,3001,DataAcquisitionMode.NumericPreserveRows,true,false,1);
var frame=new DataFrame();frame.Variables.Add(new DoubleVariable(a,"Before"){Origin=originA});frame.Variables.Add(new DoubleVariable(b,"After"){Origin=originB});
var bag=new ParameterBag();bag.AddInput("data",frame);
var operation=new Operation{Name="TPaired"};var acquired=new OperationRun(operation);
acquired.Note(new FrameParameter{Name="data"},"Selected pairs",value:bag["data"]);
Array.Fill(a,999.0);Array.Fill(b,999.0);frame.Variables[0].Title="Later title";originA.WorksheetName="Later sheet";
string first=RunRecord.Write(acquired,bag);
var inherited=new OperationRun(operation,bag);
Array.Fill(a,888.0);Array.Fill(b,888.0);originB.Rows=999;
Console.WriteLine("ACQUIRED "+first);Console.WriteLine("INHERITED "+RunRecord.Write(inherited,bag));
''')
    for name in ('ACQUIRED', 'INHERITED'):
        record = records[name]
        pointer = acquisition(record)
        assert pointer['sheet'] == 'Original' and [c['title'] for c in pointer['columns']] == ['Before', 'After'], pointer
        assert all(c['rows'] == [1, 6] for c in pointer['columns']), (name, pointer)
        assert [c['hash'] for c in pointer['columns']] == [digest([1, 2, 3, None, None]), digest([4, 5, 6, 7, 8])], (name, pointer)
        # 5.3.7 embeds by the observations held (eight here, of 6,000 cells selected); the held values are the acquisition's, untouched by
        # the later edits to the arrays, titles, sheet and row counts
        assert record.get('data', {}).get('data') == {'Before': [1, 2, 3, None, None], 'After': [4, 5, 6, 7, 8]}, (name, 'held values', record.get('data'))
        assert bool(pointer.get('inherited')) == (name == 'INHERITED'), pointer


def mapped_origin(session):
    # This is the shared engine's public scripting contract. Mac's grid does
    # not skip hidden rows and this does not invent a front-end row-map field.
    records = managed(session, r'''
int[] rows={1,3,4,5,6};double m=Constant.MISSING;
DataFrame Frame(bool mapped) {
  var a=new WorksheetOrigin("/tmp/Replay.xlsx","Mapped",0,0,7,DataAcquisitionMode.NumericPreserveRows,true,true,1);
  var b=new WorksheetOrigin("/tmp/Replay.xlsx","Mapped",1,0,7,DataAcquisitionMode.NumericPreserveRows,true,true,1);
  if(mapped){a.DataRowIndices=rows;b.DataRowIndices=rows;}
  var frame=new DataFrame();frame.Variables.Add(new DoubleVariable(new[]{10.0,30,40,m,m},"Before"){Origin=a});frame.Variables.Add(new DoubleVariable(new[]{11.0,32,43,m,m},"After"){Origin=b});return frame;
}
var bag=new ParameterBag();bag.AddInput("data",Frame(true));
var operation=new Operation{Name="TPaired"};var acquired=new OperationRun(operation);
acquired.Note(new FrameParameter{Name="data"},"Mapped pairs",value:bag["data"]);
rows[2]=999;
Console.WriteLine("MAPPED "+RunRecord.Write(acquired,bag,0));
var legacyBag=new ParameterBag();legacyBag.AddInput("data",Frame(false));
var legacy=new OperationRun(operation);legacy.Note(new FrameParameter{Name="data"},"Legacy pairs",value:legacyBag["data"]);
Console.WriteLine("LEGACY "+RunRecord.Write(legacy,legacyBag,0));
''')
    mapped = acquisition(records['MAPPED'])
    assert all(c['rows'] == [1, 5] for c in mapped['columns']), mapped
    assert [c['hash'] for c in mapped['columns']] == [digest([10, 30, 40]), digest([11, 32, 43])], mapped
    legacy = acquisition(records['LEGACY'])
    assert all(c['rows'] == [1, 7] for c in legacy['columns']), legacy


def paired_missing(session, writer, agreement, confidence=95, legacy=False, single=False, complete=False):
    values = [[1, None, 3, 4, 4, None, 5]] if single else ([[10, 15, 21, 24, 30], [9, 12, 17, 20, 25]] if complete else STAGGERED)
    answer = columns(*values)
    for c, title in zip(answer['columns'], ['Selected before', 'Selected after']):
        c['title'] = title
    result = session.run('TPaired', {'data': answer, 'doAgreement': agreement}, {**PREFS, 'default-ci': str(confidence)})
    if agreement and not single:
        assert '<svg' in result['html'], 'native agreement report lost its SVG chart'
    assert result['values']['n'] == 5 and result['values']['pc'] == confidence, result['values']
    record = json.loads(result['record'])
    if legacy:
        record['parameters'].pop('doAgreement', None)
    script = writer.write(record)
    before, after = ([1, 3, 4, 4, 5], None) if single else ([10, 15, 21, 24, 30], [9, 12, 17, 20, 25])
    assertions = paired_assertions(result, before, after)
    expected_plot = not single and (agreement or legacy)
    if expected_plot:
        assertions += '''
stopifnot(identical(as.numeric(plotted$x),(before+after)/2),identical(as.numeric(plotted$y),d),
          identical(plotted$xlab,"Mean ((Selected before + Selected after) / 2)"),
          identical(plotted$ylab,"Difference (Selected before - Selected after)"),
          isTRUE(all.equal(loa,mean(d)+c(-1,1)*qnorm((1+confidence)/2)*sd(d))))
'''
    else:
        assertions += '\nstopifnot(!exists("loa"))\n'
    run_r(script['text'], assertions, plot_count=int(expected_plot))


def sparse_independent(session, writer):
    raw = [1, '', '', 2, '', 3, '', '', 4, '', 5, '']
    result = session.run('HistogramPlot', {'data': sheet(['Sparse observations'], [raw])}, PREFS)
    record = json.loads(result['record'])
    pointer = acquisition(record)
    assert pointer['mode'] == 'NumericSkipMissing', pointer
    assert pointer['columns'][0]['hash'] == digest([1, 2, 3, 4, 5]), pointer
    held = writer.write(record)
    run_r(held['text'], 'stopifnot(identical(as.numeric(series[[1]]),c(1,2,3,4,5)))')
    # The last value is at physical worksheet row12, not logical row6. Read
    # exactly the saved bounds, as the real worksheet reader does.
    assert pointer['columns'][0]['rows'][1] >= 12, pointer
    record.pop('data', None)
    last = pointer['columns'][0]['rows'][1] - 1
    replay = writer.write(record, [{'name': 'data', 'columns': [{'title': 'Sparse observations', 'values': raw[:last]}]}])
    assert replay['asked'] == ['data'], replay['asked']
    run_r(replay['text'], 'stopifnot(identical(as.numeric(series[[1]]),c(1,2,3,4,5)))')


def mixed_entered_and_worksheet(session, writer):
    x = list(range(1, 10)) + [''] * 11
    y = [3 + 2 * i + (i % 3) / 10 for i in range(1, 21)]
    entered = columns(y)
    entered['columns'][0]['title'] = 'Typed outcome'
    source = sheet(['Worksheet predictor'], [x])
    model = session.run('MultipleLinearRegression', {
        'outcome': entered, 'predictors': source,
        'calculateIntercept': True, 'useWeights': False,
    }, PREFS, keep=True)
    try:
        record = json.loads(model['record'])
        outcome = acquisition(record, 'outcome')
        assert outcome['kind'] == 'entered' and outcome['columns'][0]['values'] == y, outcome
        pointer = acquisition(record, 'predictors')
        assert pointer['kind'] == 'frame', pointer
        anova = session.run('MultipleLinearRegressionAnova', {}, PREFS, parent=model['id'])
        assert anova['values']['tot_df'] == 8, anova['values']
        plain = re.sub(r'<[^>]+>', ' ', model['html'])
        coefficients = [float(value) for _, value in re.findall(r'\bb(\d+)\s*=\s*([-+0-9.Ee]+)', plain)]
        assert len(coefficients) == 2, plain
        assertions = '\nstopifnot(nobs(fit)==9L,isTRUE(all.equal(unname(coef(fit)),' + vector(coefficients) + ',tolerance=2e-9)))\n'
        assertions += 'stopifnot(identical(as.numeric(model.response(model.frame(fit))),' + vector(y[:9]) + '))\n'
        held = writer.write(record)
        run_r(held['text'], assertions)
        record.pop('data', None)
        last = pointer['columns'][0]['rows'][1] - 1
        replay = writer.write(record, [{'name': 'predictors', 'columns': [
            {'title': 'Worksheet predictor', 'values': x[:last]}]}])
        assert replay['asked'] == ['predictors'], replay['asked']
        run_r(replay['text'], assertions)
    finally:
        session.close(model['id'])


if __name__ == '__main__':
    session, writer = Session(), RWriter()
    cases = [
        ('paired blank padding at 5000-value boundary', lambda: padded_pairs(session, writer, 2500)),
        ('paired blank padding above 5000-value boundary', lambda: padded_pairs(session, writer, 2501)),
        ('paired blank padding far above the boundary, as RecordPadding.cs selects it', lambda: padded_pairs(session, writer, 10000)),
        ('large actual sample retains its last pair', lambda: large_real_sample(session, writer)),
        ('immutable acquisition prefix and inherited snapshot', lambda: immutable_acquisition(session)),
        ('paired staggered missing data, agreement false', lambda: paired_missing(session, writer, False)),
        ('paired staggered missing data, agreement true', lambda: paired_missing(session, writer, True)),
        ('legacy absent agreement option keeps prior chart default', lambda: paired_missing(session, writer, True, legacy=True)),
        ('one-column paired differences with missing data and 80% CI', lambda: paired_missing(session, writer, False, confidence=80, single=True)),
        ('paired power uses selected 80% CI', lambda: paired_missing(session, writer, False, confidence=80, complete=True)),
        ('independent compacted observations retain physical read range', lambda: sparse_independent(session, writer)),
        ('mixed entered outcome and worksheet predictor stay aligned', lambda: mixed_entered_and_worksheet(session, writer)),
    ]
    if BASELINE:
        print('SKIP: mapped-origin API is absent from the old-engine baseline', flush=True)
    else:
        cases.append(('mapped physical bounds and legacy unmapped origins', lambda: mapped_origin(session)))
    failures = []
    try:
        for label, check in cases:
            try:
                check()
                print('PASS:', label, flush=True)
            except Exception as error:
                failures.append(label)
                print('FAIL:', label, str(error)[:4000], flush=True)
    finally:
        writer.close()
        session.finish()
    print(f'PR6 REPLAY: {len(cases)-len(failures)} passed, {len(failures)} failed', flush=True)
    raise SystemExit(1 if failures else 0)
