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
            // Excel keeps a 3-D coordinate when only some constituent sheets move.
            // A grouped edit with the same shift on every sheet moves it as one range.
            if (areas.Count != 1) return base.Reference3D(ctx, range, firstSheet, lastSheet, reference);
            return base.Reference3D(ctx, range, firstSheet, lastSheet, areas[0]);
        }
    }

    static void InsertWorkbookColumns(string sourcePath, string targetPath, List<SheetInserts> inserts, List<SheetData> patches = null) {
        using var source = ZipFile.OpenRead(sourcePath);
        var package = new Package(source, true);
        var book = ReadXml(source, "xl/workbook.xml");
        var names = book.Root.Element(S + "sheets").Elements(S + "sheet").Select(e => (string)e.Attribute("name")).ToList();
        var refs = new ColumnReferences(inserts, names);
        var replaced = new Dictionary<string, XDocument>(StringComparer.OrdinalIgnoreCase);
        var sheetParts = package.Sheets.ToDictionary(s => s.Entry, s => s, StringComparer.OrdinalIgnoreCase);
        var headers = new Dictionary<string, SortedDictionary<int, List<XElement>>>(StringComparer.OrdinalIgnoreCase);
        // Cache fields, slicer field IDs, rich-value metadata and connection definitions
        // are not sheet coordinates. Keep their identities and payloads; only their
        // source ranges and the owning sheet's visible objects need relocation.
        AdjustPivotSources(source, replaced, refs);
        AdjustConnectionParameters(source, replaced, refs);
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
                if (type.EndsWith("/vmlDrawing")) {
                    var drawing = ReadXml(source, part);
                    AdjustVml(drawing, info.Name, refs);
                    replaced[part] = drawing;
                } else if (type.EndsWith("/table")) {
                    var table = ReadXml(source, part);
                    ExpandTable(source, part, table, info.Name, refs, headers, patches, replaced);
                    AdjustFeatures(table.Root, info.Name, refs);
                    replaced[part] = table;
                    foreach (var (queryType,queryPart) in PartRelations(source,part).Where(r=>r.type.EndsWith("/queryTable"))) {
                        if (replaced.ContainsKey(queryPart)) continue; // expanded query already adjusted
                        var query = ReadXml(source,queryPart); AdjustFeatures(query.Root,info.Name,refs); replaced[queryPart] = query;
                    }
                } else if ((type.EndsWith("/comments") || type.EndsWith("/threadedComment"))) {
                    var comments = ReadXml(source, part);
                    foreach (var cell in comments.Descendants().Where(e => e.Name.LocalName is "comment" or "threadedComment")) cell.SetAttributeValue("ref", refs.Range((string)cell.Attribute("ref"), info.Name));
                    replaced[part] = comments;
                } else if (type.EndsWith("/drawing")) {
                    var drawing = ReadXml(source, part);
                    AdjustFeatures(drawing.Root, info.Name, refs);
                    replaced[part] = drawing;
                } else if (type.EndsWith("/ctrlProp")) {
                    var control = ReadXml(source, part);
                    AdjustFeatures(control.Root, info.Name, refs);
                    replaced[part] = control;
                } else if (type.EndsWith("/queryTable") || type.EndsWith("/singleCellTable")) {
                    var query = ReadXml(source,part); AdjustFeatures(query.Root,info.Name,refs); replaced[part] = query;
                } else if (type.EndsWith("/pivotTable")) {
                    var pivot = ReadXml(source, part);
                    // Excel itself prohibits splitting a pivot report. Moving the
                    // complete report leaves pivot-field indices and cache IDs intact.
                    foreach (var location in pivot.Descendants(S+"location")) {
                        refs.Intact((string)location.Attribute("ref"), info.Name, "a PivotTable report");
                        location.SetAttributeValue("ref", refs.Range((string)location.Attribute("ref"), info.Name));
                    }
                    // Pivot-area references are offsets within the report, not A1
                    // coordinates on the sheet: they deliberately remain unchanged.
                    replaced[part] = pivot;
                }

            }
        }
        // Chart series on any sheet may refer to the moved data. Drop their obsolete caches.
        foreach (var entry in source.Entries.Where(e => e.FullName.StartsWith("xl/charts/") && e.FullName.EndsWith(".xml"))) {
            var chart = ReadXml(source, entry.FullName);
            XNamespace c = "http://schemas.openxmlformats.org/drawingml/2006/chart";
            foreach (var formula in chart.Descendants().Where(e=>e.Name == c+"f" || e.Name.LocalName == "f" && e.Name.NamespaceName == "http://schemas.microsoft.com/office/drawing/2014/chartex")) formula.Value = refs.Formula(formula.Value, null);
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
            if (sheetParts.TryGetValue(entry.FullName, out var sheet)) InsertSheet(entry, into, sheet.Name, refs, headers.GetValueOrDefault(sheet.Name));
            else { using var from = entry.Open(); from.CopyTo(into); }
        }
    }

    static void AdjustFeatures(XElement element, string sheet, ColumnReferences refs) {
        bool moving = refs.For(sheet).Count > 0;
        foreach (var node in element.DescendantsAndSelf().ToList()) {
            // MS-XLSX xm:f and xm:sqref explicitly expose coordinates even for
            // otherwise unknown extension payloads. Do not rewrite unrelated IDs.
            if (node.Name.Namespace == Xm && node.Name.LocalName is "f" or "sqref") {
                node.Value = node.Name.LocalName == "f" ? refs.Formula(node.Value,sheet) : refs.Range(node.Value,sheet);
                continue;
            }
            if (node.Name.Namespace != S && !IsExcelExtension(node.Name.Namespace)) continue;
            string kind = node.Name.LocalName;
            if (moving && kind == "sheetProtection" && (string)node.Attribute("sheet") is "1" or "true" && (string)node.Attribute("insertColumns") is not ("0" or "false"))
                throw new Exception($"Worksheet '{sheet}' is protected against column insertion. Unprotect it in Excel or write the results in a new worksheet.");
            if (!node.HasElements && kind is "formula" or "formula1" or "formula2" or "calculatedColumnFormula" or "totalsRowFormula") node.Value = refs.Formula(node.Value, sheet);
            string context = kind == "dataRef" && node.Attribute("sheet") != null ? (string)node.Attribute("sheet") : sheet;
            bool external = kind == "dataRef" && node.Attribute(Rel+"id") != null;
            foreach (var attr in node.Attributes().ToList()) {
                if (attr.Name.Namespace != XNamespace.None) continue;
                if (attr.Name.LocalName is "ref" or "sqref" or "activeCell" or "topLeftCell" or "syncRef" || kind is "inputCells" or "cellWatch" or "singleXmlCell" && attr.Name.LocalName == "r") if (!external) attr.Value = refs.Range(attr.Value, context);
                if (attr.Name.LocalName is "fmlaLink" or "fmlaRange" or "fmlaTxbx" or "linkedCell" or "listFillRange") attr.Value = refs.Formula(attr.Value, sheet);
                if (kind == "webPublishItem" && attr.Name.LocalName == "sourceRef") attr.Value = refs.Range(attr.Value,sheet);
                if (kind == "hyperlink" && attr.Name.LocalName == "location") attr.Value = refs.Formula(attr.Value, sheet);
            }
            if (kind == "cfvo" && (string)node.Attribute("type") == "formula" && node.Attribute("val") is XAttribute threshold) threshold.Value = refs.Formula(threshold.Value,sheet);
            if (moving && kind == "brk" && node.Parent?.Name == S+"rowBreaks") {
                bool fullWidth = ((int?)node.Attribute("min") ?? 0) == 0 && (int?)node.Attribute("max") == MaxCols-1;
                if (!fullWidth) foreach (string limit in new[] { "min", "max" }) if (node.Attribute(limit) is XAttribute bound) bound.Value = (refs.Column(sheet,int.Parse(bound.Value,CultureInfo.InvariantCulture)+1,true)-1).ToString(CultureInfo.InvariantCulture);
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
        AdjustDrawing(element, sheet, refs);
    }

    static void InsertSheet(ZipArchiveEntry entry, Stream output, string sheet, ColumnReferences refs, SortedDictionary<int, List<XElement>> headers) {
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
                    WriteMissingHeaderRows(writer, headers, rowNumber);
                    var styles = InsertedCellStyles(node,sheet,refs,rowNumber);
                    node.Attribute("spans")?.Remove();
                    int col = 0;
                    foreach (var cell in node.Elements(S+"c")) {
                        if (cell.Attribute("r") is XAttribute address) (_,col) = ParseAddress(address.Value); else col++;
                        cell.SetAttributeValue("r", ColumnName(refs.Column(sheet,col))+rowNumber.ToString(CultureInfo.InvariantCulture));
                        var f = cell.Element(S+"f");
                        if (f == null) continue;
                        string type = (string)f.Attribute("t");
                        if (type == "dataTable") {
                            if (f.Attribute("ref") is XAttribute table) {
                                refs.Intact(table.Value, sheet, "a what-if data table");
                                table.Value = refs.Range(table.Value, sheet);
                            }
                            foreach (string input in new[] { "r1", "r2" })
                                if (f.Attribute(input) is XAttribute reference) reference.Value = refs.Range(reference.Value,sheet);
                        }
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
                    MergeRowCells(node,styles);
                    AddTableHeaders(node, rowNumber, headers);
                    AdjustFeaturesInRow(node, sheet, refs);
                } else if (node.Name == S+"cols") {
                    InsertColumnStyles(node,sheet,refs);
                } else AdjustFeatures(node,sheet,refs);
                node.WriteTo(writer); more = !reader.EOF; continue;
            }
            switch (reader.NodeType) {
                case XmlNodeType.Element:
                    writer.WriteStartElement(reader.Prefix,reader.LocalName,reader.NamespaceURI); writer.WriteAttributes(reader,true);
                    if (reader.IsEmptyElement) {
                        if (reader.NamespaceURI == MainNs && reader.LocalName == "sheetData") WriteMissingHeaderRows(writer,headers,int.MaxValue);
                        writer.WriteEndElement();
                    }
                    break;
                case XmlNodeType.EndElement:
                    if (reader.NamespaceURI == MainNs && reader.LocalName == "sheetData") WriteMissingHeaderRows(writer, headers, int.MaxValue);
                    writer.WriteFullEndElement(); break;
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
