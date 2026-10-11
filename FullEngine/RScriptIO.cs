using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Text.Json;
using StatsDirect.Data;
using StatsDirect.R;
using StatsDirect.Templates;
using StatsDirect.UI;
using StatsDirect.Utilities;

// The R script of a result, written by the engine's RScriptWriter (shared with Windows) from the record of the run
// (RunRecord) that the report keeps. The native host supplies, for each frame the record points to and does not hold the
// values of, the cells as they stand now: from the open grid, or from the workbook file it opened through the engine.
// Request: {"record": <the record object, or its JSON text>, "title": "<entry title or null>",
//           "frames": [{"name": "data", "columns": [{"title": "x", "values": ["text", …], "kinds": ["number", …]}, …]}
//                     | {"name": "data", "unavailable": "<reason>"}, …]}
// Response: {"text", "hasRecipe", "detail", "dataUnavailable", "asked": [the pointer frames the writer asked for, in order],
//            "relocate": [{"frame", "name", "column", "place", "firstRow", "lastRow", "hasTitle", "sheet"}, …]}
// A column whose hash no longer matches may have moved along the sheet (output columns written to its left, a column inserted or
// removed by hand): as the Windows FrameReader does with ColumnLocator, the entry looks for it by hash and title one column at a time to
// the right and the left, within 64 columns, among the "candidates" the host supplies with the frame ({"column", "title", "values",
// "kinds"} each, over the same rows); when the frame carries no candidates, "relocate" lists the columns to look for, by the frame's
// "index" and the column's place within it, and the host supplies them in a second call. A column found elsewhere takes its new place
// (the script's comment gives it) and is marked moved; one found nowhere is marked changed.
// or {"error"}. The values go through HostParameters.ReadFrame under the frame's recorded acquisition mode, as the original
// run's did, so RunRecord.Hash of the variable equals the recorded hash exactly when the cells are unchanged (the Windows
// FrameReader reads the grid the same way); a column whose hash differs is marked Changed and the script notes it.
public static class RScriptIO {
    static readonly JsonSerializerOptions json = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase, PropertyNameCaseInsensitive = true };
    public static string Execute(string text) {
        try {
            using var request = JsonDocument.Parse(text);
            var root = request.RootElement;
            if (root.ValueKind != JsonValueKind.Object || !root.TryGetProperty("record", out var given)) throw new Exception("The request names no record of a run.");
            using var parsed = given.ValueKind == JsonValueKind.String ? JsonDocument.Parse(given.GetString() ?? "") : null;
            var record = parsed != null ? parsed.RootElement : given;
            if (record.ValueKind != JsonValueKind.Object) throw new Exception("The record of the run is not a JSON object.");
            string title = root.TryGetProperty("title", out var t) && t.ValueKind == JsonValueKind.String ? t.GetString() : null;
            // the frames the host supplies, by input name and in order: a frame asked once per pass of a loop (the groups of a survival
            // plot) is several inputs of one name, and the writer reads them in the record's order, so each read takes the next supplied
            var frames = new Dictionary<string, Queue<JsonElement>>();
            if (root.TryGetProperty("frames", out var list) && list.ValueKind == JsonValueKind.Array)
                foreach (var frame in list.EnumerateArray()) {
                    var name = RScriptWriter.Text(frame, "name");
                    if (name == null) continue;
                    if (!frames.TryGetValue(name, out var queue)) frames[name] = queue = new Queue<JsonElement>();
                    queue.Enqueue(frame);
                }
            RuntimeHelpers.RunClassConstructor(typeof(Exports).TypeHandle);
            _ = SdApplication.SoleInstance;
            var asked = new List<string>();
            var relocate = new List<object>();
            var taken = new Dictionary<string, int>();
            RScript script;
            lock (EngineExecution.Gate) script = RScriptWriter.Write(record, title, pointer => Read(pointer, frames, asked, relocate, taken));
            return JsonSerializer.Serialize(new { text = script.Text, hasRecipe = script.HasRecipe, detail = script.Detail, dataUnavailable = script.DataUnavailable, asked, relocate }, json);
        } catch (Exception ex) { return JsonSerializer.Serialize(new { error = ex.Message }, json); }
    }
    // The values of a pointer frame from what the host supplied, with the Windows FrameReader's wording when they cannot be read.
    static FrameValues Read(FramePointer pointer, Dictionary<string, Queue<JsonElement>> frames, List<string> asked, List<object> relocate, Dictionary<string, int> taken) {
        asked.Add(pointer.Name ?? "");
        if (pointer.Columns.Count == 0) return new FrameValues { Unavailable = "the record names no columns" };
        string file = string.IsNullOrEmpty(pointer.Path) ? pointer.File : pointer.Path;
        if (pointer.Name == null || !frames.TryGetValue(pointer.Name, out var queue) || queue.Count == 0) return new FrameValues { Unavailable = $"the workbook {pointer.File} is not open and was not found at {file}" };
        var frame = queue.Dequeue();
        // the frame's place among those the host supplied: its own "index", else its ordinal among those of its name
        int ordinal = taken.TryGetValue(pointer.Name, out int n) ? n : 0; taken[pointer.Name] = ordinal + 1;
        int frameIndex = frame.TryGetProperty("index", out var given) && given.ValueKind == JsonValueKind.Number ? given.GetInt32() : ordinal;
        if (RScriptWriter.Text(frame, "unavailable") is string reason) return new FrameValues { Unavailable = reason };
        string mismatch = $"sheet {pointer.Sheet} of {pointer.File} no longer gives {pointer.Columns.Count} columns at the recorded place";
        if (!frame.TryGetProperty("columns", out var columns) || columns.ValueKind != JsonValueKind.Array || columns.GetArrayLength() != pointer.Columns.Count) return new FrameValues { Unavailable = mismatch };
        if (!Enum.TryParse(pointer.Mode, out DataAcquisitionMode mode) || mode == DataAcquisitionMode.NotSet) mode = DataAcquisitionMode.NumericReplaceMissing;
        var input = new { preserveRows = true, source = pointer.File + " / " + pointer.Sheet, columns = columns.EnumerateArray().Select((c, i) => new {
            title = RScriptWriter.Text(c, "title") ?? pointer.Columns[i].Title ?? "",
            values = c.TryGetProperty("values", out var values) && values.ValueKind == JsonValueKind.Array ? values.EnumerateArray().Select(Cell).ToArray() : Array.Empty<string>() }).ToArray() };
        DataFrame read;
        try { read = HostParameters.ReadFrame(JsonSerializer.SerializeToElement(input), mode, null, true, true); }
        catch (Exception ex) { return new FrameValues { Unavailable = ex.Message }; }
        if (read == null || read.VariableCount != pointer.Columns.Count) return new FrameValues { Unavailable = mismatch };
        // the candidate columns the host supplied for a column that has moved, by their place on the sheet, read under the mode once each
        var candidates = new Dictionary<int, JsonElement>();
        if (frame.TryGetProperty("candidates", out var supplied) && supplied.ValueKind == JsonValueKind.Array)
            foreach (var candidate in supplied.EnumerateArray())
                if (candidate.TryGetProperty("column", out var place) && place.ValueKind == JsonValueKind.Number) candidates[place.GetInt32()] = candidate;
        var readAt = new Dictionary<int, IVariable>();
        IVariable ReadAt(int index) {
            if (readAt.TryGetValue(index, out var known)) return known;
            IVariable variable = null;
            if (candidates.TryGetValue(index, out var candidate)) {
                var one = new { preserveRows = true, source = pointer.File + " / " + pointer.Sheet, columns = new[] { new {
                    title = RScriptWriter.Text(candidate, "title") ?? "",
                    values = candidate.TryGetProperty("values", out var values) && values.ValueKind == JsonValueKind.Array ? values.EnumerateArray().Select(Cell).ToArray() : Array.Empty<string>() } } };
                try { var frameAt = HostParameters.ReadFrame(JsonSerializer.SerializeToElement(one), mode, null, true, true); variable = frameAt != null && frameAt.VariableCount > 0 ? frameAt.Variables[0] : null; }
                catch (Exception) { variable = null; }
            }
            readAt[index] = variable;
            return variable;
        }
        var result = new FrameValues();
        for (int i = 0; i < read.VariableCount; i++) {
            var variable = read.Variables[i];
            var column = pointer.Columns[i];
            bool moved = false;
            if (column.Hash != null && RunRecord.Hash(variable) != column.Hash) {
                if (candidates.Count > 0) {
                    int? found = ColumnLocator.Find(column, index => {
                        var v = index == column.Column ? variable : ReadAt(index);
                        return v == null ? null : (v.Title, RunRecord.Hash(v));
                    });
                    if (found != null && found != column.Column) {
                        variable = ReadAt(found.Value) ?? variable;
                        column.Column = found.Value;   // the pointer now names the column's new place, which the script's comment gives
                        moved = true;
                    }
                } else
                    relocate.Add(new { frame = frameIndex, name = pointer.Name, column = i, place = column.Column, firstRow = column.FirstRow, lastRow = column.LastRow, hasTitle = column.HasTitle, sheet = column.Sheet ?? pointer.Sheet });
            }
            result.Columns.Add(new ColumnValues {
                Title = string.IsNullOrEmpty(column.Title) ? variable.Title : column.Title,
                Values = RunRecord.Values(variable),
                Changed = column.Hash != null && RunRecord.Hash(variable) != column.Hash,
                Moved = moved
            });
        }
        return result;
    }
    // A cell as the grid's text: a string as it is; a number, a flag or nothing given typed is written as the grid would show it.
    static string Cell(JsonElement value) => value.ValueKind switch {
        JsonValueKind.String => value.GetString(),
        JsonValueKind.Number => value.TryGetDouble(out double d) ? d.ToString("R", CultureInfo.InvariantCulture) : value.GetRawText(),
        JsonValueKind.True => "TRUE",
        JsonValueKind.False => "FALSE",
        _ => ""
    };
    [UnmanagedCallersOnly]
    public static IntPtr Invoke(IntPtr input) => Marshal.StringToCoTaskMemUTF8(Execute(Marshal.PtrToStringUTF8(input) ?? "{}"));
    [UnmanagedCallersOnly]
    public static void Free(IntPtr result) => Marshal.FreeCoTaskMem(result);
}
