using System;
using System.IO;
using System.Linq;
using System.Globalization;
using NPOI.HSSF.UserModel;
using NPOI.SS.UserModel;

public static partial class WorkbookIO {
    // Explicit data export: original package/formats/macros stay in the source.
    // Excel 97-2003 dimensions and string limits are checked before writing.
    static object ExportXls(Request request) {
        if (!string.IsNullOrEmpty(request.Id) && dataCopies.TryGetValue(request.Id, out var source) &&
            string.Equals(Path.GetFullPath(request.Path), source, StringComparison.OrdinalIgnoreCase))
            throw new Exception("Choose a new filename to keep the original workbook intact.");
        System.Collections.Generic.List<SheetData> sheets;
        if (request.Snapshot != null) { using var stream = File.OpenRead(request.Snapshot); sheets = ReadSnapshot(stream); }
        else sheets = (request.Sheets ?? new()).Select(p => FromCells(p.Name, p.Cells ?? new())).ToList();
        if (sheets.Count == 0) throw new Exception("There are no worksheets to export.");
        using var book = new HSSFWorkbook();
        var date = book.CreateCellStyle(); date.DataFormat = book.CreateDataFormat().GetFormat("yyyy-mm-dd hh:mm:ss");
        var duration = book.CreateCellStyle(); duration.DataFormat = book.CreateDataFormat().GetFormat("[h]:mm:ss");
        foreach (var sheet in sheets) {
            var target = book.CreateSheet(sheet.Name); target.DefaultColumnWidth = 20;
            foreach (var col in sheet.Columns.Values) for (int i = 0; i < col.Rows.Count; i++) {
                var row = col.Rows[i];
                if (col.Col < 0 || col.Col >= 256 || row < 0 || row >= 65536)
                    throw new Exception("Excel 97-2003 (.xls) supports 65,536 rows and 256 columns. Export this workbook as .xlsx instead; no data was truncated.");
                var text = col.TextAt(i);
                if (text.Length > 32767) throw new Exception("A cell exceeds the Excel 97-2003 text limit (32,767 characters). No data was truncated.");
                var cell = (target.GetRow(row) ?? target.CreateRow(row)).CreateCell(col.Col);
                switch (col.Kinds[i]) {
                    case 0: cell.SetCellType(CellType.Blank); break;
                    case 1: cell.SetCellValue(col.Nums[i]); break;
                    case 3 when DateTime.TryParse(text, CultureInfo.InvariantCulture, DateTimeStyles.None, out var value): cell.SetCellValue(value); cell.CellStyle = date; break;
                    case 4 when TimeSpan.TryParse(text, CultureInfo.InvariantCulture, out var span): cell.SetCellValue(span.TotalDays); cell.CellStyle = duration; break;
                    case 5 when bool.TryParse(text, out var flag): cell.SetCellValue(flag); break;
                    default: cell.SetCellValue(text); break; // '=' remains literal text, never executable formulae.
                }
            }
        }
        var temporary = request.Path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try { using (var output = File.Create(temporary)) book.Write(output, true); File.Move(temporary, request.Path, true); }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
        return new { ok = true, sheets = sheets.Count, dataCopy = true };
    }
}
