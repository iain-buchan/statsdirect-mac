"""Edited and unedited Save As/reopen for workbooks with worksheet formulas.

Called by test_excel_edges.py in CI. Focused usage (optional retained work folder):
  python3 Tests/excel_closedxml_functions_save.py <workbook-driver> <node> [work-folder]

An edited save preserves formula expressions and clears the saved results for Excel to recalculate, even if
ClosedXML would reproduce all the old cached results. An unedited Save As preserves the workbook byte for byte.
Every source is real OOXML with injected Excel-equivalent cached results. The grid makes the edit, exports its
normal typed edit snapshot and checks whether the reopened cells can be used in R.
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
from openpyxl.packaging.relationship import Relationship
from openpyxl.workbook.defined_name import DefinedName
from openpyxl.worksheet.table import Table
from openpyxl.workbook.external_link import external

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
                'names': {}},
    # Only a defined name calls the function ClosedXML lacks; the formula that uses it would become 0.
    'name': {'cells': [('C1', 'IFERROR(Crit,0)', Z, None), ('D1', 'E1*2', '4', None)],
             'names': {'Crit': 'NORMSINV(0.975)'}},
    'known': {'cells': [('C1', 'SUM(A1:A6)', '21', None),
                        ('C2', 'IF(A1>0,"NORM.S.INV(x)",1)', 'NORM.S.INV(x)', 'str'),
                        ("C3", "'NORMSINV(2)'!A1*2", '14', None),
                        ('D1', 'E1*2', '4', None)],
              'names': {'Dyn': 'OFFSET(Data!$A$1,0,0,COUNTA(Data!$A:$A),1)'}},
    # Ordinary statistics: editing E1 invalidates their saved results, even if ClosedXML could reproduce them.
    'statistics': {'cells': [('C1', 'STDEV(A1:A6)', '1.8708286933869707', None),
                             ('C2', 'AVERAGE(B1:B6)*E1', '11', None),
                             ('D1', 'E1*2', '4', None)],
                   'names': {}},
    # A link that no formula reads still survives in the workbook package.
    'phantom': {'cells': [('C1', 'E1*3', '6', None), ('D1', 'E1*2', '4', None)],
                'names': {'Ext': '[1]Sheet!$A$1'}, 'external': True},
    # Old results can disagree or agree before the edit. Neither establishes the result for new inputs.
    'rounding': {'cells': [('C1', 'E1*3', '6', None), ('C4', 'ROUND(1.005,2)', '1.01', None), ('D1', 'E1*2', '4', None)],
                 'names': {}},
    # Both engines give the saved 2/1 for E1=2. For E1=1.005, Excel gives 1.01/1 while ClosedXML gives 1/0.
    'rounding-after-edit': {'cells': [('C1', 'ROUND(E1,2)', '2', None), ('C2', 'IF(C1>=1.01,1,0)', '1', None),
                                     ('D1', 'E1*2', '4', None)],
                            'names': {}, 'edit': [4, 0, '1.005']},
    # Table1 is on another sheet: ClosedXML reads the column in the formula's own sheet, and gives 14.
    'table': {'cells': [('C1', 'E1*3', '6', None), ('C5', 'SUM(Table1[Value])', '6', None), ('D1', 'E1*2', '4', None)],
              'names': {}, 'table': True},
    # Both sheets start with the same numbers. The edit changes the range ClosedXML wrongly reads, leaving the table alone.
    'table-after-edit': {'cells': [('C5', 'SUM(Table1[Value])', '14', None), ('D1', 'E1*2', '4', None)],
                         'names': {}, 'table': True, 'table_values': [3, 5, 6], 'edit': [1, 1, '10']},
    'text': {'cells': [('C1', 'E1*3', '6', None), ('C2', '(0.1+0.2)&""', '0.3', 'str'), ('D1', 'E1*2', '4', None)],
             'names': {}},
    # In C5 Excel takes the cell of the range in the formula's row, A5; ClosedXML takes the first, A1.
    'intersection': {'cells': [('C1', 'E1*3', '6', None), ('C5', 'A1:A6*2', '10', None), ('D1', 'E1*2', '4', None)],
                     'names': {}},
    # Volatile formulas and formulas saved without a result also wait for Excel to recalculate.
    'volatile': {'cells': [('C1', 'E1*3', '6', None), ('C2', 'TODAY()', '45000', None), ('D1', 'E1*2', '4', None)],
                 'names': {}},
    'unsaved': {'cells': [('C1', 'E1*3', None, None), ('D1', 'E1*2', '4', None)], 'names': {}},
    # The linked formula reads the edited E1 and comes after a local formula that ClosedXML reaches first: kept, its old
    # 99 would go to R where Excel gives 97 + 10 = 107.
    'external': {'cells': [('C1', 'E1*3', '6', None),
                           ('C2', 'IFERROR([1]Sheet!A1+E1,0)', '99', None),
                           ('D1', 'E1*2', '4', None)],
                 'names': {}, 'external': True},
    # The same formulas with no link part (a file produced by another workbook writer).
    'unlinked': {'cells': [('C1', 'E1*3', '6', None),
                           ('C2', 'IFERROR([1]Sheet!A1+E1,0)', '99', None),
                           ('D1', 'E1*2', '4', None)],
                 'names': {}},
    # A three-dimensional reference, which ClosedXML cannot evaluate: kept, its old 10 would go to R where Excel gives 18.
    'three-d': {'cells': [('C1', 'E1*3', '6', None),
                          ('C2', "IFERROR(SUM('Data:NORMSINV(2)'!A1)+E1,0)", '10', None),
                          ('D1', 'E1*2', '4', None)],
                'names': {}},
    # A circular reference, which ClosedXML cannot evaluate; Excel saved 0 for both cells.
    'circular': {'cells': [('C1', 'E1*3', '6', None),
                           ('C2', 'C3+1', '0', None),
                           ('C3', 'C2+1', '0', None),
                           ('D1', 'E1*2', '4', None)],
                 'names': {}},
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
    if spec.get('table'):
        other = book.create_sheet('T')
        other.append(['Name', 'Value', 'Qty'])
        for name, value, quantity in zip('abc', spec.get('table_values', (1, 2, 3)), (4, 5, 6)):
            other.append([name, value, quantity])
        other.add_table(Table(displayName='Table1', ref='A1:C4'))
    if spec.get('external'):
        linked_path = path.with_name('linked.xlsx')
        linked = openpyxl.Workbook()
        linked.active['A1'] = 97
        linked.save(linked_path)
        cached_row = external.ExternalRow(r=1, cell=[external.ExternalCell(r='A1', t='n', v='97')])
        cached_sheet = external.ExternalSheetData(sheetId=0, row=[cached_row])
        link = external.ExternalLink(externalBook=external.ExternalBook(
            sheetNames=external.ExternalSheetNames(['Sheet']),
            sheetDataSet=external.ExternalSheetDataSet([cached_sheet]), id='rId1'))
        link.file_link = Relationship(Id='rId1', type='externalLinkPath', Target=linked_path.resolve().as_uri(), TargetMode='External')
        book._external_links.append(link)
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
                    if value is not None: ET.SubElement(cell, S + 'v').text = value   # None: saved without a result
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
    def grid(reply, refs, label, edit=None, write_snapshot=False):
        payload = folder / (label + '.json')
        payload.write_text(json.dumps({'reply': reply, 'cells': [position(ref) for ref in refs], 'edit': edit}), encoding='utf-8')
        edits = folder / (label + '.edits.sdcol')
        command = [node, str(ROOT / 'Tests/worksheet-r-cells.mjs'), str(payload)] + ([str(edits)] if edit or write_snapshot else [])
        return json.loads(subprocess.check_output(command, text=True, cwd=ROOT)), edits
    for variant, spec in FIXTURES.items():
        source = folder / (variant + '-source.xlsx')
        fixture(source, spec)
        refs = [ref for ref, *_ in spec['cells']]
        opened = request(action='open', path=str(source), snapshot=str(snapshots))
        assert 'error' not in opened, opened
        try:
            edit = spec.get('edit', [4, 0, '10'])
            edited_ref = openpyxl.utils.cell.get_column_letter(edit[0] + 1) + str(edit[1] + 1)
            seen, edits = grid(opened, refs + [edited_ref], variant, edit=edit)
            fresh = {ref: cell for ref, cell in zip(refs, seen['before'])}
            check(fresh['D1'].get('values') == ['4'] and all((fresh[ref].get('values') is not None) == (value is not None) for ref, _, value, _ in spec['cells']),
                  variant + ': the freshly opened results go to R as Excel saved them')
            check(all(cell.get('error') == REFUSAL for cell in seen['after'][:len(refs)]), variant + ': after the grid edit every formula result is refused for R')
            _, unchanged = grid(opened, refs, variant + '-unchanged', write_snapshot=True)
            saves = [('edited', edits, True, False),
                     ('unedited', unchanged, False, False),
                     ('unedited-stream', unchanged, False, True)]
            for operation, snapshot, edited, stream in saves:
                label = variant + '-' + operation
                saved_path = folder / (label + '.xlsx')
                saved = request(action='save', path=str(saved_path), id=opened['id'], snapshot=str(snapshot), stream=stream)
                if not saved.get('ok'): check(False, label + ': the default save succeeded: ' + str(saved)); continue
                old_xml, new_xml = xml_cells(source), xml_cells(saved_path)
                check(all(new_xml[ref].findtext(S + 'f') == old_xml[ref].findtext(S + 'f') for ref in refs), label + ': every formula expression is kept')
                reopened = request(action='open', path=str(saved_path), snapshot=str(snapshots))
                assert 'error' not in reopened, reopened
                try:
                    reopened_refs = refs + ['A1', edited_ref]
                    back, _ = grid(reopened, reopened_refs, label + '-reopened')
                    cells = dict(zip(reopened_refs, back['before']))
                    edit_text = edit[2] if edited else seen['before'][-1]['text']
                    check(cells['A1'].get('values') == ['1'] and cells[edited_ref]['text'] == edit_text
                          and cells[edited_ref]['kind'] == 'number',
                          label + ': the values around the formulas survive')
                    if not edited:
                        check(saved_path.read_bytes() == source.read_bytes(), label + ': the workbook is copied byte for byte')
                        check(saved.get('recalculated') is False and saved.get('uncachedFormulas') == 0,
                              label + ': an unedited copy neither calculates nor invalidates formula results: ' + json.dumps(saved))
                        check(all(cells[ref].get('values') == fresh[ref].get('values') for ref in refs),
                              label + ': the reopened results are Excel\'s saved ones: ' + json.dumps([cells[ref] for ref in refs]))
                    else:
                        check(saved.get('recalculated') is False and saved.get('uncachedFormulas') == len(refs),
                              label + ': an edited formula workbook is saved by streaming: ' + json.dumps(saved))
                        check(all(new_xml[ref].find(S + 'v') is None and 't' not in new_xml[ref].attrib for ref in refs),
                              label + ': no formula keeps a saved result: no #NAME?, no IFERROR or ISERROR fallback, no stale value')
                        check(all(cells[ref]['text'] == '' and cells[ref]['unavailable'] is True and cells[ref].get('error') == REFUSAL for ref in refs),
                              label + ': every reopened formula result is refused for R until Excel recalculates it: ' + json.dumps([cells[ref] for ref in refs]))
                finally: assert request(action='close', id=reopened['id']).get('ok')
        finally: assert request(action='close', id=opened['id']).get('ok')
    if failures: raise AssertionError(f'{len(failures)} ClosedXML function save/reopen checks failed: ' + '; '.join(failures))
    print('PASS: edited Save As never substitutes a result from ClosedXML for Excel\'s; unedited Save As keeps Excel\'s original results', flush=True)


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
