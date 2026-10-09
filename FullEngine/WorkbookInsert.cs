using System;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Collections.Generic;
using System.Globalization;
using System.Text;
using System.Xml;
using System.Xml.Linq;
using ClosedXML.Parser;

public static partial class WorkbookIO {
    // Structural edits are applied to the original package before value patches. Rows are
    // streamed, so moving a million-row column does not need a million-cell edit list or
    // a ClosedXML workbook in memory. Unrelated package parts and style IDs stay intact.
    static object ValidateInsertions(Request request) {
        if (string.IsNullOrEmpty(request.Id) || dataCopies.ContainsKey(request.Id)) return new { ok = true };
        if (!originals.TryGetValue(request.Id, out var original)) throw new Exception("The source workbook is no longer open.");
        var path = Path.Combine(Path.GetTempPath(), "StatsDirect-insert-" + Guid.NewGuid().ToString("N") + ".xlsx");
        try { InsertWorkbookColumns(original.path, path, request.Inserts ?? new()); return new { ok = true }; }
        finally { if (File.Exists(path)) File.Delete(path); }
    }

    sealed class ColumnReferences : CopyVisitor {
        readonly Dictionary<string, List<Insert>> shifts;
        readonly List<string> sheetOrder;
        public ColumnReferences(List<SheetInserts> inserts, List<string> sheets) {
            shifts = new(StringComparer.OrdinalIgnoreCase); sheetOrder = sheets;
            foreach (var sheet in inserts) {
                if (!sheets.Contains(sheet.Name, StringComparer.OrdinalIgnoreCase) || shifts.ContainsKey(sheet.Name)) throw new Exception("Invalid worksheet in the column insertion request.");
                foreach (var ins in sheet.Inserts ?? new())
                    if (ins.Col < 0 || ins.Count < 1 || ins.Col >= MaxCols || ins.Count > MaxCols - ins.Col) throw new Exception("Invalid column insertion.");
                shifts.Add(sheet.Name, sheet.Inserts ?? new());
            }
        }
        public List<Insert> For(string sheet) => shifts.TryGetValue(sheet ?? "", out var result) ? result : new();
        public int Column(string sheet, int col, bool clip = false) {
            foreach (var ins in For(sheet)) if (col > ins.Col) col = checked(col + ins.Count);
            if (col > MaxCols && !clip) throw new Exception($"Inserting columns in '{sheet}' would move cells or references beyond Excel's last column (XFD).");
            return Math.Min(col, MaxCols);
        }
        ReferenceArea Area(string sheet, ReferenceArea area) {
            if (area.First.IsRow) return area;
            // A range ending at the edge of the worksheet keeps that edge, as Excel does.
            RowCol Move(RowCol c) => new(c.RowType, c.RowType == ReferenceAxisType.None ? 0 : c.RowValue, c.ColumnType,
                Column(sheet, c.ColumnValue, area.First != area.Second && c.ColumnValue == MaxCols), c.Style);
            if (string.IsNullOrEmpty(sheet) && shifts.Values.Any(v => v.Count > 0)) throw new Exception("A workbook name uses an unqualified cell reference. Give that name an explicit worksheet in Excel before inserting columns.");
            return new(Move(area.First), Move(area.Second));
        }
        public string Formula(string text, string sheet, int row = 1, int col = 1) {
            if (string.IsNullOrWhiteSpace(text)) return text;
            bool equals = text.StartsWith('=');
            try { return (equals ? "=" : "") + FormulaConverter.ModifyA1(equals ? text.Substring(1) : text, sheet ?? "", row, col, this); }
            catch (ParsingException) { throw new Exception($"A formula or named range in '{sheet ?? "workbook names"}' cannot be safely adjusted. Write the results in a new worksheet, or update that formula in Excel first."); }
        }
        public string Range(string text, string sheet) => string.Join(" ", text.Split((char[])null, StringSplitOptions.RemoveEmptyEntries).Select(r => Formula(r, sheet)));
        public void Intact(string text, string sheet, string feature) {
            var pieces = text.Replace("$", "").Split(':');
            var (_, first) = ParseAddress(pieces[0]); var (_, last) = ParseAddress(pieces[^1]);
            foreach (var ins in For(sheet)) {
                if (first <= ins.Col && last > ins.Col) throw new Exception($"Inserting here would split {feature} ({sheet}!{text}). Choose a position outside it or write the results in a new worksheet.");
                if (first > ins.Col) { first += ins.Count; last += ins.Count; }
            }
        }
        public override TransformedSymbol Reference(ModContext ctx, SymbolRange range, ReferenceArea reference) => base.Reference(ctx, range, Area(ctx.Sheet, reference));
        public override TransformedSymbol BangReference(ModContext ctx, SymbolRange range, ReferenceArea reference) => base.BangReference(ctx, range, Area(ctx.Sheet, reference));
        public override TransformedSymbol SheetReference(ModContext ctx, SymbolRange range, string sheet, ReferenceArea reference) => base.SheetReference(ctx, range, sheet, Area(sheet, reference));
        public override TransformedSymbol CellFunction(ModContext ctx, SymbolRange range, RowCol cell, IReadOnlyList<TransformedSymbol> arguments) => base.CellFunction(ctx, range, Area(ctx.Sheet, new(cell)).First, arguments);
        public override TransformedSymbol Reference3D(ModContext ctx, SymbolRange range, string firstSheet, string lastSheet, ReferenceArea reference) {
            int a = sheetOrder.FindIndex(s => s.Equals(firstSheet, StringComparison.OrdinalIgnoreCase)), b = sheetOrder.FindIndex(s => s.Equals(lastSheet, StringComparison.OrdinalIgnoreCase));
            if (a < 0 || b < 0) throw new Exception("A three-dimensional formula refers to an unknown worksheet.");
            var areas = sheetOrder.Skip(Math.Min(a,b)).Take(Math.Abs(b-a)+1).Select(s => Area(s,reference)).Distinct().ToList();
            if (areas.Count != 1) throw new Exception("This insertion would make a three-dimensional formula refer to different columns on different worksheets. Write the results in a new worksheet.");
            return base.Reference3D(ctx, range, firstSheet, lastSheet, areas[0]);
        }
    }

    static void InsertWorkbookColumns(string sourcePath, string targetPath, List<SheetInserts> inserts) {
        using var source = ZipFile.OpenRead(sourcePath);
        var package = new Package(source, true);
        var book = ReadXml(source, "xl/workbook.xml");
        var names = book.Root.Element(S + "sheets").Elements(S + "sheet").Select(e => (string)e.Attribute("name")).ToList();
        var refs = new ColumnReferences(inserts, names);
        var replaced = new Dictionary<string, XDocument>(StringComparer.OrdinalIgnoreCase);
        var sheetParts = package.Sheets.ToDictionary(s => s.Entry, s => s, StringComparer.OrdinalIgnoreCase);
        // These parts contain coordinate-bearing structures that require more than shifting
        // their visible cells. Reading remains unrestricted; only structural editing waits.
        foreach (var entry in source.Entries) {
            string part = entry.FullName.ToLowerInvariant();
            if (part.StartsWith("xl/pivot") || part.StartsWith("xl/slicer") || part.StartsWith("xl/threadedcomments") || part.StartsWith("xl/metadata") || part.StartsWith("xl/externalconnections") || part.StartsWith("xl/querytables/") || part == "xl/connections.xml")
                throw new Exception("This workbook contains pivot, slicer or linked-data metadata that cannot yet be moved safely. Write the results in a new worksheet.");
        }
        foreach (var name in book.Descendants(S + "definedName")) {
            int? index = (int?)name.Attribute("localSheetId");
            string context = index.HasValue && index >= 0 && index < names.Count ? names[index.Value] : null;
            name.Value = refs.Formula(name.Value, context);
        }
        replaced["xl/workbook.xml"] = book;
        // Relations tie tables, drawings and comments to their owning worksheet.
        foreach (var info in package.Sheets) {
            var slash = info.Entry.LastIndexOf('/');
            string relPath = info.Entry.Substring(0, slash + 1) + "_rels/" + info.Entry.Substring(slash + 1) + ".rels";
            if (Entry(source, relPath) == null) continue;
            foreach (var rel in ReadXml(source, relPath).Root.Elements(PackageRel + "Relationship")) {
                if ((string)rel.Attribute("TargetMode") == "External") continue;
                string type = (string)rel.Attribute("Type") ?? "", target = (string)rel.Attribute("Target");
                string part = Uri.UnescapeDataString(new Uri(new Uri("http://package/" + info.Entry), target).AbsolutePath.TrimStart('/'));
                bool moving = refs.For(info.Name).Count > 0;
                if (moving && (type.EndsWith("/oleObject") || type.EndsWith("/ctrlProp")))
                    throw new Exception($"Worksheet '{info.Name}' has legacy shapes or controls that cannot yet be moved safely. Write the results in a new worksheet.");
                if (type.EndsWith("/vmlDrawing") && moving) {
                    var drawing = ReadXml(source, part);
                    XNamespace vml = "urn:schemas-microsoft-com:vml", excel = "urn:schemas-microsoft-com:office:excel";
                    foreach (var shape in drawing.Descendants(vml+"shape")) {
                        var data = shape.Element(excel+"ClientData");
                        if ((string)data?.Attribute("ObjectType") != "Note")
                            throw new Exception($"Worksheet '{info.Name}' has legacy shapes or controls that cannot yet be moved safely. Write the results in a new worksheet.");
                        if (data.Element(excel+"Column") is XElement column)
                            column.Value = (refs.Column(info.Name, (int)column+1)-1).ToString(CultureInfo.InvariantCulture);
                        if (data.Element(excel+"Anchor") is XElement anchor) {
                            var coordinates = anchor.Value.Split(',').Select(x=>int.Parse(x.Trim(),CultureInfo.InvariantCulture)).ToArray();
                            if (coordinates.Length != 8 || coordinates.Any(n=>n<0) || coordinates[0]>=MaxCols || coordinates[4]>=MaxCols || coordinates[4]<coordinates[0]) throw new Exception("A note has an invalid anchor. Repair it in Excel before inserting columns.");
                            bool flag(string name) { var element=data.Element(excel+name); return element!=null && (element.Value.Trim() is "" or "True" or "true" or "1" or "t"); }
                            int start = coordinates[0], end = coordinates[4];
                            // Notes move with their cell. Preserve the note box's width
                            // unless the VML explicitly requests sizing with cells.
                            if (flag("MoveWithCells") || flag("SizeWithCells")) {
                                coordinates[0] = refs.Column(info.Name,start+1)-1;
                                coordinates[4] = flag("SizeWithCells") ? refs.Column(info.Name,end+1)-1 : end+coordinates[0]-start;
                            }
                            if (coordinates[4] >= MaxCols) throw new Exception("A note would move beyond Excel's last column. Write results in a new worksheet.");
                            anchor.Value = string.Join(", ", coordinates);
                        }
                    }
                    // Other VML element types can also carry coordinates. Only note
                    // drawings are supported; never accept a control by omission.
                    if (drawing.Descendants().Any(e=>e.Name.Namespace==vml && e.Name.LocalName is "rect" or "roundrect" or "oval" or "line" or "polyline" or "arc" or "curve" or "image" or "group"))
                        throw new Exception($"Worksheet '{info.Name}' has legacy shapes or controls that cannot yet be moved safely. Write the results in a new worksheet.");
                    replaced[part] = drawing;
                } else if (type.EndsWith("/table")) {
                    var table = ReadXml(source, part);
                    var range = table.Root.Attribute("ref");
                    refs.Intact(range.Value, info.Name, "an Excel table");
                    AdjustFeatures(table.Root, info.Name, refs);
                    replaced[part] = table;
                } else if (type.EndsWith("/comments")) {
                    var comments = ReadXml(source, part);
                    foreach (var cell in comments.Descendants(S + "comment")) cell.SetAttributeValue("ref", refs.Range((string)cell.Attribute("ref"), info.Name));
                    replaced[part] = comments;
                } else if (type.EndsWith("/drawing") && moving) {
                    var drawing = ReadXml(source, part);
                    XNamespace xdr = "http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing";
                    foreach (var anchor in drawing.Root.Elements()) {
                        string behavior = (string)anchor.Attribute("editAs");
                        if (anchor.Name == xdr+"absoluteAnchor" || behavior == "absolute") continue;
                        var columns = anchor.Descendants(xdr+"col").ToList();
                        int delta = columns.Count == 0 ? 0 : refs.Column(info.Name,(int)columns[0]+1)-1-(int)columns[0];
                        foreach (var col in columns) {
                            int moved = behavior == "oneCell" ? (int)col + delta : refs.Column(info.Name,(int)col+1)-1;
                            if (moved >= MaxCols) throw new Exception("A drawing would move beyond Excel's last column. Write results in a new worksheet.");
                            col.Value = moved.ToString(CultureInfo.InvariantCulture);
                        }
                    }
                    replaced[part] = drawing;
                }
            }
        }
        // Chart series on any sheet may refer to the moved data. Drop their obsolete caches.
        foreach (var entry in source.Entries.Where(e => e.FullName.StartsWith("xl/charts/") && e.FullName.EndsWith(".xml"))) {
            var chart = ReadXml(source, entry.FullName);
            XNamespace c = "http://schemas.openxmlformats.org/drawingml/2006/chart";
            foreach (var formula in chart.Descendants(c + "f")) formula.Value = refs.Formula(formula.Value, null);
            chart.Descendants().Where(e => e.Name == c+"numCache" || e.Name == c+"strCache").Remove();
            replaced[entry.FullName] = chart;
        }
        // Cached calculation order is obsolete after insertion. Remove both its relationship
        // and its content-type declaration, as well as the part itself.
        string chainPart = null;
        var relationships = ReadXml(source, "xl/_rels/workbook.xml.rels");
        foreach (var rel in relationships.Root.Elements().Where(e => ((string)e.Attribute("Type") ?? "").EndsWith("/calcChain")).ToList()) {
            chainPart = ResolveTarget((string)rel.Attribute("Target")); rel.Remove();
        }
        if (chainPart != null) {
            replaced["xl/_rels/workbook.xml.rels"] = relationships;
            var types = ReadXml(source, "[Content_Types].xml");
            types.Root.Elements().Where(e => ((string)e.Attribute("PartName"))?.TrimStart('/') == chainPart).Remove();
            replaced["[Content_Types].xml"] = types;
        }
        using var output = new ZipArchive(File.Create(targetPath), ZipArchiveMode.Create);
        foreach (var entry in source.Entries) {
            if (entry.FullName.EndsWith('/') || entry.FullName == chainPart) continue;
            using var into = output.CreateEntry(entry.FullName, CompressionLevel.Optimal).Open();
            if (replaced.TryGetValue(entry.FullName, out var doc)) { doc.Save(into); continue; }
            if (sheetParts.TryGetValue(entry.FullName, out var sheet)) InsertSheet(entry, into, sheet.Name, refs);
            else { using var from = entry.Open(); from.CopyTo(into); }
        }
    }

    static void AdjustFeatures(XElement element, string sheet, ColumnReferences refs) {
        bool moving = refs.For(sheet).Count > 0;
        foreach (var node in element.DescendantsAndSelf()) {
            if (moving && node.Name.LocalName is "extLst" or "customSheetViews" or "dataConsolidate") throw new Exception($"Worksheet '{sheet}' uses extended Excel features that cannot yet be moved safely. Write the results in a new worksheet.");
            if (node.Name.Namespace != S) continue;
            string kind = node.Name.LocalName;
            if (moving && kind == "sheetProtection" && (string)node.Attribute("sheet") is "1" or "true" && (string)node.Attribute("insertColumns") is not ("0" or "false"))
                throw new Exception($"Worksheet '{sheet}' is protected against column insertion. Unprotect it in Excel or write the results in a new worksheet.");
            if (kind == "mergeCell" && node.Attribute("ref") is XAttribute merge) refs.Intact(merge.Value, sheet, "a merged cell range");
            if (kind is "formula" or "formula1" or "formula2" or "calculatedColumnFormula" or "totalsRowFormula") node.Value = refs.Formula(node.Value, sheet);
            foreach (var attr in node.Attributes().ToList()) {
                if (attr.Name.Namespace != XNamespace.None) continue;
                if (attr.Name.LocalName is "ref" or "sqref" or "activeCell" or "topLeftCell" or "syncRef" || kind == "inputCells" && attr.Name.LocalName == "r") attr.Value = refs.Range(attr.Value, sheet);
                if (kind == "hyperlink" && attr.Name.LocalName == "location") attr.Value = refs.Formula(attr.Value, sheet);
            }
            if (kind == "autoFilter" && node.Attribute("ref") != null) {
                // colId is relative to the left edge of the filter range; insertion inside a
                // filter shifts only filter columns to its right.
                // The original range was shifted above, so invert its first column for each step.
                var (_, endFirst) = ParseAddress(((string)node.Attribute("ref")).Split(':')[0]);
                int first = endFirst;
                foreach (var ins in refs.For(sheet).AsEnumerable().Reverse()) if (first > ins.Col + ins.Count) first -= ins.Count;
                foreach (var fc in node.Elements(S+"filterColumn")) {
                    int originalCol = first + (int)fc.Attribute("colId");
                    fc.SetAttributeValue("colId", refs.Column(sheet,originalCol)-endFirst);
                }
            }
            if (moving && kind == "pane" && (string)node.Attribute("state") is "frozen" or "frozenSplit" && node.Attribute("xSplit") is XAttribute split) {
                int boundary = int.Parse(split.Value, CultureInfo.InvariantCulture);
                foreach (var ins in refs.For(sheet)) if (ins.Col < boundary) boundary += ins.Count;
                split.Value = boundary.ToString(CultureInfo.InvariantCulture);
            }
            if (moving && kind == "brk" && node.Parent?.Name == S+"colBreaks") node.SetAttributeValue("id", refs.Column(sheet,(int)node.Attribute("id")));
        }
    }

    static void InsertSheet(ZipArchiveEntry entry, Stream output, string sheet, ColumnReferences refs) {
        // Shared masters may follow their dependants in a valid file. Collect them first.
        var shared = new Dictionary<string,string>();
        using (var input = entry.Open()) using (var scan = XmlReader.Create(input)) {
            int row = 0, col = 0;
            while (scan.Read()) {
                if (scan.NodeType != XmlNodeType.Element || scan.NamespaceURI != MainNs) continue;
                if (scan.LocalName == "row") { row = int.TryParse(scan.GetAttribute("r"), out var rowIndex) ? rowIndex : row+1; col = 0; }
                if (scan.LocalName == "c") { if (scan.GetAttribute("r") is string address) (row,col) = ParseAddress(address); else col++; }
                if (scan.LocalName != "f" || scan.GetAttribute("t") != "shared") continue;
                string id = scan.GetAttribute("si");
                using var subtree = scan.ReadSubtree();
                var f = XElement.Load(subtree);
                if (f.Value.Length > 0) shared[id] = FormulaConverter.ToR1C1(f.Value,row,col);
            }
        }
        using var from = entry.Open();
        using var reader = XmlReader.Create(from, new XmlReaderSettings { IgnoreWhitespace = false });
        using var writer = XmlWriter.Create(output, new XmlWriterSettings { Encoding = new UTF8Encoding(false) });
        bool more = reader.Read();
        int rowNumber = 0;
        while (more) {
            if (reader.NodeType == XmlNodeType.Element && reader.NamespaceURI == MainNs && reader.LocalName != "worksheet" && reader.LocalName != "sheetData") {
                var node = (XElement)XNode.ReadFrom(reader);
                if (node.Name == S+"row") {
                    rowNumber = (int?)node.Attribute("r") ?? rowNumber+1;
                    node.Attribute("spans")?.Remove();
                    int col = 0;
                    foreach (var cell in node.Elements(S+"c")) {
                        if (cell.Attribute("r") is XAttribute address) (_,col) = ParseAddress(address.Value); else col++;
                        cell.SetAttributeValue("r", ColumnName(refs.Column(sheet,col))+rowNumber.ToString(CultureInfo.InvariantCulture));
                        var f = cell.Element(S+"f");
                        if (f == null) continue;
                        string type = (string)f.Attribute("t");
                        if (type == "dataTable") throw new Exception($"Worksheet '{sheet}' has a what-if data table that cannot yet be adjusted. Write results in a new worksheet.");
                        if (type == "shared") {
                            string id = (string)f.Attribute("si");
                            if (id == null || !shared.TryGetValue(id,out var master)) throw new Exception("A shared formula has no master expression.");
                            f.Value = FormulaConverter.ToA1(master,rowNumber,col);
                            f.Attribute("t")?.Remove(); f.Attribute("si")?.Remove(); f.Attribute("ref")?.Remove();
                        }
                        if (type == "array" && f.Attribute("ref") is XAttribute range) {
                            refs.Intact(range.Value,sheet,"an array formula"); range.Value = refs.Range(range.Value,sheet);
                        }
                        f.Value = refs.Formula(f.Value,sheet,rowNumber,col);
                        cell.Elements(S+"v").Remove(); cell.Elements(S+"is").Remove(); cell.Attribute("t")?.Remove();
                    }
                } else if (node.Name == S+"cols") {
                    foreach (var c in node.Elements(S+"col").ToList()) {
                        int min = (int)c.Attribute("min"), max = (int)c.Attribute("max");
                        // Keep column properties with their old columns. A spanning
                        // definition expands over the gap; other gaps use sheet defaults.
                        int movedMin = min;
                        foreach (var ins in refs.For(sheet)) if (movedMin > ins.Col) movedMin += ins.Count;
                        if (movedMin > MaxCols) { c.Remove(); continue; }
                        c.SetAttributeValue("min", movedMin); c.SetAttributeValue("max", refs.Column(sheet,max,true));
                    }
                } else AdjustFeatures(node,sheet,refs);
                node.WriteTo(writer); more = !reader.EOF; continue;
            }
            switch (reader.NodeType) {
                case XmlNodeType.Element: writer.WriteStartElement(reader.Prefix,reader.LocalName,reader.NamespaceURI); writer.WriteAttributes(reader,true); if (reader.IsEmptyElement) writer.WriteEndElement(); break;
                case XmlNodeType.EndElement: writer.WriteFullEndElement(); break;
                case XmlNodeType.XmlDeclaration: writer.WriteStartDocument(); break;
                case XmlNodeType.Text: writer.WriteString(reader.Value); break;
                case XmlNodeType.Whitespace: case XmlNodeType.SignificantWhitespace: writer.WriteWhitespace(reader.Value); break;
                case XmlNodeType.Comment: writer.WriteComment(reader.Value); break;
                case XmlNodeType.ProcessingInstruction: writer.WriteProcessingInstruction(reader.Name,reader.Value); break;
            }
            more = reader.Read();
        }
    }
}
