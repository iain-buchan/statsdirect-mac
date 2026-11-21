"""Save As/reopen when a formula calls a function ClosedXML does not implement.

Called by test_excel_edges.py in CI. Focused usage (optional retained work folder):
  python3 Tests/excel_closedxml_functions_save.py <workbook-driver> <node> [work-folder]

The default save patches a small workbook through ClosedXML, which writes its own result for every formula. For a
function it lacks that result is #NAME?, and IFERROR, ISERROR or IFNA turn it into an ordinary value, so a reopened
workbook would send R a result Excel never computed. Such a workbook must take the streaming patcher instead: its
formulas keep their expressions and lose their saved results, which Excel recalculates, and the reopened cells are
refused for R until then. A defined name a formula uses counts as that formula. A workbook whose functions ClosedXML
implements keeps the ClosedXML path and its recalculated results, even with such a name in a string literal, in a quoted
sheet name, or in a defined name nothing uses.
Every source is real OOXML with Excel's saved results; the actual grid model makes the edit, exports its edit snapshot
and reads the reopened cells for R.
"""
import json
import math
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
import zipfile
import openpyxl
from openpyxl.workbook.defined_name import DefinedName

ROOT = Path(__file__).resolve().parents[1]
MAIN = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'
S = '{' + MAIN + '}'
PART = 'xl/worksheets/sheet1.xml'
REFUSAL = 'Recalculate and save this workbook in Excel, then reopen it before using formula cells in R.'
ET.register_namespace('', MAIN)

A, B = [1, 2, 3, 4, 5, 6], [2, 3, 5, 6, 8, 9]
def correl(x, y):
    mx, my = sum(x) / len(x), sum(y) / len(y)
    sxy = sum((a - mx) * (b - my) for a, b in zip(x, y))
    return sxy / math.sqrt(sum((a - mx) ** 2 for a in x) * sum((b - my) ** 2 for b in y))
R = repr(correl(A, B))
Z = '1.959963984540054'   # NORM.S.INV(0.975), as Excel saves it
# (cell, formula as Excel stores it, saved result, saved type)
FIXTURES = {
    'unknown': {'cells': [('C1', '_xlfn.NORM.S.INV(0.975)', Z, None),
                          ('C2', 'IFERROR(_xlfn.NORM.S.INV(0.975),0)', Z, None),
                          ('C3', 'IF(ISERROR(NORMSINV(0.975)),"failed","ok")', 'ok', 'str'),
                          ('C4', '_xlfn.IFNA(CORREL(A1:A6,B1:B6),-1)', R, None),
                          ('C5', 'IFERROR(CORREL(A1:A6,B1:B6),"n/a")', R, None),
                          ('C6', 'ISNUMBER(_xlfn.T.TEST(A1:A6,B1:B6,2,1))', '1', 'b'),
                          ('C7', 'SUM(A1:A6)', '21', None),
                          ('D1', 'E1*2', '4', None)],
                'names': {}, 'streams': True},
    # Only a defined name calls the function ClosedXML lacks; the formula that uses it would become 0.
    'name': {'cells': [('C1', 'IFERROR(Crit,0)', Z, None), ('D1', 'E1*2', '4', None)],
             'names': {'Crit': 'NORMSINV(0.975)'}, 'streams': True},
    'known': {'cells': [('C1', 'SUM(A1:A6)', '21', None),
                        ('C2', 'IF(A1>0,"NORM.S.INV(x)",1)', 'NORM.S.INV(x)', 'str'),
                        ("C3", "'NORMSINV(2)'!A1*2", '14', None),
                        ('D1', 'E1*2', '4', None)],
              'names': {'Dyn': 'OFFSET(Data!$A$1,0,0,COUNTA(Data!$A:$A),1)'}, 'streams': False},
}


def column_index(ref):
    n = 0
    for ch in ref:
        if not ch.isalpha(): break
        n = n * 26 + ord(ch.upper()) - 64
    return n


def fixture(path, spec):
    seed = path.with_suffix('.seed.xlsx')
    book = openpyxl.Workbook()
    ws = book.active
    ws.title = 'Data'
    for r, (a, b) in enumerate(zip(A, B), start=1): ws.cell(r, 1, a); ws.cell(r, 2, b)
    ws['E1'] = 2
    book.create_sheet('NORMSINV(2)')['A1'] = 7
    for name, text in spec['names'].items(): book.defined_names[name] = DefinedName(name, attr_text=text)
    book.save(seed)
    with zipfile.ZipFile(seed) as source, zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as target:
        for item in source.infolist():
            data = source.read(item.filename)
            if item.filename == PART:
                sheet = ET.fromstring(data)
                sheet_data = sheet.find(S + 'sheetData')
                rows = {int(row.attrib['r']): row for row in sheet_data.iter(S + 'row')}
                for ref, formula, value, kind in spec['cells']:
                    number = int(ref[1:])
                    if number not in rows: rows[number] = ET.SubElement(sheet_data, S + 'row', {'r': str(number)})
                    cell = ET.SubElement(rows[number], S + 'c', {'r': ref, **({'t': kind} if kind else {})})
                    ET.SubElement(cell, S + 'f').text = formula
                    ET.SubElement(cell, S + 'v').text = value
                for row in rows.values(): row[:] = sorted(row, key=lambda c: column_index(c.attrib['r']))
                sheet_data[:] = sorted(sheet_data, key=lambda row: int(row.attrib['r']))
                data = ET.tostring(sheet, encoding='utf-8')
            target.writestr(item, data)
    seed.unlink()


def xml_cells(path):
    with zipfile.ZipFile(path) as archive: sheet = ET.fromstring(archive.read(PART))
    return {cell.attrib['r']: cell for cell in sheet.iter(S + 'c')}


def position(ref): return [column_index(ref) - 1, int(ref[1:]) - 1]


def check_closedxml_function_saves(request, node, folder):
    folder = Path(folder) / 'closedxml-functions-save'
    folder.mkdir(parents=True, exist_ok=True)
    snapshots = folder / 'snapshots'
    snapshots.mkdir(exist_ok=True)
    failures = []
    def check(ok, label):
        print(('PASS: ' if ok else 'FAIL: ') + label, flush=True)
        if not ok: failures.append(label)
    def grid(reply, refs, label, edit=None):
        payload = folder / (label + '.json')
        payload.write_text(json.dumps({'reply': reply, 'cells': [position(ref) for ref in refs], 'edit': edit}), encoding='utf-8')
        edits = folder / (label + '.edits.sdcol')
        command = [node, str(ROOT / 'Tests/worksheet-r-cells.mjs'), str(payload)] + ([str(edits)] if edit else [])
        return json.loads(subprocess.check_output(command, text=True, cwd=ROOT)), edits
    for variant, spec in FIXTURES.items():
        source = folder / (variant + '-source.xlsx')
        fixture(source, spec)
        refs = [ref for ref, *_ in spec['cells']]
        opened = request(action='open', path=str(source), snapshot=str(snapshots))
        assert 'error' not in opened, opened
        try:
            seen, edits = grid(opened, refs, variant, edit=[4, 0, '10'])
            fresh = {ref: cell for ref, cell in zip(refs, seen['before'])}
            check(fresh['D1'].get('values') == ['4'] and all(cell.get('values') is not None for cell in fresh.values()),
                  variant + ': the freshly opened results go to R as Excel saved them')
            check(all(cell.get('error') == REFUSAL for cell in seen['after']), variant + ': after the grid edit every formula result is refused for R')
            for label, snapshot in ((variant + '-edited', edits), (variant + '-unedited', None)):
                saved_path = folder / (label + '.xlsx')
                # Unedited, the grid sends every worksheet with no changed cells.
                unchanged = [{'name': sheet['name'], 'cells': []} for sheet in opened['sheets']]
                saved = request(action='save', path=str(saved_path), id=opened['id'], **({'snapshot': str(snapshot)} if snapshot else {'sheets': unchanged}))
                if not saved.get('ok'): check(False, label + ': the default save succeeded: ' + str(saved)); continue
                old_xml, new_xml = xml_cells(source), xml_cells(saved_path)
                check(all(new_xml[ref].findtext(S + 'f') == old_xml[ref].findtext(S + 'f') for ref in refs), label + ': every formula expression is kept')
                reopened = request(action='open', path=str(saved_path), snapshot=str(snapshots))
                assert 'error' not in reopened, reopened
                try:
                    back, _ = grid(reopened, refs + ['A1', 'E1'], label + '-reopened')
                    cells = {ref: cell for ref, cell in zip(refs + ['A1', 'E1'], back['before'])}
                    check(cells['A1'].get('values') == ['1'] and cells['E1'].get('values') == (['10'] if snapshot else ['2']), label + ': the values around the formulas survive')
                    if spec['streams']:
                        check(saved.get('recalculated') is False and saved.get('uncachedFormulas') == len(refs),
                              label + ': a function ClosedXML lacks sends the workbook to the streaming patcher: ' + json.dumps(saved))
                        check(all(new_xml[ref].find(S + 'v') is None and 't' not in new_xml[ref].attrib for ref in refs),
                              label + ': no formula keeps a saved result: no #NAME?, no IFERROR or ISERROR fallback, no stale value')
                        check(all(cells[ref]['text'] == '' and cells[ref]['unavailable'] is True and cells[ref].get('error') == REFUSAL for ref in refs),
                              label + ': every reopened formula result is refused for R until Excel recalculates it: ' + json.dumps([cells[ref] for ref in refs]))
                    else:
                        expected = {'C1': ['21'], 'C2': ['NORM.S.INV(x)'], 'C3': ['14'], 'D1': ['20' if snapshot else '4']}
                        check(saved.get('recalculated') is True and saved.get('uncachedFormulas') == 0,
                              label + ': functions ClosedXML implements keep the ClosedXML patcher: ' + json.dumps(saved))
                        check({ref: cells[ref].get('values') for ref in refs} == expected,
                              label + ': the reopened results are ClosedXML\'s recalculated ones, and R receives them: ' + json.dumps([cells[ref] for ref in refs]))
                finally: assert request(action='close', id=reopened['id']).get('ok')
        finally: assert request(action='close', id=opened['id']).get('ok')
    if failures: raise AssertionError(f'{len(failures)} ClosedXML function save/reopen checks failed: ' + '; '.join(failures))
    print('PASS: Save As never writes ClosedXML\'s #NAME? or a wrong IFERROR, ISERROR or IFNA result as Excel\'s', flush=True)


def main():
    if len(sys.argv) not in (3, 4): raise SystemExit(__doc__)
    engine = os.environ.get('STATSDIRECT_ENGINE', str(ROOT / 'FullEngine/publish/StatsDirectEngine.dylib'))
    driver = subprocess.Popen([sys.argv[1], engine], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, env=dict(os.environ, TZ='Asia/Kolkata'))
    def request(**payload):
        driver.stdin.write(json.dumps(payload) + '\n'); driver.stdin.flush()
        return json.loads(driver.stdout.readline())
    try:
        if len(sys.argv) == 4: check_closedxml_function_saves(request, sys.argv[2], Path(sys.argv[3]))
        else:
            with tempfile.TemporaryDirectory(prefix='closedxml-functions-save-') as folder: check_closedxml_function_saves(request, sys.argv[2], Path(folder))
    finally:
        driver.stdin.close(); driver.wait(timeout=15)

if __name__ == '__main__': main()
