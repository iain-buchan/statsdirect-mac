"""Edge cases of the streaming Excel reader and writers, through the native workbook driver.

Run with Python + openpyxl: python3 Tests/test_excel_edges.py <workbook-driver> <node>
"""
import datetime, json, re, subprocess, sys, tempfile, zipfile
from pathlib import Path
import openpyxl
from openpyxl.utils.datetime import CALENDAR_MAC_1904

ROOT = Path(__file__).resolve().parents[1]
driver = subprocess.Popen([sys.argv[1], str(ROOT/'FullEngine/publish/StatsDirectEngine.dylib')], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
def request(**payload):
    driver.stdin.write(json.dumps(payload) + '\n'); driver.stdin.flush()
    return json.loads(driver.stdout.readline())
def cells(reply, sheet=0):
    return {(c['col'], c['row']): c for c in reply['sheets'][sheet]['cells']}
def rewrite(source, target, part, transform):
    with zipfile.ZipFile(source) as src, zipfile.ZipFile(target, 'w', zipfile.ZIP_DEFLATED) as dst:
        for item in src.infolist():
            data = src.read(item.filename)
            if item.filename == part: data = transform(data.decode()).encode()
            dst.writestr(item, data)
def grid(path, rows, sheet='Data', epoch=None):
    book = openpyxl.Workbook(); ws = book.active; ws.title = sheet
    if epoch: book.epoch = epoch
    for row in rows: ws.append(row)
    book.save(path); return book
try:
    with tempfile.TemporaryDirectory() as folder:
        folder = Path(folder)
        # 1. A worksheet pretty-printed by another writer (StatsDirect's own ClosedXML patch path indents) and
        #    a dimension element that is not self-closing: the streaming patch keeps every cell.
        plain = folder/'plain.xlsx'; grid(plain, [[11, 12, 13], [21, 22, 23], [31, 32, 33]])
        indented = folder/'indented.xlsx'
        def indent(xml):
            xml = re.sub(r'<dimension ref="([^"]+)"\s*/>', r'<dimension ref="\1"></dimension>', xml)
            xml = xml.replace('<row ', '\n  <row ').replace('<c ', '\n    <c ').replace('</row>', '\n  </row>').replace('</sheetData>', '\n</sheetData>')
            return xml
        rewrite(plain, indented, 'xl/worksheets/sheet1.xml', indent)
        opened = request(action='open', path=str(indented)); assert 'error' not in opened, opened
        assert len(opened['sheets'][0]['cells']) == 9
        saved = folder/'indented-patched.xlsx'
        result = request(action='save', id=opened['id'], path=str(saved), stream=True, sheets=[{'name': 'Data', 'cells': [{'col': 1, 'row': 1, 'text': '77', 'kind': 'number'}, {'col': 3, 'row': 0, 'text': 'new', 'kind': 'text'}]}])
        assert result.get('ok'), result
        ws = openpyxl.load_workbook(saved)['Data']
        assert [[c.value for c in r] for r in ws.iter_rows(min_row=1, max_row=3, max_col=4)] == [[11, 12, 13, 'new'], [21, 77, 23, None], [31, 32, 33, None]]
        assert ws.dimensions == 'A1:D3'
        assert request(action='close', id=opened['id'])['ok']
        # A row with trailing extLst children and cells without r attributes merge correctly too.
        odd = folder/'odd.xlsx'
        def oddify(xml):
            xml = xml.replace('<c r="B2"', '<c').replace('<c r="C2"', '<c')
            return xml.replace('</row>', '<extLst/></row>', 1)
        rewrite(plain, odd, 'xl/worksheets/sheet1.xml', oddify)
        opened = request(action='open', path=str(odd)); assert [opened['sheets'][0]['cells'][i]['text'] for i in range(9)] and len(opened['sheets'][0]['cells']) == 9
        saved = folder/'odd-patched.xlsx'
        result = request(action='save', id=opened['id'], path=str(saved), stream=True, sheets=[{'name': 'Data', 'cells': [{'col': 0, 'row': 3, 'text': '41', 'kind': 'number'}, {'col': 2, 'row': 1, 'text': '', 'kind': 'blank'}]}])
        assert result.get('ok'), result
        ws = openpyxl.load_workbook(saved)['Data']
        assert [[c.value for c in r] for r in ws.iter_rows(min_row=1, max_row=4, max_col=3)] == [[11, 12, 13], [21, 22, None], [31, 32, 33], [41, None, None]]
        assert request(action='close', id=opened['id'])['ok']
        print('PASS: streaming patch keeps every cell of indented, extLst-bearing and implicitly addressed worksheets')
        # 2. The 1904 date system is honoured by both patch paths.
        mac = folder/'mac1904.xlsx'; grid(mac, [['when', 1]], epoch=CALENDAR_MAC_1904)
        opened = request(action='open', path=str(mac))
        for stream in (False, True):
            out = folder/f'mac1904-{stream}.xlsx'
            result = request(action='save', id=opened['id'], path=str(out), stream=stream, sheets=[{'name': 'Data', 'cells': [{'col': 0, 'row': 1, 'text': '2024-02-29 12:34:56', 'kind': 'datetime'}]}])
            assert result.get('ok'), result
            value = openpyxl.load_workbook(out)['Data']['A2'].value
            assert value == datetime.datetime(2024, 2, 29, 12, 34, 56), (stream, value)
            back = request(action='open', path=str(out)); assert cells(back)[(0, 1)]['text'] == '2024-02-29 12:34:56', (stream, back)
            assert request(action='close', id=back['id'])['ok']
        assert request(action='close', id=opened['id'])['ok']
        print('PASS: date edits in a 1904-system workbook keep their calendar date through both patch paths')
        # 3. Chart sheets are not worksheets.
        charted = folder/'charted.xlsx'; book = grid(charted, [[1, 2], [3, 4]]); book.create_chartsheet('Chart1'); book.create_sheet('Second'); book.save(charted)
        opened = request(action='open', path=str(charted))
        assert [s['name'] for s in opened['sheets']] == ['Data', 'Second'], opened['sheets']
        out = folder/'charted-out.xlsx'
        for stream in (False, True):
            result = request(action='save', id=opened['id'], path=str(out), stream=stream, sheets=[{'name': 'Second', 'cells': [{'col': 0, 'row': 0, 'text': 'x', 'kind': 'text'}]}])
            assert result.get('ok'), (stream, result)
            # openpyxl cannot read back an empty chart sheet (even its own), so inspect the package directly.
            assert re.findall(r'<sheet [^>]*name="([^"]+)"', zipfile.ZipFile(out).read('xl/workbook.xml').decode()) == ['Data', 'Chart1', 'Second']
            check = request(action='open', path=str(out)); assert [s['name'] for s in check['sheets']] == ['Data', 'Second'] and cells(check, 1)[(0, 0)]['text'] == 'x', (stream, check)
            assert request(action='close', id=check['id'])['ok']
        assert request(action='close', id=opened['id'])['ok']
        print('PASS: chart sheets are skipped on open and preserved on save')
        # 4. Part names with spaces (percent-encoded relationship targets) and case differences resolve.
        spaced = folder/'spaced.xlsx'
        with zipfile.ZipFile(plain) as src, zipfile.ZipFile(spaced, 'w', zipfile.ZIP_DEFLATED) as dst:
            for item in src.infolist():
                data = src.read(item.filename); name = item.filename
                if name == 'xl/worksheets/sheet1.xml': name = 'xl/worksheets/Sheet 1.xml'
                if name == 'xl/_rels/workbook.xml.rels': data = data.replace(b'worksheets/sheet1.xml', b'worksheets/Sheet%201.xml')
                if name == '[Content_Types].xml': data = data.replace(b'/xl/worksheets/sheet1.xml', b'/xl/worksheets/Sheet%201.xml')
                dst.writestr(name, data)
        opened = request(action='open', path=str(spaced)); assert 'error' not in opened and len(opened['sheets'][0]['cells']) == 9, opened
        result = request(action='save', id=opened['id'], path=str(folder/'spaced-out.xlsx'), stream=True, sheets=[{'name': 'Data', 'cells': [{'col': 0, 'row': 0, 'text': '1', 'kind': 'number'}]}])
        assert result.get('ok'), result
        # openpyxl does not resolve percent-encoded part names, so the engine verifies its own output.
        check = request(action='open', path=str(folder/'spaced-out.xlsx')); assert cells(check)[(0, 0)]['text'] == '1' and len(check['sheets'][0]['cells']) == 9, check
        assert request(action='close', id=check['id'])['ok'] and request(action='close', id=opened['id'])['ok']
        print('PASS: percent-encoded and differently cased part names resolve on open and streaming save')
        # 5. Shared formulas shift whole-column and whole-row ranges for dependants.
        shared = folder/'shared.xlsx'; grid(shared, [[1, 2], [3, 4], [5, 6]])
        def share(xml):
            return xml.replace('</row></sheetData>', '</row><row r="4"><c r="A4"><f t="shared" ref="A4:B4" si="0">SUM(A:A)+SUM($A1:A2)+SUM(1:2)</f><v>0</v></c><c r="B4"><f t="shared" si="0"/><v>0</v></c></row></sheetData>')
        rewrite(shared, folder/'shared2.xlsx', 'xl/worksheets/sheet1.xml', share)
        opened = request(action='open', path=str(folder/'shared2.xlsx'))
        got = cells(opened)
        assert got[(0, 3)]['formula'] == 'SUM(A:A)+SUM($A1:A2)+SUM(1:2)' and got[(1, 3)]['formula'] == 'SUM(B:B)+SUM($A1:B2)+SUM(1:2)', (got[(0, 3)], got[(1, 3)])
        assert opened['formulaCount'] == 2
        assert request(action='close', id=opened['id'])['ok']
        print('PASS: shared-formula dependants shift cell, column and row references')
        # 6. Text Excel cannot store verbatim: control characters round-trip through Excel's _xHHHH_ escapes;
        #    duplicate worksheet names in a new workbook are made unique.
        typed = folder/'control.xlsx'
        result = request(action='save', path=str(typed), sheets=[
            {'name': 'Results', 'cells': [{'col': 0, 'row': 0, 'text': 'a\x01b_x0041_', 'kind': 'text'}]},
            {'name': 'results', 'cells': []}, {'name': 'a/b', 'cells': []}, {'name': 'a\\b', 'cells': []}])
        assert result.get('ok'), result
        assert openpyxl.load_workbook(typed).sheetnames == ['Results', 'results (2)', 'ab', 'ab (2)']
        assert openpyxl.load_workbook(typed)['Results']['A1'].value == 'a_x0001_b_x005F_x0041_'
        back = request(action='open', path=str(typed)); assert cells(back)[(0, 0)]['text'] == 'a\x01b_x0041_', back
        assert request(action='close', id=back['id'])['ok']
        encoded = folder/'encoded.xlsx'; grid(encoded, [['line_x000D_break']])
        back = request(action='open', path=str(encoded)); assert cells(back)[(0, 0)]['text'] == 'line\rbreak'
        assert request(action='close', id=back['id'])['ok']
        print('PASS: control characters, literal escapes and duplicate sheet names survive a new-workbook save')
        # 7. A workbook whose later sheet part is missing leaves no snapshot files behind.
        broken = folder/'broken.xlsx'; book = grid(broken, [[1]]); book.create_sheet('Second'); book.save(broken)
        with zipfile.ZipFile(broken) as src, zipfile.ZipFile(folder/'broken2.xlsx', 'w') as dst:
            for item in src.infolist():
                if item.filename != 'xl/worksheets/sheet2.xml': dst.writestr(item, src.read(item.filename))
        snaps = folder/'snaps'
        reply = request(action='open', path=str(folder/'broken2.xlsx'), snapshot=str(snaps))
        assert 'error' in reply and 'missing' in reply['error'], reply
        assert not list(snaps.glob('*.sdcol'))
        print('PASS: a failed open leaves no snapshot files')
finally:
    driver.stdin.close(); driver.wait(timeout=15)
