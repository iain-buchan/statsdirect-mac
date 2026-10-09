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
using StatsDirect.Numerics;
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
    public sealed record Request(string Action, string Id, string Operation, int Token, JsonElement Value, JsonElement Preferences, string Parent);
    public static string Execute(string input) {
        try {
            var r = JsonSerializer.Deserialize<Request>(input, Json) ?? throw new Exception("Missing operation request.");
            if (!Guid.TryParse(r.Id, out _)) throw new Exception("Invalid operation identifier.");
            object result;
            if (r.Action == "start") {
                lock (gate) {
                    if (jobs.ContainsKey(r.Id)) throw new Exception("This analysis has already started.");
                    RuntimeHelpers.RunClassConstructor(typeof(Exports).TypeHandle);
                    _ = SdApplication.SoleInstance;
                    // A follow-on starts from the inputs of a completed analysis, as the Windows
                    // application does when the user picks a suggested operation after a result.
                    OperationJob parent = null; ParameterBag context = null;
                    if (!string.IsNullOrEmpty(r.Parent)) {
                        if (!jobs.TryGetValue(r.Parent, out parent) || parent.FollowOnContext == null) throw new Exception("The analysis this follows on from is no longer open. Run it again, then choose the follow-on from its result.");
                        context = parent.FollowOnContext.CopyWithoutOutputParameters();
                        if (context.ContainsKey(OperationJob.MemoryName)) { var memory = new List<string>(context[OperationJob.MemoryName].AsStringList); context.Remove(OperationJob.MemoryName); context.AddInput(OperationJob.MemoryName, memory); }
                    }
                    using var catalog = JsonDocument.Parse(File.ReadAllText(Path.Combine(Path.GetDirectoryName(typeof(OperationSessions).Assembly.Location), "AnalysisMenu.json")));
                    bool suggested = parent != null && r.Operation != null && parent.SuggestionNames.Contains(r.Operation);
                    JsonElement definition = default;
                    bool inCatalog = r.Operation != null && catalog.RootElement.GetProperty("operations").TryGetProperty(r.Operation, out definition);
                    if (!inCatalog && !suggested) throw new Exception("Unknown menu command.");
                    if (inCatalog && definition.TryGetProperty("unavailable", out var unavailable)) throw new Exception(unavailable.GetString());
                    if (!TemplateFactory.Operations.TryGetValue(r.Operation, out var operation)) throw new Exception("The operation definition could not be loaded.");
                    // Windows runs any operation its suggestion list offers; prerequisites only guard a direct start.
                    if (!suggested && operation.HasPrerequisites) {
                        var ran = context != null && context.ContainsKey(OperationJob.MemoryName) ? context[OperationJob.MemoryName].AsStringList : new List<string>();
                        if (!operation.PrerequisiteOperationNames.Any(ran.Contains)) {
                            var names = operation.PrerequisiteOperationNames.Select(n => TemplateFactory.Operations.TryGetValue(n, out var p) ? p.FriendlyName ?? n : n);
                            throw new Exception($"{operation.FriendlyName ?? operation.Name} follows on from {string.Join(" or ", names)}. Run that analysis first, then choose this method from its follow-on list.");
                        }
                    }
                    var job = new OperationJob(r.Id, operation, r.Preferences, context, r.Parent, parent?.HistorySnapshot()); jobs[r.Id] = job;
                    Task.Factory.StartNew(job.Run, CancellationToken.None, TaskCreationOptions.LongRunning, TaskScheduler.Default);
                    result = job.Snapshot();
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
    public JsonElement SavedPreferences { get; }
    public volatile bool Cancelled;
    public volatile bool Finished;
    int token;
    Dictionary<string, object> prompt;
    JsonElement? answer;
    string state = "running", error, html;
    string progress = "Starting analysis…";
    double? fraction;
    object frames, outputs, analysisOptions, suggestions;
    internal sealed record InputRecord(string Title, object Value, string Name = null, string Kind = null, string Mode = null);
    readonly List<InputRecord> history = new();
    // A follow-on's report and R script list the parent's inputs before its own.
    public List<InputRecord> HistorySnapshot() { lock (sync) return history.ToList(); }
    // Windows keeps the names of the operations run on a set of parameters under this key.
    public const string MemoryName = "statsdirect-operation-list";
    readonly ParameterBag startContext; readonly string parentId;
    readonly HashSet<string> suggestionNames = new();
    // The inputs a follow-on starts from (set when the operation completes) and the operations suggested from the result.
    public ParameterBag FollowOnContext { get; private set; }
    public IReadOnlyCollection<string> SuggestionNames => suggestionNames;
    // The Windows shell writes an operation's output frames into a worksheet at the first output
    // step's default placement (after the selected columns unless the definition says otherwise);
    // the form offers the same placements, so the start snapshot carries them.
    readonly bool writesWorksheet; readonly string placement;
    static OutputFrameStep FirstOutputFrame(IEnumerable<Step> steps) {
        foreach (var step in steps) {
            switch (step) {
                case OutputFrameStep o: return o;
                case IterationStep it: { var found = FirstOutputFrame(it.Steps); if (found != null) return found; break; }
                case TestStep t: { var found = FirstOutputFrame(t.TrueSteps) ?? FirstOutputFrame(t.FalseSteps); if (found != null) return found; break; }
            }
        }
        return null;
    }
    public OperationJob(string id, Operation operation, JsonElement preferences, ParameterBag context = null, string parent = null, List<InputRecord> inherited = null) {
        Id = id; Operation = operation; SavedPreferences = preferences; startContext = context; parentId = parent;
        if (inherited != null) history.AddRange(inherited);
        var output = FirstOutputFrame(operation.Steps); writesWorksheet = output != null; placement = output?.DefaultPlacement.ToString();
    }
    public object Snapshot() { lock (sync) return new { id = Id, state, token, prompt, progress, fraction, error, html, frames, analysisOptions, values = outputs, suggestions, parent = parentId, writesWorksheet, placement, history = state == "complete" ? (object)history.ToArray() : history.Select(h => new { title = h.Title }).ToArray() }; }
    static void NoteOperation(ParameterBag bag, string name) {
        if (!bag.ContainsKey(MemoryName)) bag.AddInput(MemoryName, new List<string>());
        var list = bag[MemoryName].AsStringList;
        if (!list.Contains(name)) list.Add(name);
    }
    // The Windows rule: the operation's own suggestions whose suggest-if holds; failing that,
    // those of the earliest operation already run on these parameters. The operation itself
    // is left out (the form can rerun it), as are names without a definition.
    static List<object> Suggestions(ITemplateProcessor processor, Operation operation, ParameterBag bag, HashSet<string> names) {
        IList<SuggestedOperation> available;
        try { available = operation.AvailableSuggestedOperations(processor, bag); } catch { available = new List<SuggestedOperation>(); }
        if (available.Count == 0 && bag.ContainsKey(MemoryName)) {
            foreach (var name in bag[MemoryName].AsStringList) {
                if (!TemplateFactory.Operations.TryGetValue(name, out var previous)) continue;
                try { var list = previous.AvailableSuggestedOperations(processor, bag); if (list.Count > 0) { available = list; break; } } catch { }
            }
        }
        var result = new List<object>();
        foreach (var su in available) {
            if (su.Name == operation.Name || names.Contains(su.Name) || !TemplateFactory.Operations.TryGetValue(su.Name, out var target)) continue;
            names.Add(su.Name);
            result.Add(new { operation = su.Name, title = target.FriendlyName ?? su.Name, help = target.HelpContext?.ChmId > 0 ? target.HelpContext.ChmId.ToString() : null });
        }
        return result;
    }
    public void Check() { if (Cancelled) throw new OperationCanceledException(); }
    public void Progress(string text, double? value = null) { lock (sync) { progress = text; fraction = value; } }
    public JsonElement Ask(Dictionary<string, object> descriptor) {
        var value = EngineExecution.WaitForInput(() => {
            lock (sync) {
                Check(); prompt = descriptor; answer = null; state = "input"; token++;
                while (!answer.HasValue) { Check(); Monitor.Wait(sync, 500); }
                var input = answer.Value; answer = null; state = "running"; prompt = null;
                return input;
            }
        });
        Check(); return value;
    }
    public void Record(string title, object value, string name = null, string kind = null, string mode = null) { lock (sync) history.Add(new InputRecord(title, value, name, kind, mode)); }
    public void Answer(int requestedToken, JsonElement value) {
        lock (sync) {
            Check(); if (state != "input" || token != requestedToken || answer.HasValue) throw new Exception("That input step has already changed. Use the current form.");
            answer = value.Clone(); state = "running"; Monitor.PulseAll(sync);
        }
    }
    public void Cancel() { lock (sync) { if (Finished) return; Cancelled = true; state = "running"; prompt = null; progress = "Cancelling at the next engine checkpoint…"; Monitor.PulseAll(sync); } }
    public void Run() {
        lock (EngineExecution.Gate) RunWithEngine();
    }
    void RunWithEngine() {
        try {
            Check();
            var host = new OperationHost(this);
            StatsDirect.UI.OperationHacks.Information = text => host.Warning(text,"Search results");
            // The Windows basic-search command only sends Ctrl+H to its shell. Use
            // the existing search operation and unit-conversion engine in this host.
            var engineOperation = Operation.Name switch {
                "SearchAndReplace" => TemplateFactory.Operations["SearchAndReplaceAdvanced"],
                "ConvertUnitsScreen" => TemplateFactory.Operations["ConvertUnits"],
                _ => Operation
            };
            var processor = (ITemplateProcessor)new TemplateProcessor(host);
            var result = processor.Execute(engineOperation, startContext ?? new ParameterBag());
            Check(); if (result == null) throw new Exception("The engine ended this operation without completing it.");
            NoteOperation(result.ParameterBag, Operation.Name);
            var available = Suggestions(processor, Operation, result.ParameterBag, suggestionNames);
            if (Operation.Name is "AnalysisOptions" or "MetaCalculationOptions" or "MetaPlotOptions") {
                analysisOptions = AnalysisDefaults.Values(host.Preferences);
                AnalysisDefaults.Apply(SdApplication.SoleInstance.Preferences, JsonSerializer.SerializeToElement(analysisOptions));
            }
            lock (sync) {
                html = host.Html.ToString(); frames = host.Frames.ToArray(); outputs = HostParameters.ScalarOutputs(result.ParameterBag);
                suggestions = available; FollowOnContext = result.ParameterBag.CopyWithoutOutputParameters();
                state = "complete"; Finished = true; progress = "Analysis complete"; fraction = 1;
            }
        } catch (Exception ex) {
            lock (sync) { state = Cancelled || ex is OperationCanceledException ? "cancelled" : "failed"; error = state == "failed" ? ex.Message : null; Finished = true; }
        } finally { StatsDirect.UI.OperationHacks.Information = null; lock (sync) { prompt = null; Finished = true; Monitor.PulseAll(sync); } }
    }
}

internal sealed class OperationHost : ITemplateHost {
    readonly OperationJob job;
    readonly Dictionary<string, ParameterBag> savedPerOperation = new();
    readonly ParameterBag savedAcrossOperations = new();
    internal readonly List<object> Frames = new();
    // The layout the user last chose for a pivotable frame in this analysis (Windows keeps the radio setting).
    internal bool? GroupsByIdentifier;
    public System.Text.StringBuilder Html { get; } = new();
    public OperationHost(OperationJob job) {
        this.job = job;
        var snapshot = AnalysisDefaults.Snapshot(SdApplication.SoleInstance.Preferences);
        AnalysisDefaults.Apply(snapshot, job.SavedPreferences);
        Preferences = job.Operation.Name == "GraphicsOptions" ? SdApplication.SoleInstance.Preferences : snapshot;
    }
    public SDPreferences Preferences { get; }
    public Operation Operation { get; set; }
    // Each launched form starts from definition defaults. Keep recall within that
    // running form so cancelled or previous launches cannot seed stale inputs.
    public IDictionary<string, ParameterBag> SessionParametersPerOperation => savedPerOperation;
    public ParameterBag SessionParametersAcrossOperations => savedAcrossOperations;
    readonly List<Parameter> settingsParameters = new();
    bool IsSettings => job.Operation.Name is "AnalysisOptions" or "MetaCalculationOptions" or "MetaPlotOptions";
    public bool CanCombine(Parameter p) => IsSettings && p is BooleanParameter or OptionParameter;
    public void PrepareParameter(ITemplateProcessor processor, Parameter p, ParameterBag context) { job.Check(); }
    public ParameterBag FillAndValidateCombinedParameters(ITemplateProcessor processor, ParameterBag context) {
        if (!IsSettings) throw new InvalidOperationException("Unexpected combined parameter request.");
        var fields = settingsParameters.Select(p => {
            var d=HostParameters.Describe(p,processor,context,Preferences);
            if (p.Name=="default-ci") d["prompt"]="Default confidence level";
            return d;
        }).ToArray();
        string error=null;
        while (true) {
            var input=job.Ask(new() { ["kind"]="settings", ["name"]="analysisOptions", ["prompt"]=job.Operation.FriendlyName, ["fields"]=fields, ["error"]=error });
            try {
                var filled=new ParameterBag();
                foreach (var p in settingsParameters) {
                    if (!input.TryGetProperty(p.Name,out var value)) throw new ArgumentException("Complete every analysis option.");
                    foreach (var pair in HostParameters.Parse(p,value,processor,context,this)) filled[pair.Key]=pair.Value;
                }
                // Validate the complete group before the original options builtin changes anything.
                if (job.Operation.Name == "AnalysisOptions") AnalysisDefaults.Apply(AnalysisDefaults.Snapshot(Preferences),input);
                foreach (var p in settingsParameters) job.Record(p.Prompt(processor,context),input.GetProperty(p.Name).Clone(),p.Name,p is BooleanParameter?"boolean":"option");
                settingsParameters.Clear(); return filled;
            } catch (ArgumentException ex) { error=ex.Message; }
        }
    }
    public ParameterBag FillParameter(ITemplateProcessor processor, Parameter p, ParameterBag context, bool shouldCombine) {
        job.Check();
        if (!p.AcquireIfTrue(processor, context)) return new ParameterBag();
        if (shouldCombine && CanCombine(p)) { settingsParameters.Add(p); return new ParameterBag(); }
        // Basic search is exact whole-cell replacement. Advanced search retains
        // its numeric comparisons, expressions and row/cell deletion choices.
        if (job.Operation.Name == "SearchAndReplace" && p.Name is "search-type" or "search-rule" or "action") {
            string value = p.Name == "search-type" ? "text" : p.Name == "search-rule" ? "equal" : "replace-value";
            return HostParameters.Parse(p,JsonSerializer.SerializeToElement(value),processor,context,this);
        }
        if (p is FrameParameter stored && stored.Data != null) return new ParameterBag(p.Name, FilledParameterFactory.Input(stored.Data.Frame));
        if (p is SpecialParameter target && (target.SpecialType == "frame" || target.SpecialType == "report")) return new ParameterBag();
        if (p is SpecialParameter rubric && rubric.SpecialType == "rubric") {
            Html.Append("<p>").Append(System.Net.WebUtility.HtmlEncode(p.Prompt(processor, context))).Append("</p>");
            return new ParameterBag();
        }
        if (p is SpecialParameter constant && constant.SpecialType == "addedConstant") {
            double minimum = StatsDirect.Builtins.Sheet.XConstant(((DoubleVariable)context["data"].AsDataFrame.Variables[0]).Data);
            context.AddOutput("a_min", minimum);
            if (minimum == Constant.MISSING) return new ParameterBag();
            string inputError = null;
            while (true) {
                var input = job.Ask(new() { ["kind"]="number",["name"]=p.Name,["prompt"]=p.Prompt(processor,context),["defaultValue"]=minimum,["min"]=minimum,["skip"]="Skip",["error"]=inputError });
                if (input.ValueKind == JsonValueKind.Object && input.TryGetProperty("skip",out _)) return new ParameterBag();
                try { double n=HostParameters.Number(input);if(n<minimum)throw new ArgumentException("The constant must be at least " + minimum);job.Record(p.Name,n);return new ParameterBag(p.Name,FilledParameterFactory.Input(n)); }
                catch(ArgumentException ex) { inputError=ex.Message; }
            }
        }
        if (p is SpecialParameter coding && coding.SpecialType == "textToNumbers") return HostDataForms.TextCodes(job,context);
        if (p is SpecialParameter scores && scores.SpecialType == "scores") {
            var options = new StatsDirect.Builtins.ScoresOptions {Title1=context["c1"].AsDataFrame.Variables[0].Title,Title2=context["c2"].AsDataFrame.Variables[0].Title};
            options.Values1.AddRange(Enumerable.Range(1,context["ycats"].AsInt32).Select(i=>(double)i));options.Values2.AddRange(Enumerable.Range(1,context["xcats"].AsInt32).Select(i=>(double)i));
            HostAmendments.Amend(job,this,options,context);var values=new ParameterBag();values.AddInput("values1",options.Values1.ToArray());values.AddInput("values2",options.Values2.ToArray());return values;
        }
        if (p is Frame2DParameter multi) return new ParameterBag(p.Name, FilledParameterFactory.Input(HostComplexData.Frame2D(job, multi, processor, context, this)));
        if (p is GroupedCovarianceParameter) return new ParameterBag(p.Name, FilledParameterFactory.Input(HostComplexData.GroupedCovariance(job, this)));
        string error = null;
        while (true) {
            var descriptor = HostParameters.Describe(p, processor, context, Preferences, GroupsByIdentifier);
            if (job.Operation.Name == "ConvertUnitsScreen" && p is FrameParameter) descriptor["screen"] = true;
            if (job.Operation.Name == "ClearMissing" && p.Name == "missing-double") {
                descriptor["defaultValue"] = null;
                descriptor["rubric"] = "Missing cells are shown as *. Enter an additional numeric code (for example −999), or choose Skip.";
            }
            if (job.Operation.Name == "SearchAndReplace") {
                if (p.Name == "search-expression") { descriptor["prompt"]="Find this whole-cell value"; descriptor["rubric"]="Exact, case-sensitive match. Use Advanced for expressions or numeric comparisons."; }
                if (p.Name == "replace-expression") descriptor["prompt"]="Replace with this value";
            }
            descriptor["error"] = error;
            // Match the Windows ImmediateParameterFiller: only parameters which
            // permit defaulting use the saved CI without displaying another form.
            bool useDefault = error == null && p is ConfidenceIntervalParameter ci && ci.CanDefault && Preferences.CanDefaultConfidenceInterval;
            var input = useDefault ? JsonSerializer.SerializeToElement(Preferences.DefaultConfidenceInterval * 100) : job.Ask(descriptor);
            try {
                var filled = HostParameters.Parse(p, input, processor, context, this);
                if (p is FrameParameter pivotable && descriptor.ContainsKey("groupIdentifiers")) GroupsByIdentifier = HostParameters.IsLongLayout(input);
                HostInputChecks.Validate(job.Operation.Name,p.Name,filled,context);
                var combined = new ParameterBag(); foreach (var pair in context) combined[pair.Key] = pair.Value; foreach (var pair in filled) combined[pair.Key] = pair.Value;
                if (p.Validators != null && filled.Count > 0) foreach (var validator in p.Validators) {
                    if (validator.HasTestIfTrueExpression && !(bool)processor.Evaluate(validator.TestIfTrueExpression, combined)) continue;
                    // Search's literal text fields are quoted by its builtin. Only
                    // expression mode should be passed to the expression validator.
                    bool literalText = combined.ContainsKey("search-type") && combined["search-type"].AsString == "text" &&
                        (p.Name == "search-expression" && combined["search-rule"].AsString != "match" ||
                         p.Name == "replace-expression" && combined["action"].AsString == "replace-value");
                    if (validator.ValidatorName == "Expression" && literalText) continue;
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
                job.Record(descriptor["prompt"] as string, HostParameters.Recorded(p, input, filled), p.Name, descriptor["kind"] as string, descriptor.TryGetValue("mode", out var acquisitionMode) ? acquisitionMode as string : null);
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
        job.Check(); Frames.Add(HostParameters.FrameOutput(frame, isFormulae, defaultPosition.ToString(), keepSelection, missingIndicator ?? Formatting.ASTERISK));
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
