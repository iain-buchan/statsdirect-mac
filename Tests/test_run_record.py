from r_runtime import rscript as find_rscript
"""The engine's record of a run and the R scripts its writer makes from it, through the real engine (mirroring tests/RScript on Windows).

A TPaired run answered with worksheet provenance gives the Windows record (the file, pointer columns with hashes, the settings and
results, the values of a small run); an entered frame is recorded as entered; a long layout as its pivoted groups; a distribution
calculation records the calculator's boxes. The statsdirect_r_script entry writes the short plain script from the record, reads the
values the host supplies through the recorded acquisition mode (so unchanged cells give no NOTE and a changed cell exactly one), and
says when the workbook could not be read; the scripts run in R and their figures agree with the engine's. The shared R files in
Content/R are checked to contain the pinned engine's recipes and manifest. Then, as tests/RScript/Recipes.cs and Inverse.cs do on
Windows, every recipe of the manifest is written from the record a run on the help's example would leave (Tests/RScriptExamples,
the same files as Windows's tests/RScript/examples), compared line by line with the script the Windows writer's rules give for that
record (an independent rendering here of RScriptWriter.cs: the head, the column lines, the matrix, the settings and the body), run in
R and its figures compared with the help's own script; the help's example inputs are also run through the engine as entered frames,
the record of each real run checked against the definition (kinds, values, settings as proportions, the 2 by 2 table with what its
rows and columns stand for) and its script rendered, compared and run the same way; and the inverse records of the Distributions
calculator print figures the help's scripts print."""
import sys, json, hashlib, math, os, re, subprocess, tempfile
from pathlib import Path
from datetime import datetime, timedelta
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'Tests'))
ENGINE_DRIVER = Path(sys.argv[2]) if len(sys.argv) > 2 else ROOT / 'Tests/engine-driver'
sys.argv = sys.argv[:2]
from test_menu import Session
LIBRARY = Path(os.environ.get('STATSDIRECT_TEST_ENGINE', str(ROOT / 'FullEngine/publish/StatsDirectEngine.dylib')))
WORKBOOK = ROOT / 'Content/Examples/test.xlsx'
RSCRIPT = find_rscript()
checks = 0
def check(ok, what):
    global checks
    if not ok: raise AssertionError('FAIL ' + what)
    checks += 1; print('PASS', what, flush=True)
def defined_hash(texts): return hashlib.sha256('\n'.join(texts).encode()).hexdigest()[:16]
def iso(text): return datetime.fromisoformat(re.sub(r'(\.\d{6})\d+', r'\1', text))
first = [190, 220, 260, 210, 270, 280, 260, 275, 280, 320, 300, 270, 320, 335, 350, 360, 330, 335, 400, 430]
second = [220, 200, 260, 300, 265, 280, 280, 275, 290, 290, 300, 250, 330, 320, 320, 320, 340, 385, 420, 460]
def paired_t(x, y):
    d = [a - b for a, b in zip(x, y)]; n = len(d); mean = sum(d) / n; ss = sum((v - mean) ** 2 for v in d)
    return mean / math.sqrt(ss / (n - 1) / n)
def sheet_answer(sheet, name, columns, first_row, last_row, titles, data, workbook='test.xlsx', path=str(WORKBOOK), has_title=True):
    """A worksheet frame answer as the form sends it (Grid/operation-data.mjs worksheetInputFrom) with the workbook name and path OperationHost adds."""
    texts = [[str(v) for v in column] for column in data]
    worksheet = {'workbook': workbook, 'sheet': sheet, 'sheetName': name, 'hasTitle': has_title, 'titles': titles}
    if path is not None: worksheet['workbookPath'] = path
    return {'source': f'{workbook} / {name} · rows {first_row}–{last_row}', 'range': {'firstRow': first_row, 'lastRow': last_row, 'columns': columns},
            'preserveRows': True, 'columns': [{'title': t, 'values': v} for t, v in zip(titles, texts)], 'worksheet': worksheet}
class RScript:
    """The statsdirect_r_script entry through the line driver: {record, title, frames} -> {text, hasRecipe, detail, dataUnavailable, asked}."""
    def __init__(self):
        self.p = subprocess.Popen([str(ENGINE_DRIVER.resolve()), str(LIBRARY.resolve()), 'statsdirect_r_script'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    def write(self, record, title=None, frames=()):
        self.p.stdin.write(json.dumps({'record': record, 'title': title, 'frames': list(frames)}) + '\n'); self.p.stdin.flush()
        return json.loads(self.p.stdout.readline())
    def close(self): self.p.stdin.close(); self.p.wait()
def run_r(text):
    """Runs a script as the Windows check does (Rscript --vanilla in its own folder) and returns what it printed."""
    (ROOT / '.build').mkdir(exist_ok=True)
    folder = Path(tempfile.mkdtemp(prefix='run-record-r-', dir=ROOT / '.build'))
    script = folder / 'script.R'; script.write_text(text)
    p = subprocess.run([RSCRIPT, '--vanilla', '--encoding=UTF-8', str(script)], cwd=folder, capture_output=True, text=True)
    if p.returncode != 0: raise AssertionError('FAIL R exited %d:\n%s\n%s' % (p.returncode, p.stdout, p.stderr))
    return p.stdout
def close(a, b, rel): return abs(a - b) <= rel * max(abs(a), abs(b)) + 1e-12

# --- the shared R files: Content/R holds every recipe and manifest entry of the pinned engine (and the Mac's own session files)
upstream = ROOT / 'FullEngine/Upstream/StatsDirectUI/Assets/R'
manifest = json.loads((ROOT / 'Content/R/analysis-recipes.json').read_text())
pinned = json.loads((upstream / 'analysis-recipes.json').read_text())
differing = [f.name for f in sorted((upstream / 'recipes').glob('*.R')) if not (ROOT / 'Content/R/recipes' / f.name).is_file() or (ROOT / 'Content/R/recipes' / f.name).read_bytes() != f.read_bytes()]
check(not differing and all(manifest.get(op) == entry for op, entry in pinned.items()) and (ROOT / 'Content/R/session.R').is_file() and (ROOT / 'Content/R/data-files.R').is_file(),
      'Content/R holds the pinned engine\'s %d recipes and %d manifest entries unchanged (the Mac manifest has %d) beside session.R and data-files.R' % (len(list((upstream / 'recipes').glob('*.R'))), len(pinned), len(manifest)))
missing = [op for op in manifest if not (ROOT / 'FullEngine/publish/Operations' / (op + '.xml')).is_file()]
headed = [f.name for f in (ROOT / 'Content/R/recipes').glob('*.R') if not f.read_text().startswith('# StatsDirect recipe:')]
check(len(manifest) >= 28 and not missing and not headed and all((ROOT / 'Content/R/recipes' / e['file']).is_file() for e in manifest.values()),
      'every manifest operation is a published operation with a headed recipe file')
# the recipes against the definitions of the operations they are mapped to, as tests/RScript/Script.cs CheckRecipes: every setting a recipe
# takes is a parameter of each operation it serves (or a cell of its 2 by 2 table, or a box of the Distributions calculator), and the data it
# takes are of the kind the operation asks for
mismatches = []
for op, entry in manifest.items():
    text = (ROOT / 'Content/R/recipes' / entry['file']).read_text(); xml = (ROOT / 'FullEngine/publish/Operations' / (op + '.xml')).read_text()
    parameters = {m.strip() for m in re.findall(r'<name>([^<]+)</name>', xml)[1:]}
    parameters |= {m.strip() for m in re.findall(r'<(?:top-left|top-right|bottom-left|bottom-right)-name>([^<]+)</', xml)}
    if re.search(r'<builtin function-name="dist[A-Za-z]+"', xml): parameters |= {'value', 'df', 'df2', 'lower', 'upper', 'two_sided', 'asked'}
    settings = re.search(r'^# settings:\s*(.*)$', text, re.M)
    if settings:
        for item in [x.strip() for x in settings.group(1).split(',') if '=' in x]:
            parameter = item[item.index('=') + 1:].strip()
            if parameter not in parameters: mismatches.append('%s: %s takes the setting "%s"' % (op, entry['file'], parameter))
    if re.search(r'^# (data|matrix):', text, re.M) and '<frame>' not in xml: mismatches.append('%s: %s takes columns, and the operation asks for no frame' % (op, entry['file']))
    if re.search(r'^# table:', text, re.M) and '<double-2-by-2>' not in xml: mismatches.append('%s: %s takes a 2 by 2 table, and the operation asks for none' % (op, entry['file']))
    if not re.search(r'^# (data|table|matrix|settings):', text, re.M): mismatches.append('%s: %s has no header' % (op, entry['file']))
for mismatch in sorted(set(mismatches)): print('      mismatch: ' + mismatch, flush=True)
check(not mismatches, 'every setting and kind of data a recipe takes is what the operations it serves ask for')

s = Session()
# --- the record of a pointer run, as tests/RScript/Record.cs checks it on Windows
answer = sheet_answer(4, 'Agreement', [0, 1], 2, 21, ['1st', '2nd'], [first, second])
result = s.run('TPaired', {'data': answer, 'gamma': 95, 'doAgreement': False})
check(isinstance(result.get('record'), str) and result.get('recipe') is True, 'the completed snapshot carries the record (JSON text) and recipe true for TPaired')
r = json.loads(result['record'])
check(r['version'] == 1 and r['operation'] == 'TPaired' and r['title'] == 'Paired Student t test' and abs(datetime.now(iso(r['run']).tzinfo) - iso(r['run'])) < timedelta(minutes=5),
      'the record names the operation, its friendly title and the time of the run')
source = r['source']; mtime = datetime.fromtimestamp(WORKBOOK.stat().st_mtime)
check(source['file'] == 'test.xlsx' and source['path'] == str(WORKBOOK) and iso(source['modified']).replace(tzinfo=None, microsecond=0) == mtime.replace(microsecond=0) and 'unsaved' not in source,
      'the record names the data file, its path and when it was last written')
inputs = r['inputs']
check([i['name'] for i in inputs] == ['data', 'gamma', 'doAgreement'] and [i['kind'] for i in inputs] == ['frame', 'confidence', 'boolean'], 'the inputs are listed in the order they were asked, with their kinds')
check(inputs[0]['prompt'] == 'Select 2 matched columns (or 1 of differences)', 'an input carries the prompt the user saw')
frame = inputs[0]; columns = frame['columns']
check(frame['mode'] == 'NumericReplaceMissing' and frame['file'] == 'test.xlsx' and frame['path'] == str(WORKBOOK) and frame['sheet'] == 'Agreement' and len(columns) == 2,
      'a frame read from a sheet is recorded as pointers: the mode, the file, the sheet and its columns')
check(columns[0]['title'] == '1st' and columns[0]['column'] == 1 and columns[1]['column'] == 2 and columns[0]['rows'] == [1, 21] and columns[1]['rows'] == [1, 21] and columns[0]['hasTitle'] is True and 'sheet' not in columns[0],
      'a pointer column gives its title, 1-based column, rows [1, 21] with the title row counted in, hasTitle')
check(columns[0]['hash'] == defined_hash(str(v) for v in first) and columns[1]['hash'] == defined_hash(str(v) for v in second), 'a column\'s hash is SHA-256 of its values as text joined by LF, the first 16 hex characters')
check('values' not in columns[0], 'a pointer column carries no values of its own')
check(inputs[1]['value'] == 0.95 and inputs[2]['value'] is False, 'the scalar inputs carry their values, the confidence level as a proportion')
check(r['parameters']['gamma'] == 0.95 and r['parameters']['doAgreement'] is False and 'data' not in r['parameters'], 'the settings hold every scalar input and no frame')
t = paired_t(first, second)
check(abs(r['values']['t'] - t) < 1e-9 and 'data' not in r['values'] and not any(k.startswith('statsdirect') for k in r['values']), 'the results hold the engine\'s scalar outputs, t = %r' % r['values']['t'])
check(r['data']['data']['1st'] == first and r['data']['data']['2nd'] == second, 'the values of a small run are kept with the record, by input and column title')
pointer_record = result['record']; pointer_values = r['values']
# --- hasTitle false: the data do not start under the header row
result = s.run('TPaired', {'data': sheet_answer(4, 'Agreement', [0, 1], 3, 22, ['1st', '2nd'], [first, second]), 'gamma': 95, 'doAgreement': False})
c = json.loads(result['record'])['inputs'][0]['columns'][0]
check(c['rows'] == [3, 22] and c['hasTitle'] is False, 'a selection not starting under the header row records its own rows [3, 22] without a title')
# --- an unsaved workbook: the name is the path
result = s.run('TPaired', {'data': sheet_answer(0, 'Sheet1', [2, 3], 2, 21, ['1st', '2nd'], [first, second], workbook='Untitled.xlsx', path=None), 'gamma': 95, 'doAgreement': False})
r2 = json.loads(result['record'])
check(r2['source'] == {'file': 'Untitled.xlsx', 'unsaved': True} and r2['inputs'][0]['file'] == 'Untitled.xlsx' and r2['inputs'][0]['path'] == 'Untitled.xlsx' and r2['inputs'][0]['columns'][0]['column'] == 3,
      'an unsaved workbook records source {file, unsaved} and the name as the frame\'s file and path')
# --- an entered frame
result = s.run('TPaired', {'data': {'columns': [{'title': '1st', 'values': first}, {'title': '2nd', 'values': second}], 'source': 'Test fixture'}, 'gamma': 95, 'doAgreement': False})
r3 = json.loads(result['record']); e = r3['inputs'][0]
check(e['kind'] == 'entered' and e['columns'][0]['values'] == first and e['columns'][1]['title'] == '2nd' and 'source' not in r3 and 'data' not in r3, 'a frame typed in is recorded as entered with its values and no source')
entered_record = result['record']
# --- the threshold: 2,600 x 2 pointer values keep no data
x = [100 + math.sin(i) * 10 for i in range(2600)]; y = [101 + math.cos(i) * 10 for i in range(2600)]
result = s.run('TPaired', {'data': sheet_answer(5, 'Big', [3, 4], 2, 2601, ['x', 'y'], [x, y]), 'gamma': 90, 'doAgreement': False})
big = json.loads(result['record']); bc = big['inputs'][0]['columns']
check('data' not in big and bc[1]['column'] == 5 and bc[0]['rows'] == [1, 2601] and len(result['record']) < 2000, 'a run of 5,200 values keeps pointers only: %d characters' % len(result['record']))
big_record = result['record']
# --- a long layout is recorded as entered (the pivoted groups), as the Windows pivots leave them
long_answer = {'source': 'test.xlsx / Sheet1 · groups by identifier', 'range': {'firstRow': 2, 'lastRow': 7, 'columns': [0, 1]}, 'preserveRows': True, 'layout': 'long', 'roles': {'identifiers': 1},
               'columns': [{'title': 'value', 'values': ['1', '2', '3', '4', '5', '6']}], 'groupIdentifiers': [{'title': 'group', 'values': ['a', 'a', 'b', 'b', 'c', 'c']}],
               'worksheet': {'workbook': 'test.xlsx', 'sheet': 0, 'sheetName': 'Sheet1', 'hasTitle': True, 'titles': ['value', 'group'], 'workbookPath': str(WORKBOOK), 'cells': [['1', '2', '3', '4', '5', '6'], ['a', 'a', 'b', 'b', 'c', 'c']]}}
result = s.run('OneWay', {'data': long_answer})
lr = json.loads(result['record']); li = lr['inputs'][0]
check(li['kind'] == 'entered' and len(li['columns']) == 3 and li['columns'][0]['values'] == [1, 2] and 'source' not in lr and result['history'][0]['value'].get('worksheet', {}).get('workbookPath') == str(WORKBOOK),
      'a long layout records its pivoted groups as entered, with the worksheet block kept in the history')
# --- a 2 by 2 table typed in, as tests/RScript/Table.cs checks it
result = s.run('Chi2by2', {'scrap': {'columns': [{'title': 'Present', 'values': [10, 3]}, {'title': 'Absent', 'values': [5, 12]}], 'source': 'Test fixture'}, 'cco': 95, 'study_type': 'casecontrol', 'doFisher': False})
tr = json.loads(result['record']); ti = tr['inputs'][0]
check(ti['name'] == 'scrap' and ti['kind'] == 'table' and [c['title'] for c in ti['columns']] == ['Present', 'Absent'] and ti['columns'][0]['values'] == [10, 3] and ti['counts'] == [[10, 5], [3, 12]]
      and ti['rowLabels'][1] == 'Absent' and tr['parameters']['counts'][1][0] == 3 and tr['parameters']['columnLabels'][0] == 'Present' and not any(i['name'] == 'a' for i in tr['inputs']) and tr['parameters']['a'] == 10,
      'a 2 by 2 table typed in is recorded as a table with its columns, counts and labels, the counts among the settings')
table_record = result['record']; table_values = tr['values']
# --- a distribution calculation: the calculator's boxes as the record's settings, as the Windows calculator records them (ctlPDF.Fill adds every
# shown box as an input of the run, with the number the box shows: a probability to 15 decimal places), and the report line as its only result
result = s.run('DistributionNormal', {'Normal distribution': {'x': 1.96}})
dr = json.loads(result['record']); dp = dr['parameters']
check(dr['operation'] == 'DistributionNormal' and result['recipe'] is True and dp['value'] == 1.96 and dp['asked'] == 'calculate'
      and dp['lower'] == 0.97500210485178 and dp['upper'] == 0.02499789514822 and dp['two_sided'] == 0.049995790296441
      and list(dp) == ['value', 'lower', 'upper', 'two_sided', 'asked'] and list(dr['values']) == ['gr'] and list(result['values']) == ['gr'],
      'a distribution run records value, lower, upper and two_sided (to the 15 decimal places the boxes show) and asked as its settings, and the report line as its only result')
distribution_record = result['record']

# --- the script entry, as tests/RScript/Script.cs checks the writer on Windows
rs = RScript()
script = rs.write(pointer_record, 'Paired t test of peak flow', [])
check('error' not in script and script['hasRecipe'] and script['detail'].startswith('Paired t test') and not script['dataUnavailable'] and script['asked'] == [],
      'the paired t test has a recipe, and the data of a small run come from the record')
text = script['text']
check(text.startswith('# Paired t test of peak flow, from StatsDirect, ') and '# Data: "test.xlsx", sheet "Agreement", the values the analysis used.' in text, 'the script\'s head names the analysis and where its data came from')
check('before <- c(190, 220, 260, 210' in text and '   # 1st, column 1, rows 1 to 21\n' in text and 'after <- c(220, 200, 260, 300' in text and 'confidence <- 0.95\n' in text,
      'the data are plain named vectors with the column\'s title and place beside them, and the settings plain values')
check(not any(w in text for w in ('setNames', 'data_frames', 'sd_columns', 'original_results', 'input_history')), 'nothing of the program\'s machinery is in the script')
check('t.test(before, after, paired = TRUE, conf.level = confidence)' in text, 'the paired recipe follows, taking the confidence level from the settings')
output = run_r(text)
rt = float(re.search(r't = ([-0-9.eE+]+), df = 19', output).group(1)); rp = float(re.search(r'p-value = ([0-9.eE-]+)', output).group(1))
ci = re.search(r'percent confidence interval:\s*\n\s*([-0-9.eE+]+)\s+([-0-9.eE+]+)', output)
check(close(rt, pointer_values['t'], 1e-4) and close(rp, pointer_values['tail_2'], 1e-3) and close(float(ci.group(1)), pointer_values['from'], 1e-4) and close(float(ci.group(2)), pointer_values['to'], 1e-4),
      'R\'s paired t, two-sided P and confidence interval agree with the engine\'s')
script = rs.write(json.loads(pointer_record), None, [])
check(script['text'].startswith('# Paired Student t test, from StatsDirect, '), 'without a title the script is headed by the record\'s friendly title (the record given as an object)')
script = rs.write(entered_record, None, [])
check(script['hasRecipe'] and '# Data:' not in script['text'] and 'before <- c(190, 220, 260, 210' in script['text'] and '   # 1st\n' in script['text'] and 'confidence <- 0.95\n' in script['text'],
      'an entered frame gets no Data line and its columns carry the title alone')
# the large run: the values are read again by the pointers; the hash comparison through ReadFrame under the recorded mode
same = [{'name': 'data', 'columns': [{'title': 'x', 'values': [str(v) for v in x], 'kinds': ['number'] * 2600}, {'title': 'y', 'values': [str(v) for v in y], 'kinds': ['number'] * 2600}]}]
script = rs.write(big_record, None, same)
check(script['asked'] == ['data'] and not script['dataUnavailable'] and 'NOTE' not in script['text'] and re.search(r'# Data: "test\.xlsx", sheet "Big", read on \d+ \w+ 20\d\d \d\d:\d\d\.', script['text']),
      'unchanged cells re-read through the recorded mode hash as recorded: no NOTE, and the head says when the data were read')
check(re.search(r'^before <- c\(100, 108\.414709848078\d*, ', script['text'], re.M) and '   # x, column 4, rows 1 to 2601\n' in script['text'], 'the values read are written into the script under the recipe\'s names')
changed = json.loads(json.dumps(same)); changed[0]['columns'][1]['values'][7] = '99.5'
script = rs.write(big_record, None, changed)
check(script['text'].count('# NOTE:') == 1 and '# NOTE: "y" has changed in the workbook since the analysis ran; these are its values now.' in script['text'] and '"x" has changed' not in script['text'] and ', 99.5, ' in script['text'],
      'a column whose hash no longer matches is noted, that column alone, with its values now')
script = rs.write(big_record, None, [{'name': 'data', 'unavailable': 'the workbook test.xlsx is not open and was not found'}])
check(script['dataUnavailable'] and 'before <- NULL   # x, column 4, rows 1 to 2601: not read, see above' in script['text'] and 'could not be read (the workbook test.xlsx is not open and was not found): put the values in by hand.' in script['text'],
      'when the workbook cannot be read the script says so and leaves the vectors for the user')
script = rs.write(big_record, None, [])
check(script['dataUnavailable'] and ('could not be read (the workbook test.xlsx is not open and was not found at %s): put the values in by hand.' % WORKBOOK) in script['text'],
      'a frame the host did not supply is reported as not open and not found at the recorded path')
script = rs.write(big_record, None, [{'name': 'data', 'columns': [{'title': 'x', 'values': ['1', '2']}]}])
check(script['dataUnavailable'] and 'sheet Big of test.xlsx no longer gives 2 columns at the recorded place' in script['text'], 'a frame with the wrong number of columns is reported as no longer at the recorded place')
script = rs.write(big_record, None, [{'name': 'data', 'columns': [{'title': 'x', 'values': x}, {'title': 'y', 'values': y}]}])
check('NOTE' not in script['text'] and not script['dataUnavailable'], 'typed JSON numbers hash as the texts they stand for')
# the 2 by 2 table's script: the matrix with its dimnames, run in R against the engine's chi-square
script = rs.write(table_record, None, [])
check(script['hasRecipe'] and 'counts <- matrix(c(10, 5, 3, 12), 2, byrow = TRUE,\n  dimnames = list("Outcome" = c("Present", "Absent"), "Characteristic" = c("Present", "Absent")))\n' in script['text'] and 'confidence <- 0.95\n' in script['text'],
      'a 2 by 2 table is written as a matrix of counts with its labels as dimnames, named by what the dialog\'s rows and columns stand for')
output = run_r(script['text'])
chi = re.search(r'X-squared = ([0-9.eE+-]+), df = 1', output)
check(chi is not None and close(float(chi.group(1)), table_values['chi'], 1e-4) and re.search(r'Present\s+Absent', output),
      'R\'s 2 by 2 chi-square (%s) agrees with the engine\'s uncorrected chi-square (%r) and prints the table with its labels' % (chi.group(1) if chi else None, table_values.get('chi')))
# an operation with no recipe
bare = '{"version":1,"operation":"NoSuchMethod","title":"Some method","run":"2026-10-10T22:00:00+01:00","inputs":[{"name":"data","prompt":"Select data","kind":"entered","columns":[{"title":"Peak flow (1st)","values":[1,null,3]}]},{"name":"k","prompt":"Groups","kind":"integer","value":2}],"parameters":{"k":2,"label":"x \\"y\\""},"values":{"stat":1.5}}'
script = rs.write(bare, None, [])
output = run_r(script['text'])
check(not script['hasRecipe'] and 'peak_flow_1st <- c(1, NA, 3)   # Peak flow (1st)\n' in script['text'] and 'k <- 2   # k\n' in script['text'] and 'label <- "x \\"y\\""   # label\n' in script['text'] and script['text'].rstrip().endswith('# Add your analysis here.') and output.strip() == '',
      'without a recipe the script holds the data and settings under safe names, escapes text, and runs in R')
check('error' in rs.write('not json', None, []) and 'error' in rs.write(42, None, []), 'a malformed request is answered with an error, not a crash')
script = rs.write(distribution_record, None, [])
output = run_r(script['text'])
check(script['hasRecipe'] and script['text'].startswith('# Distribution: Normal, from StatsDirect, ') and 'z <- 1.96\n' in script['text'] and 'asked <- "calculate"\n' in script['text'] and '# Data:' not in script['text']
      and 'lower <- 0.97500210485178\n' in script['text'] and 'upper <- 0.02499789514822\n' in script['text'] and 'two_sided <- 0.049995790296441\n' in script['text']
      and 'P(z 1.96) = 0.02499789514822 upper, 0.97500210485178 lower, 0.049995790296441 two sided' in output,
      'the normal distribution recipe takes the calculator\'s boxes from the record (the tails written as Windows writes them) and R prints the engine\'s tails')

# ======================================================================================================================
# The recipes against the help's scripts, as tests/RScript/Recipes.cs, Script.cs and Inverse.cs check them on Windows.
# ======================================================================================================================
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor
from decimal import Decimal
EXAMPLES = ROOT / 'Tests/RScriptExamples'
OPERATIONS = ROOT / 'FullEngine/publish/Operations'
MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']

# --- the writer's rules (StatsDirectUI/R/RScriptWriter.cs), rendered here independently so the engine's text can be checked line by line
def csharp(x):
    """A number as C# double.ToString("R") writes it: the shortest round-trip digits, E notation from 1E+15 and below 1E-05."""
    x = float(x)
    if x != x: return 'NaN'
    if x in (float('inf'), float('-inf')): return 'Infinity' if x > 0 else '-Infinity'
    if x == 0: return '-0' if math.copysign(1, x) < 0 else '0'
    sign, digits, exponent = Decimal(repr(x)).normalize().as_tuple()
    s = ''.join(map(str, digits)); e10 = len(s) - 1 + exponent
    if e10 >= 15 or e10 < -5: text = s[0] + ('.' + s[1:] if len(s) > 1 else '') + 'E' + ('+' if e10 >= 0 else '-') + '%02d' % abs(e10)
    elif exponent >= 0: text = s + '0' * exponent
    elif len(s) + exponent > 0: text = s[:len(s) + exponent] + '.' + s[len(s) + exponent:]
    else: text = '0.' + '0' * (-(len(s) + exponent)) + s
    return ('-' if sign else '') + text
def quote(value):
    out = '"'
    for ch in value or '':
        if ch == '"': out += '\\"'
        elif ch == '\\': out += '\\\\'
        elif ch == '\n': out += '\\n'
        elif ch == '\r': out += '\\r'
        elif ch == '\t': out += '\\t'
        elif ord(ch) < 32 or ord(ch) == 0x7f: out += '\\u%04x' % ord(ch)
        else: out += ch
    return out + '"'
def is_number(v): return isinstance(v, (int, float)) and not isinstance(v, bool)
def is_scalar(v): return is_number(v) or isinstance(v, (bool, str))
def literal(v):
    if isinstance(v, bool): return 'TRUE' if v else 'FALSE'
    if is_number(v): return csharp(v)
    if isinstance(v, str): return quote(v)
    if isinstance(v, list): return 'list(' + ', '.join(literal(x) for x in v) + ')'
    if isinstance(v, dict): return 'list(' + ', '.join(quote(k) + ' = ' + literal(x) for k, x in v.items()) + ')'
    return 'NULL'
def vector(values):
    numeric = all(v is None or is_number(v) for v in values)
    if not values: return 'numeric(0)' if numeric else 'character(0)'
    def one(v):
        if numeric: return 'NA' if v is None else csharp(v)
        if v is None: return 'NA'
        if isinstance(v, bool): return quote('TRUE' if v else 'FALSE')
        if is_number(v): return quote(csharp(v))
        return quote(str(v))
    return 'c(' + ', '.join(one(v) for v in values) + ')'
def safe_name(title, names):
    s = re.sub(r'[^a-z0-9]+', '_', (title or '').strip().lower()).strip('_')
    if not s or s[0].isdigit(): s = 'x' + s
    candidate, n = s, 2
    while candidate in names: candidate = s + str(n); n += 1
    names.add(candidate); return candidate
def text_of(element, key): return element[key] if isinstance(element, dict) and isinstance(element.get(key), str) else None
def parse_recipe(recipe):
    """The header's bindings and the body, as RScriptWriter.Parse reads them."""
    b = {'data': [], 'list': None, 'table': None, 'matrix': None, 'settings': [], 'body': ''}
    lines = recipe.replace('\r\n', '\n').split('\n'); last = -1; i = 0
    while i < len(lines) and (lines[i].strip() == '' or lines[i].startswith('#')):
        m = re.match(r'^#\s*(data|table|matrix|settings|recipe):\s*(.*)$', lines[i], re.I)
        if not m:
            if re.match(r'^# (StatsDirect recipe|From the help|hand-edited)', lines[i], re.I): last = i
            i += 1; continue
        last = i; what = m.group(1).lower(); rest = m.group(2).strip()
        if what == 'data':
            for item in [x.strip() for x in rest.split(',') if x.strip()]:
                eq = item.find('='); variable = (item[:eq] if eq > 0 else item).strip(); source = item[eq + 1:].strip() if eq > 0 else None
                is_list = variable.endswith('...')
                if is_list: variable = variable[:-3].strip()
                if is_list and source is None: b['list'] = variable
                else: b['data'].append((variable, source, is_list))
        elif what == 'table': b['table'] = rest
        elif what == 'matrix': b['matrix'] = rest
        elif what == 'settings':
            for item in [x.strip() for x in rest.split(',') if x.strip()]:
                eq = item.find('=')
                if eq > 0: b['settings'].append((item[:eq].strip(), item[eq + 1:].strip()))
        i += 1
    b['body'] = '\n'.join(lines[last + 1:]).lstrip('\n')
    return b
def run_time(record):
    run = text_of(record, 'run')
    try: t = iso(run).astimezone()
    except Exception: return run or ''
    return '%d %s %d %02d:%02d' % (t.day, MONTHS[t.month - 1], t.year, t.hour, t.minute)
def objects(values):
    if not isinstance(values, list): return []
    return [v if (is_number(v) or isinstance(v, (bool, str))) else None for v in values]
def expected_script(record, recipe, detail):
    """The script RScriptWriter.Write gives for a record without pointer frames (entered frames, tables, settings), with no title given."""
    operation = text_of(record, 'operation') or ''
    title = text_of(record, 'title') or operation
    binding = parse_recipe(recipe) if recipe is not None else None
    columns, tables, groups = [], [], []
    for inp in record.get('inputs', []) if isinstance(record.get('inputs'), list) else []:
        name = text_of(inp, 'name') or 'input'; kind = text_of(inp, 'kind') or 'other'; start = len(columns)
        if kind == 'table':
            counts = inp.get('counts') if isinstance(inp.get('counts'), list) else []
            rows = [[literal(v) for v in r] if isinstance(r, list) else [literal(r)] for r in counts]
            def strings(key): return [v if isinstance(v, str) else json.dumps(v) for v in inp[key]] if isinstance(inp.get(key), list) else []
            tables.append((rows, strings('rowLabels'), strings('columnLabels'), text_of(inp, 'rowsTitle'), text_of(inp, 'columnsTitle')))
            continue
        if kind not in ('frame', 'entered'): continue
        if kind == 'frame': raise AssertionError('expected_script renders records without pointer frames')
        for c in inp.get('columns', []) if isinstance(inp.get('columns'), list) else []:
            columns.append({'title': text_of(c, 'title') or '', 'values': objects(c.get('values'))})
        groups.append((name, start, len(columns) - start))
    head = '# %s, from StatsDirect, %s\n' % (title, run_time(record))
    if detail is not None: head += '# ' + detail + '\n'
    head += '\n'
    out = [head]; names = set(); bound = set()
    def assign(variable, column):
        names.add(variable); out.append(variable + ' <- ' + vector(column['values']) + '   # ' + column['title'] + '\n')
    def list_of(variable, indices):
        out.append(variable + ' <- list(' + ',\n  '.join(quote(columns[i]['title']) + ' = ' + vector(columns[i]['values']) for i in indices) + ')\n'); names.add(variable)
    def missing(variable, why): names.add(variable); out.append(variable + ' <- NULL   # ' + why + '\n')
    if binding:
        for variable, source, is_list in [d for d in binding['data'] if d[1] is not None]:
            at = next((k for k, g in enumerate(groups) if g[0] == source), -1)
            if at < 0 or groups[at][2] == 0: missing(variable, 'no "%s" in this run' % source); continue
            _, start, count = groups[at]; indices = [i for i in range(start, start + count) if i not in bound]
            if is_list: list_of(variable, indices); bound.update(indices)
            elif indices: assign(variable, columns[indices[0]]); bound.add(indices[0])
            else: missing(variable, 'no column of "%s" is left for it' % source)
    nxt = 0
    def skip(n):
        while n < len(columns) and n in bound: n += 1
        return n
    if binding:
        for variable, source, is_list in [d for d in binding['data'] if d[1] is None]:
            nxt = skip(nxt)
            if nxt >= len(columns): missing(variable, 'no column for it in this run'); continue
            assign(variable, columns[nxt]); bound.add(nxt); nxt += 1
    nxt = skip(nxt)
    if binding and binding['list'] is not None:
        list_of(binding['list'], [i for i in range(len(columns)) if i not in bound]); nxt = len(columns)
    while nxt < len(columns):
        if nxt not in bound: assign(safe_name(columns[nxt]['title'], names), columns[nxt])
        nxt += 1
    for rows, row_labels, column_labels, rows_title, columns_title in tables:
        variable = binding['table'] if binding and binding['table'] else safe_name('counts', names)
        line = variable + ' <- matrix(c(' + ', '.join(v for r in rows for v in r) + '), ' + str(len(rows)) + ', byrow = TRUE'
        if len(row_labels) == len(rows) and len(column_labels) == (len(rows[0]) if rows else 0):
            line += ',\n  dimnames = list(' + (quote(rows_title) + ' = ' if rows_title is not None else '') + 'c(' + ', '.join(map(quote, row_labels)) + '), ' \
                    + (quote(columns_title) + ' = ' if columns_title is not None else '') + 'c(' + ', '.join(map(quote, column_labels)) + '))'
        out.append(line + ')\n'); names.add(variable)
    if binding and binding['matrix'] is not None and columns and not binding['data'] and binding['list'] is None:
        out = [head, binding['matrix'] + ' <- cbind(' + ',\n  '.join(quote(c['title']) + ' = ' + vector(c['values']) for c in columns) + ')\n']; names.add(binding['matrix'])
    parameters = record.get('parameters') if isinstance(record.get('parameters'), dict) else None
    if binding:
        for variable, parameter in binding['settings']:
            if parameters is not None and parameter in parameters and is_scalar(parameters[parameter]): out.append(variable + ' <- ' + literal(parameters[parameter]) + '\n')
    elif parameters is not None:
        for key, value in parameters.items():
            if is_scalar(value) and not key.lower().startswith('statsdirect'): out.append(safe_name(key, names) + ' <- ' + literal(value) + '   # ' + key + '\n')
    out.append('\n')
    out.append(binding['body'].rstrip('\n') + '\n' if binding else '# Add your analysis here.\n')
    return ''.join(out)
def first_difference(a, b):
    """The first line that differs between two texts, 1-based, with the two lines."""
    x, y = a.split('\n'), b.split('\n')
    for i in range(max(len(x), len(y))):
        if i >= len(x) or i >= len(y) or x[i] != y[i]: return i + 1, (x[i] if i < len(x) else '(end)'), (y[i] if i < len(y) else '(end)')
    return None
def figures(output):
    """Every number printed, in order, so that a difference in a label alone does not count; the row and column indices R prints for an unlabelled matrix are not figures."""
    return ' '.join(m.group(0) for m in re.finditer(r'-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?', re.sub(r'\[\d*,\d*\]', ' ', output)))
def friendly_name(operation):
    tree = ET.parse(OPERATIONS / (operation + '.xml'))
    for element in tree.iter():
        if element.tag.endswith('friendly-name'): return element.text
    return operation
def recipe_of(operation):
    entry = manifest[operation]; return (ROOT / 'Content/R/recipes' / entry['file']).read_text(), entry['detail']

# --- the record a run on the help's example would leave, as Recipes.cs's RecordOf builds it
def record_of(example):
    inputs = []
    for named in example.get('inputs', []) if isinstance(example.get('inputs'), list) else []:
        inputs.append({'name': named['name'], 'prompt': named['name'], 'kind': 'entered', 'columns': named['columns']})
    if 'data' in example: inputs.append({'name': 'data', 'prompt': 'Select data', 'kind': 'entered', 'columns': example['data']})
    if 'list' in example: inputs.append({'name': 'data', 'prompt': 'Select data', 'kind': 'entered', 'columns': example['list']})
    if isinstance(example.get('table'), dict):
        t = example['table']; counts = t['counts']; labels = t.get('columnLabels', [])
        columns = [{'title': labels[c] if c < len(labels) else '', 'values': [r[c] for r in counts]} for c in range(len(counts[0]))]
        table = {'name': 'scrap', 'prompt': 'Table', 'kind': 'table', 'columns': columns, 'counts': counts, 'rowLabels': t['rowLabels'], 'columnLabels': t['columnLabels']}
        for key in ('rowsTitle', 'columnsTitle'):
            if key in t: table[key] = t[key]
        inputs.append(table)
    if isinstance(example.get('matrix'), dict):
        m = example['matrix']; counts = m['counts']; labels = m.get('columnLabels', [])
        inputs.append({'name': 'data', 'prompt': 'Select the table', 'kind': 'entered', 'columns': [{'title': labels[c] if c < len(labels) else 'V%d' % (c + 1), 'values': [r[c] for r in counts]} for c in range(len(counts[0]))]})
    return {'version': 1, 'operation': example['operation'], 'title': 'Example', 'run': '2026-10-11T03:00:00+01:00', 'inputs': inputs, 'parameters': example.get('settings', {}), 'values': {}}

# --- the help's example inputs through the engine as entered frames: the record of a real run
def run_example(session, example):
    """Answers the operation's prompts from the example: frames by the name the operation asks them by, else the example's columns in order (one
    at a time to a single-column prompt, the rest to a wider one), a screen-typed 2 by 2 from its cell settings, the Distributions calculator's
    boxes, settings by parameter name (a confidence level as a percentage, an option as its value), optional frames skipped, defaults otherwise."""
    id, state = session.start(example['operation']); used = set(); settings = example.get('settings') or {}
    pool = [dict(c) for key in ('data', 'list') for c in example.get(key, [])]
    named = {i['name']: i for i in example.get('inputs', [])} if isinstance(example.get('inputs'), list) else {}
    def answer(p):
        name = p.get('name'); kind = p['kind']
        if kind == 'grid':
            if p.get('screen') and len(p.get('labels') or []) == 2:
                keys = ('a', 'b', 'c', 'd') if 'c' in settings else ('a', 'b', 'pt1', 'pt2')
                if all(k in settings for k in keys):
                    a, b, c, d = (settings[k] for k in keys)
                    return {'columns': [{'title': p['labels'][0], 'values': [a, c]}, {'title': p['labels'][1], 'values': [b, d]}], 'source': 'Help example'}
            if name in named and name not in used: used.add(name); return {'columns': named[name]['columns'], 'source': 'Help example'}
            for key in ('matrix', 'table'):
                if isinstance(example.get(key), dict) and key not in used:
                    used.add(key); t = example[key]; counts = t['counts']; labels = t.get('columnLabels', [])
                    return {'columns': [{'title': labels[c] if c < len(labels) else ('V%d' % (c + 1) if key == 'matrix' else ''), 'values': [r[c] for r in counts]} for c in range(len(counts[0]))], 'source': 'Help example'}
            if pool:
                k = min(p.get('maxColumns') or len(pool), len(pool)); take = pool[:k]; del pool[:k]
                return {'columns': take, 'source': 'Help example'}
            return {'skip': True} if p.get('skip') else None
        if kind == 'fields' and any(f['name'] in ('x', 'df', 'df2') for f in p['fields']):
            boxes = {'x': 'value', 'df': 'df', 'df2': 'df2'}   # the Distributions calculator's boxes under the record's names
            return {f['name']: settings.get(boxes.get(f['name'], ''), f['defaultValue']) if settings.get(boxes.get(f['name'], '')) is not None else f['defaultValue'] for f in p['fields']}
        if name in settings and settings[name] is not None:
            v = settings[name]
            if kind == 'confidence': return v * 100
            if kind == 'option':
                values = [o['value'] for o in p['options']]
                return str(v) if str(v) in values else (v if v in values else values[0])
            return v
        if kind == 'options': return {o['value']: o['selected'] for o in p['options']}
        if kind in ('fields', 'settings'): return {o['name']: o['defaultValue'] for o in p['fields']}
        if kind == 'boolean': return False
        if kind == 'confidence': return p['defaultValue']
        if p.get('defaultValue') is not None: return p['defaultValue']
        if kind == 'option': return p['options'][0]['value']
        if kind in ('integer', 'number'): return 0
        return {'skip': True} if p.get('skip') else None
    for _ in range(100):
        if state.get('state') != 'input': break
        p = state['prompt']; value = answer(p)
        if value is None or p.get('error'): session.close(id); raise AssertionError('%s: %s' % (example['operation'], p.get('error') or 'unanswered prompt %s (%s)' % (p.get('name'), p['kind'])))
        session.request(action='answer', id=id, token=state['token'], value=value); state = session.wait(id)
    session.close(id)
    if state.get('state') != 'complete': raise AssertionError('%s: %s' % (example['operation'], state.get('error')))
    return state

def r_outputs(texts):
    """Several scripts run in R at once (each in its own folder); the outputs in order, or the error text of a failed run."""
    def one(text):
        try: return run_r(text)
        except AssertionError as e: return e
    with ThreadPoolExecutor(max_workers=6) as pool: return list(pool.map(one, texts))

operations = sorted(manifest)
check(len(operations) >= 28 and all((EXAMPLES / (op + '.json')).is_file() and (EXAMPLES / (op + '.R')).is_file() for op in operations),
      'every operation of the manifest (%d) has the help\'s script and its example to check against' % len(operations))
examples = {op: json.loads((EXAMPLES / (op + '.json')).read_text()) for op in operations}
help_scripts = {}   # the help's own script by recipe file, once each
for op in operations:
    file = manifest[op]['file']
    if file not in help_scripts: help_scripts[file] = (EXAMPLES / (op + '.R')).read_text().replace('\r', '')
help_files = sorted(help_scripts)
help_figures = dict(zip(help_files, [figures(o) if not isinstance(o, AssertionError) else o for o in r_outputs([help_scripts[f] for f in help_files])]))
broken = [f for f, o in help_figures.items() if isinstance(o, AssertionError)]
check(not broken, 'the help\'s %d scripts run in R (%s)' % (len(help_files), RSCRIPT) + ('; failed: ' + ', '.join(broken) if broken else ''))

# the harness records: the writer's text line by line, then R against the help
harness = {}
for op in operations:
    record = record_of(examples[op]); script = rs.write(record, None, [])
    harness[op] = (record, script)
mismatched = []
for op in operations:
    record, script = harness[op]; recipe, detail = recipe_of(op)
    expected = expected_script(record, recipe, detail)
    if 'error' in script or not script['hasRecipe'] or script['detail'] != detail or script['text'] != expected:
        where = first_difference(script['text'], expected) if 'text' in script else None
        mismatched.append(op); print('      %s: %s' % (op, script.get('error') or ('line %d differs: engine %r, expected %r' % where if where else 'recipe flag or detail')), flush=True)
check(not mismatched, 'the engine writes every recipe\'s script for the help\'s example exactly as the Windows writer\'s rules give it, line by line (%d operations)' % len(operations)
      + ('; differing: ' + ', '.join(mismatched) if mismatched else ''))
def compare_with_help(outputs, what):
    agreed, failures = 0, []
    for op, output in outputs:
        example = examples[op]
        if isinstance(output, AssertionError): failures.append(op); print('      %s: %s' % (op, str(output).replace('\n', ' | ')[:400]), flush=True); continue
        ours = figures(output)
        if example.get('nocompare') is True:
            if ours: agreed += 1
            else: failures.append(op + ' (printed no figure)')
            continue
        expected = help_figures[manifest[op]['file']]
        if ours == expected or (example.get('cut') is True and ours and expected.startswith(ours + ' ')): agreed += 1
        else:
            failures.append(op); a, b = ours.split(' '), expected.split(' '); i = 0
            while i < len(a) and i < len(b) and a[i] == b[i]: i += 1
            print('      %s: the figures differ from the %dth: %s %s, help %s (%d and %d figures)' % (op, i + 1, what, a[i] if i < len(a) else '(end)', b[i] if i < len(b) else '(end)', len(a), len(b)), flush=True)
    return agreed, failures
agreed, failures = compare_with_help(zip(operations, r_outputs([harness[op][1]['text'] for op in operations])), 'recipe')
check(not failures, 'every recipe prints the figures the help\'s script prints on the help\'s example: %d of %d agree' % (agreed, len(operations)) + ('; differing: ' + ', '.join(failures) if failures else ''))

# the real runs: the help's example inputs through the engine as entered frames
FOLLOW_ONS = {'FollowUpLifeTable', 'FriedmanMulti', 'PolynomialRegressionChangeDegree'}   # run from a parent result, not from the menu
runnable = [op for op in operations if op not in FOLLOW_ONS]
# A run leaves its record at the template's report step: the random number generators and the summary written to the worksheet alone have
# no report step, and the quick summary reports through its builtin, so those runs leave no record (on Windows too; its harness builds
# their records by hand, as the checks above did).
NO_REPORT_STEP = {op for op in operations if op.startswith('Rnd')} | {'UnivariateSummaryToWorksheetOnly', 'QuickSummary'}
real = {}
for op in runnable: real[op] = run_example(s, examples[op])
recorded = [op for op in runnable if op not in NO_REPORT_STEP]
without = sorted(op for op in runnable if not isinstance(real[op].get('record'), str))
check(all(isinstance(real[op].get('record'), str) for op in recorded) and without == sorted(NO_REPORT_STEP) and all(real[op].get('recipe') is True for op in runnable),
      'the help\'s example inputs run through the engine as entered frames for %d operations, %d leaving a record at their report step (the %d writing to the worksheet alone, and the quick summary\'s builtin, leave none), all with recipe true; the %d follow-ons run from a parent result'
      % (len(runnable), len(recorded), len(NO_REPORT_STEP) - 1, len(FOLLOW_ONS)) + ('; without a record: ' + ', '.join(without) if without != sorted(NO_REPORT_STEP) else ''))
# Where the dialog differs from the help's example: settings the dialog does not record under the example's name (asked on a branch the
# default answers do not take; worked out from the inputs the dialog takes instead; written back by the operation as a result under the same
# name), and the plots, which sort their columns before the report step. The rank correlation calculators record the score (df2) they work
# out of the correlation, as the Windows calculator shows and records it.
DIALOG_SETTINGS = {'Crosstabs': {'ci'}, 'SizeIndCase': {'p1'}, 'SizeIndProp': {'p1'}, 'SizeMatchProp': {'p1'}, 'SizePaired': {'sd'}, 'SizeUnPaired': {'sd'}, 'SizeSurvival': {'hr'}}
SORTED_COLUMNS = {'BoxWhiskerPlotText', 'SpreadPlot'}
problems = []
for op in recorded:
    example = examples[op]; r = json.loads(real[op]['record']); settings = example.get('settings') or {}
    try:
        assert r['version'] == 1 and r['operation'] == op and r['title'] == friendly_name(op), 'version, operation or title (%r)' % r.get('title')
        assert abs(datetime.now(iso(r['run']).tzinfo) - iso(r['run'])) < timedelta(minutes=10) and 'source' not in r and 'data' not in r, 'run time, or a source for entered data'
        entered = {c['title']: c['values'] for i in r['inputs'] if i['kind'] == 'entered' for c in i['columns']}
        tables = [i for i in r['inputs'] if i['kind'] == 'table']
        for named in example.get('inputs', []) if isinstance(example.get('inputs'), list) else []:
            kinds = {i['name']: i['kind'] for i in r['inputs']}
            assert kinds.get(named['name']) == 'entered', 'the input %s is not recorded as entered (%s)' % (named['name'], kinds.get(named['name']))
        for column in [c for key in ('data', 'list') for c in example.get(key, [])] + [c for named in (example.get('inputs') or []) for c in named['columns']]:
            got = entered.get(column['title'])
            assert got is not None, 'no entered column titled %r' % column['title']
            same = lambda g, v: g == v or (isinstance(g, str) and v is not None and g == csharp(v))
            norm = lambda v: csharp(v) if is_number(v) else str(v)
            assert len(got) == len(column['values']) and (all(same(g, v) for g, v in zip(got, column['values'])) or (op in SORTED_COLUMNS and sorted(map(norm, got)) == sorted(map(norm, column['values'])))), 'the values of %r differ' % column['title']
        if isinstance(example.get('table'), dict):
            assert tables and tables[0]['counts'] == example['table']['counts'] and isinstance(tables[0].get('rowsTitle'), str) and isinstance(tables[0].get('columnsTitle'), str) \
                   and len(tables[0]['rowLabels']) == 2 and len(tables[0]['columnLabels']) == 2 and len(tables[0]['columns']) == 2 and tables[0]['columns'][0]['values'] == [row[0] for row in example['table']['counts']], 'the table'
            assert r['parameters']['counts'] == example['table']['counts'] and r['parameters']['rowsTitle'] == tables[0]['rowsTitle'], 'the table among the settings'
        if isinstance(example.get('matrix'), dict):
            labels = example['matrix']['columnLabels']
            assert [entered.get(label) for label in labels] == [[row[c] for row in example['matrix']['counts']] for c in range(len(labels))], 'the matrix columns'
        for key, value in settings.items():
            if value is None or key in ('a', 'b', 'c', 'd', 'pt1', 'pt2') or key in DIALOG_SETTINGS.get(op, ()): continue
            got = r['parameters'].get(key)
            assert got == value or (isinstance(got, str) and got == str(value)) or (is_number(got) and is_number(value) and close(got, value, 1e-9)), 'the setting %s: recorded %r, example %r' % (key, got, value)
        for key in ('a', 'b', 'c', 'd', 'pt1', 'pt2'):
            if key in settings: assert r['parameters'].get(key) == settings[key], 'the count %s' % key
        assert all(v is None or isinstance(v, (int, float, bool, str)) for v in r['values'].values()), 'a result that is not a scalar'
        assert all(k not in r['parameters'] for k in DIALOG_SETTINGS.get(op, ())), 'a setting listed as one the dialog does not record is recorded after all'
    except AssertionError as e: problems.append(op); print('      %s: %s' % (op, e), flush=True)
check(not problems, 'the record of each real run holds the example\'s columns as entered values, its settings (a confidence level as a proportion, a typed 2 by 2 with its counts and what its rows and columns stand for) and scalar results, apart from the %d dialog differences listed in the test' % len(DIALOG_SETTINGS)
      + ('; failing: ' + ', '.join(problems) if problems else ''))
real_scripts = {op: rs.write(real[op]['record'], None, []) for op in recorded}
mismatched = []
for op in recorded:
    script = real_scripts[op]; recipe, detail = recipe_of(op); expected = expected_script(json.loads(real[op]['record']), recipe, detail)
    if 'error' in script or not script['hasRecipe'] or script['text'] != expected:
        where = first_difference(script['text'], expected) if 'text' in script else None
        mismatched.append(op); print('      %s: %s' % (op, script.get('error') or ('line %d differs: engine %r, expected %r' % where if where else 'no recipe')), flush=True)
check(not mismatched, 'the engine writes each real run\'s script exactly as the Windows writer\'s rules give it for that record, line by line (%d operations)' % len(recorded)
      + ('; differing: ' + ', '.join(mismatched) if mismatched else ''))
# the real runs' scripts against the help: the same figures where the run's settings are the help's; where the dialog differs from the help's
# example (a stated default the help's script does not take, a seed the form chose, the dialog's own labels), the difference is listed
agreed, failures = compare_with_help(zip(recorded, r_outputs([real_scripts[op]['text'] for op in recorded])), 'real run')
# Expected, and the same for a Windows run of the dialog (to raise with Windows rather than diverge): Crosstabs's recipe takes `ci`, which the
# dialog asks only with Monte Carlo (its confidence level is `cco`); LogRank's group identifier is recorded as text labels, which the recipe's
# tabulate() does not take; MiscRelRisk's help labels its columns "220 or more" and "Under 220", whose digits count as figures, where the
# dialog's labels are Present and Absent; SizePaired and SizeUnPaired write the standard deviation back as a result under the parameter's own
# name `sd`, so the record's settings lack it.
EXPECTED_REAL_DIFFERENCES = {'Crosstabs', 'LogRank', 'MiscRelRisk', 'SizePaired', 'SizeUnPaired'}
unexpected = sorted(set(failures) - EXPECTED_REAL_DIFFERENCES); newly_agreeing = sorted(EXPECTED_REAL_DIFFERENCES - set(failures))
check(not unexpected and not newly_agreeing, 'the scripts of the real runs print the help\'s figures: %d of %d agree%s' % (agreed, len(recorded), ('; differing as listed: ' + ', '.join(sorted(failures))) if failures else '')
      + ('; unexpected: ' + ', '.join(unexpected) if unexpected else '') + ('; now agreeing, remove from the list: ' + ', '.join(newly_agreeing) if newly_agreeing else ''))

# --- the inverse records of the Distributions calculator, as Inverse.cs checks them: every figure printed is among the help script's
INVERSE = [('DistributionNormal', {'upper': 0.025, 'asked': 'invert-upper'}), ('DistributionNormal', {'lower': 0.975, 'asked': 'invert-lower'}), ('DistributionNormal', {'two_sided': 0.05, 'asked': 'invert-two-sided'}),
           ('DistributionT', {'df': 10, 'upper': 0.025, 'asked': 'invert-upper'}), ('DistributionT', {'df': 10, 'lower': 0.975, 'asked': 'invert-lower'}),
           ('DistributionChiSquare', {'df': 3, 'upper': 0.01, 'asked': 'invert-upper'}), ('DistributionF', {'df': 6, 'df2': 8, 'upper': 0.05, 'asked': 'invert-upper'}),
           ('DistributionQ', {'df': 36, 'df2': 4, 'upper': 0.05, 'asked': 'invert-upper'}), ('DistributionNonCentralT', {'df': 10, 'df2': 1, 'upper': 0.1, 'asked': 'invert-upper'}),
           ('DistributionPoisson', {'df': 14, 'upper': 0.025, 'asked': 'invert-upper'}), ('DistributionPoisson', {'df': 14, 'two_sided': 0.025, 'asked': 'invert-two-sided'}),
           # the rank correlation calculators: the help works from two rankings of 10 (S = 23, T = 52), so their forward branch is checked here too
           ('DistributionKendall', {'df': 10, 'df2': 23, 'asked': 'calculate'}), ('DistributionKendall', {'df': 10, 'upper': 0.05, 'asked': 'invert-upper'}),
           ('DistributionSpearman', {'df': 10, 'df2': 52, 'asked': 'calculate'}), ('DistributionSpearman', {'df': 10, 'upper': 0.025, 'asked': 'invert-upper'})]
inverse_scripts = [rs.write({'version': 1, 'operation': op, 'title': 'Example', 'run': '2026-10-11T03:00:00+01:00', 'inputs': [], 'parameters': settings, 'values': {}}, None, []) for op, settings in INVERSE]
failures = []
for (op, settings), script, output in zip(INVERSE, inverse_scripts, r_outputs([x['text'] for x in inverse_scripts])):
    if isinstance(output, AssertionError): failures.append('%s %s: %s' % (op, settings, output)); continue
    printed = figures(output).split(); allowed = set(help_figures[manifest[op]['file']].split()); missing = [f for f in printed if f not in allowed]
    print('      %s %s: %s' % (op, json.dumps(settings), output.strip().replace('\n', ' | ')), flush=True)
    if not printed or missing: failures.append('%s %s: %s' % (op, settings, 'printed no figure' if not printed else 'not in the help\'s output: ' + ', '.join(missing)))
for f in failures: print('      ' + f, flush=True)
check(not failures and all(x['hasRecipe'] for x in inverse_scripts), 'every inverse a distribution recipe gives prints figures the help\'s script prints: %d of %d cases' % (len(INVERSE) - len(failures), len(INVERSE)))
s.finish(); rs.close()
print('PASS %d run record checks' % checks)
