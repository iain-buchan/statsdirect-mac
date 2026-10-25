using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Text;
using System.Text.Json;
using StatsDirect.R;
using StatsDirect.UI;

public static partial class RScriptIO {
    // Mac-only transport for the shared, platform-independent notebook writer.
    // The host reads each requested range once. Acquisition, hash verification
    // and relocation use the ordinary Continue in R reader, then the exact typed
    // values are reused for both the notebook datasets and its executable code.
    sealed record NotebookFrame(FramePointer Pointer, FrameValues Values);

    static string NotebookPointerKey(FramePointer pointer) => JsonSerializer.Serialize(new {
        pointer.File, pointer.Path, pointer.Sheet, pointer.Mode,
        columns = pointer.Columns.Select(c => new { c.Title, c.Sheet, c.Column, c.FirstRow, c.LastRow, c.HasTitle, c.Hash }).ToArray()
    }, json);

    static string ExecuteNotebook(JsonElement request) {
        using var snapshot = NotebookSnapshot(request.GetProperty("notebook"));
        string title = RScriptWriter.Text(request, "title") ?? "Report";
        string version = RScriptWriter.Text(request, "appVersion") ?? "development";
        var resolved = new Dictionary<string, NotebookFrame>();
        var relocate = new List<object>();
        RuntimeHelpers.RunClassConstructor(typeof(Exports).TypeHandle);
        _ = SdApplication.SoleInstance;
        lock (EngineExecution.Gate) {
            if (request.TryGetProperty("frames", out var supplied) && supplied.ValueKind == JsonValueKind.Array)
                foreach (var item in supplied.EnumerateArray()) {
                    FramePointer pointer = FramePointer.From(item.GetProperty("pointer"));
                    // Historical records may have no hash. The shared writer
                    // explicitly labels those rereads as unverified; a present
                    // malformed hash cannot be treated as historical provenance.
                    if (pointer.Columns.Count == 0 || pointer.Columns.Any(c => c.Hash != null && (c.Hash.Length != 16 || !c.Hash.All(Uri.IsHexDigit))))
                        throw new InvalidDataException("The saved result cannot verify its original workbook data. Open the original workbook and rerun the analysis before exporting the notebook.");
                    string key = NotebookPointerKey(pointer);
                    if (resolved.ContainsKey(key)) continue;
                    var frame = item.GetProperty("frame");
                    var frames = new Dictionary<string, Queue<JsonElement>> {
                        [pointer.Name ?? "input"] = new Queue<JsonElement>(new[] { frame })
                    };
                    FrameValues values = Read(pointer, frames, new List<string>(), relocate, new Dictionary<string, int>());
                    resolved[key] = new NotebookFrame(pointer, values);
                }
            // First return every relocation request together, before serializing
            // anything. The second call reuses the same initial cells plus only
            // the candidate bands the reader requested; no neighbouring data is
            // included in the final notebook.
            if (relocate.Count > 0) return JsonSerializer.Serialize(new { relocate }, json);
            FrameValues ReadResolved(FramePointer pointer) {
                if (!resolved.TryGetValue(NotebookPointerKey(pointer), out var frame))
                    return new FrameValues { Unavailable = "the original workbook data could not be recovered; open the original workbook or rerun the analysis" };
                for (int i = 0; i < pointer.Columns.Count && i < frame.Pointer.Columns.Count; i++)
                    pointer.Columns[i].Column = frame.Pointer.Columns[i].Column;
                return frame.Values;
            }
            string notebook = StatsDirect.UI.WebReports.ReportNotebook.Write(snapshot.RootElement, title, ReadResolved, version);
            return JsonSerializer.Serialize(new { notebook }, json);
        }
    }

    // Raw records and report cells cross the Swift boundary as strings so
    // Foundation cannot round their numbers or reorder their keys (an
    // attachment bundle must keep its PNG first). Convert them inside the
    // managed bridge, preserving their JSON exactly for the shared writer.
    static JsonDocument NotebookSnapshot(JsonElement supplied) {
        using var stream = new MemoryStream();
        using (var writer = new Utf8JsonWriter(stream)) {
            writer.WriteStartObject();
            foreach (var property in supplied.EnumerateObject()) {
                writer.WritePropertyName(property.Name);
                if (property.Name != "entries") { property.Value.WriteTo(writer); continue; }
                writer.WriteStartArray();
                foreach (var entry in property.Value.EnumerateArray()) {
                    writer.WriteStartObject();
                    foreach (var field in entry.EnumerateObject()) {
                        writer.WritePropertyName(field.Name);
                        if (field.Name == "record" && field.Value.ValueKind == JsonValueKind.String) {
                            using var record = JsonDocument.Parse(field.Value.GetString());
                            if (record.RootElement.ValueKind != JsonValueKind.Object) throw new InvalidDataException("The saved analysis record is unreadable. Rerun the analysis, then export again.");
                            record.RootElement.WriteTo(writer);
                        } else if (field.Name == "cells" && field.Value.ValueKind == JsonValueKind.String) {
                            using var cells = JsonDocument.Parse(field.Value.GetString());
                            if (cells.RootElement.ValueKind != JsonValueKind.Array) throw new InvalidDataException("The report returned unreadable notebook cells. Try exporting again.");
                            cells.RootElement.WriteTo(writer);
                        } else field.Value.WriteTo(writer);
                    }
                    writer.WriteEndObject();
                }
                writer.WriteEndArray();
            }
            writer.WriteEndObject();
        }
        return JsonDocument.Parse(stream.ToArray());
    }
}
