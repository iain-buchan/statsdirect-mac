"""Columns inserted into an opened workbook by a write-back are moved in the saved file: cells with their
styles, column widths and every formula in the workbook re-referenced, or the save is refused where
the prototype cannot move a feature. Run with the workbook driver and openpyxl."""
import json, subprocess, sys, tempfile
from pathlib import Path
import openpyxl
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'Tests'))

driver = subprocess.Popen([sys.argv[1], str(ROOT / 'FullEngine/publish/StatsDirectEngine.dylib')], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
def request(**payload):
    driver.stdin.write(json.dumps(payload) + '\n'); driver.stdin.flush()
    return json.loads(driver.stdout.readline())
def cell(col, row, text, kind='number'): return {'col': col, 'row': row, 'text': str(text), 'kind': kind}

try:
    with tempfile.TemporaryDirectory() as folder:
        source = Path(folder) / 'source.xlsx'
        wb = openpyxl.Workbook(); ws = wb.active; ws.title = 'Data'
        ws['A1'] = 'double'; ws['B1'] = 'y'; ws['C1'] = 'z'
        for r, (y, z) in enumerate([(0.5, 7), (0.25, 8), (0.125, 9)], start=2):
            ws.cell(r, 1, f'=B{r}*2'); c = ws.cell(r, 2, y); c.number_format = '0.00%'; ws.cell(r, 3, z)
        ws.column_dimensions['B'].width = 30
        other = wb.create_sheet('Other'); other['A1'] = '=Data!B2+1'
        wb.save(source)
        opened = request(action='open', path=str(source)); assert 'error' not in opened, opened
        # The grid inserted one column before B (a log transform written after the selected column A):
        # B holds the output, y moved to C with its format, z to D; A's formulas and Other's formula still point at y.
        moved = [cell(2, r, y) for r, y in enumerate([0.5, 0.25, 0.125], start=1)] + [cell(3, r, z) for r, z in enumerate([7, 8, 9], start=1)] + [cell(2, 0, 'y', 'text'), cell(3, 0, 'z', 'text')]
        output = [cell(1, 0, 'log', 'text')] + [cell(1, r, v) for r, v in enumerate([10, 20, 30], start=1)]
        saved = Path(folder) / 'inserted.xlsx'
        result = request(action='save', id=opened['id'], path=str(saved), sheets=[{'name': 'Data', 'cells': output + moved}], inserts=[{'name': 'Data', 'inserts': [{'col': 1, 'count': 1}]}])
        assert result.get('ok'), result
        book = openpyxl.load_workbook(saved); data = book['Data']
        assert [data.cell(1, c).value for c in range(1, 5)] == ['double', 'log', 'y', 'z'], [data.cell(1, c).value for c in range(1, 5)]
        assert [data.cell(r, 2).value for r in (2, 3, 4)] == [10, 20, 30]
        assert [data.cell(r, 3).value for r in (2, 3, 4)] == [0.5, 0.25, 0.125] and data['C2'].number_format == '0.00%', (data['C2'].value, data['C2'].number_format)
        assert [data.cell(r, 4).value for r in (2, 3, 4)] == [7, 8, 9]
        assert data['A2'].value == '=C2*2' and data['A4'].value == '=C4*2', (data['A2'].value, data['A4'].value)   # re-referenced past the inserted column
        assert book['Other']['A1'].value == '=Data!C2+1', book['Other']['A1'].value
        assert abs(data.column_dimensions['C'].width - 30) < 0.01, data.column_dimensions['C'].width   # the width travelled with y
        assert data.max_column == 4
        print('PASS: an inserted column moves the file\'s cells with their styles and widths and re-references every formula in the workbook')

        # Two insertions in sequence, the second in the coordinates after the first.
        twice = Path(folder) / 'twice.xlsx'
        result = request(action='save', id=opened['id'], path=str(twice), sheets=[{'name': 'Data', 'cells': [cell(1, 0, 'first', 'text'), cell(3, 0, 'second', 'text'), cell(2, 0, 'y', 'text'), cell(4, 0, 'z', 'text')] + [cell(2, r, y) for r, y in enumerate([0.5, 0.25, 0.125], start=1)] + [cell(4, r, z) for r, z in enumerate([7, 8, 9], start=1)]}],
                         inserts=[{'name': 'Data', 'inserts': [{'col': 1, 'count': 1}, {'col': 3, 'count': 1}]}])
        assert result.get('ok'), result
        data = openpyxl.load_workbook(twice)['Data']
        assert [data.cell(1, c).value for c in range(1, 6)] == ['double', 'first', 'y', 'second', 'z'] and data['A2'].value == '=C2*2' and data['E3'].value == 8, [data.cell(1, c).value for c in range(1, 6)]
        print('PASS: successive insertions are applied in order')

        # Features the prototype cannot move are refused, not corrupted.
        merged = Path(folder) / 'merged.xlsx'; wb2 = openpyxl.Workbook(); ws2 = wb2.active; ws2.title = 'Data'; ws2['A1'] = 1; ws2['B1'] = 2; ws2.merge_cells('A3:B3'); wb2.save(merged)
        opened2 = request(action='open', path=str(merged))
        refused = request(action='save', id=opened2['id'], path=str(Path(folder) / 'refused.xlsx'), sheets=[{'name': 'Data', 'cells': [cell(1, 0, 9)]}], inserts=[{'name': 'Data', 'inserts': [{'col': 1, 'count': 1}]}])
        assert 'mergeCells' in refused.get('error', ''), refused
        shared = request(action='open', path=str(ROOT / 'Content/Examples/test.xlsx'))   # its formulas are shared formulas
        refused = request(action='save', id=shared['id'], path=str(Path(folder) / 'refused2.xlsx'), sheets=[{'name': 'Parametric', 'cells': [cell(1, 0, 'x', 'text')]}], inserts=[{'name': 'Parametric', 'inserts': [{'col': 1, 'count': 1}]}])
        assert 'shared or array formulas' in refused.get('error', ''), refused
        refused = request(action='save', id=opened['id'], path=str(Path(folder) / 'refused3.xlsx'), stream=True, sheets=[{'name': 'Data', 'cells': [cell(1, 0, 9)]}], inserts=[{'name': 'Data', 'inserts': [{'col': 1, 'count': 1}]}])
        assert 'streaming' in refused.get('error', ''), refused
        print('PASS: insertions are refused for merged cells, shared formulas and streaming saves')
finally:
    driver.stdin.close(); driver.wait()
