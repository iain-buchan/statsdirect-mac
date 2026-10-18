using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text.Json;
using StatsDirect.Charting;
using StatsDirect.Templates;

// Mac controls for the shared chart options. The engine owns calculations,
// automatic axis descriptions and the final run record used by Continue in R.
internal static class HostChartForms {
    internal static void Histogram(OperationJob job, ChartDefinition chart, HistogramOptions histogram) {
        var fields = new List<object>();
        string Key(string name, int index) => histogram.HistoSeriesOptions.Count == 1 ? name : name + index;
        for (int i = 0; i < histogram.HistoSeriesOptions.Count; i++) {
            var series = histogram.HistoSeriesOptions[i];
            string group = histogram.HistoSeriesOptions.Count == 1 ? null : chart.YSeries[i].Title;
            void Add(string name, string label, string value) => fields.Add(new {
                name = Key(name, i), label, defaultValue = value ?? "", kind = "text", group });
            Add("title", "Title", series.ChartTitle);
            Add("x", "Horizontal axis", series.XAxisTitle);
            Add("y", "Vertical axis", series.YAxisTitle);
        }
        fields.Add(HostAmendments.Field("bins", "Number of bins (0 = automatic; otherwise 2–1000)", 0, "integer", 0, 1000));
        JsonElement? initial = null; string error = null;
        while (true) {
            var answer = job.Ask(new() { ["kind"] = "fields", ["title"] = "Histogram", ["prompt"] = "Histogram",
                ["fields"] = fields, ["initial"] = initial, ["error"] = error, ["submitLabel"] = "Run" });
            initial = answer.Clone();
            try {
                var bins = HostParameters.Number(answer.GetProperty("bins"));
                if (bins < 0 || bins == 1 || bins > 1000 || bins != Math.Truncate(bins))
                    throw new ArgumentException("Use 0 for automatic bins or a whole number from 2 to 1000.");
                string Text(string name, int i) => answer.TryGetProperty(Key(name, i), out var v) && v.ValueKind == JsonValueKind.String
                    ? v.GetString() : throw new ArgumentException("Complete the histogram labels.");
                var labels = Enumerable.Range(0, histogram.HistoSeriesOptions.Count).Select(i =>
                    (title: Text("title", i), x: Text("x", i), y: Text("y", i))).ToArray();
                for (int i = 0; i < labels.Length; i++) {
                    var series = histogram.HistoSeriesOptions[i];
                    series.ChartTitle = labels[i].title; series.XAxisTitle = labels[i].x; series.YAxisTitle = labels[i].y;
                    if (bins > 1) histogram.Reset(false, (int)bins, i, (DoubleSeries)chart.YSeries[i]);
                }
                job.Record("Histogram", answer); return;
            } catch (ArgumentException ex) { error = ex.Message; }
        }
    }

    internal static void BoxWhisker(OperationJob job, OperationHost host, ChartDefinition chart, BoxWhiskerOptions box) {
        box.Cco = host.Preferences.DefaultConfidenceInterval;
        var fields = new List<Dictionary<string, object>>();
        void Add(string name, string label, object value, string kind = "text", string group = null,
            object[] choices = null, string dependency = null, object[] enabledValues = null, bool optional = false) {
            fields.Add(new() { ["name"] = name, ["label"] = label, ["defaultValue"] = value, ["kind"] = kind,
                ["group"] = group, ["options"] = choices, ["enabledWhen"] = dependency == null ? null : new { name = dependency, values = enabledValues }, ["optional"] = optional });
        }
        object Choice(string value, string label) => new { value, label };
        Add("method", "Box and whisker method", ((int)box.Method).ToString(CultureInfo.InvariantCulture), "select", choices: new[] {
            Choice("1", "Median, quartiles and range"), Choice("7", "Tukey hinges (median of each half)"), Choice("2", "Mean, standard deviation and range"),
            Choice("6", "Mean, standard error and range"), Choice("3", "Mean, confidence interval and range"),
            Choice("4", "Seven-number summary"), Choice("5", "Bowley summary") });
        Add("confidence", "Confidence level (%)", box.Cco * 100, "number", dependency: "method", enabledValues: new object[] { "3" });
        Add("innerFence", "Use inner fence", box.UseInnerFence, "boolean", dependency: "method", enabledValues: new object[] { "1", "7", "2", "3", "6" });
        Add("outerFence", "Use outer fence", box.UseOuterFence, "boolean", dependency: "method", enabledValues: new object[] { "1", "7", "2", "3", "6" });
        Add("markMeanAndMedian", "Mark both mean and median", box.MarkMeanAndMedian, "boolean");
        if (!chart.IsAscii) Add("orientation", "Orientation", box.Orientation.ToString(), "select", choices: new[] { Choice("Horizontal", "Horizontal"), Choice("Vertical", "Vertical") });
        Add("title", "Chart title", box.Title ?? "");
        Add("automaticAxisTitle", "Describe the method on the value axis automatically", true, "boolean");
        Add("x", "Value axis title", box.XAxisTitle ?? "", dependency: "automaticAxisTitle", enabledValues: new object[] { false });
        for (int i = 0; i < box.SeriesTitles.Length; i++) Add("series" + i, "Series " + (i + 1), box.SeriesTitles[i], group: "Series labels");
        if (!chart.IsAscii) {
            Add("boxAxes", "Box axes", box.ShouldBoxAxes, "boolean", "Axes");
            Add("minimum", "Value axis minimum (empty = automatic)", "", "number", "Axes", optional: true);
            Add("maximum", "Value axis maximum (empty = automatic)", "", "number", "Axes", optional: true);
            Add("valueGrid", "Value axis grid lines", chart.ScaleParameters.X.HasGridLines, "boolean", "Axes");
            Add("valueMarker", "Value axis reference line (empty = none)", chart.ScaleParameters.X.MarkerLineValue?.ToString(CultureInfo.InvariantCulture) ?? "", "number", "Axes", optional: true);
        }
        JsonElement? initial = null; string error = null;
        while (true) {
            var a = job.Ask(new() { ["kind"] = "fields", ["title"] = "Box and whisker plot", ["prompt"] = "Box and whisker plot",
                ["fields"] = fields, ["initial"] = initial, ["error"] = error, ["submitLabel"] = "Run" });
            initial = a.Clone();
            try {
                string Text(string key) => a.TryGetProperty(key, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : throw new ArgumentException("Complete " + key + ".");
                bool Flag(string key) => a.TryGetProperty(key, out var v) && (v.ValueKind == JsonValueKind.True || v.ValueKind == JsonValueKind.False) ? v.GetBoolean() : throw new ArgumentException("Complete " + key + ".");
                double Number(string key) => a.TryGetProperty(key, out var v) ? HostParameters.Number(v) : throw new ArgumentException("Complete " + key + ".");
                double? OptionalNumber(string key) => !a.TryGetProperty(key, out var v) || v.ValueKind == JsonValueKind.Null || (v.ValueKind == JsonValueKind.String && string.IsNullOrWhiteSpace(v.GetString())) ? null : Number(key);
                if (!int.TryParse(Text("method"), out int method) || !Enum.IsDefined(typeof(BoxWhiskerOptions.BoxWhiskerMethod), method)) throw new ArgumentException("Choose a box and whisker method.");
                var confidence = method == 3 ? Number("confidence") / 100 : box.Cco;
                if (!(confidence > 0 && confidence < 1)) throw new ArgumentException("Confidence must be greater than 0 and less than 100%.");
                var orientation = box.Orientation;
                if (!chart.IsAscii && (!Enum.TryParse(Text("orientation"), out orientation) || !Enum.IsDefined(orientation))) throw new ArgumentException("Choose horizontal or vertical orientation.");
                var minimum = OptionalNumber("minimum"); var maximum = OptionalNumber("maximum"); var marker = OptionalNumber("valueMarker");
                if (minimum.HasValue != maximum.HasValue || minimum >= maximum) throw new ArgumentException("Enter both axis limits, with the minimum smaller than the maximum, or leave both empty for automatic scaling.");
                // Validate everything before modifying the shared definition.
                var title = Text("title"); var x = Text("x"); var automatic = Flag("automaticAxisTitle");
                var inner = Flag("innerFence"); var outer = Flag("outerFence"); var both = Flag("markMeanAndMedian");
                var names = Enumerable.Range(0, box.SeriesTitles.Length).Select(i => Text("series" + i)).ToArray();
                var boxed = !chart.IsAscii && Flag("boxAxes"); var grid = !chart.IsAscii && Flag("valueGrid");
                box.Method = (BoxWhiskerOptions.BoxWhiskerMethod)method; box.Cco = confidence; box.Orientation = orientation;
                box.UseInnerFence = inner; box.UseOuterFence = outer; box.MarkMeanAndMedian = both;
                box.Title = title; box.SeriesTitles = names; box.ShouldBoxAxes = boxed;
                if (automatic) box.SetDefaultXAxisTitle(); else box.XAxisTitle = x;
                var axis = chart.ScaleParameters.X;
                axis.ScaleType = ScaleType.Linear;
                axis.AxisScale = minimum.HasValue ? AxisScalerFactory.AxisScalerFor(ScaleType.Linear).QAxis(minimum.Value, minimum.Value, maximum.Value, false, true) : null;
                axis.HasGridLines = grid; axis.MarkerLineValue = marker;
                job.Record("Box and whisker plot", a); return;
            } catch (ArgumentException ex) { error = ex.Message; }
        }
    }
}
