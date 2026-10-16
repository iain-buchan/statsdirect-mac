"""Arbitrary Mac chart selections survive saving and Continue in R.

Count actual graphics pages, check the title that R draws, and use values and
labels unrelated to the worked examples (including a histogram with negatives).
"""
import json
import os
import subprocess
import tempfile
from pathlib import Path
from test_menu import ROOT, Session
from r_runtime import rscript


def columns(*items):
    return {'source': 'Selected worksheet', 'columns': [{'title': name, 'values': values} for name, values in items]}


CASES = {
    'BarPlot': {'labels': columns(('Selected categories', ['North', 'South', 'West'])),
                'values': columns(('Trainees', [7, 4, 9]), ('Staff', [3, 5, 2]))},
    'BarPlotFrequency': {'rawValues': columns(('Selected category', ['North', 'West', 'North', 'South', 'South', 'South']),
                                            ('Selected comparison', ['West', 'West', 'North', 'South']))},
    'HistogramPlot': {'data': columns(('Selected difference', [-8, -4, -3, -2, 0, 1, 2, 4, 5, 9]))},
    'NormalPlot': {'X': columns(('Selected pressure', [41, 53, 64, 64, 72, 81, 89, 104, 113, 127]))},
    'SpreadPlot': {'data': columns(('Selected first', [9, 1, 4, 4, 7, 2]), ('Selected second', [8, 3, 6, 5, 2, 1]))},
    'LinePlot': {'n': 1, 'Ynew': columns(('Selected outcome', [2, 7, 4, 8, 6])), 'Xnew': columns(('Selected time', [1, 2, 3, 4, 5]))},
    'ScatterPlot': {'n': 1, 'Ynew': columns(('Selected outcome', [2, 7, 4, 8, 6])), 'Xnew': columns(('Selected time', [1, 2, 3, 4, 5]))},
    'LadderPlot': {'data': columns(('Selected before', [2, 7, 4, 8, 6]), ('Selected after', [3, 5, 8, 10, 7]))},
    'ErrorPlot': {'ydatNew': columns(('Selected mean', [2, 7, 4, 8, 6])), 'xdatNew': columns(('Selected time', [1, 2, 3, 4, 5])),
                  'ydatuNew': columns(('Selected upper', [4, 10, 6, 9, 8])), 'ydatlNew': columns(('Selected lower', [1, 4, 2, 5, 3]))},
    'ControlPlot': {'Y': columns(('Selected process', [10, 12, 11, 15, 13, 12])),
                    'X': columns(('Selected sequence', [11, 12, 14, 17, 21, 28]))},
    'PyramidPlot': {'male': columns(('Selected first population', [10, 17, 8])),
                    'female': columns(('Selected second population', [11, 14, 9])),
                    'labels': columns(('Selected age bands', ['Younger', 'Middle', 'Older']))},
}

# Independent expectations for the actual Mac defaults and selected observations.
# The shared 227-reference suite additionally exercises explicit Windows options.
VALUES = {
    'BarPlot': 'stopifnot(identical(unname(bar_values), rbind(c(7,4,9),c(3,5,2))))',
    'BarPlotFrequency': 'expected <- cbind(c(2,3,1),c(1,1,2)); stopifnot(all(counts==expected), max(abs(frequency_values-prop.table(expected,2)))<1e-12)',
    'HistogramPlot': 'stopifnot(identical(as.numeric(histograms[[1]]$counts),c(2,3,3,2)), histograms[[1]]$n==10)',
    'NormalPlot': 'stopifnot(identical(observed,c(41,53,64,64,72,81,89,104,113,127)), isTRUE(all.equal(normal_scores,qnorm(rank(observed)/11))))',
    'SpreadPlot': 'stopifnot(identical(unname(groups),list(c(1,2,4,4,7,9),c(1,2,3,5,6,8))))',
    'LadderPlot': 'stopifnot(identical(ladder_before,c(2,7,4,8,6)),identical(ladder_after,c(3,5,8,10,7)),identical(ladder_difference,c(-1,2,-4,-2,-1)))',
    'ErrorPlot': 'stopifnot(identical(error_series[[1]]$y,c(2,7,4,8,6)),identical(error_series[[1]]$lower,c(1,4,2,5,3)),identical(error_series[[1]]$upper,c(4,10,6,9,8)))',
    'ControlPlot': 'expected <- c(10,12,11,15,13,12); stopifnot(identical(control_y,expected),identical(control_x,c(11,12,14,17,21,28)),abs(control_mean-mean(expected))<1e-12,abs(control_sd-sd(expected))<1e-12)',
    'PyramidPlot': 'stopifnot(identical(pyramid_males,c(10,17,8)),identical(pyramid_females,c(11,14,9)))',
}

session = Session()
writer = subprocess.Popen([str(ROOT/'Tests/engine-driver'), os.environ.get('STATSDIRECT_TEST_ENGINE', str(ROOT/'FullEngine/publish/StatsDirectEngine.dylib')),
                           'statsdirect_r_script'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
work = Path(tempfile.mkdtemp(prefix='chart-replay-', dir=ROOT/'.build'))
program = [r'''
trace("plot.new", tracer=quote(.pages <<- .pages + 1L), print=FALSE, where=asNamespace("graphics"))
trace("title", tracer=quote({ if (!is.null(main)) { m <- if(is.list(main)) main[[1L]] else main; .titles <<- c(.titles, gsub("[[:space:]]+", " ", paste(m, collapse=" "))) } }), print=FALSE, where=as.environment("package:graphics"))
trace("plot.xy", tracer=quote(.drawn <<- c(.drawn, list(list(type=type,x=xy$x,y=xy$y)))), print=FALSE, where=asNamespace("graphics"))
''']
try:
    for operation, answers in CASES.items():
        title = 'Selected ' + operation + ' result'
        job, state = session.start(operation)
        for _ in range(30):
            if state['state'] != 'input': break
            prompt = state['prompt']; kind = prompt['kind']
            assert not prompt.get('error'), (operation, prompt)
            if prompt.get('name') in answers:
                value = answers[prompt['name']]
            elif kind == 'fields':
                value = {f['name']: f['defaultValue'] for f in prompt['fields']}
                if 'title' in value:
                    value.update(title=title, x='Selected horizontal axis', y='Selected vertical axis')
                if 'bins' in value: value['bins'] = 4
            elif kind == 'options': value = {o['value']: o['selected'] for o in prompt['options']}
            elif prompt.get('skip'): value = {'skip': True}
            elif prompt.get('defaultValue') is not None: value = prompt['defaultValue']
            elif kind == 'boolean': value = False
            else: raise AssertionError((operation, 'unanswered prompt', prompt))
            session.request(action='answer', id=job, token=state['token'], value=value)
            state = session.wait(job)
        assert state['state'] == 'complete', (operation, state)
        assert state['html'].count('<svg') == 1 and 'Chart not drawn' not in state['html'], operation
        assert title in state['html'], (operation, 'native chart lost selected title')
        record = json.loads(state['record'])
        settings = record['parameters']['chartSettings']
        if operation == 'HistogramPlot':
            histogram = settings['histograms'][0]
            assert histogram['title'] == title and histogram['xTitle'] == 'Selected horizontal axis', histogram
            assert histogram['counts'] == [2, 3, 3, 2], histogram
            assert len(histogram['edges']) == 5 and histogram['edges'][0] == -8 and histogram['edges'][-1] == 9, histogram
        else:
            assert settings['title'] == title, settings
        writer.stdin.write(json.dumps({'record': json.loads(json.dumps(record)), 'frames': []}) + '\n'); writer.stdin.flush()
        reply = json.loads(writer.stdout.readline())
        assert reply.get('hasRecipe') and not reply.get('dataUnavailable'), reply
        path = work/(operation + '.R'); path.write_text(reply['text'])
        program.extend([
            '.pages <- 0L; .titles <- character(); .drawn <- list(); grDevices::pdf(' + json.dumps(str(work/(operation + '.pdf'))) + ')',
            'local({source(' + json.dumps(str(path)) + ', local=TRUE); ' + VALUES.get(operation, '') + '}); grDevices::dev.off()',
            'stopifnot(.pages == 1L, ' + json.dumps(title) + ' %in% .titles)',
            'cat(' + json.dumps('PASS: ' + operation + ' replays one chart with the selected title\n') + ')',
        ])
        if operation in ('LinePlot', 'ScatterPlot'):
            program.append('matches <- vapply(.drawn, function(d) isTRUE(all.equal(as.numeric(d$x), c(1,2,3,4,5))) && isTRUE(all.equal(as.numeric(d$y), c(2,7,4,8,6))) && d$type %in% c(' + ('"l","b","o"' if operation == 'LinePlot' else '"p","b","o"') + '), logical(1)); stopifnot(any(matches))')
        session.close(job)
    path = work/'run.R'; path.write_text('\n'.join(program))
    run = subprocess.run([rscript(), '--vanilla', str(path)], cwd=work, capture_output=True, text=True, timeout=120)
    print(run.stdout, end='', flush=True)
    assert run.returncode == 0, run.stderr
    assert len(list(work.glob('*.pdf'))) == len(CASES)
    print('PASS:', len(CASES), 'Mac chart forms preserve chosen data and titles through saved-record R/PDF replay', flush=True)
finally:
    session.finish()
    writer.stdin.close(); writer.wait()
