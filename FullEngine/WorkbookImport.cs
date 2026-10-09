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
        // Only ordinary, unencrypted XLSX packages use the existing preserving editor.
        // Format detection, rather than extension alone, routes everything else through
        // the compatibility reader (including Strict OOXML and mislabeled XLS files).
        if (EditableXlsx(path)) return OpenXlsx(path, snapshotDir);
        return ImportValues(path, snapshotDir, password);
    }

    static bool EditableXlsx(string path) {
        if (!Path.GetExtension(path).Equals(".xlsx", StringComparison.OrdinalIgnoreCase)) return false;
        using var file = File.OpenRead(path);
        if (file.ReadByte() != 'P' || file.ReadByte() != 'K') return false;
        file.Position = 0;
        using var zip = new ZipArchive(file, ZipArchiveMode.Read);
        var book = Entry(zip, "xl/workbook.xml");
        if (book == null || Entry(zip, "xl/_rels/workbook.xml.rels") == null) return false;
        using var stream = book.Open();
        using var reader = XmlReader.Create(stream, new XmlReaderSettings { DtdProcessing = DtdProcessing.Prohibit, XmlResolver = null });
        reader.MoveToContent();
        if (reader.NamespaceURI != MainNs) return false;
        // A macro-enabled workbook renamed to .xlsx must not lose its VBA on saving.
        var types = Entry(zip, "[Content_Types].xml");
        if (types == null) return false;
        using var typeStream = types.Open();
        return XDocument.Load(typeStream).Root.Elements().Any(e =>
            string.Equals((string)e.Attribute("PartName"), "/xl/workbook.xml", StringComparison.OrdinalIgnoreCase) &&
            (string)e.Attribute("ContentType") == "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml");
    }

    static object ImportValues(string path, string snapshotDir, string password, bool singlePass = true) {
        var id = Guid.NewGuid().ToString("N");
        var sheets = new List<Sheet>();
        var written = new List<string>();
        try {
            using var file = File.OpenRead(path);
            using var reader = ExcelReaderFactory.CreateReader(file, new ExcelReaderConfiguration { Password = password, SinglePassMode = singlePass });
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
                            case double n: kind = 1; num = n; break;
                            case int n: kind = 1; num = n; break;
                            case bool b: kind = 5; text = b ? "TRUE" : "FALSE"; break;
                            case DateTime d: kind = 3; text = DateText(d); break;
                            case TimeSpan t: kind = 4; text = t.ToString("c", CultureInfo.InvariantCulture); break;
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

    static string ErrorText(CellError error) => error switch {
        CellError.NULL => "#NULL!", CellError.DIV0 => "#DIV/0!", CellError.VALUE => "#VALUE!",
        CellError.REF => "#REF!", CellError.NAME => "#NAME?", CellError.NUM => "#NUM!",
        CellError.NA => "#N/A", CellError.GETTING_DATA => "#GETTING_DATA",
        _ => "#ERROR!"
    };
}
