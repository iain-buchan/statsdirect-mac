"""Save As/reopen regression for cached array/spill and what-if dependents.

Called by test_excel_edges.py in CI. Focused usage (optional retained work folder):
  python3 Tests/excel_formula_region_save.py <workbook-driver> <node> [work-folder]

Every source is real OOXML. The production loader opens it, the actual grid
model edits E1 or B4, exports its normal typed edit snapshot, and the production
workbook bridge saves/reopens both the small default and forced-streaming path.
Only the cached dependent (without its own <f>) is selected for R. The corrected
conservative policy never asks ClosedXML to recalculate array/spill/data-table
files; an ordinary scalar-only control still uses ClosedXML successfully.
"""
import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
import zipfile
import openpyxl
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side

ROOT = Path(__file__).resolve().parents[1]
MAIN = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'
S = '{' + MAIN + '}'
PART = 'xl/worksheets/sheet1.xml'
REFUSAL = 'Recalculate and save this workbook in Excel, then reopen it before using formula cells in R.'
ET.register_namespace('', MAIN)


def fixture(path, variant):
    seed = path.with_suffix('.seed.xlsx')
    book = openpyxl.Workbook()
    ws = book.active
    ws.title = 'Data'
    if variant == 'what-if':
        ws['B3'] = 1; ws['B4'] = 2; ws['C2'] = 3
        ws['C3'] = 2; ws['C4'] = 3; ws['E1'] = 2
    else:
        ws['A1'] = 2; ws['B1'] = 3; ws['E1'] = 2; ws['F1'] = 4
    # Unrelated values, styles and structural metadata must survive either path.
    ws['G5'] = 123.45; ws['G5'].number_format = '0.00'
    ws['H2'] = 'Keep α & literal <text>'
    ws['H2'].font = Font(name='Calibri', bold=True, color='FF123456')
    ws['H2'].fill = PatternFill(fill_type='solid', fgColor='FFEEDDCC')
    ws['H2'].alignment = Alignment(horizontal='left', wrap_text=True)
    ws['H2'].border = Border(bottom=Side(style='thin', color='FF667788'))
    ws.column_dimensions['H'].width = 23; ws.row_dimensions[2].height = 27
    ws.merge_cells('H4:I4'); ws['H4'] = 'Merged value stays'
    book.save(seed)
    with zipfile.ZipFile(seed) as source, zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as target:
        for item in source.infolist():
            data = source.read(item.filename)
            if item.filename == PART:
                sheet = ET.fromstring(data)
                def cell(ref): return sheet.find(f'.//{S}c[@r="{ref}"]')
                if variant != 'scalar':
                    attrs = {'t': 'dataTable' if variant == 'what-if' else 'array',
                             'ref': 'C3:C4' if variant == 'what-if' else 'A1:B2' if variant == 'spill' else 'A1:B1'}
                    if variant == 'what-if': attrs['r1'] = 'E1'
                    anchor = ET.Element(S + 'f', attrs)
                    anchor.text = 'E1+{0,1}' if variant == 'array' else '_xlfn.SEQUENCE(2,2,E1)' if variant == 'spill' else None
                    cell('C3' if variant == 'what-if' else 'A1').insert(0, anchor)
                scalar = ET.Element(S + 'f')
                scalar.text = 'E1+1' if variant == 'what-if' else 'E1*2'
                cell('C2' if variant == 'what-if' else 'F1').insert(0, scalar)
                data = ET.tostring(sheet, encoding='utf-8')
            target.writestr(item, data)
    seed.unlink()


def xml_cells(path):
    with zipfile.ZipFile(path) as archive: sheet = ET.fromstring(archive.read(PART))
    return {cell.attrib['r']: cell for cell in sheet.iter(S + 'c')}


def formula(cell):
    node = cell.find(S + 'f') if cell is not None else None
    return None if node is None else (node.attrib, node.text or '')


def unrelated_preserved(before, after):
    original = openpyxl.load_workbook(before)['Data']
    saved = openpyxl.load_workbook(after)['Data']
    for address in ('G5', 'H2', 'H4'):
        a, b = original[address], saved[address]
        if a.value != b.value or a.number_format != b.number_format: return False
        for feature in ('font', 'fill', 'border', 'alignment'):
            if copy.copy(getattr(a, feature)) != copy.copy(getattr(b, feature)): return False
    return (set(map(str, original.merged_cells.ranges)) == set(map(str, saved.merged_cells.ranges))
            and original.column_dimensions['H'].width == saved.column_dimensions['H'].width
            and original.row_dimensions[2].height == saved.row_dimensions[2].height)


def check_formula_region_saves(request, node, folder):
    folder = Path(folder) / 'formula-region-save'
    folder.mkdir(parents=True, exist_ok=True)
    snapshots = folder / 'snapshots'
    snapshots.mkdir(exist_ok=True)
    failures, results = [], []
    def check(ok, label):
        print(('PASS: ' if ok else 'FAIL: ') + label, flush=True)
        if not ok: failures.append(label)
    def grid(reply, variant, label, edit=False):
        payload = folder / (label + '.json')
        payload.write_text(json.dumps({'reply': reply, 'variant': variant}), encoding='utf-8')
        edits = folder / (variant + '.edits.sdcol')
        command = [node, str(ROOT / 'Tests/worksheet-r-save-reopen.mjs'), str(payload)]
        if edit: command.append(str(edits))
        return json.loads(subprocess.check_output(command, text=True, cwd=ROOT)), edits
    for variant in ('array', 'spill', 'what-if', 'scalar'):
        source = folder / (variant + '-source.xlsx')
        fixture(source, variant)
        original_bytes = source.read_bytes()
        opened = request(action='open', path=str(source), snapshot=str(snapshots))
        assert 'error' not in opened, opened
        try:
            before, edits = grid(opened, variant, variant, edit=True)
            check(before['before'].get('values') == ['4' if variant == 'scalar' else '3'], variant + ' fresh dependent-only R selection reads the actual saved result')
            check(before['after'].get('error') == REFUSAL and before['after']['input'] == '10', variant + ' real grid input edit refuses the stale dependent before saving')
            for stream in ((False,) if variant == 'scalar' else (False, True)):
                label = variant + ('-stream' if stream else '-default')
                saved_path = folder / (label + '.xlsx')
                saved = request(action='save', path=str(saved_path), id=opened['id'], stream=stream, snapshot=str(edits))
                if not saved.get('ok'):
                    check(False, label + ': production save succeeded: ' + str(saved)); continue
                reopened = request(action='open', path=str(saved_path), snapshot=str(snapshots))
                assert 'error' not in reopened, reopened
                try:
                    observed, _ = grid(reopened, variant, label + '-reopened')
                    actual = observed['before']
                    old_xml, new_xml = xml_cells(source), xml_cells(saved_path)
                    input_ref = 'B4' if variant == 'what-if' else 'E1'
                    check(actual['input'] == '10' and new_xml[input_ref].findtext(S + 'v') == '10', label + ': edited ' + input_ref + ' survives Save As/reopen')
                    check(unrelated_preserved(source, saved_path), label + ': unrelated values, cell styles, merged area and dimensions survive')
                    if variant == 'scalar':
                        check(saved.get('recalculated') is True and actual.get('values') == ['20'] and actual.get('unavailable') is False,
                              label + ': the ordinary small scalar-only workbook retains ClosedXML recalculation')
                        check(formula(new_xml.get('F1')) == formula(old_xml.get('F1')), label + ': scalar expression is preserved')
                    else:
                        anchor_ref = 'C3' if variant == 'what-if' else 'A1'
                        child_ref = 'C4' if variant == 'what-if' else 'B1'
                        check(formula(new_xml.get(anchor_ref)) == formula(old_xml.get(anchor_ref)), label + ': actual formula expression and t/ref/input attributes are preserved')
                        check(saved.get('recalculated') is False, label + ': formula regions take the conservative non-recalculating save route')
                        child = new_xml.get(child_ref)
                        check(child is None or child.find(S + 'v') is None, label + ': covered child cache is removed from actual OOXML')
                        check(actual.get('unavailable') is True and actual.get('error') == REFUSAL,
                              label + ': reopened child-only R selection refuses instead of importing stale values or a synthetic #NAME?')
                    results.append({'case': label, 'save': saved, 'beforeEdit': before['before'], 'afterEdit': before['after'], 'reopened': actual})
                finally: assert request(action='close', id=reopened['id']).get('ok')
            if variant in ('array', 'spill'):
                # Cached-only B1 and absent B2 are formula results despite having
                # no own <f>. A rejected Save As cannot replace an existing file.
                target_ref = 'B1' if variant == 'array' else 'B2'
                target_row = 0 if variant == 'array' else 1
                sentinel = folder / (variant + '-must-stay.xlsx')
                sentinel_bytes = b'Existing destination must remain unchanged\n'
                sentinel.write_bytes(sentinel_bytes)
                rejected = request(action='save', path=str(sentinel), id=opened['id'], stream=True,
                                   sheets=[{'name': 'Data', 'cells': [{'col': 1, 'row': target_row, 'text': '99', 'kind': 'number'}]}])
                check('formula' in rejected.get('error', '').lower() and sentinel.read_bytes() == sentinel_bytes,
                      variant + ': editing covered ' + target_ref + ' is refused atomically without replacing an existing destination')
            check(source.read_bytes() == original_bytes, variant + ': Save As never modifies the source workbook')
        finally: assert request(action='close', id=opened['id']).get('ok')
    (folder / 'results.json').write_text(json.dumps({'results': results, 'failures': failures}, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    if failures: raise AssertionError(f'{len(failures)} formula-region save/reopen checks failed: ' + '; '.join(failures))
    print('PASS: formula-region Save As/reopen and atomic dependent-edit regressions completed', flush=True)


def main():
    if len(sys.argv) not in (3, 4): raise SystemExit(__doc__)
    driver = subprocess.Popen([sys.argv[1], str(ROOT / 'FullEngine/publish/StatsDirectEngine.dylib')],
                              stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, env=dict(os.environ, TZ='Asia/Kolkata'))
    def request(**payload):
        driver.stdin.write(json.dumps(payload) + '\n'); driver.stdin.flush()
        return json.loads(driver.stdout.readline())
    try:
        if len(sys.argv) == 4: check_formula_region_saves(request, sys.argv[2], Path(sys.argv[3]))
        else:
            with tempfile.TemporaryDirectory(prefix='formula-region-save-') as folder: check_formula_region_saves(request, sys.argv[2], Path(folder))
    finally:
        driver.stdin.close(); driver.wait(timeout=15)

if __name__ == '__main__': main()
