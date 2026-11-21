"""The same cells as an Excel workbook (.xlsx and its macro-enabled, template and Strict forms), an Excel 97-2003 workbook
(.xls, BIFF8 in a compound file) and an Excel binary workbook (.xlsb, BIFF12), written with the standard library so that
the loader's tests can choose every number format, value and date system and compare the readers cell by cell. Neither
legacy format has a writer among the test dependencies (xlrd only reads, and only .xls).

    write_xlsx(path, sheets, date1904=False, kind='xlsx')   # kind: xlsx, xlsm, xltx, xltm or strict
    write_xls(path, sheets, date1904=False)
    write_xlsb(path, sheets, date1904=False)

`sheets` is a list of (name, cells), and each cell is (row, col, value, format) with 0-based row and column. A value is a
float (a number), a str (text), ('formula', float) for a formula whose saved result is that number, or, in an .xlsx only,
('iso', text) for an ISO 8601 date cell (t="d"). A format is None
(General), an int (a built-in format id, written with no format code, as Excel writes built-ins) or a str (a custom format
code, given its own id from 164). Only what the readers need is written: the fonts and style records Excel requires and a
cell style per format. Numbers are stored exactly, in the records Excel uses: in an .xlsx, the shortest text that reads back
as the double (NaN, Infinity and -Infinity as those words); in an .xls, RK for whole numbers that fit in 30 bits (MULRK for
a run of them along a row), NUMBER otherwise and FORMULA for a saved result; in an .xlsb, BrtCellRk, BrtCellReal and
BrtFmlaNum.
"""
import math, struct, zipfile

# ---------- Formats shared by both writers ----------

def _formats(sheets):
    """The custom codes (code -> id from 164) and the cell styles (format -> style index, General first)."""
    custom, styles = {}, {None: 0}
    for _, cells in sheets:
        for *_, fmt in cells:
            if isinstance(fmt, str) and fmt not in custom: custom[fmt] = 164 + len(custom)
            if fmt not in styles: styles[fmt] = len(styles)
    return custom, styles

def _format_id(fmt, custom):
    return 0 if fmt is None else fmt if isinstance(fmt, int) else custom[fmt]

# ---------- .xls: BIFF8 records in a compound file ----------

def _record(rid, data=b''):
    return struct.pack('<HH', rid, len(data)) + data

def _unicode(text, count='<H'):
    """XLUnicodeString (a 16-bit count) or ShortXLUnicodeString (count '<B'): Latin-1 compressed, otherwise UTF-16."""
    try: return struct.pack(count, len(text)) + b'\x00' + text.encode('latin-1')
    except UnicodeEncodeError:
        raw = text.encode('utf-16-le')
        return struct.pack(count, len(raw) // 2) + b'\x01' + raw

def _bof(kind):   # 0x0005 workbook globals, 0x0010 worksheet
    return _record(0x0809, struct.pack('<HHHHII', 0x0600, kind, 0x18AF, 0x07CD, 0x000080C1, 0x00000306))

def _xf(fmt_id, style):
    # ifnt, ifmt, flags (fLocked, fStyle, ixfParent), alignment, rotation, indent and used attributes (fAtrNum for a cell
    # style with its own format), borders and the default pattern colours.
    flags = 0xFFF5 if style else 0x0001
    used = 0xF400 if style else 0x0400
    return _record(0x00E0, struct.pack('<HHHBBHIIH', 0, fmt_id, flags, 0x20, 0, used, 0, 0, 0x20C0))

def _cell(row, col, xf, value):
    if isinstance(value, str): return _record(0x0204, struct.pack('<HHH', row, col, xf) + _unicode(value))   # LABEL
    if isinstance(value, tuple) and value[0] == 'formula':
        # FORMULA: the saved number, then the parsed formula =<that number> (ptgNum), which no reader here evaluates.
        tokens = b'\x1F' + struct.pack('<d', value[1])
        return _record(0x0006, struct.pack('<HHHdHIH', row, col, xf, value[1], 0, 0, len(tokens)) + tokens)
    if _rk(float(value)) is not None: return _record(0x027E, struct.pack('<HHHI', row, col, xf, _rk(float(value))))   # RK
    return _record(0x0203, struct.pack('<HHHd', row, col, xf, float(value)))   # NUMBER

def _cells(cells, styles):
    """A sheet's cell records in row order. Excel stores whole numbers as RK records, and a run of them along a row as one
    MULRK record, so these do too."""
    records, run = [], []
    def flush():
        if len(run) > 1:
            row, first = run[0][0], run[0][1]
            body = b''.join(struct.pack('<HI', xf, _rk(float(v))) for _, _, xf, v in run)
            records.append(_record(0x00BD, struct.pack('<HH', row, first) + body + struct.pack('<H', run[-1][1])))
        elif run: records.append(_cell(*run[0]))
        run.clear()
    for row, col, value, fmt in sorted(cells, key=lambda c: c[:2]):
        item = (row, col, 15 + styles[fmt], value)
        whole = not isinstance(value, (str, tuple)) and _rk(float(value)) is not None
        if not (whole and run and run[-1][0] == row and run[-1][1] == col - 1): flush()
        if whole: run.append(item)
        else: records.append(_cell(*item))
    flush()
    return records

def _biff8(sheets, date1904):
    custom, styles = _formats(sheets)
    globals_ = [_bof(0x0005), _record(0x00E1, struct.pack('<H', 0x04B0)), _record(0x0042, struct.pack('<H', 1200)),
                _record(0x0022, struct.pack('<H', 1 if date1904 else 0))]
    for _ in range(4):   # Excel's minimum font table; cell styles use font 0
        globals_.append(_record(0x0031, struct.pack('<HHHHHBBBB', 200, 0, 0x7FFF, 400, 0, 0, 0, 0, 0) + _unicode('Arial', '<B')))
    for code, number in custom.items():
        globals_.append(_record(0x041E, struct.pack('<H', number) + _unicode(code)))
    xfs = [_xf(0, True) for _ in range(15)]   # the 15 style formats Excel requires; cell styles follow from 15
    for fmt in styles: xfs.append(_xf(_format_id(fmt, custom), False))
    globals_ += xfs
    # BOUNDSHEET: each sheet's name and the stream offset of its BOF, filled in once the offsets are known.
    bound = [_record(0x0085, struct.pack('<IBB', 0, 0, 0) + _unicode(name, '<B')) for name, _ in sheets]
    head = b''.join(globals_)
    tail = _record(0x000A)
    position = len(head) + sum(len(b) for b in bound) + len(tail)
    bodies = []
    for (name, cells), record in zip(sheets, bound):
        rows = [r for r, *_ in cells] or [0]; cols = [c for _, c, *_ in cells] or [0]
        body = [_bof(0x0010), _record(0x0200, struct.pack('<IIHHH', min(rows), max(rows) + 1, min(cols), max(cols) + 1, 0))]
        body += _cells(cells, styles)
        body.append(_record(0x000A))
        bodies.append((position, b''.join(body)))
        position += len(bodies[-1][1])
    bound = [struct.pack('<HHI', 0x0085, len(b) - 4, at) + b[8:] for b, (at, _) in zip(bound, bodies)]
    return head + b''.join(bound) + tail + b''.join(body for _, body in bodies)

def _compound(stream, name='Workbook'):
    """A version 3 compound file holding one stream. Streams under 4,096 bytes belong in the mini stream, so the stream is
    padded to that size after its last record; readers stop at the last substream's EOF."""
    stream = stream + b'\x00' * max(0, 4096 - len(stream))
    stream += b'\x00' * (-len(stream) % 512)
    data_sectors = len(stream) // 512
    fat_sectors = 1
    while 128 * fat_sectors < data_sectors + 1 + fat_sectors: fat_sectors += 1
    directory_sector = data_sectors
    first_fat = data_sectors + 1
    END, FREE, FATSECT, NOSTREAM = 0xFFFFFFFE, 0xFFFFFFFF, 0xFFFFFFFD, 0xFFFFFFFF
    fat = [i + 1 for i in range(data_sectors - 1)] + [END] + [END] + [FATSECT] * fat_sectors
    fat += [FREE] * (128 * fat_sectors - len(fat))
    difat = list(range(first_fat, first_fat + fat_sectors)) + [FREE] * (109 - fat_sectors)
    header = (b'\xD0\xCF\x11\xE0\xA1\xB1\x1A\xE1' + b'\x00' * 16 + struct.pack('<HHHHH', 0x003E, 0x0003, 0xFFFE, 9, 6)
              + b'\x00' * 6 + struct.pack('<IIIIIIIII', 0, fat_sectors, directory_sector, 0, 4096, END, 0, END, 0)
              + struct.pack('<109I', *difat))
    def entry(label, kind, child, start, size):
        raw = (label + '\x00').encode('utf-16-le') if label else b''
        return (raw.ljust(64, b'\x00') + struct.pack('<HBB', len(raw), kind, 1) + struct.pack('<III', NOSTREAM, NOSTREAM, child)
                + b'\x00' * 16 + struct.pack('<IQQ', 0, 0, 0) + struct.pack('<IQ', start, size))
    directory = (entry('Root Entry', 5, 1, END, 0) + entry(name, 2, NOSTREAM, 0, len(stream))
                 + entry('', 0, NOSTREAM, 0, 0) * 2)
    return header + stream + directory + struct.pack('<%dI' % len(fat), *fat)

def write_xls(path, sheets, date1904=False):
    with open(path, 'wb') as out: out.write(_compound(_biff8(sheets, date1904)))

# ---------- .xlsb: BIFF12 records in a package ----------

def _brt(rid, data=b''):
    head = bytes([rid]) if rid < 0x80 else bytes([(rid & 0x7F) | 0x80, rid >> 7])
    size, n = b'', len(data)
    while True:
        size += bytes([(n & 0x7F) | (0x80 if n > 0x7F else 0)]); n >>= 7
        if not n: break
    return head + size + data

def _wide(text):   # XLWideString
    raw = text.encode('utf-16-le')
    return struct.pack('<I', len(raw) // 2) + raw

def _rk(value):
    """The RK form of a whole number that fits in 30 bits (but not -0), as Excel writes it, else None."""
    if not math.isfinite(value) or value != int(value) or not -2**29 <= value < 2**29 or value == 0 and math.copysign(1, value) < 0:
        return None
    return (int(value) << 2 | 2) & 0xFFFFFFFF

def _sheet_bin(cells, styles):
    rows = [r for r, *_ in cells] or [0]; cols = [c for _, c, *_ in cells] or [0]
    out = [_brt(0x81), _brt(0x94, struct.pack('<IIII', min(rows), max(rows), min(cols), max(cols))), _brt(0x91)]
    by_row = {}
    for row, col, value, fmt in sorted(cells, key=lambda c: c[:2]): by_row.setdefault(row, []).append((col, value, styles[fmt]))
    for row, items in sorted(by_row.items()):
        out.append(_brt(0x00, struct.pack('<IIHHBI', row, 0, 300, 0, 0, 0)))   # BrtRowHdr
        for col, value, style in items:
            head = struct.pack('<II', col, style)
            if isinstance(value, str): out.append(_brt(0x06, head + _wide(value)))   # BrtCellSt
            elif isinstance(value, tuple) and value[0] == 'formula':
                tokens = b'\x1F' + struct.pack('<d', value[1])   # =<that number> (ptgNum)
                out.append(_brt(0x09, head + struct.pack('<dHI', value[1], 0, len(tokens)) + tokens + struct.pack('<I', 0)))
            elif _rk(float(value)) is not None: out.append(_brt(0x02, head + struct.pack('<I', _rk(float(value)))))
            else: out.append(_brt(0x05, head + struct.pack('<d', float(value))))
    out += [_brt(0x92), _brt(0x82)]
    return b''.join(out)

def write_xlsb(path, sheets, date1904=False):
    custom, styles = _formats(sheets)
    xf = lambda parent, fmt_id: _brt(0x2F, struct.pack('<HHHHHBBHH', parent, fmt_id, 0, 0, 0, 0, 0, 0, 0))
    style_bin = b''.join([_brt(0x116), _brt(0x267, struct.pack('<I', len(custom)))]
                         + [_brt(0x2C, struct.pack('<H', number) + _wide(code)) for code, number in custom.items()]
                         + [_brt(0x268), _brt(0x272, struct.pack('<I', 1)), xf(0xFFFF, 0), _brt(0x273),
                            _brt(0x269, struct.pack('<I', len(styles)))]
                         + [xf(0, _format_id(fmt, custom)) for fmt in styles] + [_brt(0x26A), _brt(0x117)])
    book = [_brt(0x83), _brt(0x99, struct.pack('<II', 1 if date1904 else 0, 0) + _wide('')), _brt(0x8F)]
    for i, (name, _) in enumerate(sheets, 1):
        book.append(_brt(0x9C, struct.pack('<II', 0, i) + _wide(f'rId{i}') + _wide(name)))
    book += [_brt(0x90), _brt(0x84)]
    rels = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
    types = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
             '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
             '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
             '<Default Extension="xml" ContentType="application/xml"/>'
             '<Override PartName="/xl/workbook.bin" ContentType="application/vnd.ms-excel.sheet.binary.macroEnabled.main"/>'
             '<Override PartName="/xl/styles.bin" ContentType="application/vnd.ms-excel.styles"/>'
             + ''.join(f'<Override PartName="/xl/worksheets/sheet{i}.bin" ContentType="application/vnd.ms-excel.worksheet"/>'
                       for i in range(1, len(sheets) + 1)) + '</Types>')
    package_rels = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
                    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                    f'<Relationship Id="rId1" Type="{rels}/officeDocument" Target="xl/workbook.bin"/></Relationships>')
    book_rels = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
                 '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                 + ''.join(f'<Relationship Id="rId{i}" Type="{rels}/worksheet" Target="worksheets/sheet{i}.bin"/>'
                           for i in range(1, len(sheets) + 1))
                 + f'<Relationship Id="rId{len(sheets) + 1}" Type="{rels}/styles" Target="styles.bin"/></Relationships>')
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as package:
        package.writestr('[Content_Types].xml', types)
        package.writestr('_rels/.rels', package_rels)
        package.writestr('xl/workbook.bin', b''.join(book))
        package.writestr('xl/_rels/workbook.bin.rels', book_rels)
        package.writestr('xl/styles.bin', style_bin)
        for i, (_, cells) in enumerate(sheets, 1):
            package.writestr(f'xl/worksheets/sheet{i}.bin', _sheet_bin(cells, styles))

# ---------- .xlsx: SpreadsheetML in a package ----------

_MAIN_TYPES = {
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml',
    'xlsm': 'application/vnd.ms-excel.sheet.macroEnabled.main+xml',
    'xltx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.template.main+xml',
    'xltm': 'application/vnd.ms-excel.template.macroEnabled.main+xml',
    'strict': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml'}

def _number_text(x):
    if math.isnan(x): return 'NaN'
    if math.isinf(x): return 'Infinity' if x > 0 else '-Infinity'
    text = repr(float(x))
    return text[:-2] if text.endswith('.0') else text

def _markup(text):
    return text.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;').replace('"', '&quot;')

def _address(row, col):
    letters, n = '', col + 1
    while n: n, r = divmod(n - 1, 26); letters = chr(65 + r) + letters
    return f'{letters}{row + 1}'

def write_xlsx(path, sheets, date1904=False, kind='xlsx'):
    """A transitional workbook of the given kind, or, for kind 'strict', the same parts in Strict OOXML's namespaces."""
    strict = kind == 'strict'
    main = 'http://purl.oclc.org/ooxml/spreadsheetml/main' if strict else 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'
    rels = 'http://purl.oclc.org/ooxml/officeDocument/relationships' if strict else 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
    package = 'http://schemas.openxmlformats.org/package/2006/relationships'
    head = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
    custom, styles = _formats(sheets)
    def cell(row, col, value, fmt):
        ref, style = _address(row, col), styles[fmt]
        if isinstance(value, str): return f'<c r="{ref}" s="{style}" t="inlineStr"><is><t xml:space="preserve">{_markup(value)}</t></is></c>'
        if isinstance(value, tuple) and value[0] == 'formula':
            return f'<c r="{ref}" s="{style}"><f>{_number_text(value[1])}</f><v>{_number_text(value[1])}</v></c>'
        if isinstance(value, tuple) and value[0] == 'iso':   # an ISO 8601 date cell (t="d"), as SheetJS and openpyxl write them
            return f'<c r="{ref}" s="{style}" t="d"><v>{_markup(value[1])}</v></c>'
        return f'<c r="{ref}" s="{style}"><v>{_number_text(value)}</v></c>'
    parts = {}
    for i, (_, cells) in enumerate(sheets, 1):
        by_row = {}
        for row, col, value, fmt in sorted(cells, key=lambda c: c[:2]): by_row.setdefault(row, []).append(cell(row, col, value, fmt))
        parts[f'xl/worksheets/sheet{i}.xml'] = (head + f'<worksheet xmlns="{main}" xmlns:r="{rels}"><sheetData>'
            + ''.join(f'<row r="{row + 1}">' + ''.join(items) + '</row>' for row, items in sorted(by_row.items())) + '</sheetData></worksheet>')
    parts['xl/styles.xml'] = (head + f'<styleSheet xmlns="{main}">'
        + (f'<numFmts count="{len(custom)}">' + ''.join(f'<numFmt numFmtId="{n}" formatCode="{_markup(c)}"/>' for c, n in custom.items()) + '</numFmts>' if custom else '')
        + '<fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts>'
        '<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>'
        '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
        '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
        f'<cellXfs count="{len(styles)}">' + ''.join(f'<xf numFmtId="{_format_id(fmt, custom)}" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>' for fmt in styles)
        + '</cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>')
    parts['xl/workbook.xml'] = (head + f'<workbook xmlns="{main}" xmlns:r="{rels}"><workbookPr date1904="{1 if date1904 else 0}"/><sheets>'
        + ''.join(f'<sheet name="{_markup(name)}" sheetId="{i}" r:id="rId{i}"/>' for i, (name, _) in enumerate(sheets, 1)) + '</sheets></workbook>')
    parts['xl/_rels/workbook.xml.rels'] = (head + f'<Relationships xmlns="{package}">'
        + ''.join(f'<Relationship Id="rId{i}" Type="{rels}/worksheet" Target="worksheets/sheet{i}.xml"/>' for i in range(1, len(sheets) + 1))
        + f'<Relationship Id="rId{len(sheets) + 1}" Type="{rels}/styles" Target="styles.xml"/></Relationships>')
    parts['_rels/.rels'] = (head + f'<Relationships xmlns="{package}"><Relationship Id="rId1" Type="{rels}/officeDocument" Target="xl/workbook.xml"/></Relationships>')
    parts['[Content_Types].xml'] = (head + '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        f'<Override PartName="/xl/workbook.xml" ContentType="{_MAIN_TYPES[kind]}"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        + ''.join(f'<Override PartName="/xl/worksheets/sheet{i}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
                  for i in range(1, len(sheets) + 1)) + '</Types>')
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as out:
        for name in ['[Content_Types].xml', '_rels/.rels', 'xl/workbook.xml', 'xl/_rels/workbook.xml.rels', 'xl/styles.xml'] + sorted(n for n in parts if n.startswith('xl/worksheets/')):
            out.writestr(name, parts[name])
