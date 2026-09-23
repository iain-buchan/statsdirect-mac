using System;
using System.Collections.Generic;
using System.Collections.Concurrent;
using System.Globalization;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Text.Json;
using StatsDirect.UI;
using StatsDirect.Templates;
using StatsDirect.TemplateProcessing;
using StatsDirect.Builtins;
using StatsDirect.Numerics;

// Validates form input and supplies the original operation's parameters. No calculation code lives here.
public static class AnalysisIO {
    static readonly JsonSerializerOptions json = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase, PropertyNameCaseInsensitive = true };
    sealed class Job { public volatile bool Cancelled; public DateTime Created = DateTime.UtcNow; }
    static readonly ConcurrentDictionary<string, Job> jobs = new();
    public sealed record Request(string Action, string Id, Input Input);
    public sealed class Input {
        public double[][] Counts { get; set; }
        public string[] RowLabels { get; set; }
        public string[] ColumnLabels { get; set; }
        public bool DoExact { get; set; } = true;
        public bool Show_pc { get; set; } = true;
        public bool Xp { get; set; }
        public bool Cs { get; set; }
        public bool Xs { get; set; }
        public bool Specify_scores { get; set; }
        public double Cco { get; set; } = .95;
        public bool DoMonteCarlo { get; set; }
        public int Iterations { get; set; } = 1000000;
        public int Seed { get; set; } = 12345;
        public double Ci { get; set; } = .99;
        public double[] RowScores { get; set; }
        public double[] ColumnScores { get; set; }
    }
    public static string Execute(string text) {
        try {
            var request = JsonSerializer.Deserialize<Request>(text, json) ?? throw new Exception("Missing analysis request.");
            if (!Guid.TryParse(request.Id, out _)) throw new Exception("Missing analysis identifier.");
            if (request.Action == "cancel") {
                jobs.GetOrAdd(request.Id, _ => new Job()).Cancelled = true;
                return "{\"ok\":true}";
            }
            if (request.Action != "run") throw new Exception("Unknown analysis action.");
            foreach (var old in jobs.Where(j => j.Value.Created < DateTime.UtcNow.AddDays(-1))) jobs.TryRemove(old.Key, out _);
            var job = jobs.GetOrAdd(request.Id, _ => new Job());
            try { return JsonSerializer.Serialize(Run(request.Input, job), json); }
            finally { jobs.TryRemove(request.Id, out _); }
        } catch (OperationCanceledException) { return "{\"cancelled\":true}"; }
        catch (Exception ex) { return JsonSerializer.Serialize(new { error = ex.Message }, json); }
    }
    static void Require(bool condition, string message) { if (!condition) throw new ArgumentException(message); }
    static object Run(Input input, Job job) {
        Require(input != null, "Missing contingency table.");
        var a = input.Counts;
        int rows = a?.Length ?? 0, cols = rows > 0 ? a[0]?.Length ?? 0 : 0;
        Require(rows >= 2 && rows <= 200 && cols >= 2 && cols <= 200 && rows * cols <= 2500,
            "Use 2–200 rows and columns, with at most 2,500 cells in this prototype.");
        Require(a.All(row => row != null && row.Length == cols), "Every row must have the same number of counts.");
        Require(a.SelectMany(row => row).All(x => double.IsFinite(x) && x >= 0 && x <= 1000000000 && x == Math.Floor(x)),
            "Every cell needs a non-negative whole count. Enter 0 explicitly for an empty cell.");
        double total = a.Sum(row => row.Sum());
        Require(total <= 1000000000, "The prototype supports a total count up to 1,000,000,000.");
        Require(a.All(row => row.Sum() > 0) && Enumerable.Range(0, cols).All(c => a.Sum(row => row[c]) > 0),
            "Every row and column must have a positive total. Remove unused categories.");
        Require(input.Cco > 0 && input.Cco < 1, "Confidence must be greater than 0% and less than 100%.");
        if (input.DoMonteCarlo) {
            Require(input.Iterations >= 1 && input.Iterations <= 10000000, "Use 1–10,000,000 simulation iterations.");
            Require(input.Seed >= 1, "Use a seed from 1 to 2,147,483,647.");
            Require(input.Ci > 0 && input.Ci < 1, "Simulation confidence must be between 0% and 100%.");
            Require(total <= 5000000, "Simulation supports a total count up to 5,000,000.");
        }
        if (input.Specify_scores) {
            bool Valid(double[] values, int count) => values?.Length == count && values.All(x => double.IsFinite(x) && Math.Abs(x) <= 1000000) && values.Distinct().Count() > 1;
            Require(Valid(input.RowScores, rows) && Valid(input.ColumnScores, cols), "Supply one finite score per category, with varying scores on each axis (magnitude up to 1,000,000).");
        }
        Require(input.RowLabels == null || input.RowLabels.Length == rows, "Row label count does not match the table.");
        Require(input.ColumnLabels == null || input.ColumnLabels.Length == cols, "Column label count does not match the table.");
        void Check() { if (job.Cancelled) throw new OperationCanceledException(); }
        Check();
        RuntimeHelpers.RunClassConstructor(typeof(Exports).TypeHandle);
        _ = SdApplication.SoleInstance;
        var parameters = new List<OperationTestInputParameter>();
        void Add(string name, object value) => parameters.Add(new() { Name = name, Value = Convert.ToString(value, CultureInfo.InvariantCulture) });
        string csv = string.Join(',', Enumerable.Range(1, cols).Select(c => "Column " + c)) + "\n" +
            string.Join('\n', a.Select(row => string.Join(',', row.Select(x => x.ToString("R", CultureInfo.InvariantCulture)))));
        Add("data", csv); Add("doExact", input.DoExact); Add("show_pc", input.Show_pc); Add("xp", input.Xp);
        Add("cs", input.Cs); Add("xs", input.Xs); Add("specify_scores", input.Specify_scores); Add("cco", input.Cco);
        Add("doMonteCarlo", input.DoMonteCarlo); Add("iterations", input.Iterations); Add("seed", input.Seed); Add("ci", input.Ci);
        var host = new ViewerHost(parameters) { Cancelled = () => job.Cancelled, AmendOptions = options => {
            if (options is not ScoresOptions scores || !input.Specify_scores) throw new Exception("Unexpected operation prompt.");
            // The upstream routine consumes Values1 as row scores and Values2 as column scores.
            scores.Values1.Clear(); scores.Values1.AddRange(input.RowScores);
            scores.Values2.Clear(); scores.Values2.AddRange(input.ColumnScores);
        }};
        var result = ((ITemplateProcessor)new TemplateProcessor(host)).Execute(TemplateFactory.Operations["ExactChiRbyCScreen"], new ParameterBag()).ParameterBag;
        Check(); // A cancelled simulation may return partial output: never publish it as a completed report.
        return new { html = host.Html.ToString(), values = Scalars(result), input, total, warnings = host.Warnings,
            operation = "ExactChiRbyCScreen", exactSkipped = input.DoExact && total > 100000 };
    }
    static Dictionary<string, object> Scalars(ParameterBag bag) {
        var result = new Dictionary<string, object>();
        foreach (var (key, value) in bag) {
            if (value.IsDouble) result[key] = double.IsFinite(value.AsDouble) && value.AsDouble != Constant.MISSING ? value.AsDouble : null;
            else if (value.IsInt32) result[key] = value.AsInt32;
            else if (value.IsString) result[key] = value.AsString;
            else if (key.StartsWith("*pmc") && value.IsParameterBagList) result[key] = value.AsParameterBagList.Select(Scalars).ToArray();
        }
        return result;
    }
    [UnmanagedCallersOnly]
    public static IntPtr Invoke(IntPtr input) => Marshal.StringToCoTaskMemUTF8(Execute(Marshal.PtrToStringUTF8(input) ?? "{}"));
    [UnmanagedCallersOnly]
    public static void Free(IntPtr result) => Marshal.FreeCoTaskMem(result);
}
