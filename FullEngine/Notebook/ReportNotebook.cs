using StatsDirect.R;
using StatsDirect.Templates;
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace StatsDirect.UI.WebReports;

/// <summary>
/// A portable copy of the edited report and its unexecuted R replay. The original run records are retained verbatim as JSON;
/// workbook values resolved for this export live separately, so they cannot be mistaken for an acquisition-time snapshot.
/// Nothing in this class evaluates R or changes the report.
/// </summary>
internal static class ReportNotebook
{
    private const int MaximumEntries = 1000;
    private const int MaximumCells = 20000;
    private const int MaximumInputs = 20000;
    private const int MaximumColumns = 20000;
    private const int MaximumCharacters = 90_000_000;
    private const int MaximumValues = 5_000_000;
    private const int MaximumNodes = 10_000_000;
    private static readonly CultureInfo invariant = CultureInfo.InvariantCulture;

    private sealed class Budget
    {
        private long characters, values, nodes;
        internal void Text(string text)
        {
            characters += text?.Length ?? 0;
            if (characters > MaximumCharacters) throw Failure("the report and its input text are too large", "Export a smaller report.");
        }
        internal void Value()
        {
            if (++values > MaximumValues) throw Failure("the recorded inputs contain too many values", "Export fewer analyses together.");
        }
        internal void Node()
        {
            if (++nodes > MaximumNodes) throw Failure("the recorded inputs are too large", "Export fewer analyses together.");
        }
    }

    private sealed class ResolvedFrame
    {
        internal FramePointer Pointer;
        internal FrameValues Values;
    }

    internal static string Write(JsonElement snapshot, string title, Func<FramePointer, FrameValues> read, string appVersion)
    {
        try { return WriteNotebook(snapshot, title, read, appVersion); }
        catch (Exception ex) when (ex is JsonException or FormatException or OverflowException or ArgumentException)
        {
            throw new InvalidOperationException("Cannot export a complete Jupyter notebook because report metadata are malformed. Reopen the report or rerun the affected analysis.", ex);
        }
        catch (InvalidOperationException ex) when (!ex.Message.StartsWith("Cannot export", StringComparison.Ordinal))
        {
            throw new InvalidOperationException("Cannot export a complete Jupyter notebook because report metadata are malformed. Reopen the report or rerun the affected analysis.", ex);
        }
    }

    private static string WriteNotebook(JsonElement snapshot, string title, Func<FramePointer, FrameValues> read, string appVersion)
    {
        RequireObject(snapshot, "the report snapshot");
        if (!snapshot.TryGetProperty("version", out JsonElement version) || version.ValueKind != JsonValueKind.Number || !version.TryGetInt32(out int number) || number != 1)
            throw Failure("the report snapshot has an unsupported version", "Reopen the report in this version of StatsDirect.");
        JsonElement entries = Array(snapshot, "entries", "the report snapshot");
        if (entries.GetArrayLength() > MaximumEntries) throw Failure("the report contains too many sections", "Export a smaller report.");
        string reportHtml = RequiredText(snapshot, "reportHtml", "the report snapshot");
        string engineVersion = Text(snapshot, "engineVersion", "the report snapshot");
        var budget = new Budget();
        budget.Text(reportHtml);
        budget.Text(engineVersion);
        title = string.IsNullOrWhiteSpace(title) ? "StatsDirect report" : title;
        budget.Text(title);
        budget.Text(appVersion);
        var cells = new JsonArray();
        var savedEntries = new JsonArray();
        var entryIds = new HashSet<string>(StringComparer.Ordinal);
        var resolved = new Dictionary<string, ResolvedFrame>(StringComparer.Ordinal);
        int cellNumber = 0;

        JsonObject Cell(string type, string source, JsonObject metadata, JsonNode attachments = null)
        {
            if (++cellNumber > MaximumCells) throw Failure("the notebook contains too many cells", "Export a smaller report.");
            var cell = new JsonObject
            {
                ["id"] = "statsdirect-" + cellNumber.ToString("D6", invariant),
                ["cell_type"] = type,
                ["metadata"] = new JsonObject { ["statsdirect"] = metadata },
                ["source"] = source
            };
            if (type == "code") { cell["execution_count"] = null; cell["outputs"] = new JsonArray(); }
            else if (attachments != null) cell["attachments"] = attachments;
            return cell;
        }
        void Note(string text, string entryId = null) => cells.Add(Cell("markdown", text, new JsonObject { ["role"] = "export note", ["entryId"] = entryId }));

        Note("# " + Markdown(title) + "\n\nExported from StatsDirect" + (string.IsNullOrWhiteSpace(appVersion) ? "." : " " + Markdown(appVersion) + ".") +
            "\n\nThe report cells preserve saved report content, including native StatsDirect results and your edits. " +
            "The R cells contain data, recorded settings and available replay code; they have not been executed, and their outputs are empty. " +
            "Run them with an R Jupyter kernel to produce new R results. Each R cell uses `local({ ... })` so its analysis variables do not leak into later cells. " +
            "The complete HTML report, original run records and all resolved inputs are retained in the notebook's StatsDirect metadata.");

        foreach (JsonElement entry in entries.EnumerateArray())
        {
            RequireObject(entry, "a report section");
            string id = RequiredText(entry, "id", "a report section");
            if (id.Length == 0 || id.Length > 200 || !entryIds.Add(id)) throw Failure("report section identifiers are missing or duplicated", "Reopen the report.");
            string entryTitle = Text(entry, "title", "a report section") ?? "Analysis";
            string operation = Text(entry, "operation", "a report section") ?? "";
            string html = RequiredText(entry, "html", "a report section");
            budget.Text(entryTitle); budget.Text(operation); budget.Text(html);
            JsonElement reportCells = Array(entry, "cells", "report section \"" + entryTitle + "\"");
            foreach (JsonElement reportCell in reportCells.EnumerateArray())
            {
                RequireObject(reportCell, "a report cell");
                string source = RequiredText(reportCell, "source", "a report cell");
                budget.Text(source);
                JsonNode attachments = null;
                if (reportCell.TryGetProperty("attachments", out JsonElement images))
                {
                    ValidateAttachments(images, budget);
                    attachments = Copy(images);
                }
                cells.Add(Cell("markdown", source, new JsonObject { ["role"] = "original StatsDirect report", ["entryId"] = id }, attachments));
            }
            var saved = new JsonObject { ["id"] = id, ["title"] = entryTitle, ["operation"] = operation, ["html"] = html };
            savedEntries.Add(saved);
            if (!entry.TryGetProperty("record", out JsonElement record) || record.ValueKind == JsonValueKind.Null)
            {
                saved["record"] = null;
                saved["datasets"] = new JsonArray();
                Note("**" + Markdown(entryTitle) + ":** This report section has no saved analysis run record. Its original report is included; its input data and R replay cannot be reconstructed.", id);
                continue;
            }
            RequireObject(record, "the run record of \"" + entryTitle + "\"");
            if (record.TryGetProperty("version", out JsonElement recordVersion) && (recordVersion.ValueKind != JsonValueKind.Number || !recordVersion.TryGetInt32(out int recordNumber) || recordNumber != 1))
                throw Failure("\"" + entryTitle + "\" has an unsupported run-record version", "Reopen it in the StatsDirect version that created it.");
            Inspect(record, budget, "the run record of \"" + entryTitle + "\"", 0);
            saved["record"] = Copy(record);
            var datasets = new JsonArray();
            saved["datasets"] = datasets;
            var unverified = new List<string>();
            ResolveInputs(record, entryTitle, datasets, resolved, read, budget, unverified);
            FrameValues ReadResolved(FramePointer pointer)
            {
                if (!resolved.TryGetValue(Key(pointer), out ResolvedFrame frame))
                    throw Failure("an input of \"" + entryTitle + "\" could not be matched to its resolved dataset", "Rerun the analysis and export the new report.");
                // FrameReader may have found these same values in a moved column. Keep the script's provenance comment accurate.
                for (int i = 0; i < pointer.Columns.Count; i++) pointer.Columns[i].Column = frame.Pointer.Columns[i].Column;
                return frame.Values;
            }
            RScript script;
            try { script = RScriptWriter.Write(record, entryTitle, ReadResolved); }
            catch (Exception ex) { throw new InvalidOperationException("Cannot export the R replay for \"" + entryTitle + "\". Rerun the analysis or repair its saved run record. " + ex.Message, ex); }
            if (script.DataUnavailable) throw Failure("the R replay for \"" + entryTitle + "\" is missing input data", "Open the unchanged original workbook, or rerun the analysis and export its new report.");
            saved["hasRecipe"] = script.HasRecipe;
            saved["replayDetail"] = script.Detail;
            if (!script.HasRecipe)
                Note("**" + Markdown(entryTitle) + ":** An R analysis recipe is unavailable for this method. The following unexecuted cell contains the available data and settings for your own analysis." +
                    (string.IsNullOrEmpty(script.Detail) ? "" : " " + Markdown(script.Detail)), id);
            foreach (string name in unverified.Distinct(StringComparer.Ordinal))
                Note("**Input provenance:** The saved record has no verification hash for " + Markdown(name) + " in **" + Markdown(entryTitle) + "**. The included workbook values could not be checked against the original analysis.", id);
            string isolated = "# Generated R replay; nothing in this cell has been executed.\nlocal({\n" +
                string.Join("\n", script.Text.Replace("\r\n", "\n").TrimEnd('\n').Split('\n').Select(line => "  " + line)) + "\n})\n";
            budget.Text(isolated);
            cells.Add(Cell("code", isolated, new JsonObject { ["role"] = "unexecuted R replay", ["entryId"] = id, ["hasRecipe"] = script.HasRecipe }));
        }
        var provenance = new JsonObject
        {
            ["version"] = 1,
            ["application"] = "StatsDirect",
            ["appVersion"] = appVersion ?? "",
            ["title"] = title,
            ["reportHtml"] = reportHtml,
            ["execution"] = "R was not run during export. Report cells contain original native StatsDirect output.",
            ["cellScope"] = "Each R replay is wrapped in local({ ... }) to isolate its analysis variables.",
            ["valueEncoding"] = "RunRecord JSON: numbers, text (including ISO 8601 dates), boolean flags, and null for missing values. Date strings retain their original encoding; no date type is guessed from text.",
            ["entries"] = savedEntries
        };
        if (engineVersion != null) provenance["engineVersion"] = engineVersion;
        if (snapshot.TryGetProperty("revision", out JsonElement revision))
        {
            if (revision.ValueKind != JsonValueKind.Number || !revision.TryGetInt64(out _)) throw Failure("the report revision is malformed", "Reopen the report.");
            provenance["revision"] = Copy(revision);
        }
        var notebook = new JsonObject
        {
            ["nbformat"] = 4,
            ["nbformat_minor"] = 5,
            ["metadata"] = new JsonObject
            {
                ["kernelspec"] = new JsonObject { ["name"] = "ir", ["display_name"] = "R", ["language"] = "R" },
                ["language_info"] = new JsonObject { ["name"] = "R" },
                ["statsdirect"] = provenance
            },
            ["cells"] = cells
        };
        return notebook.ToJsonString(new JsonSerializerOptions { WriteIndented = true });
    }

    private static void ResolveInputs(JsonElement record, string title, JsonArray datasets, Dictionary<string, ResolvedFrame> cache,
        Func<FramePointer, FrameValues> read, Budget budget, List<string> unverified)
    {
        if (!record.TryGetProperty("parameters", out JsonElement parameters))
            throw Failure("the run record of \"" + title + "\" has no parameters object", "Rerun the analysis and export the new report.");
        RequireObject(parameters, "the settings of \"" + title + "\"");
        RejectIncompleteInput(parameters, "the settings of \"" + title + "\"");
        JsonElement held = default;
        if (record.TryGetProperty("data", out held)) RequireObject(held, "the held data of \"" + title + "\"");
        if (!record.TryGetProperty("inputs", out JsonElement inputs) || inputs.ValueKind != JsonValueKind.Array || inputs.GetArrayLength() > MaximumInputs)
            throw Failure("the inputs array of \"" + title + "\" is missing, malformed or too large", "Rerun the analysis and export the new report.");
        var heldKeys = new HashSet<string>(StringComparer.Ordinal);
        int index = 0;
        foreach (JsonElement input in inputs.EnumerateArray())
        {
            RequireObject(input, "an input of \"" + title + "\"");
            string name = RequiredText(input, "name", "an input of \"" + title + "\"");
            string kind = RequiredText(input, "kind", "input \"" + name + "\"");
            string context = "\"" + title + "\", input \"" + name + "\"";
            RejectIncompleteInput(input, context);
            var dataset = new JsonObject { ["inputIndex"] = index++, ["name"] = name, ["kind"] = kind, ["originalInput"] = Copy(input) };
            datasets.Add(dataset);
            if (kind == "frame")
            {
                ValidatePointer(input, context);
                FramePointer pointer = FramePointer.From(input);
                string heldKey = Text(input, "held", context) ?? name;
                var columns = new JsonArray();
                dataset["columns"] = columns;
                if (held.ValueKind == JsonValueKind.Object && held.TryGetProperty(heldKey, out JsonElement data))
                {
                    RequireObject(data, "the held values for " + context);
                    if (!heldKeys.Add(heldKey)) throw Failure(context + " reuses an ambiguous held-data key", "Rerun the analysis and export the new report.");
                    JsonProperty[] stored = data.EnumerateObject().ToArray();
                    if (stored.Length != pointer.Columns.Count) throw Failure(context + " has incomplete held columns", "Rerun the analysis and export the new report.");
                    dataset["storedData"] = "Original values held with the saved run";
                    for (int i = 0; i < stored.Length; i++)
                    {
                        ValidateValues(stored[i].Value, context, budget);
                        VerifyHash(pointer.Columns[i], JsonValues(stored[i].Value), context);
                        columns.Add(new JsonObject { ["title"] = stored[i].Name, ["values"] = Copy(stored[i].Value) });
                    }
                }
                else
                {
                    string key = Key(pointer);
                    if (!cache.TryGetValue(key, out ResolvedFrame frame))
                    {
                        FrameValues values;
                        try { values = read?.Invoke(pointer); }
                        catch (Exception ex) { throw new InvalidOperationException("Cannot export a complete Jupyter notebook: " + context + " could not be read. Open the unchanged original workbook, or rerun the analysis. " + ex.Message, ex); }
                        if (values == null || !string.IsNullOrEmpty(values.Unavailable))
                            throw Failure(context + " could not be read" + (string.IsNullOrWhiteSpace(values?.Unavailable) ? "" : " (" + values.Unavailable + ")"), "Open the unchanged original workbook, or rerun the analysis and export its new report.");
                        if (values.Columns.Count != pointer.Columns.Count) throw Failure(context + " returned incomplete columns", "Open the unchanged original workbook, or rerun the analysis.");
                        var copied = new FrameValues();
                        for (int i = 0; i < values.Columns.Count; i++)
                        {
                            ColumnValues column = values.Columns[i];
                            if (column?.Values == null) throw Failure(context + " returned an incomplete column", "Open the unchanged original workbook, or rerun the analysis.");
                            if (column.Changed) throw Changed(context, column.Title ?? pointer.Columns[i].Title);
                            if (column.Values.Length > MaximumValues) throw Failure(context + " contains too many values", "Export a smaller input selection.");
                            object[] clean = column.Values.Select(value => Normalize(value, context)).ToArray();
                            VerifyHash(pointer.Columns[i], clean, context);
                            copied.Columns.Add(new ColumnValues { Title = column.Title ?? pointer.Columns[i].Title, Values = clean, Moved = column.Moved });
                        }
                        frame = new ResolvedFrame { Pointer = pointer, Values = copied };
                        cache.Add(key, frame);
                    }
                    dataset["storedData"] = "Workbook values captured for this export; saved verification hashes were checked where present";
                    dataset["resolvedPointer"] = JsonSerializer.SerializeToNode(frame.Pointer);
                    for (int i = 0; i < frame.Values.Columns.Count; i++)
                    {
                        ColumnValues column = frame.Values.Columns[i];
                        foreach (object value in column.Values) { budget.Value(); if (value is string text) budget.Text(text); }
                        if (string.IsNullOrEmpty(pointer.Columns[i].Hash)) unverified.Add(name + ", column \"" + column.Title + "\"");
                        columns.Add(new JsonObject
                        {
                            ["title"] = column.Title,
                            ["values"] = JsonSerializer.SerializeToNode(column.Values),
                            ["moved"] = column.Moved,
                            ["verifiedAgainstRun"] = !string.IsNullOrEmpty(pointer.Columns[i].Hash)
                        });
                    }
                }
            }
            else if (kind == "entered")
            {
                JsonElement columns = Array(input, "columns", context);
                ValidateColumns(columns, context, budget);
                dataset["storedData"] = "Original entered values held with the saved run";
                dataset["columns"] = Copy(columns);
            }
            else if (kind is "frame2d" or "covariance")
            {
                if (!input.TryGetProperty("value", out JsonElement value)) throw Failure(context + " has no nested data", "Rerun the analysis and export the new report.");
                RequireObject(value, context);
                JsonElement frames = Array(value, "frames", context + " nested data");
                if (frames.GetArrayLength() > MaximumColumns) throw Failure(context + " has too many nested frames", "Export a smaller analysis.");
                foreach (JsonElement columns in frames.EnumerateArray()) ValidateColumns(columns, context, budget);
                dataset["storedData"] = "Original nested values held with the saved run";
                dataset["frames"] = Copy(frames);
            }
            else if (kind == "table")
            {
                JsonElement counts = Array(input, "counts", context);
                int width = -1;
                if (counts.GetArrayLength() == 0) throw Failure(context + " has no table counts", "Rerun the analysis.");
                foreach (JsonElement row in counts.EnumerateArray())
                {
                    ValidateValues(row, context, budget);
                    if (width < 0) width = row.GetArrayLength();
                    if (width == 0 || row.GetArrayLength() != width || row.EnumerateArray().Any(v => v.ValueKind is not (JsonValueKind.Number or JsonValueKind.Null)))
                        throw Failure(context + " has malformed table counts", "Rerun the analysis.");
                }
                if (input.TryGetProperty("columns", out JsonElement columns)) ValidateColumns(columns, context, budget);
                dataset["storedData"] = "Original table counts held with the saved run";
                dataset["counts"] = Copy(counts);
            }
            else
            {
                if (!input.TryGetProperty("value", out JsonElement value)) throw Failure(context + " has no saved value", "Rerun the analysis and export the new report.");
                dataset["storedData"] = "Original input held with the saved run";
                dataset["value"] = Copy(value);
            }
        }
    }

    private static void ValidatePointer(JsonElement input, string context)
    {
        JsonElement columns = Array(input, "columns", context);
        if (columns.GetArrayLength() == 0 || columns.GetArrayLength() > MaximumColumns) throw Failure(context + " names no usable workbook columns", "Rerun the analysis.");
        foreach (string field in new[] { "file", "path", "sheet", "mode" }) Text(input, field, context);
        foreach (JsonElement column in columns.EnumerateArray())
        {
            RequireObject(column, context + " column");
            if (!column.TryGetProperty("column", out JsonElement index) || index.ValueKind != JsonValueKind.Number || !index.TryGetInt32(out int position) || position < 1)
                throw Failure(context + " has an invalid column pointer", "Rerun the analysis.");
            JsonElement rows = Array(column, "rows", context);
            if (rows.GetArrayLength() != 2 || rows[0].ValueKind != JsonValueKind.Number || rows[1].ValueKind != JsonValueKind.Number || !rows[0].TryGetInt32(out int first) || first < 1 || !rows[1].TryGetInt32(out _))
                throw Failure(context + " has an invalid row pointer", "Rerun the analysis.");
            // A negative original row count represents a whole-column selection; retain that existing RunRecord convention.
            foreach (string field in new[] { "title", "sheet", "hash" }) Text(column, field, context);
            if (column.TryGetProperty("hasTitle", out JsonElement hasTitle) && hasTitle.ValueKind is not (JsonValueKind.True or JsonValueKind.False))
                throw Failure(context + " has a malformed title flag", "Rerun the analysis.");
        }
    }

    private static void ValidateColumns(JsonElement columns, string context, Budget budget)
    {
        if (columns.ValueKind != JsonValueKind.Array || columns.GetArrayLength() > MaximumColumns) throw Failure(context + " has malformed columns", "Rerun the analysis.");
        foreach (JsonElement column in columns.EnumerateArray())
        {
            RequireObject(column, context + " column");
            Text(column, "title", context);
            ValidateValues(Array(column, "values", context), context, budget);
        }
    }

    private static void ValidateValues(JsonElement values, string context, Budget budget)
    {
        if (values.ValueKind != JsonValueKind.Array) throw Failure(context + " has missing or malformed values", "Rerun the analysis.");
        foreach (JsonElement value in values.EnumerateArray())
        {
            budget.Value();
            if (value.ValueKind is JsonValueKind.Object or JsonValueKind.Array or JsonValueKind.Undefined)
                throw Failure(context + " has a malformed column value", "Rerun the analysis.");
            if (value.ValueKind == JsonValueKind.Number && (!value.TryGetDouble(out double number) || double.IsNaN(number) || double.IsInfinity(number)))
                throw Failure(context + " has an invalid numeric value", "Rerun the analysis.");
        }
    }

    private static void VerifyHash(ColumnPointer pointer, object[] values, string context)
    {
        if (!string.IsNullOrEmpty(pointer.Hash) && !string.Equals(RunRecord.Hash(values), pointer.Hash, StringComparison.OrdinalIgnoreCase))
            throw Changed(context, pointer.Title);
    }

    private static InvalidOperationException Changed(string context, string column) => Failure(context + ", column \"" + column + "\", differs from the values used by the original analysis",
        "Restore the unchanged original workbook, or rerun the analysis with the current data and export its new report.");

    private static object Normalize(object value, string context) => value switch
    {
        null => null,
        double number => RunRecord.Missing(number) ? null : number,
        float number => RunRecord.Missing(number) ? null : (double)number,
        byte or sbyte or short or ushort or int or uint => Convert.ToDouble(value, invariant),
        long or ulong => ExactInteger(value, context),
        DateTime date => date.ToString("o", invariant),
        string or bool => value,
        _ => throw Failure(context + " returned an unsupported data value", "Rerun the analysis and export the new report.")
    };

    private static double ExactInteger(object value, string context)
    {
        double number = Convert.ToDouble(value, invariant);
        try
        {
            if (value is long signed && checked((long)number) == signed || value is ulong unsigned && checked((ulong)number) == unsigned) return number;
        }
        catch (OverflowException) { }
        throw Failure(context + " contains an integer that cannot be represented exactly by the R replay", "Use a smaller exact numeric range, or retain those identifiers as text and rerun the analysis.");
    }

    private static object[] JsonValues(JsonElement array) => array.EnumerateArray().Select(value => value.ValueKind switch
    {
        JsonValueKind.Number => (object)value.GetDouble(),
        JsonValueKind.String => value.GetString(),
        JsonValueKind.True => true,
        JsonValueKind.False => false,
        _ => null
    }).ToArray();

    private static string Key(FramePointer pointer) => JsonSerializer.Serialize(pointer);

    private static void ValidateAttachments(JsonElement attachments, Budget budget)
    {
        RequireObject(attachments, "report-cell attachments");
        int count = 0;
        foreach (JsonProperty attachment in attachments.EnumerateObject())
        {
            if (++count > 2000 || attachment.Name.Length == 0 || attachment.Name.Length > 1000) throw Failure("a report cell has malformed attachments", "Reopen the report.");
            RequireObject(attachment.Value, "an attachment MIME bundle");
            int mimeCount = 0;
            foreach (JsonProperty mime in attachment.Value.EnumerateObject())
            {
                if (++mimeCount > 20 || mime.Name.Length > 200 || !mime.Name.Contains('/')) throw Failure("an attachment MIME bundle is malformed", "Reopen the report.");
                if (mime.Value.ValueKind == JsonValueKind.String) budget.Text(mime.Value.GetString());
                else if (mime.Value.ValueKind == JsonValueKind.Array)
                    foreach (JsonElement line in mime.Value.EnumerateArray())
                    {
                        if (line.ValueKind != JsonValueKind.String) throw Failure("an attachment has malformed image data", "Reopen the report.");
                        budget.Text(line.GetString());
                    }
                else throw Failure("an attachment has malformed image data", "Reopen the report.");
            }
            if (mimeCount == 0) throw Failure("an attachment has no image data", "Reopen the report.");
        }
    }

    private static void Inspect(JsonElement value, Budget budget, string context, int depth)
    {
        budget.Node();
        if (depth > 24) throw Failure(context + " is nested too deeply", "Rerun the analysis.");
        switch (value.ValueKind)
        {
            case JsonValueKind.Object:
                var names = new HashSet<string>(StringComparer.Ordinal);
                foreach (JsonProperty property in value.EnumerateObject())
                {
                    if (!names.Add(property.Name)) throw Failure(context + " contains duplicate JSON fields", "Rerun the analysis.");
                    budget.Text(property.Name);
                    Inspect(property.Value, budget, context, depth + 1);
                }
                break;
            case JsonValueKind.Array:
                foreach (JsonElement child in value.EnumerateArray()) Inspect(child, budget, context, depth + 1);
                break;
            case JsonValueKind.String: budget.Text(value.GetString()); break;
            case JsonValueKind.Number:
                if (!value.TryGetDouble(out double number) || double.IsInfinity(number) || double.IsNaN(number)) throw Failure(context + " contains an invalid numeric value", "Rerun the analysis.");
                break;
            case JsonValueKind.Undefined: throw Failure(context + " is incomplete", "Rerun the analysis.");
        }
    }

    // Result matrices can themselves be deliberately abbreviated. Only inputs/settings must be complete to replay an analysis.
    private static void RejectIncompleteInput(JsonElement value, string context)
    {
        if (value.ValueKind == JsonValueKind.Object)
            foreach (JsonProperty property in value.EnumerateObject())
            {
                if ((property.Name == "omitted" || property.Name == "truncated") && property.Value.ValueKind == JsonValueKind.True)
                    throw Failure(context + " contains omitted or truncated input data", "Rerun the analysis with a smaller input selection so its full nested data can be retained.");
                RejectIncompleteInput(property.Value, context);
            }
        else if (value.ValueKind == JsonValueKind.Array)
            foreach (JsonElement child in value.EnumerateArray()) RejectIncompleteInput(child, context);
    }

    private static JsonElement Array(JsonElement parent, string name, string context)
    {
        if (!parent.TryGetProperty(name, out JsonElement value) || value.ValueKind != JsonValueKind.Array)
            throw Failure(context + " has a missing or malformed " + name + " array", "Reopen the report or rerun the affected analysis.");
        return value;
    }
    private static string RequiredText(JsonElement parent, string name, string context) => Text(parent, name, context) ??
        throw Failure(context + " has a missing " + name + " field", "Reopen the report or rerun the affected analysis.");
    private static string Text(JsonElement parent, string name, string context)
    {
        if (!parent.TryGetProperty(name, out JsonElement value)) return null;
        if (value.ValueKind != JsonValueKind.String) throw Failure(context + " has a malformed " + name + " field", "Reopen the report or rerun the affected analysis.");
        return value.GetString();
    }
    private static void RequireObject(JsonElement value, string context)
    {
        if (value.ValueKind != JsonValueKind.Object) throw Failure(context + " is missing or malformed", "Reopen the report or rerun the affected analysis.");
    }
    private static JsonNode Copy(JsonElement value) => JsonNode.Parse(value.GetRawText());
    private static string Markdown(string value) => string.Concat((value ?? "").Select(character => character < ' ' ? " " : "\\`*_{}[]<>#!|".Contains(character) ? "\\" + character : character.ToString()));
    private static InvalidOperationException Failure(string detail, string recovery) => new("Cannot export a complete Jupyter notebook: " + detail + ". " + recovery);
}
