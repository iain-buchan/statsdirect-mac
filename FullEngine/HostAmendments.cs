using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using StatsDirect.Builtins;
using StatsDirect.Charting;
using StatsDirect.Numerics;
using StatsDirect.Templates;
using StatsDirect.Utilities;

internal static class HostAmendments {
    internal static object Field(string name, string label, object value, string kind = "number", double? min = null, double? max = null) => new { name, label, defaultValue = value, kind, min, max };
    internal static JsonElement Form(OperationJob job, string title, object[] fields, Action<JsonElement> validate = null, string rubric = null) {
        string error = null;
        while (true) {
            var value = job.Ask(new() { ["kind"] = "fields", ["title"] = title, ["prompt"] = title, ["fields"] = fields, ["rubric"] = rubric, ["error"] = error });
            try { validate?.Invoke(value); job.Record(title, value); return value; } catch (ArgumentException ex) { error = ex.Message; }
        }
    }
    internal static ParameterBag Amend(OperationJob job, OperationHost host, IFillable options, ParameterBag context) {
        context ??= new ParameterBag();
        if (options is CategoriseOptions categorise) return HostDataForms.Categorise(job,categorise,context);
        if (options is ExtractionOptions extraction) return HostDataForms.Extract(job,extraction,context);
        if (options is SortInPlaceOptions) return HostDataForms.Sort(job,host,context);
        if (options is ToggleFiltersOptions) return HostDataForms.Filter(job,host,context);
        if (options is ROCCutoff cutoff) {
            var a=Form(job,"ROC cutoff",new[]{Field("cutoff","Cutoff",cutoff.SeriesRecord.cutoff)});
            cutoff.SeriesRecord.cutoff=HostParameters.Number(a.GetProperty("cutoff"));cutoff.SeriesRecord.ReCut();return context;
        }
        if (options is GraphicsOptions) {
            var answer = job.Ask(new() { ["kind"]="options",["title"]="Graphics options",["prompt"]="Graphics defaults for new charts",["options"]=new[] {
                new {value="colour",label="Use colour",selected=host.Preferences.ShouldUseColour},
                new {value="box",label="Box axes",selected=ChartPreferences.DefaultBoxAxes}
            }});
            host.Preferences.ShouldUseColour=answer.GetProperty("colour").GetBoolean();
            ChartPreferences.DefaultBoxAxes=answer.GetProperty("box").GetBoolean();
            job.Record("Graphics options",answer);return context;
        }
        if (options is DummyOptions dummy) {
            var choices = dummy.CategoryNames.Select((name,i) => new { value=i.ToString(),label=name }).ToList();
            choices.Add(new {value="-1",label="No reference — include every category"});
            if (dummy.AllowUserToTreatAsContinuous) choices.Add(new {value="-2",label="Treat as a continuous variable"});
            var initial=dummy.CategoryNames.IndexOf(dummy.LargestCategoryTitle).ToString();
            var answer=job.Ask(new(){["kind"]="option",["title"]="Reference category",["prompt"]="Choose the reference category for " + dummy.VariableName,["options"]=choices,["defaultValue"]=initial});
            if(!int.TryParse(answer.GetString(),out int choice)||choice < (dummy.AllowUserToTreatAsContinuous?-2:-1)||choice>=dummy.CategoryNames.Count) throw new ArgumentException("Invalid reference category.");
            dummy.TreatAsContinuous=choice == -2; dummy.JDrop=choice; job.Record("Reference category for " + dummy.VariableName,choices.First(c=>c.value==choice.ToString()).label); return context;
        }
        if (options is SummaryStatisticsOptions summary) { host.Html.Append("<pre>").Append(System.Net.WebUtility.HtmlEncode(summary.Text)).Append("</pre>"); return context; }
        if (options is ChartDefinition chart) {
            // The calculation layer has already set the appropriate chart type and scales.
            if (chart.ChartOptions != null) {
                // The Windows options control initializes the marker list. Renderers
                // need it for mixed numeric/category series such as bar-chart labels.
                if (chart.ChartOptions.MarkerTypes == null || chart.ChartOptions.MarkerTypes.Count == 0)
                    chart.ChartOptions.MarkerTypes = ChartPreferences.MarkerTypes.Select(m=>m.Clone()).ToList();
                var a = Form(job, "Chart labels", new[] { Field("title", "Title", chart.ChartOptions.Title ?? "", "text"), Field("x", "Horizontal axis", chart.ChartOptions.XAxisTitle ?? "", "text"), Field("y", "Vertical axis", chart.ChartOptions.YAxisTitle ?? "", "text") });
                chart.ChartOptions.Title = a.GetProperty("title").GetString(); chart.ChartOptions.XAxisTitle = a.GetProperty("x").GetString(); chart.ChartOptions.YAxisTitle = a.GetProperty("y").GetString();
                if (chart.IsAscii && chart.ChartOptions is ScatterXYOptions) {
                    var scale=chart.ScaleParameters;
                    foreach(var pair in new[]{(axis:scale.X,isY:false),(axis:scale.Y,isY:true)}) {
                        pair.axis.ScaleType=ScaleType.Linear;
                        pair.axis.AxisScale=AxisScalerFactory.AxisScalerFor(ScaleType.Linear).QAxis(pair.axis.Min,pair.axis.MinGreaterThanZero,pair.axis.Max,pair.isY,true);
                    }
                }
            }
            return context;
        }
        if (options is ScoresOptions scores) {
            var fields = scores.Values1.Select((n, i) => Field("a" + i, (scores.Title1 ?? "First scores") + " " + (i + 1), n)).Concat(scores.Values2.Select((n, i) => Field("b" + i, (scores.Title2 ?? "Second scores") + " " + (i + 1), n))).ToArray();
            var a = Form(job, "Scores", fields, v => { foreach (var p in v.EnumerateObject()) HostParameters.Number(p.Value); });
            for (int i = 0; i < scores.Values1.Count; i++) scores.Values1[i] = HostParameters.Number(a.GetProperty("a" + i));
            for (int i = 0; i < scores.Values2.Count; i++) scores.Values2[i] = HostParameters.Number(a.GetProperty("b" + i));
            return context;
        }
        if (options is ChiSquareGoodnessOfFitOptions goodness) {
            var fields = new[] { Field("df", "Degrees of freedom", goodness.Df, "integer", 1) }.Concat(goodness.X.Select((label, i) => Field("e" + i, label + " — expected (observed " + goodness.Xn[i] + ")", goodness.Xe[i], min: 0))).ToArray();
            var a = Form(job, "Expected frequencies", fields, v => { double df = HostParameters.Number(v.GetProperty("df")); if (df < 1 || df != Math.Truncate(df)) throw new ArgumentException("Degrees of freedom must be a positive integer."); for (int i = 0; i < goodness.Xe.Count; i++) if (HostParameters.Number(v.GetProperty("e" + i)) <= 0) throw new ArgumentException("Expected frequencies must be positive."); });
            goodness.Df = (int)HostParameters.Number(a.GetProperty("df")); for (int i = 0; i < goodness.Xe.Count; i++) goodness.Xe[i] = HostParameters.Number(a.GetProperty("e" + i)); return context;
        }
        if (options is DistributionOptions distribution) return Distribution(job, distribution.SelectedTest);
        throw new NotSupportedException("The Mac options form for " + options.FillerToUse + " is not available yet.");
    }
    static ParameterBag Distribution(OperationJob job, DistributionType type) {
        var fields = new List<object>();
        if (type != DistributionType.Poisson) fields.Add(Field("x", type == DistributionType.Binomial ? "Probability of success" : type == DistributionType.Kendall ? "Kendall tau" : type == DistributionType.Rho ? "Spearman rho" : "Statistic", type == DistributionType.Binomial || type == DistributionType.Kendall || type == DistributionType.Rho ? 0.5 : 1.96));
        if (type != DistributionType.Z) fields.Add(Field("df", type == DistributionType.Binomial ? "Number of trials" : type == DistributionType.Poisson ? "Number of events" : type == DistributionType.Rho || type == DistributionType.Kendall ? "Sample size" : "Degrees of freedom", 10, "integer", type == DistributionType.Poisson ? 0 : 1));
        if (type == DistributionType.F || type == DistributionType.Q || type == DistributionType.Binomial || type == DistributionType.Poisson || type == DistributionType.NonCentralT) fields.Add(Field("df2", type == DistributionType.F ? "Denominator degrees of freedom" : type == DistributionType.Q ? "Number of samples" : type == DistributionType.Binomial ? "Number of successes" : type == DistributionType.Poisson ? "Mean" : "Noncentrality", type == DistributionType.NonCentralT ? 0 : 2));
        double lower = 0, upper = 0, mass = double.NaN;
        var result = Form(job, type + " distribution", fields.ToArray(), a => {
            double x = a.TryGetProperty("x", out var v) ? HostParameters.Number(v) : 0;
            double df = a.TryGetProperty("df", out v) ? HostParameters.Number(v) : 0;
            double df2 = a.TryGetProperty("df2", out v) ? HostParameters.Number(v) : 0;
            if (type != DistributionType.Z && (df < (type == DistributionType.Poisson ? 0 : 1) || df != Math.Truncate(df) || df > int.MaxValue)) throw new ArgumentException("Enter valid integer degrees of freedom, sample size or event count.");
            int fault = 0;
            switch (type) {
                case DistributionType.Z: lower = PDF.alnorm(x); upper = 1 - lower; break;
                case DistributionType.T: upper = PDF.tvalp(x, df); lower = 1 - upper; break;
                case DistributionType.F: if (x < 0 || df2 <= 0) throw new ArgumentException("F must be non-negative and both degrees of freedom positive."); upper = PDF.fvalp(x, df, df2); lower = 1 - upper; break;
                case DistributionType.ChiSq: if (x < 0) throw new ArgumentException("Chi-square must be non-negative."); upper = PDF.chivalp(x, df); lower = 1 - upper; break;
                case DistributionType.Q: if (x < 0 || df2 < 2) throw new ArgumentException("Q must be non-negative and the number of samples at least two."); lower = PDF.probsr(x, df2, df); upper = 1 - lower; break;
                case DistributionType.Binomial: if (x < 0 || x > 1 || df2 < 0 || df2 > df || df2 != Math.Truncate(df2)) throw new ArgumentException("Use a probability from 0 to 1 and an integer number of successes between 0 and the trial count."); ExFortran.bino((int)df, x, (int)df2, out mass, out lower, out upper, out fault); break;
                case DistributionType.Poisson: if (df2 < 0) throw new ArgumentException("The mean must be non-negative."); ExFortran.poisson(df2, (int)df, out upper, out lower, out mass, out fault); break;
                case DistributionType.NonCentralT: lower = ExFortran.pnct(x, (int)df, df2, out fault); upper = 1 - lower; break;
                case DistributionType.Rho: if (df < 4 || x < -1 || x > 1) throw new ArgumentException("Use a sample size of at least 4 and rho between −1 and 1."); upper = MathDbl.prhoUpper((int)df, Convert.ToInt32((1 - x) * df * (df * df - 1) / 6), out fault); lower = double.NaN; break;
                case DistributionType.Kendall: if (x < -1 || x > 1) throw new ArgumentException("Tau must be between −1 and 1."); upper = MathDbl.kendp(Convert.ToInt32(x * df * (df - 1) / 2), (int)df, ref fault); lower = double.NaN; break;
            }
            if (fault != 0 || !double.IsFinite(upper) || upper < 0 || upper > 1) throw new ArgumentException("The engine could not calculate this distribution for those inputs.");
        });
        string inputs = string.Join(", ", result.EnumerateObject().Select(p => p.Name + " = " + p.Value));
        string report = type + " distribution (" + inputs + ")\nUpper tail = " + upper.ToString("G15", System.Globalization.CultureInfo.InvariantCulture);
        if (double.IsFinite(lower)) report += "\nLower tail = " + lower.ToString("G15", System.Globalization.CultureInfo.InvariantCulture);
        if (double.IsFinite(mass)) report += "\nProbability of exactly this count = " + mass.ToString("G15", System.Globalization.CultureInfo.InvariantCulture);
        if (type == DistributionType.Z || type == DistributionType.T) report += "\nTwo-sided P = " + (2 * Math.Min(lower, upper)).ToString("G15", System.Globalization.CultureInfo.InvariantCulture);
        var bag = new ParameterBag(); bag.AddOutput("gr", report); bag.AddOutput("upper", upper); if (double.IsFinite(lower)) bag.AddOutput("lower", lower); return bag;
    }
}
