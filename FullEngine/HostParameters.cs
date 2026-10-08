using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text.Json;
using StatsDirect.Data;
using StatsDirect.Numerics;
using StatsDirect.Templates;
using StatsDirect.Utilities;

internal static class HostParameters {
    static object Choice(string value, string label, bool selected = false) => new { value, label, selected };
    internal static Dictionary<string, object> Describe(Parameter p, ITemplateProcessor processor, ParameterBag context, SDPreferences preferences, bool? groupsByIdentifier = null) {
        var d = new Dictionary<string, object> { ["name"] = p.Name, ["title"] = p.Title ?? p.Operation?.ToString() ?? "Analysis options", ["prompt"] = p.Prompt(processor, context, p.Title ?? "Enter a value"), ["rubric"] = p.Rubric(processor, context), ["skip"] = p.CancelSkipsParameter };
        switch (p) {
            case BooleanParameter b: d["kind"] = "boolean"; d["defaultValue"] = b.DefaultValue(processor, context) ?? false; break;
            case ConfidenceIntervalParameter c: d["kind"] = "confidence"; d["defaultValue"] = (c.DefaultValue(processor, context) ?? preferences.DefaultConfidenceInterval) * 100; break;
            case DoubleParameter n: d["kind"] = "number"; d["defaultValue"] = n.DefaultValue(processor, context); d["min"] = n.MinimumValue(processor, context); d["max"] = n.MaximumValue(processor, context); break;
            case IntegerParameter n: d["kind"] = "integer"; d["defaultValue"] = n.DefaultValue(processor, context); d["min"] = n.MinimumValue; d["max"] = n.MaximumValue; break;
            case StringParameter s: d["kind"] = "text"; d["defaultValue"] = s.DefaultValue(processor, context); d["maxLength"] = s.MaxLength; break;
            case DateParameter date: d["kind"]="text";d["defaultValue"]=(date.HasDefaultValue?date.DefaultValue(processor,context):DateTime.Today).ToString("yyyy-MM-dd HH:mm:ss",CultureInfo.InvariantCulture);d["rubric"]="Enter a date as YYYY-MM-DD, optionally followed by HH:MM:SS.";break;
            case OptionParameter o: d["kind"] = "option"; d["options"] = o.Options.Where(x => x.AvailableIf(processor, context)).Select(x => Choice(x.Value, x.Label)).ToArray(); d["defaultValue"] = o.DefaultValue(processor, context); break;
            case OptionsParameter o: d["kind"] = "options"; d["options"] = o.Options.Select(x => Choice(x.Name, x.Label, x.Selected)).ToArray(); break;
            case FrameParameter f:
                Grid(d, f.MinimumColumns(processor, context), f.MaximumColumns(processor, context));
                d["mode"] = f.DataAcquisitionMode.ToString(); d["equalLength"] = f.ColumnsAreSameLength;
                if (f.HasLength) d["length"] = f.Length(processor, context);
                if (f.SameLengthAsParameter != null) foreach (string other in f.SameLengthAsParameter) if (context.ContainsKey(other)) d["length"] = context[other].AsDataFrame.MaxRows;
                // Windows lets these frames come from long data: one data column plus group identifiers
                // (or treatment and block identifiers), pivoted into one variable per group.
                // Only numeric frames pivot (the Windows routine reads the data column as numbers); the layout last
                // used in this analysis, else the saved setting, is the default.
                if (f.ShouldAskForGroupId && f.DataAcquisitionMode is DataAcquisitionMode.NumericReplaceMissing or DataAcquisitionMode.NumericSkipMissing) {
                    d["groupIdentifiers"] = f.GroupIdentifierMode == GroupIdentifierMode.TreatmentAndBlock ? "treatmentAndBlock" : "single";
                    d["groupsByIdentifier"] = groupsByIdentifier ?? preferences.SelectGroupsByIdentifier;
                }
                break;
            case Double2By2Parameter t:
                Grid(d, 2, 2); d["rows"] = 2; d["fixedRows"] = true; d["screen"] = true;
                d["labels"] = new[] { t.LeftColumnPrompt ?? "Column 1", t.RightColumnPrompt ?? "Column 2" };
                d["rowLabels"] = new[] { t.TopRowPrompt ?? "Row 1", t.BottomRowPrompt ?? "Row 2" }; d["rubric"] = t.RowsPrompt + " / " + t.ColumnsPrompt; break;
            case Double2By2ByKParameter: Grid(d, 2, 2); d["rows"] = 4; d["rubric"] = "Enter two rows per stratum: the first 2 × 2 table, then the next. All entries must be non-negative."; break;
            case SpecialParameter s:
                DescribeSpecial(s, d);
                if(s.SpecialType=="1-to-n" && context.ContainsKey(s.Name)) {var values=context[s.Name].AsDataFrame; d["rows"]=values.MaxRows;d["fixedRows"]=true;d["initial"]=FrameInput(values);}
                break;
            case PickVariablesParameter v:
                d["kind"]="selectList";d["multiple"]=v.MaximumVariables>1;d["allowNone"]=v.MinimumVariables==0;
                d["options"]=context[v.ParameterName].AsDataFrame.Variables.Select((item,i)=>Choice(i.ToString(),item.Title)).ToArray();break;
            case EditGridParameter e:
                var old=context[e.Source].AsDataFrame;var keys=old.FindVariable(e.KeyVariable);var vals=old.FindVariable(e.ValueVariable);
                d["kind"]="fields";d["fields"]=Enumerable.Range(0,keys.Length).Select(i=>HostAmendments.Field(i.ToString(),Convert.ToString(keys.DataAsObject(i)),vals.DataAsObject(i),"text")).ToArray();break;
            case PickFromListParameter pick:
                d["kind"] = "selectList"; d["multiple"] = pick.AllowMultiple; d["allowNone"] = pick.IncludeNoneEntry;
                d["options"] = Enumerable.Range(0, context[pick.Source].AsDataFrame.Variables[0].Length).Select(i => Choice(i.ToString(), Convert.ToString(context[pick.Source].AsDataFrame.Variables[0].DataAsObject(i)))).ToArray(); break;
            default: throw new NotSupportedException("The Mac form for " + p.GetType().Name.Replace("Parameter", "") + " is not available yet. The method's help remains available.");
        }
        return d;
    }
    static void Grid(Dictionary<string, object> d, int min, int max) { d["kind"] = "grid"; d["minColumns"] = min; d["maxColumns"] = max; d["rows"] = 12; }
    static void DescribeSpecial(SpecialParameter p, Dictionary<string, object> d) {
        string[] labels = p.SpecialType switch {
            "chi-2-column" => new[] { "Successes", "Failures" }, "chi-3-column" => new[] { "Successes", "Failures", "Score" },
            "likelihood" => new[] { "+Feature", "−Feature" }, "person-time-size" => new[] { "Index events", "Index person-time", "Reference size" },
            "rr-index" => new[] { "Reference rate", "Index person-time" }, "1-to-n" => new[] { "Score" }, "scores" => new[] { "Score" }, "raters-2d" => null,
            _ => throw new NotSupportedException("The Mac form for " + p.SpecialType + " is not available yet.")
        };
        Grid(d, labels?.Length ?? 2, labels?.Length ?? 100); d["screen"] = true; if (labels != null) d["labels"] = labels;
        if (p.SpecialType == "raters-2d") d["rubric"] = "Enter a square contingency table. Each column and row represents a rating category.";
    }
    internal static double Number(JsonElement v) {
        if (v.ValueKind == JsonValueKind.Number && v.TryGetDouble(out double n) && double.IsFinite(n)) return n;
        if (v.ValueKind == JsonValueKind.String && double.TryParse(v.GetString(), NumberStyles.Float, CultureInfo.InvariantCulture, out n) && double.IsFinite(n)) return n;
        throw new ArgumentException("Enter a finite number, using a decimal point if needed.");
    }
    internal static ParameterBag Parse(Parameter p, JsonElement input, ITemplateProcessor processor, ParameterBag context, OperationHost host) {
        if (input.ValueKind == JsonValueKind.Object && input.TryGetProperty("skip", out var skip) && skip.ValueKind == JsonValueKind.True) {
            if (p.CancelSkipsParameter == null) throw new ArgumentException("This value is required.");
            return new ParameterBag();
        }
        var bag = new ParameterBag(); object value;
        switch (p) {
            case BooleanParameter: if (input.ValueKind != JsonValueKind.True && input.ValueKind != JsonValueKind.False) throw new ArgumentException("Select yes or no."); value = input.GetBoolean(); break;
            case ConfidenceIntervalParameter: var confidence = Number(input) / 100; if (confidence <= 0 || confidence >= 1) throw new ArgumentException("Confidence must be greater than 0 and less than 100 percent."); value = confidence; break;
            case DoubleParameter n: var x = Number(input); if (x < n.MinimumValue(processor, context) || x > n.MaximumValue(processor, context)) throw new ArgumentException($"Enter a value from {n.MinimumValue(processor, context)} to {n.MaximumValue(processor, context)}."); value = x; break;
            case IntegerParameter n: x = Number(input); if (x != Math.Truncate(x) || x < n.MinimumValue || x > n.MaximumValue) throw new ArgumentException($"Enter a whole number from {n.MinimumValue} to {n.MaximumValue}."); value = (int)x; break;
            case StringParameter s: var text = input.GetString() ?? ""; if (s.MaxLength > 0 && text.Length > s.MaxLength) throw new ArgumentException("The text is too long."); value = text; break;
            case DateParameter: value=ParseDate(input.GetString());break;
            case OptionParameter o: text = input.GetString(); if (!o.Options.Any(x => x.Value == text && x.AvailableIf(processor, context))) throw new ArgumentException("Choose one of the available options."); value = text; break;
            case OptionsParameter o: foreach (var option in o.Options) bag.AddInput(option.Name, input.TryGetProperty(option.Name, out var flag) && flag.GetBoolean()); return bag;
            case FrameParameter f:
                bool longLayout = IsLongLayout(input);
                var frame = longLayout ? PivotLongFrame(input, f, processor, context, host) : ReadFrame(input, f.DataAcquisitionMode, host);
                var count = longLayout ? frame.VariableCount : input.GetProperty("columns").GetArrayLength();
                // Windows pads pivoted groups of unequal size with missing values once the user accepts.
                if (longLayout && f.ColumnsAreSameLength && frame.MinRows != frame.MaxRows) {
                    if (host != null && host.GetBoolean("Warning: unequal length columns. If you select OK then the jagged ends of columns will be padded with missing data.", "StatsDirect Data Selection", true, out _))
                        foreach (var v in frame.Variables) v.EnsureLengthAndPadWithMissing(frame.MaxRows);
                    else throw new ArgumentException("The groups have different numbers of observations. Choose groups of equal size, or accept padding with missing data.");
                }
                if (count < f.MinimumColumns(processor, context) || count > f.MaximumColumns(processor, context)) throw new ArgumentException($"Choose {f.MinimumColumns(processor, context)} to {f.MaximumColumns(processor, context)} columns.");
                if (f.ColumnsAreSameLength && frame.MinRows != frame.MaxRows) throw new ArgumentException("Columns must have the same number of rows. Use * for missing observations.");
                if (f.HasLength && frame.MaxRows != f.Length(processor, context)) throw new ArgumentException($"Exactly {f.Length(processor, context)} rows are required.");
                if (f.SameLengthAsParameter != null) foreach (var name in f.SameLengthAsParameter) if (context.ContainsKey(name) && frame.MaxRows != context[name].AsDataFrame.MaxRows) throw new ArgumentException($"The data must have {context[name].AsDataFrame.MaxRows} rows, matching the earlier selection.");
                value = frame; break;
            case Double2By2Parameter t:
                var cells = ReadFrame(input, DataAcquisitionMode.NumericReplaceMissing); if (cells.VariableCount != 2 || cells.MinRows != 2 || cells.MaxRows != 2) throw new ArgumentException("Enter all four values in the 2 × 2 table.");
                string[] names = { t.TopLeftName, t.TopRightName, t.BottomLeftName, t.BottomRightName };
                for (int r = 0; r < 2; r++) for (int c = 0; c < 2; c++) { x = ((DoubleVariable)cells.Variables[c]).Data[r]; if (x < 0 || x == Constant.MISSING) throw new ArgumentException("All four values must be non-negative."); bag.AddInput(names[r * 2 + c], x); } return bag;
            case Double2By2ByKParameter:
                frame = ReadFrame(input, DataAcquisitionMode.NumericReplaceMissing);
                if (frame.VariableCount != 2 || frame.MinRows != frame.MaxRows || frame.MaxRows % 2 != 0 || frame.MaxRows < 2 || frame.Variables.Cast<DoubleVariable>().Any(v => v.Data.Any(n => n < 0 || n == Constant.MISSING))) throw new ArgumentException("Enter two complete rows per stratum, with two non-negative values in each row."); value = frame; break;
            case SpecialParameter s:
                frame = ReadFrame(input, DataAcquisitionMode.NumericReplaceMissing);
                var spec = new Dictionary<string, object>(); DescribeSpecial(s, spec); int min = (int)spec["minColumns"], max = (int)spec["maxColumns"];
                if (frame.VariableCount < min || frame.VariableCount > max) throw new ArgumentException($"Enter {min} columns.");
                if (frame.Variables.Cast<DoubleVariable>().Any(v => v.Data.Any(n => n == Constant.MISSING))) throw new ArgumentException("Complete every cell; missing values are not allowed in this table.");
                if (s.SpecialType == "raters-2d" && frame.MaxRows != frame.VariableCount) throw new ArgumentException("The table must have the same number of rows and columns.");
                value = frame; break;
            case PickVariablesParameter v:
                var indices=input.EnumerateArray().Select(x=>x.GetInt32()).ToArray();if(indices.Length<v.MinimumVariables||indices.Length>v.MaximumVariables||indices.Distinct().Count()!=indices.Length||indices.Any(i=>i<0||i>=context[v.ParameterName].AsDataFrame.VariableCount))throw new ArgumentException("Choose the required number of variables.");value=indices;break;
            case EditGridParameter e:
                var old=context[e.Source].AsDataFrame;var keys=old.FindVariable(e.KeyVariable);var replacement=new StringVariable(Enumerable.Range(0,keys.Length).Select(i=>input.GetProperty(i.ToString()).GetString()).ToArray(),e.ValueVariable);
                var edited=new DataFrame();foreach(var v in old.Variables)edited.Variables.Add(v.Title==e.ValueVariable?replacement:v);value=edited;break;
            case PickFromListParameter pick:
                var flags = new bool[context[pick.Source].AsDataFrame.Variables[0].Length]; foreach (var index in input.EnumerateArray()) { int i = index.GetInt32(); if (i < 0 || i >= flags.Length) throw new ArgumentException("Invalid selection."); flags[i] = true; }
                if ((!pick.AllowMultiple && flags.Count(x => x) > 1) || (!pick.IncludeNoneEntry && !flags.Any(x => x))) throw new ArgumentException("Select an item from the list."); value = flags; break;
            default: throw new NotSupportedException("This input form is not available yet.");
        }
        bag.AddInput(p.Name, value); return bag;
    }
    // Append only after validation, so retrying a rejected selection cannot duplicate columns.
    internal static void Commit(Parameter p, ParameterBag filled, ParameterBag context) {
        if (p is FrameParameter f && !string.IsNullOrEmpty(f.AppendToFrame) && filled.ContainsKey(f.Name)) {
            var target = context.ContainsKey(f.AppendToFrame) ? context[f.AppendToFrame].AsDataFrame : new DataFrame();
            foreach (var variable in filled[f.Name].AsDataFrame.Variables) target.Variables.Add(variable); if (!context.ContainsKey(f.AppendToFrame)) filled.AddInput(f.AppendToFrame, target);
        }
    }
    internal static DataFrame ReadFrame(JsonElement input, DataAcquisitionMode mode, OperationHost host = null) {
        if (!input.TryGetProperty("columns", out var cols) || cols.ValueKind != JsonValueKind.Array || cols.GetArrayLength() == 0) throw new ArgumentException("Choose worksheet columns or enter data in the table.");
        var frame = new DataFrame(); frame.Name = input.TryGetProperty("source", out var source) ? source.GetString() : "Entered data";
        if(mode==DataAcquisitionMode.CategoryCombineAllColumns) {
            var parts=cols.EnumerateArray().Select(c=>c.GetProperty("values").EnumerateArray().Select(v=>v.ValueKind==JsonValueKind.Null?"":v.ToString().Trim()).ToArray()).ToArray();
            var values=Enumerable.Range(0,parts.Max(c=>c.Length)).Select(r=>parts.Select(c=>r<c.Length?c[r]:"").ToArray()).Where(row=>row.All(s=>s!=""&&s!="*")).Select(row=>string.Join(", ",row)).ToArray();
            var combinedInput=JsonSerializer.SerializeToElement(new {source=frame.Name,columns=new[]{new {title=string.Join(", ",cols.EnumerateArray().Select(c=>c.GetProperty("title").GetString())),values}}});
            return ReadFrame(combinedInput,DataAcquisitionMode.GroupIdentifiers,host);
        }
        int categoryLength=cols.EnumerateArray().Select(c=>c.GetProperty("values").EnumerateArray().Select((v,r)=> new {v=v.ToString().Trim(),r}).Where(x=>x.v!=""&&x.v!="*").Select(x=>x.r+1).DefaultIfEmpty(0).Max()).Max();
        foreach (var col in cols.EnumerateArray()) {
            string title = col.TryGetProperty("title", out var label) ? label.GetString() : "Column " + (frame.VariableCount + 1);
            var texts = col.GetProperty("values").EnumerateArray().Select(v => v.ValueKind == JsonValueKind.Null ? "" : v.ToString().Trim()).ToArray();
            // Trim only genuinely empty tail cells; '*' deliberately retains a missing final observation.
            int length = texts.Length;
            bool preserveRows = input.TryGetProperty("preserveRows", out var preserve) && preserve.ValueKind == JsonValueKind.True;
            if (!preserveRows) while (length > 0 && texts[length - 1] == "") length--;
            texts = texts.Take(length).ToArray();
            bool missing(string s) => s == "" || s == "*";
            bool numeric(string s) => missing(s) || double.TryParse(s, NumberStyles.Float, CultureInfo.InvariantCulture, out double n) && double.IsFinite(n);
            bool coded = mode == DataAcquisitionMode.NumericCodingTextToCategories || mode == DataAcquisitionMode.NumericCodingTextToDummies;
            if (mode == DataAcquisitionMode.DateReplaceMissing) {frame.Variables.Add(new DateVariable(texts.Select(s=>missing(s)?DateTime.MinValue:ParseDate(s)).ToArray(),title));continue;}
            if (mode == DataAcquisitionMode.Text || mode == DataAcquisitionMode.TextWithFormulae || mode == DataAcquisitionMode.TextNoTitles) { frame.Variables.Add(new StringVariable(texts, title)); continue; }
            if (mode == DataAcquisitionMode.CategoryReplaceMissing || mode == DataAcquisitionMode.CategoryCombineAllColumns || mode == DataAcquisitionMode.GroupIdentifiers || coded && texts.Any(s => !numeric(s))) {
                if(mode==DataAcquisitionMode.CategoryReplaceMissing) {texts=Enumerable.Range(0,categoryLength).Select(r=>r>=texts.Length||missing(texts[r])?Formatting.MISSINGLABEL:texts[r]).ToArray();length=texts.Length;}
                if(mode==DataAcquisitionMode.GroupIdentifiers) {texts=texts.Where(s=>!missing(s)).ToArray();length=texts.Length;}
                var groups = new Dictionary<string, Group>();
                var cv = new ClassifierVariable { Title = title, Data = Enumerable.Repeat(Constant.MISSING, length).ToArray() };
                for (int r = 0; r < length; r++) {
                    string text = texts[r]; if (missing(text)) continue;
                    if (!groups.TryGetValue(text, out var group)) { group = new Group(text, groups.Count); groups.Add(text, group); }
                    group.NBin++; cv.Data[r] = text.Contains(Formatting.MISSINGLABEL) ? Constant.MISSING : group.Id;
                }
                cv.Groups = groups.Values.ToList();
                if (mode == DataAcquisitionMode.NumericCodingTextToDummies) {
                    var dummy = StatsDirect.Builtins.Sheet.ToDummyVariables(host, cv, true);
                    if (dummy == null) frame.Variables.Add(cv); else foreach (var v in dummy.Variables) frame.Variables.Add(v);
                } else frame.Variables.Add(cv);
                continue;
            }
            double[] data = texts.Select((s, r) => missing(s) ? Constant.MISSING : double.TryParse(s, NumberStyles.Float, CultureInfo.InvariantCulture, out double n) && double.IsFinite(n) ? n : throw new ArgumentException($"{title}, row {r + 1}: ‘{s}’ is not numeric. Correct it or use * for a missing value.")).ToArray();
            if (mode == DataAcquisitionMode.NumericSkipMissing) data = data.Where(n => n != Constant.MISSING).ToArray();
            if(mode==DataAcquisitionMode.NumericCodingTextToDummies && data.All(n=>n>=int.MinValue && n<=int.MaxValue && n==Math.Truncate(n))) {
                var categories=data.Distinct().ToArray();
                if(categories.Length>2 && categories.Length<Math.Min(data.Length,12)) {
                    var classifier=new ClassifierVariable {Title=title,Data=data.Select(n=>(double)Array.IndexOf(categories,n)).ToArray(),Groups=categories.Select((n,i)=>new Group(n.ToString(CultureInfo.InvariantCulture),i){NBin=data.Count(v=>v==n)}).ToList()};
                    var dummy=StatsDirect.Builtins.Sheet.ToDummyVariables(host,classifier,true);
                    if(dummy!=null){foreach(var v in dummy.Variables)frame.Variables.Add(v);continue;}
                }
            }
            frame.Variables.Add(new DoubleVariable(data, title));
        }
        if (frame.MaxRows == 0) throw new ArgumentException("Enter at least one observation.");
        return frame;
    }
    internal static bool IsLongLayout(JsonElement input) => input.ValueKind == JsonValueKind.Object && input.TryGetProperty("layout", out var layout) && layout.ValueKind == JsonValueKind.String && layout.GetString() == "long";
    // What the history records for a frame: the pivoted variables for long data, so the report's
    // inputs, the R script and an instant rerun see exactly what the engine analysed.
    internal static object Recorded(Parameter p, JsonElement input, ParameterBag filled) {
        if (!(p is FrameParameter) || !IsLongLayout(input) || !filled.ContainsKey(p.Name)) return input;
        // The pivoted variables, with the answer's provenance (source, rows, which columns identified the groups).
        var record = new Dictionary<string, object>();
        foreach (var property in input.EnumerateObject()) if (property.Name is "source" or "range" or "preserveRows" or "layout" or "roles") record[property.Name] = property.Value.Clone();
        record["identifiers"] = IdentifierColumns(input, "groupIdentifiers").Select(c => c.title).ToArray();
        var blocks = IdentifierColumns(input, "blockIdentifiers"); if (blocks.Length > 0) record["blocks"] = blocks.Select(c => c.title).ToArray();
        record["columns"] = ((dynamic)FrameInput(filled[p.Name].AsDataFrame)).columns;
        return record;
    }
    // Groups by identifier, as the Windows shell's Gidx1 (one identifier) and Gidx2 (treatment and
    // block identifiers) build them: groups in order of first appearance, labelled by the identifier
    // text (several identifier columns joined with ", "), one variable per group titled
    // data_identifiers_label, missing data kept unless the frame skips missing values.
    internal static DataFrame PivotLongFrame(JsonElement input, FrameParameter f, ITemplateProcessor processor, ParameterBag context, OperationHost host) {
        if (!f.ShouldAskForGroupId || !(f.DataAcquisitionMode is DataAcquisitionMode.NumericReplaceMissing or DataAcquisitionMode.NumericSkipMissing)) throw new ArgumentException("This step takes each group in its own column.");
        int min = f.MinimumColumns(processor, context), max = f.MaximumColumns(processor, context);
        if (!input.TryGetProperty("columns", out var columns) || columns.ValueKind != JsonValueKind.Array || columns.GetArrayLength() != 1) throw new ArgumentException("Choose one data column for groups by identifier.");
        string source = input.TryGetProperty("source", out var s) && s.ValueKind == JsonValueKind.String ? s.GetString() : "Worksheet";
        var dataFrame = ReadFrame(JsonSerializer.SerializeToElement(new { source, preserveRows = true, columns = new[] { columns[0] } }), DataAcquisitionMode.NumericReplaceMissing, host);
        var dataVariable = (DoubleVariable)dataFrame.Variables[0];
        var identifiers = IdentifierColumns(input, "groupIdentifiers");
        bool twoWay = f.GroupIdentifierMode == GroupIdentifierMode.TreatmentAndBlock;
        if (identifiers.Length == 0) throw new ArgumentException(twoWay ? "Choose a treatment (column) identifier column." : "Choose at least one group identifier column.");
        if (identifiers.Length > (twoWay ? 1 : 20)) throw new ArgumentException(twoWay ? "Choose one treatment identifier column." : "Choose up to 20 group identifier columns.");
        int rows = Math.Max(dataVariable.Length, identifiers.Max(c => c.values.Length));
        string groupTitle = string.Join(", ", identifiers.Select(c => c.title));
        var groupIds = Classify(identifiers, rows, dataVariable, "group", out var groups);
        if (!twoWay) {
            if (groups.Count < min || groups.Count > max) throw new ArgumentException(CountMessage(min, max, groups.Count));
            bool skipMissing = f.DataAcquisitionMode == DataAcquisitionMode.NumericSkipMissing;
            var output = new DataFrame { Name = dataFrame.Name };
            for (int i = 0; i < groups.Count; i++) {
                var values = new List<double>();
                for (int j = 0; j < rows; j++) {
                    if (groupIds[j] != i) continue;
                    double x = j < dataVariable.Length ? dataVariable.Data[j] : Constant.MISSING;
                    if (skipMissing && x == Constant.MISSING) continue;
                    values.Add(x);
                }
                if (values.Count == 0) throw new ArgumentException($"Group '{groups[i]}' has no numeric observations.");
                output.Variables.Add(new DoubleVariable(values.ToArray(), groups.Count > 1 ? dataVariable.Title + "_" + groupTitle + "_" + groups[i] : dataVariable.Title));
            }
            return output;
        }
        var blocks = IdentifierColumns(input, "blockIdentifiers");
        if (blocks.Length != 1) throw new ArgumentException("Choose one block (row) identifier column.");
        if (groups.Count < min || groups.Count > max) throw new ArgumentException(CountMessage(min, max, groups.Count));
        var sizes = new int[groups.Count]; for (int j = 0; j < rows; j++) if (groupIds[j] >= 0) sizes[groupIds[j]]++;
        if (sizes.Any(n => n != sizes[0])) throw new ArgumentException("All groups must be the same size: each treatment needs one observation in every block.");
        var blockIds = Classify(blocks, rows, dataVariable, "block", out var blockLabels);
        var blockSizes = new int[blockLabels.Count]; for (int j = 0; j < rows; j++) if (blockIds[j] >= 0) blockSizes[blockIds[j]]++;
        int blockMax = blockSizes.DefaultIfEmpty(0).Max();
        if (blockMax > groups.Count) throw new ArgumentException($"Two way ANOVA requires only one observation per block - you entered {(blockMax / (double)groups.Count).ToString(CultureInfo.InvariantCulture)}. Please use a repeated/replicate measures method for repeated observations.");
        int perTreatment = sizes.DefaultIfEmpty(0).Max();
        if (blockLabels.Count > perTreatment) throw new ArgumentException("Each block must have one observation for every treatment.");
        var result = new DataFrame { Name = dataFrame.Name };
        for (int i = 0; i < groups.Count; i++) {
            var data = Enumerable.Repeat(Constant.MISSING, perTreatment).ToArray();
            for (int j = 0; j < rows; j++) {
                if (groupIds[j] != i) continue;
                if (blockIds[j] < 0) throw new ArgumentException($"Row {j + 1} has no block identifier.");
                data[blockIds[j]] = j < dataVariable.Length ? dataVariable.Data[j] : Constant.MISSING;
            }
            result.Variables.Add(new DoubleVariable(data, groups.Count > 1 ? dataVariable.Title + "_" + groupTitle + "_" + groups[i] : dataVariable.Title));
        }
        return result;
    }
    static (string title, string[] values)[] IdentifierColumns(JsonElement input, string name) {
        if (!input.TryGetProperty(name, out var list) || list.ValueKind != JsonValueKind.Array) return Array.Empty<(string, string[])>();
        return list.EnumerateArray().Select((c, i) => (
            c.TryGetProperty("title", out var t) && t.ValueKind == JsonValueKind.String ? t.GetString() : "Column " + (i + 1),
            c.TryGetProperty("values", out var v) && v.ValueKind == JsonValueKind.Array ? v.EnumerateArray().Select(x => x.ValueKind == JsonValueKind.Null ? "" : x.ToString().Trim()).ToArray() : Array.Empty<string>())).ToArray();
    }
    // Group index per row (-1 where the row has no identifier), labels in order of first appearance.
    static int[] Classify((string title, string[] values)[] identifiers, int rows, DoubleVariable data, string what, out List<string> labels) {
        var ids = new int[rows]; var index = new Dictionary<string, int>(); labels = new List<string>();
        for (int r = 0; r < rows; r++) {
            var parts = identifiers.Select(c => r < c.values.Length ? c.values[r] : "").ToArray();
            bool blank = parts.Any(t => t == "" || t == "*");
            bool hasData = r < data.Length && data.Data[r] != Constant.MISSING;
            if (blank) {
                if (hasData) throw new ArgumentException($"Row {r + 1} has a value but no {what} identifier. Give every data row an identifier or leave the cell blank.");
                ids[r] = -1; continue;
            }
            string label = string.Join(", ", parts);
            if (!index.TryGetValue(label, out int id)) { id = labels.Count; index[label] = id; labels.Add(label); }
            ids[r] = id;
        }
        return ids;
    }
    static string CountMessage(int min, int max, int count) =>
        min == max ? $"The identifiers define {count} group{(count == 1 ? "" : "s")}; this method needs exactly {min}."
        : count < min ? $"The identifiers define {count} group{(count == 1 ? "" : "s")}; this method needs at least {min}."
        : $"The identifiers define {count} groups; this method takes at most {max}.";
    // A missing number is written as "*", as the forms and the R script generator expect.
    internal static object FrameInput(DataFrame frame) => new {columns=frame.Variables.Select(v=>new {title=v.Title,values=Enumerable.Range(0,v.Length).Select(r=>{var x=v.DataAsObject(r);return x is double d&&(d==Constant.MISSING||!double.IsFinite(d))?"*":x;}).ToArray()}).ToArray()};
    static DateTime ParseDate(string text) {
        if(DateTime.TryParseExact(text,new[]{"yyyy-MM-dd","yyyy-MM-dd HH:mm:ss","yyyy-MM-ddTHH:mm:ss","yyyy-MM-ddTHH:mm:ss.FFFFFFF"},CultureInfo.InvariantCulture,DateTimeStyles.None,out var date))return date;
        throw new ArgumentException("Enter the date as YYYY-MM-DD, optionally followed by HH:MM:SS.");
    }
    internal static object ScalarOutputs(ParameterBag bag) => bag.Where(p => p.Value != null && p.Value.Direction == FilledParameterDirection.Output && (p.Value.AsObject is string || p.Value.AsObject is bool || p.Value.AsObject is int || p.Value.AsObject is double d && double.IsFinite(d))).ToDictionary(p => p.Key, p => p.Value.AsObject);
    internal static object FrameOutput(DataFrame frame, bool formulae) {
        var cells = new List<object>();
        for (int c = 0; c < frame.VariableCount; c++) {
            var v = frame.Variables[c]; cells.Add(new { col = c, row = 0, text = v.Title ?? "Column " + (c + 1), kind = "text" });
            for (int r = 0; r < v.Length; r++) { object o = v.DataAsObject(r); if (o == null || o is double missing && (missing == Constant.MISSING || !double.IsFinite(missing))) continue; cells.Add(new { col = c, row = r + 1, text = Convert.ToString(o, CultureInfo.InvariantCulture), kind = o is double || o is int ? "number" : "text" }); }
        }
        return new { name = frame.Name ?? "Analysis data", rows = frame.MaxRows + 1, columns = frame.VariableCount, cells, headerRow = true, hidden = false };
    }
}
