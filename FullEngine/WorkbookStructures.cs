using System;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Collections.Generic;
using System.Globalization;
using System.Xml;
using System.Xml.Linq;

public static partial class WorkbookIO {
    static readonly XNamespace Xm = "http://schemas.microsoft.com/office/excel/2006/main";
    static readonly XNamespace Xdr = "http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing";
    static readonly XNamespace Vml = "urn:schemas-microsoft-com:vml";
    static readonly XNamespace VmlExcel = "urn:schemas-microsoft-com:office:excel";
    static bool IsExcelExtension(XNamespace ns) => ns.NamespaceName.StartsWith("http://schemas.microsoft.com/office/spreadsheetml/", StringComparison.Ordinal);
    static bool XmlFlag(XElement element, string name) => (string)element.Attribute(name) is "1" or "true";
    static IEnumerable<(string type, string part)> PartRelations(ZipArchive zip, string owner) {
        int slash = owner.LastIndexOf('/');
        string path = owner.Substring(0,slash+1)+"_rels/"+owner.Substring(slash+1)+".rels";
        if (Entry(zip,path) == null) yield break;
        foreach (var rel in ReadXml(zip,path).Root.Elements(PackageRel+"Relationship")) {
            if ((string)rel.Attribute("TargetMode") == "External") continue;
            yield return ((string)rel.Attribute("Type") ?? "", Uri.UnescapeDataString(new Uri(new Uri("http://package/"+owner),(string)rel.Attribute("Target")).AbsolutePath.TrimStart('/')));
        }
    }

    static void AdjustPivotSources(ZipArchive zip, Dictionary<string,XDocument> changed, ColumnReferences refs) {
        foreach (var (_, part) in PartRelations(zip,"xl/workbook.xml").Where(r=>r.type.EndsWith("/pivotCacheDefinition"))) {
            // Records are deliberately streamed/copied, never loaded: their field order
            // and the referencing pivot/slicer IDs belong to the existing cache snapshot.
            var cache = ReadXml(zip,part);
            foreach (var source in cache.Descendants().Where(e=>e.Name == S+"worksheetSource" || e.Name == S+"rangeSet")) {
                if (source.Attribute(Rel+"id") != null) continue; // an external workbook
                string sheet = (string)source.Attribute("sheet");
                if (sheet != null && source.Attribute("ref") is XAttribute range) range.Value = refs.Range(range.Value,sheet);
            }
            changed[part] = cache;
        }
    }

    static void AdjustConnectionParameters(ZipArchive zip, Dictionary<string,XDocument> changed, ColumnReferences refs) {
        foreach (var (_,part) in PartRelations(zip,"xl/workbook.xml").Where(r=>r.type.EndsWith("/connections"))) {
            var connections = ReadXml(zip,part); bool edited = false;
            foreach (var parameter in connections.Descendants(S+"parameter")) {
                if ((string)parameter.Attribute("parameterType") != "cell" || parameter.Attribute("cell") is not XAttribute cell) continue;
                string moved = refs.Formula(cell.Value,null);
                if (moved != cell.Value) { cell.Value = moved; edited = true; }
            }
            // Credentials, SQL and external connection strings are opaque payloads.
            if (edited) changed[part] = connections;
        }
    }

    static long AvailableFieldId(HashSet<long> used, long candidate) {
        if (candidate < 1 || candidate > uint.MaxValue) candidate = 1;
        while (used.Contains(candidate)) candidate = candidate == uint.MaxValue ? 1 : candidate+1;
        return candidate;
    }

    static void ExpandTable(ZipArchive zip, string part, XDocument table, string sheet, ColumnReferences refs,
        Dictionary<string,SortedDictionary<int,List<XElement>>> headers, List<SheetData> patches, Dictionary<string,XDocument> changed) {
        var root = table.Root;
        string range = (string)root.Attribute("ref");
        var ends = range.Split(':'); var (row, first) = ParseAddress(ends[0]); var (_, last) = ParseAddress(ends[^1]);
        var columns = root.Element(S+"tableColumns");
        if (columns == null || columns.Elements(S+"tableColumn").Count() != last-first+1) throw new Exception("An Excel table has inconsistent column definitions. Repair the workbook in Excel before inserting columns.");
        var fields = columns.Elements(S+"tableColumn").ToList();
        var added = new HashSet<XElement>();
        var fieldIds = fields.Select(f=>(long)f.Attribute("id")).ToHashSet();
        long nextId = fieldIds.Max()+1;
        foreach (var ins in refs.For(sheet)) {
            if (ins.Col < first) { first+=ins.Count; last+=ins.Count; }
            else if (ins.Col < last) {
                int at = ins.Col-first+1;
                for (int i=0;i<ins.Count;i++) {
                    nextId = AvailableFieldId(fieldIds,nextId); fieldIds.Add(nextId);
                    var field = new XElement(S+"tableColumn",new XAttribute("id",nextId++));
                    // Differential formats describe the column, independently of its ID.
                    foreach (var a in fields[Math.Max(0,at-1)].Attributes().Where(a=>a.Name.LocalName is "headerRowDxfId" or "dataDxfId" or "totalsRowDxfId" or "headerRowCellStyle" or "dataCellStyle" or "totalsRowCellStyle")) field.Add(new XAttribute(a));
                    fields.Insert(at+i,field); added.Add(field);
                }
                last+=ins.Count;
            }
        }
        if (added.Count == 0) return;
        if (last > MaxCols) throw new Exception("An Excel table would move beyond Excel's last column (XFD).");
        var used = new HashSet<string>(fields.Where(f=>!added.Contains(f)).Select(f=>(string)f.Attribute("name")),StringComparer.OrdinalIgnoreCase);
        var data = patches?.FirstOrDefault(p=>p.Name.Equals(sheet,StringComparison.OrdinalIgnoreCase));
        bool hasHeaders = (int?)root.Attribute("headerRowCount") != 0;
        for (int i=0;i<fields.Count;i++) {
            var field = fields[i]; if (!added.Contains(field)) continue;
            int col = first+i;
            ColumnData edit = data?.Columns.GetValueOrDefault(col-1);
            int at = edit?.Rows.IndexOf(row-1) ?? -1;
            string requested = hasHeaders && at >= 0 ? edit.TextAt(at) : null;
            string name = string.IsNullOrWhiteSpace(requested) ? "Column1" : requested;
            if (name.Length > 255) name = name.Substring(0,255);
            string stem = name; for (int suffix=2; !used.Add(name); suffix++) {
                string tail = suffix.ToString(CultureInfo.InvariantCulture);
                name = stem.Substring(0,Math.Min(stem.Length,255-tail.Length))+tail;
            }
            field.SetAttributeValue("name",Escape(name));
            if (!hasHeaders) continue;
            if (!headers.TryGetValue(sheet,out var rows)) headers[sheet] = rows = new();
            if (!rows.TryGetValue(row,out var cells)) rows[row] = cells = new();
            cells.Add(new XElement(S+"c",new XAttribute("r",ColumnName(col)+row),new XAttribute("t","inlineStr"),new XElement(S+"is",new XElement(S+"t",Escape(name)))));
            // Excel table headings must be unique strings, even when the supplied
            // output heading is empty, numeric or duplicates another table column.
            if (at >= 0) {
                edit.Kinds[at] = 2;
                int textIndex = edit.Texts.FindIndex(t=>t.Key==at);
                if (textIndex>=0) edit.Texts[textIndex] = new(at,name);
                else { edit.Texts.Add(new(at,name)); edit.Texts.Sort((a,b)=>a.Key.CompareTo(b.Key)); }
            }
        }
        columns.ReplaceNodes(fields); columns.SetAttributeValue("count",fields.Count);
        foreach (var (type,target) in PartRelations(zip,part).Where(r=>r.type.EndsWith("/queryTable"))) {
            var query = ReadXml(zip,target);
            var refresh = query.Root.Element(S+"queryTableRefresh");
            var queryFields = refresh?.Element(S+"queryTableFields");
            if (queryFields == null) throw new Exception("A connected Excel table has no query field definitions. Repair it in Excel before inserting columns.");
            var queryIds = queryFields.Elements(S+"queryTableField").Select(f=>(long)f.Attribute("id")).ToHashSet();
            long nextQueryId = Math.Max((long?)refresh.Attribute("nextId") ?? 1,queryIds.DefaultIfEmpty(0).Max()+1);
            foreach (var field in fields.Where(added.Contains)) {
                long id = AvailableFieldId(queryIds,nextQueryId); queryIds.Add(id); nextQueryId = id+1;
                field.SetAttributeValue("queryTableFieldId",id);
                queryFields.Add(new XElement(S+"queryTableField",new XAttribute("id",id),new XAttribute("name",(string)field.Attribute("name")),new XAttribute("tableColumnId",(string)field.Attribute("id")),new XAttribute("dataBound","0")));
            }
            // Preserve the visible field order, including unbound inserted fields.
            var order = fields.Select((f,i)=>(id:(string)f.Attribute("id"),i)).ToDictionary(x=>x.id,x=>x.i);
            queryFields.ReplaceNodes(queryFields.Elements(S+"queryTableField").OrderBy(f=>order.GetValueOrDefault((string)f.Attribute("tableColumnId") ?? "",int.MaxValue)).ToList());
            queryFields.SetAttributeValue("count",queryFields.Elements(S+"queryTableField").Count());
            refresh.SetAttributeValue("preserveSortFilterLayout","1");
            AdjustFeatures(query.Root,sheet,refs);
            refresh.SetAttributeValue("nextId",AvailableFieldId(queryIds,nextQueryId));
            changed[target] = query;
        }
    }

    static List<XElement> InsertedCellStyles(XElement row, string sheet, ColumnReferences refs, int rowNumber) {
        if (refs.For(sheet).Count == 0) return new();
        var styles = new Dictionary<int,string>(); var inserted = new HashSet<int>();
        int column = 0;
        foreach (var cell in row.Elements(S+"c")) {
            column = cell.Attribute("r") == null ? column+1 : ParseAddress((string)cell.Attribute("r")).col;
            if (cell.Attribute("s") is XAttribute style) styles[column] = style.Value;
        }
        foreach (var ins in refs.For(sheet)) {
            string style = styles.GetValueOrDefault(ins.Col == 0 ? 1 : ins.Col);
            styles = styles.ToDictionary(p=>p.Key>ins.Col ? p.Key+ins.Count : p.Key,p=>p.Value);
            inserted = inserted.Select(c=>c>ins.Col ? c+ins.Count : c).ToHashSet();
            if (style != null && style != "0") for (int i=1;i<=ins.Count;i++) { styles[ins.Col+i] = style; inserted.Add(ins.Col+i); }
        }
        if (inserted.Any(c=>c>MaxCols)) throw new Exception("Inserted formatting would move beyond Excel's last column (XFD).");
        return inserted.OrderBy(c=>c).Select(c=>new XElement(S+"c",new XAttribute("r",ColumnName(c)+rowNumber),new XAttribute("s",styles[c]))).ToList();
    }
    static void MergeRowCells(XElement row, IEnumerable<XElement> additions) {
        foreach (var cell in additions) {
            int col = ParseAddress((string)cell.Attribute("r")).col;
            var existing = row.Elements(S+"c").ToList();
            var same = existing.FirstOrDefault(c=>ParseAddress((string)c.Attribute("r")).col == col);
            if (same != null) { if (same.Attribute("s") is XAttribute style) cell.SetAttributeValue("s",style.Value); same.ReplaceWith(cell); continue; }
            var before = existing.FirstOrDefault(c=>ParseAddress((string)c.Attribute("r")).col > col);
            if (before != null) before.AddBeforeSelf(cell);
            else if (existing.Count>0) existing[^1].AddAfterSelf(cell);
            else row.AddFirst(cell);
        }
    }
    static void InsertColumnStyles(XElement columns, string sheet, ColumnReferences refs) {
        foreach (var ins in refs.For(sheet)) {
            var definitions = columns.Elements(S+"col").ToList();
            int inherit = ins.Col == 0 ? 1 : ins.Col;
            var previous = definitions.FirstOrDefault(c=>(int)c.Attribute("min")<=inherit && (int)c.Attribute("max")>=inherit);
            var added = previous == null ? null : new XElement(previous);
            foreach (var c in definitions) {
                int min = (int)c.Attribute("min"), max = (int)c.Attribute("max");
                if (min>ins.Col) min+=ins.Count;
                if (max>ins.Col) max+=ins.Count;
                if (min>MaxCols) { c.Remove(); continue; }
                c.SetAttributeValue("min",min); c.SetAttributeValue("max",Math.Min(max,MaxCols));
            }
            if (added != null && !columns.Elements(S+"col").Any(c=>(int)c.Attribute("min")<=ins.Col+1 && (int)c.Attribute("max")>=ins.Col+1)) {
                added.SetAttributeValue("min",ins.Col+1); added.SetAttributeValue("max",ins.Col+ins.Count); columns.Add(added);
            }
            columns.ReplaceNodes(columns.Elements(S+"col").OrderBy(c=>(int)c.Attribute("min")).ToList());
        }
    }

    static void WriteMissingHeaderRows(XmlWriter writer, SortedDictionary<int,List<XElement>> headers, int before) {
        if (headers == null) return;
        foreach (int row in headers.Keys.TakeWhile(r=>r<before).ToList()) {
            var element = new XElement(S+"row",new XAttribute("r",row));
            AddTableHeaders(element,row,headers); element.WriteTo(writer);
        }
    }
    static void AddTableHeaders(XElement row, int number, SortedDictionary<int,List<XElement>> headers) {
        if (headers == null || !headers.Remove(number,out var cells)) return;
        MergeRowCells(row,cells);
    }
    static void AdjustFeaturesInRow(XElement row, string sheet, ColumnReferences refs) {
        // Row and cell extension payloads can contain xm references too. The cell r
        // and f have already been moved; never adjust them twice.
        foreach (var extension in row.Descendants(S+"extLst").Where(e=>!e.Ancestors(S+"extLst").Any()).ToList()) AdjustFeatures(extension,sheet,refs);
    }

    static void AdjustVml(XDocument drawing, string sheet, ColumnReferences refs) {
        foreach (var data in drawing.Descendants(VmlExcel+"ClientData")) {
            if (data.Element(VmlExcel+"Column") is XElement column) column.Value = (refs.Column(sheet,(int)column+1)-1).ToString(CultureInfo.InvariantCulture);
            foreach (var formula in data.Elements().Where(e=>e.Name.LocalName is "FmlaLink" or "FmlaRange" or "FmlaTxbx" or "FmlaPict" or "FmlaGroup")) formula.Value = refs.Formula(formula.Value,sheet);
            if (data.Element(VmlExcel+"Anchor") is not XElement anchor) continue;
            var coordinates = anchor.Value.Split(',').Select(x=>int.Parse(x.Trim(),CultureInfo.InvariantCulture)).ToArray();
            if (coordinates.Length != 8 || coordinates.Any(n=>n<0) || coordinates[0]>=MaxCols || coordinates[4]>=MaxCols || coordinates[4]<coordinates[0]) throw new Exception("An Excel object has an invalid anchor. Repair it in Excel before inserting columns.");
            bool Flag(string name) { var e = data.Element(VmlExcel+name); return e != null && e.Value.Trim() is "" or "True" or "true" or "1" or "t"; }
            int start = coordinates[0], end = coordinates[4];
            if (Flag("MoveWithCells") || Flag("SizeWithCells")) {
                coordinates[0] = refs.Column(sheet,start+1)-1;
                coordinates[4] = Flag("SizeWithCells") ? refs.Column(sheet,end+1)-1 : end+coordinates[0]-start;
            }
            if (coordinates[4]>=MaxCols) throw new Exception("An Excel object would move beyond Excel's last column (XFD).");
            anchor.Value = string.Join(", ",coordinates);
        }
        // VML groups use a local coordinate system. Moving the outer ClientData
        // anchor carries the nested shapes without rewriting their local geometry.
    }

    static void AdjustDrawing(XElement root, string sheet, ColumnReferences refs) {
        foreach (var anchor in root.DescendantsAndSelf().Where(e=>e.Name == Xdr+"oneCellAnchor" || e.Name == Xdr+"twoCellAnchor" || e.Name.LocalName == "anchor" && (e.Name.Namespace == S || IsExcelExtension(e.Name.Namespace))).ToList()) {
            string behavior = (string)anchor.Attribute("editAs");
            if (behavior == "absolute") continue;
            var columns = anchor.Descendants().Where(e=>e.Name.LocalName == "col" && (e.Name.Namespace == Xdr || e.Name.Namespace == S || IsExcelExtension(e.Name.Namespace))).ToList();
            bool control = anchor.Name.LocalName == "anchor";
            if (control && !XmlFlag(anchor,"moveWithCells") && !XmlFlag(anchor,"sizeWithCells")) continue;
            bool preserveWidth = behavior == "oneCell" || control && !XmlFlag(anchor,"sizeWithCells");
            int delta = columns.Count == 0 ? 0 : refs.Column(sheet,(int)columns[0]+1)-1-(int)columns[0];
            foreach (var col in columns) {
                int moved = preserveWidth ? (int)col+delta : refs.Column(sheet,(int)col+1)-1;
                if (moved>=MaxCols) throw new Exception("An Excel drawing would move beyond Excel's last column (XFD).");
                col.Value = moved.ToString(CultureInfo.InvariantCulture);
            }
        }

    }

    static bool NeedsExcelCalculation(string path) {
        // ClosedXML cannot interpret every Excel extension or control. These packages
        // use the lossless streaming patcher regardless of size; Excel recalculates them.
        using var zip = ZipFile.OpenRead(path);
        foreach (var entry in zip.Entries) {
            string name = entry.FullName.ToLowerInvariant();
            if (name.StartsWith("xl/pivot") || name.StartsWith("xl/slicer") || name.StartsWith("xl/querytables/") || name.StartsWith("xl/ctrlprops/") || name.StartsWith("xl/activex/") || name.StartsWith("xl/threadedcomments/") || name is "xl/metadata.xml" or "xl/connections.xml") return true;
            if (!name.StartsWith("xl/worksheets/") || !name.EndsWith(".xml")) continue;
            using var stream = entry.Open(); using var reader = XmlReader.Create(stream);
            while (reader.Read()) if (reader.NodeType == XmlNodeType.Element && (reader.LocalName == "extLst" || reader.LocalName == "f" && reader.GetAttribute("t") == "dataTable")) return true;
        }
        return false;
    }
}
