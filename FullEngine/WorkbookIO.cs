using System;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Collections.Generic;
using System.Collections.Concurrent;
using System.Globalization;
using System.Text.Json;
using System.Runtime.InteropServices;
using System.Xml.Linq;
using ClosedXML.Excel;

// Host file I/O only. The vendored StatsDirect calculation layer is unchanged.
public static class WorkbookIO {
    const int MaxCells = 500000;
    static readonly ConcurrentDictionary<string, byte[]> originals = new();
    static readonly JsonSerializerOptions json = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase, PropertyNameCaseInsensitive = true };
    public sealed record Cell(int Col, int Row, string Text, string Kind, string Formula = "");
    public sealed record Sheet(string Name, int Rows, int Columns, bool Hidden, List<Cell> Cells);
    public sealed record Patch(string Name, List<Cell> Cells);
    public sealed record Request(string Action, string Path, string Id, List<Patch> Sheets);

    public static string Execute(string input) {
        try {
            var request = JsonSerializer.Deserialize<Request>(input, json) ?? throw new Exception("Missing workbook request.");
            object result = request.Action switch {
                "open" => Open(request.Path),
                "save" => Save(request),
                "close" => new { ok = originals.TryRemove(request.Id ?? "", out _) },
                _ => throw new Exception("Unknown workbook action.")
            };
            return JsonSerializer.Serialize(result, json);
        } catch (Exception ex) { return JsonSerializer.Serialize(new { error = ex.Message }, json); }
    }

    static object Open(string path) {
        if (!string.Equals(System.IO.Path.GetExtension(path), ".xlsx", StringComparison.OrdinalIgnoreCase))
            throw new Exception("Choose an .xlsx workbook. Legacy .xls and .xlsb files are not supported yet.");
        if (new FileInfo(path).Length > 50 * 1024 * 1024) throw new Exception("This prototype opens workbooks up to 50 MB.");
        var bytes = File.ReadAllBytes(path);
        using (var archive = new ZipArchive(new MemoryStream(bytes), ZipArchiveMode.Read)) {
            if (archive.Entries.Sum(e => e.Length) > 256L * 1024 * 1024) throw new Exception("This workbook expands beyond the prototype's 256 MB limit.");
        }
        using var workbook = new XLWorkbook(new MemoryStream(bytes));
        if (workbook.Worksheets.Count > 128) throw new Exception("This prototype opens up to 128 worksheets.");
        var sheets = new List<Sheet>();
        int total = 0;
        foreach (var sheet in workbook.Worksheets) {
            var cells = new List<Cell>();
            int rows = 0, cols = 0;
            foreach (var cell in sheet.CellsUsed(XLCellsUsedOptions.Contents)) {
                if (++total > MaxCells) throw new Exception("This prototype opens up to 500,000 populated cells per workbook.");
                int r = cell.Address.RowNumber - 1, c = cell.Address.ColumnNumber - 1;
                rows = Math.Max(rows, r + 1); cols = Math.Max(cols, c + 1);
                // Read the saved formula result. Do not silently substitute a different calculation engine.
                var value = cell.CachedValue;
                string kind = value.Type.ToString().ToLowerInvariant();
                string text = value.Type switch {
                    XLDataType.Blank => "",
                    XLDataType.Number => value.GetNumber().ToString("R", CultureInfo.InvariantCulture),
                    XLDataType.DateTime => value.GetDateTime().ToString("yyyy-MM-dd HH:mm:ss.fffffff", CultureInfo.InvariantCulture).TrimEnd('0').TrimEnd('.'),
                    XLDataType.TimeSpan => value.GetTimeSpan().ToString("c", CultureInfo.InvariantCulture),
                    XLDataType.Boolean => value.GetBoolean() ? "TRUE" : "FALSE",
                    _ => value.ToString(CultureInfo.InvariantCulture)
                };
                cells.Add(new Cell(c, r, text, kind, cell.HasFormula ? cell.FormulaA1 : ""));
            }
            sheets.Add(new Sheet(sheet.Name, rows, cols, sheet.Visibility != XLWorksheetVisibility.Visible, cells));
        }
        var id = Guid.NewGuid().ToString("N"); originals[id] = bytes;
        return new { id, name = System.IO.Path.GetFileName(path), sheets, formulaCount = sheets.Sum(s => s.Cells.Count(c => c.Formula.Length > 0)) };
    }

    static object Save(Request request) {
        if (!string.Equals(System.IO.Path.GetExtension(request.Path), ".xlsx", StringComparison.OrdinalIgnoreCase)) throw new Exception("Save the workbook with an .xlsx extension.");
        byte[] source = null;
        if (!string.IsNullOrEmpty(request.Id) && !originals.TryGetValue(request.Id, out source)) throw new Exception("The source workbook is no longer open.");
        using var workbook = source == null ? new XLWorkbook() : new XLWorkbook(new MemoryStream(source));
        if (request.Sheets == null || request.Sheets.Count == 0) throw new Exception("There are no worksheets to save.");
        int count = 0;
        foreach (var patch in request.Sheets) {
            if (source != null && !workbook.Worksheets.Contains(patch.Name)) throw new Exception("The worksheet no longer exists in this workbook.");
            var sheet = workbook.Worksheets.TryGetWorksheet(patch.Name, out var found) ? found : workbook.AddWorksheet(patch.Name);
            foreach (var edit in patch.Cells) {
                if (++count > MaxCells) throw new Exception("Save up to 500,000 changed cells at a time in this prototype.");
                if (edit.Row < 0 || edit.Row >= 1048576 || edit.Col < 0 || edit.Col >= 16384) throw new Exception("Cell is outside Excel's worksheet dimensions.");
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
            if (source == null) { sheet.SheetView.FreezeRows(1); sheet.Columns(1, Math.Max(1, patch.Cells.Select(c => c.Col + 1).DefaultIfEmpty(1).Max())).Width = 20; }
        }
        // Excel refreshes preserved formula expressions when it opens the exported workbook.
        workbook.CalculateMode = XLCalculateMode.Auto;
        workbook.FullCalculationOnLoad = true;
        workbook.ForceFullCalculation = true;
        var temporary = request.Path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        int uncached = 0;
        try {
            if (source == null) {
                using var stream = File.Create(temporary);
                workbook.SaveAs(stream, new ClosedXML.Excel.SaveOptions { EvaluateFormulasBeforeSaving = true });
            } else {
                File.WriteAllBytes(temporary, source);
                uncached = PatchOriginal(temporary, workbook, request.Sheets);
            }
            File.Move(temporary, request.Path, true);
        } finally { if (File.Exists(temporary)) File.Delete(temporary); }
        return new { ok = true, path = request.Path, sheets = workbook.Worksheets.Count, uncachedFormulas = uncached };
    }

    // Preserve the source package's styles, rich text and other worksheet features.
    // ClosedXML rewrites some inherited fonts on a full save of StatsDirect's test.xlsx.
    // Existing workbooks therefore receive cell patches, rather than a package rebuild.
    static int PatchOriginal(string path, XLWorkbook workbook, List<Patch> patches) {
        foreach (var worksheet in workbook.Worksheets)
            foreach (var cell in worksheet.CellsUsed(XLCellsUsedOptions.Contents).Where(c => c.HasFormula)) cell.InvalidateFormula();
        XNamespace s = "http://schemas.openxmlformats.org/spreadsheetml/2006/main";
        XNamespace rel = "http://schemas.openxmlformats.org/officeDocument/2006/relationships";
        XNamespace packageRel = "http://schemas.openxmlformats.org/package/2006/relationships";
        using var zip = ZipFile.Open(path, ZipArchiveMode.Update);
        XDocument Read(string name) { using var stream = zip.GetEntry(name).Open(); return XDocument.Load(stream); }
        void Write(string name, XDocument doc) {
            zip.GetEntry(name)?.Delete();
            using var stream = zip.CreateEntry(name, CompressionLevel.Optimal).Open(); doc.Save(stream);
        }
        var bookXml = Read("xl/workbook.xml");
        var relationships = Read("xl/_rels/workbook.xml.rels").Root.Elements(packageRel + "Relationship")
            .ToDictionary(e => (string)e.Attribute("Id"), e => (string)e.Attribute("Target"));
        int uncached = 0;
        foreach (var sheetInfo in bookXml.Root.Element(s + "sheets").Elements(s + "sheet")) {
            var name = (string)sheetInfo.Attribute("name"); var sheet = workbook.Worksheet(name);
            var edits = patches.FirstOrDefault(p => p.Name == name)?.Cells ?? new List<Cell>();
            var formulas = sheet.CellsUsed(XLCellsUsedOptions.Contents).Where(c => c.HasFormula).ToList();
            if (edits.Count == 0 && formulas.Count == 0) continue;
            var target = relationships[(string)sheetInfo.Attribute(rel + "id")];
            var entry = new Uri(new Uri("http://xlsx/xl/workbook.xml"), target).AbsolutePath.TrimStart('/');
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
            foreach (var edit in edits) SetValue(Find(edit.Row+1, edit.Col+1), edit.Kind == "text" ? (XLCellValue)edit.Text : sheet.Cell(edit.Row+1, edit.Col+1).Value, false);
            foreach (var cell in formulas) {
                XLCellValue value;
                try { value = cell.Value; } catch { value = Blank.Value; uncached++; }
                SetValue(Find(cell.Address.RowNumber, cell.Address.ColumnNumber), value, true);
            }
            var dimension = xml.Root.Element(s + "dimension");
            if (dimension != null && edits.Count > 0) {
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

    [UnmanagedCallersOnly]
    public static IntPtr Invoke(IntPtr input) => Marshal.StringToCoTaskMemUTF8(Execute(Marshal.PtrToStringUTF8(input) ?? "{}"));
    [UnmanagedCallersOnly]
    public static void Free(IntPtr result) => Marshal.FreeCoTaskMem(result);
}
