using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Text.Json.Nodes;
using StatsDirect.Builtins;
using StatsDirect.Templates;
using StatsDirect.UI;

// The local check behind AI Assist's distribution cards (Windows 5.3.22), exposed to the native pane as statsdirect_measurement_check.
// The Windows code is copied unchanged between windows-copy markers naming its lines in FullEngine/Upstream, and
// Tests/test_measurement_check.py checks that the copies still match: the Windows grid's diagnostics of two selected columns
// (frmSpreadsheetGear.MeasurementDiagnostics.cs) and the decision its pane draws as an interval card (IntervalDecision in
// ScriptAIPane.WorksheetAnalysis.cs), whose lines show the numbers in the user's culture, as on Windows. Only the reading is the
// Mac's: the grid reads the selection as an analysis of it would and sends the complete-pair differences or each column's values.
// Nothing computed here is sent to an AI provider. The numerics keep no shared state, so a check takes no engine lock and does not
// wait behind a running analysis.
public static class MeasurementChecks {
    const string Unrecognised = "The measurements to check are not in a recognised form.";
    // The branches of an interval card, in the order of its buttons.
    static readonly string[] Branches = { "large", "normal", "non-normal" };

    // Request: {design: "paired" | "independent", culture, separateSamples, read}. read is null when the grid could not read the
    // selection, {snapshot: path, pairs: n} or {differences: [...]} for paired measurements, and {samples: [{count, values}, {count,
    // values}]} for independent ones, with each column's values only when it has at most 100. separateSamples is the user's
    // confirmation that independent columns hold the two samples. Reply: the card as Windows' Display gives it for the decision, with
    // what the pane needs for the branch buttons and the unrounded values; or {error}.
    public static string Execute(string input) {
        try {
            using var document = JsonDocument.Parse(input);
            var request = document.RootElement;
            string design = request.ValueKind == JsonValueKind.Object && request.TryGetProperty("design", out var given)
                && given.ValueKind == JsonValueKind.String ? given.GetString() : null;
            if (design is not ("paired" or "independent")) throw new ArgumentException("Set design to paired or independent.");
            var previous = CultureInfo.CurrentCulture;
            try {
                CultureInfo.CurrentCulture = Culture(request);
                // The decision as Windows' ReadSelection leaves it (ScriptAIPane.WorksheetAnalysis.cs:57-59), from what the grid read;
                // unread when the grid could not read the selection.
                var decision = new IntervalDecision(design == "paired");
                if (request.TryGetProperty("read", out var read) && read.ValueKind != JsonValueKind.Null)
                    decision = decision.Paired
                        ? decision with { Pairs = MeasurementDiagnostics.CheckPairedDifferences(Differences(read)) }
                        : decision with { Columns = Samples(read),
                            SeparateSamples = request.TryGetProperty("separateSamples", out var separate) && separate.ValueKind == JsonValueKind.True };
                var card = new IntervalCard(decision.Kind, decision).Display();
                // For the branch buttons: whether the size is known to be large, the method and advice of each branch, and the feedback
                // for a branch of the other size (Windows refuses that branch, never non-normal).
                card["largeSample"] = decision.LargeSample;
                card["methods"] = ByBranch(decision.Method);
                card["advice"] = ByBranch(decision.Advice);
                card["conflict"] = decision.LargeSample is bool large ? decision.Conflict(large) : null;
                card["values"] = Values(decision);
                return card.ToJsonString();
            } finally { CultureInfo.CurrentCulture = previous; }
        } catch (Exception error) {
            return JsonSerializer.Serialize(new { error = error.Message });
        }
    }
    // The user's number format, scoped to the call as the calculator scopes it (CalculatorIO); without a name .NET knows, the invariant culture.
    static CultureInfo Culture(JsonElement request) {
        string name = request.TryGetProperty("culture", out var given) && given.ValueKind == JsonValueKind.String ? given.GetString() : "";
        try { return name.Length == 0 ? CultureInfo.InvariantCulture : CultureInfo.GetCultureInfo(name); }
        catch (CultureNotFoundException) { return CultureInfo.InvariantCulture; }
    }
    // A paired read: the differences of the complete pairs, first column minus second in row order, from the snapshot file the grid
    // posted (one sheet with one column of numbers, as many as the pairs it counted; read as Excel saves read theirs) or inline.
    static List<double> Differences(JsonElement read) {
        if (read.ValueKind != JsonValueKind.Object) throw new ArgumentException(Unrecognised);
        if (read.TryGetProperty("snapshot", out var file) && file.ValueKind == JsonValueKind.String) {
            List<WorkbookIO.SheetData> sheets;
            using (var stream = File.OpenRead(file.GetString())) sheets = WorkbookIO.ReadSnapshot(stream);
            var column = sheets.Count == 1 && sheets[0].Columns.Count == 1 ? sheets[0].Columns.Values.Single() : null;
            if (column == null || Count(read, "pairs") != column.Nums.Count || column.Kinds.Any(kind => kind != 1)) throw new ArgumentException(Unrecognised);
            return column.Nums;
        }
        if (!read.TryGetProperty("differences", out var list) || list.ValueKind != JsonValueKind.Array) throw new ArgumentException(Unrecognised);
        var differences = new List<double>(list.GetArrayLength());
        foreach (var item in list.EnumerateArray())
            // A number beyond the range of a double is infinite here, which the Windows check refuses as too large.
            differences.Add(item.ValueKind != JsonValueKind.Number ? throw new ArgumentException(Unrecognised)
                : item.TryGetDouble(out double difference) ? difference : double.PositiveInfinity);
        return differences;
    }
    // An independent read: for each column, the count of its usable values and, when there are at most 100, the values.
    static IndependentSampleDiagnostics Samples(JsonElement read) {
        if (read.ValueKind != JsonValueKind.Object || !read.TryGetProperty("samples", out var samples) || samples.ValueKind != JsonValueKind.Array
            || samples.GetArrayLength() != 2) throw new ArgumentException(Unrecognised);
        var columns = samples.EnumerateArray().Select(Sample).ToArray();
        return new IndependentSampleDiagnostics(columns[0], columns[1]);
    }
    static MeasurementDistributionDiagnostics Sample(JsonElement sample) {
        int count = sample.ValueKind == JsonValueKind.Object ? Count(sample, "count") : -1;
        if (count < 0 || !sample.TryGetProperty("values", out var list) || list.ValueKind != JsonValueKind.Array
            || list.GetArrayLength() != (count <= MeasurementDistributionDiagnostics.LargeSampleThreshold ? count : 0)) throw new ArgumentException(Unrecognised);
        var values = new List<double>(list.GetArrayLength());
        foreach (var item in list.EnumerateArray())
            values.Add(item.ValueKind == JsonValueKind.Number && item.TryGetDouble(out double value) && !RunRecord.Missing(value) ? value
                : throw new ArgumentException(Unrecognised));
        return MeasurementDiagnostics.SummarizeSample(count, values);
    }
    static int Count(JsonElement element, string name) =>
        element.TryGetProperty(name, out var count) && count.ValueKind == JsonValueKind.Number && count.TryGetInt32(out int n) ? n : -1;
    // The diagnostics behind the card's lines, unrounded, for tests: null where Windows has none, and never a number JSON cannot hold.
    static JsonObject Values(IntervalDecision decision) =>
        decision.Pairs is { } pairs ? new JsonObject {
            ["count"] = pairs.Count, ["w"] = Finite(pairs.ShapiroWilkW), ["p"] = Finite(pairs.ShapiroWilkP),
            ["hasVariation"] = pairs.HasVariation, ["hasPotentialOutlier"] = pairs.HasPotentialOutlier, ["hasSkewSignal"] = pairs.HasSkewSignal,
            ["shape"] = pairs.Shape is { } shape ? new JsonObject {
                ["lowerQuartile"] = Finite(shape.LowerQuartile), ["upperQuartile"] = Finite(shape.UpperQuartile), ["skewness"] = Finite(shape.Skewness),
                ["excessKurtosis"] = Finite(shape.ExcessKurtosis), ["farOutCount"] = shape.FarOutCount, ["hasHeavyTails"] = shape.HasHeavyTails } : null }
        : decision.Columns is { } columns ? new JsonObject { ["first"] = Values(columns.First), ["second"] = Values(columns.Second) }
        : null;
    static JsonObject Values(MeasurementDistributionDiagnostics sample) =>
        new() { ["count"] = sample.Count, ["w"] = Finite(sample.ShapiroWilkW), ["p"] = Finite(sample.ShapiroWilkP) };
    static double? Finite(double? value) => value is double x && double.IsFinite(x) ? x : null;
    static JsonObject ByBranch(Func<string, string> text) => new(Branches.Select(branch => KeyValuePair.Create(branch, (JsonNode)text(branch))));
    [UnmanagedCallersOnly]
    public static IntPtr Invoke(IntPtr input) => Marshal.StringToCoTaskMemUTF8(Execute(Marshal.PtrToStringUTF8(input) ?? "{}"));
    [UnmanagedCallersOnly]
    public static void Free(IntPtr result) => Marshal.FreeCoTaskMem(result);

    // Windows' WorksheetAction for an interval card, as far as its Display (ScriptAIPane.WorksheetAnalysis.cs:162-196) shows the
    // decision; the Mac pane keeps the card's token and feedback itself.
    sealed record IntervalCard(string Kind, IntervalDecision Interval) {
        internal JsonObject Display() {
            var card = new JsonObject { ["kind"] = Kind };
            // windows-copy begin StatsDirectUI/UI/Learning/ScriptAIPane.WorksheetAnalysis.cs:174-180
            Interval?.AddDetails(card);
            if (Kind == "paired-interval" && Interval?.Pairs is { } pairs)
            {
                var (branch, reason) = IntervalDecision.SuggestPairedBranch(pairs);
                card["suggestedBranch"] = branch;
                card["recommendation"] = reason;
            }
            // windows-copy end
            return card;
        }
    }

    // The decision behind an interval card, as the Windows pane keeps it, without ReadSelection (:57-59), which reads the Windows
    // grid; Execute builds the decision from the request instead.
    // windows-copy begin StatsDirectUI/UI/Learning/ScriptAIPane.WorksheetAnalysis.cs:44-55
    private sealed record IntervalDecision(bool Paired, PairedDifferenceDiagnostics Pairs = null,
        IndependentSampleDiagnostics Columns = null, bool SeparateSamples = false)
    {
        internal string Kind => Paired ? "paired-interval" : "independent-interval";

        internal bool CanCheck => Paired ? Pairs == null : !SeparateSamples;

        internal bool? LargeSample => Pairs is { } pairs
            ? pairs.Count > MeasurementDistributionDiagnostics.LargeSampleThreshold
            : SeparateSamples && Columns is { } columns
                ? Math.Min(columns.First.Count, columns.Second.Count) > MeasurementDistributionDiagnostics.LargeSampleThreshold
                : null;
        // windows-copy end

        // windows-copy begin StatsDirectUI/UI/Learning/ScriptAIPane.WorksheetAnalysis.cs:61-153
        internal string Method(string branch) => (Paired, branch) switch
        {
            (true, "non-normal") => "Wilcoxon",
            (true, _) => "TPaired",
            (false, "large") => "ZUnpaired",
            (false, "non-normal") => "MannWhitney",
            _ => "TUnpaired"
        };

        internal string Advice(string branch) => (Paired, branch) switch
        {
            (true, "large") => "The large-sample branch recommends the paired t test for the mean difference.",
            (true, "normal") => "The paired t test addresses the mean difference. This branch assumes approximately normal differences.",
            (true, "non-normal") => "The signed-rank test concerns a shift in location and assumes roughly symmetric differences. If the aim is specifically to estimate or test the mean difference, consider whether this answers your question.",
            (false, "large") => "The Help routes large, well-behaved samples to the two-sample Z test for the difference in means.",
            (false, "normal") => "The unpaired t test compares means. Consider the spread in each group before using an equal-variance result.",
            _ => "Mann–Whitney compares relative ordering between groups. Use that question to decide whether it fits your goal."
        };

        internal string Conflict(bool large) => Paired
            ? large
                ? "The local check found more than 100 complete pairs. Choose the large-sample route for the mean difference or the non-normal route for Wilcoxon signed ranks."
                : "The local check found at most 100 complete pairs. Choose the branch for the distribution of the differences."
            : large
                ? "The local check found more than 100 observations in each sample. Review their distributions before choosing a method."
                : "The local check found at most 100 observations in at least one sample. Choose the branch for the distributions within groups.";

        internal void AddDetails(JsonObject card)
        {
            card["sizeKnown"] = LargeSample.HasValue;
            card["canCheck"] = CanCheck;
            if (Pairs is { } pairs)
            {
                string summary = pairs.Count == 1 ? "Local check found 1 complete pair" : $"Local check found {pairs.Count} complete pairs";
                summary += NormalityText(pairs.ShapiroWilkW, pairs.ShapiroWilkP);
                if (pairs.ShapiroWilkW == null && LargeSample == false)
                    summary += ". Shapiro–Wilk needs at least three finite differences with some variation.";
                var lines = new JsonArray(summary);
                if (LargeSample == true && pairs.Shape is { } shape)
                {
                    lines.Add($"Shape check · {shape.FarOutCount} beyond the 3× IQR fences");
                    if (shape.Skewness is double skewness && shape.ExcessKurtosis is double kurtosis)
                        lines.Add($"Skewness {skewness:G3} · Excess kurtosis {kurtosis:G3}");
                }
                card["diagnostics"] = lines;
            }
            else if (Columns is { } columns)
            {
                var lines = new JsonArray();
                if (!SeparateSamples)
                    lines.Add("Selected columns, if they hold the two samples separately:");
                lines.Add($"Column 1: n = {columns.First.Count}" + NormalityText(columns.First.ShapiroWilkW, columns.First.ShapiroWilkP));
                lines.Add($"Column 2: n = {columns.Second.Count}" + NormalityText(columns.Second.ShapiroWilkW, columns.Second.ShapiroWilkP));
                card["diagnostics"] = lines;
            }
        }

        internal static (string Branch, string Reason) SuggestPairedBranch(PairedDifferenceDiagnostics pairs)
        {
            if (pairs.Count < 3)
                return (null, "There are too few complete pairs to assess the distribution. Check the selected measurements before choosing.");
            if (!pairs.HasVariation)
                return (null, "All the paired differences are the same, leaving zero variation for the test. Check the selected measurements.");
            if (pairs.Count > MeasurementDistributionDiagnostics.LargeSampleThreshold)
            {
                var signals = new List<string>();
                if (pairs.HasPotentialOutlier) signals.Add("far-out differences");
                if (pairs.HasSkewSignal) signals.Add("pronounced skew");
                if (pairs.Shape?.HasHeavyTails == true) signals.Add("heavy tails");
                if (signals.Count == 0)
                    return ("large", "There are more than 100 complete pairs and the shape checks found no substantial departure. A paired t test answers the question about the mean difference.");

                string evidence = "The shape checks flagged " + string.Join(", ", signals) + ". ";
                string signedRanks = pairs.HasSkewSignal
                    ? "Wilcoxon signed ranks addresses a shift in location and assumes roughly symmetric differences. Pronounced skew makes that assumption doubtful."
                    : "Consider Wilcoxon signed ranks for a shift in location if the differences look roughly symmetric.";
                return (null, evidence + signedRanks + " A paired t test still answers the question about the mean difference. Review any influential differences before choosing.");
            }
            if (pairs.HasPotentialOutlier)
                return (null, "The box-plot check flagged an unusually distant difference. Review whether it reflects a data error or strongly affects the mean before choosing.");
            if (pairs.HasSkewSignal)
                return (null, "The skewness check flagged an uneven shape. Examine the differences before choosing. Signed-rank inference about a shift in location requires roughly symmetric differences.");
            if (pairs.ShapiroWilkP is not double p)
                return (null, "The normality check could not assess these differences. Look at their shape before choosing.");
            if (p < 0.05)
                return ("non-normal", "Shapiro–Wilk found evidence of non-normal differences. Consider Wilcoxon signed-rank if the differences look roughly symmetric and a shift in location answers your question.");
            return ("normal", "A paired t test answers the question about the mean difference. Shapiro–Wilk found no clear departure from normality, and the shape checks flagged no unusual differences. With this sample, those checks provide limited evidence.");
        }

        private static string NormalityText(double? w, double? p) => w.HasValue && p.HasValue
            ? $". Shapiro–Wilk W = {w.Value:G4}, P = {p.Value:G4}."
            : "";
    }
    // windows-copy end
}

namespace StatsDirect.UI {
    // windows-copy begin StatsDirectUI/UI/frmSpreadsheetGear.MeasurementDiagnostics.cs:9-25
    internal sealed record MeasurementDistributionDiagnostics(int Count, double? ShapiroWilkW, double? ShapiroWilkP)
    {
        internal const int LargeSampleThreshold = 100;
    }

    internal sealed record IndependentSampleDiagnostics(
        MeasurementDistributionDiagnostics First, MeasurementDistributionDiagnostics Second);

    internal sealed record PairedDifferenceDiagnostics(
        int Count, double? ShapiroWilkW, double? ShapiroWilkP,
        bool HasVariation, bool HasPotentialOutlier, bool HasSkewSignal, PairedDifferenceShape Shape = null);

    internal sealed record PairedDifferenceShape(
        double LowerQuartile, double UpperQuartile, double? Skewness, double? ExcessKurtosis, int FarOutCount)
    {
        internal bool HasHeavyTails => ExcessKurtosis >= 2.0;
    }
    // windows-copy end

    // The Windows grid's checks of two selected columns (frmSpreadsheetGear.MeasurementDiagnostics.cs:29-56) on what the Mac grid
    // reads from them: it drops the rows without two values and subtracts (:35-36), and sends a column's usable values only (:52-53).
    internal static class MeasurementDiagnostics {
        // CheckSelectedPairedDifferences (:29-44), its row body from the difference on.
        internal static PairedDifferenceDiagnostics CheckPairedDifferences(IEnumerable<double> supplied) {
            var differences = new List<double>();
            double minimum = double.PositiveInfinity, maximum = double.NegativeInfinity;
            foreach (double difference in supplied) {
                // windows-copy begin StatsDirectUI/UI/frmSpreadsheetGear.MeasurementDiagnostics.cs:37-41
                if (RunRecord.Missing(difference))
                    throw new InvalidOperationException("A paired difference is too large to check. Rescale the measurements and try again.");
                differences.Add(difference);
                minimum = Math.Min(minimum, difference);
                maximum = Math.Max(maximum, difference);
                // windows-copy end
            }
            return SummarizePaired(differences, minimum, maximum);
        }
        // CheckSelectedIndependentSamples (:46-56) for one column. The accumulator keeps the first 100 values, and Summarize gives a
        // column of more than 100 its count alone (:84-102), so the grid sends no values for such a column.
        internal static MeasurementDistributionDiagnostics SummarizeSample(int count, IReadOnlyList<double> values) {
            if (count > MeasurementDistributionDiagnostics.LargeSampleThreshold) return new MeasurementDistributionDiagnostics(count, null, null);
            var sample = new MeasurementAccumulator();
            foreach (double value in values) sample.Add(value);
            return sample.Summarize();
        }

        // windows-copy begin StatsDirectUI/UI/frmSpreadsheetGear.MeasurementDiagnostics.cs:84-173
        private sealed class MeasurementAccumulator
        {
            private readonly List<double> smallSample = new(MeasurementDistributionDiagnostics.LargeSampleThreshold);
            private int count;

            internal void Add(double value)
            {
                count++;
                if (count <= MeasurementDistributionDiagnostics.LargeSampleThreshold)
                    smallSample.Add(value);
            }

            internal MeasurementDistributionDiagnostics Summarize()
            {
                var normality = count <= MeasurementDistributionDiagnostics.LargeSampleThreshold
                    ? Parametric.ShapiroWilkDiagnostics(smallSample.ToArray()) : null;
                return new MeasurementDistributionDiagnostics(count, normality?.W, normality?.P);
            }
        }

        private static PairedDifferenceDiagnostics SummarizePaired(List<double> differences, double minimum, double maximum)
        {
            int count = differences.Count;
            bool hasVariation = maximum > minimum;
            if (!hasVariation)
                return new PairedDifferenceDiagnostics(count, null, null, false, false, false);

            bool large = count > MeasurementDistributionDiagnostics.LargeSampleThreshold;
            var sample = differences.ToArray();
            var normality = large ? null : Parametric.ShapiroWilkDiagnostics(sample);
            if (count < 4)
                return new PairedDifferenceDiagnostics(count, normality?.W, normality?.P, true, false, false);

            Array.Sort(sample);
            double lowerQuartile = InterpolatedQuartile(sample, 0.25);
            double upperQuartile = InterpolatedQuartile(sample, 0.75);
            double lower = lowerQuartile, upper = upperQuartile;

            // Rescale extreme data only for the comparisons and moments. Keep the reported quartiles in the original units.
            double span = maximum - minimum;
            if (double.IsInfinity(span))
            {
                double scale = Math.Max(Math.Abs(minimum), Math.Abs(maximum));
                for (int i = 0; i < sample.Length; i++) sample[i] /= scale;
                lower = InterpolatedQuartile(sample, 0.25);
                upper = InterpolatedQuartile(sample, 0.75);
            }
            else if (large && double.IsSubnormal(span))
            {
                for (int i = 0; i < sample.Length; i++) sample[i] = (sample[i] - minimum) / span;
                lower = InterpolatedQuartile(sample, 0.25);
                upper = InterpolatedQuartile(sample, 0.75);
            }
            double iqr = upper - lower;

            Parametric.normality_sk(sample, 0, count, out _, out _, out double skewness, out double kurtosis, out _, out _, out _, out _, out _, out _);
            bool skew = !RunRecord.Missing(skewness) && Math.Abs(skewness) >= 1.0;
            if (!large)
            {
                bool outlier = false;
                if (count >= PairedOutlierFence.MinimumPairs)
                {
                    double multiplier = PairedOutlierFence.Multiplier(count);
                    outlier = (lower - sample[0]) / multiplier > iqr || (sample[^1] - upper) / multiplier > iqr;
                }
                return new PairedDifferenceDiagnostics(count, normality?.W, normality?.P, true, outlier, skew);
            }

            int left = 0, right = count - 1;
            while (left <= right && (lower - sample[left]) / 3.0 > iqr) left++;
            while (right >= left && (sample[right] - upper) / 3.0 > iqr) right--;
            int farOut = left + (count - 1 - right);
            var shape = new PairedDifferenceShape(lowerQuartile, upperQuartile, RunRecord.Missing(skewness) ? null : skewness,
                RunRecord.Missing(kurtosis) ? null : kurtosis - 3.0, farOut);
            // Require at least 0.1% of pairs outside the outer fences so the warning does not depend on seeing just one point in a very large sample.
            return new PairedDifferenceDiagnostics(count, null, null, true, farOut * 1000L >= count, skew, shape);
        }

        private static double InterpolatedQuartile(double[] sorted, double fraction)
        {
            // Match the StatsDirect boxplot's conventional p(n + 1) quantile, using zero-based positions here.
            double position = Math.Clamp(fraction * (sorted.Length + 1) - 1.0, 0.0, sorted.Length - 1);
            int lower = (int)position;
            double remainder = position - lower;
            double first = sorted[lower];
            if (remainder == 0.0) return first;
            double next = sorted[lower + 1];
            double gap = next - first;
            return double.IsInfinity(gap) ? (1.0 - remainder) * first + remainder * next : first + remainder * gap;
        }
        // windows-copy end
    }
}
