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
rows and columns stand for) and its script rendered, compared and run the same way (the differences a real run has from the help's
example, shared with a Windows run of the same dialog, are listed and must stay as listed); the follow-on operations run from a parent
run through the engine, as FollowOn.cs and Regression.cs do, their records carrying the parent's frames marked inherited and their
scripts the parent's; and the inverse records of the Distributions calculator print figures the help's scripts print. The scripts run
with the program's own R library on the path, where the method comparison recipe's mcr package is installed when missing."""
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
# The packages the help's scripts and the recipes load beyond R's own (mcr for method comparison regression) live in the library the
# program keeps for R beside its own runs, where its R operations install what they need; the scripts here run with that library on
# R's path, as the program's do, and the package is installed there first when it is missing (on a fresh runner, say).
R_LIBRARY = Path(os.environ.get('STATSDIRECT_R_LIBRARY') or os.path.join(os.environ.get('STATSDIRECT_R_FOLDER') or os.path.expanduser('~/Library/Application Support/StatsDirect Viewer'), 'R Library'))
R_ENV = dict(os.environ, R_LIBS=str(R_LIBRARY))
def ensure_r_packages(*packages):
    R_LIBRARY.mkdir(parents=True, exist_ok=True)
    p = subprocess.run([RSCRIPT, '--vanilla', '-e', 'for (x in commandArgs(TRUE)) if (!requireNamespace(x, quietly = TRUE)) utils::install.packages(x, lib = Sys.getenv("R_LIBS"), repos = "https://cloud.r-project.org", quiet = TRUE, type = "binary"); cat(sapply(commandArgs(TRUE), requireNamespace, quietly = TRUE))', *packages], env=R_ENV, capture_output=True, text=True)
    if p.returncode != 0 or 'FALSE' in p.stdout: raise AssertionError('FAIL the R packages %s could not be installed in %s:\n%s\n%s' % (', '.join(packages), R_LIBRARY, p.stdout, p.stderr))
def run_r(text):
    """Runs a script as the Windows check does (Rscript --vanilla in its own folder, the program's R library on the path) and returns what it printed."""
    (ROOT / '.build').mkdir(exist_ok=True)
    folder = Path(tempfile.mkdtemp(prefix='run-record-r-', dir=ROOT / '.build'))
    script = folder / 'script.R'; script.write_text(text)
    p = subprocess.run([RSCRIPT, '--vanilla', '--encoding=UTF-8', str(script)], cwd=folder, env=R_ENV, capture_output=True, text=True)
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
# raised with Windows (the shared recipe binds the screen grid as "data", where the parameter is responsesCrosstab, so a real run's script
# gets no counts); its real run is listed among the expected differences below until the recipe is corrected
KNOWN_BINDING_MISMATCHES = {'KappaScreen'}
mismatches = []
for op, entry in manifest.items():
    text = (ROOT / 'Content/R/recipes' / entry['file']).read_text(); xml = (ROOT / 'FullEngine/publish/Operations' / (op + '.xml')).read_text()
    parameters = {m.strip() for m in re.findall(r'<name>([^<]+)</name>', xml)[1:]}
    # a follow-on operation continues an earlier run and may take that operation's parameters and frames
    if 'inherits' in entry:
        parent = (ROOT / 'FullEngine/publish/Operations' / (entry['inherits'] + '.xml')).read_text()
        parameters |= {m.strip() for m in re.findall(r'<name>([^<]+)</name>', parent)[1:]}
        if '<frame>' in parent: xml += '<frame>'
    parameters |= {m.strip() for m in re.findall(r'<(?:top-left|top-right|bottom-left|bottom-right)-name>([^<]+)</', xml)}
    if re.search(r'<builtin function-name="dist[A-Za-z]+"', xml): parameters |= {'value', 'df', 'df2', 'lower', 'upper', 'two_sided', 'asked'}
    settings = re.search(r'^# settings:\s*(.*)$', text, re.M)
    if settings:
        for item in [x.strip() for x in settings.group(1).split(',') if '=' in x]:
            parameter = item[item.index('=') + 1:].strip()
            if parameter not in parameters: mismatches.append('%s: %s takes the setting "%s"' % (op, entry['file'], parameter))
    # a grid typed on screen (a special parameter of one of these types) reaches the run as a frame too
    frames = '<frame>' in xml or '<double-2-by-2-by-k>' in xml or re.search(r'<type>(chi-2-column|chi-3-column|person-time-size|rr-index|raters-2d|likelihood|1-to-n|frame)</type>', xml) is not None
    if re.search(r'^# (data|matrix):', text, re.M) and not frames: mismatches.append('%s: %s takes columns, and the operation asks for no frame' % (op, entry['file']))
    data = re.search(r'^# data:\s*(.*)$', text, re.M)
    if data:
        for item in [x.strip() for x in data.group(1).split(',') if '=' in x]:
            bound_input = item[item.index('=') + 1:].strip()
            if bound_input not in parameters and op not in KNOWN_BINDING_MISMATCHES: mismatches.append('%s: %s takes the input "%s", which the operation does not ask for' % (op, entry['file'], bound_input))
    if re.search(r'^# table:', text, re.M) and '<double-2-by-2>' not in xml: mismatches.append('%s: %s takes a 2 by 2 table, and the operation asks for none' % (op, entry['file']))
    if not re.search(r'^# (data|table|matrix|settings):', text, re.M): mismatches.append('%s: %s has no header' % (op, entry['file']))
for mismatch in sorted(set(mismatches)): print('      mismatch: ' + mismatch, flush=True)
check(not mismatches, 'every setting, input and kind of data a recipe takes is what the operations it serves ask for (%s known otherwise)' % ', '.join(sorted(KNOWN_BINDING_MISMATCHES)))

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
def plain(value):
    """Text for a comment line as RScriptWriter.Plain gives it: each control character (a line break in a title, say) a space."""
    return ''.join(' ' if ord(ch) < 32 or ord(ch) == 0x7f else ch for ch in (value or ''))
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
            columns.append({'title': text_of(c, 'title') or '', 'values': objects(c.get('values')), 'inherited': inp.get('inherited') is True})
        groups.append((name, start, len(columns) - start))
    head = '# %s, from StatsDirect, %s\n' % (plain(title), run_time(record))
    if detail is not None: head += '# ' + plain(detail) + '\n'
    head += '\n'
    out = [head]; names = set(); bound = set()
    def assign(variable, column):
        names.add(variable); out.append(variable + ' <- ' + vector(column['values']) + '   # ' + plain(column['title']) + '\n')
    def list_of(variable, indices):
        out.append(variable + ' <- list(' + ',\n  '.join(quote(columns[i]['title']) + ' = ' + vector(columns[i]['values']) for i in indices) + ')\n'); names.add(variable)
    def missing(variable, why): names.add(variable); out.append(variable + ' <- NULL   # ' + why + '\n')
    if binding:
        for variable, source, is_list in [d for d in binding['data'] if d[1] is not None]:
            # a prompt repeated for each series, group or period gives several inputs of one name: a list takes every one of their
            # columns, a vector the first not yet taken
            indices = [i for _, start, count in groups if _ == source for i in range(start, start + count) if i not in bound]
            if not any(g[0] == source for g in groups): missing(variable, 'no "%s" in this run' % source); continue
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
        if nxt not in bound and not (binding and columns[nxt]['inherited']): assign(safe_name(columns[nxt]['title'], names), columns[nxt])   # an inherited frame the recipe does not take is left out
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
            if is_scalar(value) and not key.lower().startswith('statsdirect'): out.append(safe_name(key, names) + ' <- ' + literal(value) + '   # ' + plain(key) + '\n')
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
def survival_proportions(times, events):
    """Kaplan-Meier S at each subject's time, the rows in time order as the Kaplan-Meier function saves them."""
    s, out, i, n = 1.0, [], 0, len(times)
    while i < n:
        j = i
        while j < n and times[j] == times[i]: j += 1
        s *= 1 - sum(1 for k in range(i, j) if events[k]) / (n - i); out.extend([s] * (j - i)); i = j
    return out
def _survival_plot_s():
    e = json.loads((EXAMPLES / 'SurvivalPlot.json').read_text()); frames = {i['name']: i['columns'] for i in e['inputs']}
    return [{'title': t['title'], 'values': survival_proportions(t['values'], c['values'])} for t, c in zip(frames['xdatNew'], frames['cdatNew'])]
# columns a form wants beyond the example's: the 2 by k trend test's scores, and the survival plot's survival proportion of each group, which
# the help's script works out from the times and events with survfit (the dialog takes the column the Kaplan-Meier function saved)
REAL_RUN_COLUMNS = {'Chi2byNWithTrend': {'data': [{'title': 'score', 'values': [1, 2, 3]}]}, 'SurvivalPlot': {'ydatNew': _survival_plot_s()}}
# settings a form asks for that the example leaves to the help's layout: the number of groups or repeats whose frames it then asks for one by one
REAL_RUN_SETTINGS = {'SurvivalPlot': {'group-count': 2}, 'WeiLachin': {'nr': 4}, 'PoissonRegression': {'has-exposure': 'true'}}
def run_example(session, example, parent=None, keep=False, extra=None):
    """Answers the operation's prompts from the example: frames by the name the operation asks them by, else the example's columns in order (one
    at a time to a single-column prompt, the rest to a wider one), a screen-typed 2 by 2 from its cell settings, the Distributions calculator's
    boxes, settings by parameter name (a confidence level as a percentage, an option as its value), optional frames skipped, defaults otherwise."""
    id, state = session.start(example['operation'], parent=parent); used = set(); settings = dict(example.get('settings') or {}); settings.update(REAL_RUN_SETTINGS.get(example['operation'], {})); settings.update(extra or {})
    pool = [dict(c) for key in ('data', 'list') for c in example.get(key, [])]
    # the example's named inputs, each a pool of columns: a prompt put once for each group or repeat takes the next of them (as many as it
    # allows), and a prompt named otherwise than the example's input (a table typed on screen) takes the next input not yet used
    named = {i['name']: list(i['columns']) for i in example.get('inputs', [])} if isinstance(example.get('inputs'), list) else {}
    for extra_name, extra_columns in REAL_RUN_COLUMNS.get(example['operation'], {}).items(): named.setdefault(extra_name, []).extend(extra_columns)
    def from_named(name, p):
        if name not in named:
            rest = [n for n in named if named[n]]
            if not rest: return None
            name = rest[0]
        if not named[name]: return None
        k = min(p.get('maxColumns') or len(named[name]), len(named[name])); take = named[name][:k]; del named[name][:k]
        return {'columns': take, 'source': 'Help example'}
    def answer(p):
        name = p.get('name'); kind = p['kind']
        if kind == 'grid':
            if p.get('screen') and len(p.get('labels') or []) == 2:
                keys = ('a', 'b', 'c', 'd') if 'c' in settings else ('a', 'b', 'pt1', 'pt2')
                if all(k in settings for k in keys):
                    a, b, c, d = (settings[k] for k in keys)
                    return {'columns': [{'title': p['labels'][0], 'values': [a, c]}, {'title': p['labels'][1], 'values': [b, d]}], 'source': 'Help example'}
            if name in named or not p.get('skip'):   # an optional frame the example does not give (a baseline, a confidence limit) is skipped below
                answer_from_named = from_named(name, p)
                if answer_from_named is not None: return answer_from_named
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
            if kind == 'grid': return v
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
    if not keep or state.get('state') != 'complete': session.close(id)
    if state.get('state') != 'complete': raise AssertionError('%s: %s' % (example['operation'], state.get('error')))
    if keep: state['jobId'] = id
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
ensure_r_packages('mcr')   # the help's method comparison regression, through the mcr package as the operation runs it
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
        expected = help_figures[manifest[op]['file']]; allowed = set(expected.split())
        if ours == expected or (example.get('cut') is True and ours and expected.startswith(ours + ' ')) or (example.get('subset') is True and ours and all(f in allowed for f in ours.split())): agreed += 1
        else:
            failures.append(op); a, b = ours.split(' '), expected.split(' '); i = 0
            while i < len(a) and i < len(b) and a[i] == b[i]: i += 1
            print('      %s: the figures differ from the %dth: %s %s, help %s (%d and %d figures)' % (op, i + 1, what, a[i] if i < len(a) else '(end)', b[i] if i < len(b) else '(end)', len(a), len(b)), flush=True)
    return agreed, failures
agreed, failures = compare_with_help(zip(operations, r_outputs([harness[op][1]['text'] for op in operations])), 'recipe')
check(not failures, 'every recipe prints the figures the help\'s script prints on the help\'s example: %d of %d agree' % (agreed, len(operations)) + ('; differing: ' + ', '.join(failures) if failures else ''))

# the real runs: the help's example inputs through the engine as entered frames
INHERITING = {op: manifest[op]['inherits'] for op in operations if 'inherits' in manifest[op]}   # the follow-ons whose record carries the parent's frames
FOLLOW_ONS = {'FollowUpLifeTable', 'FriedmanMulti', 'PolynomialRegressionChangeDegree'} | set(INHERITING)   # run from a parent result, not from the menu
DEFERRED = {'MethodComparisonRegression'}   # R-based, not hosted on the Mac yet: its recipe is checked above, its real run waits for the host
runnable = [op for op in operations if op not in FOLLOW_ONS and op not in DEFERRED]
# A run leaves its record at the template's report step: the random number generators and the summary written to the worksheet alone have
# no report step, and the quick summary reports through its builtin, so those runs leave no record (on Windows too; its harness builds
# their records by hand, as the checks above did).
NO_REPORT_STEP = {op for op in operations if op.startswith('Rnd')} | {'UnivariateSummaryToWorksheetOnly', 'QuickSummary'}
real = {}; not_run = {}
for op in runnable:
    try: real[op] = run_example(s, examples[op])
    except AssertionError as e: not_run[op] = str(e).replace('\n', ' | ')[:300]
for op, why in sorted(not_run.items()): print('      not run, %s' % why, flush=True)
check(not not_run, 'every operation of the manifest that is not a follow-on runs through the engine on the help\'s example (%d of %d; %s deferred on the Mac)' % (len(real), len(runnable), ', '.join(sorted(DEFERRED))) + ('; not run: ' + ', '.join(sorted(not_run)) if not_run else ''))
recorded = [op for op in runnable if op not in NO_REPORT_STEP]
without = sorted(op for op in runnable if not isinstance(real[op].get('record'), str))
check(all(isinstance(real[op].get('record'), str) for op in recorded) and without == sorted(NO_REPORT_STEP) and all(real[op].get('recipe') is True for op in runnable),
      'the help\'s example inputs run through the engine as entered frames for %d operations, %d leaving a record at their report step (the %d writing to the worksheet alone, and the quick summary\'s builtin, leave none), all with recipe true; the %d follow-ons run from a parent result'
      % (len(runnable), len(recorded), len(NO_REPORT_STEP) - 1, len(FOLLOW_ONS)) + ('; without a record: ' + ', '.join(without) if without != sorted(NO_REPORT_STEP) else ''))
# Where the dialog differs from the help's example: settings the dialog does not record under the example's name (asked on a branch the
# default answers do not take; worked out from the inputs the dialog takes instead; written back by the operation as a result under the same
# name), and the plots, which sort their columns before the report step. The rank correlation calculators record the score (df2) they work
# out of the correlation, as the Windows calculator shows and records it.
DIALOG_SETTINGS = {'SizeIndCase': {'p1'}, 'SizeIndProp': {'p1'}, 'SizeMatchProp': {'p1'}, 'SizeSurvival': {'hr'}}
SORTED_COLUMNS = {'BoxWhiskerPlotText', 'SpreadPlot'}
RENAMED_INPUTS = {'KappaScreen': {'data': 'responsesCrosstab'}}   # the example names an input otherwise than the parameter the dialog records it under
def equivalent(got, values, op):
    """Whether a recorded column holds the example's values: as numbers or their texts (a categorical column), a date typed as text recorded as
    the worksheet's serial day, a shorter column of an entered frame padded with missing values to the frame's height, or sorted for the plots."""
    def norm(v): return csharp(v) if is_number(v) else v
    def serial(v): return (datetime.strptime(v, '%Y-%m-%d') - datetime(1899, 12, 30)).days if isinstance(v, str) and re.fullmatch(r'\d{4}-\d{2}-\d{2}', v) else v
    g = list(got); v = list(values)
    while len(g) > len(v) and g[-1] is None: g.pop()
    if len(g) != len(v): return False
    if all(a == b or (a is not None and b is not None and norm(a) == norm(b)) or a == serial(b) for a, b in zip(g, v)): return True
    return op in SORTED_COLUMNS and sorted(map(norm, g)) == sorted(map(norm, v))
problems = []
for op in recorded:
    example = examples[op]; r = json.loads(real[op]['record']); settings = example.get('settings') or {}
    try:
        assert r['version'] == 1 and r['operation'] == op and r['title'] == friendly_name(op), 'version, operation or title (%r)' % r.get('title')
        assert abs(datetime.now(iso(r['run']).tzinfo) - iso(r['run'])) < timedelta(minutes=10) and 'source' not in r and 'data' not in r, 'run time, or a source for entered data'
        entered = {}   # the entered columns under each input's name, those of a prompt put once for each group or repeat gathered
        for i in r['inputs']:
            if i['kind'] == 'entered': entered.setdefault(i['name'], []).extend(i['columns'])
        kinds = {i['name']: i['kind'] for i in r['inputs']}; renamed = RENAMED_INPUTS.get(op, {})
        tables = [i for i in r['inputs'] if i['kind'] == 'table']
        wanted = [(None, c) for key in ('data', 'list') for c in example.get(key, [])]
        for named in example.get('inputs', []) if isinstance(example.get('inputs'), list) else []:
            name = renamed.get(named['name'], named['name'])
            assert kinds.get(name) == 'entered', 'the input %s is not recorded as entered (%s)' % (name, kinds.get(name))
            wanted += [(name, c) for c in named['columns']]
        every = [c for columns in entered.values() for c in columns]
        for name, column in wanted:
            # a frame asked once per group or repeat is recorded under its name for the last ask, and the frame the asks built up
            # (the operation's own) carries every column: a column not under the name is looked for in the rest
            titled = [c['values'] for c in (entered.get(name, []) if name else []) + every if c['title'] == column['title']]
            assert titled, 'no entered column titled %r%s' % (column['title'], ' under ' + name if name else '')
            assert any(equivalent(got, column['values'], op) for got in titled), 'the values of %r differ: recorded %s' % (column['title'], json.dumps(titled[0])[:120])
        if isinstance(example.get('table'), dict):
            assert tables and tables[0]['counts'] == example['table']['counts'] and isinstance(tables[0].get('rowsTitle'), str) and isinstance(tables[0].get('columnsTitle'), str) \
                   and len(tables[0]['rowLabels']) == 2 and len(tables[0]['columnLabels']) == 2 and len(tables[0]['columns']) == 2 and tables[0]['columns'][0]['values'] == [row[0] for row in example['table']['counts']], 'the table'
            assert r['parameters']['counts'] == example['table']['counts'] and r['parameters']['rowsTitle'] == tables[0]['rowsTitle'], 'the table among the settings'
        if isinstance(example.get('matrix'), dict):
            labels = example['matrix']['columnLabels']; every = [c for columns in entered.values() for c in columns]
            assert [next((c['values'] for c in every if c['title'] == label), None) for label in labels] == [[row[c] for row in example['matrix']['counts']] for c in range(len(labels))], 'the matrix columns'
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
# Expected, and the same for a Windows run of the dialog (raised with Windows rather than diverged from): Crosstabs's classifiers are recorded
# as text ("0", "1"), as the category mode reads them, and the recipe takes the help's numbers (mean(v) of text is NA); KappaScreen's recipe
# binds "data" where the grid's parameter is responsesCrosstab; LogisticRegression's recipe takes the rest of the columns as the predictors,
# and the rest includes the prediction grid's source (Name, Value, Old value) the regression leaves in the bag, which the writer leaves out
# of named vectors but not of the rest list; MiscRelRisk's help labels its columns "220 or more" and "Under 220", whose digits count as
# figures, where the dialog's labels are Present and Absent; SurvivalPlot's and WeiLachin's frames are asked once for each group or repeat,
# and the record keeps a parameter's last ask alone (OperationRun.Note), so their scripts hold the last group's columns.
EXPECTED_REAL_DIFFERENCES = {'Crosstabs', 'KappaScreen', 'LogisticRegression', 'MiscRelRisk', 'SurvivalPlot', 'WeiLachin'}
unexpected = sorted(set(failures) - EXPECTED_REAL_DIFFERENCES); newly_agreeing = sorted(EXPECTED_REAL_DIFFERENCES - set(failures))
check(not unexpected and not newly_agreeing, 'the scripts of the real runs print the help\'s figures: %d of %d agree%s' % (agreed, len(recorded), ('; differing as listed: ' + ', '.join(sorted(failures))) if failures else '')
      + ('; unexpected: ' + ', '.join(unexpected) if unexpected else '') + ('; now agreeing, remove from the list: ' + ', '.join(newly_agreeing) if newly_agreeing else ''))

# --- the follow-on operations through the engine from a parent run, as FollowOn.cs and Regression.cs check them on Windows: the record
# carries the frames the follow-on inherited from the parent's run, marked inherited, with the parent's columns; its script is the parent's
# (the same recipe on the same data) where it asked for no frame of its own, and holds every line of the parent's where it did; and its
# text is what the writer's rules give for its record (an inherited frame no variable of the recipe takes is left out)
FOLLOW_ON_ANSWERS = {}   # answers to the prompts a follow-on puts of its own, beyond its example's settings, by operation
follow_on_problems = []; inherited_frames = 0
for op, parent_op in sorted(INHERITING.items()):
    try:
        parent_state = run_example(s, examples[parent_op], keep=True)
        try: child = run_example(s, examples[op], parent=parent_state['jobId'], extra=FOLLOW_ON_ANSWERS.get(op))
        finally: s.close(parent_state['jobId'])
        pr = json.loads(parent_state['record']); cr = json.loads(child['record'])
        inherited = [i for i in cr['inputs'] if i.get('inherited') is True]
        own = [i for i in cr['inputs'] if i.get('inherited') is not True and i['kind'] in ('frame', 'entered', 'table')]
        # the frames the parent asked for (a frame the parent itself held in the bag, the prediction grid's source, may be the follow-on's own input)
        parent_frames = [i for i in pr['inputs'] if i['kind'] in ('frame', 'entered') and i.get('inherited') is not True]
        assert cr['operation'] == op and child.get('recipe') is True, 'operation %r or recipe flag %r' % (cr['operation'], child.get('recipe'))
        assert inherited and all(i['kind'] == 'entered' and i.get('prompt') == '' for i in inherited), 'no frame marked inherited among the inputs %s' % [(i['name'], i['kind'], i.get('inherited')) for i in cr['inputs']]
        for frame in parent_frames:
            match = [i for i in inherited if i['name'] == frame['name']]
            assert match and match[0]['columns'] == frame['columns'], 'the parent\'s frame %s is not inherited with its columns' % frame['name']
        inherited_frames += len(inherited)
        parent_script = rs.write(parent_state['record'], None, []); child_script = rs.write(child['record'], None, [])
        a, b = parent_script['text'].split('\n')[1:], child_script['text'].split('\n')[1:]
        if not own: assert b == a, 'the scripts differ at line %d: parent %r, follow-on %r' % first_difference(parent_script['text'], child_script['text'])
        else:
            rest = iter(b); assert all(line in rest for line in a), 'the parent\'s script lines are not all in the follow-on\'s (which asked for %s itself)' % [i['name'] for i in own]
        expected = expected_script(cr, *recipe_of(op))
        assert child_script['text'] == expected, 'line %d differs from the writer\'s rules: engine %r, expected %r' % first_difference(child_script['text'], expected)
    except AssertionError as e: follow_on_problems.append(op); print('      %s: %s' % (op, str(e).replace('\n', ' | ')[:600]), flush=True)
check(not follow_on_problems, 'the %d follow-on operations run from a parent run record the frames they inherit (%d), marked inherited, and their scripts are the parent run\'s, the recipe on the inherited data' % (len(INHERITING), inherited_frames)
      + ('; failing: ' + ', '.join(follow_on_problems) if follow_on_problems else ''))

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
