using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using StatsDirect.Data;
using StatsDirect.Templates;
using StatsDirect.TemplateProcessing;
using StatsDirect.UI;

internal sealed partial class OperationHost {
    int formNumber;
    static ParameterBag Copy(ParameterBag source) { var result = new ParameterBag(); foreach (var item in source) result[item.Key] = item.Value; return result; }
    bool DefaultConfidence(Parameter p) => p is ConfidenceIntervalParameter ci && ci.CanDefault && Preferences.CanDefaultConfidenceInterval;

    // Respect the engine's ParametersStep boundaries. Preview only changes the
    // form's working values; it never commits inputs, records history or runs a
    // builtin. Conditional controls are evaluated by the original expressions.
    ParameterBag FillForm(ITemplateProcessor processor, ParameterBag context) {
        var parameters = settingsParameters.ToArray(); settingsParameters.Clear();
        string Key(Parameter p) => p.Name ?? "field-" + Array.IndexOf(parameters, p);
        string name = "form-" + (++formNumber), error = null;
        var values = new Dictionary<string, JsonElement>();
        while (true) {
            var working = Copy(context);
            var fields = new List<Dictionary<string, object>>();
            foreach (var p in parameters) {
                if (!Acquire(p, processor, working)) continue;
                var descriptor = HostParameters.Describe(p, processor, working, Preferences, GroupsByIdentifier);
                if (DefaultConfidence(p)) values[Key(p)] = JsonSerializer.SerializeToElement(Preferences.DefaultConfidenceInterval * 100);
                else {
                    descriptor["name"] = Key(p);
                    fields.Add(descriptor);
                    if (!values.ContainsKey(Key(p))) {
                        var json = JsonSerializer.SerializeToElement(descriptor, OperationSessions.Json);
                        if (json.TryGetProperty("initial", out var initial)) values[Key(p)] = initial.Clone();
                        else if (json.TryGetProperty("defaultValue", out var value) && value.ValueKind != JsonValueKind.Null) values[Key(p)] = value.Clone();
                        else if (p is OptionsParameter options) values[Key(p)] = JsonSerializer.SerializeToElement(options.Options.ToDictionary(o => o.Name, o => o.Selected));
                    }
                }
                if (values.TryGetValue(Key(p), out var saved)) {
                    // No host during preview: parsing must not ask questions or
                    // perform data coding. Embedded entry tables are numeric.
                    try { foreach (var pair in HostParameters.Parse(p, saved, processor, working, null)) working[pair.Key] = pair.Value; }
                    catch (ArgumentException) { }
                    catch (InvalidOperationException) { }
                }
            }
            if (fields.Count > 0) {
                var response = job.Ask(new() { ["kind"] = "form", ["name"] = name, ["prompt"] = job.Operation.FriendlyName,
                    ["fields"] = fields, ["values"] = values.ToDictionary(pair => pair.Key, pair => pair.Value), ["error"] = error });
                if (!response.TryGetProperty("values", out var supplied) || supplied.ValueKind != JsonValueKind.Object) { error = "Complete the analysis form."; continue; }
                foreach (var pair in supplied.EnumerateObject()) if (parameters.Any(p => Key(p) == pair.Name)) values[pair.Name] = pair.Value.Clone();
                if (response.TryGetProperty("preview", out var preview) && preview.ValueKind == JsonValueKind.True) { error = null; continue; }
            }
            try {
                var filled = new ParameterBag(); working = Copy(context);
                var accepted = new List<(Parameter parameter, JsonElement input, ParameterBag filled, Dictionary<string, object> descriptor)>();
                foreach (var p in parameters) {
                    if (!Acquire(p, processor, working)) continue;
                    if (DefaultConfidence(p)) values[Key(p)] = JsonSerializer.SerializeToElement(Preferences.DefaultConfidenceInterval * 100);
                    if (!values.TryGetValue(Key(p), out var input)) throw new ArgumentException("Complete " + p.Prompt(processor, working) + ".");
                    var descriptor = HostParameters.Describe(p, processor, working, Preferences, GroupsByIdentifier);
                    var parsed = HostParameters.Parse(p, input, processor, working, this);
                    foreach (var pair in parsed) { filled[pair.Key] = pair.Value; working[pair.Key] = pair.Value; }
                    accepted.Add((p, input, parsed, descriptor));
                }
                // Validate the entire form before committing any field or recording
                // answers. Validators can depend on later controls in this form.
                foreach (var item in accepted) ValidateInput(item.parameter, item.filled, processor, working);
                foreach (var item in accepted) {
                    HostParameters.Commit(item.parameter, item.filled, working);
                    job.Record(item.descriptor["prompt"] as string, HostParameters.Recorded(item.parameter, item.input, item.filled), item.parameter.Name,
                        HostParameters.RecordKind(item.parameter, item.descriptor["kind"] as string), item.descriptor.TryGetValue("mode", out var mode) ? mode as string : null);
                }
                return filled;
            } catch (ArgumentException ex) { error = ex.Message; }
        }
    }
    void ValidateInput(Parameter p, ParameterBag filled, ITemplateProcessor processor, ParameterBag context) {
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
    }
}
