"""Writes Tests/Fixtures/Excel/formula-column.xlsx: a worksheet of 2,600 rows whose column y holds formulas (=A2*2 ...) with their
results saved, as Excel saves them, and a worksheet extension list (Excel for Mac's page layout view, which every workbook Excel for
Mac saves carries), which routes this program's save of the workbook through its streaming patcher. The streaming patcher keeps the
formulas and drops their saved results, so Excel recalculates: a run on x and y, the file saved, the grid closed and Continue in R
is then the case of a workbook whose formula cells have no saved results (Tests/report-export-driver.swift runRecords).

    python3 Tests/make-formula-workbook.py [path]
"""
import math, sys, zipfile
from pathlib import Path
ROWS = 2600
out = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parent / 'Fixtures/Excel/formula-column.xlsx')
NS = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'
R = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
def inline(ref, text): return '<c r="%s" t="inlineStr"><is><t>%s</t></is></c>' % (ref, text)
rows = ['<row r="1">%s%s</row>' % (inline('A1', 'x'), inline('B1', 'y'))]
for i in range(ROWS):
    n = i + 2; x = 100 + math.sin(i) * 10
    rows.append('<row r="%d"><c r="A%d"><v>%r</v></c><c r="B%d"><f>A%d*2</f><v>%r</v></c></row>' % (n, n, x, n, n, 2 * x))
sheet = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<worksheet xmlns="%s" xmlns:r="%s"><dimension ref="A1:B%d"/>'
         '<sheetViews><sheetView workbookViewId="0"/></sheetViews><sheetFormatPr defaultRowHeight="15"/><sheetData>%s</sheetData>'
         '<pageMargins left="0.7" right="0.7" top="0.75" bottom="0.75" header="0.3" footer="0.3"/>'
         '<extLst><ext uri="{64002731-A6B0-56B0-2670-7721B7C09600}" xmlns:mx="http://schemas.microsoft.com/office/mac/excel/2008/main">'
         '<mx:PLV Mode="0" OnePage="0" WScale="0"/></ext></extLst></worksheet>') % (NS, R, ROWS + 1, ''.join(rows))
parts = {
    '[Content_Types].xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>',
    '_rels/.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>',
    'xl/workbook.xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<workbook xmlns="%s" xmlns:r="%s"><sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets>'
        '<calcPr calcId="191029"/></workbook>' % (NS, R),
    'xl/_rels/workbook.xml.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>',
    'xl/styles.xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<styleSheet xmlns="%s"><fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts>'
        '<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>'
        '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
        '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
        '<cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs>'
        '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>' % NS,
    'xl/worksheets/sheet1.xml': sheet,
}
out.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as zip:
    for name, text in parts.items():
        info = zipfile.ZipInfo(name, date_time=(2026, 10, 11, 0, 0, 0)); info.compress_type = zipfile.ZIP_DEFLATED
        zip.writestr(info, text)
print('wrote', out, out.stat().st_size, 'bytes,', ROWS, 'rows')
