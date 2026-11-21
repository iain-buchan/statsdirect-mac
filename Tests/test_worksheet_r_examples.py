"""The worksheet R examples on the Mac, from an Excel file to the object in R.

    python3 Tests/test_worksheet_r_examples.py <workbook-driver> <node> <Rscript> [examples.json ...]

With no example files named, it runs the cases shared with StatsDirect for Windows (Learn/Upstream/WorksheetR/examples.json,
at the pinned Learning tag; see RULES.md beside it) and the Mac's own (Tests/worksheet-r-mac-examples.json). Every case
without skip.mac goes through the Mac's own code, each part as the app runs it:

1. The case is written as a real .xlsx with the standard library, in hand-written SpreadsheetML, so that a formula's saved
   value is exactly what Excel writes: t="str" with <v></v> for empty text, t="b", t="e", or a number. The file carries the
   case's number formats (built-in ids for built-in codes, custom numFmts otherwise), its format-only cells (a style and no
   value) and merged areas. Text goes in the shared-string table on odd rows and inline on even rows, so both readers are
   used. Characters XML 1.0 cannot hold (NUL, other C0 controls, U+FFFE, U+FFFF, lone surrogates), and CR, which XML would
   read as LF, are written as Excel's _xHHHH_ escapes, and a literal _x as _x005F_x. Dates, times and durations are serials
   with their formats, so the loader decides their kinds.
2. The engine's loader (FullEngine/publish/StatsDirectEngine.dylib, through the workbook driver) opens it and writes the
   typed snapshot that the app's grid reads.
3. Node (Tests/worksheet-r-examples.mjs) loads the snapshot into a WorkbookStore as the grid's loadWorkbook does, types the
   cells a Mac case types, makes the case's selection as Glide and Grid/main.tsx give it, and calls the grid's own
   worksheetRImport for the prompt's preview and for the data. Select all runs in each of its Mac forms. The Mac grid
   opens a workbook with only the columns its file uses, so where a case selects beyond them the grid is first grown with
   its own Add column command, as a user would have to, and the run's label says so.
4. Swift (Tests/worksheet-r-examples-driver.swift, compiled as Scripts/test-unified-toolbar.sh compiles the prompt driver)
   builds the Mac's prompt from the preview, makes the case's choices in it, checks the data as WorksheetRHost does, and
   writes the script with WorksheetRScript.build.
5. One Rscript run, in a UTF-8 locale, parses each whole script and evaluates it in the global environment as the
   integrated session does, then checks that it made worksheet_data alone, identical() to expect.r, and printed only its
   str().

Prints one PASS or FAIL line per check and a summary, and exits non-zero on any failure.
"""
import json, math, os, re, shutil, struct, subprocess, sys, tempfile, zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_EXAMPLES = [ROOT / 'Learn/Upstream/WorksheetR/examples.json', ROOT / 'Tests/worksheet-r-mac-examples.json']
if len(sys.argv) < 4:
    sys.exit(__doc__.split('\n\n')[1])
DRIVER, NODE, RSCRIPT = sys.argv[1:4]
EXAMPLES = [Path(p).resolve() for p in sys.argv[4:]] or DEFAULT_EXAMPLES
# A time zone away from UTC, with no daylight saving, so that a date moved by this Mac's own zone would show.
ZONE = dict(os.environ, TZ='Asia/Kolkata')

# ---------- The cases ----------

SERIALS = ('date', 'datetime', 'time', 'duration')
CELL_KINDS = ('number', 'text', 'textUnits', 'boolean', 'error', 'formula', 'typed') + SERIALS

def tag(path):
    return 'shared' if path.parent.name == 'WorksheetR' else 'mac' if path.name == 'worksheet-r-mac-examples.json' else path.stem

def check_cell(where, cell, inside_formula=False):
    """Refuses a cell this harness would not write as the schema says, so that a new kind of cell cannot pass unseen."""
    kinds = [k for k in CELL_KINDS if k in cell]
    allowed = {kinds[0]} if len(kinds) == 1 else set()
    if kinds and kinds[0] in SERIALS: allowed.add('format')
    if kinds == ['formula']: allowed.add('value')
    if len(kinds) != 1 or set(cell) != allowed or inside_formula and kinds[0] in ('formula', 'typed'):
        raise SystemExit(f'{where}: a cell this harness cannot write: {json.dumps(cell)}')
    if kinds == ['formula']: check_cell(where + ' (its value)', cell['value'], True)

# Every field the schema names, the Mac file's dateSystem included: a field added to a later version stops the test, rather
# than passing unread.
CASE_KEYS = {'name', 'rules', 'cells', 'select', 'options', 'expect', 'formatOnly', 'merged', 'note', 'skip', 'dateSystem'}
SELECT_KEYS = {'entire', 'range', 'columns', 'rows', 'areas', 'all', 'none'}
OPTION_KEYS = {'format', 'headings', 'friendly'}
EXPECT_KEYS = {'entire', 'selected', 'entireEnabled', 'selectedEnabled', 'headingsEnabled', 'headingsSuggested', 'comments', 'r',
               'refusedNaming', 'refusedMessage', 'labelsOnly'}

def check_case(where, case):
    for field, keys, allowed in [('the case', set(case), CASE_KEYS), ('select', set(case['select']), SELECT_KEYS),
                                 ('options', set(case['options']), OPTION_KEYS), ('expect', set(case['expect']), EXPECT_KEYS)]:
        if not keys <= allowed: raise SystemExit(f'{where}: {field} has fields this harness does not know: {sorted(keys - allowed)}')
    if len(case['select']) != 1 or case.get('dateSystem', 1900) not in (1900, 1904):
        raise SystemExit(f'{where}: a selection or date system this harness cannot make')
    for ref, cell in case['cells'].items():
        check_cell(f'{where} {ref}', cell)

cases = []
for path in EXAMPLES:
    examples = json.loads(path.read_text(encoding='utf-8'))
    for number, case in enumerate(examples['cases'], 1):
        check_case(f'{tag(path)} {number}', case)
        cases.append(dict(case, tag=f'{tag(path)} {number}', id=f'{tag(path)}-{number:02d}'))

# ---------- The workbook, written as Excel writes it ----------

BUILT_IN = {  # ECMA-376 Part 1, 18.8.30: the built-in number formats, as openpyxl and Excel (en-US) name them
    'General': 0, '0': 1, '0.00': 2, '#,##0': 3, '#,##0.00': 4, '0%': 9, '0.00%': 10, '0.00E+00': 11, '# ?/?': 12,
    '# ??/??': 13, 'mm-dd-yy': 14, 'd-mmm-yy': 15, 'd-mmm': 16, 'mmm-yy': 17, 'h:mm AM/PM': 18, 'h:mm:ss AM/PM': 19,
    'h:mm': 20, 'h:mm:ss': 21, 'm/d/yy h:mm': 22, '#,##0 ;(#,##0)': 37, '#,##0 ;[Red](#,##0)': 38,
    '#,##0.00;(#,##0.00)': 39, '#,##0.00;[Red](#,##0.00)': 40, 'mm:ss': 45, '[h]:mm:ss': 46, 'mmss.0': 47,
    '##0.0E+0': 48, '@': 49}
FORMAT_ONLY = 'yyyy-mm-dd'   # a format-only cell's number format: a date, which must not make the empty cell a date
MAIN = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'
RELS = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
PACKAGE = 'http://schemas.openxmlformats.org/package/2006/relationships'
HEAD = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'

def column_number(letters):
    n = 0
    for ch in letters: n = n * 26 + ord(ch) - 64
    return n

def column_letters(n):
    s = ''
    while n: n, r = divmod(n - 1, 26); s = chr(65 + r) + s
    return s

def address(ref):
    m = re.fullmatch(r'([A-Z]{1,3})([1-9][0-9]*)', ref)
    if not m: raise SystemExit(f'Not a cell reference: {ref}')
    return column_number(m.group(1)), int(m.group(2))

def markup(text):
    return text.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')

def attribute(text):
    return markup(text).replace('"', '&quot;')

def cell_text(text):
    """Text as Excel writes it in a <t> or <v>: a literal _x as _x005F_x, then each character XML 1.0 cannot hold, and CR
    (which an XML reader turns into LF), as _xHHHH_."""
    out = []
    for ch in text.replace('_x', '_x005F_x'):
        c = ord(ch)
        if c in (0x9, 0xA) or 0x20 <= c <= 0xD7FF or 0xE000 <= c <= 0xFFFD or c >= 0x10000: out.append(markup(ch))
        else: out.append('_x%04X_' % c)
    return ''.join(out)

def units_text(units):
    """A string from UTF-16 code units, lone surrogates included."""
    return struct.pack('<%dH' % len(units), *units).decode('utf-16-le', 'surrogatepass')

def number_text(decimal):
    """The nearest double to the case's decimal text, in the shortest form that reads back as it, as Excel would write it."""
    x = float(decimal)
    if not math.isfinite(x): raise SystemExit(f'Not a finite number: {decimal}')
    text = repr(x)
    return (text[:-2] if text.endswith('.0') else text).replace('e', 'E')

def write_workbook(case, path):
    formats, strings, shared = [], [], {}
    def style(code):   # cellXfs index 0 is General; each format used gets its own
        if code not in formats: formats.append(code)
        return formats.index(code) + 1
    def string(text, row):
        if row % 2 == 0: return f' t="inlineStr"><is><t xml:space="preserve">{cell_text(text)}</t></is>'
        if text not in shared: shared[text] = len(shared)
        strings.append(text)
        return f' t="s"><v>{shared[text]}</v>'
    def value(cell, row):   # the attributes and content after <c r="..."
        if 'number' in cell: return f'><v>{number_text(cell["number"])}</v>'
        if 'text' in cell or 'textUnits' in cell:
            return string(cell['text'] if 'text' in cell else units_text(cell['textUnits']), row)
        if 'boolean' in cell: return f' t="b"><v>{1 if cell["boolean"] else 0}</v>'
        if 'error' in cell: return f' t="e"><v>{markup(cell["error"])}</v>'
        kind = next(k for k in SERIALS if k in cell)
        return f' s="{style(cell["format"])}"><v>{number_text(cell[kind])}</v>'
    def formula(cell):   # a formula with the value Excel saved for it
        saved = cell['value']
        text = markup(cell['formula'][1:] if cell['formula'].startswith('=') else cell['formula'])
        if 'text' in saved: return f' t="str"><f>{text}</f><v>{cell_text(saved["text"])}</v>'
        if 'boolean' in saved: return f' t="b"><f>{text}</f><v>{1 if saved["boolean"] else 0}</v>'
        if 'error' in saved: return f' t="e"><f>{text}</f><v>{markup(saved["error"])}</v>'
        if 'number' in saved: return f'><f>{text}</f><v>{number_text(saved["number"])}</v>'
        kind = next(k for k in SERIALS if k in saved)
        return f' s="{style(saved["format"])}"><f>{text}</f><v>{number_text(saved[kind])}</v>'
    rows = {}
    for ref, cell in case['cells'].items():
        if 'typed' in cell: continue   # typed into the grid once the workbook is open, never in the file
        col, row = address(ref)
        rows.setdefault(row, {})[col] = (ref, cell)
    for ref in case.get('formatOnly', []):
        col, row = address(ref)
        rows.setdefault(row, {}).setdefault(col, (ref, None))
    sheet_rows = []
    for row in sorted(rows):
        cells = []
        for col in sorted(rows[row]):
            ref, cell = rows[row][col]
            if cell is None: cells.append(f'<c r="{ref}" s="{style(FORMAT_ONLY)}"/>')
            else: cells.append(f'<c r="{ref}"' + (formula(cell) if 'formula' in cell else value(cell, row)) + '</c>')
        sheet_rows.append(f'<row r="{row}">' + ''.join(cells) + '</row>')
    used = [(col, row) for row in rows for col in rows[row]]
    dimension = 'A1' if not used else (f'{column_letters(min(c for c, _ in used))}{min(r for _, r in used)}:'
                                       f'{column_letters(max(c for c, _ in used))}{max(r for _, r in used)}')
    merged = case.get('merged', [])
    sheet = (HEAD + f'<worksheet xmlns="{MAIN}" xmlns:r="{RELS}"><dimension ref="{dimension}"/>'
             '<sheetViews><sheetView workbookViewId="0"/></sheetViews><sheetFormatPr defaultRowHeight="15"/>'
             + ('<sheetData>' + ''.join(sheet_rows) + '</sheetData>' if sheet_rows else '<sheetData/>')
             + (f'<mergeCells count="{len(merged)}">' + ''.join(f'<mergeCell ref="{m}"/>' for m in merged) + '</mergeCells>' if merged else '')
             + '<pageMargins left="0.7" right="0.7" top="0.75" bottom="0.75" header="0.3" footer="0.3"/></worksheet>')
    ids, custom = [], []
    for code in formats:
        if code in BUILT_IN: ids.append(BUILT_IN[code])
        else: custom.append((164 + len(custom), code)); ids.append(custom[-1][0])
    styles = (HEAD + f'<styleSheet xmlns="{MAIN}">'
              + (f'<numFmts count="{len(custom)}">' + ''.join(f'<numFmt numFmtId="{i}" formatCode="{attribute(c)}"/>' for i, c in custom) + '</numFmts>' if custom else '')
              + '<fonts count="1"><font><sz val="11"/><name val="Calibri"/><family val="2"/></font></fonts>'
              '<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>'
              '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
              '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
              f'<cellXfs count="{len(ids) + 1}"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
              + ''.join(f'<xf numFmtId="{i}" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>' for i in ids)
              + '</cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>')
    sst = (HEAD + f'<sst xmlns="{MAIN}" count="{len(strings)}" uniqueCount="{len(shared)}">'
           + ''.join(f'<si><t xml:space="preserve">{cell_text(t)}</t></si>' for t in shared) + '</sst>')
    workbook = (HEAD + f'<workbook xmlns="{MAIN}" xmlns:r="{RELS}">'
                + ('<workbookPr date1904="1"/>' if case.get('dateSystem') == 1904 else '<workbookPr/>')
                + '<bookViews><workbookView/></bookViews><sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets></workbook>')
    types = (HEAD + '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
             '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
             '<Default Extension="xml" ContentType="application/xml"/>'
             '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
             '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
             '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
             '<Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>'
             '</Types>')
    package_rels = (HEAD + f'<Relationships xmlns="{PACKAGE}"><Relationship Id="rId1" '
                    f'Type="{RELS}/officeDocument" Target="xl/workbook.xml"/></Relationships>')
    workbook_rels = (HEAD + f'<Relationships xmlns="{PACKAGE}">'
                     f'<Relationship Id="rId1" Type="{RELS}/worksheet" Target="worksheets/sheet1.xml"/>'
                     f'<Relationship Id="rId2" Type="{RELS}/styles" Target="styles.xml"/>'
                     f'<Relationship Id="rId3" Type="{RELS}/sharedStrings" Target="sharedStrings.xml"/></Relationships>')
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as package:
        for name, xml in [('[Content_Types].xml', types), ('_rels/.rels', package_rels), ('xl/workbook.xml', workbook),
                          ('xl/_rels/workbook.xml.rels', workbook_rels), ('xl/styles.xml', styles),
                          ('xl/sharedStrings.xml', sst), ('xl/worksheets/sheet1.xml', sheet)]:
            package.writestr(name, xml.encode('utf-8'))

def self_test():
    """The text escapes, checked against the loader's reading of them (Unescape in FullEngine/WorkbookIO.cs)."""
    unescape = lambda t: re.sub(r'_x([0-9A-Fa-f]{4})_', lambda m: chr(int(m.group(1), 16)), t)
    for text in ['a\x00b', 'line\r\nbreak', '_x0041_', '_x005F_', 'a_xyz_x', units_text([97, 0xD800, 98]), '\ufffe\uffff', '\U0001F600 & <b>']:
        written = cell_text(text).replace('&amp;', '&').replace('&lt;', '<').replace('&gt;', '>')
        assert unescape(written) == text, (text, written)

# ---------- Running the parts ----------

passed = failed = 0
lines = {}   # run id -> its check lines, printed in run order

def report(run_id, label, check, ok, detail=''):
    global passed, failed
    if ok: passed += 1
    else: failed += 1
    lines.setdefault(run_id, []).append(('PASS' if ok else 'FAIL') + f' {label}: {check}' + ('' if ok or not detail else f' ({detail})'))

def r_string(text):
    out = ['"']
    for ch in text:
        c = ord(ch)
        if ch in '"\\': out.append('\\' + ch)
        elif 0x20 <= c < 0x7f: out.append(ch)
        else: out.append('\\u{%x}' % c)
    return ''.join(out + ['"'])

R_CHECKS = r'''
read_text <- function(path) {
  size <- file.info(path)$size
  text <- if (size > 0) readChar(path, size, useBytes = TRUE) else ""
  Encoding(text) <- "UTF-8"
  text
}
one_line <- function(x) gsub("[\t\r\n]+", " ", paste(x, collapse = " "))
exact <- function(x) one_line(deparse(x, control = c("keepNA", "keepInteger", "niceNames", "showAttributes", "hexNumeric")))
# As StatsDirect's own R session runs a script (Native/RConsoleWorker.cpp, evaluate): the whole text is parsed at once, then
# each expression is evaluated in the global environment and printed when visible.
run_case <- function(id, script, expected) {
  if (exists("worksheet_data", envir = globalenv(), inherits = FALSE)) rm("worksheet_data", envir = globalenv())
  before <- ls(globalenv(), all.names = TRUE)
  problems <- character(0)
  printed <- tryCatch(withCallingHandlers(capture.output({
      expressions <- parse(text = read_text(script), keep.source = FALSE, encoding = "UTF-8")
      for (e in expressions) { r <- withVisible(eval(e, globalenv())); if (r$visible) print(r$value) }
    }), warning = function(w) { problems <<- c(problems, paste("warning:", conditionMessage(w))); invokeRestart("muffleWarning") }),
    error = function(e) { problems <<- c(problems, paste("error:", conditionMessage(e))); character(0) })
  made <- setdiff(ls(globalenv(), all.names = TRUE), before)
  want <- eval(parse(text = read_text(expected), keep.source = FALSE, encoding = "UTF-8")[[1L]], baseenv())
  if (!length(problems)) {
    if (!identical(made, "worksheet_data")) {
      problems <- paste("the script made", if (length(made)) paste(made, collapse = ", ") else "no object")
    } else if (!identical(got <- get("worksheet_data", envir = globalenv()), want)) {
      problems <- paste("got", exact(got), "but expected", exact(want))
    } else if (!identical(printed, capture.output(str(want)))) {
      problems <- paste("R printed", one_line(printed), "instead of str(worksheet_data) alone")
    }
  }
  cat("RESULT\t", id, "\t", if (length(problems)) one_line(problems) else "PASS", "\n", sep = "")
}
'''

def main():
    self_test()
    for case in cases:
        if 'mac' in case.get('skip', {}): print(f'SKIP {case["tag"]} {case["name"]}: {case["skip"]["mac"]}')
    todo = [c for c in cases if 'mac' not in c.get('skip', {})]
    dylib = ROOT / 'FullEngine/publish/StatsDirectEngine.dylib'
    if not dylib.exists(): raise SystemExit(f'Build the engine first (FullEngine/build.sh): {dylib} is missing.')
    folder = Path(tempfile.mkdtemp(prefix='worksheet-r-examples-'))
    try:
        # 1 and 2: each workbook, opened by the engine's own loader into a snapshot.
        driver = subprocess.Popen([DRIVER, str(dylib)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, encoding='utf-8', env=ZONE)
        def request(**payload):
            driver.stdin.write(json.dumps(payload) + '\n'); driver.stdin.flush()
            return json.loads(driver.stdout.readline())
        plan = []
        try:
            for case in todo:
                book = folder / f'{case["id"]}.xlsx'
                write_workbook(case, book)
                reply = request(action='open', path=str(book), snapshot=str(folder / 'snapshots'))
                if 'error' in reply or reply.get('dataCopy'):
                    raise SystemExit(f'{case["tag"]}: the loader did not open the workbook as an editable .xlsx: {reply}')
                assert request(action='close', id=reply['id']).get('ok'), case['tag']
                typed = [{'ref': ref, 'text': cell['typed']} for ref, cell in case['cells'].items() if 'typed' in cell]
                plan.append({'id': case['id'], 'select': case['select'], 'options': case['options'],
                             'labelsOnly': bool(case['expect'].get('labelsOnly')), 'typed': typed, 'reply': reply})
        finally:
            driver.stdin.close(); driver.wait(timeout=30)
        # 3: the grid's preview and data.
        (folder / 'plan.json').write_text(json.dumps({'cases': plan}), encoding='utf-8')
        subprocess.run([NODE, str(ROOT / 'Tests/worksheet-r-examples.mjs'), str(folder / 'plan.json'), str(folder / 'runs.json')],
                       check=True, env=ZONE)
        runs = json.loads((folder / 'runs.json').read_text(encoding='utf-8'))['runs']
        # 4: the prompt and the script.
        (ROOT / '.build/swift-cache').mkdir(parents=True, exist_ok=True)
        swift = folder / 'worksheet-r-examples-driver'
        subprocess.run(['swiftc', '-target', 'arm64-apple-macosx14.0', '-module-cache-path', str(ROOT / '.build/swift-cache'),
                        *[str(ROOT / s) for s in ('Sources/ConversationRScript.swift', 'Sources/WorksheetRScript.swift',
                                                  'Sources/WorksheetRImportPrompt.swift', 'Tests/worksheet-r-examples-driver.swift')],
                        '-o', str(swift), '-framework', 'Cocoa'], check=True)
        subprocess.run([str(swift), str(folder / 'runs.json'), str(folder / 'prompts.json')], check=True)
        prompts = {p['id']: p for p in json.loads((folder / 'prompts.json').read_text(encoding='utf-8'))['results']}
        # The checks of the labels, the prompt's choice and the script; the R objects are queued for one Rscript run.
        by_id = {c['id']: c for c in todo}
        r_runs, r_lines = {}, [R_CHECKS]
        mac = lambda value: value['mac'] if isinstance(value, dict) else value   # a label given per platform
        for run in runs:
            case, prompt, rid = by_id[run['case']], prompts[run['id']], run['id']
            label = case['tag'] + ' ' + case['name'] + (f' [{run["form"]}]' if run['form'] else '')
            expect, options = case['expect'], case['options']
            if 'previewError' in run:
                report(rid, label, 'the grid gives the prompt its preview', False, run['previewError']); continue
            for key in ('entire', 'selected'):
                if key in expect: report(rid, label, f'{key} label "{mac(expect[key])}"', prompt[key] == mac(expect[key]), f'shows "{prompt[key]}"')
            for key in ('entireEnabled', 'selectedEnabled', 'headingsSuggested', 'headingsEnabled'):
                if key in expect: report(rid, label, f'{key} {str(expect[key]).lower()}', prompt[key] == expect[key], f'is {str(prompt[key]).lower()}')
            if expect.get('labelsOnly'): continue
            choice, option = prompt['choice'], run['preview'][run['scope']]
            if expect.get('r') is None and 'refusedMessage' not in expect:
                report(rid, label, 'nothing can be imported', choice['scope'] == 'none', f'the prompt imports {choice["scope"]}')
                continue
            # The prompt can make the choice the case describes, and asks the grid for the headings the data used.
            headings = run['headings'] and option is not None and option['rowCount'] > 1
            wanted = {'scope': run['scope'], 'headings': headings, 'asList': options['format'] == 'list',
                      'rFriendlyNames': bool(options['friendly']) and headings}
            report(rid, label, "the prompt makes the case's choice", choice == wanted, f'it makes {choice}, not {wanted}')
            problem = run.get('error') or prompt.get('hostError') or prompt.get('scriptError')
            if 'refusedMessage' in expect:
                naming = expect.get('refusedNaming')
                names = naming is None or re.search(r'\b%s\b' % re.escape(naming), problem or '') is not None
                report(rid, label, f'refused: "{expect["refusedMessage"]}"' + (f', naming {naming}' if naming else ''),
                       problem == expect['refusedMessage'] and names,
                       'it was imported' if not problem else f'refused with {json.dumps(problem, ensure_ascii=False)}')
                continue
            script = prompt.get('script')
            if problem or script is None:
                report(rid, label, 'imported', False, problem or 'no script')
                continue
            for line in expect.get('comments', []):
                report(rid, label, f'comment "{line}"', line in script.split('\n'))
            number = len(r_runs) + 1
            (folder / f'r-{number}.R').write_text(script, encoding='utf-8')
            (folder / f'r-{number}.expected.R').write_text(expect['r'], encoding='utf-8')
            r_runs[str(number)] = (rid, label)
            r_lines.append(f'run_case({r_string(str(number))}, {r_string(str(folder / f"r-{number}.R"))}, '
                           f'{r_string(str(folder / f"r-{number}.expected.R"))})')
        # 5: every object in R, in one run.
        (folder / 'checks.R').write_text('\n'.join(r_lines) + '\n', encoding='utf-8')
        r = subprocess.run([RSCRIPT, '--vanilla', str(folder / 'checks.R')], capture_output=True, text=True, encoding='utf-8',
                           env=dict(os.environ, LANG='en_US.UTF-8', LC_ALL='en_US.UTF-8'))
        results = dict(line.split('\t')[1:3] for line in r.stdout.splitlines() if line.startswith('RESULT\t'))
        for number, (rid, label) in r_runs.items():
            outcome = results.get(number, f'R stopped before this case (status {r.returncode}): {r.stderr.strip()[-400:]}')
            report(rid, label, 'R makes worksheet_data identical() to expect.r', outcome == 'PASS', outcome)
        for run in runs:
            for line in lines.get(run['id'], []): print(line)
        print(f'worksheet R examples: {len(todo)} cases ({len(cases) - len(todo)} skipped), {len(runs)} runs, '
              f'{passed + failed} checks, {failed} failures')
    finally:
        if os.environ.get('WORKSHEET_R_EXAMPLES_KEEP'): print(f'Work files kept in {folder}')
        else: shutil.rmtree(folder, ignore_errors=True)
    sys.exit(1 if failed or not passed else 0)

main()
