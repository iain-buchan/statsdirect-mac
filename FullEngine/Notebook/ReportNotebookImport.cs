using StatsDirect.Templates;
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace StatsDirect.UI.WebReports;

/// <summary>A validated plan for opening a StatsDirect notebook. No files, workbooks, browser content or R code are opened here.</summary>
internal static class ReportNotebookImport
{
    internal sealed class ImportPlan
    {
        internal string Title { get; set; }
        internal JsonElement Entries { get; set; }
        internal string Script { get; set; }
        internal Table[] Tables { get; set; }
        internal string[] Warnings { get; set; }
        internal JsonElement Provenance { get; set; }
    }
    internal sealed class Table
    {
        internal string Title { get; set; }
        internal Column[] Columns { get; set; }
    }
    internal sealed class Column
    {
        internal string Title { get; set; }
        internal object[] Values { get; set; }
    }

    private const int MaximumJsonBytes = 90_000_000;
    private const int MaximumCells = 20000;
    private const int MaximumValues = 5_000_000;
    private const int MaximumSheets = 1000;
    private const int MaximumSections = 1000;
    private const int MaximumColumns = 16384;
    private const int MaximumDataRows = 1048575; // One worksheet row is reserved for the titles.
    private const long MaximumExpandedRecords = 30_000_000;
    private const long MaximumExpandedContent = 60_000_000;
    private const int MaximumCellCharacters = 32767;   // Excel's limit for the text of one cell

    private sealed class SavedEntry
    {
        internal string Id, Title, Operation;
        internal int HelpContextId;
        internal JsonNode Record;
        internal long RecordCost;
    }
    private sealed class Reader
    {
        internal readonly List<Table> Tables = new();
        internal readonly List<string> Warnings = new();
        private readonly HashSet<string> tablePayloads = new(StringComparer.Ordinal);
        private readonly HashSet<string> sheetNames = new(StringComparer.OrdinalIgnoreCase);
        private int values;

        internal Column[] Columns(JsonElement columns, string context)
        {
            RequireArray(columns, context + " columns");
            if (columns.GetArrayLength() > MaximumColumns) throw Error(context + " exceeds Excel's 16,384-column worksheet limit");
            var result = new List<Column>();
            foreach (JsonElement column in columns.EnumerateArray())
            {
                RequireObject(column, context + " column");
                result.Add(new Column { Title = CellText(String(column, "title", context, false) ?? "", context), Values = Values(Property(column, "values", context), context) });
            }
            return result.ToArray();
        }
        internal object[] Values(JsonElement items, string context)
        {
            RequireArray(items, context + " values");
            if (items.GetArrayLength() > MaximumDataRows) throw Error(context + " exceeds Excel's 1,048,576 rows including its header row");
            values += items.GetArrayLength();
            if (values > MaximumValues) throw Error("the notebook data exceed the 5,000,000-value import limit");
            return items.EnumerateArray().Select(item => Scalar(item, context)).ToArray();
        }
        internal void ExtraValues(int count)
        {
            values += count;
            if (values > MaximumValues) throw Error("the notebook data exceed the 5,000,000-value import limit");
        }
        internal void SettingValues(JsonElement value)
        {
            if (value.ValueKind == JsonValueKind.Array) foreach (JsonElement child in value.EnumerateArray()) SettingValues(child);
            else if (value.ValueKind == JsonValueKind.Object) foreach (JsonProperty property in value.EnumerateObject()) SettingValues(property.Value);
            else ExtraValues(1);
        }
        internal void AddTable(string title, Column[] columns)
        {
            if (columns.Length == 0) return;
            // Compare the complete typed payload: a repeated input's name or source alone cannot identify its data.
            string payload = JsonSerializer.Serialize(columns.Select(column => new { column.Title, column.Values }));
            if (!tablePayloads.Add(payload)) return;
            if (Tables.Count >= MaximumSheets) throw Error("the notebook needs more than 1,000 worksheets");
            string stem = new((title ?? "Notebook data").Where(character => character >= ' ' && !"[]:*?/\\".Contains(character)).ToArray());
            stem = stem.Trim().Trim('\'');
            if (stem.Length == 0) stem = "Notebook data";
            if (stem.Length > 31) stem = stem[..31];
            string name = stem;
            for (int suffix = 2; !sheetNames.Add(name); suffix++)
            {
                string ending = " " + suffix.ToString(CultureInfo.InvariantCulture);
                name = stem[..Math.Min(stem.Length, 31 - ending.Length)] + ending;
            }
            Tables.Add(new Table { Title = name, Columns = columns });
        }
        internal void Warn(string warning)
        {
            if (!Warnings.Contains(warning, StringComparer.Ordinal)) Warnings.Add(warning);
        }
    }

    internal static ImportPlan Read(string json, string fallbackTitle)
    {
        if (string.IsNullOrWhiteSpace(json)) throw Error("the file is empty");
        if (json.Length > MaximumJsonBytes || Encoding.UTF8.GetByteCount(json) > MaximumJsonBytes) throw Error("the file exceeds the 90 MB notebook import limit");
        try
        {
            // The plan nests a record one level deeper than the file, and the report browser receives it at the default depth of 64
            using JsonDocument document = JsonDocument.Parse(json, new JsonDocumentOptions { MaxDepth = 60 });
            JsonElement notebook = document.RootElement;
            int nodes = 0;
            ValidateJson(notebook, ref nodes);
            RequireObject(notebook, "the notebook");
            if (Integer(notebook, "nbformat", "the notebook") != 4) throw Error("only Jupyter nbformat 4 notebooks are supported");
            int minor = Integer(notebook, "nbformat_minor", "the notebook");
            if (minor < 0) throw Error("this notebook's nbformat minor version is unsupported");   // a later minor, as a newer IDE may write, is compatible by definition
            JsonElement metadata = Property(notebook, "metadata", "the notebook");
            RequireObject(metadata, "notebook metadata");
            if (!metadata.TryGetProperty("statsdirect", out JsonElement provenance))
                throw Error("this file is not a StatsDirect-exported notebook; general notebook import is not supported");
            RequireObject(provenance, "StatsDirect metadata");
            ValidateKernel(metadata);   // after the StatsDirect check: a notebook of another kernel without StatsDirect metadata is a general notebook, refused as one
            if (Integer(provenance, "version", "StatsDirect metadata") != 1) throw Error("the StatsDirect notebook metadata version is unsupported");
            JsonElement savedEntries = Property(provenance, "entries", "StatsDirect metadata");
            RequireArray(savedEntries, "StatsDirect entries");
            if (savedEntries.GetArrayLength() > 1000) throw Error("the file contains more than 1,000 StatsDirect analysis entries");
            var reader = new Reader();
            var saved = new Dictionary<string, SavedEntry>(StringComparer.Ordinal);
            foreach (JsonElement entry in savedEntries.EnumerateArray())
            {
                SavedEntry parsed = ReadSavedEntry(entry, provenance, reader);
                if (!saved.TryAdd(parsed.Id, parsed)) throw Error("StatsDirect analysis entry identifiers are duplicated");
            }
            JsonElement currentCells = Property(notebook, "cells", "the notebook");
            RequireArray(currentCells, "notebook cells");
            if (currentCells.GetArrayLength() > MaximumCells) throw Error("the notebook contains more than 20,000 cells");
            var entries = new JsonArray();
            var script = new StringBuilder();
            var cellIds = new HashSet<string>(StringComparer.Ordinal);
            var entryIds = new HashSet<string>(saved.Keys, StringComparer.Ordinal);
            JsonObject active = null;
            string activeSource = null;
            long expandedRecords = 0, expandedContent = 2;
            int noteNumber = 0, sectionNumber = 0, position = 0, codeCount = 0, outputCount = 0;
            void Reserve(long cost)
            {
                expandedContent += cost;
                if (expandedContent > MaximumExpandedContent) throw ExpandedError();
            }
            string NewId(string prefix)
            {
                string id;
                do { id = prefix + (++sectionNumber).ToString("D6", CultureInfo.InvariantCulture); } while (!entryIds.Add(id));
                return id;
            }
            JsonObject NewSection(string title, string operation, JsonNode record, string sourceId = null, long recordCost = 0, int helpContextId = 0)
            {
                // A moved cell can start another section of the same analysis. Budget its record before DeepClone allocates it.
                expandedRecords += recordCost;
                if (expandedRecords > MaximumExpandedRecords) throw ExpandedError();
                string sectionId = NewId("notebook-section-");
                Reserve(144 + StringCost(sectionId) + StringCost(title) + StringCost(operation) + StringCost(sourceId) + recordCost);
                var entry = new JsonObject
                {
                    ["id"] = sectionId, ["title"] = title, ["operation"] = operation, ["helpContextId"] = helpContextId,
                    ["record"] = record?.DeepClone(), ["cells"] = new JsonArray()
                };
                if (sourceId != null) entry["sourceEntryId"] = sourceId;
                entries.Add(entry);
                if (entries.Count > MaximumSections) throw Error("the notebook report needs more than 1,000 sections; split it into smaller notebooks before opening it");
                return entry;
            }
            void AddCell(JsonObject section, JsonObject cell)
            {
                Reserve(JsonCost(cell) + 1);
                section["cells"].AsArray().Add(cell);
            }
            void Note(string title, JsonObject cell)
            {
                AddCell(NewSection(title, "", null), cell);
                active = null; activeSource = null;
            }
            foreach (JsonElement cell in currentCells.EnumerateArray())
            {
                position++;
                RequireObject(cell, "notebook cell " + position);
                string type = String(cell, "cell_type", "notebook cell " + position);
                string id = String(cell, "id", "notebook cell " + position, false);
                if (id != null && (id.Length == 0 || id.Length > 64 || id.Any(character => !char.IsAsciiLetterOrDigit(character) && character != '-' && character != '_') || !cellIds.Add(id)))
                    throw Error("notebook cell identifiers are invalid or duplicated");
                string source = Multiline(Property(cell, "source", "notebook cell " + position), "notebook cell source");
                JsonElement cellMetadata = Property(cell, "metadata", "notebook cell " + position);
                RequireObject(cellMetadata, "notebook cell metadata");
                if (type == "code")
                {
                    if (source.Length > 0)
                    {
                        Reserve(StringCost(source) + 120);
                        script.Append("# Current notebook R cell ").Append(position).Append("; imported without execution.\n").Append(source);
                        if (!source.EndsWith('\n')) script.Append('\n');
                        script.Append('\n');
                        codeCount++;
                    }
                    if (cell.TryGetProperty("outputs", out JsonElement outputs))
                    {
                        RequireArray(outputs, "saved R cell outputs");
                        foreach (JsonElement output in outputs.EnumerateArray())
                        {
                            if (++outputCount + currentCells.GetArrayLength() > MaximumCells) throw Error("the notebook contains too many saved output cells");
                            foreach (JsonObject outputCell in ReadOutput(output, outputCount, reader)) Note("Saved notebook R output (cell " + position + ")", outputCell);
                        }
                    }
                    continue;
                }
                if (type is not ("markdown" or "raw")) throw Error("notebook cell type \"" + type + "\" is unsupported");
                var reportCell = new JsonObject { ["source"] = source, ["cellType"] = type };
                if (cell.TryGetProperty("attachments", out JsonElement attachments)) reportCell["attachments"] = ReadAttachments(attachments);
                string role = null, sourceEntry = null, digest = null;
                if (cellMetadata.TryGetProperty("statsdirect", out JsonElement label))
                {
                    RequireObject(label, "StatsDirect cell metadata");
                    role = String(label, "role", "StatsDirect cell metadata", false);
                    sourceEntry = String(label, "entryId", "StatsDirect cell metadata", false);
                    digest = String(label, "digest", "StatsDirect cell metadata", false);
                }
                if (role == "original StatsDirect report")
                {
                    if (sourceEntry == null || !saved.TryGetValue(sourceEntry, out SavedEntry original)) throw Error("a report cell refers to an unknown StatsDirect analysis entry");
                    if (active == null || activeSource != sourceEntry)
                    {
                        active = NewSection(original.Title, original.Operation, original.Record, sourceEntry, original.RecordCost, original.HelpContextId);
                        activeSource = sourceEntry;
                    }
                    AddCell(active, reportCell);
                }
                else if (role == "export note" && digest != null && string.Equals(digest, Digest(source), StringComparison.OrdinalIgnoreCase))
                {
                    // the export's own note, unchanged since it was written: written afresh at each export, so not report content
                }
                else
                {
                    // a notebook editor keeps a cell's metadata through an edit: a note of the export's own that reads differently is the user's now
                    if (role == "export note") reader.Warn("A note written by the export and edited since was kept as a report note.");
                    Note("Notebook note " + (++noteNumber), reportCell);
                }
            }
            if (codeCount > 0) reader.Warn("Current notebook R code is available for review. It has not been run, and edits to it do not establish how the saved native StatsDirect results were produced.");
            if (outputCount > 0) reader.Warn("Saved notebook R outputs are labelled separately from native StatsDirect results; none were recomputed during import.");
            string title = String(provenance, "title", "StatsDirect metadata", false);
            if (string.IsNullOrWhiteSpace(title)) title = string.IsNullOrWhiteSpace(fallbackTitle) ? "Imported notebook" : fallbackTitle;
            // This counts the complete escaped descriptor payload, including restored data and cell-local attachment copies,
            // before SerializeToElement allocates its UTF-8 document or either host sends it to its browser.
            if (JsonCost(entries) > MaximumExpandedContent) throw ExpandedError();
            return new ImportPlan
            {
                Title = title, Entries = JsonSerializer.SerializeToElement(entries), Script = script.ToString(),
                Tables = reader.Tables.ToArray(), Warnings = reader.Warnings.ToArray(), Provenance = provenance.Clone()
            };
        }
        catch (Exception ex) when (ex is JsonException or ArgumentException or FormatException or OverflowException)
        {
            throw new InvalidOperationException("Cannot open this StatsDirect notebook because its content or metadata are malformed. Re-export it from StatsDirect or repair the affected notebook data.", ex);
        }
        catch (InvalidOperationException ex) when (!ex.Message.StartsWith("Cannot open", StringComparison.Ordinal))
        {
            throw new InvalidOperationException("Cannot open this StatsDirect notebook because its content or metadata are malformed. " + ex.Message, ex);
        }
    }

    private static SavedEntry ReadSavedEntry(JsonElement entry, JsonElement provenance, Reader reader)
    {
        RequireObject(entry, "a StatsDirect analysis entry");
        string id = String(entry, "id", "a StatsDirect analysis entry");
        if (id.Length == 0 || id.Length > 200) throw Error("a StatsDirect analysis identifier is invalid");
        string title = String(entry, "title", "a StatsDirect analysis entry");
        string operation = String(entry, "operation", "a StatsDirect analysis entry");
        // the result's help topic, saved since 5.2.9; a notebook without it opens with the report's own topic
        int helpContextId = entry.TryGetProperty("helpContextId", out JsonElement help) && help.ValueKind == JsonValueKind.Number && help.TryGetInt32(out int topic) && topic >= 0 ? topic : 0;
        JsonElement datasets = Property(entry, "datasets", "analysis \"" + title + "\"");
        RequireArray(datasets, "analysis datasets");
        JsonElement originalRecord = Property(entry, "record", "analysis \"" + title + "\"");
        var result = new SavedEntry { Id = id, Title = title, Operation = operation, HelpContextId = helpContextId };
        if (originalRecord.ValueKind == JsonValueKind.Null)
        {
            if (datasets.GetArrayLength() != 0) throw Error("a report section without a run record has unexpected analysis datasets");
            return result;
        }
        RequireObject(originalRecord, "the original run record");
        if (originalRecord.TryGetProperty("version", out JsonElement version) && (!version.TryGetInt32(out int number) || number != 1)) throw Error("an original run record version is unsupported");
        JsonElement inputs = Property(originalRecord, "inputs", "the original run record");
        RequireArray(inputs, "original run inputs");
        JsonElement parameters = Property(originalRecord, "parameters", "the original run record");
        RequireObject(parameters, "original run settings");
        RejectIncomplete(parameters, "original run settings");
        if (inputs.GetArrayLength() != datasets.GetArrayLength()) throw Error("the notebook does not contain every original analysis input dataset");
        var record = JsonNode.Parse(originalRecord.GetRawText()).AsObject();
        JsonObject held = originalRecord.TryGetProperty("data", out JsonElement originalHeld)
            ? JsonNode.Parse(originalHeld.GetRawText()) as JsonObject ?? throw Error("original held data are malformed") : new JsonObject();
        var heldKeys = new HashSet<string>(StringComparer.Ordinal);
        var sources = new JsonArray();
        for (int i = 0; i < inputs.GetArrayLength(); i++)
        {
            JsonElement input = inputs[i], dataset = datasets[i];
            RequireObject(input, "an original input"); RequireObject(dataset, "an input dataset");
            RejectIncomplete(input, "an original input"); RejectIncomplete(dataset, "an input dataset");
            string name = String(input, "name", "an original input"), kind = String(input, "kind", "an original input");
            string context = "analysis \"" + title + "\", input \"" + name + "\"";
            if (Integer(dataset, "inputIndex", context) != i || String(dataset, "name", context) != name || String(dataset, "kind", context) != kind ||
                !Equal(Property(dataset, "originalInput", context), input)) throw Error(context + " no longer matches its original input provenance");
            var source = new JsonObject
            {
                ["inputIndex"] = i, ["name"] = name, ["kind"] = kind,
                ["storedData"] = String(dataset, "storedData", context, false) ?? "Included notebook dataset"
            };
            sources.Add(source);
            if (kind is "frame" or "entered")
            {
                Column[] columns = reader.Columns(Property(dataset, "columns", context), context);
                if (kind == "frame")
                {
                    JsonElement pointers = Property(input, "columns", context); RequireArray(pointers, context + " column pointers");
                    if (pointers.GetArrayLength() == 0 || pointers.GetArrayLength() != columns.Length) throw Error(context + " has incomplete workbook columns");
                    string heldKey = String(input, "held", context, false) ?? name;
                    if (!heldKeys.Add(heldKey)) throw Error(context + " has an ambiguous repeated held-data key");
                    JsonElement savedHeld = default;
                    bool hasHeld = originalHeld.ValueKind == JsonValueKind.Object && originalHeld.TryGetProperty(heldKey, out savedHeld);
                    JsonProperty[] prior = hasHeld && savedHeld.ValueKind == JsonValueKind.Object ? savedHeld.EnumerateObject().ToArray() : null;
                    if (hasHeld && (prior == null || prior.Length != columns.Length)) throw Error(context + " has incomplete original held data");
                    var data = new JsonObject();
                    var names = new HashSet<string>(StringComparer.Ordinal);
                    var pointerTitles = new HashSet<string>(StringComparer.Ordinal);
                    var heldTitles = new HashSet<string>(StringComparer.Ordinal);   // the held object's keys: the columns' titles made unique in column order, as the run record writes them
                    var verified = new JsonArray();
                    for (int column = 0; column < columns.Length; column++)
                    {
                        JsonElement pointer = pointers[column]; RequireObject(pointer, context + " column pointer");
                        ValidatePointer(pointer, context);
                        string pointerTitle = String(pointer, "title", context, false) ?? "";
                        string originalUniqueTitle = UniqueTitle(pointerTitle, pointerTitles);
                        if (!hasHeld && pointerTitle.Length > 0 && columns[column].Title != pointerTitle && columns[column].Title != originalUniqueTitle)
                            throw Error(context + " has a column title that differs from its original input provenance");
                        string hash = String(pointer, "hash", context, false);
                        if (!string.IsNullOrEmpty(hash) && !string.Equals(hash, RunRecord.Hash(columns[column].Values), StringComparison.OrdinalIgnoreCase))
                            throw Error(context + " contains values that differ from the recorded analysis hash");
                        if (string.IsNullOrEmpty(hash) && !hasHeld) reader.Warn("Some historical workbook inputs have no recorded verification hash; their included notebook values cannot be verified against the original analysis.");
                        // By key, not by position: a JSON object carries no order, and Jupyter tooling re-saves a notebook with its keys sorted.
                        if (hasHeld && (!savedHeld.TryGetProperty(UniqueTitle(columns[column].Title, heldTitles), out JsonElement priorValue) || !Equal(priorValue, JsonSerializer.SerializeToElement(columns[column].Values))))
                            throw Error(context + " conflicts with the original held input values or titles");
                        string unique = UniqueTitle(columns[column].Title, names);
                        data[unique] = JsonSerializer.SerializeToNode(columns[column].Values);
                        verified.Add(new JsonObject { ["title"] = columns[column].Title, ["verifiedAgainstRun"] = !string.IsNullOrEmpty(hash), ["originallyHeld"] = hasHeld });
                    }
                    held[heldKey] = data;
                    source["columns"] = verified;
                    foreach (string field in new[] { "file", "path", "sheet" })
                    {
                        string value = String(input, field, context, false);
                        if (value != null) source[field] = value;
                    }
                }
                else if (!Equal(Property(input, "columns", context), Property(dataset, "columns", context))) throw Error(context + " conflicts with the original entered values");
                reader.AddTable(title + " " + name, columns);
            }
            else if (kind is "frame2d" or "covariance")
            {
                JsonElement frames = Property(dataset, "frames", context); RequireArray(frames, context + " nested frames");
                JsonElement value = Property(input, "value", context); RequireObject(value, context + " nested values");
                if (!Equal(Property(value, "frames", context), frames)) throw Error(context + " conflicts with the original nested values");
                for (int group = 0; group < frames.GetArrayLength(); group++)
                {
                    Column[] columns = reader.Columns(frames[group], context);
                    if (kind == "covariance" && (columns.Length == 0 || columns[0].Values.Length != columns.Length - 1)) throw Error(context + " has incomplete covariance predictor levels or outcome replicates");
                    reader.AddTable(title + " " + name + " " + (group + 1), columns);
                }
            }
            else if (kind == "table")
            {
                JsonElement counts = Property(dataset, "counts", context);
                if (!Equal(Property(input, "counts", context), counts)) throw Error(context + " conflicts with the original table counts");
                reader.AddTable(title + " " + name, ReadCounts(input, counts, context, reader));
            }
            else
            {
                JsonElement value = Property(dataset, "value", context);
                if (!Equal(Property(input, "value", context), value)) throw Error(context + " conflicts with the original saved input value");
                reader.SettingValues(value);
            }
        }
        if (held.Count > 0) record["data"] = held;
        JsonElement archive = originalRecord;
        if (originalRecord.TryGetProperty("notebookImport", out JsonElement earlier))
        {
            RequireObject(earlier, "earlier notebook provenance");
            archive = Property(earlier, "originalRecord", "earlier notebook provenance");
            RequireObject(archive, "the archived original run record");
        }
        var imported = new JsonObject
        {
            ["version"] = 1, ["entryId"] = id, ["originalRecord"] = JsonNode.Parse(archive.GetRawText()),
            ["dataOrigin"] = "Values restored from notebook datasets; this is not a new acquisition-time snapshot or an execution of the current notebook code.",
            ["datasets"] = sources
        };
        foreach (string field in new[] { "title", "appVersion", "engineVersion" })
        {
            string value = String(provenance, field, "StatsDirect metadata", false);
            if (value != null) imported[field] = value;
        }
        record["notebookImport"] = imported;
        result.Record = record;
        result.RecordCost = JsonCost(record);
        return result;
    }

    private static void ValidatePointer(JsonElement pointer, string context)
    {
        if (Integer(pointer, "column", context) < 1) throw Error(context + " has an invalid original column pointer");
        JsonElement rows = Property(pointer, "rows", context); RequireArray(rows, context + " original row pointer");
        if (rows.GetArrayLength() != 2 || rows[0].ValueKind != JsonValueKind.Number || !rows[0].TryGetInt32(out int first) || first < 1 || rows[1].ValueKind != JsonValueKind.Number || !rows[1].TryGetInt32(out _))
            throw Error(context + " has an invalid original row pointer");
        if (pointer.TryGetProperty("hasTitle", out JsonElement title) && title.ValueKind is not (JsonValueKind.True or JsonValueKind.False)) throw Error(context + " has a malformed original title flag");
    }

    private static Column[] ReadCounts(JsonElement input, JsonElement counts, string context, Reader reader)
    {
        RequireArray(counts, context + " table counts");
        if (counts.GetArrayLength() == 0 || counts.GetArrayLength() > MaximumDataRows) throw Error(context + " has no usable counts or exceeds Excel's worksheet rows");
        var rows = new List<object[]>();
        int width = -1;
        foreach (JsonElement row in counts.EnumerateArray())
        {
            object[] values = reader.Values(row, context);
            if (width < 0) width = values.Length;
            if (width == 0 || values.Length != width || values.Any(value => value is not (double or null))) throw Error(context + " has malformed numeric table counts");
            rows.Add(values);
        }
        string[] labels = Labels(input, "columnLabels", width, context);
        string[] rowLabels = Labels(input, "rowLabels", rows.Count, context);
        if (rowLabels != null) reader.ExtraValues(rowLabels.Length);
        if (input.TryGetProperty("columns", out JsonElement originalColumns))
        {
            Column[] recorded = reader.Columns(originalColumns, context);
            if (recorded.Length != width || recorded.Where((column, index) => column.Values.Length != rows.Count ||
                column.Values.Where((value, row) => !Equals(value, rows[row][index])).Any()).Any()) throw Error(context + " has table columns inconsistent with its original counts");
        }
        if (width + (rowLabels == null ? 0 : 1) > MaximumColumns) throw Error(context + " exceeds Excel's 16,384-column worksheet limit");
        var columns = new List<Column>();
        if (rowLabels != null) columns.Add(new Column { Title = CellText(String(input, "rowsTitle", context, false) ?? "Row", context), Values = rowLabels.Cast<object>().ToArray() });
        for (int column = 0; column < width; column++) columns.Add(new Column
        {
            Title = labels?[column] ?? "Column " + (column + 1), Values = rows.Select(row => row[column]).ToArray()
        });
        return columns.ToArray();
    }

    private static string[] Labels(JsonElement input, string name, int count, string context)
    {
        if (!input.TryGetProperty(name, out JsonElement labels)) return null;
        RequireArray(labels, context + " " + name);
        if (labels.GetArrayLength() != count || labels.EnumerateArray().Any(label => label.ValueKind != JsonValueKind.String)) throw Error(context + " has incomplete table labels");
        return labels.EnumerateArray().Select(label => CellText(label.GetString(), context)).ToArray();
    }

    private static IEnumerable<JsonObject> ReadOutput(JsonElement output, int number, Reader reader)
    {
        RequireObject(output, "a saved R output");
        string type = String(output, "output_type", "a saved R output");
        if (type == "stream") return new[] { new JsonObject { ["cellType"] = "raw", ["source"] = Multiline(Property(output, "text", "a saved R output"), "saved R output text") } };
        if (type == "error")
        {
            string text = (String(output, "ename", "a saved R error", false) ?? "R error") + ": " + (String(output, "evalue", "a saved R error", false) ?? "");
            if (output.TryGetProperty("traceback", out JsonElement trace)) text += "\n" + string.Join("\n", Strings(trace, "saved R traceback"));
            return new[] { new JsonObject { ["cellType"] = "raw", ["source"] = text } };
        }
        if (type is not ("display_data" or "execute_result"))
        {
            reader.Warn("An unsupported saved notebook output was omitted; no widgets or JavaScript were loaded.");
            return System.Array.Empty<JsonObject>();
        }
        JsonElement data = Property(output, "data", "a saved R output"); RequireObject(data, "saved R output MIME data");
        var bundle = new JsonObject();
        foreach (string mime in new[] { "image/svg+xml", "image/png", "image/jpeg", "image/gif" })
            if (data.TryGetProperty(mime, out JsonElement image)) bundle[mime] = ValidateImage(mime, Multiline(image, "saved output image"));
        if (bundle.Count > 0)
        {
            string name = "saved-output-" + number + (bundle.ContainsKey("image/svg+xml") ? ".svg" : bundle.ContainsKey("image/png") ? ".png" : bundle.ContainsKey("image/jpeg") ? ".jpg" : ".gif");
            return new[] { new JsonObject { ["cellType"] = "markdown", ["source"] = "![Saved notebook R output](attachment:" + name + ")", ["attachments"] = new JsonObject { [name] = bundle } } };
        }
        if (data.TryGetProperty("text/html", out JsonElement html)) return new[] { new JsonObject { ["cellType"] = "html", ["source"] = Multiline(html, "saved HTML output") } };
        if (data.TryGetProperty("text/plain", out JsonElement plain)) return new[] { new JsonObject { ["cellType"] = "raw", ["source"] = Multiline(plain, "saved plain-text output") } };
        reader.Warn("An unsupported saved notebook output was omitted; no widgets or JavaScript were loaded.");
        return System.Array.Empty<JsonObject>();
    }

    private static JsonObject ReadAttachments(JsonElement attachments)
    {
        RequireObject(attachments, "cell attachments");
        var result = new JsonObject();
        int count = 0;
        foreach (JsonProperty image in attachments.EnumerateObject())
        {
            if (++count > 2000 || image.Name.Length == 0 || image.Name.Length > 1000) throw Error("notebook cell attachments are invalid or too numerous");
            RequireObject(image.Value, "an attachment MIME bundle");
            var bundle = new JsonObject();
            foreach (JsonProperty mime in image.Value.EnumerateObject())
            {
                if (mime.Name is not ("image/svg+xml" or "image/png" or "image/jpeg" or "image/gif")) throw Error("a report attachment uses an unsupported image format");
                bundle[mime.Name] = ValidateImage(mime.Name, Multiline(mime.Value, "attachment data"));
            }
            if (bundle.Count == 0) throw Error("a report attachment contains no image data");
            result[image.Name] = bundle;
        }
        return result;
    }

    private static string ValidateImage(string mime, string source)
    {
        if (string.IsNullOrWhiteSpace(source)) throw Error("a notebook image is empty");
        if (mime != "image/svg+xml")
        {
            byte[] bytes;
            try { bytes = Convert.FromBase64String(source); }
            catch (FormatException) { throw Error("a notebook image contains invalid base64 data"); }
            if (bytes.Length == 0) throw Error("a notebook image is empty");
            if (mime == "image/png" && (bytes.Length < 8 || bytes[0] != 137 || bytes[1] != 80 || bytes[2] != 78 || bytes[3] != 71 || bytes[4] != 13 || bytes[5] != 10 || bytes[6] != 26 || bytes[7] != 10))
                throw Error("a notebook PNG attachment has invalid image data");
        }
        return source;
    }

    private static void ValidateKernel(JsonElement metadata)
    {
        JsonElement kernel = Property(metadata, "kernelspec", "notebook metadata"); RequireObject(kernel, "notebook kernel metadata");
        string name = String(kernel, "name", "notebook kernel metadata"), language = String(kernel, "language", "notebook kernel metadata", false);
        if (language == null && name == "ir") language = "R";
        if (!string.Equals(language, "R", StringComparison.OrdinalIgnoreCase)) throw Error("this notebook uses an unsupported kernel; only R StatsDirect notebooks can be opened");
        if (metadata.TryGetProperty("language_info", out JsonElement info))
        {
            RequireObject(info, "notebook language metadata");
            if (!string.Equals(String(info, "name", "notebook language metadata"), "R", StringComparison.OrdinalIgnoreCase)) throw Error("this notebook uses an unsupported language; only R notebooks can be opened");
        }
    }

    private static object Scalar(JsonElement value, string context) => value.ValueKind switch
    {
        JsonValueKind.Null => null,
        JsonValueKind.True => true,
        JsonValueKind.False => false,
        JsonValueKind.String => CellText(value.GetString(), context),
        JsonValueKind.Number when value.TryGetDouble(out double number) && double.IsFinite(number) => number,
        _ => throw Error(context + " contains a non-finite or unsupported worksheet value")
    };
    private static string Digest(string text) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(text ?? "")));
    // Text destined for one worksheet cell: longer than Excel's limit, the grid would write it cut short or not at all
    private static string CellText(string text, string context)
    {
        if (text != null && text.Length > MaximumCellCharacters) throw Error(context + " contains text longer than Excel's 32,767-character cell limit");
        return text;
    }
    private static string UniqueTitle(string title, HashSet<string> used)
    {
        string candidate = title;
        for (int suffix = 2; !used.Add(candidate); suffix++) candidate = title + "_" + suffix.ToString(CultureInfo.InvariantCulture);
        return candidate;
    }
    private static void RejectIncomplete(JsonElement value, string context)
    {
        if (value.ValueKind == JsonValueKind.Object)
            foreach (JsonProperty property in value.EnumerateObject())
            {
                if ((property.Name == "omitted" || property.Name == "truncated" || property.Name == "unavailable" || property.Name == "changed") && property.Value.ValueKind == JsonValueKind.True)
                    throw Error(context + " contains omitted, truncated, unavailable or changed input data");
                if (property.Name == "Unavailable" && property.Value.ValueKind == JsonValueKind.String && property.Value.GetString().Length > 0) throw Error(context + " contains unavailable input data");
                RejectIncomplete(property.Value, context);
            }
        else if (value.ValueKind == JsonValueKind.Array)
            foreach (JsonElement child in value.EnumerateArray()) RejectIncomplete(child, context);
    }
    private static void ValidateJson(JsonElement value, ref int nodes)
    {
        if (++nodes > 25_000_000) throw Error("notebook metadata are too large");
        if (value.ValueKind == JsonValueKind.Object)
        {
            var names = new HashSet<string>(StringComparer.Ordinal);
            foreach (JsonProperty property in value.EnumerateObject())
            {
                if (!names.Add(property.Name)) throw Error("the notebook contains duplicate JSON fields");
                ValidateJson(property.Value, ref nodes);
            }
        }
        else if (value.ValueKind == JsonValueKind.Array)
            foreach (JsonElement child in value.EnumerateArray()) ValidateJson(child, ref nodes);
        else if (value.ValueKind == JsonValueKind.Number && (!value.TryGetDouble(out double number) || !double.IsFinite(number))) throw Error("the notebook contains non-finite numeric data");
    }
    private static bool Equal(JsonElement first, JsonElement second) => JsonElement.DeepEquals(first, second);
    private static long JsonCost(JsonNode node)
    {
        long count = 0;
        void Add(long size)
        {
            count += size;
            if (count > MaximumExpandedContent) throw ExpandedError();
        }
        void Visit(JsonNode current)
        {
            if (current == null) { Add(4); return; }
            if (current is JsonObject map)
            {
                Add(2);
                foreach (KeyValuePair<string, JsonNode> property in map) { Add(StringCost(property.Key) + 2); Visit(property.Value); }
            }
            else if (current is JsonArray array)
            {
                Add(2);
                foreach (JsonNode item in array) { Add(1); Visit(item); }
            }
            else if (current.GetValueKind() == JsonValueKind.String) Add(StringCost(current.GetValue<string>()));
            else Add(current.ToJsonString().Length);
        }
        Visit(node);
        return count;
    }
    // Conservative UTF-8 size for System.Text.Json's default escaping, without allocating an encoded copy of large HTML/code.
    private static long StringCost(string value)
    {
        if (value == null) return 4;
        long count = 2;
        foreach (char character in value)
        {
            if (character == '\\' || character is '\b' or '\f' or '\n' or '\r' or '\t') count += 2;
            else if (character > 127 || character == '"' || JavaScriptEncoder.Default.WillEncode(character)) count += 6;
            else count++;
            if (count > MaximumExpandedContent) throw ExpandedError();
        }
        return count;
    }
    private static InvalidOperationException ExpandedError() => Error("the expanded report, restored run records or current R code are too large to open safely; split the notebook into smaller reports before opening it");
    private static string Multiline(JsonElement value, string context) => value.ValueKind == JsonValueKind.String ? value.GetString() : string.Concat(Strings(value, context));
    private static string[] Strings(JsonElement value, string context)
    {
        RequireArray(value, context);
        if (value.EnumerateArray().Any(line => line.ValueKind != JsonValueKind.String)) throw Error(context + " must contain only strings");
        return value.EnumerateArray().Select(line => line.GetString()).ToArray();
    }
    private static int Integer(JsonElement parent, string name, string context)
    {
        JsonElement value = Property(parent, name, context);
        if (value.ValueKind != JsonValueKind.Number || !value.TryGetInt32(out int integer)) throw Error(context + " has an invalid " + name);
        return integer;
    }
    private static string String(JsonElement parent, string name, string context, bool required = true)
    {
        if (!parent.TryGetProperty(name, out JsonElement value))
        {
            if (required) throw Error(context + " is missing " + name);
            return null;
        }
        if (value.ValueKind == JsonValueKind.Null && !required) return null;
        if (value.ValueKind != JsonValueKind.String) throw Error(context + " has an invalid " + name);
        return value.GetString();
    }
    private static JsonElement Property(JsonElement parent, string name, string context)
    {
        if (!parent.TryGetProperty(name, out JsonElement value)) throw Error(context + " is missing " + name);
        return value;
    }
    private static void RequireObject(JsonElement value, string context)
    {
        if (value.ValueKind != JsonValueKind.Object) throw Error(context + " must be a JSON object");
    }
    private static void RequireArray(JsonElement value, string context)
    {
        if (value.ValueKind != JsonValueKind.Array) throw Error(context + " must be a JSON array");
    }
    private static InvalidOperationException Error(string detail) => new("Cannot open this StatsDirect notebook: " + detail + ". Re-export it from StatsDirect or repair the affected notebook content.");
}
