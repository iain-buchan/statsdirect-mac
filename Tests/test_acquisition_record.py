"""A saved analysis records the acquired worksheet, even when a calculation sorts it.

Exercise entered data, retained small worksheet data, and pointer-only large
worksheets through the real Mac host, including a genuine subsequent cell edit.
"""
import hashlib
import json
import os
import subprocess
import tempfile
from copy import deepcopy
from pathlib import Path
from test_menu import ROOT, Session
from r_runtime import rscript


def worksheet(name, values, column):
    return {'source': 'Acquisition.xlsx / Data',
            'columns': [{'title': name, 'values': values}],
            'range': {'firstRow': 2, 'lastRow': len(values) + 1, 'columns': [column]},
            'worksheet': {'workbook': 'Acquisition.xlsx', 'workbookPath': '/tmp/Acquisition.xlsx',
                          'sheet': 0, 'sheetName': 'Data', 'hasTitle': True, 'titles': [name]}}


session = Session()
writer = subprocess.Popen([str(ROOT / 'Tests/engine-driver'),
                           os.environ.get('STATSDIRECT_TEST_ENGINE', str(ROOT / 'FullEngine/publish/StatsDirectEngine.dylib')),
                           'statsdirect_r_script'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)


def script(record, frames):
    writer.stdin.write(json.dumps({'record': json.loads(json.dumps(record)), 'frames': frames}) + '\n')
    writer.stdin.flush()
    reply = json.loads(writer.stdout.readline())
    assert reply.get('hasRecipe') and not reply.get('dataUnavailable'), reply
    return reply['text']


try:
    count = 0
    for operation, input_name in [('SpreadPlot', 'data'), ('HistogramPlot', 'data'),
                                  ('NormalPlot', 'X'), ('BoxWhiskerPlot', 'data'),
                                  ('BoxWhiskerPlotText', 'data'), ('PolynomialRegression', 'x')]:
        for size, entered in [(9, True), (9, False), (5001, False)]:
            x = list(range(size, 0, -1))
            originals = {input_name: ('Selected measurement', x)}
            if operation == 'PolynomialRegression':
                originals['y'] = ('Selected outcome', [v*v + 3*v + 7 + i % 3 for i, v in enumerate(x)])
            answers = {name: worksheet(title, values, i) for i, (name, (title, values)) in enumerate(originals.items())}
            if entered:
                answers = {name: {'source': 'Entered data', 'columns': frame['columns']} for name, frame in answers.items()}
            if operation == 'PolynomialRegression':
                answers['degree'] = '2'
            result = session.run(operation, answers)
            record = json.loads(result['record'])
            assert 'Chart not drawn' not in result['html'], operation
            for name, (title, values) in originals.items():
                acquisition = next(item for item in record['inputs'] if item['name'] == name)
                column = acquisition['columns'][0]
                if entered:
                    assert column['values'] == values, (operation, name, 'entered values changed order')
                else:
                    expected = hashlib.sha256('\n'.join(map(str, values)).encode()).hexdigest()[:16]
                    assert column['hash'] == expected, (operation, name, size, 'acquisition hash changed')
                    if size == 9:
                        assert record['data'][name][title] == values, (operation, name, 'retained values changed order')
                    else:
                        assert 'data' not in record, (operation, 'large worksheet should be read by pointer')
            frames = [{'name': name, 'columns': [{'title': title, 'values': values}]} for name, (title, values) in originals.items()]
            unchanged = script(record, frames)
            assert 'has changed in the workbook' not in unchanged, (operation, size, 'false changed-data warning')
            if size == 5001:
                modified = deepcopy(frames)
                modified[0]['columns'][0]['values'][1] += 1
                changed = script(record, modified)
                assert changed.count('has changed in the workbook') == 1, (operation, 'a real cell edit must still be detected')
            count += 1
            print('PASS:', operation, size, 'entered' if entered else 'worksheet', 'preserves acquisition order and detects real changes', flush=True)
    # Paired missing values must remain in their acquired rows. A change of degree
    # must inherit that acquisition, not the sorted/filtered working arrays.
    paired = {'x': [9, 8, None, 6, 5, 4, 3, 2, 1], 'y': [117, 95, 77, None, 47, 36, 27, 17, 11]}
    answers = {name: {'source': 'Entered pairs', 'columns': [{'title': name, 'values': values}]} for name, values in paired.items()}
    parent = session.run('PolynomialRegression', dict(answers, degree='2'), keep=True)
    child = session.run('PolynomialRegressionChangeDegree', {'degree': '3'}, parent=parent['id'], keep=True)
    for degree, result in [(2, parent), (3, child)]:
        record = json.loads(result['record'])
        for name, values in paired.items():
            recorded = next(item for item in record['inputs'] if item['name'] == name)
            assert recorded['columns'][0]['values'] == values, (degree, name, 'paired acquisition or missing rows lost')
            if degree == 3: assert recorded['inherited'] is True
        prediction = session.run('PolynomialRegressionInterpolation', {'newx': 2.5}, parent=result['id'])
        wanted = [prediction['values'][key] for key in ['y_res', 'from_conf', 'to_conf', 'from_pred', 'to_pred']]
        text = script(record, []) + '''
expected_x <- c(1,2,3,4,5,8,9); expected_y <- c(11,17,27,36,47,95,117)
expected_fit <- lm(expected_y ~ poly(expected_x, degree, raw=TRUE))
stopifnot(isTRUE(all.equal(unname(coef(fit)), unname(coef(expected_fit)), tolerance=1e-9)))
ci <- predict(fit, data.frame(size=2.5), interval="confidence", level=.95)
pi <- predict(fit, data.frame(size=2.5), interval="prediction", level=.95)
stopifnot(max(abs(c(ci, pi[2:3]) - c(''' + ','.join(map(str, wanted)) + '''))) < 1e-7)
'''
        with tempfile.TemporaryDirectory(prefix='acquisition-pairs-', dir=ROOT/'.build') as folder:
            path = Path(folder)/'run.R'
            path.write_text(text)
            run = subprocess.run([rscript(), '--vanilla', str(path)], cwd=folder, text=True, capture_output=True, timeout=30)
            assert run.returncode == 0, (degree, run.stdout, run.stderr)
        print('PASS: polynomial degree', degree, 'retains original paired missing rows; generated R fit and intervals match native follow-on', flush=True)
    session.close(child['id']); session.close(parent['id'])
    print(f'PASS: {count} real Mac analyses preserve immutable selected-data records through saved-record R replay', flush=True)
finally:
    session.finish()
    writer.stdin.close()
    writer.wait()
