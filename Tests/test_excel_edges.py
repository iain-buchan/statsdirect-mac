"""Edge cases of the streaming Excel reader and writers, through the native workbook driver.

Run with Python + openpyxl: python3 Tests/test_excel_edges.py <workbook-driver> <node>
"""
import datetime, json, os, re, struct, subprocess, sys, tempfile, zipfile
from pathlib import Path
import openpyxl
from openpyxl.utils.datetime import CALENDAR_MAC_1904

ROOT = Path(__file__).resolve().parents[1]
# A time zone away from UTC, with no daylight saving, so that a date-time moved by the Mac's own zone would show.
driver = subprocess.Popen([sys.argv[1], str(ROOT/'FullEngine/publish/StatsDirectEngine.dylib')], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True,
                          env=dict(os.environ, TZ='Asia/Kolkata'))
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
        # 8. Number formats. Each format holds 14:30, 26 hours and minus 1 hour, and its class decides all three cells: a time
        #    of day (a time and no date) is a timespan below one day, a date-time from one day, and a number when negative; an
        #    elapsed time is always a duration; a date is always a date-time, and a number when negative.
        SIGNATURES = {
            'time': [('14:30:00', 'timespan'), ('1900-01-01 02:00:00', 'datetime'), (None, 'number')],
            'date': [('1899-12-31 14:30:00', 'datetime'), ('1900-01-01 02:00:00', 'datetime'), (None, 'number')],
            'elapsed': [('14:30:00', 'timespan'), ('1.02:00:00', 'timespan'), ('-01:00:00', 'timespan')],
            'number': [(None, 'number')] * 3}
        FORMATS = [
            # Built-ins (openpyxl writes these codes as their ids): 18 to 21, 45 and 47 times of day, 46 a duration, 14, 16 and 22 dates.
            ('h:mm AM/PM', 'time'), ('h:mm:ss AM/PM', 'time'), ('h:mm', 'time'), ('h:mm:ss', 'time'),
            ('mm:ss', 'time'), ('[h]:mm:ss', 'elapsed'), ('mmss.0', 'time'),
            ('mm-dd-yy', 'date'), ('d-mmm', 'date'), ('m/d/yy h:mm', 'date'), ('General', 'number'), ('0.00', 'number'),
            # Custom codes: m is minutes after an h or before an s, otherwise the month, and never across a ;. Quoted text,
            # \ escapes, _ and * padding and [...] blocks are not tokens, except [h], [m] and [s].
            ('hh:mm:ss.000', 'time'), ('mm:ss.0', 'time'), ('m:ss', 'time'), ('h:m', 'time'), ('[$-409]h:mm AM/PM;@', 'time'),
            ('[$-F400]h:mm:ss\\ AM/PM', 'time'), ('AM/PM', 'time'), ('"d"h:mm', 'time'), ('\\dh:mm', 'time'), ('*mh:mm', 'time'), ('_mh:mm', 'time'),
            ('[mm]:ss', 'elapsed'), ('[ss].00', 'elapsed'), ('[Red][h]:mm', 'elapsed'),
            ('yyyy-mm-dd', 'date'), ('yyyy-mm-dd hh:mm:ss', 'date'), ('mmmm yyyy', 'date'), ('mm', 'date'), ('mm/dd', 'date'), ('h;mm', 'date'), ('dddd', 'date'),
            ('0.000', 'number'), ('"h:mm"0.0', 'number'), ('0.0\\h', 'number'), ('[Red]0.00;[Blue]-0.00', 'number'), ('#,##0_);[Red]\\(#,##0\\)', 'number'), ('0.00E+00', 'number')]
        # East Asian built-ins, which have no openpyxl code: 32 and 33 are times of day in every locale that has them; 27 is a date.
        EAST_ASIAN = [('0.0000', 32, 'time'), ('0.00000', 33, 'time'), ('0.000000', 27, 'date')]
        formats = folder/'formats.xlsx'; book = openpyxl.Workbook(); ws = book.active; ws.title = 'Formats'
        for r, code in enumerate([code for code, _ in FORMATS] + [code for code, _, _ in EAST_ASIAN], 1):
            ws.cell(r, 1, code)
            for c, value in enumerate([14.5 / 24, 26 / 24, -1 / 24], 2): ws.cell(r, c, value).number_format = code
        book.save(formats)
        def builtins(xml):
            for code, number, _ in EAST_ASIAN:
                custom = re.search(r'<numFmt numFmtId="(\d+)" formatCode="%s"\s*/>' % re.escape(code), xml).group(1)
                xml = xml.replace('<xf numFmtId="%s"' % custom, '<xf numFmtId="%d"' % number)
            return xml
        rewrite(formats, folder/'formats-builtins.xlsx', 'xl/styles.xml', builtins)
        opened = request(action='open', path=str(folder/'formats-builtins.xlsx')); got = cells(opened)
        for r, (code, kind) in enumerate(FORMATS + [(code, kind) for code, _, kind in EAST_ASIAN]):
            for c, (text, k) in enumerate(SIGNATURES[kind], 1):
                cell = got[(c, r)]
                assert cell['kind'] == k and text in (None, cell['text']), (code, kind, c, cell)
        assert request(action='close', id=opened['id'])['ok']
        print(f'PASS: {len(FORMATS) + len(EAST_ASIAN)} number formats are read as times of day, durations, dates or numbers by Excel\'s minutes-or-months rule')
        # 9. Values (RULES 3.9 and 3.2): times of day and durations are rounded to the millisecond; serial 60 is 1900-02-29, also
        #    when a value rounds to it; negative dates and times stay numbers; a value that is not a finite number keeps its text;
        #    a formula whose saved result is empty text is marked savedEmpty, and a formula with no saved result is not.
        VALUES = [  # (value, format, text, kind)
            (14.5 / 24, 'h:mm', '14:30:00', 'timespan'),
            ((14.5 * 3600 + 0.5) / 86400, 'h:mm:ss', '14:30:00.5000000', 'timespan'),
            (26 / 24, '[h]:mm:ss', '1.02:00:00', 'timespan'),
            ((14.5 * 3600 + 0.5) / 86400, '[h]:mm:ss', '14:30:00.5000000', 'timespan'),
            (-1 / 24, '[h]:mm:ss', '-01:00:00', 'timespan'),
            (60, 'yyyy-mm-dd', '1900-02-29 00:00:00', 'datetime'),
            (60.5, 'yyyy-mm-dd hh:mm:ss', '1900-02-29 12:00:00', 'datetime'),
            (59, 'yyyy-mm-dd', '1900-02-28 00:00:00', 'datetime'),
            (61, 'yyyy-mm-dd', '1900-03-01 00:00:00', 'datetime'),
            (60.99999999999, 'yyyy-mm-dd hh:mm:ss', '1900-03-01 00:00:00', 'datetime'),
            (59.99999999999, 'yyyy-mm-dd hh:mm:ss', '1900-02-29 00:00:00', 'datetime'),
            (46347, 'yyyy-mm-dd', '2026-11-21 00:00:00', 'datetime'),
            (-1, 'yyyy-mm-dd', '-1', 'number'),
            (-0.25, 'h:mm', '-0.25', 'number'),
            (-0.25, 'yyyy-mm-dd hh:mm', '-0.25', 'number')]
        NONFINITE = ['NaN', 'INF', '-INF', 'Infinity', '-Infinity', '1e999']   # every other one with a date format
        FORMULA = 'IF(A1>0,"",1)'
        FORMULAS = [  # (cell, text, kind, formula, savedEmpty)
            ('<c r="B{r}" t="str"><f>IF(A1&gt;0,"",1)</f><v></v></c>', '', 'blank', FORMULA, True),
            ('<c r="B{r}" t="str"><f>IF(A1&gt;0,"",1)</f><v/></c>', '', 'blank', FORMULA, True),
            ('<c r="B{r}" t="str"><f>IF(A1&gt;0,"",1)</f></c>', '', 'blank', FORMULA, None),   # no saved result
            ('<c r="B{r}"><f>IF(A1&gt;0,"",1)</f><v/></c>', '', 'blank', FORMULA, None),       # as openpyxl writes every formula
            ('<c r="B{r}" t="str"><f>"x"</f><v>x</v></c>', 'x', 'text', '"x"', None)]
        def make_values(path, nonfinite):
            source = folder/'values-source.xlsx'; book = openpyxl.Workbook(); ws = book.active; ws.title = 'Values'
            for r, (value, code, _, _) in enumerate(VALUES, 1): ws.cell(r, 1, value).number_format = code
            for r in range(1, len(FORMULAS) + 1): ws.cell(r, 2, 2000 + r)
            for r in range(1, len(nonfinite) + 1): ws.cell(r, 3, 1000 + r).number_format = 'yyyy-mm-dd' if r % 2 else 'General'
            book.save(source)
            def special(xml):
                for r, text in enumerate(nonfinite, 1): xml = xml.replace('<v>%d</v>' % (1000 + r), '<v>%s</v>' % text)
                for r, (cell, *_) in enumerate(FORMULAS, 1): xml = re.sub(r'<c r="B%d"[^>]*>.*?</c>' % r, lambda m: cell.format(r=r), xml, count=1)
                return xml
            rewrite(source, path, 'xl/worksheets/sheet1.xml', special)
        def check_values(reply, nonfinite=NONFINITE):
            got = cells(reply)
            for r, (_, code, text, kind) in enumerate(VALUES):
                assert (got[(0, r)]['text'], got[(0, r)]['kind']) == (text, kind), (code, got[(0, r)])
            for r, text in enumerate(nonfinite): assert (got[(2, r)]['text'], got[(2, r)]['kind']) == (text, 'text'), got[(2, r)]
            return got
        values = folder/'values.xlsx'; make_values(values, NONFINITE)
        opened = request(action='open', path=str(values)); got = check_values(opened)
        for r, (_, text, kind, formula, saved) in enumerate(FORMULAS):
            cell = got[(1, r)]
            assert (cell['text'], cell['kind'], cell['formula'], cell.get('savedEmpty')) == (text, kind, formula, saved), cell
        assert opened['formulaCount'] == len(FORMULAS)
        # The typed snapshot holds the same cells, its extras group carries the flag, and the grid's store reads it.
        typed = request(action='open', path=str(values), snapshot=str(folder/'snapshots'))
        snapshot = typed['sheets'][0]['snapshot']
        assert struct.unpack_from('<I', Path(snapshot).read_bytes(), 12)[0] == 1   # the header's extras flag
        decoded = json.loads(subprocess.check_output([sys.argv[2], str(ROOT/'Tests/decode-snapshot.mjs'), snapshot], text=True))[0]['cells']
        key = lambda c: (c['col'], c['row'])
        assert sorted(decoded, key=key) == sorted(opened['sheets'][0]['cells'], key=key)
        script = ("import fs from 'node:fs';import {decodeSnapshot} from './Grid/snapshot.mjs';import {WorkbookStore} from './Grid/workbook.mjs';"
                  "const s=decodeSnapshot(fs.readFileSync(process.argv[1])).sheets[0];const b=new WorkbookStore();"
                  "b.load({name:'values.xlsx',sheets:[{name:s.name,rows:20,columns:3,columnar:s.columns}]});const st=b.sheets[0].store;"
                  "process.stdout.write(JSON.stringify(Array.from({length:%d},(_,r)=>[st.formula(1,r),st.loaded(1,r)?.savedEmpty??null])));" % len(FORMULAS))
        grid_cells = json.loads(subprocess.check_output([sys.argv[2], '--input-type=module', '-e', script, snapshot], text=True, cwd=ROOT))
        assert grid_cells == [[formula, saved] for _, _, _, formula, saved in FORMULAS], grid_cells
        assert request(action='close', id=typed['id'])['ok']
        print('PASS: times of day, durations, serial 60, negative and non-finite values and saved empty formula results load as RULES 3.9 needs, in the JSON reply, the snapshot and the grid')
        # 10. Save and reopen through the new-workbook writer, the ClosedXML patch and the streaming patch: every value comes back
        #     with its text and kind, also when moved into cells of the General style (each path then adds a date or duration style).
        #     Text a user may type into a date or duration cell is saved as Excel would hold it: 26:00:00 is 26 hours, not the 26
        #     days TimeSpan.Parse reads; R's UTC date-times keep their clock time whatever the time zone; text that is no date or
        #     duration is saved as text rather than failing the save. ClosedXML cannot load a workbook holding NaN, 1e999 or
        #     -Infinity (nor Infinity in a date cell), so that one is saved by the streaming patch instead of failing.
        TYPED = [  # (text typed into a cell of that kind, text and kind after reopening)
            ('26:00:00', 'timespan', '1.02:00:00', 'timespan'),
            ('-1.02:00:00.25', 'timespan', '-1.02:00:00.2500000', 'timespan'),
            ('1900-02-29 06:00:00', 'datetime', '1900-02-29 06:00:00', 'datetime'),
            ('1900-02-29', 'datetime', '1900-02-29 00:00:00', 'datetime'),
            ('2026-07-01T14:30:00.123456Z', 'datetime', '2026-07-01 14:30:00.123', 'datetime'),
            ('2026-02-30', 'datetime', '2026-02-30', 'text'),
            ('25:61:00', 'timespan', '25:61:00', 'text')]
        typed_cells = [{'col': 8, 'row': r, 'text': text, 'kind': kind} for r, (text, kind, _, _) in enumerate(TYPED)]
        def edits_of(reply):
            value_cells = [c for c in reply['sheets'][0]['cells'] if not c['formula']]
            moved = [dict(c, col=c['col'] + 4) for c in value_cells]
            return moved, [{'name': 'Values', 'cells': value_cells + moved + typed_cells}]
        def check_round_trip(path, label, moved, formulas, nonfinite=NONFINITE):
            back = request(action='open', path=str(path)); got = check_values(back, nonfinite)
            for c in moved: assert (got[(c['col'], c['row'])]['text'], got[(c['col'], c['row'])]['kind']) == (c['text'], c['kind']), (label, c, got[(c['col'], c['row'])])
            for r, (_, _, text, kind) in enumerate(TYPED): assert (got[(8, r)]['text'], got[(8, r)]['kind']) == (text, kind), (label, TYPED[r], got[(8, r)])
            for r, expected in enumerate(formulas):
                cell = got[(1, r)]
                assert (cell['text'], cell['kind'], cell['formula'], cell.get('savedEmpty')) == expected, (label, cell)
            assert request(action='close', id=back['id'])['ok']
        moved, edits = edits_of(opened)
        new = folder/'values-new.xlsx'
        result = request(action='save', path=str(new), sheets=edits)
        assert result.get('ok'), result
        check_round_trip(new, 'new workbook', moved, [])   # a new workbook holds values only
        # The streaming patch drops every saved formula result for Excel to recalculate, also when it stands in for ClosedXML.
        uncached = [('', 'blank', formula, None) for _, _, _, formula, _ in FORMULAS]
        for stream in (True, False):
            out = folder/f'values-patched-{stream}.xlsx'
            result = request(action='save', id=opened['id'], path=str(out), stream=stream, sheets=edits)
            assert result.get('ok') and result['recalculated'] is False and result['uncachedFormulas'] == len(FORMULAS), (stream, result)
            check_round_trip(out, f'streaming patch, stream={stream}', moved, uncached)
        assert request(action='close', id=opened['id'])['ok']
        # ClosedXML recalculates every formula, so =IF(A1>0,"",1) then has a saved empty result.
        READABLE = ['INF', '-INF']   # ClosedXML 0.105 loads these, which .NET does not read as numbers, in any style
        readable = folder/'values-readable.xlsx'; make_values(readable, READABLE)
        opened = request(action='open', path=str(readable)); check_values(opened, READABLE)
        moved, edits = edits_of(opened)
        out = folder/'values-closedxml.xlsx'
        result = request(action='save', id=opened['id'], path=str(out), sheets=edits)
        assert result.get('ok') and result['recalculated'] is True and result['uncachedFormulas'] == 0, result
        recalculated = [('', 'blank', formula, True) if formula == FORMULA else (text, kind, formula, None) for _, text, kind, formula, _ in FORMULAS]
        check_round_trip(out, 'ClosedXML patch', moved, recalculated, READABLE)
        assert request(action='close', id=opened['id'])['ok']
        print('PASS: dates (1900-02-29 included), times of day and durations keep their text and kind through all three save paths; typed 26:00:00, R date-times and impossible dates save correctly; a workbook ClosedXML cannot load is saved by streaming')
        # 11. The 1904 date system: a time of day is still a time, serial 0 is 1904-01-01, 60 is an ordinary day, a negative date
        #     stays a number, and 1900-02-29 is no date at all. A workbook without saved empty results has no extras group.
        MAC = [(14.5 / 24, 'h:mm', '14:30:00', 'timespan'), (0, 'yyyy-mm-dd', '1904-01-01 00:00:00', 'datetime'),
               (0.5, 'yyyy-mm-dd hh:mm', '1904-01-01 12:00:00', 'datetime'), (60, 'yyyy-mm-dd', '1904-03-01 00:00:00', 'datetime'),
               (-1, 'yyyy-mm-dd', '-1', 'number'), (26 / 24, '[h]:mm:ss', '1.02:00:00', 'timespan')]
        mac = folder/'times1904.xlsx'; book = openpyxl.Workbook(); book.epoch = CALENDAR_MAC_1904; ws = book.active; ws.title = 'Mac'
        for r, (value, code, _, _) in enumerate(MAC, 1): ws.cell(r, 1, value).number_format = code
        book.save(mac)
        opened = request(action='open', path=str(mac), snapshot=str(folder/'snapshots'))
        assert struct.unpack_from('<I', Path(opened['sheets'][0]['snapshot']).read_bytes(), 12)[0] == 0
        decoded = json.loads(subprocess.check_output([sys.argv[2], str(ROOT/'Tests/decode-snapshot.mjs'), opened['sheets'][0]['snapshot']], text=True))[0]['cells']
        assert [(c['text'], c['kind']) for c in sorted(decoded, key=lambda c: c['row'])] == [(text, kind) for _, _, text, kind in MAC], decoded
        mac_cells = [{'col': 0, 'row': r, 'text': text, 'kind': kind} for r, (_, _, text, kind) in enumerate(MAC)]
        mac_typed = [{'col': 1, 'row': 0, 'text': '1900-02-29', 'kind': 'datetime'}, {'col': 1, 'row': 1, 'text': '1904-01-01 06:00:00', 'kind': 'datetime'}]
        # A new workbook uses the 1900 system, where 1900-02-29 is Excel's day 60.
        for n, (label, kwargs, leap_day) in enumerate([('new workbook', {}, ('1900-02-29 00:00:00', 'datetime')),
                                                       ('ClosedXML patch', {'id': opened['id']}, ('1900-02-29', 'text')),
                                                       ('streaming patch', {'id': opened['id'], 'stream': True}, ('1900-02-29', 'text'))]):
            out = folder/f'times1904-{n}.xlsx'
            result = request(action='save', path=str(out), sheets=[{'name': 'Mac', 'cells': mac_cells + [dict(c, col=c['col'] + 2) for c in mac_cells] + mac_typed}], **kwargs)
            assert result.get('ok'), (label, result)
            back = request(action='open', path=str(out)); got = cells(back)
            for c in mac_cells:
                for col in (0, 2): assert (got[(col, c['row'])]['text'], got[(col, c['row'])]['kind']) == (c['text'], c['kind']), (label, col, c, got[(col, c['row'])])
            assert (got[(1, 0)]['text'], got[(1, 0)]['kind']) == leap_day, (label, got[(1, 0)])
            assert (got[(1, 1)]['text'], got[(1, 1)]['kind']) == ('1904-01-01 06:00:00', 'datetime'), (label, got[(1, 1)])
            assert request(action='close', id=back['id'])['ok']
        assert request(action='close', id=opened['id'])['ok']
        print('PASS: 1904-system times of day, dates from 1904-01-01 and negative dates load and survive all three save paths; 1900-02-29 is no date there')
finally:
    driver.stdin.close(); driver.wait(timeout=15)
