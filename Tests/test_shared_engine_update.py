"""Focused 5.3.5 regressions through the Mac operation host, with base-R oracles.

Fixtures mirror the verified upstream PairwiseDifferencesChecks,
MixedSelectionChecks and LogisticStackingChecks at 3de5558. They exercise actual
worksheet answers and follow-on operations rather than calling builtins directly.
"""
from html.parser import HTMLParser
import hashlib
import json
import math
import os
import re
import subprocess

from r_runtime import rscript
from test_menu import ROOT, Session, columns


PREFERENCES = {'decp': '12', 'pdecp': '7', 'use-default-ci': True, 'default-ci': '95'}
NUMBER = r'[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[Ee][-+]?\d+)?'


def worksheet(title, values):
    """The ordinary Mac worksheet bridge retains the selected physical rows."""
    answer = columns(values)
    answer['columns'][0]['title'] = title
    answer['preserveRows'] = True
    return answer


def recorded_worksheet(titles, values):
    """Deliberately omit preserveRows: the operation's acquisition mode must align."""
    assert titles and len(titles) == len(values) and len({len(v) for v in values}) == 1
    return {
        'source': 'Shared-engine-update.xlsx / Data',
        'columns': [{'title': title, 'values': list(column)} for title, column in zip(titles, values)],
        'range': {'firstRow': 2, 'lastRow': len(values[0]) + 1, 'columns': list(range(len(titles)))},
        'worksheet': {'workbook': 'Shared-engine-update.xlsx',
                      'workbookPath': '/tmp/Shared-engine-update.xlsx',
                      'sheet': 0, 'sheetName': 'Data', 'hasTitle': True, 'titles': titles},
    }


def value_hash(values):
    return hashlib.sha256('\n'.join('' if v is None else str(v) for v in values).encode()).hexdigest()[:16]


def r_vector(text, name):
    match = re.search(r'^' + re.escape(name) + r' <- c\(', text, re.M)
    assert match, (name, text)
    # Read complete quoted tokens before interpreting commas or parentheses;
    # both are legitimate characters in worksheet labels.
    token = re.compile(r'\s*("(?:\\.|[^"\\])*"|NA|' + NUMBER + r')\s*([,)])')
    position, values = match.end(), []
    while True:
        item = token.match(text, position)
        assert item, (name, text[position:position + 120])
        value = item[1]
        values.append(None if value == 'NA' else json.loads(value) if value.startswith('"') else float(value))
        if item[2] == ')':
            return values
        position = item.end()


def compare(actual, expected, label, tolerance=2e-8):
    assert len(actual) == len(expected), (label, actual, expected)
    for got, want in zip(actual, expected):
        assert math.isfinite(got) and math.isclose(got, want, rel_tol=tolerance,
                                                   abs_tol=tolerance * 1e-4), (label, got, want)


def output_columns(result, expected_lengths):
    """Reconstruct by coordinates: omitted missing cells must not compact rows."""
    assert len(result['frames']) == 1, result['frames']
    frame = result['frames'][0]
    assert frame['lengths'] == expected_lengths, frame
    assert frame['columns'] == len(expected_lengths), frame
    assert frame['rows'] == max(expected_lengths) + 1 and frame['headerRow'], frame
    cells = {}
    for cell in frame['cells']:
        position = (cell['col'], cell['row'])
        assert position not in cells, ('duplicate output coordinate', cell)
        assert 0 <= cell['col'] < len(expected_lengths), cell
        assert 0 <= cell['row'] <= expected_lengths[cell['col']], cell
        cells[position] = cell
    return [[float(cells[(col, row)]['text']) if (col, row) in cells else None
             for row in range(1, length + 1)]
            for col, length in enumerate(expected_lengths)]


class ReportText(HTMLParser):
    def __init__(self, source):
        super().__init__()
        self.parts = []
        self.rows = []
        self.row = None
        self.cell = None
        self.feed(source)
        self.text = ' '.join(' '.join(self.parts).split())

    def handle_starttag(self, tag, attrs):
        if tag == 'tr':
            self.row = []
        elif tag in ('td', 'th'):
            self.cell = []

    def handle_data(self, value):
        self.parts.append(value)
        if self.cell is not None:
            self.cell.append(value)

    def handle_endtag(self, tag):
        if tag in ('td', 'th') and self.cell is not None:
            assert self.row is not None
            self.row.append(' '.join(' '.join(self.cell).split()))
            self.cell = None
        elif tag == 'tr' and self.row is not None:
            self.rows.append(self.row)
            self.row = None


def r_references():
    # Complete cases must be removed BEFORE stacking equal covariate patterns.
    # Individual-row glm has the same coefficients but a different deviance.
    code = '''
options(digits=17)
emit <- function(name, values) cat(name, sprintf("%.17g", values), "\\n")
emit("differences_2x3", as.vector(t(outer(c(1,3), c(10,20,30), "-"))))
emit("differences_3x2", as.vector(t(outer(c(1,2,3), c(10,30), "-"))))
emit("differences_edges", as.vector(t(outer(c(1,3), c(10,30,40), "-"))))
y <- c(1,3,5)
walsh <- outer(y,y,"+")/2
emit("walsh", unlist(lapply(seq_along(y), function(i) walsh[i,i:length(y)])))
x <- c(1,1,1,1,2); y <- c(10,20,30,40,50)
pairs <- combn(seq_along(x),2)
eligible <- pairs[,x[pairs[1,]] != x[pairs[2,]],drop=FALSE]
emit("tied_slopes", (y[eligible[2,]]-y[eligible[1,]])/(x[eligible[2,]]-x[eligible[1,]]))
group <- factor(c("A","B",NA,"B","A"), levels=c("A","B"))
fit <- lm(c(1,2,20,2,1) ~ group)
emit("categorical", c(nobs(fit), unname(coef(fit))))
base <- data.frame(x=0:4, response=c(5,8,11,14,16), total=rep(20,5), prior=1)
incomplete <- data.frame(x=0, response=3, total=NA_real_, prior=1)
for (name in c("base", "before", "after")) {
  raw <- switch(name, base=base, before=rbind(incomplete,base), after=rbind(base,incomplete))
  complete <- raw[complete.cases(raw),,drop=FALSE]
  stacked <- aggregate(cbind(response,total) ~ x+prior, data=complete, FUN=sum)
  fit <- glm(cbind(response,total-response) ~ x, data=stacked,
             family=binomial(), weights=prior, control=glm.control(epsilon=1e-12,maxit=200))
  emit(paste0("logistic_",name), c(unname(coef(fit)), unname(sqrt(diag(vcov(fit)))),
                                 deviance(fit), df.residual(fit), nobs(fit)))
}
'''
    output = subprocess.check_output([rscript(), '--vanilla', '-e', code], text=True)
    references = {}
    for line in output.splitlines():
        name, *values = line.split()
        assert name not in references, output
        references[name] = list(map(float, values))
    assert set(references) == {'differences_2x3', 'differences_3x2', 'differences_edges',
                               'walsh', 'tied_slopes', 'categorical', 'logistic_base',
                               'logistic_before', 'logistic_after'}, output
    return references


def pairwise_checks(session, reference):
    cases = [
        ('2x3', [1, None, 3], [10, 20, 30]),
        ('3x2', [1, 2, 3, None], [None, 10, None, 30]),
        ('edges', [None, 1, 3, None], [10, None, 30, 40]),
    ]
    for label, x, y in cases:
        result = session.run('PairDifferences', {'x': worksheet('X', x),
                                                'y': worksheet('Y', y)}, PREFERENCES)
        expected = reference['differences_' + label]
        compare(output_columns(result, [6])[0], expected, label)
    print('PASS: Cartesian differences retain all six X-major combinations with unequal observed counts and edge/interior missing values', flush=True)

    means = session.run('PairMeans', {'y': worksheet('Y', [None, 1, 3, 5, None])}, PREFERENCES)
    compare(output_columns(means, [6])[0], reference['walsh'], 'Walsh means')
    # 1448*1449/2 = 1,049,076, just beyond the real Mac worksheet limit.
    # The method must reject before constructing a million-cell output frame.
    ident, state = session.start('PairMeans', PREFERENCES)
    try:
        assert state['state'] == 'input' and state['prompt']['name'] == 'y', state
        response = session.request(action='answer', id=ident, token=state['token'],
                                   value=worksheet('Y', [1] * 1448))
        assert not response.get('error'), response
        state = session.wait(ident)
        assert state['state'] == 'failed' and state['error'] == 'Pairwise: Too many data.', state
        assert not state['frames'], state['frames']
    finally:
        session.close(ident)
    print('PASS: Walsh means agree with R and exceeding the worksheet row limit returns a clear error without an output frame', flush=True)

    # 65,536 squared is 2**32: the Cartesian product must be checked in a
    # wide integer before narrowing it or allocating/enumerating output rows.
    ident, state = session.start('PairDifferences', PREFERENCES)
    try:
        for name in ('y', 'x'):
            assert state['state'] == 'input' and state['prompt']['name'] == name, state
            response = session.request(action='answer', id=ident, token=state['token'],
                                       value=worksheet(name.upper(), [1] * 65536))
            assert not response.get('error'), response
            state = session.wait(ident)
        assert state['state'] == 'failed' and state['error'] == 'Pairwise: Too many data.', state
        assert not state['frames'], state['frames']
    finally:
        session.close(ident)
    print('PASS: a 2**32 Cartesian product is rejected before integer narrowing or output allocation', flush=True)

    slopes = session.run('PairSlopes', {'x': worksheet('X', [1, 1, 1, 1, 2]),
                                        'y': worksheet('Y', [10, 20, 30, 40, 50]),
                                        'calculate-slope': False}, PREFERENCES)
    compare(output_columns(slopes, [4])[0], reference['tied_slopes'], 'tied-X slopes')
    empty = session.run('PairSlopes', {'x': worksheet('X', [1] * 5),
                                       'y': worksheet('Y', [10, 20, 30, 40, 50]),
                                       'calculate-slope': False}, PREFERENCES)
    assert output_columns(empty, [0]) == [[]]
    print('PASS: tied X values produce exactly four eligible slopes and constant X produces zero rows, without phantom zeros', flush=True)


def categorical_checks(session, reference):
    groups = worksheet('group', ['A', 'B', None, 'B', 'A'])
    choose_a = {'Choose the reference category for group': '0'}
    dummies = session.run('DummyVariables', {'data': groups, **choose_a}, PREFERENCES)
    assert output_columns(dummies, [5]) == [[0.0, 1.0, None, 1.0, 0.0]], dummies['frames']

    model = session.run('MultipleLinearRegression', {
        'outcome': recorded_worksheet(['Y'], [[1, 2, 20, 2, 1]]),
        'predictors': recorded_worksheet(['group'], [['A', 'B', None, 'B', 'A']]),
        'calculateIntercept': True, 'useWeights': False, **choose_a,
    }, PREFERENCES, keep=True)
    try:
        record = json.loads(model['record'])
        predictors = next(item for item in record['inputs'] if item['name'] == 'predictors')
        assert predictors['kind'] == 'entered' and 'mode' not in predictors, predictors
        assert [column['values'] for column in predictors['columns']] == [[0, 1, None, 1, 0]], predictors
        text = ReportText(model['html']).text
        coefficients = [(int(index), float(value)) for index, value in
                        re.findall(r'\bb(\d+)\s*=\s*(' + NUMBER + ')', text)]
        assert [index for index, _ in coefficients] == [0, 1], text
        anova = session.run('MultipleLinearRegressionAnova', {}, PREFERENCES, parent=model['id'])
        actual = [anova['values']['tot_df'] + 1] + [value for _, value in coefficients]
        compare(actual, reference['categorical'], 'missing categorical complete-case model')
        assert actual == [4, 1, 1], actual
        assert anova['values']['res_df'] == 2, anova['values']
    finally:
        session.close(model['id'])
    print('PASS: categorical dummy retains its missing row and the actual regression uses four cases with intercept/slope 1, matching R', flush=True)


def alignment_record_checks(session):
    # The original regression lost a leading blank independently in one column,
    # then padded at the tail: it silently changed the mean from -52 to -50.
    x = [None] + list(range(2, 101)) + [None]
    y = [2 * i + i % 3 for i in range(1, 101)] + [None]
    source = recorded_worksheet(['Before', 'After'], [x, y])
    paired = session.run('TPaired', {'data': source, 'doAgreement': False}, PREFERENCES)
    assert paired['values']['n'] == 99 and paired['values']['df'] == 98, paired['values']
    compare([paired['values']['mean']], [-52], 'paired row alignment without payload flag')
    record = json.loads(paired['record'])
    acquired = next(item for item in record['inputs'] if item['name'] == 'data')
    assert acquired['kind'] == 'frame' and acquired['mode'] == 'NumericPreserveRows', acquired
    assert [c['hash'] for c in acquired['columns']] == [value_hash(x), value_hash(y)], acquired
    assert [c['rows'] for c in acquired['columns']] == [[1, 102], [1, 102]], acquired

    # Clear only the optional small-data cache to take the real pointer-only
    # path, exactly as a large saved run does, without a large statistical fit.
    record.pop('data', None)
    writer = subprocess.Popen([str(ROOT / 'Tests/engine-driver'),
                               os.environ.get('STATSDIRECT_TEST_ENGINE', str(ROOT / 'FullEngine/publish/StatsDirectEngine.dylib')),
                               'statsdirect_r_script'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)

    def write(current_record, frames):
        writer.stdin.write(json.dumps({'record': current_record, 'frames': frames}) + '\n')
        writer.stdin.flush()
        result = json.loads(writer.stdout.readline())
        assert result.get('hasRecipe') and not result.get('dataUnavailable'), result
        assert not result.get('relocate') and 'has changed in the workbook' not in result['text'], result
        return result

    try:
        for mode in ('NumericPreserveRows', '108'):
            acquired['mode'] = mode
            script = write(record, [{'name': 'data', 'columns': source['columns']}])
            assert script['asked'] == ['data'], script
            assert r_vector(script['text'], 'before') == x, script['text']
            assert r_vector(script['text'], 'after') == y, script['text']
        print('PASS: paired inputs align without preserveRows; numeric origins persist as mode 108 and named/numeric pointer rereads retain all 101 rows and missing edges', flush=True)

        # Ten matched pairs, five case-only exposures and one control-only:
        # finite conditional logistic estimate log(5), plus a wholly blank tail.
        stratum = [i for i in range(1, 11) for _ in (0, 1)] + [None]
        # A legitimate label containing the displayed missing marker is still
        # a real stratum; only the actual blank tail is missing.
        stratum[:2] = ['stratum * (missing) note'] * 2
        case = [1, 0] * 10 + [None]
        exposure = [1, 0, 1, 0, 1, 1, 0, 1, 1, 0, 0, 0, 1, 0, 1, 1, 0, 0, 1, 0] + [None]
        answers = {'stratum': recorded_worksheet(['Pair'], [stratum]),
                   'case-control': recorded_worksheet(['Case'], [case]),
                   'predictors': recorded_worksheet(['Exposure'], [exposure]),
                   'accuracy': '0.0000000001', 'show-counts': False}
        conditional = session.run('ConditionalLogisticRegression', answers, PREFERENCES)
        estimates = [row for row in ReportText(conditional['html']).rows
                     if len(row) == 5 and row[0] == 'Exposure']
        assert len(estimates) == 1, conditional['html']
        compare([float(estimates[0][1])], [math.log(5)], 'matched-pair estimate with blank tail')
        conditional_record = json.loads(conditional['record'])
        strata = next(item for item in conditional_record['inputs'] if item['name'] == 'stratum')
        assert strata['kind'] == 'frame' and strata['mode'] == 'CategoryCombineAllColumns', strata
        assert strata['columns'][0]['rows'] == [1, 22], strata
        assert strata['columns'][0]['hash'] == value_hash(stratum), strata
        numeric = next(item for item in conditional_record['inputs'] if item['name'] == 'predictors')
        assert numeric['kind'] == 'frame' and numeric['mode'] == 'NumericPreserveRows', numeric
        assert numeric['columns'][0]['hash'] == value_hash(exposure), numeric
        conditional_record.pop('data', None)
        frames = [{'name': name, 'columns': answers[name]['columns']}
                  for name in ('stratum', 'case-control', 'predictors')]
        script = write(conditional_record, frames)
        assert script['asked'] == ['stratum', 'case-control', 'predictors'], script
        assert r_vector(script['text'], 'stratum') == [str(v) if v is not None else None for v in stratum], script['text']
        assert r_vector(script['text'], 'case') == case, script['text']
        assert re.search(r'"Exposure" = c\([^)]*, NA\)', script['text']), script['text']
        print('PASS: aligned conditional-logistic stratum records mode 5 and retains its 21st missing row through hash-checked R-pointer reread', flush=True)
    finally:
        writer.stdin.close()
        writer.wait()


def logistic_checks(session, reference):
    baseline = None
    for label in ('base', 'before', 'after'):
        x, response, total = list(range(5)), [5, 8, 11, 14, 16], [20] * 5
        if label == 'before':
            x, response, total = [0] + x, [3] + response, [None] + total
        elif label == 'after':
            x, response, total = x + [0], response + [3], total + [None]
        fit = session.run('LogisticRegression', {
            'grouping': 'grouped', 'accuracy': '0.0000000001',
            'intercept': True, 'weights': False, 'total': worksheet('Total', total),
            'response': worksheet('Response', response), 'predictors': worksheet('X', x),
            # Duplicating X=0 makes an integer predictor look categorical;
            # this fixture, like upstream's direct numeric fit, uses it continuously.
            'Choose the reference category for X': '-2',
        }, PREFERENCES, keep=True)
        try:
            model = session.run('LogisticRegressionModel', {}, PREFERENCES, parent=fit['id'])
            rows = ReportText(model['html']).rows
            coefficients = []
            for row in rows:
                if len(row) == 5 and re.fullmatch(NUMBER, row[1]) and re.fullmatch(NUMBER, row[2]):
                    coefficients.append((float(row[1]), float(row[2])))
            assert len(coefficients) == 2, rows
            values = model['values']
            patterns = values['idf'] + values['rank']
            actual = [item[0] for item in coefficients] + [item[1] for item in coefficients]
            actual += [fit['values']['dev'], fit['values']['df'], patterns]
            compare(actual, reference['logistic_' + label], 'grouped logistic ' + label)
            assert fit['values']['df'] == 3 and patterns == 5, actual
            text = ReportText(fit['html']).text
            warning = 'observations dropped due to missing data'
            if label == 'base':
                assert warning not in text, text
                baseline = actual
            else:
                assert '1 ' + warning in text, text
                compare(actual, baseline, 'missing TOTAL does not poison valid equal-pattern row')
        finally:
            session.close(fit['id'])
    print('PASS: grouped logistic omits a missing TOTAL before stacking, in either order, retaining five patterns and matching complete-case R coefficients, SEs and deviance', flush=True)


if __name__ == '__main__':
    reference = r_references()
    session = Session()
    try:
        pairwise_checks(session, reference)
        categorical_checks(session, reference)
        alignment_record_checks(session)
        logistic_checks(session, reference)
    finally:
        session.finish()
