using System;
using System.Globalization;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using StatsDirect.Builtins;
using StatsDirect.Charting;
using StatsDirect.Expressions;
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
                if (!chart.IsAscii && chart.ChartOptions is BoxWhiskerOptions box) {
                    HostChartForms.BoxWhisker(job, host, chart, box);
                    return context;
                }
                var fields = new List<object> { Field("title", "Title", chart.ChartOptions.Title ?? "", "text"), Field("x", "Horizontal axis", chart.ChartOptions.XAxisTitle ?? "", "text"), Field("y", "Vertical axis", chart.ChartOptions.YAxisTitle ?? "", "text") };
                if (chart.ChartOptions is HistogramOptions) fields.Add(Field("bins","Number of bins (0 = automatic; otherwise 2–1000)",0,"integer",0,1000));
                var a = Form(job, "Chart labels", fields.ToArray(), value => {
                    if (value.TryGetProperty("bins",out var b)) { double n=HostParameters.Number(b); if(n<0||n==1||n>1000||n!=Math.Truncate(n))throw new ArgumentException("Use 0 for automatic bins or a whole number from 2 to 1000."); }
                });
                if (chart.ChartOptions is HistogramOptions histogram && a.TryGetProperty("bins",out var bins) && HostParameters.Number(bins)>1) {
                    for(int i=0;i<histogram.HistoSeriesOptions.Count;i++) histogram.Reset(false,(int)HostParameters.Number(bins),i,(DoubleSeries)chart.YSeries[i]);
                }
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
    // The Distributions calculator, as the Windows ctlPDF: the boxes a distribution has (ctlPDF.SetVisibility), under the names the
    // Windows calculator records. With the value given (for the Poisson distribution, the mean) the probabilities of the value are
    // calculated; with the value left empty and one probability box filled, the value of that probability is found (Invert on Windows).
    static ParameterBag Distribution(OperationJob job, DistributionType type) {
        bool poisson = type == DistributionType.Poisson, binomial = type == DistributionType.Binomial, counts = poisson || binomial;
        // The boxes each distribution shows; the binomial shows its three probabilities but has no inverse.
        bool showLower = type is DistributionType.Z or DistributionType.T or DistributionType.Q or DistributionType.NonCentralT || counts;
        bool showTwoSided = type is DistributionType.Z or DistributionType.T || counts;
        var fields = new List<object>();
        if (!poisson) fields.Add(Field("x", binomial ? "Probability of success" : type == DistributionType.Kendall ? "Kendall tau" : type == DistributionType.Rho ? "Spearman rho" : "Statistic", binomial || type == DistributionType.Kendall || type == DistributionType.Rho ? 0.5 : 1.96));
        if (type != DistributionType.Z) fields.Add(Field("df", binomial ? "Number of trials" : poisson ? "Number of events" : type == DistributionType.Rho || type == DistributionType.Kendall ? "Sample size" : "Degrees of freedom", 10, type == DistributionType.T ? "number" : "integer", poisson ? 0 : type == DistributionType.Kendall ? 2 : 1));
        if (type is DistributionType.F or DistributionType.Q or DistributionType.Binomial or DistributionType.Poisson or DistributionType.NonCentralT) fields.Add(Field("df2", type == DistributionType.F ? "Denominator degrees of freedom" : type == DistributionType.Q ? "Number of samples" : binomial ? "Number of successes" : poisson ? "Mean" : "Noncentrality", type == DistributionType.NonCentralT ? 0 : 2));
        string count = "Probability of this count";
        if (showLower) fields.Add(Field("lower", counts ? count : "Lower tail probability", null, "number", 0, 1));
        fields.Add(Field("upper", counts ? count + " or more" : "Upper tail probability", null, "number", 0, 1));
        if (showTwoSided) fields.Add(Field("two_sided", counts ? count + " or fewer" : "Two-sided probability", null, "number", 0, 1));
        string rubric = binomial ? null : poisson ? "Enter the mean to calculate the probabilities of the count, or leave the mean empty and enter one probability to find the mean that gives it."
            : "Enter the value to calculate its probabilities, or leave the value empty and enter one probability to find the value of that probability.";
        static bool Given(JsonElement a, string name, out double value) {
            value = double.NaN;
            if (!a.TryGetProperty(name, out var v) || v.ValueKind == JsonValueKind.Null || v.ValueKind == JsonValueKind.Undefined) return false;
            if (v.ValueKind == JsonValueKind.String && string.IsNullOrWhiteSpace(v.GetString())) return false;
            value = HostParameters.Number(v); return true;
        }
        string asked = "calculate"; double x = double.NaN, df = 0, df2 = double.NaN, lower = double.NaN, upper = double.NaN, twoSided = double.NaN, mass = double.NaN; int statistic = 0;
        var result = Form(job, type + " distribution", fields.ToArray(), a => {
            asked = "calculate"; x = double.NaN; lower = double.NaN; upper = double.NaN; twoSided = double.NaN; mass = double.NaN; statistic = 0;
            bool valueGiven = poisson ? Given(a, "df2", out df2) : Given(a, "x", out x);
            if (!poisson) df2 = Given(a, "df2", out var d2) ? d2 : double.NaN;
            df = Given(a, "df", out var d) ? d : 0;
            if (type != DistributionType.Z && (df < (poisson ? 0 : 1) || (type != DistributionType.T && df != Math.Truncate(df)) || df > int.MaxValue)) throw new ArgumentException(type == DistributionType.T ? "Degrees of freedom must be at least 1 and no greater than 2,147,483,647." : "Enter valid integer degrees of freedom, sample size or event count.");
            var boxes = new List<(string name, double p)>();
            foreach (var (name, shown) in new[] { ("lower", showLower), ("upper", true), ("two_sided", showTwoSided) }) if (shown && Given(a, name, out var p)) boxes.Add((name, p));
            if (!valueGiven) {
                if (binomial) throw new ArgumentException("Enter the probability of success.");
                if (boxes.Count != 1) throw new ArgumentException(poisson ? "Enter the mean, or leave it empty and enter exactly one probability to find the mean." : "Enter the value, or leave it empty and enter exactly one probability to find the value.");
                Invert(type, boxes[0].name, boxes[0].p, ref df, ref df2, out x, out lower, out upper, out twoSided);
                if (type == DistributionType.Rho || type == DistributionType.Kendall) statistic = (int)df2;
                asked = "invert-" + (boxes[0].name == "two_sided" ? "two-sided" : boxes[0].name);
                return;
            }
            int fault = 0;
            switch (type) {
                // Obtain each tail directly: subtracting a rounded tail loses small probabilities.
                case DistributionType.Z: lower = PDF.alnorm(x); upper = PDF.alnorm(-x); twoSided = 2 * Math.Min(lower, upper); break;
                case DistributionType.T: upper = PDF.TProbability(x, df); lower = PDF.TProbability(x, df, true); twoSided = 2 * Math.Min(lower, upper); break;
                case DistributionType.F: if (x < 0 || !(df2 > 0)) throw new ArgumentException("F must be non-negative and both degrees of freedom positive."); upper = PDF.FProbability(x, df, df2); lower = PDF.FProbability(x, df, df2, true); break;
                case DistributionType.ChiSq: if (x < 0) throw new ArgumentException("Chi-square must be non-negative."); upper = SDMath.Pchisq(x, df, false, false); lower = SDMath.Pchisq(x, df, true, false); break;
                case DistributionType.Q: if (x < 0 || !(df2 >= 2)) throw new ArgumentException("Q must be non-negative and the number of samples at least two."); lower = PDF.probsr(x, df2, df); upper = 1 - lower; break;
                // The Windows boxes hold the probabilities of exactly, at least and at most the count (ctlPDF.PFromBinomial, PFromPoisson).
                case DistributionType.Binomial: if (x < 0 || x > 1 || !(df2 >= 0) || df2 > df || df2 != Math.Truncate(df2)) throw new ArgumentException("Use a probability from 0 to 1 and an integer number of successes between 0 and the trial count."); ExFortran.bino((int)df, x, (int)df2, out mass, out twoSided, out upper, out fault); lower = mass; break;
                case DistributionType.Poisson: if (df2 < 0) throw new ArgumentException("The mean must be non-negative."); ExFortran.poisson(df2, (int)df, out upper, out twoSided, out mass, out fault); lower = mass; break;
                case DistributionType.NonCentralT:
                    if (double.IsNaN(df2)) throw new ArgumentException("Enter the noncentrality.");
                    lower = ExFortran.pnct(x, (int)df, df2, out fault); upper = 1 - lower;
                    // Match ctlPDF: obtain the small upper tail by symmetry, before subtraction loses it.
                    if (fault == 0 && lower > .5) { upper = ExFortran.pnct(-x, (int)df, -df2, out fault); lower = 1 - upper; }
                    break;
                case DistributionType.Rho:
                    double most = df * (df * df - 1) / 3;
                    if (df < 4 || most > int.MaxValue - 4 || x < -1 || x > 1) throw new ArgumentException("Use a sample size from 4 to 1860 and rho between −1 and 1.");
                    statistic = Convert.ToInt32((1 - x) * most / 2); upper = MathDbl.prhoUpper((int)df, statistic, out fault); lower = double.NaN; break;
                case DistributionType.Kendall:
                    double score = x * df * (df - 1) / 2;
                    if (df < 2 || x < -1 || x > 1 || Math.Abs(score) > int.MaxValue) throw new ArgumentException("Use a sample size of at least 2 and tau between −1 and 1, with a Kendall score within the engine's integer range.");
                    statistic = Convert.ToInt32(score); upper = MathDbl.kendp(statistic, (int)df, ref fault); lower = double.NaN; break;
            }
            if (fault != 0 || !double.IsFinite(upper) || upper < 0 || upper > 1) throw new ArgumentException("The engine could not calculate this distribution for those inputs.");
        }, rubric);
        string F(double v) => v.ToString("G15", System.Globalization.CultureInfo.InvariantCulture);
        var shown = new List<string>();
        if (!poisson && double.IsFinite(x)) shown.Add("x = " + F(x)); if (type != DistributionType.Z) shown.Add("df = " + F(df)); if (double.IsFinite(df2)) shown.Add("df2 = " + F(df2));
        string report = type + " distribution (" + string.Join(", ", shown) + (asked == "calculate" ? "" : ", " + asked) + ")";
        if (asked != "calculate") report += poisson ? "\nMean = " + F(df2) : "\nValue = " + F(x);
        // For a count the tails are this count or more and this count or fewer, with the probability of exactly this count as well.
        if (counts) report += "\nUpper tail = " + F(upper) + "\nLower tail = " + F(twoSided) + "\nProbability of exactly this count = " + F(lower);
        else {
            report += "\nUpper tail = " + F(upper);
            if (double.IsFinite(lower)) report += "\nLower tail = " + F(lower);
            if (double.IsFinite(twoSided)) report += "\nTwo-sided P = " + F(twoSided);
        }
        // The report line is the calculation's only output, as on Windows (ctlPDF.Fill). The calculation's inputs go to the bag for the
        // record a report keeps of the run and the R script written from it, as the Windows Distributions calculator records its boxes
        // (ctlPDF.Fill through Box): every box that is shown for the distribution and holds a number, under one set of names for every
        // distribution, with the number as the box shows it and reads it back (a value to 15 figures, a probability to 15 decimal places,
        // the studentized range's to 7, "< 1E-15" as the machine epsilon), and what was asked of them (calculate, or the box inverted).
        var bag = new ParameterBag(); bag.AddOutput("gr", report);
        void Box(string name, double? value) { if (value is double n) bag.AddInput(name, n); }
        if (!poisson && double.IsFinite(x)) Box("value", ShownValue(x));
        if (type != DistributionType.Z) Box("df", ShownValue(df));
        if (type == DistributionType.Rho || type == DistributionType.Kendall) Box("df2", statistic);   // the score the calculator works out of the correlation, shown in its second box
        else if (double.IsFinite(df2)) Box("df2", ShownValue(df2));
        bool zeroShown = type != DistributionType.Rho && type != DistributionType.Kendall;   // ctlPDF.AllowsZeroP
        switch (type) {
            case DistributionType.Z: case DistributionType.T: Box("lower", ShownProbability(lower, zeroShown)); Box("upper", ShownProbability(upper, zeroShown)); Box("two_sided", ShownProbability(twoSided, zeroShown)); break;
            case DistributionType.NonCentralT: Box("lower", ShownProbability(lower, zeroShown)); Box("upper", ShownProbability(upper, zeroShown)); break;
            case DistributionType.Q: Box("lower", ShownRounded(lower, 7)); Box("upper", ShownRounded(upper, 7)); break;
            case DistributionType.Binomial: case DistributionType.Poisson: Box("lower", ShownProbability(lower, zeroShown)); Box("upper", ShownProbability(upper, zeroShown)); Box("two_sided", ShownProbability(twoSided, zeroShown)); break;
            default: Box("upper", ShownProbability(upper, zeroShown)); break;   // F, chi-square, Spearman's rho, Kendall's tau: the upper tail alone
        }
        bag.AddInput("asked", asked);
        return bag;
    }
    // The value of a probability box, as the Windows calculator's Invert: the probability is kept within 0 to 1, the other
    // boxes follow from it, and the value is found through the routine that takes the probability most exactly.
    static void Invert(DistributionType type, string box, double p, ref double df, ref double df2, out double x, out double lower, out double upper, out double twoSided) {
        p = Math.Max(0, Math.Min(1, p)); x = double.NaN; int fault = 0;
        bool poisson = type == DistributionType.Poisson;
        if (type != DistributionType.Z && !poisson && df < 1) df = 1;   // degrees of freedom below 1 are taken as 1
        if (poisson) {
            // The mean with which this count has the box's probability: the three probabilities of the count with that mean follow.
            int nl = (int)df, idx = box == "lower" ? 1 : box == "upper" ? 2 : 3; double P = box == "lower" ? 1 - p : p, xmid, trm, phi, plo;
            if (nl == 0) {
                // With no events the search never leaves the origin; the probability of none is exp(-mean), so the mean at which
                // 0 or fewer events has probability P is -ln P; 0 or more has probability 1 whatever the mean, so that is refused.
                if (idx == 3 && p > 0 && p <= 1) { xmid = 0.0 - Math.Log(p); trm = p; plo = p; phi = 1; fault = 0; } else { xmid = trm = phi = plo = double.NaN; fault = 1; }
            } else ExFortran.poissoni(idx, P, out xmid, out trm, out phi, out plo, nl, out fault);
            if (fault != 0 || !double.IsFinite(xmid)) throw new ArgumentException("The engine could not find a mean for that probability and count.");
            df2 = xmid; lower = trm; upper = phi; twoSided = plo; return;
        }
        // The lower tail, the upper tail and the two-sided probability of the box, as the Windows boxes are filled before inverting.
        if (box == "lower") { lower = p; upper = 1 - p; twoSided = 2 * Math.Min(p, 1 - p); }
        else if (box == "upper") { upper = p; lower = 1 - p; twoSided = 2 * Math.Min(p, 1 - p); }
        else { twoSided = p; double half = p / 2; if (half > 1 - half) half = 1 - half; upper = half; lower = 1 - half; }
        switch (type) {
            // gauinv takes a lower tail area; an upper or two-sided P is inverted by symmetry as minus the deviate of its own value.
            case DistributionType.Z: x = box == "lower" ? PDF.gauinv(lower, out fault) : 0.0 - PDF.gauinv(upper, out fault); break;
            // tfromp takes an upper tail area; a lower tail P by symmetry as minus the value of its own area.
            case DistributionType.T: x = box == "lower" ? 0.0 - PDF.tfromp(lower, df) : PDF.tfromp(upper, df); break;
            case DistributionType.F: if (!(df2 > 0)) throw new ArgumentException("Enter both degrees of freedom."); x = PDF.ffromp(df2, df, upper); break;
            case DistributionType.ChiSq: x = box == "lower" ? PDF.ppchi2(lower, df, out fault) : PDF.ppchi2(upper, df, true, out fault); break;
            // The studentized range routine takes the probability below the value.
            case DistributionType.Q: if (!(df2 >= 2)) throw new ArgumentException("Enter the number of samples, at least two."); x = PDF.quantsr(lower, df2, df); if (x == Constant.MISSING) fault = 1; else x = double.Parse(x.ToString("G7", CultureInfo.InvariantCulture), CultureInfo.InvariantCulture); break;
            // tnct takes a lower tail area; an upper tail P by symmetry with the non-centrality negated.
            case DistributionType.NonCentralT:
                if (double.IsNaN(df2)) throw new ArgumentException("Enter the non-centrality.");
                if (box == "lower") x = ExFortran.tnct(lower, (int)df, df2, out fault); else { x = ExFortran.tnct(upper, (int)df, 0.0 - df2, out fault); if (fault == 0) x = 0.0 - x; }
                break;
            // Spearman's rho and Kendall's tau of an upper tail P: the greatest statistic whose probability is not above P, with its probability.
            case DistributionType.Rho: { x = MathDbl.rhofromp(upper, out double pu, out int ix, (int)df, out fault); if (fault == 0) { df2 = ix; upper = pu; } break; }
            case DistributionType.Kendall: { int nx = (int)df; x = MathDbl.taufromp(upper, out double pu, out int ix, ref nx, out fault); if (fault == 0) { df2 = ix; upper = pu; } break; }
            default: throw new ArgumentException("This distribution cannot be inverted.");
        }
        if (fault != 0 || !double.IsFinite(x)) throw new ArgumentException("The engine could not find a value for that probability.");
        if (type != DistributionType.Q) x = double.Parse(x.ToString("G15", CultureInfo.InvariantCulture), CultureInfo.InvariantCulture);
    }
    // A probability as the Windows calculator's box shows it (ctlPDF.Pval15) and reads it back (CdblTxt): to 15 decimal places; to 15
    // figures below 1e-15, or "< 1E-15", read as the machine epsilon, where a probability of 0 cannot be shown; 1 from 0.999999999999999;
    // nothing where the box would say "error".
    static double? ShownProbability(double p, bool allowZero) {
        if (!double.IsFinite(p) || p == Constant.MISSING) return null;
        if (!allowZero && p < 1e-15) return Constant.EPSILON;
        return ReadBack(p < 1e-15 ? p.ToString("G15") : p >= 0.999999999999999 ? "1" : Formatting.XRound(p, 15));
    }
    // A value as the calculator's box shows it (ctlPDF.Xval15: 15 figures), or a probability to the places the box shows (the studentized
    // range's tails to 7, ctlPDF.PFromQ), read back as a number.
    static double? ShownValue(double x) => ShownRounded(x, 15);
    static double? ShownRounded(double x, int places) => double.IsFinite(x) && x != Constant.MISSING ? ReadBack(Formatting.XRound(x, places)) : null;
    static double? ReadBack(string text) => double.TryParse(text, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.CurrentCulture, out double n) && double.IsFinite(n) ? n : null;
}
