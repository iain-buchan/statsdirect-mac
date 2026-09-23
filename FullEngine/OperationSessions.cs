using System;
using System.Collections.Generic;
using System.Collections.Concurrent;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using StatsDirect.Data;
using StatsDirect.Templates;
using StatsDirect.TemplateProcessing;
using StatsDirect.UI;
using StatsDirect.Utilities;

// A running operation is suspended at the original host's input boundary, not replayed.
// In particular, answering a follow-up never reruns randomisation or earlier calculations.
public static class OperationSessions {
    internal static readonly JsonSerializerOptions Json = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase, PropertyNameCaseInsensitive = true };
    static readonly ConcurrentDictionary<string, OperationJob> jobs = new();
    static readonly object gate = new();
    internal static readonly Dictionary<string, ParameterBag> SavedPerOperation = new();
    internal static readonly ParameterBag SavedAcrossOperations = new();
    public sealed record Request(string Action, string Id, string Operation, int Token, JsonElement Value);
    public static string Execute(string input) {
        try {
            var r = JsonSerializer.Deserialize<Request>(input, Json) ?? throw new Exception("Missing operation request.");
            if (!Guid.TryParse(r.Id, out _)) throw new Exception("Invalid operation identifier.");
            object result;
            if (r.Action == "start") {
                lock (gate) {
                    if (jobs.Values.Any(j => !j.Finished)) throw new Exception("Finish or cancel the current analysis first.");
                    if (jobs.ContainsKey(r.Id)) throw new Exception("This analysis has already started.");
                    RuntimeHelpers.RunClassConstructor(typeof(Exports).TypeHandle);
                    _ = SdApplication.SoleInstance;
                    using var catalog = JsonDocument.Parse(File.ReadAllText(Path.Combine(Path.GetDirectoryName(typeof(OperationSessions).Assembly.Location), "AnalysisMenu.json")));
                    if (r.Operation == null || !catalog.RootElement.GetProperty("operations").TryGetProperty(r.Operation, out var definition)) throw new Exception("Unknown Analysis menu command.");
                    if (definition.TryGetProperty("unavailable", out var unavailable)) throw new Exception(unavailable.GetString());
                    if (!TemplateFactory.Operations.TryGetValue(r.Operation, out var operation)) throw new Exception("The operation definition could not be loaded.");
                    var job = new OperationJob(r.Id, operation); jobs[r.Id] = job;
                    Task.Run(job.Run); result = job.Snapshot();
                }
            } else {
                if (!jobs.TryGetValue(r.Id, out var job)) throw new Exception("This analysis session is no longer available.");
                switch (r.Action) {
                    case "poll": result = job.Snapshot(); break;
                    case "answer": job.Answer(r.Token, r.Value); result = job.Snapshot(); break;
                    case "cancel": job.Cancel(); result = job.Snapshot(); break;
                    case "release":
                        if (!job.Finished) throw new Exception("Cancel the analysis before closing it.");
                        jobs.TryRemove(r.Id, out _); result = new { ok = true }; break;
                    default: throw new Exception("Unknown operation action.");
                }
            }
            return JsonSerializer.Serialize(result, Json);
        } catch (Exception ex) { return JsonSerializer.Serialize(new { error = ex.Message }, Json); }
    }
    [UnmanagedCallersOnly] public static IntPtr Invoke(IntPtr text) => Marshal.StringToCoTaskMemUTF8(Execute(Marshal.PtrToStringUTF8(text) ?? "{}"));
    [UnmanagedCallersOnly] public static void Free(IntPtr text) => Marshal.FreeCoTaskMem(text);
}

internal sealed class OperationJob {
    readonly object sync = new();
    public string Id { get; }
    public Operation Operation { get; }
    public volatile bool Cancelled;
    public volatile bool Finished;
    int token;
    Dictionary<string, object> prompt;
    JsonElement? answer;
    string state = "running", error, html;
    string progress = "Starting analysis…";
    double? fraction;
    object frames, outputs;
    sealed record InputRecord(string Title, object Value);
    readonly List<InputRecord> history = new();
    public OperationJob(string id, Operation operation) { Id = id; Operation = operation; }
    public object Snapshot() { lock (sync) return new { id = Id, state, token, prompt, progress, fraction, error, html, frames, values = outputs, history = state == "complete" ? (object)history.ToArray() : history.Select(h => new { title = h.Title }).ToArray() }; }
    public void Check() { if (Cancelled) throw new OperationCanceledException(); }
    public void Progress(string text, double? value = null) { lock (sync) { progress = text; fraction = value; } }
    public JsonElement Ask(Dictionary<string, object> descriptor) {
        lock (sync) {
            Check(); prompt = descriptor; answer = null; state = "input"; token++;
            while (!answer.HasValue) { Check(); Monitor.Wait(sync, 500); }
            var value = answer.Value; answer = null; state = "running"; prompt = null;
            return value;
        }
    }
    public void Record(string title, object value) { lock (sync) history.Add(new InputRecord(title, value)); }
    public void Answer(int requestedToken, JsonElement value) {
        lock (sync) {
            Check(); if (state != "input" || token != requestedToken || answer.HasValue) throw new Exception("That input step has already changed. Use the current form.");
            answer = value.Clone(); state = "running"; Monitor.PulseAll(sync);
        }
    }
    public void Cancel() { lock (sync) { if (Finished) return; Cancelled = true; progress = "Cancelling at the next engine checkpoint…"; Monitor.PulseAll(sync); } }
    public void Run() {
        try {
            var host = new OperationHost(this);
            var result = ((ITemplateProcessor)new TemplateProcessor(host)).Execute(Operation, new ParameterBag());
            Check(); if (result == null) throw new Exception("The engine ended this operation without completing it.");
            lock (sync) {
                html = host.Html.ToString(); frames = host.Frames.ToArray(); outputs = HostParameters.ScalarOutputs(result.ParameterBag);
                state = "complete"; Finished = true; progress = "Analysis complete"; fraction = 1;
            }
        } catch (Exception ex) {
            lock (sync) { state = Cancelled || ex is OperationCanceledException ? "cancelled" : "failed"; error = state == "failed" ? ex.Message : null; Finished = true; }
        } finally { lock (sync) { prompt = null; Finished = true; Monitor.PulseAll(sync); } }
    }
}

internal sealed class OperationHost : ITemplateHost {
    readonly OperationJob job;
    internal readonly List<object> Frames = new();
    public System.Text.StringBuilder Html { get; } = new();
    public OperationHost(OperationJob job) { this.job = job; }
    public SDPreferences Preferences => SdApplication.SoleInstance.Preferences;
    public Operation Operation { get; set; }
    public IDictionary<string, ParameterBag> SessionParametersPerOperation => OperationSessions.SavedPerOperation;
    public ParameterBag SessionParametersAcrossOperations => OperationSessions.SavedAcrossOperations;
    public bool CanCombine(Parameter p) => false;
    public void PrepareParameter(ITemplateProcessor processor, Parameter p, ParameterBag context) { job.Check(); }
    public ParameterBag FillAndValidateCombinedParameters(ITemplateProcessor processor, ParameterBag context) => throw new InvalidOperationException("Unexpected combined parameter request.");
    public ParameterBag FillParameter(ITemplateProcessor processor, Parameter p, ParameterBag context, bool shouldCombine) {
        job.Check();
        if (!p.AcquireIfTrue(processor, context)) return new ParameterBag();
        if (p is FrameParameter stored && stored.Data != null) return new ParameterBag(p.Name, FilledParameterFactory.Input(stored.Data.Frame));
        if (p is SpecialParameter target && (target.SpecialType == "frame" || target.SpecialType == "report")) return new ParameterBag();
        if (p is SpecialParameter scores && scores.SpecialType == "scores") {
            var options = new StatsDirect.Builtins.ScoresOptions {Title1=context["c1"].AsDataFrame.Variables[0].Title,Title2=context["c2"].AsDataFrame.Variables[0].Title};
            options.Values1.AddRange(Enumerable.Range(1,context["ycats"].AsInt32).Select(i=>(double)i));options.Values2.AddRange(Enumerable.Range(1,context["xcats"].AsInt32).Select(i=>(double)i));
            HostAmendments.Amend(job,this,options,context);var values=new ParameterBag();values.AddInput("values1",options.Values1.ToArray());values.AddInput("values2",options.Values2.ToArray());return values;
        }
        if (p is Frame2DParameter multi) return new ParameterBag(p.Name, FilledParameterFactory.Input(HostComplexData.Frame2D(job, multi, processor, context)));
        if (p is GroupedCovarianceParameter) return new ParameterBag(p.Name, FilledParameterFactory.Input(HostComplexData.GroupedCovariance(job, this)));
        string error = null;
        while (true) {
            var descriptor = HostParameters.Describe(p, processor, context, Preferences);
            descriptor["error"] = error;
            var input = job.Ask(descriptor);
            try {
                var filled = HostParameters.Parse(p, input, processor, context, this);
                var combined = new ParameterBag(); foreach (var pair in context) combined[pair.Key] = pair.Value; foreach (var pair in filled) combined[pair.Key] = pair.Value;
                if (p.Validators != null && filled.Count > 0) foreach (var validator in p.Validators) {
                    if (validator.HasTestIfTrueExpression && !(bool)processor.Evaluate(validator.TestIfTrueExpression, combined)) continue;
                    var validation = ValidationProcessor.Validate(this, validator.ValidatorName, p, combined, p.ValidationFailMessage);
                    if (validation.Validity == Validity.Invalid) throw new ArgumentException(validation.FailedValidationMessage);
                    if (validation.Validity == Validity.NeedMoreInformation) {
                        bool yes = GetBoolean(validation.PromptForMoreInformation, validation.TitleForMoreInformation, false, out _);
                        var action = yes ? validation.ActionOnMoreInformationYes : validation.ActionOnMoreInformationNo;
                        if (action == ValidationAction.CancelOperation) { job.Cancel(); job.Check(); }
                        if (action == ValidationAction.RequestAgain) throw new ArgumentException(validation.FailedValidationMessage);
                    }
                }
                HostParameters.Commit(p, filled, context);
                job.Record(descriptor["prompt"] as string, input);
                return filled;
            } catch (ArgumentException ex) { error = ex.Message; }
        }
    }
    public bool GetBoolean(string prompt, string title, bool initialValue, out bool cancelled) {
        cancelled = false;
        var response = job.Ask(new() { ["kind"] = "boolean", ["title"] = title, ["prompt"] = prompt, ["defaultValue"] = initialValue });
        bool value = response.GetBoolean(); job.Record(title + ": " + prompt, value); return value;
    }
    public ParameterBag Amend(IFillable options, ParameterBag context) => HostAmendments.Amend(job, this, options, context);
    public void Error(string message, string caption) { job.Check(); throw new InvalidOperationException(caption + ": " + message); }
    public void Warning(string message, string caption) { Html.Append("<p class='note'>").Append(System.Net.WebUtility.HtmlEncode(caption + ": " + message)).Append("</p>"); }
    public object OutputReport(IRenderable renderable, Operation operation, object preferredOutputLocation) { job.Check(); Html.Append(new HtmlRenderer(this).Render(renderable)); return null; }
    public void OutputFrame(DataFrame frame, bool keepSelection, bool isFormulae, string missingIndicator, PaneAndPosition preferredOutputLocation, RelativePosition defaultPosition) {
        job.Check(); Frames.Add(HostParameters.FrameOutput(frame, isFormulae));
    }
    public IScriptEngine GetScriptEngine(string language) => ScriptEngine.CanHandle(language) ? new ScriptEngine() : null;
    public string pval(double p) => Formatting.pval(p, Preferences.PDecimalPlaces, Preferences.UseScientificNotationForSmallPValues);
    public string pval_half(double p) => Formatting.pval_half(p, Preferences.PDecimalPlaces, Preferences.UseScientificNotationForSmallPValues);
    public string RoundU(double value) => Formatting.XRound(value, Preferences.DisplayDecimalPlaces);
    public IProgressBar StartProgress(string operationDescription, bool provideProgress, bool display) { job.Check(); job.Progress(operationDescription); return new ProgressBar(job, operationDescription); }
    sealed class ProgressBar(OperationJob job, string title) : IProgressBar {
        public bool Update(double fractionComplete) { job.Progress(title, fractionComplete); return job.Cancelled; }
        public void Finish() { }
        public void Dispose() { }
    }
}
