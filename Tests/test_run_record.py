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
scripts the parent's; the two-level inputs (the replicated two-way and nested analyses of variance, the grouped covariance) run
through the Mac's own prompts and are recorded as the frame2d and covariance kinds the "# nested:" header takes; and the inverse records
of the Distributions calculator print figures the help's scripts print; and, as Options.cs, Options2.cs and Options3.cs do, runs with the
options, sizes and confidence levels the help's examples do not have go through the Mac's own prompts, their scripts run in R, and the
figures and limits R prints are compared with the engine's. The scripts run with the program's own R library on the path, where the
method comparison recipe's mcr package is installed when missing."""
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
headed = [f.name for f in (ROOT / 'Content/R/recipes').glob('*.R') if f.name not in ('chart-common.R', 'dose-response-common.R') and not f.read_text().startswith('# StatsDirect recipe:')]
check(len(manifest) >= 28 and not missing and not headed and all((ROOT / 'Content/R/recipes' / e['file']).is_file() for e in manifest.values()),
      'every manifest operation is a published operation with a headed recipe file')
# the recipes against the definitions of the operations they are mapped to, as tests/RScript/Script.cs CheckRecipes: every setting a recipe
# takes is a parameter of each operation it serves (or a cell of its 2 by 2 table, or a box of the Distributions calculator), and the data it
# takes are of the kind the operation asks for
KNOWN_BINDING_MISMATCHES = set()   # operations whose recipe is known to bind an input the operation does not ask for (raised with Windows)
def definition(op): return re.sub(r'<!--.*?-->', '', (ROOT / 'FullEngine/publish/Operations' / (op + '.xml')).read_text(), flags=re.S)   # a parameter commented out is not asked, so no run records it
mismatches = []
for op, entry in manifest.items():
    text = (ROOT / 'Content/R/recipes' / entry['file']).read_text(); xml = definition(op)
    parameters = {m.strip() for m in re.findall(r'<name>([^<]+)</name>', xml)[1:]} | set(re.findall(r'<option name="([^"]+)"', xml))   # the options of a set of options, which the dialog records one by one under their names
    parameters |= {'statsdirectOperation', 'statsdirectRootOperation'}  # the writer exposes saved-record provenance to routed recipes
    # a follow-on operation continues an earlier run and may take that operation's parameters and frames
    if 'inherits' in entry:
        parent = definition(entry['inherits'])
        parameters |= {m.strip() for m in re.findall(r'<name>([^<]+)</name>', parent)[1:]} | set(re.findall(r'<option name="([^"]+)"', parent))
        if '<frame>' in parent: xml += '<frame>'
    parameters |= {m.strip() for m in re.findall(r'<(?:top-left|top-right|bottom-left|bottom-right)-name>([^<]+)</', xml)}
    if re.search(r'<builtin function-name="dist[A-Za-z]+"', xml): parameters |= {'value', 'df', 'df2', 'lower', 'upper', 'two_sided', 'asked'}
    if '<chart-type>BoxWhisker</chart-type>' in xml: parameters.add('boxWhisker')   # final chart dialog choices recorded by the shared processor
    if '<chart' in xml: parameters.add('chartSettings')   # portable final settings for the chart actually drawn
    if op == 'ROCPlot': parameters.add('rocCutoffs')
    if op in ('Probit', 'Logit') or op.startswith('Probit'): parameters.add('doseResponseModel')
    if '<grouped-covariance>' in xml: parameters.add('ci')   # its confidence level is asked through the grid and recorded as the setting ci
    settings = re.search(r'^# settings:\s*(.*)$', text, re.M)
    if settings:
        for item in [x.strip() for x in settings.group(1).split(',') if '=' in x]:
            parameter = item[item.index('=') + 1:].strip()
            if parameter not in parameters: mismatches.append('%s: %s takes the setting "%s"' % (op, entry['file'], parameter))
    # a grid typed on screen (a special parameter of one of these types) reaches the run as a frame too
    frames = '<frame>' in xml or '<double-2-by-2-by-k>' in xml or re.search(r'<type>(chi-2-column|chi-3-column|person-time-size|rr-index|raters-2d|likelihood|1-to-n|frame)</type>', xml) is not None
    if re.search(r'^# (data|matrix):', text, re.M) and not frames: mismatches.append('%s: %s takes columns, and the operation asks for no frame' % (op, entry['file']))
    # every input a recipe binds by name must be a parameter the operation, or the operation it continues, asks for
    for header in re.finditer(r'^# (?:data|nested):[ ]*(.*)$', text, re.M):
        for item in [x.strip() for x in header.group(1).split(',') if '=' in x]:
            bound_input = item[item.index('=') + 1:].strip()
            if bound_input not in parameters and op not in KNOWN_BINDING_MISMATCHES: mismatches.append('%s: %s takes the input "%s", which the operation does not ask for' % (op, entry['file'], bound_input))
    if re.search(r'^# table:', text, re.M) and '<double-2-by-2>' not in xml: mismatches.append('%s: %s takes a 2 by 2 table, and the operation asks for none' % (op, entry['file']))
    if re.search(r'^# nested:', text, re.M) and '<frame2d>' not in xml and '<grouped-covariance>' not in xml: mismatches.append('%s: %s takes a two-level input, and the operation asks for none' % (op, entry['file']))
    if not re.search(r'^# (data|table|matrix|nested|settings):', text, re.M): mismatches.append('%s: %s has no header' % (op, entry['file']))
    # a package the recipe loads is installed first when it is missing, so that the script runs where the package is not yet
    for library in re.finditer(r'^[ ]*library\((\w[\w.]*)\)', text, re.M):
        if 'if (!requireNamespace("%s", quietly = TRUE)) install.packages("%s"' % (library.group(1), library.group(1)) not in text:
            mismatches.append('%s: %s loads %s without installing it first when it is missing' % (op, entry['file'], library.group(1)))
for definition in sorted((ROOT / 'FullEngine/publish/Operations').glob('*.xml')):   # every operation that continues one with a recipe has a recipe of its own
    prerequisite = re.search(r'<prerequisite-operation>\s*([^<\s]+)\s*</prerequisite-operation>', definition.read_text())
    if prerequisite and prerequisite.group(1) in manifest and definition.stem not in manifest: mismatches.append('%s: continues %s, which has a recipe, and has none of its own' % (definition.stem, prerequisite.group(1)))
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
# a frame asked once per pass of a loop (the groups of a survival plot) is several inputs of one name, their kept values under keys the
# inputs' "held" names; over the threshold the host reads them again and supplies one frame per input in the record's order, and each
# read takes the next supplied frame of that name
two = json.loads(big_record); first = two['inputs'][0]; second = json.loads(json.dumps(first))
first['columns'] = first['columns'][:1]; second['columns'] = second['columns'][1:]; second['held'] = 'data#2'; two['inputs'] = [first, second] + two['inputs'][1:]
script = rs.write(two, None, [{'name': 'data', 'columns': same[0]['columns'][:1]}, {'name': 'data', 'columns': same[0]['columns'][1:]}])
check(script['asked'] == ['data', 'data'] and 'NOTE' not in script['text'] and re.search(r'^before <- c\(100, ', script['text'], re.M) and re.search(r'^after <- c\(111, ', script['text'], re.M),
      'two inputs of one name, asked once per pass of a loop, take the frames supplied in the record\'s order, each with its own values and no NOTE')
# --- a column that has moved along the sheet since the run (output columns written to its left, a column inserted or removed by hand), as
# tests/RScript/Relocate.cs checks ColumnLocator on Windows and FrameReader applies it: the entry looks for a column whose hash no longer
# matches among the candidate columns the host supplies (one column at a time to the right and the left, within 64), by hash and title;
# without candidates it names the columns to look for, and the host supplies them in a second call
blank = [''] * 2600
def band(columns):
    """Candidate columns by place: {place: (title, values)}."""
    return [{'column': place, 'title': title, 'values': [str(v) for v in values], 'kinds': ['number' if v != '' else 'blank' for v in values]} for place, (title, values) in sorted(columns.items())]
def at_recorded(x_title, x_values, y_title, y_values):
    return {'name': 'data', 'index': 0, 'columns': [{'title': x_title, 'values': [str(v) for v in x_values], 'kinds': ['number'] * 2600}, {'title': y_title, 'values': [str(v) for v in y_values], 'kinds': ['number'] * 2600}]}
# 1. the first call, without candidates: the columns at the recorded places hold other values, and the engine asks the host to look
shifted = at_recorded('x', blank, 'y', x)   # a column inserted to the left: blanks at 4, x's values at 5
script = rs.write(big_record, None, [shifted])
check(script['relocate'] == [{'frame': 0, 'name': 'data', 'column': 0, 'place': 4, 'firstRow': 1, 'lastRow': 2601, 'hasTitle': True, 'sheet': 'Big'},
                             {'frame': 0, 'name': 'data', 'column': 1, 'place': 5, 'firstRow': 1, 'lastRow': 2601, 'hasTitle': True, 'sheet': 'Big'}] and script['text'].count('# NOTE:') == 2 and ' has moved ' not in script['text'],
      'without candidates the entry names each column whose values are not at its recorded place, by frame, place and rows, and the script says they changed for now')
# 2. the second call, with the band either side: x found at 5 and y at 6, each noted as moved with its new place, values as they were
shifted['candidates'] = band({3: ('', blank), 5: ('x', x), 6: ('y', y), 7: ('', blank)})
script = rs.write(big_record, None, [shifted])
notes = [l for l in script['text'].split('\n') if l.startswith('# NOTE:')]
check(script['relocate'] == [] and notes == ['# NOTE: "x" has moved along the sheet since the analysis ran, by columns inserted or removed to its left; its values are as they were.',
                                            '# NOTE: "y" has moved along the sheet since the analysis ran, by columns inserted or removed to its left; its values are as they were.']
      and '   # x, column 5, rows 1 to 2601\n' in script['text'] and '   # y, column 6, rows 1 to 2601\n' in script['text'] and re.search(r'^before <- c\(100, ', script['text'], re.M) and re.search(r'^after <- c\(111, ', script['text'], re.M),
      'a column inserted to the left: both columns found one to the right by hash and title, noted as moved with their new places, their values as they were')
# 3. a column removed to the left: y found at 4, one to the left
removed = at_recorded('x', y, 'y', blank); removed['candidates'] = band({3: ('x', x), 4: ('y', y), 6: ('', blank)})
script = rs.write(big_record, None, [removed])
check([l for l in script['text'].split('\n') if l.startswith('# NOTE:')] == ['# NOTE: "x" has moved along the sheet since the analysis ran, by columns inserted or removed to its left; its values are as they were.',
                                                                                 '# NOTE: "y" has moved along the sheet since the analysis ran, by columns inserted or removed to its left; its values are as they were.']
      and '   # x, column 3, rows 1 to 2601\n' in script['text'] and '   # y, column 4, rows 1 to 2601\n' in script['text'], 'columns removed to the left: both found to the left')
# 4. values that have changed are found nowhere: changed, not moved; a column with the right values under another title is not taken
changed_values = [v + 1 for v in x]
altered = at_recorded('x', changed_values, 'y', y); altered['candidates'] = band({3: ('x', changed_values), 5: ('z', x), 6: ('', blank)})
script = rs.write(big_record, None, [altered])
check([l for l in script['text'].split('\n') if l.startswith('# NOTE:')] == ['# NOTE: "x" has changed in the workbook since the analysis ran; these are its values now.'] and '   # x, column 4, rows 1 to 2601\n' in script['text'] and re.search(r'^before <- c\(101, ', script['text'], re.M),
      'a column whose values changed is noted as changed at its recorded place; the values under another title are not taken for it')
# 5. a column beyond the reach is not found; without a title to go by the hash alone identifies a column
far = at_recorded('x', blank, 'y', y); far['candidates'] = band({70: ('x', x)})
script = rs.write(big_record, None, [far])
check(script['text'].count('# NOTE: "x" has changed') == 1 and ' has moved ' not in script['text'], 'a column beyond the reach of 64 is not found')
untitled = json.loads(big_record); untitled['inputs'][0]['columns'][0]['hasTitle'] = False; untitled['inputs'][0]['columns'][0]['rows'] = [2, 2601]
plain_frame = at_recorded('x', blank, 'y', y); plain_frame['candidates'] = band({5: ('something else', x)})
script = rs.write(untitled, None, [plain_frame])
check('# NOTE: "x" has moved along the sheet' in script['text'] and '   # x, column 5, rows 2 to 2601\n' in script['text'], 'without a title the hash alone identifies the column')
# 6. a pointer without a hash keeps its recorded place
unhashed = json.loads(big_record); del unhashed['inputs'][0]['columns'][0]['hash']
script = rs.write(unhashed, None, [at_recorded('x', blank, 'y', y)])
check('# NOTE:' not in script['text'] and script['relocate'] == [] and re.search(r'^before <- c\(NA, NA, ', script['text'], re.M), 'a pointer without a hash keeps its recorded place and is not looked for')
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
    b = {'data': [], 'list': None, 'table': None, 'matrix': None, 'nested': [], 'settings': [], 'body': ''}
    lines = recipe.replace('\r\n', '\n').split('\n'); last = -1; i = 0
    while i < len(lines) and (lines[i].strip() == '' or lines[i].startswith('#')):
        m = re.match(r'^#\s*(data|table|matrix|nested|settings|recipe):\s*(.*)$', lines[i], re.I)
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
        elif what == 'nested':
            for item in [x.strip() for x in rest.split(',') if x.strip()]:
                eq = item.find('=')
                if eq > 0: b['nested'].append((item[:eq].strip(), item[eq + 1:].strip()))
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
    """The script RScriptWriter.Write gives for a record without pointer frames (entered frames, two-level inputs, tables, settings), with no title given."""
    operation = text_of(record, 'operation') or ''
    title = text_of(record, 'title') or operation
    binding = parse_recipe(recipe) if recipe is not None else None
    columns, tables, groups, nested = [], [], [], {}
    for inp in record.get('inputs', []) if isinstance(record.get('inputs'), list) else []:
        name = text_of(inp, 'name') or 'input'; kind = text_of(inp, 'kind') or 'other'; start = len(columns); inherited = inp.get('inherited') is True
        if kind == 'table':
            counts = inp.get('counts') if isinstance(inp.get('counts'), list) else []
            rows = [[literal(v) for v in r] if isinstance(r, list) else [literal(r)] for r in counts]
            def strings(key): return [v if isinstance(v, str) else json.dumps(v) for v in inp[key]] if isinstance(inp.get(key), list) else []
            tables.append((rows, strings('rowLabels'), strings('columnLabels'), text_of(inp, 'rowsTitle'), text_of(inp, 'columnsTitle')))
            continue
        if kind in ('frame2d', 'covariance') and isinstance(inp.get('value'), dict): nested[name] = (inp['value'], inherited); continue   # a two-level input, kept whole for a nested list
        if kind not in ('frame', 'entered'): continue
        if kind == 'frame': raise AssertionError('expected_script renders records without pointer frames')
        for c in inp.get('columns', []) if isinstance(inp.get('columns'), list) else []:
            columns.append({'title': text_of(c, 'title') or '', 'values': objects(c.get('values')), 'inherited': inherited})
        groups.append((name, start, len(columns) - start))
    head = '# %s, from StatsDirect, %s\n' % (plain(title), run_time(record))
    if detail is not None: head += '# ' + plain(detail) + '\n'
    head += '\n'
    out = [head]; names = set(); bound = set()
    # a recipe that names every input it takes (no positional column, no rest list, no table or matrix) gets only those; and when the run
    # asked for frames itself, the bag's inherited frames are not its data, so the rest list leaves them out
    named_only = bool(binding) and binding['list'] is None and binding['matrix'] is None and binding['table'] is None and all(d[1] is not None for d in binding['data']) and bool(binding['data'] or binding['nested'])
    own_frames = any(not c['inherited'] for c in columns)
    def assign(variable, column):
        names.add(variable); out.append(variable + ' <- ' + vector(column['values']) + '   # ' + plain(column['title']) + '\n')
    def list_of(variable, indices):
        out.append(variable + ' <- list(' + ',\n  '.join(quote(columns[i]['title']) + ' = ' + vector(columns[i]['values']) for i in indices) + ')\n'); names.add(variable)
    def missing(variable, why): names.add(variable); out.append(variable + ' <- NULL   # ' + why + '\n')
    def nested_list(variable, value):
        # a two-level input as a list of lists, the inner vectors named by their titles when they have any
        names.add(variable); frames = value.get('frames')
        if not isinstance(frames, list): out.append(variable + " <- NULL   # the run's data were too many to keep with the result\n"); return
        levels = []
        for level in frames:
            items = []
            for c in level if isinstance(level, list) else []:
                t = text_of(c, 'title'); items.append(('' if not t else quote(t) + ' = ') + vector(objects(c.get('values') if isinstance(c, dict) else None)))
            levels.append('list(' + ', '.join(items) + ')')
        out.append(variable + ' <- list(\n  ' + ',\n  '.join(levels) + ')\n')
    if binding:
        for variable, source, is_list in [d for d in binding['data'] if d[1] is not None]:
            # a prompt repeated for each series, group or period gives several inputs of one name: a list takes every one of their
            # columns, a vector the first not yet taken
            indices = [i for _, start, count in groups if _ == source for i in range(start, start + count) if i not in bound]
            if not any(g[0] == source for g in groups): missing(variable, 'no "%s" in this run' % source); continue
            if is_list: list_of(variable, indices); bound.update(indices)
            elif indices: assign(variable, columns[indices[0]]); bound.add(indices[0])
            else: missing(variable, 'no column of "%s" is left for it' % source)
    nested_taken = set()
    if binding:
        for variable, source in binding['nested']:
            if source not in nested: missing(variable, 'no "%s" in this run' % source); continue
            nested_taken.add(source); nested_list(variable, nested[source][0])
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
        list_of(binding['list'], [i for i in range(len(columns)) if i not in bound and not (own_frames and columns[i]['inherited'])]); nxt = len(columns)   # the rest list: not the bag's grids
    while nxt < len(columns):
        if nxt not in bound and not (binding and columns[nxt]['inherited']) and not named_only: assign(safe_name(columns[nxt]['title'], names), columns[nxt])   # an inherited frame the recipe does not take is left out
        nxt += 1
    for name, (value, inherited) in nested.items():
        if name not in nested_taken and not (binding and inherited) and not named_only: nested_list(safe_name(name, names), value)   # as for the columns: without a recipe every input is written
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
        # a bound setting the record holds is written as its literal (a list of marks as list(...), null as NULL); one the run skipped or was
        # not asked for is NULL with a note, so that the script does not stop on the missing name
        for variable, parameter in binding['settings']:
            source = {key: record[field] for key, field in [('statsdirectOperation', 'operation'), ('statsdirectRootOperation', 'rootOperation')] if field in record} if parameter in ('statsdirectOperation', 'statsdirectRootOperation') else parameters
            if source is not None and parameter in source and (is_scalar(source[parameter]) or source[parameter] is None or isinstance(source[parameter], (list, dict))): out.append(variable + ' <- ' + literal(source[parameter]) + '\n')
            else: out.append(variable + ' <- NULL   # the run had no ' + plain(parameter) + '\n')
    elif parameters is not None:
        for key, value in parameters.items():
            if is_scalar(value) and not key.lower().startswith('statsdirect'): out.append(safe_name(key, names) + ' <- ' + literal(value) + '   # ' + plain(key) + '\n')
    out.append('\n')
    if binding and any(parameter == 'chartSettings' for _, parameter in binding['settings']):
        out.append((ROOT / 'Content/R/recipes/chart-common.R').read_text().rstrip('\n') + '\n')
    if binding and any(parameter == 'doseResponseModel' for _, parameter in binding['settings']):
        out.append((ROOT / 'Content/R/recipes/dose-response-common.R').read_text().rstrip('\n') + '\n')
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
def recipe_of(operation, record=None):
    entry = manifest[operation]
    root = (record or {}).get('rootOperation', entry.get('inherits', operation))
    file = entry.get('parentFiles', {}).get(root, entry['file'])
    return (ROOT / 'Content/R/recipes' / file).read_text(), entry['detail']

# --- the record a run on the help's example would leave, as Recipes.cs's RecordOf builds it
def record_of(example):
    inputs = []
    for named in example.get('inputs', []) if isinstance(example.get('inputs'), list) else []:
        inputs.append({'name': named['name'], 'prompt': named['name'], 'kind': 'entered', 'columns': named['columns']})
    for two in example.get('nested', []) if isinstance(example.get('nested'), list) else []:   # a two-level input: its blocks or groups, each a list of columns
        inputs.append({'name': two['name'], 'prompt': two['name'], 'kind': 'frame2d', 'value': {'frames': two['frames']}})
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
    root = example.get('rootOperation', manifest[example['operation']].get('inherits', example['operation']))
    return {'version': 1, 'operation': example['operation'], 'rootOperation': root, 'title': 'Example', 'run': '2026-10-11T03:00:00+01:00', 'inputs': inputs, 'parameters': example.get('settings', {}), 'values': {}}

# --- the help's example inputs through the engine as entered frames: the record of a real run
# The 2 by k trend form also asks for category scores. Survival fixtures now
# contain the actual S and confidence-limit columns supplied to the plot form.
REAL_RUN_COLUMNS = {'Chi2byNWithTrend': {'data': [{'title': 'score', 'values': [1, 2, 3]}]}}
# settings a form asks for that the example leaves to the help's layout: the number of groups or repeats whose frames it then asks for one by one
REAL_RUN_SETTINGS = {'SurvivalPlot': {'group-count': 2}, 'WeiLachin': {'nr': 4}, 'PoissonRegression': {'has-exposure': 'true'}}
def run_example(session, example, parent=None, keep=False, extra=None, preferences=None):
    """Answers the operation's prompts from the example: frames by the name the operation asks them by, else the example's columns in order (one
    at a time to a single-column prompt, the rest to a wider one), a screen-typed 2 by 2 from its cell settings, the Distributions calculator's
    boxes, settings by parameter name (a confidence level as a percentage, an option as its value), optional frames skipped, defaults otherwise."""
    id, state = session.start(example['operation'], preferences, parent=parent); used = set(); settings = dict(example.get('settings') or {}); settings.update(REAL_RUN_SETTINGS.get(example['operation'], {})); settings.update(extra or {})
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
        return {'columns': take, 'source': 'Help example', 'preserveRows': True}
    nested_frames = example['nested'][0]['frames'] if isinstance(example.get('nested'), list) and example['nested'] else None
    def answer(p):
        name = p.get('name'); kind = p['kind']; prompt = p.get('prompt') or ''
        if nested_frames is not None:
            # a two-level input as the Mac form asks it in separate columns: the number of groups or repeats, then one grid per group
            # (its subgroups) or per repeat (subjects in rows, treatments in columns: the example's blocks hold each treatment's repeats);
            # the grouped covariance's predictor series in one grid, then each group's outcome replicates, one column per X level
            group = re.match(r'(Group|Repeat) (\d+):', prompt)
            if kind == 'fields' and p.get('fields') and p['fields'][0]['name'] == 'n' and prompt.startswith('Number of'):
                return {'n': len(nested_frames[0][0]['values']) if 'repeat' in prompt else len(nested_frames)}
            if kind == 'grid' and group and group.group(1) == 'Repeat':
                r = int(group.group(2)) - 1
                return {'columns': [{'title': '', 'values': [block[c]['values'][r] for block in nested_frames]} for c in range(len(nested_frames[0]))], 'source': 'Help example'}
            if kind == 'grid' and group and 'replicates' in prompt: return {'columns': nested_frames[int(group.group(2)) - 1][1:], 'source': 'Help example'}
            if kind == 'grid' and group: return {'columns': nested_frames[int(group.group(2)) - 1], 'source': 'Help example'}
            if kind == 'grid' and prompt.startswith('Select predictor (X) series'): return {'columns': [level[0] for level in nested_frames], 'source': 'Help example'}
            if kind == 'boolean' and prompt == 'Use Y replicates': return True
        if name not in settings and prompt in settings: name = prompt   # a question put by its text (a yes/no question of the host)
        if name in settings and settings[name] is None and p.get('skip'): return {'skip': True}   # a setting given as null: the optional prompt skipped, as a Windows run without it
        if kind == 'options' and any(o['value'] in settings for o in p['options']): return {o['value']: bool(settings.get(o['value'], o['selected'])) for o in p['options']}   # the options as the record holds them, one boolean under each option's name
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
                return {'columns': take, 'source': 'Help example', 'preserveRows': True}
            return {'skip': True} if p.get('skip') else None
        if kind == 'fields' and any(f['name'] == 'method' for f in p['fields']) and 'boxWhisker' in settings:
            box = settings['boxWhisker']; answer = {f['name']:f['defaultValue'] for f in p['fields']}
            for key in ('innerFence', 'outerFence', 'markMeanAndMedian', 'title', 'boxAxes'):
                if key in box: answer[key] = box[key]
            answer.update(method=str(box['method']), confidence=box['confidence']*100,
                          orientation='Horizontal' if box['horizontal'] else 'Vertical',
                          automaticAxisTitle=False, x=box['axisTitle'])
            for i, title in enumerate(box['seriesTitles']): answer['series'+str(i)] = title
            return answer
        if kind == 'fields' and 'chartSettings' in settings:
            answer = {f['name']:f['defaultValue'] for f in p['fields']}
            if 'title' in answer: answer['title'] = settings['chartSettings'].get('title', answer['title'])
            return answer   # other Windows chart controls are not yet exposed by the Mac form
        if kind == 'fields' and any(f['name'] in ('x', 'df', 'df2') for f in p['fields']):
            boxes = {'x': 'value', 'df': 'df', 'df2': 'df2'}   # the Distributions calculator's boxes under the record's names
            return {f['name']: settings.get(boxes.get(f['name'], ''), f['defaultValue']) if settings.get(boxes.get(f['name'], '')) is not None else f['defaultValue'] for f in p['fields']}
        if name in settings and settings[name] is not None:
            v = settings[name]
            if kind == 'confidence': return v * 100
            if kind == 'options' and isinstance(v, list): return {o['value']: o['value'] in v for o in p['options']}   # the record's list of the options chosen (the method comparison's regressions)
            if kind == 'selectList' and isinstance(v, list) and all(isinstance(x, bool) for x in v): return [i for i, flag in enumerate(v) if flag]   # the record's marks of a pick from a list, as the form sends the indices
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
help_scripts = {op: (EXAMPLES / (op + '.R')).read_text().replace('\r', '') for op in operations}
# A shared recipe can now print different follow-on results or fit different
# parent models. Deduplicate only identical reference text, not recipe filenames.
unique_references = list(dict.fromkeys(help_scripts.values()))
ensure_r_packages('mcr')   # the help's method comparison regression, through the mcr package as the operation runs it
reference_outputs = dict(zip(unique_references, [figures(o) if not isinstance(o, AssertionError) else o for o in r_outputs(unique_references)]))
help_figures = {op: reference_outputs[text] for op, text in help_scripts.items()}
broken = [f for f, o in help_figures.items() if isinstance(o, AssertionError)]
check(not broken, 'the help\'s %d independent reference scripts run in R (%s)' % (len(unique_references), RSCRIPT) + ('; failed: ' + ', '.join(broken) if broken else ''))

# the harness records: the writer's text line by line, then R against the help
harness = {}
for op in operations:
    record = record_of(examples[op]); script = rs.write(record, None, [])
    harness[op] = (record, script)
mismatched = []
for op in operations:
    record, script = harness[op]; recipe, detail = recipe_of(op, record)
    expected = expected_script(record, recipe, detail)
    if 'error' in script or not script['hasRecipe'] or script['detail'] != detail or script['text'] != expected:
        where = first_difference(script['text'], expected) if 'text' in script else None
        mismatched.append(op); print('      %s: %s' % (op, script.get('error') or ('line %d differs: engine %r, expected %r' % where if where else 'recipe flag or detail')), flush=True)
check(not mismatched, 'the engine writes every recipe\'s script for the help\'s example exactly as the Windows writer\'s rules give it, line by line (%d operations)' % len(operations)
      + ('; differing: ' + ', '.join(mismatched) if mismatched else ''))
CHART_PROBES = {
    'BarPlot': 'emit(c(dim(bar_values), as.vector(bar_values)))\nfor (s in bar_segments) emit(unlist(s, use.names=FALSE))',
    'BarPlotFrequency': 'emit(c(dim(counts), as.vector(counts), as.vector(frequency_values), dim(bar_values), as.vector(bar_values)))\nfor (s in bar_segments) emit(unlist(s, use.names=FALSE))',
    'HistogramPlot': 'emit(length(histograms))\nfor (h in histograms) emit(c(h$n, h$breaks, h$counts, h$mids, h$heights))',
    'NormalPlot': 'emit(c(length(observed), normal_ranks, normal_scores, observed))',
    'SpreadPlot': 'stopifnot(spread_tolerance>0,spread_tolerance<1)\nemit(length(groups))\nfor (i in seq_along(groups)) { emit(c(length(groups[[i]]), groups[[i]])); emit(unlist(spread_stacks[[i]],use.names=FALSE)) }',
    'LinePlot': 'emit(length(xy_series))\nfor (s in xy_series) emit(c(length(s$x), s$x, s$y))',
    'ScatterPlot': 'emit(length(xy_series))\nfor (s in xy_series) emit(c(length(s$x), s$x, s$y))',
    'LadderPlot': 'emit(c(length(ladder_before), ladder_before, ladder_after, ladder_difference))',
    'ErrorPlot': 'emit(length(error_series))\nfor (s in error_series) emit(c(length(s$x), s$x, s$y, s$lower, s$upper, s$plot_x))',
    'PyramidPlot': 'emit(c(length(pyramid_rows), pyramid_rows, pyramid_males, pyramid_females, pyramid_scale))',
    'ControlPlot': 'emit(c(length(control_y), control_x, control_y, control_mean, control_sd, control_bands))',
    'SurvivalPlot': 'emit(length(survival_curves))\nfor(s in survival_curves) emit(c(length(s$x),s$x,s$y,s$lower,s$upper,s$event))',
    'CochranePlot': 'emit(c(nrow(forest_rows),forest_rows$effect,forest_rows$lower,forest_rows$upper,forest_rows$weight,forest_rows$pooling,forest_rows$y))',
    'ROCPlot': 'emit(length(roc_series))\nfor(s in roc_series) emit(c(length(s$cuts),s$cuts,s$sensitivity,s$specificity,s$auc,s$theta,s$se,s$confidence,s$comparison,s$weight,s$cutoff,s$optimum,s$a,s$b,s$c,s$d,as.vector(s$proportions)))',
}

ANALYSIS_PROBES = {
    **dict.fromkeys(('Friedman', 'CochranQ', 'FriedmanSimulateExactP'), 'emit(friedman_result)\nemit(R/b)'),
    'FriedmanMulti': 'emit(c(critical_t,critical_difference))\nemit(c(friedman_comparisons$difference,friedman_comparisons$p,as.integer(friedman_comparisons$significant)))',
    'Ranv': 'emit(regression_anova)',
    **dict.fromkeys(('LinearizedEstimates', 'LinearizedEstimatesWithModel', 'LinearizedEstimatePlot', 'LinearizedEstimateInterpolation'), 'emit(linearized_result)'),
}

def comparison_script(operation, text):
    # Graphical Continue in R draws one chart without printing teaching variants.
    # Read the actual plotted summaries for the independent worked-example check.
    if operation in CHART_PROBES or operation in ANALYSIS_PROBES:
        return 'options(device=function(...) grDevices::pdf(file="selected-chart.pdf",...))\ninvisible(capture.output({\n' + text + '\n}))\nemit <- function(x) cat(formatC(as.double(x), digits=8, format="f"), "\\n")\n' + (CHART_PROBES.get(operation) or ANALYSIS_PROBES[operation])
    if operation != 'BoxWhiskerPlot': return text
    return text + r"""
stopifnot(box_method == 1L, box_inner_fence, box_outer_fence,
          box_horizontal, !box_mark_mean_median,
          identical(box_title, "Selected Cuzick cell lines"),
          identical(box_axis_title, "Selected box-and-whisker settings"),
          identical(box_series_titles, names(mets)))
six <- function(x) formatC(x, digits = 6, format = "f", drop0trailing = TRUE)
for (name in names(box_summaries)) {
  s <- box_summaries[[name]]
  cat(paste0(name, ":"), "n =", s$n, " min =", six(s$x[1]), " LQ =", six(s$box[1]),
      " median =", six(s$centre), " UQ =", six(s$box[2]), " max =", six(s$x[s$n]), "\n")
  beyond <- s$x[s$x < s$inner[1] | s$x > s$inner[2]]
  if (length(beyond))
    cat("   inner fences", six(s$inner[1]), "to", six(s$inner[2]),
        " outer fences", six(s$outer[1]), "to", six(s$outer[2]),
        " beyond the inner fence:", six(beyond), "\n")
}
"""

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
        expected = help_figures[op]; allowed = set(expected.split())
        subset = example.get('subset') is True or (what == 'real run' and op in REAL_RUN_SUBSET)
        if ours == expected or (example.get('cut') is True and ours and expected.startswith(ours + ' ')) or (subset and ours and all(f in allowed for f in ours.split())): agreed += 1
        else:
            failures.append(op); a, b = ours.split(' '), expected.split(' '); i = 0
            while i < len(a) and i < len(b) and a[i] == b[i]: i += 1
            print('      %s: the figures differ from the %dth: %s %s, help %s (%d and %d figures)' % (op, i + 1, what, a[i] if i < len(a) else '(end)', b[i] if i < len(b) else '(end)', len(a), len(b)), flush=True)
    return agreed, failures
agreed, failures = compare_with_help(zip(operations, r_outputs([comparison_script(op, harness[op][1]['text']) for op in operations])), 'recipe')
check(not failures, 'every recipe prints the figures the help\'s script prints on the help\'s example: %d of %d agree' % (agreed, len(operations)) + ('; differing: ' + ', '.join(failures) if failures else ''))

# the real runs: the help's example inputs through the engine as entered frames
INHERITING = {op: manifest[op]['inherits'] for op in operations if 'inherits' in manifest[op]}   # the follow-ons whose record carries the parent's frames
FOLLOW_ONS = {'FollowUpLifeTable', 'FriedmanMulti', 'PolynomialRegressionChangeDegree'} | set(INHERITING)   # run from a parent result, not from the menu
DEFERRED = set()   # operations the Mac does not host yet (none: the R-based ones run through the engine's R step)
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
check(not not_run, 'every operation of the manifest that is not a follow-on runs through the engine on the help\'s example (%d of %d%s)' % (len(real), len(runnable), '; deferred on the Mac: ' + ', '.join(sorted(DEFERRED)) if DEFERRED else '') + ('; not run: ' + ', '.join(sorted(not_run)) if not_run else ''))
recorded = [op for op in runnable if op not in NO_REPORT_STEP]
without = sorted(op for op in runnable if not isinstance(real[op].get('record'), str))
check(all(isinstance(real[op].get('record'), str) for op in recorded) and without == sorted(NO_REPORT_STEP) and all(real[op].get('recipe') is True for op in runnable),
      'the help\'s example inputs run through the engine as entered frames for %d operations, %d leaving a record at their report step (the %d writing to the worksheet alone, and the quick summary\'s builtin, leave none), all with recipe true; the %d follow-ons run from a parent result'
      % (len(runnable), len(recorded), len(NO_REPORT_STEP) - 1, len(FOLLOW_ONS)) + ('; without a record: ' + ', '.join(without) if without != sorted(NO_REPORT_STEP) else ''))
# Where the dialog differs from the help's example: settings the dialog does not record under the example's name (asked on a branch the
# default answers do not take; worked out from the inputs the dialog takes instead; written back by the operation as a result under the same
# name). The rank correlation calculators record the score (df2) they work
# out of the correlation, as the Windows calculator shows and records it.
# The regenerated examples (2570f206) also state settings the dialog asks only on another branch: the Fisher test of a cohort or neither
# study, the control responders when there are controls.
DIALOG_SETTINGS = {'SizeIndCase': {'p1'}, 'SizeIndProp': {'p1'}, 'SizeMatchProp': {'p1'}, 'SizeSurvival': {'hr'}, 'Chi2by2': {'doFisher'}, 'Logit': {'nrc'}, 'Probit': {'nrc'}}
RENAMED_INPUTS = {}   # an example naming an input otherwise than the parameter the dialog records it under (none now)
REAL_RUN_SUBSET = {'MiscRelRisk'}   # the dialog's labels (Present, Absent) differ from the help's, which carry digits: every figure printed is among the help's
def equivalent(got, values, op):
    """Whether a recorded column holds the example's values: as numbers or their texts (a categorical column), a date typed as text recorded as
    the worksheet's serial day, or a shorter column of an entered frame padded with missing values to the frame's height."""
    def norm(v): return csharp(v) if is_number(v) else v
    def serial(v): return (datetime.strptime(v, '%Y-%m-%d') - datetime(1899, 12, 30)).days if isinstance(v, str) and re.fullmatch(r'\d{4}-\d{2}-\d{2}', v) else v
    g = list(got); v = list(values)
    while len(g) > len(v) and g[-1] is None: g.pop()
    if len(g) != len(v): return False
    if all(a == b or (a is not None and b is not None and norm(a) == norm(b)) or a == serial(b) for a, b in zip(g, v)): return True
    return False   # a calculation's private sorting must not change the acquisition record
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
            if not named['columns']: assert name not in kinds, 'the optional input %s, which the example does not give, is recorded (%s)' % (name, kinds.get(name)); continue   # an optional frame the example leaves out: skipped in the run
            assert kinds.get(name) == 'entered', 'the input %s is not recorded as entered (%s)' % (name, kinds.get(name))
            wanted += [(name, c) for c in named['columns']]
        every = [c for columns in entered.values() for c in columns]
        for name, column in wanted:
            # a frame asked once per group or repeat is recorded under its name for the last ask, and the frame the asks built up
            # (the operation's own) carries every column: a column not under the name is looked for in the rest
            titled = [c['values'] for c in (entered.get(name, []) if name else []) + every if c['title'] == column['title']]
            assert titled, 'no entered column titled %r%s' % (column['title'], ' under ' + name if name else '')
            assert any(equivalent(got, column['values'], op) for got in titled), 'the values of %r differ: recorded %s' % (column['title'], json.dumps(titled[0])[:120])
        for two in example.get('nested', []) if isinstance(example.get('nested'), list) else []:
            got = next((i for i in r['inputs'] if i['name'] == two['name']), None)
            assert got is not None and got['kind'] in ('frame2d', 'covariance') and isinstance(got.get('value'), dict), 'the two-level input %s is not recorded (%s)' % (two['name'], got and got.get('kind'))
            frames = got['value'].get('frames')
            assert isinstance(frames, list) and len(frames) == len(two['frames']) and all(len(a) == len(b) and all(equivalent(x['values'], y['values'], op) for x, y in zip(a, b)) for a, b in zip(frames, two['frames'])), 'the two-level frames of %s differ' % two['name']
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
            if key == 'boxWhisker':
                assert isinstance(got, dict) and all(got.get(k) == v for k, v in value.items()), ('recorded chart options', got, value)
                continue  # the real chart also records its font and scale defaults
            if key == 'chartSettings':
                assert isinstance(got, dict) and got.get('type') and got.get('markers'), ('portable native chart settings', got)
                title = got['histograms'][0]['title'] if op == 'HistogramPlot' else got['title']
                assert title == value['title'], ('selected Mac title', title, value['title'])
                continue  # check actual Mac defaults/replay separately; do not require controls that only Windows exposes
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
    script = real_scripts[op]; record = json.loads(real[op]['record']); recipe, detail = recipe_of(op, record); expected = expected_script(record, recipe, detail)
    if 'error' in script or not script['hasRecipe'] or script['text'] != expected:
        where = first_difference(script['text'], expected) if 'text' in script else None
        mismatched.append(op); print('      %s: %s' % (op, script.get('error') or ('line %d differs: engine %r, expected %r' % where if where else 'no recipe')), flush=True)
check(not mismatched, 'the engine writes each real run\'s script exactly as the Windows writer\'s rules give it for that record, line by line (%d operations)' % len(recorded)
      + ('; differing: ' + ', '.join(mismatched) if mismatched else ''))
# the real runs' scripts against the help: the same figures where the run's settings are the help's; where the dialog differs from the help's
# example (a stated default the help's script does not take, a seed the form chose, the dialog's own labels), the difference is listed
# The shared graphical references deliberately select Windows-only options such
# as scaled Blom scores and relative histograms. Compare their mathematics using
# the actual acquired Mac data with those explicit fixture options. The unmodified
# Mac records/scripts are checked above and through test_chart_replay.py/native UI.
def real_reference_script(op):
    if op not in CHART_PROBES: return real_scripts[op]['text']
    record = json.loads(real[op]['record'])
    record['parameters']['chartSettings'] = examples[op]['settings']['chartSettings']
    return rs.write(record, None, [])['text']
agreed, failures = compare_with_help(zip(recorded, r_outputs([comparison_script(op, real_reference_script(op)) for op in recorded])), 'real run')
# Expected, and the same for a Windows run of the dialog (raised with Windows rather than diverged from): none at present. The six the
# Mac's real runs found on 11 October 2026 (Crosstabs's text classifiers, KappaScreen's binding, LogisticRegression's rest list, the
# survival plot's and Wei-Lachin's frames asked once per group kept as the last ask alone) were changed in the shared code at e99fe24a,
# and MiscRelRisk's labels are covered by the subset comparison above.
# The 2 by 2 example takes the Fisher test, which the dialog asks only for a cohort or neither study: a case-control run records no
# doFisher, so its script prints no Fisher P, as the engine's own report for that run has none. (At 2570f206 the Mac's real runs found two
# recipes binding a setting no dialog run records, the method comparison's "methods" and the normal plot's score method; Windows changed
# both at 3cc4cbc9, and the real runs below check them.)
EXPECTED_REAL_DIFFERENCES = {'Chi2by2'}
unexpected = sorted(set(failures) - EXPECTED_REAL_DIFFERENCES); newly_agreeing = sorted(EXPECTED_REAL_DIFFERENCES - set(failures))
check(not unexpected and not newly_agreeing, 'the scripts of the real runs print the help\'s figures: %d of %d agree%s' % (agreed, len(recorded), ('; differing as listed: ' + ', '.join(sorted(failures))) if failures else '')
      + ('; unexpected: ' + ', '.join(unexpected) if unexpected else '') + ('; now agreeing, remove from the list: ' + ', '.join(newly_agreeing) if newly_agreeing else ''))

# --- the follow-on operations through the engine from a parent run, as FollowOn.cs and Regression.cs check them on Windows: the record
# carries the frames the follow-on inherited from the parent's run, marked inherited, with the parent's columns; its script is the parent's
# (the same recipe on the same data) where it asked for no frame of its own, and holds every line of the parent's where it did; and its
# text is what the writer's rules give for its record (an inherited frame no variable of the recipe takes is left out)
FOLLOW_ON_ANSWERS = {}   # answers to the prompts a follow-on puts of its own, beyond its example's settings, by operation
# a parent run answered otherwise than its example, so that it offers the follow-on: the agreement analysis offers the exact P simulation
# only when no observer is marked as the reference standard, and the example (2570f206) marks observer 1
PARENT_ANSWERS = {'UniversalAgreementSimulateExactP': {'reference': None}}
# follow-ons with no report step (they write their result to the worksheet alone) leave no record, as on Windows: they must run, and leave none
FOLLOW_ON_NO_REPORT_STEP = {'CoxBaselineToWorksheet', 'LogisticRegressionFitToWorksheet', 'PoissonRegressionFitToWorksheet', 'SimpleLinearRegressionCI'}
follow_on_problems = []; inherited_frames = 0; without_record = 0
for op, parent_op in sorted(INHERITING.items()):
    try:
        parent_state = run_example(s, examples[parent_op], keep=True, extra=PARENT_ANSWERS.get(op))
        try: child = run_example(s, examples[op], parent=parent_state['jobId'], extra=FOLLOW_ON_ANSWERS.get(op))
        finally: s.close(parent_state['jobId'])
        assert isinstance(parent_state.get('record'), str), 'the parent %s left no record at a report step' % parent_op
        if op in FOLLOW_ON_NO_REPORT_STEP:
            assert child.get('state') == 'complete' and child.get('record') is None, 'expected to run and leave no record, as it has no report step'
            without_record += 1; continue
        assert isinstance(child.get('record'), str), 'the follow-on left no record at a report step (it writes to the worksheet or draws alone?)'
        pr = json.loads(parent_state['record']); cr = json.loads(child['record'])
        inherited = [i for i in cr['inputs'] if i.get('inherited') is True]
        own = [i for i in cr['inputs'] if i.get('inherited') is not True and i['kind'] in ('frame', 'entered', 'table', 'frame2d', 'covariance')]
        # the frames the parent asked for (a frame the parent itself held in the bag, the prediction grid's source, may be the follow-on's own input)
        parent_frames = [i for i in pr['inputs'] if i['kind'] in ('frame', 'entered', 'frame2d', 'covariance') and i.get('inherited') is not True]
        assert cr['operation'] == op and child.get('recipe') is True, 'operation %r or recipe flag %r' % (cr['operation'], child.get('recipe'))
        assert inherited and all(i['kind'] in ('entered', 'frame2d') and i.get('prompt') == '' for i in inherited), 'no frame marked inherited among the inputs %s' % [(i['name'], i['kind'], i.get('inherited')) for i in cr['inputs']]
        for frame in parent_frames:
            match = [i for i in inherited if i['name'] == frame['name']]
            if frame['kind'] in ('frame2d', 'covariance'):   # a two-level frame is inherited as frame2d with its blocks or groups
                assert match and match[0]['kind'] == 'frame2d' and match[0].get('value', {}).get('frames') == frame.get('value', {}).get('frames'), 'the parent\'s two-level frame %s is not inherited with its frames' % frame['name']
            else:
                assert match and match[0]['columns'] == frame['columns'], 'the parent\'s frame %s is not inherited with its columns' % frame['name']
        inherited_frames += len(inherited)
        parent_script = rs.write(parent_state['record'], None, []); child_script = rs.write(child['record'], None, [])
        a, b = parent_script['text'].split('\n')[1:], child_script['text'].split('\n')[1:]
        child_recipe, child_detail = recipe_of(op, cr)
        settings_used = [parameter for _, parameter in parse_recipe(child_recipe)['settings']]
        contextual = (child_recipe != recipe_of(parent_op, pr)[0]
                      or any(parameter in ('statsdirectOperation', 'statsdirectRootOperation') for parameter in settings_used)
                      or any(pr.get('parameters', {}).get(parameter) != cr.get('parameters', {}).get(parameter) for parameter in settings_used))
        if not contextual:
            if not own: assert b == a, 'the scripts differ at line %d: parent %r, follow-on %r' % first_difference(parent_script['text'], child_script['text'])
            else:
                rest = iter(b); assert all(line in rest for line in a), 'the parent\'s script lines are not all in the follow-on\'s (which asked for %s itself)' % [i['name'] for i in own]
        # Routed/interpolation/ANOVA recipes intentionally differ from the parent.
        # Their inherited data are checked above and their exact own script below;
        # varied native numerical results are checked in test_recipe_regressions.
        expected = expected_script(cr, child_recipe, child_detail)
        assert child_script['text'] == expected, 'line %d differs from the writer\'s rules: engine %r, expected %r' % first_difference(child_script['text'], expected)
    except AssertionError as e: follow_on_problems.append(op); print('      %s: %s' % (op, str(e).replace('\n', ' | ')[:600]), flush=True)
check(not follow_on_problems, 'the %d follow-on operations run from a parent run record the frames they inherit (%d), marked inherited, and their scripts use the correct recipe, inherited data and selected follow-on settings (the %d writing to the worksheet alone leave no record)' % (len(INHERITING), inherited_frames, without_record)
      + ('; failing: ' + ', '.join(follow_on_problems) if follow_on_problems else ''))

# --- runs with the options and sizes the help's examples do not have, as tests/RScript/Options.cs and Options2.cs check them on Windows
# (a reviewer's findings on the 5.1.0 scripts, 11 October 2026: the scripts fitted the help's example rather than the run). Each run goes
# through the engine with its options set, the writer writes its script, R runs it, and the figures R prints are compared with the
# engine's: its scalar outputs, or the report's own lines where the figure sits in a table. The data are small and made up: R is the
# independent route to the same model. Where the engine runs R itself (LOESS, the method comparison) or the record is built by hand on
# Windows, the record is built here from the example and the script's run checked.
import html as html_module
def report_text(h):
    """The report's text, a line for each block, as the help replay reads a page."""
    t = re.sub(r'<script.*?</script>', '', h or '', flags=re.S); t = re.sub(r'</(p|div|h[1-6]|li|tr|table)>', '\n', t, flags=re.I); t = re.sub(r'<br\s*/?>', '\n', t, flags=re.I)
    x = html_module.unescape(re.sub(r'<[^>]+>', ' ', t)).replace('\xa0', ' ')
    return '\n'.join(l for l in (re.sub(r'[ \t]+', ' ', line).strip() for line in x.split('\n')) if l)
def numbers(text, pattern): return [float(m.group(1)) for m in re.finditer(pattern, text, re.M)]
# R prints the recipe's figures to 6 decimal places, so a figure near 0 can differ from the engine's by half a unit in the sixth
def near(a, b, rel=1e-5): return abs(a - b) <= rel * max(abs(a), abs(b)) + 6e-7
def agree(r, engine, rel=1e-5): return len(r) == len(engine) > 0 and all(near(a, b, rel) for a, b in zip(r, engine))
def shown(v): return ' '.join('%.7g' % x for x in v)
def columns_of(*pairs): return [{'title': title, 'values': list(values)} for title, values in pairs]
def option_run(operation, inputs, settings):
    """A run through the engine with the options given (a null setting skips its optional prompt): the state, the record, the script's text,
    what R printed for it and the report's text."""
    example = {'operation': operation, 'inputs': [{'name': name, 'columns': columns_of(*pairs)} for name, pairs in inputs], 'settings': settings}
    state = run_example(s, example, extra=settings, preferences={'use-default-ci': False}); script = rs.write(state['record'], None, [])   # the confidence level asked, not the default taken
    if not script['hasRecipe']: raise AssertionError('%s: the run\'s script has no recipe' % operation)
    return state, json.loads(state['record']), script['text'], run_r(script['text']), report_text(state.get('html'))
def built(example):
    """The script of a record built from an example, as Recipes.cs's RecordOf builds it, and what R printed for it."""
    text = rs.write(record_of(example), None, [])['text']; return text, run_r(text)
CONTINUOUS = 'Choose the reference category for %s'   # the dialog put for an integer predictor of 3 to 11 distinct values, as on Windows: -2 treats it as continuous

# multiple linear regression without an intercept and with weights: lm gets the formula without the intercept and the weights
y = [12.1, 14.3, 15.2, 18.9, 20.4, 22.8, 23.9, 27.1, 29.6, 30.2, 33.8, 35.1]; x1 = list(range(1, 13)); x2 = [3.2, 1.5, 4.8, 2.2, 5.9, 3.1, 6.4, 2.8, 7.1, 4.4, 8.3, 5.0]; w = [1, 2, 1, 3, 1, 2, 1, 3, 1, 2, 1, 3]
state, record, script, r, report = option_run('MultipleLinearRegression', [('outcome', [('y', y)]), ('weights', [('w', w)]), ('predictors', [('x1', x1), ('x2', x2)])], {'ci': 0.95, 'calculateIntercept': False, 'useWeights': True})
check('intercept <- FALSE' in script and 'weights <- c(1, 2, 1, 3' in script and 'intercept = intercept' in script and 'weights = weights' in script,
      'the regression\'s script carries the run\'s intercept option and weights and hands them to lm')
engine_b = numbers(report, r'^\S+ b\d+ = (-?[0-9.]+) r = '); engine_t = numbers(report, r'^\S+ b\d+ = -?[0-9.]+ r = -?[0-9.]+ t = (-?[0-9.]+)')
r_b = numbers(r, r'^.+ b\d+ = (-?[0-9.]+)'); r_t = numbers(r, r'^.+ b\d+ = .*  t = (-?[0-9.]+)')
print('      weighted regression without an intercept: engine b %s, R b %s; t %s and %s' % (shown(engine_b), shown(r_b), shown(engine_t), shown(r_t)), flush=True)
check(agree(r_b, engine_b) and agree(r_t, engine_t) and len(engine_b) == 2, 'R\'s weighted regression without an intercept gives the engine\'s two coefficients and t statistics')

# logistic regression of individual responses with one predictor and a 99% interval: the rows are merged by covariate pattern as the
# report does, the one predictor's loop runs, and the interval is the run's level (the dose of four levels kept continuous, as the
# Windows check's frame is)
dose = [1]*4 + [2]*4 + [3]*4 + [4]*4; response = [0, 0, 0, 1, 0, 0, 1, 1, 0, 1, 1, 1, 1, 1, 1, 0]
state, record, script, r, report = option_run('LogisticRegression', [('response', [('response', response)]), ('predictors', [('dose', dose)])],
                                              {'grouping': 'individual', 'accuracy': '0.0000001', 'intercept': True, 'weights': False, 'gamma': 0.99, CONTINUOUS % 'dose': '-2'})
check('total <- NULL' in script and 'confidence <- 0.99' in script and 'if (is.null(total))' in script, 'the logistic script of individual responses has no totals, the run\'s confidence level, and the merging of the rows')
engine_or = numbers(report, r'^\S+ (-?[0-9.]+) \(-?[0-9.]+ to -?[0-9.]+\) -?[0-9.]+ P'); engine_lo = numbers(report, r'^\S+ -?[0-9.]+ \((-?[0-9.]+) to'); engine_hi = numbers(report, r'^\S+ -?[0-9.]+ \(-?[0-9.]+ to (-?[0-9.]+)\)')
r_or = numbers(r, r'^\S+ odds ratio = (-?[0-9.]+)'); r_lo = numbers(r, r'^\S+ odds ratio = -?[0-9.]+ +\( +(-?[0-9.]+) to'); r_hi = numbers(r, r'^\S+ odds ratio = -?[0-9.]+ +\( +-?[0-9.]+ to (-?[0-9.]+)')
r_dev = numbers(r, r'^Deviance goodness of fit chi-square = (-?[0-9.]+)')[0]; engine_dev = state['values']['dev']
print('      individual logistic: engine OR %s (%s to %s), deviance %.7g; R %s (%s to %s), deviance %.7g' % (shown(engine_or), shown(engine_lo), shown(engine_hi), engine_dev, shown(r_or), shown(r_lo), shown(r_hi), r_dev), flush=True)
check(agree(r_or, engine_or) and agree(r_lo, engine_lo, 1e-4) and agree(r_hi, engine_hi, 1e-4) and len(engine_or) == 1 and near(r_dev, engine_dev),
      'R\'s logistic regression of the individual responses gives the engine\'s odds ratio, its 99% limits and the deviance of the merged rows')
# logistic regression of grouped counts without an intercept and with prior weights
total = [20]*6; responders = [3, 6, 9, 12, 14, 17]; level = [-2, -1, 0, 1, 2, 3]; second = [1, 0, 1, 0, 1, 0]; prior = [1, 2, 1, 2, 1, 2]
state, record, script, r, report = option_run('LogisticRegression', [('total', [('total', total)]), ('response', [('responders', responders)]), ('weight', [('prior', prior)]), ('predictors', [('level', level), ('second', second)])],
                                              {'grouping': 'grouped', 'accuracy': '0.0000001', 'intercept': False, 'weights': True, 'gamma': 0.95})
engine_or = numbers(report, r'^\S+ (-?[0-9.]+) \(-?[0-9.]+ to -?[0-9.]+\) -?[0-9.]+ P'); r_or = numbers(r, r'^\S+ odds ratio = (-?[0-9.]+)')
print('      weighted logistic without an intercept: engine OR %s, R %s' % (shown(engine_or), shown(r_or)), flush=True)
check('intercept <- FALSE' in script and 'weight <- c(1, 2, 1, 2, 1, 2)' in script and agree(r_or, engine_or) and len(engine_or) == 2, 'R\'s logistic regression without an intercept and with the prior weights gives the engine\'s two odds ratios')

# Poisson regression of counts alone (no exposure) with one predictor, then with an exposure and prior weights
counts = [2, 3, 6, 7, 8, 9, 10, 12, 15]; xp = list(range(1, 10))
state, record, script, r, report = option_run('PoissonRegression', [('response', [('counts', counts)]), ('predictors', [('xp', xp)])],
                                              {'gamma': 0.95, 'grouping': 'individual', 'accuracy': '0.0000001', 'intercept': True, 'weights': False, 'has-exposure': 'false'})
check('exposure <- NULL' in script, 'the Poisson script of counts alone has no exposure')
engine_coef = numbers(report, r'^\S+ b\d+ = (-?[0-9.]+)'); r_coef = numbers(r, r'^.+ b\d+ = (-?[0-9.]+)  z = ')
print('      Poisson of counts alone: engine b %s, R b %s' % (shown(engine_coef), shown(r_coef)), flush=True)
check(agree(r_coef, engine_coef) and len(engine_coef) == 2, 'R\'s Poisson regression of the counts alone with one predictor gives the engine\'s two coefficients')
exposure = [10, 12, 15, 14, 16, 15, 18, 20, 22]; pw = [1, 1, 2, 1, 2, 1, 1, 2, 1]
state, record, script, r, report = option_run('PoissonRegression', [('response', [('counts', counts)]), ('exposure', [('exposure', exposure)]), ('weight', [('pw', pw)]), ('predictors', [('xp', xp)])],
                                              {'gamma': 0.95, 'grouping': 'individual', 'accuracy': '0.0000001', 'intercept': True, 'weights': True, 'has-exposure': 'true'})
engine_coef = numbers(report, r'^\S+ b\d+ = (-?[0-9.]+)'); r_coef = numbers(r, r'^.+ b\d+ = (-?[0-9.]+)  z = ')
print('      Poisson with an exposure and prior weights: engine b %s, R b %s' % (shown(engine_coef), shown(r_coef)), flush=True)
check('weight <- c(1, 1, 2, 1, 2, 1, 1, 2, 1)' in script and agree(r_coef, engine_coef) and len(engine_coef) == 2, 'R\'s Poisson regression with the exposure as an offset and the prior weights gives the engine\'s coefficients')

# polynomial regression of degree 3: the script fits the run's degree
py = [1.2, 1.9, 4.1, 8.3, 15.2, 26.1, 40.8, 60.9, 86.2, 118.1, 157.5, 204.2]
state, record, script, r, report = option_run('PolynomialRegression', [('y', [('y', py)]), ('x', [('x', x1)])], {'degree': '3'})
engine_b = numbers(report, r'^\S+ b\d+ *= (-?[0-9.]+)'); r_b = numbers(r, r'^.+ b\d+ *= (-?[0-9.]+)')
print('      polynomial of degree 3: engine b %s, R b %s' % (shown(engine_b), shown(r_b)), flush=True)
check(re.search(r'^degree <- "?3"?', script, re.M) and 'poly(size, .(degree), raw = TRUE)' in script and agree(r_b, engine_b) and len(engine_b) == 4, 'R\'s polynomial regression of degree 3 gives the engine\'s four coefficients')

# Cox regression with strata: the model is stratified as the run was
times = [6, 7, 10, 15, 19, 25, 2, 4, 8, 12, 14, 20, 23, 30]; events = [1, 1, 1, 1, 0, 1, 1, 1, 1, 0, 1, 1, 1, 0]; treatment = [0, 1]*7; stratum = [1]*7 + [2]*7
state, record, script, r, report = option_run('CoxRegression', [('times', [('times', times)]), ('events', [('events', events)]), ('predictors', [('treatment', treatment)]), ('strata', [('stratum', stratum)])],
                                              {'accuracy': 0.000000001, 'centre-continuous-covariates': True, 'useTimesAdjustment': False})
engine_cox = numbers(report, r'^\S+ b1 = (-?[0-9.]+)')[0]; r_cox = numbers(r, r'^\S+ b1 = (-?[0-9.]+)')[0]
print('      stratified Cox: engine b %.7g, R b %.7g' % (engine_cox, r_cox), flush=True)
check('stratum <- c(' in script and 'strata(sd_stratum)' in script and near(r_cox, engine_cox), 'R\'s stratified Cox regression gives the engine\'s coefficient')

# conditional logistic regression with one predictor: the loops take the run's number of coefficients (ten matched pairs, case then
# control: five pairs with the case alone exposed, one with the control alone, four concordant, so that the estimate is finite, log 5)
pair = [i for i in range(1, 11) for _ in (0, 1)]; case_control = [1, 0]*10; exposure1 = [1, 0, 1, 0, 1, 1, 0, 1, 1, 0, 0, 0, 1, 0, 1, 1, 0, 0, 1, 0]
state, record, script, r, report = option_run('ConditionalLogisticRegression', [('stratum', [('pair', pair)]), ('case-control', [('case', case_control)]), ('predictors', [('exposure1', exposure1)])],
                                              {'gamma': 0.95, 'accuracy': '0.0000001', 'show-counts': False})
engine_cond = numbers(report, r'^exposure1 (-?[0-9.]+) -?[0-9.]+ z =')[0]; r_cond = numbers(r, r'^exposure1 (-?[0-9.]+) -?[0-9.]+  z =')[0]
print('      conditional logistic with one predictor: engine b %.7g, R b %.7g' % (engine_cond, r_cond), flush=True)
check(near(r_cond, engine_cond, 1e-4), 'R\'s conditional logistic regression with one predictor runs and gives the engine\'s coefficient')

# the log-rank test with strata and the Gehan-Breslow weight: the script's stratified test agrees with R's survdiff on the run's strata
state, record, script, r, report = option_run('LogRank', [('gid', [('group', [1, 2]*7)]), ('times', [('time', times)]), ('deaths', [('dead', events)]), ('strata', [('stratum', stratum)])], {'gamma': 0.95, 'wt_method': '2'})
survdiff = numbers(r, r'Chisq= *(-?[0-9.]+) +on 1 degrees of freedom')[-1]; combined = numbers(r, r'^overall chi-square = (-?[0-9.]+)')[0]
print('      stratified log-rank: survdiff %.7g, the script\'s combined test %.7g' % (survdiff, combined), flush=True)
check('wt_method <- "2"' in script and 'Generalised Wilcoxon (Gehan-Breslow)' in r and 'STRATUM 2 of 2' in r and '1976, 1990, 2240' not in r and abs(round(combined, 1) - survdiff) < 1e-9,   # survdiff prints its chi-square rounded to one decimal place
      'the log-rank script runs the stratified test on the run\'s strata, agreeing with survdiff, with the run\'s Wilcoxon weight and none of the help\'s data')

# a bar chart of four series and a box plot of three groups: the scripts draw the run's series and groups
bar_script, _ = built({'operation': 'BarPlot', 'inputs': [{'name': 'labels', 'columns': columns_of(('Blood group', ['O', 'A', 'B', 'AB']))},
                                                           {'name': 'values', 'columns': columns_of(('First', [44, 45, 8, 3]), ('Second', [79, 16, 4, 1]), ('Third', [61, 39, 0, 0]), ('Fourth', [50, 30, 15, 5]))}]})
box_script, r = built({'operation': 'BoxWhiskerPlotText', 'list': columns_of(('One', [12, 15, 11, 19, 22, 14, 30]), ('Two', [20, 25, 21, 29, 32, 24, 27]), ('Three', [5, 8, 11, 9, 6, 40, 7]))})
run_r(bar_script + '\nstopifnot(nrow(bar_values)==4L, ncol(bar_values)==4L)\n')
check(len(re.findall(r'^\S+ \(n = 7\)', r, re.M)) == 3, 'the bar chart of four series and the box plot of three groups draw the run\'s series and groups')

# kappa with quadratic weights, then with a table of weights given (not symmetric, so that the table's orientation tells)
rater1 = [1, 1, 2, 2, 3, 3, 1, 2, 3, 1, 2, 3, 2, 1, 3, 3]; rater2 = [1, 2, 2, 3, 3, 3, 1, 1, 2, 1, 2, 3, 3, 1, 2, 3]
state, record, script, r, report = option_run('Kappa', [('responses', [('first', rater1), ('second', rater2)])], {'ci': 0.95, 'method': '2'})
r_kappa = numbers(r, r'^Kappa = (-?[0-9.]+)'); engine_kw = state['values']['kappaw']
print('      quadratic kappa: engine %.7g, R unweighted and weighted %s' % (engine_kw, shown(r_kappa)), flush=True)
check('method <- "2"' in script and len(r_kappa) == 2 and near(r_kappa[1], engine_kw, 1e-4), 'R\'s quadratically weighted kappa gives the engine\'s')
state, record, script, r, report = option_run('Kappa', [('responses', [('first', rater1), ('second', rater2)]), ('weights', [('w1', [1, 0.6, 0]), ('w2', [0.3, 1, 0.6]), ('w3', [0, 0.3, 1])])], {'ci': 0.95, 'method': '3'})
r_kappa = numbers(r, r'^Kappa = (-?[0-9.]+)'); engine_kw = state['values']['kappaw']
print('      kappa with a table of weights: engine %.7g, R %s' % (engine_kw, shown(r_kappa)), flush=True)
check('weights <- list(' in script and len(r_kappa) == 2 and near(r_kappa[1], engine_kw, 1e-4), 'R\'s kappa with the run\'s table of weights gives the engine\'s, with the table as the run gave it')

# the Gini coefficient with frequency weights
state, record, script, r, report = option_run('Gini', [('data', [('income', [1, 2, 3, 4, 10])]), ('weights', [('freq', [3, 1, 2, 1, 1])])], {'gamma': 0.95, 'boots': 200, 'seed': 7})
r_gini = numbers(r, r'^Gini coefficient = (-?[0-9.]+)')[0]; engine_gini = numbers(report, r'^Gini coefficient = (-?[0-9.]+)')[0]
print('      Gini with frequency weights: engine %.7g, R %.7g' % (engine_gini, r_gini), flush=True)
check('rep(imr, floor(weights))' in script and 'births <-' not in script and near(r_gini, engine_gini), 'R\'s Gini coefficient of the values repeated by their frequency weights gives the engine\'s, without the help\'s own births and deaths')

# the effect size meta-analysis as a weighted mean difference, then from effect sizes given
en = [20, 25, 30]; em = [5.1, 4.8, 5.5]; es = [1.2, 1.5, 1.1]; cn = [22, 24, 28]; cm = [4.2, 4.1, 4.9]; cs = [1.3, 1.4, 1.0]
state, record, script, r, report = option_run('Effect', [('en', [('en', en)]), ('em', [('em', em)]), ('es', [('es', es)]), ('cn', [('cn', cn)]), ('cm', [('cm', cm)]), ('cs', [('cs', cs)])], {'gamma': 0.95, 'type': 'm', 'strata': None})
r_pooled = numbers(r, r'^Pooled effect size d\+ = (-?[0-9.]+)')[0]; engine_pooled = numbers(report, r'^Pooled effect size \S+ = (-?[0-9.]+)')[0]
print('      weighted mean difference: engine d+ %.7g, R %.7g' % (engine_pooled, r_pooled), flush=True)
check('type <- "m"' in script and near(r_pooled, engine_pooled, 1e-4), 'R\'s pooled weighted mean difference gives the engine\'s')
state, record, script, r, report = option_run('Effect', [('en', [('en', en)]), ('cn', [('cn', cn)]), ('g', [('g', [0.5, 0.3, 0.8])])], {'gamma': 0.95, 'type': 'g', 'strata': None})
r_pooled = numbers(r, r'^Pooled effect size d\+ = (-?[0-9.]+)')[0]; engine_pooled = numbers(report, r'^Pooled effect size \S+ = (-?[0-9.]+)')[0]
print('      effect sizes given: engine d+ %.7g, R %.7g' % (engine_pooled, r_pooled), flush=True)
check('gin <- c(0.5, 0.3, 0.8)' in script and 'em <- NULL' in script and near(r_pooled, engine_pooled, 1e-4), 'R\'s pooled effect size from the sizes given gives the engine\'s')

# the single sample z test with the population standard deviation known
state, record, script, r, report = option_run('ZSingle', [('data', [('speed', [9.1, 10.4, 11.2, 8.7, 10.9, 9.8, 12.1, 10.2])])], {'gamma': 0.95, 'popmean': 10.0, 'popsd': 2.5})
r_z = numbers(r, r'^Standard normal deviate \(z\) = (-?[0-9.]+)')[0]; engine_z = state['values']['z']
print('      z with the population sd: engine %.7g, R %.7g' % (engine_z, r_z), flush=True)
check('popsd <- 2.5' in script and 'speed[1:50]' not in script and near(r_z, engine_z, 1e-4), 'R\'s z with the population standard deviation gives the engine\'s, without the help\'s own first and last 50')

# principal components of five items without the reversal correction, then of the covariance matrix
items = [[3, 4, 5, 2, 4, 3, 5, 1, 4, 2], [2, 4, 4, 1, 5, 3, 4, 2, 3, 2], [4, 3, 2, 5, 2, 3, 1, 5, 2, 4], [1, 2, 3, 2, 4, 3, 5, 2, 4, 1], [5, 3, 4, 2, 4, 4, 5, 1, 3, 3]]
state, record, script, r, report = option_run('PCRCorrelation', [('data', [('i%d' % (i + 1), items[i]) for i in range(5)])], {'correctForReversal': False})
r_eigen = numbers(r, r'^[1-5] (-?[0-9.]+) '); engine_eigen = numbers(report, r'^[1-5] (-?[0-9.]+) ')
print('      principal components: engine eigenvalues %s, R %s' % (shown(engine_eigen), shown(r_eigen)), flush=True)
check('correct <- FALSE' in script and 'Sign was reversed' not in r and len(r_eigen) == 5 and agree(r_eigen, engine_eigen, 1e-4), 'R\'s principal components of five items without the reversal correction give the engine\'s eigenvalues')
state, record, script, r, report = option_run('PCRCovariance', [('data', [('i%d' % (i + 1), items[i]) for i in range(5)])], {'ci': 0.95, 'correctForReversal': True})
r_eigen = numbers(r, r'^[1-5] (-?[0-9.]+) '); engine_eigen = numbers(report, r'^[1-5] (-?[0-9.]+) ')
print('      principal components of the covariance matrix: engine eigenvalues %s, R %s' % (shown(engine_eigen), shown(r_eigen)), flush=True)
check('scale. = FALSE' in script and len(r_eigen) == 5 and agree(r_eigen, engine_eigen, 1e-4), 'R\'s principal components of the covariance matrix give the engine\'s eigenvalues')

# the logit model with the doses as logarithms and another centile
state, record, script, r, report = option_run('Logit', [('dose', [('dose', [1, 2, 4, 8, 16])]), ('subjects', [('subjects', [20]*5)]), ('responders', [('responders', [2, 5, 10, 15, 19])])], {'conf': 0.95, 'calc-log10-doses': True, 'nc': 0, 'nrc': 0, 'qld': 80.0})
r_median = numbers(r, r'^Median \* Dose = (-?[0-9.]+)')[0]; r_centile = numbers(r, r'^\* Dose for centile 80 = (-?[0-9.]+)')[0]
engine_median = state['values']['mxd']; engine_centile = state['values']['doseq']   # the report gives the doses back as doses, not their logarithms
print('      logit with log doses: engine median %.7g and centile 80 %.7g, R %.7g and %.7g' % (engine_median, engine_centile, r_median, r_centile), flush=True)
check('log_doses <- TRUE' in script and 'centile <- 80' in script and near(engine_median, r_median, 1e-4) and near(engine_centile, r_centile, 1e-4), 'R\'s logit on the log doses gives the engine\'s median dose and its dose for the centile chosen, as doses')

# the meta-analysis of relative risks given with their standard errors
state, record, script, r, report = option_run('MetaSummary', [('y', [('rr', [1.2, 0.8, 1.5])]), ('se_y', [('se', [0.1, 0.2, 0.15])])], {'gamma': 0.95, 'type': 'relativeRisk', 'use_ci': 'false', 'studies': None})
r_meta = numbers(r, r'^Pooled odds ratio = (-?[0-9.]+)')[0]; engine_meta = state['values']['rmh']
print('      relative risks with standard errors: engine pooled %.7g, R %.7g' % (engine_meta, r_meta), flush=True)
check('se_in <- c(0.1, 0.2, 0.15)' in script and 'lower <- NULL' in script and near(r_meta, engine_meta, 1e-4), 'R\'s pooled relative risk from the standard errors given gives the engine\'s')

# the proportion meta-analysis with Miller's inverse (the dialog's "Weights = n +" choice does not reach the engine, which adds 0.5 whatever is chosen)
state, record, script, r, report = option_run('ProportionMeta', [('sn', [('n', [50, 60, 40])]), ('sr', [('r', [20, 30, 10])])], {'gamma': 0.95, 'method': 'doubleArcsine', 'strata': None})
r_prop = numbers(r, r'^Pooled proportion = +(-?[0-9.]+)')[0]; engine_prop = state['values']['rmh']
print('      proportions by Miller\'s inverse: engine pooled %.7g, R %.7g' % (engine_prop, r_prop), flush=True)
check('method <- "doubleArcsine"' in script and near(r_prop, engine_prop, 1e-4), 'R\'s pooled proportion by Miller\'s inverse gives the engine\'s')

# the 2 by 2 chi-square of a cohort study without the exact test
state, record, script, r, report = option_run('Chi2by2', [], {'a': 30, 'b': 10, 'c': 20, 'd': 40, 'cco': 0.95, 'study_type': 'cohort', 'doFisher': False})
r_rr = numbers(r, r'^Relative risk = (-?[0-9.]+)')[0]; engine_rr = numbers(report, r'^Risk ratio \(relative risk in incidence study\) = (-?[0-9.]+)')[0]
r_koop = numbers(r, r'^Approximate \(Koopman\) 95% confidence interval = (-?[0-9.]+)')[0]; engine_koop = numbers(report, r'^Approximate \(Koopman\) 95% confidence interval = (-?[0-9.]+)')[0]
print('      2 by 2 cohort: engine relative risk %.7g from %.7g, R %.7g from %.7g' % (engine_rr, engine_koop, r_rr, r_koop), flush=True)
check('study <- "cohort"' in script and 'Odds Ratio =' not in r and "Fisher's Exact Test" not in r and near(r_rr, engine_rr, 1e-4) and near(r_koop, engine_koop, 1e-4), 'R\'s 2 by 2 of a cohort study gives the engine\'s relative risk and Koopman limit, with no odds ratio and no exact test')

# the crossover trial with baselines
state, record, script, r, report = option_run('Crossover', [(name, [(title, values)]) for name, title, values in [('group1drug', 'd1', [12, 15, 11, 14, 13, 16]), ('group1placebo', 'p1', [10, 12, 9, 11, 12, 13]), ('group1baseline', 'b1', [9, 11, 8, 10, 11, 12]),
                                                                                                                 ('group2drug', 'd2', [14, 13, 15, 12, 16, 14]), ('group2placebo', 'p2', [11, 10, 12, 10, 13, 11]), ('group2baseline', 'b2', [10, 9, 11, 9, 12, 10])]], {'gamma': 0.95})
r_cross = numbers(r, r'^diff 1 - diff 2 = (-?[0-9.]+)')[0]; engine_cross = state['values']['treatment_diff']
print('      crossover with baselines: engine treatment difference %.7g, R %.7g' % (engine_cross, r_cross), flush=True)
check('baseline1 <- c(9, 11, 8' in script and near(r_cross, engine_cross, 1e-4), 'R\'s crossover analysis with the baselines taken from both periods gives the engine\'s treatment difference')

# the time series summary with an observation of 0 at time 0 for each subject
ts_times = [1, 2, 4]*6; ts_obs = [5, 9, 4, 6, 10, 5, 4, 8, 3, 7, 12, 6, 5, 11, 2, 8, 9, 7]; ts_ids = [i for i in range(1, 7) for _ in range(3)]
state, record, script, r, report = option_run('TimeSeriesSummary', [('times', [('time', ts_times)]), ('observations', [('value', ts_obs)]), ('subjectIds', [('subject', ts_ids)])],
                                              {'ci': 0.95, 'addZeroObservationAtZeroTime': True, 'doExactP': False, 'iterations': 1000, 'seed': 1, 'groups': None})
r_auc = numbers(r[r.index('Subject ID'):], r'^1 (?:\S+ ){5}(-?[0-9.]+) ?$')[0]; engine_auc = numbers(report[report.index('Subject ID'):], r'^1 (?:\S+ ){5}(-?[0-9.]+)$')[0]   # subject 1's line after the header: id, baseline, min, max, time to max, slope, AUC
print('      time series with a zero at time 0: engine AUC of subject 1 %.7g, R %.7g' % (engine_auc, r_auc), flush=True)
check('zero_at_start <- TRUE' in script and near(r_auc, engine_auc, 1e-4), 'R\'s area under the curve with the zero at time 0 gives the engine\'s')

# the number needed to treat with an expected risk, and the risk analysis with a population proportion exposed and without one
state, record, script, r, report = option_run('MiscNumberNeededToTreat', [], {'cco': 0.95, 'nc': 100.0, 'xc': 30.0, 'nt': 100.0, 'xt': 15.0, 'brr': 0.2})
r_nnt = numbers(r, r'^NNT \[odds ratio\] = (-?[0-9.]+)')[0]; engine_nnt = numbers(report, r'^NNT \[odds ratio\] = (-?[0-9.]+)')[0]
print('      number needed to treat at an expected risk of 20%%: engine from the odds ratio %.7g, R %.7g' % (engine_nnt, r_nnt), flush=True)
check('brr <- 0.2' in script and 'Expected risk of event without treatment = 20%' in r and near(r_nnt, engine_nnt, 1e-4), 'R\'s number needed to treat from the odds ratio at the expected risk given gives the engine\'s')
state, record, script, r, report = option_run('MiscRelRisk', [], {'a': 72, 'b': 20, 'c': 684, 'd': 553, 'pe': 0.4, 'cco': 0.95})
r_par = numbers(r, r'^Population attributable risk % = (-?[0-9.]+)')[0]; engine_par = numbers(report, r'^Population attributable risk % = (-?[0-9.]+)')[0]
print('      attributable risk with 40%% exposed: engine %.7g, R %.7g%%' % (engine_par, r_par), flush=True)
check('pe <- 0.4' in script and (near(r_par, engine_par, 1e-4) or near(r_par, 100 * engine_par, 1e-4)), 'R\'s population attributable risk with the proportion exposed given gives the engine\'s')
state, record, script, r, report = option_run('MiscRelRisk', [], {'a': 72, 'b': 20, 'c': 684, 'd': 553, 'pe': None, 'cco': 0.95})
check('pe' not in record['parameters'] and 'pe <- NULL   # the run had no pe' in script and 'Population exposure %' in report, 'a setting the run skipped is NULL in the script, with a note, and the engine worked the exposure out from the table')

# the reference range of more than 200 values with the conservative limits
big = [50 + 8 * math.sin(i * 0.7) + 3 * math.cos(i * 1.9) + (i % 7) for i in range(250)]
state, record, script, r, report = option_run('ReferenceRange', [('data', [('x', big)])], {'gamma': 0.95, 'reference-interval': 0.95, 'do_conservative': True})
r_cons = numbers(r, r'^Approximate 95% confidence interval \(conservative\) = (-?[0-9.]+) to'); engine_from_any = state['values']['from_any']
print('      reference range, conservative lower limits: engine %.7g, R %s' % (engine_from_any, shown(r_cons)), flush=True)
check('conservative <- TRUE' in script and len(r_cons) == 2 and near(r_cons[0], engine_from_any, 1e-6), 'R\'s conservative confidence limit of the lower quantile of a reference range gives the engine\'s')

# the abridged life table with utility weights: the adjusted expectation of life (a cohort that halves within the table, so that it has a median)
state, record, script, r, report = option_run('AbridgedLifetable', [('intervals', [('n', [1, 4, 5, 10])]), ('population', [('P', [1000, 4000, 5000, 9000, 8000])]), ('deaths', [('D', [50, 40, 100, 1500, 4000])]), ('weights', [('u', [1, 1, 0.9, 0.8, 0.7])])],
                                              {'gamma': 0.95, 'save': False, 'iterations': '10000', 'fractions': None})
r_adjusted = numbers(r, r'^0 to 1 \d+ (-?[0-9.]+) ?$')[-1]; engine_adjusted = numbers(report[report.index('Adjusted (u) expectation'):], r'^0 to 1 (-?[0-9.]+)$')[0]
print('      life table with utility weights: engine adjusted expectation at birth %.7g, R %.7g' % (engine_adjusted, r_adjusted), flush=True)
check('u <- c(1, 1, 0.9, 0.8, 0.7)' in script and near(r_adjusted, engine_adjusted, 1e-4), 'R\'s adjusted expectation of life with the utility weights gives the engine\'s')

# the universal agreement coefficient with observer 2 as the reference standard (the pick from the list of observers, as the form sends it)
measure = [1.2, 1.4, 1.1, 1.3, 1.5, 1.3, 1.5, 1.0, 1.4, 1.6, 1.1, 1.3, 1.2, 1.2, 1.4]; raters = [1]*5 + [2]*5 + [3]*5; objects = [1, 2, 3, 4, 5]*3
state, record, script, r, report = option_run('UniversalAgreement', [('data', [('measure', measure)]), ('raters', [('rater', raters)]), ('objects', [('object', objects)])], {'categories': None, 'reference': [False, True, False]})
r_r = numbers(r, r'^Agreement coefficient R: (-?[0-9.]+)'); engine_r = state['values'].get('R', numbers(report, r'^Agreement coefficient R: (-?[0-9.]+)') + [None])[0] if 'R' not in state['values'] else state['values']['R']
print('      agreement with observer 2 as the reference: engine R %s, R %s' % (engine_r, shown(r_r)), flush=True)
check(record['parameters']['reference'] == [False, True, False] and 'reference <- list(FALSE, TRUE, FALSE)' in script and 'Reference standard: Observer 2' in r and len(r_r) == 2 and engine_r is not None and near(r_r[1], engine_r, 1e-4),
      'the record keeps the observer marked as the reference, and R\'s agreement coefficient with that observer as the reference gives the engine\'s')

# --- intervals at the run's confidence level, as tests/RScript/Options3.cs checks them (the reviewer's recheck: intervals the recipes had
# fixed at 95%, and a predictor whose title has a space): each run goes through the engine at 90% or 99%, with the exact methods of the
# meta-analyses on where the exact limits are compared, and the limits R prints are compared with the engine's
def pair_of(text, pattern):
    m = re.search(pattern, text, re.M)
    if not m: raise AssertionError('FAIL R did not print ' + pattern)
    return float(m.group(1)), float(m.group(2))
def engine_pair(state, report, keys, pattern):
    """The engine's limits: its scalar outputs under the keys, else the report line the pattern finds."""
    if all(k in state['values'] for k in keys): return state['values'][keys[0]], state['values'][keys[1]]
    return pair_of(report, pattern)
def interval(what, script, setting, r_pair, engine, rel=1e-4):
    print('      %s: engine %.7g to %.7g, R %.7g to %.7g' % (what, engine[0], engine[1], r_pair[0], r_pair[1]), flush=True)
    check(setting in script and near(r_pair[0], engine[0], rel) and near(r_pair[1], engine[1], rel), 'R\'s %s are the engine\'s at the run\'s level' % what)
def exact_run(operation, inputs, settings):
    """A run with the meta-analyses' exact methods on, as the Windows checking host's MetaExact preference."""
    example = {'operation': operation, 'inputs': [{'name': name, 'columns': columns_of(*pairs)} for name, pairs in inputs], 'settings': settings}
    state = run_example(s, example, extra=settings, preferences={'use-default-ci': False, 'meta-exact': True}); script = rs.write(state['record'], None, [])
    if not script['hasRecipe']: raise AssertionError('%s: the run\'s script has no recipe' % operation)
    return state, json.loads(state['record']), script['text'], run_r(script['text']), report_text(state.get('html'))
# Poisson regression at 99%
state, record, script, r, report = option_run('PoissonRegression', [('response', [('counts', counts)]), ('exposure', [('exposure', exposure)]), ('predictors', [('xp', xp)])],
                                              {'gamma': 0.99, 'grouping': 'individual', 'accuracy': '0.0000001', 'intercept': True, 'weights': False, 'has-exposure': 'true'})
interval('Poisson rate ratio limits at 99%', script, 'confidence <- 0.99', pair_of(r, r'^xp -?[0-9.]+ -?[0-9.]+ (-?[0-9.]+) to (-?[0-9.]+)'), pair_of(report, r'^xp b\d+ = -?[0-9.]+ -?[0-9.]+ (-?[0-9.]+) to (-?[0-9.]+)'))
# conditional logistic regression at 99%, with a predictor whose title has a space
state, record, script, r, report = option_run('ConditionalLogisticRegression', [('stratum', [('pair', pair)]), ('case-control', [('case', case_control)]), ('predictors', [('Smoking status', exposure1)])],
                                              {'gamma': 0.99, 'accuracy': '0.0000001', 'show-counts': False})
interval('conditional logistic odds ratio limits at 99%, for a predictor titled with a space', script, 'confidence <- 0.99', pair_of(r, r'^`?Smoking status`? -?[0-9.]+ (-?[0-9.]+) to (-?[0-9.]+)'), pair_of(report, r'^Smoking status -?[0-9.]+ (-?[0-9.]+) to (-?[0-9.]+)$'))
# simple linear regression at 90%
state, record, script, r, report = option_run('SimpleLinearRegression', [('y', [('increase', [15, 14, 12, 11, 10, 8, 7, 6])]), ('x', [('weight', [2.1, 2.5, 2.8, 3.0, 3.2, 3.5, 3.8, 4.1])])], {'gamma': 0.9})
interval('slope limits at 90%', script, 'confidence <- 0.9', pair_of(r, r'^90% CI for population value of slope = (-?[0-9.]+) to (-?[0-9.]+)'), engine_pair(state, report, ('se_from', 'se_to'), r'^90% CI for population value of slope = (-?[0-9.]+) to (-?[0-9.]+)'))
# the Mann-Whitney test at 90% (R names the level the exact interval reaches)
state, record, script, r, report = option_run('MannWhitney', [('data', [('farm', [14.8, 7.3, 5.6, 6.3, 9.0, 4.2, 10.6, 12.5, 12.9, 16.1]), ('town', [12.7, 14.2, 12.6, 2.1, 17.7, 11.8, 16.9, 7.9, 16.0, 10.5])])], {'gamma': 0.9})
interval('Mann-Whitney difference limits at 90%', script, 'confidence <- 0.9', pair_of(r, r'[0-9.]+ percent confidence interval:\s*\n\s*(-?[0-9.]+)\s+(-?[0-9.]+)'), engine_pair(state, report, ('from', 'to'), r'^K = \d+ Median difference = -?[0-9.]+ \(CI: (-?[0-9.]+) to (-?[0-9.]+)\)$'))   # the report's line for the difference's limits
# the diagnostic test at 90%
state, record, script, r, report = option_run('MiscDiagnostic', [], {'cco': 0.9, 'a': 40, 'b': 10, 'c': 15, 'd': 60})
interval('exact odds ratio limits of the diagnostic test at 90%', script, 'confidence <- 0.9', pair_of(r, r'^Conditional maximum likelihood estimate = -?[0-9.]+ \((-?[0-9.]+) to (-?[0-9.]+)\)'), engine_pair(state, report, ('cmle_from', 'cmle_to'), r'^Conditional maximum likelihood estimate = -?[0-9.]+ \((-?[0-9.]+) to (-?[0-9.]+)\)'))
# agreement of three raters at 90%
state, record, script, r, report = option_run('Agreement', [('data', [('first', [10, 12, 14, 9, 11, 13, 15, 8]), ('second', [11, 12, 13, 10, 11, 14, 14, 9]), ('third', [9, 13, 14, 9, 12, 12, 16, 8])])], {'ci': 0.9})
interval('intraclass correlation limits at 90%', script, 'confidence <- 0.9', pair_of(r, r'\(90% CI = (-?[0-9.]+) to (-?[0-9.]+) \)'), engine_pair(state, report, ('icc_lcl', 'icc_ucl'), r'90% CI = (-?[0-9.]+) to (-?[0-9.]+)'))
# the proportion meta-analysis at 90%: each study's exact limits
state, record, script, r, report = option_run('ProportionMeta', [('sn', [('n', [50, 60, 40])]), ('sr', [('r', [20, 30, 10])])], {'gamma': 0.9, 'method': 'arcsine', 'strata': None})
interval('first study\'s proportion limits at 90%', script, 'confidence <- 0.9', pair_of(r, r'^ *1 +-?[0-9.]+ +(-?[0-9.]+) +(-?[0-9.]+) '), pair_of(report[report.index('Proportion 90% CI'):], r'^1 -?[0-9.]+ (-?[0-9.]+) (-?[0-9.]+)$'))
# the incidence rate ratio meta-analysis at 90%: the exact limits (small counts, within the reach of the exact method)
state, record, script, r, report = exact_run('MetaIncidenceRateRatio', [('a', [('a', [4, 3, 5])]), ('pt1', [('pt1', [1000, 800, 1200])]), ('b', [('b', [2, 3, 2])]), ('pt2', [('pt2', [1100, 900, 1300])])], {'gamma': 0.9, 'strata': None})
interval('exact limits of the pooled rate ratio at 90%', script, 'confidence <- 0.9', pair_of(r, r'^Exact Fisher 90% confidence interval = (-?[0-9.]+) to (-?[0-9.]+)'), engine_pair(state, report, ('llf', 'ulf'), r'^Exact Fisher 90% confidence interval = (-?[0-9.]+) to (-?[0-9.]+)'))
# the effect size meta-analysis at 90%: the first study's exact limits (of g, with the correction J) and approximate limits (of d), and the
# inconsistency's limits, which are the non-central ones only with the exact preference on
state, record, script, r, report = exact_run('Effect', [('en', [('en', en)]), ('em', [('em', em)]), ('es', [('es', es)]), ('cn', [('cn', cn)]), ('cm', [('cm', cm)]), ('cs', [('cs', cs)])], {'gamma': 0.9, 'type': 'd', 'strata': None})
interval('first study\'s exact effect size limits at 90%', script, 'confidence <- 0.9', pair_of(r, r'^ *Trial 1 +-?[0-9.]+ +-?[0-9.]+ +(-?[0-9.]+) +(-?[0-9.]+)'), pair_of(report[report.index('Exact 90% CI'):], r'^1 -?[0-9.]+ -?[0-9.]+ (-?[0-9.]+) (-?[0-9.]+)$'))
interval('first study\'s approximate effect size limits at 90%', script, 'confidence <- 0.9', pair_of(r, r'^ *Trial 1 +\d+ +\d+ +-?[0-9.]+ +(-?[0-9.]+) +(-?[0-9.]+)'), pair_of(report[report.index('Approximate 90% CI'):], r'^1 \d+ \d+ -?[0-9.]+ (-?[0-9.]+) (-?[0-9.]+)$'))
INCONSISTENCY = r'^I(?:²|2|-squared) \(inconsistency\) = -?[0-9.]+% \( ?90% ?CI = (-?[0-9.]+)% to (-?[0-9.]+)% ?\)'   # the report's line, to the decimal place it prints, as R's
i_low, i_high = pair_of(r, r'^I-squared \(inconsistency\) = -?[0-9.]+% \(90% ?CI = (-?[0-9.]+)% to (-?[0-9.]+)%\)'); engine_i = engine_pair(state, report, ('llisq', 'ulisq'), INCONSISTENCY)
print('      inconsistency limits at 90%%: engine %.7g%% to %.7g%%, R %s%% to %s%%' % (engine_i[0], engine_i[1], i_low, i_high), flush=True)
check(abs(round(engine_i[0], 1) - i_low) < 1e-9 and abs(round(engine_i[1], 1) - i_high) < 1e-9, 'R\'s inconsistency limits of the effect size meta-analysis are the engine\'s at the run\'s level, to the decimal place R prints')
# the Mantel-Haenszel analysis at 90%: the inconsistency's limits
state, record, script, r, report = exact_run('Mantel', [('sn', [('sn', [100, 120, 90])]), ('sr', [('sr', [30, 45, 20])]), ('xn', [('xn', [110, 100, 95])]), ('xr', [('xr', [20, 25, 18])])], {'gamma': 0.9, 'strata': None})
i_low, i_high = pair_of(r, r'^I2 \(inconsistency\) = -?[0-9.]+% \(90% ?CI = (-?[0-9.]+)% to (-?[0-9.]+)%\)'); engine_i = engine_pair(state, report, ('llisq', 'ulisq'), INCONSISTENCY)
print('      Mantel-Haenszel inconsistency limits at 90%%: engine %.7g%% to %.7g%%, R %s%% to %s%%' % (engine_i[0], engine_i[1], i_low, i_high), flush=True)
check('confidence <- 0.9' in script and abs(round(engine_i[0], 1) - i_low) < 1e-9 and abs(round(engine_i[1], 1) - i_high) < 1e-9, 'R\'s inconsistency limits of the Mantel-Haenszel analysis are the engine\'s at the run\'s level, to the decimal place R prints')

# records built from an example, for the operations that run R themselves or whose prompts the Windows harness cannot answer
script, r = built({'operation': 'LOESS', 'inputs': [{'name': 'outcome', 'columns': columns_of(('y', [3.1, 4.2, 5.9, 7.1, 8.8, 9.9, 12.2, 13.1, 15.3, 16.8]))},
                                                     {'name': 'predictors', 'columns': columns_of(('x1', list(range(1, 11))), ('Age (years)', [30, 35, 41, 28, 52, 47, 60, 33, 45, 58]))}],
                   'settings': {'span': 0.9, 'degree': '1', 'model': 'y~x1+age..years.', 'title': 'A fit', 'xlab': 'x1', 'ylab': 'y'}})
check('model <- "y~x1+age..years."' in script and 'Equivalent Number of Parameters' in r and re.search(r'y ~ x1 \+ age\.\.years\.', r), 'the LOESS script fits the run\'s formula over its two predictors, named as the program names them for R')
script, r = built({'operation': 'MethodComparisonRegression', 'inputs': [{'name': 'testData', 'columns': columns_of(('test', [1.1, 2.3, 2.9, 4.2, 5.1, 5.8, 7.2, 8.1, 8.8, 10.3, 11.1, 12.4]))},
                                                                          {'name': 'referenceData', 'columns': columns_of(('reference', list(range(1, 13))))}],
                   'settings': {'error-ratio': 1, 'ci': 0.95, 'seed': 3, 'do.deming.jackknife': False, 'do.deming.analytical': True}})
check('do.deming.analytical <- TRUE' in script and re.search(r'^Slope: ', r, re.M) and 'jackknife' not in r, 'the method comparison script runs the regression the run chose, the Deming line with Wald limits, and not the help\'s jackknife')
# the same through the engine, which records the regressions as one boolean under each option's name, as the dialog fills them
MCR_OPTIONS = ('do.deming.jackknife', 'do.deming.bootstrap', 'do.deming.analytical', 'do.wdeming.jackknife', 'do.wdeming.nestedbootstrap', 'do.paba', 'do.paba.nestedbootstrap', 'do.pabalarge', 'do.pabalarge.nestedbootstrap')
state, record, script, r, report = option_run('MethodComparisonRegression', [('testData', [('test', [1.1, 2.3, 2.9, 4.2, 5.1, 5.8, 7.2, 8.1, 8.8, 10.3, 11.1, 12.4])]), ('referenceData', [('reference', list(range(1, 13)))])],
                                              {'error-ratio': 1.0, 'ci': 0.95, 'seed': 3, 'saveRScript': False, **{name: name == 'do.deming.analytical' for name in MCR_OPTIONS}})
r_slope = numbers(r, r'^Slope: (-?[0-9.]+) ')[0]; engine_slope = state['values']['slope'] if is_number(state['values'].get('slope')) else numbers(report, r'^Slope:? +(-?[0-9.]+)')[0]
print('      method comparison through the engine: engine slope %.7g, R %.7g' % (engine_slope, r_slope), flush=True)
check('do.deming.analytical <- TRUE' in script and 'do.paba <- FALSE' in script and near(r_slope, engine_slope, 1e-4), 'a real method comparison run\'s script runs the regression the run ticked and gives the engine\'s slope')
script, r = built({'operation': 'LinearizedEstimates', 'inputs': [{'name':'y','columns':columns_of(('kwh',[2,4,9,16,26,38]))}, {'name':'x','columns':columns_of(('size',[1,2,3,4,5,6]))}], 'settings': {'model': '1'}})
check('Selected model: Geometric / power' in r, 'the linearized estimates script names the model the run chose')
# A real Mac normal plot records its default method; R draws those scores alone.
state, record, script, r, report = option_run('NormalPlot', [('X', [('pimax', [40, 55, 62, 70, 76, 81, 88, 95, 103, 120])])], {})
run_r(script + '\nstopifnot(isTRUE(all.equal(normal_scores, qnorm(rank(observed)/(length(observed)+1)))))\n')
check(record['parameters']['chartSettings']['method']==1 and not record['parameters']['chartSettings']['scaleZ'] and 'The four values of 75' not in script, 'a real normal plot records its van der Waerden method and R draws exactly those scores without teaching illustrations')
script, r = built({'operation': 'UnivariateSummary', 'data': columns_of(('speed', [12, 15, 11, 19, 22, 14, 30, 25, 17, 21, 16, 18])), 'settings': {'gamma': 0.95, 'report-udca': 0.1, 'report-udcb': 0.9}})
check('Centile 90 ' in r and 'Centile 10 ' in r and 'Centile 95' not in r, 'the summary\'s script gives the two centiles the run chose')

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
    printed = figures(output).split(); allowed = set(help_figures[op].split()); missing = [f for f in printed if f not in allowed]
    print('      %s %s: %s' % (op, json.dumps(settings), output.strip().replace('\n', ' | ')), flush=True)
    if not printed or missing: failures.append('%s %s: %s' % (op, settings, 'printed no figure' if not printed else 'not in the help\'s output: ' + ', '.join(missing)))
for f in failures: print('      ' + f, flush=True)
check(not failures and all(x['hasRecipe'] for x in inverse_scripts), 'every inverse a distribution recipe gives prints figures the help\'s script prints: %d of %d cases' % (len(INVERSE) - len(failures), len(INVERSE)))
s.finish(); rs.close()
print('PASS %d run record checks' % checks)
