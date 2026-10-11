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
// Response: {"text", "hasRecipe", "detail", "dataUnavailable", "asked": [the pointer frames the writer asked for, in order]}
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
            RScript script;
            lock (EngineExecution.Gate) script = RScriptWriter.Write(record, title, pointer => Read(pointer, frames, asked));
            return JsonSerializer.Serialize(new { text = script.Text, hasRecipe = script.HasRecipe, detail = script.Detail, dataUnavailable = script.DataUnavailable, asked }, json);
        } catch (Exception ex) { return JsonSerializer.Serialize(new { error = ex.Message }, json); }
    }
    // The values of a pointer frame from what the host supplied, with the Windows FrameReader's wording when they cannot be read.
    static FrameValues Read(FramePointer pointer, Dictionary<string, Queue<JsonElement>> frames, List<string> asked) {
        asked.Add(pointer.Name ?? "");
        if (pointer.Columns.Count == 0) return new FrameValues { Unavailable = "the record names no columns" };
        string file = string.IsNullOrEmpty(pointer.Path) ? pointer.File : pointer.Path;
        if (pointer.Name == null || !frames.TryGetValue(pointer.Name, out var queue) || queue.Count == 0) return new FrameValues { Unavailable = $"the workbook {pointer.File} is not open and was not found at {file}" };
        var frame = queue.Dequeue();
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
        var result = new FrameValues();
        for (int i = 0; i < read.VariableCount; i++) {
            var variable = read.Variables[i];
            result.Columns.Add(new ColumnValues {
                Title = string.IsNullOrEmpty(pointer.Columns[i].Title) ? variable.Title : pointer.Columns[i].Title,
                Values = RunRecord.Values(variable),
                Changed = pointer.Columns[i].Hash != null && RunRecord.Hash(variable) != pointer.Columns[i].Hash
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
