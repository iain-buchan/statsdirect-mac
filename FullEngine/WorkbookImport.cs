using System;
using System.IO;
using System.IO.Compression;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Xml;
using System.Xml.Linq;
using ExcelDataReader;

public static partial class WorkbookIO {
    // Compatibility imports hold values, not an editable copy of the original package.
    // Retain only the path to prevent an export from replacing an encrypted/legacy source.
    // No password or decrypted source file is retained.
    static readonly ConcurrentDictionary<string, string> dataCopies = new();
    const string DataCopyNotice = "Imported worksheet values. Formula results are from the last Excel save; formulas, formatting, charts and macros are not copied. Save as a new .xlsx workbook to keep the original intact.";

    static object Open(string path, string snapshotDir, string password) {
        if (!File.Exists(path)) throw new Exception("The workbook could not be found.");
        // Format detection, rather than extension alone, decides the reader. Only ordinary, unencrypted XLSX packages use
        // the existing preserving editor. Every other transitional SpreadsheetML package (.xlsm, .xltx and .xltm, and a
        // macro-enabled workbook renamed .xlsx) is a data copy read by the same reader, so that its values load exactly as
        // an .xlsx's do (RULES 3.9 has no exception by file format). The rest go through the compatibility reader: .xls,
        // .xlt, .xlsb, Strict OOXML, encrypted packages and mislabelled files.
        return TransitionalPackage(path) switch {
            true => OpenXlsx(path, snapshotDir),
            false => OpenXlsx(path, snapshotDir, dataCopy: true),
            null => ImportValues(path, snapshotDir, password)
        };
    }

    // Null unless the file is a transitional SpreadsheetML package (xl/workbook.xml in the main namespace, with its
    // relationships). Otherwise true when the preserving editor may patch it: an .xlsx whose content types name an
    // ordinary workbook, since a macro-enabled workbook renamed to .xlsx must not lose its VBA on saving.
    static bool? TransitionalPackage(string path) {
        try {
            using var file = File.OpenRead(path);
            if (file.ReadByte() != 'P' || file.ReadByte() != 'K') return null;
            file.Position = 0;
            using var zip = new ZipArchive(file, ZipArchiveMode.Read);
            var book = Entry(zip, "xl/workbook.xml");
            if (book == null || Entry(zip, "xl/_rels/workbook.xml.rels") == null) return null;
            using (var stream = book.Open())
            using (var reader = XmlReader.Create(stream, new XmlReaderSettings { DtdProcessing = DtdProcessing.Prohibit, XmlResolver = null })) {
                reader.MoveToContent();
                if (reader.NamespaceURI != MainNs) return null;
            }
            if (!Path.GetExtension(path).Equals(".xlsx", StringComparison.OrdinalIgnoreCase)) return false;
            var types = Entry(zip, "[Content_Types].xml");
            if (types == null) return false;
            using var typeStream = types.Open();
            return XDocument.Load(typeStream).Root.Elements().Any(e =>
                string.Equals((string)e.Attribute("PartName"), "/xl/workbook.xml", StringComparison.OrdinalIgnoreCase) &&
                (string)e.Attribute("ContentType") == "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml");
        } catch (Exception ex) when (ex is InvalidDataException or XmlException) { return null; }   // left to the compatibility reader's own message
    }

    static object ImportValues(string path, string snapshotDir, string password, bool singlePass = true) {
        var id = Guid.NewGuid().ToString("N");
        var sheets = new List<Sheet>();
        var written = new List<string>();
        try {
            using var file = File.OpenRead(path);
            using var reader = ExcelReaderFactory.CreateReader(file, new ExcelReaderConfiguration { Password = password, SinglePassMode = singlePass });
            bool date1904 = ReaderDate1904(reader);
            var formatKinds = new Dictionary<int, byte>();   // FormatKind of each number format the workbook uses
            LegacyNumbers own = null;                        // the file's own numbers, read once a date or time needs them
            do {
                var data = new SheetData { Name = reader.Name ?? $"Sheet {sheets.Count + 1}" };
                int count = 0, rows = 0, cols = 0;
                while (reader.Read()) {
                    // Depth is the actual worksheet row, including intervening blank rows.
                    int row = reader.Depth;
                    for (int col = 0; col < reader.FieldCount; col++) {
                        var value = reader.GetValue(col);
                        var error = reader.GetCellError(col);
                        if (value == null && error == null) continue;
                        if (row < 0 || row >= MaxRows || col >= MaxCols)
                            throw new Exception("The workbook contains data outside Excel's worksheet dimensions.");
                        byte kind; double num = double.NaN; string text = "";
                        if (error != null) { kind = 6; text = ErrorText(error.Value); }
                        else switch (value) {
                            case double or int or DateTime or TimeSpan:
                                int formatId = reader.GetNumberFormatIndex(col);
                                if (!formatKinds.TryGetValue(formatId, out var format)) formatKinds[formatId] = format = FormatKind(formatId, reader.GetNumberFormatString(col));
                                double? exact = null;
                                if (value is DateTime or TimeSpan) exact = (own ??= LegacyNumbers.Read(path, password)).Find(sheets.Count, reader.Name, row, col);
                                ClassifyNumber(exact ?? ReaderSerial(value, date1904), format, date1904, out kind, out num, out text);
                                break;
                            case bool b: kind = 5; text = b ? "TRUE" : "FALSE"; break;
                            case string s: kind = 2; text = s; break;
                            default: throw new Exception("The workbook contains an unrecognised cell value.");
                        }
                        if (kind == 2 && text.Length == 0) continue;
                        data.Column(col).Add(row, kind, num, text, "");
                        count++; rows = Math.Max(rows, row + 1); cols = Math.Max(cols, col + 1);
                    }
                }
                string snapshot = null;
                if (snapshotDir != null) {
                    Directory.CreateDirectory(snapshotDir);
                    snapshot = Path.Combine(snapshotDir, $"{id}-{sheets.Count}.sdcol");
                    written.Add(snapshot);
                    using var output = File.Create(snapshot);
                    WriteSnapshot(output, new[] { data });
                }
                sheets.Add(new Sheet(data.Name, rows, cols, reader.VisibleState is "hidden" or "veryhidden",
                    snapshot == null ? Cells(data).ToList() : new List<Cell>(), count, 0, snapshot));
            } while (reader.NextResult());
            if (sheets.Count == 0) throw new Exception("The workbook contains no worksheets.");
            dataCopies[id] = Path.GetFullPath(path);
            return new { id, name = Path.GetFileName(path), sheets, formulaCount = 0,
                cellCount = sheets.Sum(s => (long)s.Count), dataCopy = true, importNotice = DataCopyNotice };
        } catch (Exception ex) {
            foreach (var file in written) { try { File.Delete(file); } catch { } }
            // Some BIFF writers split one row across several record blocks. The
            // reader's indexed mode reconstructs those rows; retry once from the
            // original file after discarding every partial single-pass snapshot.
            if (singlePass && ex is InvalidOperationException && ex.Message.Contains("SinglePassMode = false", StringComparison.Ordinal))
                return ImportValues(path, snapshotDir, password, singlePass: false);
            throw;
        }
    }

    // ---- Numbers, dates and times from the compatibility reader ---------------------------
    // A number cell is classed as the xlsx reader classes it (ReadSheet and TryDateTimeText in WorkbookIO.cs, RULES 3.9), by
    // FormatKind of the reader's number format: a time of day, a duration rounded to the millisecond, a date or date-time with
    // serial 60 as 1900-02-29, or a number, which a negative or out-of-range value in a date or time format stays. A value
    // that is not a finite number is text, as the xlsx reader keeps it, never a blank number cell.
    static void ClassifyNumber(double serial, byte format, bool date1904, out byte kind, out double num, out string text) {
        num = double.NaN; text = "";
        if (!double.IsFinite(serial)) { kind = 2; text = JsNumber(serial); return; }   // NaN, Infinity, -Infinity
        if (format != FormatNumber && TryDateTimeText(serial, format, date1904, out kind, out text)) return;
        kind = 1; num = serial; text = "";
    }
    // ExcelDataReader returns a number in what it takes for a date or time format as a DateTime: DateTime.FromOADate, rounded to
    // the millisecond, of the serial plus 1462 in the 1904 system, or plus 1 below 60 in the 1900 system, so that Excel's day
    // 60 (1900-02-29) and day 59 both read as 1900-02-28. In what it takes for an elapsed format, [Magenta] and [Red][h]
    // included, it returns TimeSpan.FromDays, truncated to the 100 ns tick below. Each cell it returns so is therefore looked up
    // in the file's own numbers (LegacyNumbers); this is the serial it came from only when the file's numbers cannot be read
    // (BIFF2 to BIFF5 .xls, Strict OOXML and encrypted packages): day 59 for 1900-02-28, and to the millisecond, or to the tick.
    static double ReaderSerial(object value, bool date1904) {
        switch (value) {
            case int n: return n;
            case TimeSpan t: return t.TotalDays;
            case DateTime d:
                double oa = d.ToOADate();
                if (date1904) return oa - 1462;
                if (oa >= 61) return oa;
                if (oa >= 1) return oa - 1;
                // A serial from -1 up to 0 reads as 1899-12-30 plus its time, as OLE Automation counts the days of a negative
                // date down and its time up; from -1 down, ToOADate gives the serial back.
                return oa >= 0 ? -oa : oa;
            default: return (double)value;
        }
    }
    // ExcelDataReader 3.9 keeps the workbook's date system to itself, on its reader's Workbook (IsDate1904), for every format it
    // reads. Tests/test_excel_compatibility.py opens 1904-system .xls and .xlsb files, so a version that moves it fails there.
    static bool ReaderDate1904(IExcelDataReader reader) {
        const System.Reflection.BindingFlags members = System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.NonPublic;
        for (var type = reader.GetType(); type != null; type = type.BaseType) {
            var workbook = type.GetProperty("Workbook", members | System.Reflection.BindingFlags.DeclaredOnly)?.GetValue(reader);
            if (workbook?.GetType().GetProperty("IsDate1904", members)?.GetValue(workbook) is bool date1904) return date1904;
        }
        return false;
    }

    // The numbers a legacy workbook stores in its date, time and duration cells, read straight from the file: an Excel
    // 97-2003 workbook (BIFF8, encrypted ones included) through NPOI's record reader, and an .xlsb through its cell records.
    // Only cells whose number format ExcelDataReader or FormatKind takes for a date, time or duration are kept, keyed by
    // sheet, row and column. Any other file, or one these cannot read, gives none.
    sealed class LegacyNumbers {
        readonly List<(string name, Dictionary<long, double> cells)> sheets = new();
        static long Key(int row, int col) => (long)row << 16 | (uint)col;
        Dictionary<long, double> Sheet(string name) { var cells = new Dictionary<long, double>(); sheets.Add((name, cells)); return cells; }
        // The sheet ExcelDataReader gives at that position, or else the one of that name.
        public double? Find(int index, string name, int row, int col) {
            var cells = index < sheets.Count && (name == null || sheets[index].name == name) ? sheets[index].cells
                : sheets.FirstOrDefault(s => s.name == name).cells;
            return cells != null && cells.TryGetValue(Key(row, col), out var value) ? value : null;
        }
        // Whether a number in this format can be a date, time or duration: by FormatKind, or by ExcelDataReader's own parser,
        // which also takes [Magenta] and other codes for one (a built-in format without a code is one for both or for neither).
        static bool DateLike(int id, string code) {
            if (FormatKind(id, code) != FormatNumber) return true;
            if (code == null) return false;
            try { var parsed = new ExcelDataReader.Core.NumberFormat.NumberFormatString(code); return parsed.IsDateTimeFormat || parsed.IsTimeSpanFormat; }
            catch (Exception) { return true; }
        }
        static HashSet<int> DateLikeStyles(List<int> styleFormats, Dictionary<int, string> codes) {
            var styles = new HashSet<int>();
            for (int i = 0; i < styleFormats.Count; i++) if (DateLike(styleFormats[i], codes.TryGetValue(styleFormats[i], out var code) ? code : null)) styles.Add(i);
            return styles;
        }

        public static LegacyNumbers Read(string path, string password) {
            var numbers = new LegacyNumbers();
            try {
                using var file = File.OpenRead(path);
                var head = new byte[8];
                int got = file.Read(head, 0, head.Length);
                file.Position = 0;
                if (got == 8 && NPOI.POIFS.FileSystem.POIFSFileSystem.HasPOIFSHeader(head)) numbers.ReadBiff8(file, password);
                else if (got >= 2 && head[0] == 'P' && head[1] == 'K') numbers.ReadXlsb(file);
            } catch (Exception) { numbers.sheets.Clear(); }   // ExcelDataReader's own values stand
            return numbers;
        }

        // ---- Excel 97-2003 (BIFF8) ----
        void ReadBiff8(Stream file, string password) {
            var listener = new Biff8Numbers(this);
            var request = new NPOI.HSSF.EventUserModel.HSSFRequest();
            request.AddListenerForAllRecords(listener);
            var previous = NPOI.HSSF.Record.Crypto.Biff8EncryptionKey.CurrentUserPassword;
            NPOI.HSSF.Record.Crypto.Biff8EncryptionKey.CurrentUserPassword = password;
            try { new NPOI.HSSF.EventUserModel.HSSFEventFactory().ProcessWorkbookEvents(request, new NPOI.POIFS.FileSystem.POIFSFileSystem(file)); }
            finally { NPOI.HSSF.Record.Crypto.Biff8EncryptionKey.CurrentUserPassword = previous; }
        }
        // The record stream gives RK and MULRK records as NUMBER records. Each top-level substream after the workbook globals is
        // a sheet's, in the order of their BOUNDSHEET offsets; a chart's own substream inside a sheet is skipped.
        sealed class Biff8Numbers : NPOI.HSSF.EventUserModel.IHSSFListener {
            readonly LegacyNumbers numbers;
            readonly Dictionary<int, string> codes = new();
            readonly List<int> styleFormats = new();
            readonly List<NPOI.HSSF.Record.BoundSheetRecord> bound = new();
            NPOI.HSSF.Record.BoundSheetRecord[] ordered;
            HashSet<int> dateStyles;
            int depth, substream = -1;
            Dictionary<long, double> current;
            public Biff8Numbers(LegacyNumbers numbers) { this.numbers = numbers; }
            public void ProcessRecord(NPOI.HSSF.Record.Record record) {
                switch (record) {
                    case NPOI.HSSF.Record.BOFRecord:
                        if (depth++ > 0 || ++substream == 0) break;
                        ordered ??= NPOI.HSSF.Record.BoundSheetRecord.OrderByBofPosition(bound);
                        dateStyles ??= DateLikeStyles(styleFormats, codes);
                        current = substream <= ordered.Length ? numbers.Sheet(ordered[substream - 1].Sheetname) : null;
                        break;
                    case NPOI.HSSF.Record.EOFRecord: if (--depth == 0) current = null; break;
                    case NPOI.HSSF.Record.BoundSheetRecord sheet: bound.Add(sheet); break;
                    case NPOI.HSSF.Record.FormatRecord format: codes[format.IndexCode] = format.FormatString; break;
                    case NPOI.HSSF.Record.ExtendedFormatRecord style: styleFormats.Add(style.FormatIndex & 0xFFFF); break;
                    case NPOI.HSSF.Record.NumberRecord n: Add(n.Row, n.Column, n.XFIndex, n.Value); break;
                    case NPOI.HSSF.Record.FormulaRecord f when f.CachedResultType == NPOI.SS.UserModel.CellType.Numeric: Add(f.Row, f.Column, f.XFIndex, f.Value); break;
                }
            }
            void Add(int row, int col, short style, double value) {
                if (current != null && depth == 1 && dateStyles.Contains(style & 0xFFFF)) current[Key(row, col)] = value;
            }
        }

        // ---- Excel binary workbook (.xlsb, BIFF12) ----
        // Records are a type (one or two bytes of 7 bits) and a size (up to four bytes of 7 bits), then the data. A cell record's
        // data starts with its column (u32) and its cell style (24 bits); the number follows at offset 8.
        const int BrtRowHdr = 0x00, BrtCellRk = 0x02, BrtCellReal = 0x05, BrtFmlaNum = 0x09, BrtFmt = 0x2C, BrtXF = 0x2F,
            BrtBundleSh = 0x9C, BrtBeginCellXFs = 0x269, BrtEndCellXFs = 0x26A;
        static IEnumerable<(int type, byte[] data, int size)> Records(Stream stream) {
            var buffer = new byte[256];
            while (true) {
                int b = stream.ReadByte(); if (b < 0) yield break;
                int type = b & 0x7F;
                if ((b & 0x80) != 0) { b = stream.ReadByte(); if (b < 0) yield break; type |= (b & 0x7F) << 7; }
                int size = 0;
                for (int i = 0; i < 4; i++) { b = stream.ReadByte(); if (b < 0) yield break; size |= (b & 0x7F) << (7 * i); if ((b & 0x80) == 0) break; }
                if (size > buffer.Length) buffer = new byte[size];
                stream.ReadExactly(buffer, 0, size);
                yield return (type, buffer, size);
            }
        }
        static string WideString(byte[] data, ref int at) {
            int length = (int)BitConverter.ToUInt32(data, at); at += 4;
            if (length == -1) return null;   // XLNullableWideString
            var text = System.Text.Encoding.Unicode.GetString(data, at, length * 2); at += length * 2;
            return text;
        }
        static double Rk(uint rk) {
            double value = (rk & 2) != 0 ? (int)rk >> 2 : BitConverter.Int64BitsToDouble((long)(rk & 0xFFFFFFFC) << 32);
            return (rk & 1) != 0 ? value / 100 : value;
        }
        void ReadXlsb(Stream file) {
            using var zip = new ZipArchive(file, ZipArchiveMode.Read, true);
            ZipArchiveEntry Part(string name) => Entry(zip, name) ?? throw new InvalidDataException(name);
            XDocument relsXml;
            using (var stream = Part("xl/_rels/workbook.bin.rels").Open()) relsXml = XDocument.Load(stream);
            var rels = relsXml.Root.Elements(PackageRel + "Relationship")
                .ToDictionary(e => (string)e.Attribute("Id"), e => (target: ResolveTarget((string)e.Attribute("Target")), type: (string)e.Attribute("Type") ?? ""));
            var codes = new Dictionary<int, string>(); var styleFormats = new List<int>(); bool cellStyles = false;
            var styles = rels.Values.FirstOrDefault(r => r.type.EndsWith("/styles", StringComparison.OrdinalIgnoreCase)).target;
            if (styles != null && Entry(zip, styles) is ZipArchiveEntry stylePart) {
                using var stream = stylePart.Open();
                foreach (var (type, data, _) in Records(stream)) {
                    if (type == BrtFmt) { int at = 2; codes[BitConverter.ToUInt16(data, 0)] = WideString(data, ref at); }
                    else if (type == BrtBeginCellXFs) cellStyles = true;
                    else if (type == BrtEndCellXFs) cellStyles = false;
                    else if (type == BrtXF && cellStyles) styleFormats.Add(BitConverter.ToUInt16(data, 2));
                }
            }
            var dateStyles = DateLikeStyles(styleFormats, codes);
            var book = new List<(string rel, string name)>();
            using (var stream = Part("xl/workbook.bin").Open())
                foreach (var (type, data, _) in Records(stream)) {
                    if (type != BrtBundleSh) continue;
                    int at = 8; var rel = WideString(data, ref at); book.Add((rel, WideString(data, ref at)));
                }
            foreach (var (rel, name) in book) {
                var cells = Sheet(name);
                if (rel == null || !rels.TryGetValue(rel, out var target) || !target.type.EndsWith("/worksheet", StringComparison.OrdinalIgnoreCase)) continue;
                using var stream = Part(target.target).Open();
                int row = 0;
                foreach (var (type, data, size) in Records(stream)) {
                    if (type == BrtRowHdr) { row = (int)BitConverter.ToUInt32(data, 0); continue; }
                    if (type is not (BrtCellRk or BrtCellReal or BrtFmlaNum) || size < 12 || !dateStyles.Contains((int)(BitConverter.ToUInt32(data, 4) & 0xFFFFFF))) continue;
                    int col = (int)BitConverter.ToUInt32(data, 0);
                    cells[Key(row, col)] = type == BrtCellRk ? Rk(BitConverter.ToUInt32(data, 8)) : BitConverter.ToDouble(data, 8);
                }
            }
        }
    }

    static string ErrorText(CellError error) => error switch {
        CellError.NULL => "#NULL!", CellError.DIV0 => "#DIV/0!", CellError.VALUE => "#VALUE!",
        CellError.REF => "#REF!", CellError.NAME => "#NAME?", CellError.NUM => "#NUM!",
        CellError.NA => "#N/A", CellError.GETTING_DATA => "#GETTING_DATA",
        _ => "#ERROR!"
    };
}
