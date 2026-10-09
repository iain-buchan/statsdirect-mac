using System;
using System.Linq;
using System.Text.Json;
using System.Collections.Generic;
using StatsDirect.Builtins;
using StatsDirect.Data;
using StatsDirect.Numerics;
using StatsDirect.Templates;
using StatsDirect.Utilities;

// Host-side data arrangement mirrors GridSelectionProcessor; all statistical work stays in Builtins.
internal static class HostComplexData {
    internal static DataFrame AskFrame(OperationJob job, string title, int min, int max, bool equal = false, int length = 0) {
        string error = null;
        while (true) {
            var input = job.Ask(new() { ["kind"]="grid",["title"]=title,["prompt"]=title,["minColumns"]=min,["maxColumns"]=max,["rows"]=Math.Max(12,length),["length"]=length,["equalLength"]=equal,["error"]=error });
            try {
                var frame = HostParameters.ReadFrame(input, DataAcquisitionMode.NumericReplaceMissing);
                if (frame.VariableCount < min || frame.VariableCount > max) throw new ArgumentException($"Select {min} to {max} columns.");
                if (equal && frame.MinRows != frame.MaxRows) throw new ArgumentException("All columns must have equal length. Use * for missing observations.");
                if (length > 0 && (frame.MinRows != length || frame.MaxRows != length)) throw new ArgumentException($"Each column must have {length} rows.");
                job.Record(title,input); return frame;
            } catch (ArgumentException ex) { error = ex.Message; }
        }
    }
    internal static DataFrame2D Frame2D(OperationJob job, Frame2DParameter p, ITemplateProcessor processor, ParameterBag context, OperationHost host) {
        bool repeats = p.DataAcquisitionMode == DataAcquisitionMode2D.BlockThenGroup;
        // The Windows selection panel offers groups by column or by identifier for these frames too
        // (FillFrameParameter2D routes through Gidx3 when the setting is on). One choice replaces the radios.
        bool byIdentifier = host.GroupsByIdentifier ?? host.Preferences.SelectGroupsByIdentifier;
        string layoutError = null;
        while (true) {
            var choice = job.Ask(new() { ["kind"]="option", ["name"]="layout2d", ["title"]=p.Operation?.ToString() ?? "Data layout", ["prompt"]="How are the groups laid out in the worksheet?",
                ["options"]=new object[] {
                    new { value="columns", label=repeats ? "Each repeat's treatments in separate columns" : "Each group's sub-groups in separate columns", selected=!byIdentifier },
                    new { value="identifiers", label=repeats ? "One data column with treatment and block (subject) identifier columns" : "One data column with group and sub-group identifier columns", selected=byIdentifier } },
                ["defaultValue"]=byIdentifier ? "identifiers" : "columns", ["error"]=layoutError });
            string layout = choice.ValueKind == JsonValueKind.String ? choice.GetString() : null;
            if (layout is not ("columns" or "identifiers")) { layoutError = "Choose one of the available options."; continue; }
            if (layout == "identifiers") {
                var frame = Frame2DFromIdentifiers(job, p, processor, context);
                if (frame != null) { job.Record("How are the groups laid out in the worksheet?", layout, "layout2d", "option"); host.GroupsByIdentifier = true; return frame; }
                // The form could only send columns (entered data or a lesson's data): offer the layout choice again.
                byIdentifier = false; layoutError = "This data cannot be read by identifier: entered data and lesson data stay in separate columns. Choose separate columns, or open a worksheet and refresh.";
                continue;
            }
            job.Record("How are the groups laid out in the worksheet?", layout, "layout2d", "option"); host.GroupsByIdentifier = false;
            break;
        }
        string title = repeats ? "Number of repeats" : "Number of groups";
        var number = HostAmendments.Form(job, title, new[]{HostAmendments.Field("n",title,2,"integer",2,100)}, v=>{double n=HostParameters.Number(v.GetProperty("n"));if(n<2||n>100||n!=Math.Truncate(n))throw new ArgumentException("Enter a whole number from 2 to 100.");});
        int count = (int)HostParameters.Number(number.GetProperty("n")); var frames = new List<DataFrame>();
        for(int i=0;i<count;i++) frames.Add(AskFrame(job,repeats?$"Repeat {i+1}: subjects in rows, treatments in columns":$"Group {i+1}: one column per subgroup",p.MinimumColumns(processor,context),p.MaximumColumns(processor,context),p.ColumnsAreSameLength,repeats&&i>0?frames[0].MaxRows:0));
        var result = new DataFrame2D(); result.Name=string.Join("; ",frames.Select(f=>f.Name));
        if(repeats) {
            int rows=frames[0].MaxRows,cols=frames[0].VariableCount;
            if(frames.Any(f=>f.VariableCount!=cols))throw new ArgumentException("Every repeat must have the same treatments.");
            result.EnsureVariablesSquare(rows,cols);
            for(int r=0;r<rows;r++)for(int c=0;c<cols;c++)result.Variables[r][c]=new DoubleVariable(frames.Select(f=>((DoubleVariable)f.Variables[c]).Data[r]).ToArray(),frames[0].Variables[c].Title);
        } else {
            for(int g=0;g<count;g++){result.EnsureVariablesJagged(g+1,frames[g].VariableCount);for(int c=0;c<frames[g].VariableCount;c++)result.Variables[g][c]=frames[g].Variables[c];}
            if(p.ShouldSquare)foreach(var group in result.Variables)foreach(var v in group) v?.EnsureLengthAndPadWithMissing(result.MaxRows);
        }
        return result;
    }
    // Long data for a two-dimensional frame, as the Windows shell's Gidx3: a group identifier column
    // (treatment, for repeated measures), a sub-group identifier column (block or subject) and a data
    // column. Groups and sub-groups keep the order of first appearance and label the variables as
    // "group_label (sub-group_label)". GroupThenBlock gives a jagged frame of repeated values per cell;
    // BlockThenGroup gives a square frame indexed [sub-group][group] with values in repeat order,
    // padded with missing to the largest cell.
    static DataFrame2D Frame2DFromIdentifiers(OperationJob job, Frame2DParameter p, ITemplateProcessor processor, ParameterBag context) {
        bool repeats = p.DataAcquisitionMode == DataAcquisitionMode2D.BlockThenGroup;
        int min = p.MinimumColumns(processor, context), max = p.MaximumColumns(processor, context);
        // The Windows prompts name the roles; the form shows them as nouns beside the data column.
        static string Noun(string prompt) {
            var text = System.Text.RegularExpressions.Regex.Replace(prompt.Trim(), @"^select\s+", "", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
            if (text.Length > 0 && text == text.ToUpperInvariant()) text = text.ToLowerInvariant();
            return text.Length > 0 ? char.ToUpperInvariant(text[0]) + text.Substring(1) : text;
        }
        string groupPrompt = repeats ? "Treatment (column) identifier" : "Group identifier";
        string sub = p.SubPrompt(processor, context); string subPrompt = string.IsNullOrWhiteSpace(sub) ? "Sub-group identifier" : Noun(sub);
        string title = repeats ? "Select the data, treatment and block (subject) identifier columns" : "Select the data, group and sub-group identifier columns";
        string error = null;
        while (true) {
            var input = job.Ask(new() { ["kind"]="grid", ["name"]=p.Name, ["title"]=title, ["prompt"]=title, ["minColumns"]=min, ["maxColumns"]=max, ["rows"]=12, ["mode"]="NumericReplaceMissing",
                ["groupIdentifiers"]="groupAndSubgroup", ["groupsByIdentifier"]=true, ["layout"]="long",
                ["identifierLabels"]=new { first=groupPrompt, second=subPrompt }, ["error"]=error });
            try {
                if (!HostParameters.IsLongLayout(input)) return null;   // the form had only separate columns to offer
                if (!input.TryGetProperty("columns", out var columns) || columns.ValueKind != JsonValueKind.Array || columns.GetArrayLength() != 1) throw new ArgumentException("Choose one data column.");
                string source = input.TryGetProperty("source", out var s) && s.ValueKind == JsonValueKind.String ? s.GetString() : "Worksheet";
                var dataFrame = HostParameters.ReadFrame(JsonSerializer.SerializeToElement(new { source, preserveRows = true, columns = new[] { columns[0] } }), DataAcquisitionMode.NumericReplaceMissing);
                var data = (DoubleVariable)dataFrame.Variables[0];
                var groups = HostParameters.IdentifierColumns(input, "groupIdentifiers"); var subgroups = HostParameters.IdentifierColumns(input, "blockIdentifiers");
                if (groups.Length != 1) throw new ArgumentException(repeats ? "Choose one treatment identifier column." : "Choose one group identifier column.");
                if (subgroups.Length != 1) throw new ArgumentException(repeats ? "Choose one block (subject) identifier column." : "Choose one sub-group identifier column.");
                int rows = Math.Max(data.Length, Math.Max(groups[0].values.Length, subgroups[0].values.Length));
                var gid = HostParameters.Classify(groups, rows, data, repeats ? "treatment" : "group", out var gcat);
                if (gcat.Count < min || gcat.Count > max) throw new ArgumentException(HostParameters.CountMessage(min, max, gcat.Count));
                var sgid = HostParameters.Classify(subgroups, rows, data, repeats ? "block" : "sub-group", out var sgcat);
                var sizes = new int[gcat.Count]; var subSizes = new int[sgcat.Count];
                for (int j = 0; j < rows; j++) { if (gid[j] >= 0) sizes[gid[j]]++; if (sgid[j] >= 0) subSizes[sgid[j]]++; }
                int maxgn = sizes.DefaultIfEmpty(0).Max(), maxsgn = subSizes.DefaultIfEmpty(0).Max();
                string gTitle = groups[0].title, sTitle = subgroups[0].title;
                double at(int j) => j < data.Length ? data.Data[j] : Constant.MISSING;
                var result = new DataFrame2D();
                if (!repeats) {
                    for (int g = 0; g < gcat.Count; g++) for (int sg = 0; sg < sgcat.Count; sg++) {
                        var values = new List<double>();
                        for (int j = 0; j < rows; j++) if (gid[j] == g && sgid[j] == sg) values.Add(at(j));
                        if (values.Count == 0) continue;   // jagged sources end without every sub-group
                        // Subgroups are nested within their parent, not crossed with every group.
                        // Global label indices leave null holes when parents have distinct labels;
                        // the core correctly counts those holes as an invalid subgroup layout.
                        int localSub = g < result.Variables.Count ? result.Variables[g].Count : 0;
                        result.EnsureVariablesJagged(g + 1, localSub + 1);
                        result.Variables[g][localSub] = new DoubleVariable(values.ToArray(), gTitle + "_" + gcat[g] + " (" + sTitle + "_" + sgcat[sg] + ")");
                    }
                } else {
                    result.EnsureVariablesSquare(sgcat.Count, gcat.Count);
                    int highest = 0;
                    for (int g = 0; g < gcat.Count; g++) for (int sg = 0; sg < sgcat.Count; sg++) {
                        int cnt = 0;
                        for (int j = 0; j < rows; j++) {
                            if (gid[j] != g || sgid[j] != sg) continue;
                            if (result.Variables[sg][g] == null) result.Variables[sg][g] = new DoubleVariable(Enumerable.Repeat(Constant.MISSING, maxsgn).ToArray(), gTitle + "_" + gcat[g] + " (" + sTitle + "_" + sgcat[sg] + ")");
                            ((DoubleVariable)result.Variables[sg][g]).Data[cnt++] = at(j);
                        }
                        highest = Math.Max(highest, cnt);
                    }
                    for (int g = 0; g < gcat.Count; g++) for (int sg = 0; sg < sgcat.Count; sg++) result.Variables[sg][g]?.TruncateDataToLength(highest);   // a combination with no rows stays null, for the analysis to refuse
                    result.Name = " " + data.Title + " (data), " + gTitle + " (group), " + sTitle + " (sub-group)";
                }
                // Recorded as a frame of the three columns, so the report's inputs and the R script hold the data, group and sub-group together.
                var record = new Dictionary<string, object>();
                foreach (var property in input.EnumerateObject()) if (property.Name is "source" or "range" or "preserveRows" or "layout" or "roles") record[property.Name] = property.Value.Clone();
                record["identifiers"] = new[] { gTitle }; record["blocks"] = new[] { sTitle };
                record["columns"] = new object[] { new { title = data.Title, values = Enumerable.Range(0, data.Length).Select(r => data.Data[r] == Constant.MISSING ? (object)"*" : data.Data[r]).ToArray() },
                    new { title = gTitle, mode = "GroupIdentifiers", values = (object)groups[0].values }, new { title = sTitle, mode = "GroupIdentifiers", values = (object)subgroups[0].values } };
                job.Record(title, record, p.Name, "grid", "NumericReplaceMissing"); return result;
            } catch (ArgumentException ex) { error = ex.Message; }
        }
    }
    // The Windows selection panel offers groups by column or by identifier for the analysis of covariance too
    // (FillGroupedCovarianceParameter routes through Gidxyr when the setting is on). One choice replaces the radios.
    internal static GroupedCovarianceData GroupedCovariance(OperationJob job, OperationHost host) {
        const string question = "How are the groups laid out in the worksheet?";
        bool byIdentifier = host.GroupsByIdentifier ?? host.Preferences.SelectGroupsByIdentifier;
        string layoutError = null;
        while (true) {
            var choice = job.Ask(new() { ["kind"]="option", ["name"]="layoutCovariance", ["title"]="Analysis of covariance", ["prompt"]=question,
                ["options"]=new object[] {
                    new { value="columns", label="Each group's predictor (X) series in its own column, then its outcomes (Y)", selected=!byIdentifier },
                    new { value="identifiers", label="One X column and Y column(s) with group identifier columns", selected=byIdentifier } },
                ["defaultValue"]=byIdentifier ? "identifiers" : "columns", ["error"]=layoutError });
            string layout = choice.ValueKind == JsonValueKind.String ? choice.GetString() : null;
            if (layout is not ("columns" or "identifiers")) { layoutError = "Choose one of the available options."; continue; }
            if (layout == "identifiers") {
                var pivoted = GroupedCovarianceFromIdentifiers(job);
                if (pivoted != null) { job.Record(question, layout, "layoutCovariance", "option"); host.GroupsByIdentifier = true; pivoted.GAMMA = Confidence(job, host); return pivoted; }
                // The form could only send columns (entered data or a lesson's data): offer the layout choice again.
                byIdentifier = false; layoutError = "This data cannot be read by identifier: entered data and lesson data stay in separate columns. Choose separate columns, or open a worksheet and refresh.";
                continue;
            }
            job.Record(question, layout, "layoutCovariance", "option"); host.GroupsByIdentifier = false;
            break;
        }
        var predictors=AskFrame(job,"Select predictor (X) series — one column per group",2,200);
        // The Windows grouped-covariance form removes missing observations within each selected series.
        foreach(DoubleVariable v in predictors.Variables)v.Data=v.Data.Where(n=>n!=Constant.MISSING).ToArray();
        int k=predictors.VariableCount,maxr=predictors.MaxRows;
        bool replicate=host.GetBoolean("Use Y replicates", "Grouped linear covariance",false,out _);
        var outcomes=new List<DataFrame>();int maxreps=1;
        for(int g=0;g<k;g++){
            int n=predictors.Variables[g].Length;
            var frame=AskFrame(job,replicate?$"Group {g+1}: one column of Y replicates for each X value":$"Group {g+1}: Y outcomes for {predictors.Variables[g].Title}",replicate?n:1,replicate?n:1,!replicate,replicate?0:n);
            foreach(DoubleVariable v in frame.Variables)v.Data=v.Data.Where(n=>n!=Constant.MISSING).ToArray();
            if(!replicate&&frame.MaxRows!=n)throw new ArgumentException("Missing Y observations do not match the X series. Supply complete paired observations.");
            outcomes.Add(frame);if(replicate)maxreps=Math.Max(maxreps,frame.MaxRows);
        }
        var data=new GroupedCovarianceData {k=k,maxr=maxr,maxreps=maxreps,GAMMA=Confidence(job,host),
            a=new double[k+1],b=new double[k+1],bnam=new string[k+1],cx=new ColumnData[k+1],nxi=new int[k+1],ny=new int[k+1,maxr+1],rssx=new double[k+1],xmean=new double[k+1],ymean=new double[k+1],xt=new double[k+1,maxr+1],y=new double[k+1,maxr+1,maxreps+1],
            xlab=string.Join(" ",predictors.Variables.Select(v=>v.Title)),minMax=new MinMax {MinX=double.MaxValue,MaxX=double.MinValue,MinY=double.MaxValue,MaxY=double.MinValue}};
        for(int g=1;g<=k;g++){
            var x=(DoubleVariable)predictors.Variables[g-1];data.cx[g]=new ColumnData {Title=x.Title,Rows=x.Length,Sum=x.Sum};data.nxi[g]=x.Length;
            for(int r=1;r<=x.Length;r++){
                data.xt[g,r]=x.Data[r-1];data.minMax.MinX=Math.Min(data.minMax.MinX,x.Data[r-1]);data.minMax.MaxX=Math.Max(data.minMax.MaxX,x.Data[r-1]);
                var values=replicate?((DoubleVariable)outcomes[g-1].Variables[r-1]).Data:new[]{((DoubleVariable)outcomes[g-1].Variables[0]).Data[r-1]};data.ny[g,r]=values.Length;
                for(int n=0;n<values.Length;n++){data.y[g,r,n+1]=values[n];data.minMax.MinY=Math.Min(data.minMax.MinY,values[n]);data.minMax.MaxY=Math.Max(data.minMax.MaxY,values[n]);}
            }
        }
        return data;
    }
    static double Confidence(OperationJob job, OperationHost host) {
        if (host.Preferences.CanDefaultConfidenceInterval) {
            double confidence = host.Preferences.DefaultConfidenceInterval;
            job.Record("Confidence level", new { ci = confidence * 100 });
            return confidence;
        }
        var ci=HostAmendments.Form(job,"Confidence level",new[]{HostAmendments.Field("ci","Confidence level (%)",host.Preferences.DefaultConfidenceInterval*100)},v=>{var ci=HostParameters.Number(v.GetProperty("ci"));if(ci<=0||ci>=100)throw new ArgumentException("Confidence must be greater than 0 and less than 100%.");});
        return HostParameters.Number(ci.GetProperty("ci"))/100;
    }
    // Long data for the analysis of covariance, as the Windows shell's Gidxyr: group (series) identifier
    // column(s), one predictor (X) column and one or more outcome (Y) columns, all over the same rows.
    // Groups keep the order of first appearance and are titled identifiers_label; x[g, i] and y[g, i, k]
    // hold the group's rows in worksheet order. A value beside a blank identifier is refused by row, each
    // Y column in turn and then X, as Windows does. Windows keeps missing values in the arrays, where the
    // covariance sums them as numbers; here a row whose X is missing is left out of its group and a missing
    // Y replicate out of its X level, as the separate-column path removes missing observations within a series
    // (Windows adopted the same placement on 9 October 2026 after this port reported that it summed missing values).
    static GroupedCovarianceData GroupedCovarianceFromIdentifiers(OperationJob job) {
        const string title = "Select the predictor (X) column, the outcome (Y) column(s) and the group identifier column(s)";
        string error = null;
        while (true) {
            var input = job.Ask(new() { ["kind"]="grid", ["name"]="gcd", ["title"]=title, ["prompt"]=title, ["minColumns"]=2, ["maxColumns"]=200, ["rows"]=12, ["mode"]="NumericReplaceMissing",
                ["groupIdentifiers"]="covariance", ["groupsByIdentifier"]=true, ["layout"]="long",
                ["identifierLabels"]=new { first="Group (series) identifier column(s)", outcomes="Outcome (Y) column(s)" }, ["error"]=error });
            try {
                if (!HostParameters.IsLongLayout(input)) return null;   // the form had only separate columns to offer
                if (!input.TryGetProperty("columns", out var columns) || columns.ValueKind != JsonValueKind.Array || columns.GetArrayLength() != 1) throw new ArgumentException("Choose one predictor (X) column.");
                if (!input.TryGetProperty("outcomeColumns", out var outcomes) || outcomes.ValueKind != JsonValueKind.Array || outcomes.GetArrayLength() < 1) throw new ArgumentException("Choose at least one outcome (Y) column.");
                if (outcomes.GetArrayLength() > 200) throw new ArgumentException("Choose up to 200 outcome (Y) columns.");
                var groups = HostParameters.IdentifierColumns(input, "groupIdentifiers");
                if (groups.Length == 0) throw new ArgumentException("Choose at least one group identifier column.");
                if (groups.Length > 10) throw new ArgumentException("Choose up to 10 group identifier columns.");
                string source = input.TryGetProperty("source", out var s) && s.ValueKind == JsonValueKind.String ? s.GetString() : "Worksheet";
                var x = (DoubleVariable)HostParameters.ReadFrame(JsonSerializer.SerializeToElement(new { source, preserveRows = true, columns = new[] { columns[0] } }), DataAcquisitionMode.NumericReplaceMissing).Variables[0];
                var ys = HostParameters.ReadFrame(JsonSerializer.SerializeToElement(new { source, preserveRows = true, columns = outcomes }), DataAcquisitionMode.NumericReplaceMissing).Variables.Cast<DoubleVariable>().ToArray();
                int rows = Math.Max(Math.Max(x.Length, ys.Max(v => v.Length)), groups.Max(c => c.values.Length));
                foreach (var y in ys) HostParameters.Classify(groups, rows, y, "group", out _, "Y");
                var gid = HostParameters.Classify(groups, rows, x, "group", out var gcat, "X");
                if (gcat.Count < 2 || gcat.Count > 200) throw new ArgumentException(HostParameters.CountMessage(2, 200, gcat.Count));
                int k = gcat.Count, nrep = ys.Length;
                var members = Enumerable.Range(0, k).Select(_ => new List<int>()).ToArray();
                for (int j = 0; j < rows; j++) if (gid[j] >= 0 && j < x.Length && x.Data[j] != Constant.MISSING) members[gid[j]].Add(j);
                for (int g = 0; g < k; g++) if (members[g].Count == 0) throw new ArgumentException($"Group '{gcat[g]}' has no predictor (X) observations.");
                int maxr = members.Max(m => m.Count);
                string catlab = string.Join(", ", groups.Select(c => c.title));
                var data = new GroupedCovarianceData { k=k, maxr=maxr, maxreps=nrep, xlab=x.Title,
                    a=new double[k+1], b=new double[k+1], bnam=new string[k+1], cx=new ColumnData[k+1], nxi=new int[k+1], ny=new int[k+1,maxr+1], rssx=new double[k+1], xmean=new double[k+1], ymean=new double[k+1],
                    xt=new double[k+1,maxr+1], y=new double[k+1,maxr+1,nrep+1], minMax=new MinMax { MinX=double.MaxValue, MaxX=double.MinValue, MinY=double.MaxValue, MaxY=double.MinValue } };
                for (int g = 1; g <= k; g++) {
                    var rowsOf = members[g-1]; data.nxi[g] = rowsOf.Count;
                    data.cx[g] = new ColumnData { Title = k > 1 ? catlab + "_" + gcat[g-1] : catlab, Rows = rowsOf.Count, Sum = 0 };
                    for (int i = 1; i <= rowsOf.Count; i++) {
                        int j = rowsOf[i-1]; double xv = x.Data[j];
                        data.xt[g,i] = xv; data.cx[g].Sum += xv; data.minMax.MinX = Math.Min(data.minMax.MinX, xv); data.minMax.MaxX = Math.Max(data.minMax.MaxX, xv);
                        int cnt = 0;
                        for (int r = 0; r < nrep; r++) {
                            double yv = j < ys[r].Length ? ys[r].Data[j] : Constant.MISSING; if (yv == Constant.MISSING) continue;
                            data.y[g,i,++cnt] = yv; data.minMax.MinY = Math.Min(data.minMax.MinY, yv); data.minMax.MaxY = Math.Max(data.minMax.MaxY, yv);
                        }
                        data.ny[g,i] = cnt;   // a level whose replicates are all missing stays with a count of 0, as the separate-column path and Windows (since 9 October 2026) leave it
                    }
                }
                // Recorded as a frame of the X, Y and identifier columns, so the report's inputs and the R script hold them together.
                var record = new Dictionary<string, object>();
                foreach (var property in input.EnumerateObject()) if (property.Name is "source" or "range" or "preserveRows" or "layout" or "roles") record[property.Name] = property.Value.Clone();
                record["identifiers"] = groups.Select(c => c.title).ToArray();
                Func<DoubleVariable, object> column = v => new { title = v.Title, values = Enumerable.Range(0, v.Length).Select(r => v.Data[r] == Constant.MISSING ? (object)"*" : v.Data[r]).ToArray() };
                record["columns"] = new[] { column(x) }.Concat(ys.Select(column)).Concat(groups.Select(c => (object)new { title = c.title, mode = "GroupIdentifiers", values = (object)c.values })).ToArray();
                job.Record(title, record, "gcd", "grid", "NumericReplaceMissing"); return data;
            } catch (ArgumentException ex) { error = ex.Message; }
        }
    }
}
