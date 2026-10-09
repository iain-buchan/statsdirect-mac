using System;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Collections.Generic;
using System.Collections.Concurrent;
using System.Globalization;
using System.Text;
using System.Text.Json;
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
// Saving writes a new workbook with a streaming XML writer. An opened workbook is patched:
// small workbooks through ClosedXML (which recalculates formulas and preserves styles),
// large ones by streaming each worksheet part and merging the edited cells, leaving Excel
// to recalculate formulas when it opens the file.
public static partial class WorkbookIO {
    // Above this many cells (original plus edits) a patch streams instead of loading ClosedXML.
    public const int ClosedXmlCells = 1000000;
    const int MaxRows = 1048576, MaxCols = 16384;
    static readonly ConcurrentDictionary<string, (string path, long cells)> originals = new();
    static WorkbookIO() {
        Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
        AppDomain.CurrentDomain.ProcessExit += (_, _) => { foreach (var original in originals.Values) { try { File.Delete(original.path); } catch { } } };
    }
    static readonly JsonSerializerOptions json = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase, PropertyNameCaseInsensitive = true };
    public sealed record Cell(int Col, int Row, string Text, string Kind, string Formula = "");
    public sealed record Sheet(string Name, int Rows, int Columns, bool Hidden, List<Cell> Cells, int Count, int FormulaCount, string Snapshot);
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
    // an extras string group of loader metadata follows each column's formulas; skipped here).
    // Sheet: name length u32, UTF-8 name, pad to 4, column count u32. Column: index u32,
    // cell count n u32, text count u32, formula count u32, rows u32[n], kinds u8[n], pad to 8,
    // numbers f64[n], then text and formula entries (cell ordinal u32, byte length u32, UTF-8),
    // each group padded to 4. Kinds: 0 blank, 1 number, 2 text, 3 datetime, 4 timespan,
    // 5 boolean, 6 error. A number cell carries its value; every other kind carries text.
    static readonly string[] KindNames = { "blank", "number", "text", "datetime", "timespan", "boolean", "error" };
    public sealed class ColumnData {
        public int Col;
        public readonly List<int> Rows = new();
        public readonly List<byte> Kinds = new();
        public readonly List<double> Nums = new();
        public readonly List<KeyValuePair<int, string>> Texts = new();
        public readonly List<KeyValuePair<int, string>> Formulas = new();
        public void Add(int row, byte kind, double num, string text, string formula) {
            int ordinal = Rows.Count;
            Rows.Add(row); Kinds.Add(kind); Nums.Add(num);
            if (kind != 1 && text.Length > 0) Texts.Add(new(ordinal, text));
            if (formula.Length > 0) Formulas.Add(new(ordinal, formula));
        }
        public string TextAt(int i) => Kinds[i] == 1 ? JsNumber(Nums[i]) : Texts.Count > 0 && Texts.BinarySearch(new(i, null), OrdinalOrder) is int k && k >= 0 ? Texts[k].Value : "";
        static readonly Comparer<KeyValuePair<int, string>> OrdinalOrder = Comparer<KeyValuePair<int, string>>.Create((a, b) => a.Key.CompareTo(b.Key));
    }
    public sealed class SheetData {
        public string Name;
        public readonly SortedDictionary<int, ColumnData> Columns = new();
        public ColumnData Column(int c) { if (!Columns.TryGetValue(c, out var d)) Columns[c] = d = new ColumnData { Col = c }; return d; }
    }
    static void Pad(BinaryWriter w, int align) { while (w.BaseStream.Position % align != 0) w.Write((byte)0); }
    public static void WriteSnapshot(Stream stream, IReadOnlyList<SheetData> sheets) {
        using var w = new BinaryWriter(stream, Encoding.UTF8, true);
        w.Write(0x4C4F4353u); w.Write(1u); w.Write((uint)sheets.Count); w.Write(0u);
        foreach (var sheet in sheets) {
            var name = Encoding.UTF8.GetBytes(sheet.Name ?? ""); w.Write((uint)name.Length); w.Write(name); Pad(w, 4);
            w.Write((uint)sheet.Columns.Count);
            foreach (var col in sheet.Columns.Values) {
                int n = col.Rows.Count;
                w.Write((uint)col.Col); w.Write((uint)n); w.Write((uint)col.Texts.Count); w.Write((uint)col.Formulas.Count);
                foreach (var r in col.Rows) w.Write((uint)r);
                w.Write(col.Kinds.ToArray()); Pad(w, 8);
                foreach (var x in col.Nums) w.Write(x);
                foreach (var group in new[] { col.Texts, col.Formulas }) {
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
            for (int i = 0; i < col.Rows.Count; i++)
                yield return new Cell(col.Col, col.Rows[i], col.TextAt(i), KindNames[col.Kinds[i]], formulas.TryGetValue(i, out var f) ? f : "");
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
    static object OpenXlsx(string path, string snapshotDir) {
        var id = Guid.NewGuid().ToString("N");
        var sheets = new List<Sheet>();
        var written = new List<string>();
        try {
        using (var zip = ZipFile.OpenRead(path)) {
            var package = new Package(zip);
            int index = 0;
            foreach (var info in package.Sheets) {
                var data = new SheetData { Name = info.Name };
                int count = 0, formulas = 0, rows = 0, cols = 0;
                ReadSheet(zip, package, info, data, ref count, ref formulas, ref rows, ref cols);
                string snapshot = null; List<Cell> cells;
                if (snapshotDir != null) {
                    Directory.CreateDirectory(snapshotDir);
                    snapshot = System.IO.Path.Combine(snapshotDir, $"{id}-{index}.sdcol");
                    written.Add(snapshot);
                    using var stream = File.Create(snapshot);
                    WriteSnapshot(stream, new[] { data });
                    cells = new List<Cell>();
                } else cells = Cells(data).ToList();
                sheets.Add(new Sheet(info.Name, rows, cols, info.Hidden, cells, count, formulas, snapshot));
                index++;
            }
        }
        if (sheets.Count == 0) throw new Exception("The workbook contains no worksheets.");
        // The original is kept as a private copy so later edits on disk do not change what is patched.
        var copy = System.IO.Path.Combine(snapshotDir ?? System.IO.Path.GetTempPath(), $"statsdirect-workbook-{id}.xlsx");
        written.Add(copy);
        File.Copy(path, copy, true); originals[id] = (copy, sheets.Sum(x => (long)x.Count));
        return new { id, name = System.IO.Path.GetFileName(path), sheets, formulaCount = sheets.Sum(s => s.FormulaCount), cellCount = sheets.Sum(s => s.Count) };
        } catch { foreach (var file in written) { try { File.Delete(file); } catch { } } throw; }
    }

    sealed class SheetInfo { public string Name; public string Entry; public bool Hidden; }
    // Part names in a package are case-insensitive and relationship targets are percent-encoded.
    static ZipArchiveEntry Entry(ZipArchive zip, string name) =>
        zip.GetEntry(name) ?? zip.Entries.FirstOrDefault(e => string.Equals(e.FullName, name, StringComparison.OrdinalIgnoreCase));
    static string ResolveTarget(string target) => Uri.UnescapeDataString(new Uri(new Uri("http://xlsx/xl/workbook.xml"), target).AbsolutePath.TrimStart('/'));
    sealed class Package {
        public readonly List<SheetInfo> Sheets = new();
        public readonly List<string> SharedStrings = new();
        public readonly List<byte> StyleKinds = new();   // per cellXfs index: 1 number, 3 datetime, 4 timespan
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
                StyleKinds.Add(FormatKind(id, custom.TryGetValue(id, out var code) ? code : null));
            }
        }
    }
    // Excel's built-in date and time formats, and custom codes with date or time tokens.
    public static byte FormatKind(int id, string code) {
        if (code == null) {
            if (id is 45 or 46 or 47) return 4;
            if ((id >= 14 && id <= 22) || (id >= 27 && id <= 36) || (id >= 50 && id <= 58)) return 3;
            return 1;
        }
        bool elapsed = false, date = false, time = false, quoted = false;
        for (int i = 0; i < code.Length; i++) {
            char ch = code[i];
            if (quoted) { if (ch == '"') quoted = false; continue; }
            if (ch == '"') { quoted = true; continue; }
            if (ch == '\\') { i++; continue; }
            if (ch == '[') {
                int end = code.IndexOf(']', i); if (end < 0) end = code.Length - 1;
                var inner = code.Substring(i + 1, end - i - 1).ToLowerInvariant();
                if (inner.Length > 0 && inner.All(c => c == 'h' || c == 'm' || c == 's')) elapsed = true;
                i = end; continue;
            }
            char l = char.ToLowerInvariant(ch);
            if (l == 'y' || l == 'd' || l == 'm') date = true;
            if (l == 'h' || l == 's') time = true;
        }
        if (elapsed) return 4;
        if (date || time) return 3;
        return 1;
    }
    static void ReadSheet(ZipArchive zip, Package package, SheetInfo info, SheetData data, ref int count, ref int formulaCount, ref int rows, ref int cols) {
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
            if (hasFormula && formula.Length == 0) formula = "=";  // a formula without text still protects the cell
            byte kind; double num = double.NaN; string cellText;
            if (type == "s") { kind = 2; cellText = value != null && int.TryParse(value, NumberStyles.None, CultureInfo.InvariantCulture, out var si) && si < package.SharedStrings.Count ? package.SharedStrings[si] : ""; }
            else if (type == "inlineStr") { kind = 2; cellText = inline ?? ""; }
            else if (type == "str") { kind = 2; cellText = Unescape(value ?? ""); }
            else if (type == "b") { kind = 5; cellText = value == "1" ? "TRUE" : value == "0" ? "FALSE" : value ?? ""; if (cellText.Length == 0) kind = 0; }
            else if (type == "e") { kind = 6; cellText = value ?? ""; }
            else if (type == "d") { kind = 3; cellText = DateTime.TryParse(value, CultureInfo.InvariantCulture, DateTimeStyles.None, out var dt) ? DateText(dt) : value ?? ""; }
            else if (string.IsNullOrEmpty(value)) { kind = 0; cellText = ""; }
            else {
                if (!double.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out num)) { kind = 2; cellText = value; }
                else {
                    byte styleKind = style != null && int.TryParse(style, NumberStyles.None, CultureInfo.InvariantCulture, out var sx) && sx < package.StyleKinds.Count ? package.StyleKinds[sx] : (byte)1;
                    kind = 1; cellText = "";
                    // A number with date/time formatting can exceed that format's
                    // representable range. Keep the numeric value readable instead
                    // of rejecting the whole workbook because of its display style.
                    if (styleKind == 3) {
                        try { cellText = DateText(SerialToDate(num, package.Date1904)); kind = 3; num = double.NaN; }
                        catch (ArgumentException) { }
                    } else if (styleKind == 4) {
                        try { cellText = TimeSpan.FromDays(num).ToString("c", CultureInfo.InvariantCulture); kind = 4; num = double.NaN; }
                        catch (OverflowException) { }
                    }
                }
            }
            if (kind == 0 && !hasFormula) continue;
            if (cellText.Length == 0 && kind != 1) kind = 0;
            int row0 = rowNumber - 1, col0 = colNumber - 1;
            if (row0 < 0 || col0 < 0 || row0 >= MaxRows || col0 >= MaxCols) continue;
            data.Column(col0).Add(row0, kind, num, cellText, formula);
            count++; if (formula.Length > 0) formulaCount++;
            rows = Math.Max(rows, row0 + 1); cols = Math.Max(cols, col0 + 1);
        }
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
    static DateTime SerialToDate(double serial, bool date1904) {
        if (date1904) serial += 1462; else if (serial < 61) serial += 1;
        serial = Math.Max(serial, 1); return DateTime.FromOADate(serial);
    }
    static string DateText(DateTime dt) => dt.ToString("yyyy-MM-dd HH:mm:ss.fffffff", CultureInfo.InvariantCulture).TrimEnd('0').TrimEnd('.');
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
                if (inserts.Count > 0) {
                    insertedSource = temporary + ".inserted.xlsx";
                    InsertWorkbookColumns(source, insertedSource, inserts);
                    source = insertedSource;
                }
                if (!request.Stream && edits + originalCells <= ClosedXmlCells) { File.Copy(source, temporary, true); uncached = PatchWithClosedXml(temporary, source, sheets); }
                else { uncached = PatchStreaming(source, temporary, sheets); recalculated = false; }
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
    const int DateStyle = 1, TextStyle = 2;
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
        w.WriteStartElement("cellXfs"); w.WriteAttributeString("count", "3");
        foreach (var fmt in new[] { "0", "164", "49" }) { w.WriteStartElement("xf"); w.WriteAttributeString("numFmtId", fmt); w.WriteAttributeString("fontId", "0"); w.WriteAttributeString("fillId", "0"); w.WriteAttributeString("borderId", "0"); w.WriteAttributeString("xfId", "0"); if (fmt != "0") w.WriteAttributeString("applyNumberFormat", "1"); w.WriteEndElement(); }
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
        if (newWorkbook && kind == 2 && style == null && LooksNumeric(text)) style = TextStyle.ToString(CultureInfo.InvariantCulture);
        if (style != null) w.WriteAttributeString("s", style);
        switch (kind) {
            case 0: return;
            case 1: w.WriteElementString("v", MainNs, col.Nums[i].ToString("R", CultureInfo.InvariantCulture)); return;
            case 5: w.WriteAttributeString("t", "b"); w.WriteElementString("v", MainNs, string.Equals(text, "TRUE", StringComparison.OrdinalIgnoreCase) ? "1" : "0"); return;
            case 6: w.WriteAttributeString("t", "e"); w.WriteElementString("v", MainNs, Escape(text)); return;
            case 3: {
                var dt = DateTime.Parse(text, CultureInfo.InvariantCulture, DateTimeStyles.None);
                double serial = dt.ToOADate(); serial -= date1904 ? 1462 : serial < 61 ? 1 : 0;
                w.WriteElementString("v", MainNs, serial.ToString("R", CultureInfo.InvariantCulture)); return;
            }
            case 4: w.WriteElementString("v", MainNs, TimeSpan.Parse(text, CultureInfo.InvariantCulture).TotalDays.ToString("R", CultureInfo.InvariantCulture)); return;
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

    // ---- Patch an opened workbook through ClosedXML (small workbooks) ------------------
    // Preserve the source package's styles, rich text and other worksheet features.
    // ClosedXML rewrites some inherited fonts on a full save of StatsDirect's test.xlsx.
    // Existing workbooks therefore receive cell patches, rather than a package rebuild.
    static int PatchWithClosedXml(string temporary, string source, List<SheetData> sheets) {
        using var workbook = new XLWorkbook(source);
        var patches = new List<Patch>();
        foreach (var data in sheets) {
            if (!workbook.Worksheets.Contains(data.Name)) throw new Exception("The worksheet no longer exists in this workbook.");
            var sheet = workbook.Worksheet(data.Name);
            var cells = Cells(data).ToList();
            foreach (var edit in cells) {
                var cell = sheet.Cell(edit.Row + 1, edit.Col + 1);
                if (cell.HasFormula) throw new Exception($"{sheet.Name}!{cell.Address}: formula cells are read-only in this prototype.");
                cell.Value = edit.Kind switch {
                    "blank" => Blank.Value,
                    "number" => double.Parse(edit.Text, NumberStyles.Float, CultureInfo.InvariantCulture),
                    "boolean" => bool.Parse(edit.Text),
                    "datetime" => DateTime.Parse(edit.Text, CultureInfo.InvariantCulture, DateTimeStyles.None),
                    "timespan" => TimeSpan.Parse(edit.Text, CultureInfo.InvariantCulture),
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
    static int PatchOriginal(string path, XLWorkbook workbook, List<Patch> patches) {
        foreach (var worksheet in workbook.Worksheets)
            foreach (var cell in worksheet.CellsUsed(XLCellsUsedOptions.Contents).Where(c => c.HasFormula)) cell.InvalidateFormula();
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
        int uncached = 0, dateStyle = -1;
        if (patches.Any(p => p.Cells.Any(c => c.Kind == "datetime"))) {
            var stylesEntry = relationships.Values.Select(ResolveTarget).FirstOrDefault(e => Entry(zip, e) != null && e.EndsWith("styles.xml", StringComparison.OrdinalIgnoreCase));
            if (stylesEntry != null) { var styles = Read(stylesEntry); dateStyle = EnsureDateStyle(styles, out var added); if (added) Write(stylesEntry, styles); }
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
                if (edit.Kind == "datetime" && dateStyle >= 0 && ((string)xmlCell.Attribute("s") ?? "0") == "0") xmlCell.SetAttributeValue("s", dateStyle);
            }
            foreach (var cell in formulas) {
                XLCellValue value;
                try { value = cell.Value; } catch { value = Blank.Value; uncached++; }
                var xmlCell = Find(cell.Address.RowNumber, cell.Address.ColumnNumber);
                SetValue(xmlCell, value, true);
            }
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
        return uncached;
    }

    // Index of a cellXfs entry with a date-time format (numFmtId 22), added when none exists.
    // Returns -1 when the document has no cellXfs to extend. `added` reports whether it changed.
    static int EnsureDateStyle(XDocument styles, out bool added) {
        added = false;
        var xfs = styles.Root.Element(S + "cellXfs");
        if (xfs == null) { xfs = new XElement(S + "cellXfs"); styles.Root.Add(xfs); }
        var list = xfs.Elements(S + "xf").ToList();
        int index = list.FindIndex(x => ((int?)x.Attribute("numFmtId") ?? 0) == 22);
        if (index >= 0) return index;
        xfs.Add(new XElement(S + "xf", new XAttribute("numFmtId", 22), new XAttribute("fontId", 0), new XAttribute("fillId", 0), new XAttribute("borderId", 0), new XAttribute("xfId", 0), new XAttribute("applyNumberFormat", 1)));
        xfs.SetAttributeValue("count", list.Count + 1); added = true;
        return list.Count;
    }

    // ---- Patch an opened workbook by streaming (large workbooks) -----------------------
    // Each worksheet part is copied through an XmlReader/XmlWriter pair, merging the edited
    // cells in place. Cached formula results are removed and Excel recalculates on load,
    // because this path never evaluates formulas; the count is reported to the caller.
    static int PatchStreaming(string sourcePath, string targetPath, List<SheetData> sheets) {
        var edits = sheets.ToDictionary(s => s.Name, s => s);
        int uncached = 0;
        using var source = ZipFile.OpenRead(sourcePath);
        var package = new Package(source, true);
        foreach (var name in edits.Keys) if (!package.Sheets.Any(s => s.Name == name)) throw new Exception("The worksheet no longer exists in this workbook.");
        var rels = ReadXml(source, "xl/_rels/workbook.xml.rels").Root.Elements(PackageRel + "Relationship").ToDictionary(e => (string)e.Attribute("Id"), e => (string)e.Attribute("Target"));
        var stylesEntry = rels.Values.Select(ResolveTarget).FirstOrDefault(e => Entry(source, e) != null && e.EndsWith("styles.xml", StringComparison.OrdinalIgnoreCase));
        var replaced = new Dictionary<string, XDocument>(StringComparer.OrdinalIgnoreCase);
        int dateStyle = -1;
        if (sheets.Any(s => s.Columns.Values.Any(c => c.Kinds.Contains((byte)3))) && stylesEntry != null) {
            var styles = ReadXml(source, stylesEntry);
            dateStyle = EnsureDateStyle(styles, out var added);
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
                StreamSheet(from, into, sheet, info.Name, dateStyle, package.Date1904, ref uncached);
            } else from.CopyTo(into);
        }
        return uncached;
    }
    static XDocument ReadXml(ZipArchive zip, string name) { var entry = Entry(zip, name) ?? throw new Exception("The workbook is missing " + name + "."); using var stream = entry.Open(); return XDocument.Load(stream); }
    // Throws when an edit targets a formula cell. The reader advances exactly once per node:
    // XmlWriter.WriteNode leaves it on the node after the one copied, so nothing reads again
    // after it, and whitespace between rows and cells is dropped rather than copied.
    static void StreamSheet(Stream input, Stream output, SheetData sheet, string sheetName, int dateStyle, bool date1904, ref int uncached) {
        var pending = sheet == null ? new List<(int row, List<(int col, ColumnData data, int i)> cells)>() : RowsOf(sheet).ToList();
        int pendingAt = 0, uncachedHere = 0;
        using var reader = XmlReader.Create(input, new XmlReaderSettings { IgnoreWhitespace = false });
        using var writer = XmlWriter.Create(output, new XmlWriterSettings { Encoding = new UTF8Encoding(false), OmitXmlDeclaration = false });
        string styleFor(ColumnData data, int i, string existing) => data.Kinds[i] == 3 && (existing == null || existing == "0") && dateStyle >= 0 ? dateStyle.ToString(CultureInfo.InvariantCulture) : existing;
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
                        CopyCell(reader, writer, rowNumber, colNumber, edit.data, edit.i, styleFor, date1904, ref uncachedHere, sheetName);
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
    static void CopyCell(XmlReader reader, XmlWriter writer, int rowNumber, int colNumber, ColumnData edit, int editIndex, Func<ColumnData, int, string, string> styleFor, bool date1904, ref int uncached, string sheetName) {
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
        var address = ColumnName(colNumber) + rowNumber.ToString(CultureInfo.InvariantCulture);
        if (edit != null && hasFormula) throw new Exception($"{sheetName}!{address}: formula cells are read-only in this prototype.");
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
                if (hasFormula && a.ns.Length == 0 && a.name == "t") continue;
                writer.WriteAttributeString(a.prefix, a.name, a.ns, a.value);
            }
            if (attributes.All(a => a.name != "r")) writer.WriteAttributeString("r", address);
            foreach (var c in children) {
                if (hasFormula && (c.name == "v" || c.name == "is")) continue;
                if (c.text != null) { writer.WriteStartElement(c.name, MainNs); foreach (var a in c.attrs) writer.WriteAttributeString(a.prefix, a.name, a.ns, a.value); writer.WriteString(c.text); writer.WriteEndElement(); }
                else writer.WriteRaw(c.innerXml);
            }
            if (hasFormula) uncached++;
        }
        writer.WriteEndElement();
    }

    [UnmanagedCallersOnly]
    public static IntPtr Invoke(IntPtr input) => Marshal.StringToCoTaskMemUTF8(Execute(Marshal.PtrToStringUTF8(input) ?? "{}"));
    [UnmanagedCallersOnly]
    public static void Free(IntPtr result) => Marshal.FreeCoTaskMem(result);
}
