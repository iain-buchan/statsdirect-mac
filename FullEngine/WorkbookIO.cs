using System;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Collections.Generic;
using System.Collections.Concurrent;
using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using System.Runtime.InteropServices;
using System.Xml;
using System.Xml.Linq;
using ClosedXML.Excel;

// Host file I/O only. The vendored StatsDirect calculation layer is unchanged.
//
// Workbooks are read by streaming each worksheet part with XmlReader, so a sheet of Excel's
// full dimensions (1,048,576 rows by 16,384 columns) costs memory only for the cells it
// holds. The cells are delivered either as per-cell JSON (`cells`) or, when the request
// names a `snapshot` directory, as one typed columnar file per sheet (see Snapshot below)
// that the grid loads into typed arrays without going through JSON.
//
// Saving writes a new workbook with a streaming XML writer. An unchanged source workbook
// is copied with its original calculation settings and cached results. Edits are patched
// through ClosedXML (which recalculates formulas and preserves styles) only where its
// results can be trusted: a small workbook, of features ClosedXML keeps, every one of whose
// formulas ClosedXML recalculates, before the edits, to the result Excel saved. Any other
// workbook is patched by streaming each worksheet part and merging the edited cells, which
// leaves Excel to recalculate the formulas when it opens the file.
public static partial class WorkbookIO {
    // Above this many cells (original plus edits) a patch streams instead of loading ClosedXML.
    public const int ClosedXmlCells = 1000000;
    // And above this many formula cells: ClosedXML's recalculation, which a save runs twice, takes time that grows faster
    // than their number. On an M-series Mac a save at this limit takes about 3 s; one recalculation of 100,000 formulas
    // takes about a minute, and of 500,000 over twenty minutes.
    public const int ClosedXmlFormulas = 20000;
    const int MaxRows = 1048576, MaxCols = 16384;
    static readonly ConcurrentDictionary<string, (string path, long cells)> originals = new();
    static WorkbookIO() {
        Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
        AppDomain.CurrentDomain.ProcessExit += (_, _) => { foreach (var original in originals.Values) { try { File.Delete(original.path); } catch { } } };
    }
    static readonly JsonSerializerOptions json = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase, PropertyNameCaseInsensitive = true };
    // SavedEmpty marks empty saved text, including an array/spill or data-table result without its own formula element.
    public sealed record Cell(int Col, int Row, string Text, string Kind, string Formula = "",
        [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] bool? SavedEmpty = null);
    // Formula result regions are inclusive and zero-based. They stay separate from cell formula expressions, and from the
    // sparse snapshot cells, so a missing dependent needs no materialised cell to retain its formula origin.
    public sealed record FormulaRegion(int FirstRow, int LastRow, int FirstColumn, int LastColumn);
    public sealed record Sheet(string Name, int Rows, int Columns, bool Hidden, List<Cell> Cells, int Count, int FormulaCount, string Snapshot,
        [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] List<FormulaRegion> FormulaRegions = null);
    public sealed record Patch(string Name, List<Cell> Cells);
    public sealed record Request(string Action, string Path, string Id, List<Patch> Sheets, string Snapshot, bool Stream = false, List<SheetInserts> Inserts = null, string Password = null);
    // Columns inserted into an opened worksheet by the grid (a write-back placed before existing columns), in the
    // order they were made and in the coordinates of that moment; the cells sent to save are in the final coordinates.
    public sealed record SheetInserts(string Name, List<Insert> Inserts);
    public sealed record Insert(int Col, int Count);
    static readonly XNamespace S = "http://schemas.openxmlformats.org/spreadsheetml/2006/main";
    static readonly XNamespace Rel = "http://schemas.openxmlformats.org/officeDocument/2006/relationships";
    static readonly XNamespace PackageRel = "http://schemas.openxmlformats.org/package/2006/relationships";
    const string MainNs = "http://schemas.openxmlformats.org/spreadsheetml/2006/main";

    public static string Execute(string input) {
        try {
            var request = JsonSerializer.Deserialize<Request>(input, json) ?? throw new Exception("Missing workbook request.");
            object result = request.Action switch {
                "open" => Open(request.Path, request.Snapshot, request.Password),
                "save" => Save(request),
                "exportXls" => ExportXls(request),
                "validateInserts" => ValidateInsertions(request),
                "close" => Close(request.Id),
                _ => throw new Exception("Unknown workbook action.")
            };
            return JsonSerializer.Serialize(result, json);
        } catch (ExcelDataReader.Exceptions.InvalidPasswordException) {
            return JsonSerializer.Serialize(new { error = "This workbook needs its opening password.", code = "workbookPassword" }, json);
        } catch (Exception ex) { return JsonSerializer.Serialize(new { error = ex.Message }, json); }
    }

    static object Close(string id) {
        if (dataCopies.TryRemove(id ?? "", out _)) return new { ok = true };
        if (!originals.TryRemove(id ?? "", out var original)) return new { ok = false };
        try { File.Delete(original.path); } catch { }
        return new { ok = true };
    }

    // ---- Typed columnar snapshot -------------------------------------------------------
    // Little-endian. Header: "SCOL" u32, version u32 (1), sheet count u32, flags u32 (bit 0:
    // every column header has an extras count after its formula count, and an extras string
    // group of loader metadata follows its formulas; written when any cell has extras, skipped
    // when read here). Sheet: name length u32, UTF-8 name, pad to 4, column count u32. Column:
    // index u32, cell count n u32, text count u32, formula count u32, (extras count u32), rows
    // u32[n], kinds u8[n], pad to 8, numbers f64[n], then text, formula and extras entries
    // (cell ordinal u32, byte length u32, UTF-8), each group padded to 4. Kinds: 0 blank,
    // 1 number, 2 text, 3 datetime, 4 timespan, 5 boolean, 6 error. A number cell carries its
    // value; every other kind carries text. An extras entry is a JSON object: the loader writes
    // {"savedEmpty":true} for a formula whose saved result is empty text (the grid's col.extra).
    static readonly string[] KindNames = { "blank", "number", "text", "datetime", "timespan", "boolean", "error" };
    const string SavedEmptyExtra = "{\"savedEmpty\":true}";
    public sealed class ColumnData {
        public int Col;
        public readonly List<int> Rows = new();
        public readonly List<byte> Kinds = new();
        public readonly List<double> Nums = new();
        public readonly List<KeyValuePair<int, string>> Texts = new();
        public readonly List<KeyValuePair<int, string>> Formulas = new();
        public readonly List<KeyValuePair<int, string>> Extras = new();
        public void Add(int row, byte kind, double num, string text, string formula, string extra = "") {
            int ordinal = Rows.Count;
            Rows.Add(row); Kinds.Add(kind); Nums.Add(num);
            if (kind != 1 && text.Length > 0) Texts.Add(new(ordinal, text));
            if (formula.Length > 0) Formulas.Add(new(ordinal, formula));
            if (extra.Length > 0) Extras.Add(new(ordinal, extra));
        }
        public string TextAt(int i) => Kinds[i] == 1 ? JsNumber(Nums[i]) : Texts.Count > 0 && Texts.BinarySearch(new(i, null), OrdinalOrder) is int k && k >= 0 ? Texts[k].Value : "";
        static readonly Comparer<KeyValuePair<int, string>> OrdinalOrder = Comparer<KeyValuePair<int, string>>.Create((a, b) => a.Key.CompareTo(b.Key));
    }
    public sealed class SheetData {
        public string Name;
        public readonly SortedDictionary<int, ColumnData> Columns = new();
        public readonly List<FormulaRegion> FormulaRegions = new();
        public ColumnData Column(int c) { if (!Columns.TryGetValue(c, out var d)) Columns[c] = d = new ColumnData { Col = c }; return d; }
    }
    static void Pad(BinaryWriter w, int align) { while (w.BaseStream.Position % align != 0) w.Write((byte)0); }
    public static void WriteSnapshot(Stream stream, IReadOnlyList<SheetData> sheets) {
        using var w = new BinaryWriter(stream, Encoding.UTF8, true);
        bool extras = sheets.Any(s => s.Columns.Values.Any(c => c.Extras.Count > 0));
        w.Write(0x4C4F4353u); w.Write(1u); w.Write((uint)sheets.Count); w.Write(extras ? 1u : 0u);
        foreach (var sheet in sheets) {
            var name = Encoding.UTF8.GetBytes(sheet.Name ?? ""); w.Write((uint)name.Length); w.Write(name); Pad(w, 4);
            w.Write((uint)sheet.Columns.Count);
            foreach (var col in sheet.Columns.Values) {
                int n = col.Rows.Count;
                w.Write((uint)col.Col); w.Write((uint)n); w.Write((uint)col.Texts.Count); w.Write((uint)col.Formulas.Count);
                if (extras) w.Write((uint)col.Extras.Count);
                foreach (var r in col.Rows) w.Write((uint)r);
                w.Write(col.Kinds.ToArray()); Pad(w, 8);
                foreach (var x in col.Nums) w.Write(x);
                foreach (var group in extras ? new[] { col.Texts, col.Formulas, col.Extras } : new[] { col.Texts, col.Formulas }) {
                    foreach (var (ordinal, text) in group) { var bytes = Encoding.UTF8.GetBytes(text); w.Write((uint)ordinal); w.Write((uint)bytes.Length); w.Write(bytes); }
                    Pad(w, 4);
                }
            }
        }
    }
    public static List<SheetData> ReadSnapshot(Stream stream) {
        using var r = new BinaryReader(stream, Encoding.UTF8, true);
        if (r.ReadUInt32() != 0x4C4F4353u || r.ReadUInt32() != 1u) throw new Exception("The worksheet snapshot is not in a recognised format.");
        int sheetCount = (int)r.ReadUInt32(); uint flags = r.ReadUInt32();
        void Align(int a) { while (r.BaseStream.Position % a != 0) r.ReadByte(); }
        var sheets = new List<SheetData>();
        for (int s = 0; s < sheetCount; s++) {
            var sheet = new SheetData { Name = Encoding.UTF8.GetString(r.ReadBytes((int)r.ReadUInt32())) }; Align(4);
            int columns = (int)r.ReadUInt32();
            for (int c = 0; c < columns; c++) {
                var col = new ColumnData { Col = (int)r.ReadUInt32() };
                int n = (int)r.ReadUInt32(), texts = (int)r.ReadUInt32(), formulas = (int)r.ReadUInt32();
                int extras = (flags & 1) != 0 ? (int)r.ReadUInt32() : 0;
                for (int i = 0; i < n; i++) col.Rows.Add((int)r.ReadUInt32());
                col.Kinds.AddRange(r.ReadBytes(n)); Align(8);
                for (int i = 0; i < n; i++) col.Nums.Add(r.ReadDouble());
                for (int i = 0; i < texts; i++) { int o = (int)r.ReadUInt32(); col.Texts.Add(new(o, Encoding.UTF8.GetString(r.ReadBytes((int)r.ReadUInt32())))); }
                Align(4);
                for (int i = 0; i < formulas; i++) { int o = (int)r.ReadUInt32(); col.Formulas.Add(new(o, Encoding.UTF8.GetString(r.ReadBytes((int)r.ReadUInt32())))); }
                Align(4);
                // Loader metadata (the R data markers) has no meaning in a workbook.
                for (int i = 0; i < extras; i++) { r.ReadUInt32(); r.ReadBytes((int)r.ReadUInt32()); }
                if (extras > 0) Align(4);
                sheet.Columns[col.Col] = col;
            }
            sheets.Add(sheet);
        }
        return sheets;
    }
    static IEnumerable<Cell> Cells(SheetData sheet) {
        foreach (var col in sheet.Columns.Values) {
            var formulas = col.Formulas.ToDictionary(p => p.Key, p => p.Value);
            var savedEmpty = col.Extras.Where(p => p.Value == SavedEmptyExtra).Select(p => p.Key).ToHashSet();
            for (int i = 0; i < col.Rows.Count; i++)
                yield return new Cell(col.Col, col.Rows[i], col.TextAt(i), KindNames[col.Kinds[i]], formulas.TryGetValue(i, out var f) ? f : "", savedEmpty.Contains(i) ? true : (bool?)null);
        }
    }
    static SheetData FromCells(string name, IEnumerable<Cell> cells) {
        var sheet = new SheetData { Name = name };
        foreach (var cell in cells) {
            byte kind = (byte)Math.Max(0, Array.IndexOf(KindNames, cell.Kind ?? "text"));
            var text = cell.Text ?? "";
            if (text.Length == 0) kind = 0;
            double num = double.NaN;
            if (kind == 1 && !double.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out num)) throw new Exception($"'{text}' is not a number.");
            sheet.Column(cell.Col).Add(cell.Row, kind, num, text, cell.Formula ?? "");
        }
        return sheet;
    }

    // JavaScript's Number-to-string form, so the grid stores the value as a double without
    // keeping the file's own spelling (.NET's shortest round-trip digits are the same as JS's).
    public static string JsNumber(double v) {
        if (double.IsNaN(v)) return "NaN";
        if (double.IsInfinity(v)) return v > 0 ? "Infinity" : "-Infinity";
        if (v == 0) return "0";
        var r = v.ToString("R", CultureInfo.InvariantCulture);
        bool negative = r[0] == '-'; if (negative) r = r.Substring(1);
        int e = r.IndexOf('E'); int exp = 0;
        if (e >= 0) { exp = int.Parse(r.Substring(e + 1), CultureInfo.InvariantCulture); r = r.Substring(0, e); }
        int point = r.IndexOf('.'); string digits = point < 0 ? r : r.Remove(point, 1);
        int intDigits = point < 0 ? r.Length : point;
        int lead = 0; while (lead < digits.Length - 1 && digits[lead] == '0') { lead++; intDigits--; }
        digits = digits.Substring(lead).TrimEnd('0'); if (digits.Length == 0) digits = "0";
        int k = digits.Length, n = intDigits + exp;
        string body;
        if (k <= n && n <= 21) body = digits + new string('0', n - k);
        else if (0 < n && n <= 21) body = digits.Substring(0, n) + "." + digits.Substring(n);
        else if (-6 < n && n <= 0) body = "0." + new string('0', -n) + digits;
        else { int ex = n - 1; body = (k == 1 ? digits : digits.Substring(0, 1) + "." + digits.Substring(1)) + "e" + (ex < 0 ? "-" : "+") + Math.Abs(ex).ToString(CultureInfo.InvariantCulture); }
        return negative ? "-" + body : body;
    }

    // ---- Open ------------------------------------------------------------------------
    // A data copy (dataCopy) is any other transitional SpreadsheetML package, such as .xlsm, .xltx or .xltm: its values are read
    // exactly as an .xlsx's are, but, as with the compatibility reader (WorkbookImport.cs), only the values are kept (a formula's
    // saved result, without the formula) and the original is never patched.
    static object OpenXlsx(string path, string snapshotDir, bool dataCopy = false) {
        var id = Guid.NewGuid().ToString("N");
        var sheets = new List<Sheet>();
        var written = new List<string>();
        try {
        // The original is kept as a private copy so later edits on disk do not change what is patched. The copy is taken
        // first and the cells are read from it, so the grid and the copy hold the same workbook even when the file is
        // replaced while it is read (by a sync client, or Excel's AutoSave).
        string copy = null;
        if (!dataCopy) {
            if (snapshotDir != null) Directory.CreateDirectory(snapshotDir);
            copy = System.IO.Path.Combine(snapshotDir ?? System.IO.Path.GetTempPath(), $"statsdirect-workbook-{id}.xlsx");
            written.Add(copy);
            CopyContents(path, copy);
        }
        using (var zip = ZipFile.OpenRead(copy ?? path)) {
            var package = new Package(zip);
            int index = 0;
            foreach (var info in package.Sheets) {
                var data = new SheetData { Name = info.Name };
                int count = 0, formulas = 0, rows = 0, cols = 0;
                ReadSheet(zip, package, info, data, ref count, ref formulas, ref rows, ref cols, dataCopy);
                string snapshot = null; List<Cell> cells;
                if (snapshotDir != null) {
                    Directory.CreateDirectory(snapshotDir);
                    snapshot = System.IO.Path.Combine(snapshotDir, $"{id}-{index}.sdcol");
                    written.Add(snapshot);
                    using var stream = File.Create(snapshot);
                    WriteSnapshot(stream, new[] { data });
                    cells = new List<Cell>();
                } else cells = Cells(data).ToList();
                sheets.Add(new Sheet(info.Name, rows, cols, info.Hidden, cells, count, formulas, snapshot,
                    data.FormulaRegions.Count == 0 ? null : data.FormulaRegions));
                index++;
            }
        }
        if (sheets.Count == 0) throw new Exception("The workbook contains no worksheets.");
        if (dataCopy) {
            dataCopies[id] = System.IO.Path.GetFullPath(path);
            return new { id, name = System.IO.Path.GetFileName(path), sheets, formulaCount = 0,
                cellCount = sheets.Sum(s => (long)s.Count), dataCopy = true, importNotice = DataCopyNotice };
        }
        originals[id] = (copy, sheets.Sum(x => (long)x.Count));
        return new { id, name = System.IO.Path.GetFileName(path), sheets, formulaCount = sheets.Sum(s => s.FormulaCount), cellCount = sheets.Sum(s => s.Count) };
        } catch { foreach (var file in written) { try { File.Delete(file); } catch { } } throw; }
    }
    // A new file holding the source's bytes. A file-system copy would also give it the source's modification time,
    // read-only permission and Finder lock, and a locked copy can be neither patched nor removed.
    static void CopyContents(string source, string target) {
        using var input = File.OpenRead(source);
        using var output = File.Create(target);
        input.CopyTo(output);
    }

    sealed class SheetInfo { public string Name; public string Entry; public bool Hidden; }
    // Part names in a package are case-insensitive and relationship targets are percent-encoded.
    static ZipArchiveEntry Entry(ZipArchive zip, string name) =>
        zip.GetEntry(name) ?? zip.Entries.FirstOrDefault(e => string.Equals(e.FullName, name, StringComparison.OrdinalIgnoreCase));
    static string ResolveTarget(string target) => Uri.UnescapeDataString(new Uri(new Uri("http://xlsx/xl/workbook.xml"), target).AbsolutePath.TrimStart('/'));
    sealed class Package {
        public readonly List<SheetInfo> Sheets = new();
        public readonly List<string> SharedStrings = new();
        public readonly List<NumberFormat> StyleFormats = new();   // per cellXfs index, its number format's sections and their classes
        public bool Date1904;
        public Package(ZipArchive zip, bool structureOnly = false) {
            XDocument Read(string name) { var entry = Entry(zip, name) ?? throw new Exception("The workbook is missing " + name + "."); using var s = entry.Open(); return XDocument.Load(s); }
            var book = Read("xl/workbook.xml");
            var rels = Read("xl/_rels/workbook.xml.rels").Root.Elements(PackageRel + "Relationship")
                .ToDictionary(e => (string)e.Attribute("Id"), e => (target: (string)e.Attribute("Target"), type: (string)e.Attribute("Type") ?? ""));
            Date1904 = (string)book.Root.Element(S + "workbookPr")?.Attribute("date1904") is "1" or "true";
            foreach (var sheet in book.Root.Element(S + "sheets")?.Elements(S + "sheet") ?? Enumerable.Empty<XElement>()) {
                var rid = (string)sheet.Attribute(Rel + "id");
                if (rid == null || !rels.TryGetValue(rid, out var rel)) continue;
                // Chart, dialog and macro sheets are not worksheets and hold no cells.
                if (!rel.type.EndsWith("/worksheet", StringComparison.OrdinalIgnoreCase)) continue;
                Sheets.Add(new SheetInfo { Name = (string)sheet.Attribute("name"), Entry = ResolveTarget(rel.target), Hidden = (string)sheet.Attribute("state") is "hidden" or "veryHidden" });
            }
            string Part(string suffix) => rels.Values.Where(r => r.type.EndsWith(suffix, StringComparison.OrdinalIgnoreCase)).Select(r => ResolveTarget(r.target)).FirstOrDefault(e => Entry(zip, e) != null);
            var shared = Part("/sharedStrings");
            if (shared != null && !structureOnly) ReadSharedStrings(Entry(zip, shared));
            var styles = Part("/styles");
            if (styles != null) ReadStyles(Read(styles));
        }
        void ReadSharedStrings(ZipArchiveEntry entry) {
            using var stream = entry.Open();
            using var reader = XmlReader.Create(stream, new XmlReaderSettings { IgnoreWhitespace = false });
            while (reader.Read()) {
                if (reader.NodeType != XmlNodeType.Element || reader.LocalName != "si") continue;
                if (reader.IsEmptyElement) { SharedStrings.Add(""); continue; }
                SharedStrings.Add(ReadRichText(reader));
            }
        }
        void ReadStyles(XDocument styles) {
            var custom = new Dictionary<int, string>();
            foreach (var f in styles.Root.Element(S + "numFmts")?.Elements(S + "numFmt") ?? Enumerable.Empty<XElement>())
                custom[(int)f.Attribute("numFmtId")] = (string)f.Attribute("formatCode") ?? "";
            foreach (var xf in styles.Root.Element(S + "cellXfs")?.Elements(S + "xf") ?? Enumerable.Empty<XElement>()) {
                int id = (int?)xf.Attribute("numFmtId") ?? 0;
                StyleFormats.Add(ParseFormat(id, custom.TryGetValue(id, out var code) ? code : null));
            }
        }
    }
    // Classes of number format: a plain number, a date or date-time, an elapsed time (a duration)
    // and a time of day (a time with no date). The first three share the cell kinds' numbers.
    public const byte FormatNumber = 1, FormatDate = 3, FormatElapsed = 4, FormatTime = 7;
    // Excel's built-in date and time formats, and custom codes with date or time tokens. In a code,
    // m or mm is minutes after an h or before an s, otherwise the month (Excel's rule); quoted
    // text, \x escapes, _x and *x padding and [...] blocks (colours, conditions, locales) are not
    // tokens, except a bracket holding one of h, m or s alone, repeated ([h], [hh], [mm], [ss]),
    // which is an elapsed time: [Magenta] and [Red] are colours (RULES 3.9). An unclosed [ runs to
    // the end of the code. Built-ins 46 ([h]:mm:ss) and 79 (Thai [h]:mm:ss) are the elapsed ones:
    // 45 (mm:ss) and 47 (mmss.0) wrap at the hour, so they are times of day, as are 32 and 33 in
    // every East Asian locale that defines them and Thai 75, 76, 78 and 80; the other East Asian
    // and Thai date formats (71 to 74, 77 and 81) are dates. ExcelDataReader names each built-in
    // by a code that this function classes as it classes the id, so a legacy file classes as an
    // .xlsx does (WorkbookImport.cs).
    // A number format's sections, separated by ; outside quotes, escapes and brackets, each with its class and any condition
    // ([<0], [>=100]) outside quotes; a built-in format without a code has one section. Only the section that applies to a
    // value counts, and its own class decides how the value is read (RULES 3.9, amendments 1 and 2, as Excel does). With a
    // condition in the first or second section, a section without a condition keeps its role, the first for positive values
    // and the second for negative ones: the first applies where it can, then the second, then the third, and of only two
    // sections the second applies wherever the first does not. Without conditions, the first is for a positive value, the
    // second for a negative one and the third for zero, where they exist (zero takes the first when there is no third, and a
    // negative the first when there is no second).
    public sealed class NumberFormat {
        readonly List<(byte kind, Func<double, bool> condition)> sections;
        internal NumberFormat(List<(byte kind, Func<double, bool> condition)> sections) { this.sections = sections; }
        public byte KindFor(double value) {
            if (sections.Count == 0) return FormatNumber;
            if (sections[0].condition != null || sections.Count > 1 && sections[1].condition != null) {
                var (first, firstCondition) = sections[0];
                if (firstCondition != null ? firstCondition(value) : value > 0) return first;
                if (sections.Count == 1) return FormatNumber;
                var (second, secondCondition) = sections[1];
                if (sections.Count == 2 || (secondCondition != null ? secondCondition(value) : value < 0)) return second;
                return sections[2].kind;
            }
            int index = value < 0 ? 1 : value == 0 ? 2 : 0;
            return (index < sections.Count && index < 3 ? sections[index] : sections[0]).kind;
        }
        // Whether any section is a date, time or duration format.
        public bool DateLike => sections.Any(s => s.kind != FormatNumber);
    }
    static readonly Regex Condition = new(@"^\s*(<=|>=|<>|<|>|=)\s*([+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?)\s*$", RegexOptions.Compiled | RegexOptions.CultureInvariant);
    public static NumberFormat ParseFormat(int id, string code) {
        if (code == null) return new NumberFormat(new() { (BuiltInKind(id), null) });
        var sections = new List<(byte kind, Func<double, bool> condition)>();
        int start = 0;
        Func<double, bool> condition = null;
        for (int i = 0; i <= code.Length; i++) {
            if (i == code.Length || code[i] == ';') {
                sections.Add((SectionKind(code.Substring(start, i - start)), condition));
                start = i + 1; condition = null; continue;
            }
            char ch = code[i];
            if (ch == '"') { int close = code.IndexOf('"', i + 1); i = close < 0 ? code.Length - 1 : close; continue; }
            if (ch is '\\' or '_' or '*') { if (i + 1 < code.Length) i++; continue; }   // never past the last section's end
            if (ch == '[') {
                int close = code.IndexOf(']', i); if (close < 0) close = code.Length;
                var m = Condition.Match(code.Substring(i + 1, close - i - 1));
                if (m.Success && condition == null && double.TryParse(m.Groups[2].Value, NumberStyles.Float, CultureInfo.InvariantCulture, out var bound)) {
                    string op = m.Groups[1].Value;
                    condition = op switch {
                        "<" => v => v < bound, ">" => v => v > bound, "=" => v => v == bound,
                        "<=" => v => v <= bound, ">=" => v => v >= bound, _ => v => v != bound };
                }
                i = Math.Min(close, code.Length - 1);   // on the ], or on the last character of an unclosed bracket
                continue;
            }
        }
        return new NumberFormat(sections);
    }
    // The class of a value in this format: the class of the section that applies to it.
    public static byte FormatKind(int id, string code, double value) => ParseFormat(id, code).KindFor(value);
    // The class of a positive value, for callers that have no value.
    public static byte FormatKind(int id, string code) => ParseFormat(id, code).KindFor(1);
    static byte BuiltInKind(int id) {
        if (id is 46 or 79) return FormatElapsed;   // [h]:mm:ss
        if (id is (>= 18 and <= 21) or 32 or 33 or 45 or 47 or 75 or 76 or 78 or 80) return FormatTime;   // 45 mm:ss and 47 mmss.0 wrap at the hour, as times of day do
        if (id is (>= 14 and <= 22) or (>= 27 and <= 36) or (>= 50 and <= 58) or (>= 71 and <= 81)) return FormatDate;
        return FormatNumber;
    }
    // The class of one section: y, d, h, s; m for m or mm, M for mmm and longer (always the month), a for AM/PM or A/P; m or mm
    // is the minute after an h or before an s, otherwise the month. Quoted text, \x escapes, _x and *x padding and [...]
    // blocks (colours, conditions, locales) are not tokens, except [h], [m] and [s] repeated, which make an elapsed time.
    static byte SectionKind(string code) {
        var tokens = new List<char>();
        for (int i = 0; i < code.Length; i++) {
            char ch = code[i];
            if (ch == '"') { int end = code.IndexOf('"', i + 1); i = end < 0 ? code.Length : end; continue; }
            if (ch is '\\' or '_' or '*') { i++; continue; }
            if (ch == '[') {
                // A code ending in an unclosed [ (another program can write "0.00[") must not fail the whole workbook.
                int end = code.IndexOf(']', i); if (end < 0) end = code.Length;
                var inner = code.Substring(i + 1, end - i - 1).ToLowerInvariant();
                if (inner.Length > 0 && inner[0] is 'h' or 'm' or 's' && inner.All(c => c == inner[0])) return FormatElapsed;
                i = end; continue;
            }
            if (string.Compare(code, i, "AM/PM", 0, 5, StringComparison.OrdinalIgnoreCase) == 0) { tokens.Add('a'); i += 4; continue; }
            if (string.Compare(code, i, "A/P", 0, 3, StringComparison.OrdinalIgnoreCase) == 0) { tokens.Add('a'); i += 2; continue; }
            char l = char.ToLowerInvariant(ch);
            if (l is not ('y' or 'm' or 'd' or 'h' or 's')) continue;
            int run = 1; while (i + 1 < code.Length && char.ToLowerInvariant(code[i + 1]) == l) { i++; run++; }
            tokens.Add(l == 'm' && run > 2 ? 'M' : l);
        }
        bool date = false, time = false;
        for (int t = 0; t < tokens.Count; t++) {
            switch (tokens[t]) {
                case 'y' or 'd' or 'M': date = true; break;
                case 'h' or 's' or 'a': time = true; break;
                case 'm' when t > 0 && tokens[t - 1] == 'h' || t + 1 < tokens.Count && tokens[t + 1] == 's': time = true; break;
                case 'm': date = true; break;
            }
        }
        return date ? FormatDate : time ? FormatTime : FormatNumber;
    }
    static void ReadSheet(ZipArchive zip, Package package, SheetInfo info, SheetData data, ref int count, ref int formulaCount, ref int rows, ref int cols, bool valuesOnly = false) {
        var entry = Entry(zip, info.Entry) ?? throw new Exception("The worksheet part " + info.Entry + " is missing.");
        using var stream = entry.Open();
        using var reader = XmlReader.Create(stream, new XmlReaderSettings { IgnoreWhitespace = true });
        var shared = new Dictionary<string, (string formula, int row, int col)>();  // shared formula masters by si
        int rowNumber = 0, colNumber = 0;
        if (!reader.ReadToFollowing("sheetData", MainNs)) return;
        if (reader.IsEmptyElement) return;
        int depth = reader.Depth;
        while (reader.Read()) {
            if (reader.NodeType == XmlNodeType.EndElement && reader.Depth == depth) break;
            if (reader.NodeType != XmlNodeType.Element) continue;
            if (reader.LocalName == "row") {
                rowNumber = int.TryParse(reader.GetAttribute("r"), NumberStyles.None, CultureInfo.InvariantCulture, out var rn) ? rn : rowNumber + 1;
                colNumber = 0;
                continue;
            }
            if (reader.LocalName != "c") continue;
            var address = reader.GetAttribute("r");
            if (address != null) { var (r, c) = ParseAddress(address); if (r > 0) rowNumber = r; colNumber = c; } else colNumber++;
            string type = reader.GetAttribute("t"), style = reader.GetAttribute("s");
            string value = null, formula = "", inline = null; bool hasFormula = false;
            if (!reader.IsEmptyElement) {
                int cellDepth = reader.Depth;
                reader.Read();
                while (!reader.EOF && !(reader.NodeType == XmlNodeType.EndElement && reader.Depth == cellDepth)) {
                    if (reader.NodeType != XmlNodeType.Element) { reader.Read(); continue; }
                    if (reader.LocalName == "v") { value = reader.ReadElementContentAsString(); continue; }
                    if (reader.LocalName == "f") {
                        hasFormula = true;
                        string ft = reader.GetAttribute("t"), si = reader.GetAttribute("si");
                        if (!valuesOnly && (ft is "array" or "dataTable")) {
                            var region = FormulaResultRegion(reader.GetAttribute("ref"));
                            if (region != null) {
                                data.FormulaRegions.Add(region);
                                rows = Math.Max(rows, region.LastRow + 1); cols = Math.Max(cols, region.LastColumn + 1);
                            }
                        }
                        string text = reader.ReadElementContentAsString();
                        if (ft == "shared" && si != null) {
                            if (text.Length > 0) shared[si] = (text, rowNumber, colNumber);
                            else if (shared.TryGetValue(si, out var master)) text = ShiftFormula(master.formula, rowNumber - master.row, colNumber - master.col);
                        }
                        formula = text; continue;
                    }
                    if (reader.LocalName == "is") { inline = reader.IsEmptyElement ? "" : ReadRichText(reader); reader.Read(); continue; }
                    reader.Skip();
                }
            }
            if (valuesOnly) { hasFormula = false; formula = ""; }   // a data copy keeps a formula's saved result alone
            if (hasFormula && formula.Length == 0) formula = "=";  // a formula without text still protects the cell
            // Empty saved text (t="str" with <v></v> or <v/>) is distinct from no saved result. Keep it even when the
            // formula belongs to an array/spill or data-table anchor elsewhere, whose result region names this cell.
            // An untyped empty <v/> as openpyxl writes every formula is not a saved empty-text result.
            string extra = !valuesOnly && type == "str" && value?.Length == 0 ? SavedEmptyExtra : "";
            byte kind; double num = double.NaN; string cellText;
            if (type == "s") { kind = 2; cellText = value != null && int.TryParse(value, NumberStyles.None, CultureInfo.InvariantCulture, out var si) && si < package.SharedStrings.Count ? package.SharedStrings[si] : ""; }
            else if (type == "inlineStr") { kind = 2; cellText = inline ?? ""; }
            else if (type == "str") { kind = 2; cellText = Unescape(value ?? ""); }
            else if (type == "b") { kind = 5; cellText = value == "1" ? "TRUE" : value == "0" ? "FALSE" : value ?? ""; if (cellText.Length == 0) kind = 0; }
            else if (type == "e") { kind = 6; cellText = value ?? ""; }
            else if (type == "d") IsoDateText(value ?? "", out kind, out cellText);
            else if (string.IsNullOrEmpty(value)) { kind = 0; cellText = ""; }
            else {
                // A value that is not a finite number keeps the file's text, NaN, INF and 1e999 included (.NET reads some of
                // them as non-finite doubles, which the grid would show as blank cells).
                if (!double.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out num) || !double.IsFinite(num)) { kind = 2; cellText = value; num = double.NaN; }
                else {
                    // Only the section of the number format that applies to this value counts (RULES 3.9, amendment 1).
                    byte format = style != null && int.TryParse(style, NumberStyles.None, CultureInfo.InvariantCulture, out var sx) && sx < package.StyleFormats.Count ? package.StyleFormats[sx].KindFor(num) : FormatNumber;
                    kind = 1; cellText = "";
                    // A number with date/time formatting can exceed that format's
                    // representable range. Keep the numeric value readable instead
                    // of rejecting the whole workbook because of its display style.
                    if (format != FormatNumber && TryDateTimeText(num, format, package.Date1904, out var timeKind, out var timeText)) { kind = timeKind; cellText = timeText; num = double.NaN; }
                }
            }
            if (kind == 0 && !hasFormula && extra.Length == 0) continue;
            if (cellText.Length == 0 && kind != 1) kind = 0;
            if (kind == 0 && valuesOnly) continue;   // empty text too, as the compatibility reader leaves it out
            int row0 = rowNumber - 1, col0 = colNumber - 1;
            if (row0 < 0 || col0 < 0 || row0 >= MaxRows || col0 >= MaxCols) continue;
            data.Column(col0).Add(row0, kind, num, cellText, formula, extra);
            count++; if (formula.Length > 0) formulaCount++;
            rows = Math.Max(rows, row0 + 1); cols = Math.Max(cols, col0 + 1);
        }
    }
    static FormulaRegion FormulaResultRegion(string reference) {
        if (reference == null || !Regex.IsMatch(reference, @"^\$?[A-Za-z]{1,3}\$?[1-9][0-9]{0,6}(?::\$?[A-Za-z]{1,3}\$?[1-9][0-9]{0,6})?\z"))
            return null;
        var ends = reference.Replace("$", "").Split(':');
        var (r1, c1) = ParseAddress(ends[0]); var (r2, c2) = ParseAddress(ends[^1]);
        if (r1 > MaxRows || r2 > MaxRows || c1 > MaxCols || c2 > MaxCols) return null;
        return new FormulaRegion(Math.Min(r1, r2) - 1, Math.Max(r1, r2) - 1, Math.Min(c1, c2) - 1, Math.Max(c1, c2) - 1);
    }
    // Concatenates the text runs of an <is> or <si> element (phonetic runs excluded). The
    // reader starts on the element and finishes on its end tag.
    static string ReadRichText(XmlReader reader) {
        var text = new StringBuilder(); int depth = reader.Depth;
        reader.Read();
        while (!reader.EOF && !(reader.NodeType == XmlNodeType.EndElement && reader.Depth == depth)) {
            if (reader.NodeType == XmlNodeType.Element) {
                if (reader.LocalName == "rPh") { reader.Skip(); continue; }
                if (reader.LocalName == "t") { text.Append(reader.ReadElementContentAsString()); continue; }
            }
            reader.Read();
        }
        return Unescape(text.ToString());
    }
    // Excel stores characters that XML cannot hold as _xHHHH_ (and a literal _x as _x005F_x).
    static readonly Regex Escaped = new(@"_x([0-9A-Fa-f]{4})_", RegexOptions.Compiled);
    public static string Unescape(string text) => text.Contains("_x") ? Escaped.Replace(text, m => ((char)Convert.ToInt32(m.Groups[1].Value, 16)).ToString()) : text;
    public static string Escape(string text) {
        bool clean = true;
        for (int i = 0; i < text.Length && clean; i++) {
            char ch = text[i];
            if (char.IsHighSurrogate(ch) && i + 1 < text.Length && char.IsLowSurrogate(text[i + 1])) { i++; continue; }
            if (!XmlConvert.IsXmlChar(ch)) clean = false;
        }
        if (clean) return text;
        var result = new StringBuilder(Escaped.Replace(text, m => "_x005F" + m.Value));
        var escaped = result.ToString(); result.Clear();
        for (int i = 0; i < escaped.Length; i++) {
            char ch = escaped[i];
            if (char.IsHighSurrogate(ch) && i + 1 < escaped.Length && char.IsLowSurrogate(escaped[i + 1])) { result.Append(ch).Append(escaped[++i]); continue; }
            if (XmlConvert.IsXmlChar(ch)) result.Append(ch); else result.Append("_x").Append(((int)ch).ToString("X4")).Append('_');
        }
        return result.ToString();
    }
    public static (int row, int col) ParseAddress(string address) {
        int col = 0, i = 0;
        while (i < address.Length && char.IsLetter(address[i])) { col = col * 26 + char.ToUpperInvariant(address[i]) - 'A' + 1; i++; }
        int row = int.TryParse(address.Substring(i), NumberStyles.None, CultureInfo.InvariantCulture, out var r) ? r : 0;
        return (row, col);
    }
    public static string ColumnName(int col) {  // 1-based
        var name = ""; while (col > 0) { col--; name = (char)('A' + col % 26) + name; col /= 26; } return name;
    }
    // The kind and text of a number shown with a date or time format (RULES 3.9, with the answers agreed with Windows on
    // 21 November 2026): a duration (kind 4) for an elapsed format; a time of day (kind 4) for a time format without a date
    // and a value from 0 up to one day; otherwise a date-time (kind 3). False when the value stays a number, as Excel shows
    // ##### for it: a duration of more days, of either sign, than the serial of the last day of its date system (9999-12-31);
    // a negative value in a date or time format; a date or date-time beyond that last day, or in the 1900 system before its
    // first day, 1900-01-01. A duration and a time of day are judged on the value itself, and only then rounded to the
    // millisecond, so 0.999999999 in h:mm:ss is a time of day that reads 1.00:00:00, which the grid writes as 24:00:00. A date or
    // date-time is judged rounded to the millisecond, as its text is, so 0.9999999999 in yyyy-mm-dd hh:mm:ss is 1900-01-01.
    static bool TryDateTimeText(double serial, byte format, bool date1904, out byte kind, out string text) {
        kind = 4; text = null;
        if (!double.IsFinite(serial)) return false;
        if (format == FormatElapsed) return !DurationBeyondLastDay(serial, date1904) && (text = DurationText(serial)) != null;
        if (serial < 0) return false;
        if (format == FormatTime && serial < 1) return (text = DurationText(serial)) != null;
        double ms = Milliseconds(serial);
        // The 1900 system's first day is serial 1, 1900-01-01: Excel shows serial 0 as 1900-01-00, so a value below one day in a
        // date or date-time format is a number (amendment 1 of the shared rules). The 1904 system's first day is serial 0.
        if (ms >= (LastDay(date1904) + 1) * MillisecondsPerDay || !date1904 && ms < MillisecondsPerDay) return false;
        kind = 3; text = SerialDateText((long)ms, date1904);
        return true;
    }
    const string LeapDay1900 = "1900-02-29";
    const double MillisecondsPerDay = 86_400_000d;
    // A serial number of days in whole milliseconds, rounded half away from zero, as every date-time, time of day and duration
    // is: half a millisecond is 00:00:00.001, and minus half a millisecond -00:00:00.001.
    static double Milliseconds(double days) => Math.Round(days * MillisecondsPerDay, MidpointRounding.AwayFromZero);
    static string DateText(DateTime dt) => dt.ToString("yyyy-MM-dd HH:mm:ss.fffffff", CultureInfo.InvariantCulture).TrimEnd('0').TrimEnd('.');
    static readonly DateTime OleEpoch = new(1899, 12, 30), Epoch1900 = new(1899, 12, 31), Epoch1904 = new(1904, 1, 1);
    // The date-time text of a whole number of milliseconds from serial 0, from the first day of the date system to its last.
    // Before 1 March 1900, Excel's serials are one more than OLE Automation dates: Excel's day 60 is 29 February 1900, which
    // never existed. Excel shows that date, and so does the text; DateTime cannot hold it. The day is the one the value rounds
    // to, so a value just below day 60 or 61 belongs to the next day.
    static string SerialDateText(long ms, bool date1904) {
        const long perDay = 86_400_000;
        if (date1904) return DateText(Epoch1904.AddTicks(ms * TimeSpan.TicksPerMillisecond));
        long day = ms / perDay;
        if (day == 60) return LeapDay1900 + DateText(new DateTime(1900, 3, 1).AddTicks((ms - 60 * perDay) * TimeSpan.TicksPerMillisecond)).Substring(10);
        return DateText((day < 60 ? Epoch1900 : OleEpoch).AddTicks(ms * TimeSpan.TicksPerMillisecond));
    }
    // A duration or time of day in .NET's "c" form, [-][d.]hh:mm:ss[.fffffff], rounded to the millisecond as date-times are
    // (TimeSpan.FromDays truncates to the 100 ns tick below, so 14:30 would read 14:29:59.9999999), and made from whole ticks, so
    // that a long duration keeps its exact milliseconds. Null beyond TimeSpan's range.
    static string DurationText(double days) {
        double ms = Milliseconds(days);
        return Math.Abs(ms) <= TimeSpan.MaxValue.Ticks / TimeSpan.TicksPerMillisecond ? ClockText((long)ms) : null;
    }
    static string ClockText(long ms) => new TimeSpan(ms * TimeSpan.TicksPerMillisecond).ToString("c", CultureInfo.InvariantCulture);
    // 9999-12-31 is the last day of either date system: serial 2,958,465 in the 1900 system and 2,957,003 in the 1904 system.
    const double LastDay1900 = 2_958_465, LastDay1904 = 2_957_003;
    static double LastDay(bool date1904) => date1904 ? LastDay1904 : LastDay1900;
    // A duration of more days than the last day's serial, of either sign, is a number (RULES 3.9), judged on the value itself:
    // 2958465.25 and -3000000 in [h]:mm:ss are numbers, and 2958465 is 71003160:00:00. Duration text the grid holds beyond it is
    // saved as its text, so that it reopens as it was written.
    static bool DurationBeyondLastDay(double days, bool date1904) => Math.Abs(days) > LastDay(date1904);
    // An ISO 8601 cell (t="d", as SheetJS and openpyxl write): the clock time as written, with a trailing Z or an offset read as
    // UTC, never moved into this Mac's time zone, and rounded to the millisecond, half away from zero, as every other date-time is.
    // A time with no date is a time of day, as a number below one day in a time format is: it is below one day, and only then
    // rounded, so 23:59:59.9996 is 1.00:00:00. Text that is no date stays text.
    static readonly Regex IsoTimeOnly = new(@"^\s*T?[0-9]{1,2}:[0-9]{2}", RegexOptions.Compiled | RegexOptions.CultureInvariant);
    static void IsoDateText(string value, out byte kind, out string text) {
        if (!DateTime.TryParse(value.Trim(), CultureInfo.InvariantCulture,
            DateTimeStyles.AdjustToUniversal | DateTimeStyles.AssumeUniversal | DateTimeStyles.NoCurrentDateDefault, out var date)) {
            kind = 2; text = value; return;
        }
        const long half = TimeSpan.TicksPerMillisecond / 2;
        if (IsoTimeOnly.IsMatch(value)) { kind = 4; text = ClockText((date.TimeOfDay.Ticks + half) / TimeSpan.TicksPerMillisecond); return; }
        long ticks = (date.Ticks + half) / TimeSpan.TicksPerMillisecond * TimeSpan.TicksPerMillisecond;
        kind = 3; text = DateText(ticks <= DateTime.MaxValue.Ticks ? new DateTime(ticks) : date);
    }
    // The serial number of date-time text as the grid holds it, in the workbook's date system (the inverse of TryDateTimeText).
    // The clock time is the one written, never moved by this Mac's time zone (R's date-times end in Z). 1900-02-29 is Excel's
    // day 60 in the 1900 system. False when the text is no date, or a date before the first day of the date system (serial 0:
    // 1899-12-31, which Excel shows as 1900-01-00, or 1904-01-01), which Excel cannot show as a date: such text is saved as
    // text rather than as a negative number or a failed save, so that it reopens as it was written.
    static bool TryDateSerial(string text, bool date1904, out double serial) {
        bool leapDay = !date1904 && text.StartsWith(LeapDay1900, StringComparison.Ordinal);
        serial = 0;
        if (!DateTime.TryParse(leapDay ? "1900-03-01" + text.Substring(LeapDay1900.Length) : text, CultureInfo.InvariantCulture,
            DateTimeStyles.AdjustToUniversal | DateTimeStyles.AssumeUniversal, out var date)) return false;
        serial = date.ToOADate();
        serial -= date1904 ? 1462 : leapDay || serial < 61 ? 1 : 0;
        return Milliseconds(serial) >= (date1904 ? 0 : MillisecondsPerDay);
    }
    // Duration text as the grid holds it: .NET's "c" form, [-][d.]hh:mm:ss[.fffffff], or hours past 23 with no day count
    // (26:00:00), which TimeSpan.Parse reads as 26 days. False for any other text, which is then saved as text.
    static readonly Regex Duration = new(@"^(-)?(?:([0-9]+)\.)?([0-9]+):([0-5][0-9]):([0-5][0-9])(?:\.([0-9]{1,7}))?$", RegexOptions.Compiled | RegexOptions.CultureInvariant);
    static bool TryDuration(string text, out TimeSpan span) {
        span = default;
        var m = Duration.Match(text);
        long days = 0, hours, fraction = 0;
        if (!m.Success || m.Groups[2].Success && !long.TryParse(m.Groups[2].Value, NumberStyles.None, CultureInfo.InvariantCulture, out days)
            || !long.TryParse(m.Groups[3].Value, NumberStyles.None, CultureInfo.InvariantCulture, out hours) || m.Groups[2].Success && hours > 23) return false;
        if (m.Groups[6].Success) fraction = long.Parse(m.Groups[6].Value.PadRight(7, '0'), CultureInfo.InvariantCulture);
        try {
            long ticks = checked((((days * 24 + hours) * 60 + int.Parse(m.Groups[4].Value, CultureInfo.InvariantCulture)) * 60 + int.Parse(m.Groups[5].Value, CultureInfo.InvariantCulture)) * TimeSpan.TicksPerSecond + fraction);
            span = new TimeSpan(m.Groups[1].Success ? -ticks : ticks);
            return true;
        } catch (OverflowException) { return false; }
    }
    static readonly Regex Reference = new(@"(?<![A-Za-z0-9_.$])(\$?)([A-Za-z]{1,3})(\$?)([0-9]{1,7})(?![A-Za-z0-9_(])", RegexOptions.Compiled);
    static readonly Regex ColumnRange = new(@"(?<![A-Za-z0-9_.$])(\$?)([A-Za-z]{1,3}):(\$?)([A-Za-z]{1,3})(?![A-Za-z0-9_(])", RegexOptions.Compiled);
    static readonly Regex RowRange = new(@"(?<![A-Za-z0-9_.$:])(\$?)([0-9]{1,7}):(\$?)([0-9]{1,7})(?![A-Za-z0-9_(:])", RegexOptions.Compiled);
    // Shared formulas are stored once; dependants shift the relative references of the master.
    public static string ShiftFormula(string formula, int dRow, int dCol) {
        if (dRow == 0 && dCol == 0) return formula;
        var result = new StringBuilder(); int i = 0;
        while (i < formula.Length) {
            if (formula[i] == '"') {
                int end = i + 1;
                while (end < formula.Length) { if (formula[end] == '"') { if (end + 1 < formula.Length && formula[end + 1] == '"') { end += 2; continue; } break; } end++; }
                end = Math.Min(end + 1, formula.Length); result.Append(formula, i, end - i); i = end; continue;
            }
            int next = formula.IndexOf('"', i); if (next < 0) next = formula.Length;
            var segment = ColumnRange.Replace(formula.Substring(i, next - i), m => {
                int c1 = ParseAddress(m.Groups[2].Value + "1").col, c2 = ParseAddress(m.Groups[4].Value + "1").col;
                if (m.Groups[1].Value.Length == 0) c1 += dCol;
                if (m.Groups[3].Value.Length == 0) c2 += dCol;
                if (c1 < 1 || c1 > MaxCols || c2 < 1 || c2 > MaxCols) return "#REF!";
                return m.Groups[1].Value + ColumnName(c1) + ":" + m.Groups[3].Value + ColumnName(c2);
            });
            segment = RowRange.Replace(segment, m => {
                int r1 = int.Parse(m.Groups[2].Value, CultureInfo.InvariantCulture), r2 = int.Parse(m.Groups[4].Value, CultureInfo.InvariantCulture);
                if (m.Groups[1].Value.Length == 0) r1 += dRow;
                if (m.Groups[3].Value.Length == 0) r2 += dRow;
                if (r1 < 1 || r1 > MaxRows || r2 < 1 || r2 > MaxRows) return "#REF!";
                return m.Groups[1].Value + r1.ToString(CultureInfo.InvariantCulture) + ":" + m.Groups[3].Value + r2.ToString(CultureInfo.InvariantCulture);
            });
            result.Append(Reference.Replace(segment, m => {
                var (r, c) = ParseAddress(m.Groups[2].Value + m.Groups[4].Value);
                if (m.Groups[1].Value.Length == 0) c += dCol;
                if (m.Groups[3].Value.Length == 0) r += dRow;
                if (c < 1 || c > MaxCols || r < 1 || r > MaxRows) return "#REF!";
                return m.Groups[1].Value + ColumnName(c) + m.Groups[3].Value + r.ToString(CultureInfo.InvariantCulture);
            }));
            i = next;
        }
        return result.ToString();
    }

    // ---- Save ------------------------------------------------------------------------
    static object Save(Request request) {
        if (!string.Equals(System.IO.Path.GetExtension(request.Path), ".xlsx", StringComparison.OrdinalIgnoreCase)) throw new Exception("Save the workbook with an .xlsx extension.");
        string source = null; long originalCells = 0;
        if (!string.IsNullOrEmpty(request.Id)) {
            if (dataCopies.TryGetValue(request.Id, out var importedPath)) {
                if (string.Equals(Path.GetFullPath(request.Path), importedPath, StringComparison.OrdinalIgnoreCase))
                    throw new Exception("Save the imported data under a new name to keep the original workbook intact.");
            } else {
                if (!originals.TryGetValue(request.Id, out var original) || !File.Exists(original.path)) throw new Exception("The source workbook is no longer open.");
                source = original.path; originalCells = original.cells;
            }
        }
        List<SheetData> sheets;
        if (request.Snapshot != null) { using var stream = File.OpenRead(request.Snapshot); sheets = ReadSnapshot(stream); }
        else sheets = (request.Sheets ?? new()).Select(p => FromCells(p.Name, p.Cells ?? new())).ToList();
        if (sheets.Count == 0) throw new Exception("There are no worksheets to save.");
        foreach (var sheet in sheets) foreach (var col in sheet.Columns.Values) foreach (var r in col.Rows) {
            if (r < 0 || r >= MaxRows || col.Col < 0 || col.Col >= MaxCols) throw new Exception("Cell is outside Excel's worksheet dimensions.");
        }
        var temporary = request.Path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        int uncached = 0, sheetCount = sheets.Count; bool recalculated = true;
        var inserts = (request.Inserts ?? new()).Where(i => i.Inserts != null && i.Inserts.Count > 0).ToList();
        string insertedSource = null;
        try {
            if (source == null) { using var stream = File.Create(temporary); WriteWorkbook(stream, sheets); }   // a new workbook already holds the cells where the grid put them
            else {
                long edits = sheets.Sum(s => s.Columns.Values.Sum(c => (long)c.Rows.Count));
                if (edits == 0 && inserts.Count == 0) {
                    CopyContents(source, temporary);
                    recalculated = false;
                } else {
                    string opened = source;
                    if (inserts.Count > 0) {
                        insertedSource = temporary + ".inserted.xlsx";
                        InsertWorkbookColumns(source, insertedSource, inserts, sheets);
                        source = insertedSource;
                    }
                    bool patched = false;
                    if (!request.Stream && edits + originalCells <= ClosedXmlCells && !NeedsExcelCalculation(source) && ClosedXmlCalculates(source)) {
                        // Inserting columns removes the saved result of every formula it writes, so ClosedXML's results
                        // are then compared with Excel's in the workbook as opened, whose formulas are the same ones.
                        if (insertedSource == null || ClosedXmlReproduces(opened)) { CopyContents(source, temporary); patched = PatchWithClosedXml(temporary, source, sheets, insertedSource == null); }
                    }
                    if (!patched) { uncached = PatchStreaming(source, temporary, sheets); recalculated = false; }
                }
                sheetCount = CountSheets(temporary);
            }
            File.Move(temporary, request.Path, true);
        } finally { if (File.Exists(temporary)) File.Delete(temporary); if (insertedSource != null && File.Exists(insertedSource)) File.Delete(insertedSource); }
        return new { ok = true, path = request.Path, sheets = sheetCount, uncachedFormulas = uncached, recalculated };
    }
    static int CountSheets(string path) { using var zip = ZipFile.OpenRead(path); return new Package(zip, true).Sheets.Count; }

    // Streaming writer for a new workbook: inline strings, no shared string table, one style
    // for dates and one for text, the first row frozen and twenty-character columns.
    static void WriteWorkbook(Stream output, List<SheetData> sheets) {
        using var zip = new ZipArchive(output, ZipArchiveMode.Create, true);
        var settings = new XmlWriterSettings { Encoding = new UTF8Encoding(false), OmitXmlDeclaration = false };
        void Part(string name, Action<XmlWriter> body) {
            using var stream = zip.CreateEntry(name, CompressionLevel.Optimal).Open();
            using var w = XmlWriter.Create(stream, settings); w.WriteStartDocument(true); body(w); w.WriteEndDocument();
        }
        Part("[Content_Types].xml", w => {
            w.WriteStartElement("Types", "http://schemas.openxmlformats.org/package/2006/content-types");
            w.WriteStartElement("Default"); w.WriteAttributeString("Extension", "rels"); w.WriteAttributeString("ContentType", "application/vnd.openxmlformats-package.relationships+xml"); w.WriteEndElement();
            w.WriteStartElement("Default"); w.WriteAttributeString("Extension", "xml"); w.WriteAttributeString("ContentType", "application/xml"); w.WriteEndElement();
            w.WriteStartElement("Override"); w.WriteAttributeString("PartName", "/xl/workbook.xml"); w.WriteAttributeString("ContentType", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"); w.WriteEndElement();
            w.WriteStartElement("Override"); w.WriteAttributeString("PartName", "/xl/styles.xml"); w.WriteAttributeString("ContentType", "application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"); w.WriteEndElement();
            for (int i = 0; i < sheets.Count; i++) { w.WriteStartElement("Override"); w.WriteAttributeString("PartName", $"/xl/worksheets/sheet{i + 1}.xml"); w.WriteAttributeString("ContentType", "application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"); w.WriteEndElement(); }
            w.WriteEndElement();
        });
        Part("_rels/.rels", w => {
            w.WriteStartElement("Relationships", PackageRel.NamespaceName);
            w.WriteStartElement("Relationship"); w.WriteAttributeString("Id", "rId1"); w.WriteAttributeString("Type", "http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument"); w.WriteAttributeString("Target", "xl/workbook.xml"); w.WriteEndElement();
            w.WriteEndElement();
        });
        Part("xl/workbook.xml", w => {
            w.WriteStartElement("workbook", MainNs); w.WriteAttributeString("xmlns", "r", null, Rel.NamespaceName);
            w.WriteStartElement("sheets");
            var names = SheetNames(sheets);
            for (int i = 0; i < sheets.Count; i++) { w.WriteStartElement("sheet"); w.WriteAttributeString("name", names[i]); w.WriteAttributeString("sheetId", (i + 1).ToString(CultureInfo.InvariantCulture)); w.WriteAttributeString("id", Rel.NamespaceName, $"rId{i + 1}"); w.WriteEndElement(); }
            w.WriteEndElement();
            w.WriteStartElement("calcPr"); w.WriteAttributeString("calcId", "191029"); w.WriteAttributeString("fullCalcOnLoad", "1"); w.WriteEndElement();
            w.WriteEndElement();
        });
        Part("xl/_rels/workbook.xml.rels", w => {
            w.WriteStartElement("Relationships", PackageRel.NamespaceName);
            for (int i = 0; i < sheets.Count; i++) { w.WriteStartElement("Relationship"); w.WriteAttributeString("Id", $"rId{i + 1}"); w.WriteAttributeString("Type", "http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet"); w.WriteAttributeString("Target", $"worksheets/sheet{i + 1}.xml"); w.WriteEndElement(); }
            w.WriteStartElement("Relationship"); w.WriteAttributeString("Id", $"rId{sheets.Count + 1}"); w.WriteAttributeString("Type", "http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles"); w.WriteAttributeString("Target", "styles.xml"); w.WriteEndElement();
            w.WriteEndElement();
        });
        Part("xl/styles.xml", w => WriteStyles(w));
        for (int i = 0; i < sheets.Count; i++) Part($"xl/worksheets/sheet{i + 1}.xml", w => WriteSheet(w, sheets[i], true));
    }
    const int DateStyle = 1, TextStyle = 2, DurationStyle = 3;
    static void WriteStyles(XmlWriter w) {
        w.WriteStartElement("styleSheet", MainNs);
        w.WriteStartElement("numFmts"); w.WriteAttributeString("count", "1");
        w.WriteStartElement("numFmt"); w.WriteAttributeString("numFmtId", "164"); w.WriteAttributeString("formatCode", "yyyy-mm-dd hh:mm:ss"); w.WriteEndElement();
        w.WriteEndElement();
        w.WriteStartElement("fonts"); w.WriteAttributeString("count", "1"); w.WriteStartElement("font"); w.WriteStartElement("sz"); w.WriteAttributeString("val", "11"); w.WriteEndElement(); w.WriteStartElement("name"); w.WriteAttributeString("val", "Calibri"); w.WriteEndElement(); w.WriteEndElement(); w.WriteEndElement();
        w.WriteStartElement("fills"); w.WriteAttributeString("count", "2");
        w.WriteStartElement("fill"); w.WriteStartElement("patternFill"); w.WriteAttributeString("patternType", "none"); w.WriteEndElement(); w.WriteEndElement();
        w.WriteStartElement("fill"); w.WriteStartElement("patternFill"); w.WriteAttributeString("patternType", "gray125"); w.WriteEndElement(); w.WriteEndElement();
        w.WriteEndElement();
        w.WriteStartElement("borders"); w.WriteAttributeString("count", "1"); w.WriteStartElement("border"); w.WriteStartElement("left"); w.WriteEndElement(); w.WriteStartElement("right"); w.WriteEndElement(); w.WriteStartElement("top"); w.WriteEndElement(); w.WriteStartElement("bottom"); w.WriteEndElement(); w.WriteStartElement("diagonal"); w.WriteEndElement(); w.WriteEndElement(); w.WriteEndElement();
        w.WriteStartElement("cellStyleXfs"); w.WriteAttributeString("count", "1"); w.WriteStartElement("xf"); w.WriteAttributeString("numFmtId", "0"); w.WriteAttributeString("fontId", "0"); w.WriteAttributeString("fillId", "0"); w.WriteAttributeString("borderId", "0"); w.WriteEndElement(); w.WriteEndElement();
        w.WriteStartElement("cellXfs"); w.WriteAttributeString("count", "4");
        foreach (var fmt in new[] { "0", "164", "49", "46" }) { w.WriteStartElement("xf"); w.WriteAttributeString("numFmtId", fmt); w.WriteAttributeString("fontId", "0"); w.WriteAttributeString("fillId", "0"); w.WriteAttributeString("borderId", "0"); w.WriteAttributeString("xfId", "0"); if (fmt != "0") w.WriteAttributeString("applyNumberFormat", "1"); w.WriteEndElement(); }
        w.WriteEndElement();
        w.WriteStartElement("cellStyles"); w.WriteAttributeString("count", "1"); w.WriteStartElement("cellStyle"); w.WriteAttributeString("name", "Normal"); w.WriteAttributeString("xfId", "0"); w.WriteAttributeString("builtinId", "0"); w.WriteEndElement(); w.WriteEndElement();
        w.WriteEndElement();
    }
    static string SheetName(string name, int index) {
        var clean = new string((name ?? "").Where(c => "[]:*?/\\".IndexOf(c) < 0 && !char.IsControl(c)).ToArray()).Trim();
        if (clean.Length == 0) clean = "Sheet " + (index + 1);
        return clean.Length > 31 ? clean.Substring(0, 31) : clean;
    }
    // Excel requires worksheet names to be unique ignoring case.
    static List<string> SheetNames(List<SheetData> sheets) {
        var used = new HashSet<string>(StringComparer.OrdinalIgnoreCase); var names = new List<string>();
        for (int i = 0; i < sheets.Count; i++) {
            var name = SheetName(sheets[i].Name, i);
            for (int n = 2; !used.Add(name); n++) { var suffix = " (" + n.ToString(CultureInfo.InvariantCulture) + ")"; var stem = SheetName(sheets[i].Name, i); name = (stem.Length + suffix.Length > 31 ? stem.Substring(0, 31 - suffix.Length) : stem) + suffix; }
            names.Add(name);
        }
        return names;
    }
    // Row-major view over the per-column cells of a sheet (rows and columns ascending).
    static IEnumerable<(int row, List<(int col, ColumnData data, int i)> cells)> RowsOf(SheetData sheet) {
        var cursors = sheet.Columns.Values.Select(c => (data: c, order: Enumerable.Range(0, c.Rows.Count).OrderBy(i => c.Rows[i]).ToArray(), at: 0)).ToArray();
        while (true) {
            int row = int.MaxValue;
            foreach (var cur in cursors) if (cur.at < cur.order.Length) row = Math.Min(row, cur.data.Rows[cur.order[cur.at]]);
            if (row == int.MaxValue) yield break;
            var cells = new List<(int, ColumnData, int)>();
            for (int k = 0; k < cursors.Length; k++) {
                ref var cur = ref cursors[k];
                while (cur.at < cur.order.Length && cur.data.Rows[cur.order[cur.at]] == row) { cells.Add((cur.data.Col, cur.data, cur.order[cur.at])); cur.at++; }
            }
            yield return (row, cells);
        }
    }
    static void WriteCellValue(XmlWriter w, ColumnData col, int i, string existingStyle, bool newWorkbook, bool date1904) {
        byte kind = col.Kinds[i]; string text = col.TextAt(i);
        string style = existingStyle;
        if (kind == 3 && (style == null || style == "0")) style = DateStyle.ToString(CultureInfo.InvariantCulture);
        if (newWorkbook && kind == 4 && style == null) style = DurationStyle.ToString(CultureInfo.InvariantCulture);
        if (newWorkbook && kind == 2 && style == null && LooksNumeric(text)) style = TextStyle.ToString(CultureInfo.InvariantCulture);
        if (style != null) w.WriteAttributeString("s", style);
        switch (kind) {
            case 0: return;
            case 1: w.WriteElementString("v", MainNs, col.Nums[i].ToString("R", CultureInfo.InvariantCulture)); return;
            case 5: w.WriteAttributeString("t", "b"); w.WriteElementString("v", MainNs, string.Equals(text, "TRUE", StringComparison.OrdinalIgnoreCase) ? "1" : "0"); return;
            case 6: w.WriteAttributeString("t", "e"); w.WriteElementString("v", MainNs, Escape(text)); return;
            // Date and duration text that Excel cannot hold as a number is saved as the text (default).
            case 3 when TryDateSerial(text, date1904, out var serial): w.WriteElementString("v", MainNs, serial.ToString("R", CultureInfo.InvariantCulture)); return;
            case 4 when TryDuration(text, out var span) && !DurationBeyondLastDay(span.TotalDays, date1904): w.WriteElementString("v", MainNs, span.TotalDays.ToString("R", CultureInfo.InvariantCulture)); return;
            default:
                w.WriteAttributeString("t", "inlineStr");
                w.WriteStartElement("is", MainNs); w.WriteStartElement("t", MainNs);
                if (text.Length > 0 && (char.IsWhiteSpace(text[0]) || char.IsWhiteSpace(text[^1]))) w.WriteAttributeString("xml", "space", null, "preserve");
                w.WriteString(Escape(text)); w.WriteEndElement(); w.WriteEndElement(); return;
        }
    }
    static bool LooksNumeric(string text) => text.Length > 0 && double.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out _);
    static void WriteSheet(XmlWriter w, SheetData sheet, bool newWorkbook) {
        w.WriteStartElement("worksheet", MainNs); w.WriteAttributeString("xmlns", "r", null, Rel.NamespaceName);
        int lastRow = 0, lastCol = 0;
        foreach (var col in sheet.Columns.Values) { lastCol = Math.Max(lastCol, col.Col + 1); if (col.Rows.Count > 0) lastRow = Math.Max(lastRow, col.Rows.Max() + 1); }
        w.WriteStartElement("dimension"); w.WriteAttributeString("ref", lastRow == 0 ? "A1" : "A1:" + ColumnName(lastCol) + lastRow.ToString(CultureInfo.InvariantCulture)); w.WriteEndElement();
        w.WriteStartElement("sheetViews"); w.WriteStartElement("sheetView"); w.WriteAttributeString("workbookViewId", "0");
        w.WriteStartElement("pane"); w.WriteAttributeString("ySplit", "1"); w.WriteAttributeString("topLeftCell", "A2"); w.WriteAttributeString("activePane", "bottomLeft"); w.WriteAttributeString("state", "frozen"); w.WriteEndElement();
        w.WriteEndElement(); w.WriteEndElement();
        w.WriteStartElement("sheetFormatPr"); w.WriteAttributeString("defaultRowHeight", "15"); w.WriteEndElement();
        w.WriteStartElement("cols"); w.WriteStartElement("col"); w.WriteAttributeString("min", "1"); w.WriteAttributeString("max", Math.Max(1, lastCol).ToString(CultureInfo.InvariantCulture)); w.WriteAttributeString("width", "20"); w.WriteAttributeString("customWidth", "1"); w.WriteEndElement(); w.WriteEndElement();
        w.WriteStartElement("sheetData");
        foreach (var (row, cells) in RowsOf(sheet)) {
            if (cells.All(c => c.data.Kinds[c.i] == 0)) continue;
            w.WriteStartElement("row"); w.WriteAttributeString("r", (row + 1).ToString(CultureInfo.InvariantCulture));
            foreach (var (col, data, i) in cells) {
                if (data.Kinds[i] == 0) continue;
                w.WriteStartElement("c"); w.WriteAttributeString("r", ColumnName(col + 1) + (row + 1).ToString(CultureInfo.InvariantCulture));
                WriteCellValue(w, data, i, null, newWorkbook, false); w.WriteEndElement();
            }
            w.WriteEndElement();
        }
        w.WriteEndElement();
        w.WriteEndElement();
    }

    // ---- Which patcher: whether ClosedXML can calculate every function the formulas call --
    // The first of two checks, made on the file before ClosedXML loads it; the second, ClosedXmlReproduces, compares
    // ClosedXML's results with Excel's.
    // The ClosedXML patcher writes ClosedXML's own result for every formula (PatchOriginal). A function it does not implement
    // comes out as #NAME?, and IFERROR, ISERROR and the like turn that into an ordinary value, such as 0 for
    // IFERROR(NORM.S.INV(0.975),0): neither is the result Excel saved, and a reopened workbook would send it to R and the
    // analyses as Excel's. Such a workbook goes to the streaming patcher, which keeps the formulas, removes their saved
    // results (reported as uncached) and leaves Excel to recalculate them. The functions are those called by any worksheet
    // formula, and by the defined names those formulas use (and the names those use), each read with its string literals,
    // quoted sheet names and bracketed parts (structured and external references) left out; a name nothing uses, such as a
    // chart's OFFSET range, does not count. A workbook of more than ClosedXmlFormulas formula cells is not calculated either.
    static readonly Regex FormulaFunction = new(@"(?<![\p{L}\p{N}_.\\?])([\p{L}_\\][\p{L}\p{N}_.\\?]*)\(", RegexOptions.Compiled | RegexOptions.CultureInvariant);
    static readonly Regex FormulaWord = new(@"(?<![\p{L}\p{N}_.\\?])[\p{L}_\\][\p{L}\p{N}_.\\?]*", RegexOptions.Compiled | RegexOptions.CultureInvariant);
    static readonly Regex FormulaLiteral = new(@"""(?:[^""]|"""")*""|'(?:[^']|'')*'|\[[^\[\]]*\]", RegexOptions.Compiled | RegexOptions.CultureInvariant);
    static readonly ConcurrentDictionary<string, bool> closedXmlFunctions = new(StringComparer.OrdinalIgnoreCase);
    // Called with no arguments, a function ClosedXML lacks gives #NAME?, while one it has refuses the call as too few
    // arguments, needs a cell to evaluate in, or gives its value. A call that fails any other way (LOG10() does) is made
    // again with one argument, and one that fails both ways counts as lacking. Each name is asked once.
    static bool ClosedXmlImplements(string function) => closedXmlFunctions.GetOrAdd(function, name => {
        foreach (var call in new[] { name + "()", name + "(1)" }) {
            try { var result = XLWorkbook.EvaluateExpr(call); return !(result.IsError && result.GetError() == XLError.NameNotRecognized); }
            catch (ClosedXML.Excel.CalcEngine.ExpressionParseException) { return true; }
            catch (InvalidOperationException) { return true; }
            catch (Exception) { }
        }
        return false;
    });
    static bool ClosedXmlCalculates(string path) {
        using var zip = ZipFile.OpenRead(path);
        var package = new Package(zip, true);
        // The defined names' formulas by name; a sheet's own name shares its name with the workbook's, and both are read.
        var names = new Dictionary<string, List<string>>(StringComparer.OrdinalIgnoreCase);
        foreach (var name in ReadXml(zip, "xl/workbook.xml").Root.Element(S + "definedNames")?.Elements(S + "definedName") ?? Enumerable.Empty<XElement>()) {
            var key = (string)name.Attribute("name") ?? "";
            if (!names.TryGetValue(key, out var formulas)) names[key] = formulas = new List<string>();
            formulas.Add(name.Value);
        }
        var functions = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var used = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var pending = new Queue<string>();
        void Read(string formula) {
            var text = FormulaLiteral.Replace(formula, "\"\"");
            foreach (Match m in FormulaFunction.Matches(text)) functions.Add(m.Groups[1].Value);
            if (names.Count > 0) foreach (Match m in FormulaWord.Matches(text)) if (names.ContainsKey(m.Value) && used.Add(m.Value)) pending.Enqueue(m.Value);
        }
        int formulaCells = 0;
        foreach (var sheet in package.Sheets) {
            var entry = Entry(zip, sheet.Entry);
            if (entry == null) continue;
            using var stream = entry.Open();
            using var reader = XmlReader.Create(stream);
            while (!reader.EOF) {
                if (reader.NodeType == XmlNodeType.Element && reader.LocalName == "f" && reader.NamespaceURI == MainNs) {
                    if (++formulaCells > ClosedXmlFormulas) return false;   // a cell of a shared formula has an <f> of its own
                    Read(reader.ReadElementContentAsString());   // leaves the reader on the node after the element
                } else reader.Read();
            }
        }
        while (pending.Count > 0) foreach (var formula in names[pending.Dequeue()]) Read(formula);
        return functions.All(ClosedXmlImplements);
    }

    // ---- Patch an opened workbook through ClosedXML (small workbooks) ------------------
    // Preserve the source package's styles, rich text and other worksheet features.
    // ClosedXML rewrites some inherited fonts on a full save of StatsDirect's test.xlsx.
    // Existing workbooks therefore receive cell patches, rather than a package rebuild.
    // False when ClosedXML cannot load the workbook, as with a NaN or 1e999 cell value written by another program, or
    // when its results cannot be trusted (ClosedXmlReproduces, and the evaluation in PatchOriginal): the lossless
    // streaming patcher then saves the workbook, and Excel recalculates.
    static bool PatchWithClosedXml(string temporary, string source, List<SheetData> sheets, bool compare) {
        XLWorkbook loaded;
        try { loaded = new XLWorkbook(source); } catch (ArgumentException) { return false; }
        using var workbook = loaded;
        if (compare && !ClosedXmlReproduces(workbook)) return false;
        var patches = new List<Patch>();
        foreach (var data in sheets) {
            if (!workbook.Worksheets.Contains(data.Name)) throw new Exception("The worksheet no longer exists in this workbook.");
            var sheet = workbook.Worksheet(data.Name);
            var cells = Cells(data).ToList();
            foreach (var edit in cells) {
                var cell = sheet.Cell(edit.Row + 1, edit.Col + 1);
                if (cell.HasFormula) throw new Exception($"{sheet.Name}!{cell.Address}: formula cells are read-only in this prototype.");
                // A date goes in as its serial number, as WriteCellValue writes it, so 1900-02-29 (Excel's day 60) needs no DateTime.
                cell.Value = edit.Kind switch {
                    "blank" => Blank.Value,
                    "number" => double.Parse(edit.Text, NumberStyles.Float, CultureInfo.InvariantCulture),
                    "boolean" => bool.Parse(edit.Text),
                    "datetime" => TryDateSerial(edit.Text, workbook.Use1904DateSystem, out var serial) ? (XLCellValue)serial : edit.Text,
                    "timespan" => TryDuration(edit.Text, out var span) && !DurationBeyondLastDay(span.TotalDays, workbook.Use1904DateSystem) ? (XLCellValue)span : edit.Text,
                    _ => XLCellValue.FromObject(edit.Text ?? "", CultureInfo.InvariantCulture)
                };
                if (edit.Kind == "datetime" && cell.Style.NumberFormat.NumberFormatId == 0) cell.Style.DateFormat.Format = "yyyy-mm-dd hh:mm:ss";
            }
            patches.Add(new Patch(data.Name, cells));
        }
        // Excel refreshes preserved formula expressions when it opens the exported workbook.
        workbook.CalculateMode = XLCalculateMode.Auto;
        workbook.FullCalculationOnLoad = true;
        workbook.ForceFullCalculation = true;
        return PatchOriginal(temporary, workbook, patches);
    }
    // ---- Which patcher: whether ClosedXML gives the results Excel saved -------------------
    // ClosedXML's functions and references are not all Excel's, and where they differ nothing fails: SUM(Table1[Value])
    // on another sheet than the table adds the wrong cells, ROUND(1.005,2) gives 1 where Excel gives 1.01, a number joined
    // to text keeps 17 digits where Excel keeps 15, and a range in a single-cell formula gives its first cell, not the one
    // in the formula's row. Saved after an edit, such a result would reach R and the analyses as Excel's. So before any
    // edit, ClosedXML recalculates the workbook as it was opened, and its results are kept only if every formula comes
    // out as Excel saved it: the same text, logical value or error, or a number equal to the 15 significant digits Excel
    // works to. A formula with no saved result gives nothing to compare, so it fails the check too, as does one ClosedXML
    // cannot evaluate, and one whose result changes with each calculation (TODAY, RAND). This is evidence, not proof: a
    // formula could agree before the edit and differ after it.
    static bool ClosedXmlReproduces(string path) {
        XLWorkbook loaded;
        try { loaded = new XLWorkbook(path); } catch (ArgumentException) { return false; }
        using var workbook = loaded;
        return ClosedXmlReproduces(workbook);
    }
    static bool ClosedXmlReproduces(XLWorkbook workbook) {
        var formulas = workbook.Worksheets.SelectMany(sheet => sheet.CellsUsed(XLCellsUsedOptions.Contents).Where(c => c.HasFormula)).ToList();
        var saved = new XLCellValue[formulas.Count];
        for (int i = 0; i < formulas.Count; i++) {
            if (formulas[i].NeedsRecalculation) return false;   // the file holds no result for this formula
            saved[i] = formulas[i].CachedValue;
            if (saved[i].IsBlank) return false;
        }
        foreach (var cell in formulas) cell.InvalidateFormula();
        for (int i = 0; i < formulas.Count; i++) {
            XLCellValue value;
            try { value = formulas[i].Value; } catch { return false; }
            if (!SameResult(saved[i], value)) return false;
        }
        return true;
    }
    static bool SameResult(XLCellValue saved, XLCellValue calculated) {
        // A date or a time is a number to Excel; ClosedXML types a saved one by its cell's format.
        if (saved.IsUnifiedNumber && calculated.IsUnifiedNumber) {
            double x = saved.GetUnifiedNumber(), y = calculated.GetUnifiedNumber();
            return x == y || x.ToString("G15", CultureInfo.InvariantCulture) == y.ToString("G15", CultureInfo.InvariantCulture);
        }
        if (saved.Type != calculated.Type) return false;
        return saved.Type switch {
            XLDataType.Text => saved.GetText() == calculated.GetText(),
            XLDataType.Boolean => saved.GetBoolean() == calculated.GetBoolean(),
            XLDataType.Error => saved.GetError() == calculated.GetError(),
            _ => false
        };
    }

    // False, with the file untouched, when ClosedXML cannot evaluate a formula after the edits.
    static bool PatchOriginal(string path, XLWorkbook workbook, List<Patch> patches) {
        foreach (var worksheet in workbook.Worksheets)
            foreach (var cell in worksheet.CellsUsed(XLCellsUsedOptions.Contents).Where(c => c.HasFormula)) cell.InvalidateFormula();
        // A formula ClosedXML cannot evaluate (a reference to another workbook, a three-dimensional or circular reference, a
        // result that is not a number) makes its calculation of the whole workbook fail: results are lost, and the formula
        // that failed can come back with its old result and no error. Then no result of this calculation is trusted, and
        // the caller saves by streaming instead, which leaves every formula for Excel to recalculate.
        foreach (var worksheet in workbook.Worksheets)
            foreach (var cell in worksheet.CellsUsed(XLCellsUsedOptions.Contents).Where(c => c.HasFormula)) {
                try { _ = cell.Value; } catch { return false; }
            }
        XNamespace s = S, rel = Rel, packageRel = PackageRel;
        using var zip = ZipFile.Open(path, ZipArchiveMode.Update);
        XDocument Read(string name) { using var stream = Entry(zip, name).Open(); return XDocument.Load(stream); }
        void Write(string name, XDocument doc) {
            Entry(zip, name)?.Delete();
            using var stream = zip.CreateEntry(name, CompressionLevel.Optimal).Open(); doc.Save(stream);
        }
        var bookXml = Read("xl/workbook.xml");
        var relationships = Read("xl/_rels/workbook.xml.rels").Root.Elements(packageRel + "Relationship")
            .ToDictionary(e => (string)e.Attribute("Id"), e => (string)e.Attribute("Target"));
        int dateStyle = -1, durationStyle = -1;
        bool dates = patches.Any(p => p.Cells.Any(c => c.Kind == "datetime")), durations = patches.Any(p => p.Cells.Any(c => c.Kind == "timespan"));
        if (dates || durations) {
            var stylesEntry = relationships.Values.Select(ResolveTarget).FirstOrDefault(e => Entry(zip, e) != null && e.EndsWith("styles.xml", StringComparison.OrdinalIgnoreCase));
            if (stylesEntry != null) {
                var styles = Read(stylesEntry); bool added = false;
                if (dates) dateStyle = EnsureFormatStyle(styles, 22, ref added);
                if (durations) durationStyle = EnsureFormatStyle(styles, 46, ref added);
                if (added) Write(stylesEntry, styles);
            }
        }
        foreach (var sheetInfo in bookXml.Root.Element(s + "sheets").Elements(s + "sheet")) {
            var name = (string)sheetInfo.Attribute("name");
            if (!workbook.Worksheets.TryGetWorksheet(name, out var sheet)) continue;
            var edits = patches.FirstOrDefault(p => p.Name == name)?.Cells ?? new List<Cell>();
            var formulas = sheet.CellsUsed(XLCellsUsedOptions.Contents).Where(c => c.HasFormula).ToList();
            if (edits.Count == 0 && formulas.Count == 0) continue;
            var target = relationships[(string)sheetInfo.Attribute(rel + "id")];
            var entry = ResolveTarget(target);
            var xml = Read(entry); var data = xml.Root.Element(s + "sheetData");
            var rows = new Dictionary<int, XElement>(); var cells = new Dictionary<(int, int), XElement>();
            int rowNumber = 0;
            foreach (var row in data.Elements(s + "row")) {
                rowNumber = (int?)row.Attribute("r") ?? rowNumber + 1;
                rows[rowNumber] = row; row.SetAttributeValue("r", rowNumber);
                int col = 0;
                foreach (var cell in row.Elements(s + "c")) {
                    var address = (string)cell.Attribute("r");
                    if (address == null) col++;
                    else { col = 0; foreach (char ch in address.TakeWhile(char.IsLetter)) col = col * 26 + char.ToUpperInvariant(ch) - 'A' + 1; }
                    cells[(rowNumber, col)] = cell;
                    cell.SetAttributeValue("r", sheet.Cell(rowNumber, col).Address.ToStringRelative());
                }
            }
            XElement Find(int r, int c) {
                if (cells.TryGetValue((r,c), out var existing)) return existing;
                if (!rows.TryGetValue(r, out var row)) {
                    row = new XElement(s + "row", new XAttribute("r", r));
                    var next = rows.Where(p => p.Key > r).OrderBy(p => p.Key).FirstOrDefault().Value;
                    if (next != null) next.AddBeforeSelf(row); else data.Add(row);
                    rows[r] = row;
                }
                var cell = new XElement(s + "c", new XAttribute("r", sheet.Cell(r,c).Address.ToStringRelative()));
                var nextCell = cells.Where(p => p.Key.Item1 == r && p.Key.Item2 > c).OrderBy(p => p.Key.Item2).FirstOrDefault().Value;
                if (nextCell != null) nextCell.AddBeforeSelf(cell); else row.Add(cell);
                cells[(r,c)] = cell; return cell;
            }
            void SetValue(XElement xmlCell, XLCellValue value, bool formula) {
                xmlCell.Element(s + "v")?.Remove(); xmlCell.Element(s + "is")?.Remove(); xmlCell.Attribute("t")?.Remove();
                string text;
                switch (value.Type) {
                    case XLDataType.Blank: return;
                    case XLDataType.Text:
                        if (formula) { xmlCell.SetAttributeValue("t", "str"); xmlCell.Add(new XElement(s + "v", value.GetText())); }
                        else { xmlCell.SetAttributeValue("t", "inlineStr"); xmlCell.Add(new XElement(s + "is", new XElement(s + "t", new XAttribute(XNamespace.Xml + "space", "preserve"), value.GetText()))); }
                        return;
                    case XLDataType.Boolean: xmlCell.SetAttributeValue("t", "b"); text = value.GetBoolean() ? "1" : "0"; break;
                    case XLDataType.Error: xmlCell.SetAttributeValue("t", "e"); text = value.ToString(CultureInfo.InvariantCulture); break;
                    case XLDataType.DateTime:
                        double serial = value.GetDateTime().ToOADate();
                        serial -= workbook.Use1904DateSystem ? 1462 : serial < 61 ? 1 : 0;
                        text = serial.ToString("R", CultureInfo.InvariantCulture); break;
                    case XLDataType.TimeSpan: text = value.GetTimeSpan().TotalDays.ToString("R", CultureInfo.InvariantCulture); break;
                    default: text = value.GetNumber().ToString("R", CultureInfo.InvariantCulture); break;
                }
                xmlCell.Add(new XElement(s + "v", text));
            }
            foreach (var edit in edits) {
                var xmlCell = Find(edit.Row+1, edit.Col+1);
                SetValue(xmlCell, edit.Kind == "text" ? (XLCellValue)edit.Text : sheet.Cell(edit.Row+1, edit.Col+1).Value, false);
                int formatStyle = edit.Kind == "datetime" ? dateStyle : edit.Kind == "timespan" ? durationStyle : -1;
                if (formatStyle >= 0 && ((string)xmlCell.Attribute("s") ?? "0") == "0") xmlCell.SetAttributeValue("s", formatStyle);
            }
            foreach (var cell in formulas) SetValue(Find(cell.Address.RowNumber, cell.Address.ColumnNumber), cell.Value, true);   // evaluated above
            var dimension = xml.Root.Element(s + "dimension");
            if (dimension != null && edits.Count > 0 && cells.Count > 0) {
                int lastRow = cells.Keys.Max(k => k.Item1), lastCol = cells.Keys.Max(k => k.Item2);
                dimension.SetAttributeValue("ref", "A1:" + sheet.Cell(lastRow, lastCol).Address.ToStringRelative());
            }
            Write(entry, xml);
        }
        var calc = bookXml.Root.Element(s + "calcPr");
        if (calc == null) { calc = new XElement(s + "calcPr"); bookXml.Root.Add(calc); }
        calc.SetAttributeValue("calcMode", "auto"); calc.SetAttributeValue("fullCalcOnLoad", "1"); calc.SetAttributeValue("forceFullCalc", "1");
        Write("xl/workbook.xml", bookXml);
        return true;
    }

    // Index of a cellXfs entry with a built-in number format (22 a date-time, 46 [h]:mm:ss), added
    // when none exists, for an edited date or duration in a cell of the General style. `added` is
    // set when the document changed.
    static int EnsureFormatStyle(XDocument styles, int numFmtId, ref bool added) {
        var xfs = styles.Root.Element(S + "cellXfs");
        if (xfs == null) { xfs = new XElement(S + "cellXfs"); styles.Root.Add(xfs); }
        var list = xfs.Elements(S + "xf").ToList();
        int index = list.FindIndex(x => ((int?)x.Attribute("numFmtId") ?? 0) == numFmtId);
        if (index >= 0) return index;
        xfs.Add(new XElement(S + "xf", new XAttribute("numFmtId", numFmtId), new XAttribute("fontId", 0), new XAttribute("fillId", 0), new XAttribute("borderId", 0), new XAttribute("xfId", 0), new XAttribute("applyNumberFormat", 1)));
        xfs.SetAttributeValue("count", list.Count + 1); added = true;
        return list.Count;
    }

    // ---- Patch an opened workbook by streaming (large workbooks) -----------------------
    // Each worksheet part is copied through an XmlReader/XmlWriter pair, merging the edited
    // cells in place. Cached formula results are removed and Excel recalculates on load,
    // because this path never evaluates formulas; the count is reported to the caller.
    // Result regions are read before any cells are patched: an array/spill or data-table child has no <f> of its own,
    // and can be absent from the XML altogether. The lookup keeps rectangles compact, caching merged row spans only
    // for columns actually visited while saving.
    static List<FormulaRegion> ReadFormulaResultRegions(ZipArchiveEntry entry, out bool requiresExcel) {
        var regions = new List<FormulaRegion>();
        requiresExcel = false;
        using var stream = entry.Open();
        using var reader = XmlReader.Create(stream);
        int sheetDataDepth = -1;
        bool inRow = false, inCell = false;
        while (reader.Read()) {
            if (reader.NodeType == XmlNodeType.EndElement && sheetDataDepth >= 0 && reader.Depth == sheetDataDepth) {
                sheetDataDepth = -1; inRow = false; inCell = false;
            }
            if (reader.NodeType != XmlNodeType.Element) continue;
            if (reader.LocalName == "extLst") requiresExcel = true;
            if (reader.Depth == 1 && reader.LocalName == "sheetData" && reader.NamespaceURI == MainNs) {
                sheetDataDepth = reader.IsEmptyElement ? -1 : reader.Depth;
                continue;
            }
            if (sheetDataDepth < 0) continue;
            if (reader.Depth == sheetDataDepth + 1) {
                inRow = reader.LocalName == "row" && reader.NamespaceURI == MainNs;
                inCell = false;
                continue;
            }
            if (reader.Depth == sheetDataDepth + 2) {
                inCell = inRow && reader.LocalName == "c" && reader.NamespaceURI == MainNs;
                continue;
            }
            if (reader.Depth != sheetDataDepth + 3 || !inCell || reader.LocalName != "f" || reader.NamespaceURI != MainNs
                || reader.GetAttribute("t") is not ("array" or "dataTable")) continue;
            requiresExcel = true;
            var region = FormulaResultRegion(reader.GetAttribute("ref"));
            if (region != null) regions.Add(region);
        }
        return regions;
    }
    static Func<int, int, bool> FormulaResultCoverage(ZipArchiveEntry entry) {
        var regions = ReadFormulaResultRegions(entry, out _);
        if (regions.Count == 0) return (_, _) => false;
        var columns = new Dictionary<int, List<(int first, int last)>>();
        bool Contains(int row, int column) {
            if (!columns.TryGetValue(column, out var spans)) {
                spans = new List<(int first, int last)>();
                foreach (var region in regions.Where(r => r.FirstColumn <= column && column <= r.LastColumn).OrderBy(r => r.FirstRow)) {
                    if (spans.Count > 0 && region.FirstRow <= spans[^1].last + 1)
                        spans[^1] = (spans[^1].first, Math.Max(spans[^1].last, region.LastRow));
                    else spans.Add((region.FirstRow, region.LastRow));
                }
                columns[column] = spans;
            }
            int first = 0, last = spans.Count - 1;
            while (first <= last) {
                int middle = first + (last - first) / 2;
                if (row < spans[middle].first) last = middle - 1;
                else if (row > spans[middle].last) first = middle + 1;
                else return true;
            }
            return false;
        }
        return Contains;
    }
    static int PatchStreaming(string sourcePath, string targetPath, List<SheetData> sheets) {
        var edits = sheets.ToDictionary(s => s.Name, s => s);
        int uncached = 0;
        using var source = ZipFile.OpenRead(sourcePath);
        var package = new Package(source, true);
        foreach (var name in edits.Keys) if (!package.Sheets.Any(s => s.Name == name)) throw new Exception("The worksheet no longer exists in this workbook.");
        var rels = ReadXml(source, "xl/_rels/workbook.xml.rels").Root.Elements(PackageRel + "Relationship").ToDictionary(e => (string)e.Attribute("Id"), e => (string)e.Attribute("Target"));
        var stylesEntry = rels.Values.Select(ResolveTarget).FirstOrDefault(e => Entry(source, e) != null && e.EndsWith("styles.xml", StringComparison.OrdinalIgnoreCase));
        var replaced = new Dictionary<string, XDocument>(StringComparer.OrdinalIgnoreCase);
        int dateStyle = -1, durationStyle = -1;
        bool dates = sheets.Any(s => s.Columns.Values.Any(c => c.Kinds.Contains((byte)3))), durations = sheets.Any(s => s.Columns.Values.Any(c => c.Kinds.Contains((byte)4)));
        if ((dates || durations) && stylesEntry != null) {
            var styles = ReadXml(source, stylesEntry); bool added = false;
            if (dates) dateStyle = EnsureFormatStyle(styles, 22, ref added);
            if (durations) durationStyle = EnsureFormatStyle(styles, 46, ref added);
            if (added) replaced[stylesEntry] = styles;
        }
        var book = ReadXml(source, "xl/workbook.xml");
        var calc = book.Root.Element(S + "calcPr");
        if (calc == null) { calc = new XElement(S + "calcPr"); book.Root.Add(calc); }
        calc.SetAttributeValue("calcMode", "auto"); calc.SetAttributeValue("fullCalcOnLoad", "1"); calc.SetAttributeValue("forceFullCalc", "1");
        replaced["xl/workbook.xml"] = book;
        var sheetParts = package.Sheets.ToDictionary(s => s.Entry, s => s, StringComparer.OrdinalIgnoreCase);
        using var output = new ZipArchive(File.Create(targetPath), ZipArchiveMode.Create, false);
        foreach (var entry in source.Entries) {
            if (entry.FullName.EndsWith("/")) continue;
            var target = output.CreateEntry(entry.FullName, CompressionLevel.Optimal);
            using var into = target.Open();
            if (replaced.TryGetValue(entry.FullName, out var doc)) { doc.Save(into); continue; }
            using var from = entry.Open();
            if (sheetParts.TryGetValue(entry.FullName, out var info)) {
                edits.TryGetValue(info.Name, out var sheet);
                var formulaResult = FormulaResultCoverage(entry);
                StreamSheet(from, into, sheet, info.Name, dateStyle, durationStyle, package.Date1904, formulaResult, ref uncached);
            } else from.CopyTo(into);
        }
        return uncached;
    }
    static XDocument ReadXml(ZipArchive zip, string name) { var entry = Entry(zip, name) ?? throw new Exception("The workbook is missing " + name + "."); using var stream = entry.Open(); return XDocument.Load(stream); }
    // Throws when an edit targets a formula cell. The reader advances exactly once per node:
    // XmlWriter.WriteNode leaves it on the node after the one copied, so nothing reads again
    // after it, and whitespace between rows and cells is dropped rather than copied.
    static void StreamSheet(Stream input, Stream output, SheetData sheet, string sheetName, int dateStyle, int durationStyle, bool date1904,
                            Func<int, int, bool> formulaResult, ref int uncached) {
        var pending = sheet == null ? new List<(int row, List<(int col, ColumnData data, int i)> cells)>() : RowsOf(sheet).ToList();
        foreach (var (row, cells) in pending) foreach (var (col, _, _) in cells) {
            if (formulaResult(row, col))
                throw new Exception($"{sheetName}!{ColumnName(col + 1)}{row + 1}: formula cells are read-only in this prototype.");
        }
        int pendingAt = 0, uncachedHere = 0;
        using var reader = XmlReader.Create(input, new XmlReaderSettings { IgnoreWhitespace = false });
        using var writer = XmlWriter.Create(output, new XmlWriterSettings { Encoding = new UTF8Encoding(false), OmitXmlDeclaration = false });
        string styleFor(ColumnData data, int i, string existing) {
            int formatStyle = data.Kinds[i] == 3 ? dateStyle : data.Kinds[i] == 4 ? durationStyle : -1;
            return formatStyle >= 0 && (existing == null || existing == "0") ? formatStyle.ToString(CultureInfo.InvariantCulture) : existing;
        }
        void WriteNewCell(int row, int col, ColumnData data, int i) {
            if (data.Kinds[i] == 0) return;
            writer.WriteStartElement("c", MainNs); writer.WriteAttributeString("r", ColumnName(col + 1) + (row + 1).ToString(CultureInfo.InvariantCulture));
            WriteCellValue(writer, data, i, styleFor(data, i, null), false, date1904); writer.WriteEndElement();
        }
        void WriteNewRow(int row, List<(int col, ColumnData data, int i)> cells) {
            if (cells.All(c => c.data.Kinds[c.i] == 0)) return;
            writer.WriteStartElement("row", MainNs); writer.WriteAttributeString("r", (row + 1).ToString(CultureInfo.InvariantCulture));
            foreach (var (col, data, i) in cells) WriteNewCell(row, col, data, i);
            writer.WriteEndElement();
        }
        bool IsWhitespace() => reader.NodeType == XmlNodeType.Whitespace || reader.NodeType == XmlNodeType.SignificantWhitespace;
        // Copies the <row> the reader is on, merging its edits; leaves the reader on the row's end tag (or on the empty element).
        void CopyRow(int rowNumber, List<(int col, ColumnData data, int i)> rowEdits) {
            bool rowEmpty = reader.IsEmptyElement; bool hadRowNumber = false;
            writer.WriteStartElement(reader.Prefix, "row", MainNs);
            if (reader.MoveToFirstAttribute()) {
                do {
                    if (reader.NamespaceURI.Length == 0 && reader.LocalName == "r") { hadRowNumber = true; writer.WriteAttributeString("r", rowNumber.ToString(CultureInfo.InvariantCulture)); }
                    else if (reader.NamespaceURI.Length == 0 && reader.LocalName == "spans" && rowEdits != null) { }
                    else writer.WriteAttributeString(reader.Prefix, reader.LocalName, reader.NamespaceURI, reader.Value);
                } while (reader.MoveToNextAttribute());
                reader.MoveToElement();
            }
            if (!hadRowNumber) writer.WriteAttributeString("r", rowNumber.ToString(CultureInfo.InvariantCulture));
            int editAt = 0, colNumber = 0;
            if (!rowEmpty) {
                int rowDepth = reader.Depth;
                bool inner = reader.Read();
                while (inner && !(reader.NodeType == XmlNodeType.EndElement && reader.Depth == rowDepth)) {
                    if (reader.NodeType == XmlNodeType.Element && reader.LocalName == "c" && reader.NamespaceURI == MainNs) {
                        var address = reader.GetAttribute("r");
                        if (address != null) { var (_, c) = ParseAddress(address); colNumber = c; } else colNumber++;
                        if (rowEdits != null) while (editAt < rowEdits.Count && rowEdits[editAt].col + 1 < colNumber) { WriteNewCell(rowNumber - 1, rowEdits[editAt].col, rowEdits[editAt].data, rowEdits[editAt].i); editAt++; }
                        var edit = rowEdits != null && editAt < rowEdits.Count && rowEdits[editAt].col + 1 == colNumber ? rowEdits[editAt++] : default;
                        CopyCell(reader, writer, rowNumber, colNumber, edit.data, edit.i, styleFor, date1904,
                                 formulaResult(rowNumber - 1, colNumber - 1), ref uncachedHere, sheetName);
                        inner = reader.Read();
                    } else if (IsWhitespace()) inner = reader.Read();
                    else { writer.WriteNode(reader, false); inner = !reader.EOF; }
                }
            }
            if (rowEdits != null) for (; editAt < rowEdits.Count; editAt++) WriteNewCell(rowNumber - 1, rowEdits[editAt].col, rowEdits[editAt].data, rowEdits[editAt].i);
            writer.WriteEndElement();
        }
        bool more = reader.Read();
        while (more) {
            if (reader.NodeType == XmlNodeType.Element && reader.LocalName == "sheetData" && reader.NamespaceURI == MainNs) {
                bool empty = reader.IsEmptyElement;
                writer.WriteStartElement(reader.Prefix, "sheetData", MainNs); writer.WriteAttributes(reader, false);
                int rowNumber = 0;
                if (!empty) {
                    int depth = reader.Depth;
                    more = reader.Read();
                    while (more && !(reader.NodeType == XmlNodeType.EndElement && reader.Depth == depth)) {
                        if (reader.NodeType == XmlNodeType.Element && reader.LocalName == "row" && reader.NamespaceURI == MainNs) {
                            rowNumber = int.TryParse(reader.GetAttribute("r"), NumberStyles.None, CultureInfo.InvariantCulture, out var rn) ? rn : rowNumber + 1;
                            while (pendingAt < pending.Count && pending[pendingAt].row + 1 < rowNumber) { WriteNewRow(pending[pendingAt].row, pending[pendingAt].cells); pendingAt++; }
                            var rowEdits = pendingAt < pending.Count && pending[pendingAt].row + 1 == rowNumber ? pending[pendingAt++].cells : null;
                            CopyRow(rowNumber, rowEdits);
                            more = reader.Read();
                        } else if (IsWhitespace()) more = reader.Read();
                        else { writer.WriteNode(reader, false); more = !reader.EOF; }
                    }
                }
                for (; pendingAt < pending.Count; pendingAt++) WriteNewRow(pending[pendingAt].row, pending[pendingAt].cells);
                writer.WriteEndElement();
                more = reader.Read();
                continue;
            }
            if (reader.NodeType == XmlNodeType.Element && reader.LocalName == "dimension" && reader.NamespaceURI == MainNs && sheet != null) {
                writer.WriteStartElement(reader.Prefix, "dimension", MainNs);
                int editRow = 0, editCol = 0;
                foreach (var col in sheet.Columns.Values) { editCol = Math.Max(editCol, col.Col + 1); if (col.Rows.Count > 0) editRow = Math.Max(editRow, col.Rows.Max() + 1); }
                var existing = reader.GetAttribute("ref") ?? "A1"; var end = existing.Contains(':') ? existing.Substring(existing.IndexOf(':') + 1) : existing;
                var (er, ec) = ParseAddress(end);
                writer.WriteAttributeString("ref", "A1:" + ColumnName(Math.Max(ec, editCol)) + Math.Max(er, editRow).ToString(CultureInfo.InvariantCulture));
                if (!reader.IsEmptyElement) { int d = reader.Depth; while (reader.Read() && !(reader.NodeType == XmlNodeType.EndElement && reader.Depth == d)) { } }
                writer.WriteEndElement();
                more = reader.Read();
                continue;
            }
            switch (reader.NodeType) {
                case XmlNodeType.Element:
                    writer.WriteStartElement(reader.Prefix, reader.LocalName, reader.NamespaceURI);
                    writer.WriteAttributes(reader, true);
                    if (reader.IsEmptyElement) writer.WriteEndElement();
                    break;
                case XmlNodeType.EndElement: writer.WriteFullEndElement(); break;
                case XmlNodeType.XmlDeclaration: writer.WriteStartDocument(); break;
                case XmlNodeType.ProcessingInstruction: writer.WriteProcessingInstruction(reader.Name, reader.Value); break;
                case XmlNodeType.Text: writer.WriteString(reader.Value); break;
                case XmlNodeType.Whitespace: case XmlNodeType.SignificantWhitespace: writer.WriteWhitespace(reader.Value); break;
                case XmlNodeType.CDATA: writer.WriteCData(reader.Value); break;
                case XmlNodeType.Comment: writer.WriteComment(reader.Value); break;
                case XmlNodeType.EntityReference: writer.WriteEntityRef(reader.Name); break;
                case XmlNodeType.DocumentType: writer.WriteDocType(reader.Name, reader.GetAttribute("PUBLIC"), reader.GetAttribute("SYSTEM"), reader.Value); break;
            }
            more = reader.Read();
        }
        uncached += uncachedHere;
    }
    // Copy one <c> element. With an edit, the value is replaced (style kept). Formula cells
    // lose their cached value so Excel recalculates; an edit on a formula cell is refused.
    static void CopyCell(XmlReader reader, XmlWriter writer, int rowNumber, int colNumber, ColumnData edit, int editIndex,
                         Func<ColumnData, int, string, string> styleFor, bool date1904, bool formulaResult, ref int uncached, string sheetName) {
        bool empty = reader.IsEmptyElement;
        var attributes = new List<(string prefix, string name, string ns, string value)>();
        if (reader.MoveToFirstAttribute()) { do attributes.Add((reader.Prefix, reader.LocalName, reader.NamespaceURI, reader.Value)); while (reader.MoveToNextAttribute()); reader.MoveToElement(); }
        // Read the children first so a formula is known before writing.
        var children = new List<(string name, List<(string prefix, string name, string ns, string value)> attrs, string text, string innerXml)>();
        if (!empty) {
            int depth = reader.Depth;
            reader.Read();
            while (!reader.EOF && !(reader.NodeType == XmlNodeType.EndElement && reader.Depth == depth)) {
                if (reader.NodeType != XmlNodeType.Element) { reader.Read(); continue; }
                var attrs = new List<(string, string, string, string)>();
                if (reader.MoveToFirstAttribute()) { do attrs.Add((reader.Prefix, reader.LocalName, reader.NamespaceURI, reader.Value)); while (reader.MoveToNextAttribute()); reader.MoveToElement(); }
                string name = reader.LocalName;
                if (name == "v" || name == "f") children.Add((name, attrs, reader.ReadElementContentAsString(), null));
                else children.Add((name, attrs, null, reader.ReadOuterXml()));
            }
        }
        bool hasFormula = children.Any(c => c.name == "f");
        bool invalidate = hasFormula || formulaResult;
        var address = ColumnName(colNumber) + rowNumber.ToString(CultureInfo.InvariantCulture);
        if (edit != null && invalidate) throw new Exception($"{sheetName}!{address}: formula cells are read-only in this prototype.");
        writer.WriteStartElement("c", MainNs);
        string style = attributes.FirstOrDefault(a => a.name == "s" && a.ns.Length == 0).value;
        if (edit != null) {
            foreach (var a in attributes) if (a.ns.Length == 0 && (a.name == "t" || a.name == "s" || a.name == "r")) continue; else writer.WriteAttributeString(a.prefix, a.name, a.ns, a.value);
            writer.WriteAttributeString("r", address);
            WriteCellValue(writer, edit, editIndex, styleFor(edit, editIndex, style), false, date1904);
            foreach (var c in children) if (c.name != "v" && c.name != "is" && c.name != "f") writer.WriteRaw(c.innerXml);
        } else {
            foreach (var a in attributes) {
                if (a.ns.Length == 0 && a.name == "r") { writer.WriteAttributeString("r", address); continue; }
                if (invalidate && a.ns.Length == 0 && a.name == "t") continue;
                writer.WriteAttributeString(a.prefix, a.name, a.ns, a.value);
            }
            if (attributes.All(a => a.name != "r")) writer.WriteAttributeString("r", address);
            foreach (var c in children) {
                if (invalidate && (c.name == "v" || c.name == "is")) continue;
                if (c.text != null) { writer.WriteStartElement(c.name, MainNs); foreach (var a in c.attrs) writer.WriteAttributeString(a.prefix, a.name, a.ns, a.value); writer.WriteString(c.text); writer.WriteEndElement(); }
                else writer.WriteRaw(c.innerXml);
            }
            if (invalidate) uncached++;
        }
        writer.WriteEndElement();
    }

    [UnmanagedCallersOnly]
    public static IntPtr Invoke(IntPtr input) => Marshal.StringToCoTaskMemUTF8(Execute(Marshal.PtrToStringUTF8(input) ?? "{}"));
    [UnmanagedCallersOnly]
    public static void Free(IntPtr result) => Marshal.FreeCoTaskMem(result);
}
