using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using StatsDirect.R;
using StatsDirect.UI.WebReports;

public static partial class RScriptIO {
    static string ExecuteNotebookImport(JsonElement request) {
        string source = request.GetProperty("notebookImport").GetString();
        string title = RScriptWriter.Text(request, "title") ?? "Notebook";
        var plan = ReportNotebookImport.Read(source, title);
        using var stream = new MemoryStream();
        using (var writer = new Utf8JsonWriter(stream)) {
            writer.WriteStartObject();
            writer.WriteString("title", plan.Title);
            writer.WritePropertyName("entries");
            writer.WriteStartArray();
            foreach (var entry in plan.Entries.EnumerateArray()) {
                writer.WriteStartObject();
                foreach (var field in entry.EnumerateObject()) {
                    writer.WritePropertyName(field.Name);
                    // Keep the rehydrated run record exact across Foundation;
                    // the renderer only carries it as inert metadata.
                    if (field.Name == "record" && field.Value.ValueKind == JsonValueKind.Object)
                        writer.WriteStringValue(field.Value.GetRawText());
                    else field.Value.WriteTo(writer);
                }
                writer.WriteEndObject();
            }
            writer.WriteEndArray();
            writer.WriteString("script", plan.Script);
            // Shared plan properties are internal; publish an explicit native
            // transport rather than relying on public-property serialization.
            writer.WritePropertyName("tables");
            JsonSerializer.Serialize(writer, plan.Tables.Select(table => new { title = table.Title,
                columns = table.Columns.Select(column => new { title = column.Title, values = column.Values }).ToArray() }).ToArray(), json);
            writer.WritePropertyName("warnings"); JsonSerializer.Serialize(writer, plan.Warnings, json);
            writer.WriteString("provenance", plan.Provenance.GetRawText());
            writer.WriteEndObject();
        }
        return JsonSerializer.Serialize(new { notebookImport = Encoding.UTF8.GetString(stream.ToArray()) }, json);
    }
}
