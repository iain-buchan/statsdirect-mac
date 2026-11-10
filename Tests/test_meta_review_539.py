#!/usr/bin/env python3
"""The Mac mirror of the Windows meta-analysis review of StatsDirect 5.3.9.

Windows test: FullEngine/Upstream/tests/RScript/MetaReview539.cs (CheckMetaReview539), at the tag v5.3.9 (f41aad46).

Its five parts, with Windows's data, options, labels, expected figures and R assertions (the C# that builds them is carried over
as it is written there, and runs in the Mac's operation host as a C# script):

  forest   the native forest plots label the kept studies after a blank row as the report's tables and the R script do: with no
           labels, by their places among the kept studies, not their worksheet rows (nine analyses, with and without labels)
  bias     the bias indicators of the nine meta-analysis replays: none with two or three studies, Egger's and Harbord's
           intervals at the bias tests' level, and two studies' test-based I-squared interval exactly when Q > k
  summary  a summary meta-analysis of a difference is labelled and plotted as a difference, from standard errors or limits
  empty    tables with empty cells through the four analyses of fourfold tables and the typed-in Mantel-Haenszel test, under
           the calculation options (exact methods; the treatment arm, 0.5 or 0.01 correction; delayed or not)
  limits   a pooled proportion of 0 or 1, and summary limits selected the wrong way round

Each run is made twice in the Mac's operation host, with Windows's selection and calculation options. The analysis's own builtin
is called in a C# script, and its bag gives the native figures of Windows's assertions and the labels of the chart definitions.
The same run is then made at the operation's own prompts, each answered by its name as Windows's checking host answers its
parameters, with the columns as worksheet selections: its record is the one the shared R writer turns into the script, and its
report is where the forest plots' drawn labels are read. Rscript runs each script with Windows's assertions against the native
figures, in Windows's batches (one R process for each batch, each replay in its own environment). The run at the prompts is
given the selection as it was made, written down before the builtin runs: the summary meta-analysis puts limits selected the
wrong way round the right way round in the frames it is handed, and a replay of limits already put right would not try the
script's own correction (Windows's script re-reads the cells for the same reason). So a replay of limits the wrong way round
must have them that way round in its script, or it is listed as a disagreement. A replay whose selection the picker refuses at
a prompt is listed as a disagreement too (the rest of its checks then use a record written from the builtin's bag, so that
one run shows everything); none is refused at v5.3.9. The one selection of the forest part the picker refuses is the
proportion meta-analysis's, whose totals may not have a blank row (the template's own validation, on both platforms): its
labels are checked on the chart definitions alone, as Windows checks them. A part that passes must have made as many checks
as Windows makes in it. Parts can be run alone, as on Windows: name them in STATSDIRECT_META_REVIEW_539_PARTS (forest, bias,
summary, empty or limits, separated by commas).

Every check prints one "PASS: ..." line; the first failure stops the test with "FAIL ...". With
STATSDIRECT_META_REVIEW_539_COLLECT=1 the failures are collected instead ("FAIL: ..." lines) and counted at the end, which
shows what an older engine does not have; the default is unchanged by it.
"""
import base64
import concurrent.futures
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time
import traceback
import uuid

from r_runtime import rscript
from test_menu import ROOT, Session
from test_pr6_replay import RWriter, sheet

RSCRIPT = rscript()
PREFERENCES = {'use-default-ci': False, 'decp': '12'}
COLLECT = os.environ.get('STATSDIRECT_META_REVIEW_539_COLLECT') == '1'
SKIP = {'skip': True}                   # an optional prompt skipped, as the Windows checking host answers null
OPTIONAL = ('strata', 'studies', 'g')   # the prompts Windows answers null in these checks
# ProportionMeta.xml asks for totals that are positive numbers, so the picker does not take their blank row, on either platform
# (Tests/test_meta_missing_studies.py has the same refusal, which Windows's MetaMissingStudies marks record-only)
REFUSED_AT_PROMPTS = {'ProportionMeta': 'sn: Data must be positive non-zero numbers'}
PARTS = ('forest', 'bias', 'summary', 'empty', 'limits')
WORKERS = max(2, min(6, os.cpu_count() or 2))
WINDOWS_CHECKS = {'forest': 18, 'bias': 523, 'summary': 49, 'empty': 1825, 'limits': 137}
checks = 0
failed = []


def fail(what):
    if not COLLECT:
        raise AssertionError('FAIL ' + what)
    failed.append(what)
    print('FAIL:', what, flush=True)


def check(ok, what):
    global checks
    if not ok:
        fail(what)
        return
    checks += 1
    print('PASS:', what, flush=True)


class Writer(RWriter):
    """The shared R writer; whether the record has a recipe and its data is this test's own check, as it is Windows's."""

    def write(self, record, frames=()):
        self.process.stdin.write(json.dumps({'record': record, 'frames': list(frames)}) + '\n')
        self.process.stdin.flush()
        return json.loads(self.process.stdout.readline())


# Meta539Same: R's comparison of a replayed figure with the native one
SAME = '''same <- function(x, y, tol = 2e-7) {
  x <- as.numeric(x); y <- as.numeric(y)
  length(x) == length(y) && all(is.na(x) == is.na(y)) &&
    all(ifelse(is.na(y), TRUE, ifelse(is.infinite(y), !is.na(x) & x == y, abs(x - y) <= tol * abs(y) + 1e-9)))
}
'''

# The helpers of MetaReview539.cs as they are written there (Meta539Number, Rows, Find, Value, Vector, Compare, Assertions), and
# the run: the builtin with its inputs, then the bag the report step holds. MetaSummary's template sets three inputs from the type
# of the summary statistic before its builtin (MetaSummary.xml); they are set the same way here.
PRELUDE = r'''
var inv = CultureInfo.InvariantCulture;
double Meta539Number(ParameterBag bag, string key) =>
    bag.TryGetValue(key, out FilledParameter value) && value?.AsObject is double number ? number : Constant.MISSING;
IList<ParameterBag> Meta539Rows(ParameterBag bag, string block) =>
    bag.TryGetValue(block, out FilledParameter value) && value?.AsObject is IList<ParameterBag> rows ? rows : new List<ParameterBag>();
double Meta539Find(ParameterBag bag, string key)
{
    if (bag.TryGetValue(key, out FilledParameter value) && value?.AsObject is double number) return number;
    foreach (var pair in bag.Pairs)
        if (pair.Value?.AsObject is IList<ParameterBag> rows)
            foreach (ParameterBag row in rows)
                if (row.ContainsKey(key)) return Meta539Number(row, key);
    return Constant.MISSING;
}
string Meta539Value(double value) => value == Constant.MISSING || double.IsNaN(value) ? "NA"
    : double.IsPositiveInfinity(value) ? "Inf" : double.IsNegativeInfinity(value) ? "-Inf" : value.ToString("R", inv);
string Meta539Vector(IEnumerable<double> values) => "c(" + string.Join(", ", values.Select(Meta539Value)) + ")";
string Meta539Compare(string what, string expression, IEnumerable<double> expected, double tolerance = 2e-7) =>
    "if (!same(c(" + expression + "), " + Meta539Vector(expected) + ", " + tolerance.ToString("R", inv) + ")) stop('" + what + " differs: ', paste(format(c(" +
    expression + "), digits = 12), collapse = ' '), ' against " + string.Join(" ", expected.Select(Meta539Value)) + "')\n";

string Meta539Assertions(string operation, ParameterBag bag)
{
    var s = new System.Text.StringBuilder();
    void Same(string what, string expression, IEnumerable<double> expected, double tolerance = 2e-7) =>
        s.Append(Meta539Compare(what, expression, expected, tolerance));
    void Labels(string expression, IEnumerable<string> expected) =>
        s.Append("if (!identical(trimws(").Append(expression).Append("), ").Append(StatsDirect.R.RScriptWriter.Vector(expected.Select(e => (object)e.Trim()).ToArray()))
         .Append(")) stop('the study labels differ: ', paste(").Append(expression).Append(", collapse = '|'))\n");
    IEnumerable<double> Column(string block, string key) => Meta539Rows(bag, block).Select(row => Meta539Number(row, key));
    IEnumerable<double> Figures(params string[] keys) => keys.Select(key => Meta539Number(bag, key));
    string block = operation switch { "RelativeRiskMeta" => "*risks", "RiskDifference" => "*differences", "PetoMeta" => "*odds", _ => "*or" };
    switch (operation)
    {
        case "RelativeRiskMeta":
            Same("relative risks", "rr", Column(block, "rr"));
            Same("study limits", "ci[, 1], ci[, 2]", Column(block, "lci").Concat(Column(block, "uci")));
            Same("variances", "v_i", Column(block, "vi"));
            Same("weights", "100 * w_mh / sum(w_mh), 100 * w_dl / sum(w_dl)", Column(block, "wt").Concat(Column(block, "dwt")));
            Same("pooled relative risk", "rr_mh, exp(log(rr_mh) + c(-1, 1) * z * sqrt(v_mh)), x2, rr_dl, dl_ci, x2_dl", Figures("rr", "from", "to", "x2", "dsrr", "dsll", "dsul", "dsx2"));
            Labels("note", Meta539Rows(bag, block).Select(row => Convert.ToString(row["lb"].AsObject, inv)));
            break;
        case "RiskDifference":
            Same("risk differences", "rd", Column(block, "rd"));
            Same("study limits", "ci[, 1], ci[, 2]", Column(block, "lci").Concat(Column(block, "uci")));
            Same("variances", "v_iv", Column(block, "vi"));
            Same("weights", "100 * w_mh / sum(w_mh), 100 * w_dl / sum(w_dl)", Column(block, "wt").Concat(Column(block, "dwt")));
            Same("pooled risk difference", "rd_mh, rd_mh + c(-1, 1) * z * se_mh, x2, rd_dl, rd_dl + c(-1, 1) * z * se_dl, x2_dl", Figures("rmh", "from", "to", "x2", "dsrd", "dsll", "dsul", "dsx2"));
            Labels("note", Meta539Rows(bag, "*inputs").Select(row => Convert.ToString(row["lb"].AsObject, inv)));
            break;
        case "PetoMeta":
            Same("Peto odds ratios", "or, lower, upper", Column(block, "or").Concat(Column(block, "lci")).Concat(Column(block, "uci")));
            Same("weights", "100 * V / sum(V)", Column(block, "wt"));
            Same("pooled Peto odds ratio", "pooled, pooled_lower, pooled_upper, z_pooled", Figures("por", "from", "to", "z"));
            Labels("note", Meta539Rows(bag, block).Select(row => Convert.ToString(row["lb"].AsObject, inv)));
            break;
        default:
            Same("odds ratios", "or, lci, uci", Column(block, "or").Concat(Column(block, "lci")).Concat(Column(block, "uci")));
            Same("variances", "vi", Column(block, "vi"));
            Same("weights", "wt_fixed, wt_random", Column(block, "wt").Concat(Column(block, "dwt")));
            Same("Mantel-Haenszel odds ratio", "or_mh, mh_ci, x2", Figures("odds", "from", "to", "chi_mantel"));
            Same("Breslow-Day", "bd", Figures("bd"));
            Same("random effects odds ratio", "or_re, re_ci, x2_re", Figures("dsor", "dsll", "dsul", "dsx2"));
            if (Meta539Rows(bag, "*cml").Count == 1)
            {
                ParameterBag cml = Meta539Rows(bag, "*cml")[0];
                Same("conditional maximum likelihood", "cml, fisher, midp", new[] { "eor", "llf", "ulf", "llm", "ulm" }.Select(key => Meta539Number(cml, key)));
                Same("exact P values", "min(p_upper, p_lower), p2_fisher, p1_mid, min(1, 2 * p1_mid)", new[] { "p1f", "p2f", "p1m", "p2m" }.Select(key => Meta539Number(cml, key)));
            }
            else s.Append("if (exists('cml', inherits = FALSE)) stop('the approximate method has no exact pooled block')\n");
            Labels("note", Meta539Rows(bag, block).Select(row => Convert.ToString(row["lb"].AsObject, inv)));
            break;
    }
    Same("heterogeneity", operation == "PetoMeta" ? "Q, i2" : "q, tau2, i2", operation == "PetoMeta" ? Figures("qc", "isq") : Figures("qc", "tausq", "isq"));
    // the native search for an exact limit of I-squared is good to one part in a million
    Same("I-squared interval", "i2_ci", Figures("llisq", "ulisq"), 1e-6);
    // the bias indicators: none with three studies or fewer, as the report has them otherwise
    if (Meta539Rows(bag, "*fewStrata").Count == 1)
        s.Append("if (exists('egger_figures', inherits = FALSE)) stop('the replay gives bias indicators that the report withholds')\n");
    else
    {
        ParameterBag egger = Meta539Rows(bag, "*egger")[0];
        string begg = operation == "RelativeRiskMeta" ? "kt" : "begg";
        Same("Begg-Mazumdar", begg + "$estimate, " + begg + "$p.value", new[] { "tau", "p2" }.Select(key => Meta539Number(egger, key)));
        Same("Egger", "egger_figures", new[] { "a", "cl", "cu", "p" }.Select(key => Meta539Number(egger, key)));
        if (Meta539Rows(bag, "*harbord").Count == 1)
            Same("Harbord", "harbord_figures", new[] { "a", "cl", "cu", "p" }.Select(key => Meta539Number(Meta539Rows(bag, "*harbord")[0], key)));
    }
    return s.ToString();
}

// a frame of numeric columns, as the worksheet gives them
DataFrame F(params double[][] columns)
{
    var frame = new DataFrame();
    for (int i = 0; i < columns.Length; i++) frame.Variables.Add(new DoubleVariable(columns[i], "Column " + (i + 1)));
    return frame;
}
ParameterBag asked = null;
// what the run was asked, written down before its builtin runs: a builtin may change its inputs in place (the summary meta-analysis
// puts limits selected the wrong way round the right way round), and the run at the prompts is given the selection as it was made
string given = null;
ParameterBag Run(string operation, ParameterBag inputs)
{
    asked = inputs;
    if (operation == "MetaSummary")
    {
        string type = inputs["type"].AsString;
        bool ratio = type == "oddsRatio" || type == "relativeRisk" || type == "otherRatio";
        inputs.AddInput("use_ratio", ratio);
        inputs.AddInput("stat_in", type == "oddsRatio" ? "Odds Ratio" : type == "relativeRisk" ? "Relative Risk" : type == "riskDifference" ? "Risk Difference"
            : type == "otherRatio" ? "* Ratio" : "* Difference");
        inputs.AddInput("statx", ratio ? "differs from 1" : "differs from 0");
    }
    given = Asked();
    ParameterBag output = (operation switch {
        "RelativeRiskMeta" => Meta.RptRelativeRiskMeta(host, inputs),
        "RiskDifference" => Meta.RptRiskDifferenceMeta(host, inputs),
        "PetoMeta" => Meta.RptPetoMeta(host, inputs),
        "Mantel" => Meta.RptMantel(host, inputs),
        "MantelHaenszelScreen" => Chi.RptChiMantel(host, inputs),
        "MetaIncidenceRateRatio" => Meta.RptMetaIncidenceRateRatio(host, inputs),
        "MetaIncidenceRateDifference" => Meta.RptMetaIncidenceRateDifference(host, inputs),
        "Effect" => Meta.RptEffect(host, inputs),
        "MetaSummary" => Meta.RptMetaSummary(host, inputs),
        "MetaCorrelation" => Meta.RptMetaCorrelation(host, inputs),
        _ => Meta.RptProportionMeta(host, inputs)
    }).ParameterBag;
    var bag = inputs.Copy();
    foreach (var pair in output.Pairs) bag[pair.Key] = pair.Value;
    return bag;
}
string B64(string text) => Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes(text));
void Check(bool ok, string what) => Console.WriteLine("CHECK\t" + (ok ? "1" : "0") + "\t" + what);
void Failure(string what) => Console.WriteLine("FAILURE\t" + what);
// what the run was asked, for the same run at the operation's own prompts: its inputs, and the calculation options it ran under
string Asked()
{
    var parts = new List<string>();
    foreach (var pair in asked.Pairs)
    {
        object value = pair.Value?.AsObject;
        if (value is double number) parts.Add(pair.Key + "=d:" + number.ToString("R", inv));
        else if (value is bool flag) parts.Add(pair.Key + "=b:" + (flag ? "1" : "0"));
        else if (value is string text) parts.Add(pair.Key + "=s:" + text);
        else if (value is DataFrame one && one.Variables.Count == 1 && one.Variables[0] is StringVariable names)
            parts.Add(pair.Key + "=l:" + string.Join(",", names.Data));
        else if (value is DataFrame frame)
            parts.Add(pair.Key + "=f:" + string.Join(";", frame.Variables.Select(v => string.Join(",", ((DoubleVariable)v).Data.Select(x => x == Constant.MISSING ? "" : x.ToString("R", inv))))));
    }
    parts.Add("!meta-exact=b:" + (host.Preferences.MetaExact ? "1" : "0"));
    parts.Add("!meta-cc=d:" + Convert.ToDouble(host.Preferences.MetaCC).ToString("R", inv));
    parts.Add("!meta-delay=b:" + (host.Preferences.DelayContinuityCorrection ? "1" : "0"));
    return string.Join("|", parts);
}
// one replay of a batch: the run's answers, its record written from the bag, and Windows's assertions on the script of the record
void Replay(string batch, string label, string suffix, bool printed, string operation, ParameterBag bag, string checks) =>
    Console.WriteLine("REPLAY\t" + batch + "\t" + label + "\t" + suffix + "\t" + (printed ? "1" : "0") + "\t"
        + B64(RunRecord.Write(new OperationRun(new Operation { Name = operation }), bag)) + "\t" + B64(checks) + "\t" + operation + "\t" + B64(given));
'''

FOREST = r'''
double[] exposed = { 100, 150, 110, 80, 200, 120 }, events = { 20, 35, 23, 10, 60, 50 };
double[] control = { 100, 140, 125, 90, 210, 115 }, controlEvents = { 12, 20, 18, 12, 30, 15 };
var cases = new (string operation, (string name, double[] values)[] columns, Dictionary<string, object> settings, string labels, string format)[]
{
    ("RelativeRiskMeta", new[] { ("sn", exposed), ("sr", events), ("xn", control), ("xr", controlEvents) }, new Dictionary<string, object>(), "strata", "stratum {0}"),
    ("RiskDifference", new[] { ("sn", exposed), ("sr", events), ("xn", control), ("xr", controlEvents) }, new Dictionary<string, object>(), "strata", "stratum {0}"),
    ("PetoMeta", new[] { ("sn", exposed), ("sr", events), ("xn", control), ("xr", controlEvents) }, new Dictionary<string, object>(), "strata", "stratum {0}"),
    ("Mantel", new[] { ("sn", exposed), ("sr", events), ("xn", control), ("xr", controlEvents) }, new Dictionary<string, object>(), "strata", "stratum {0}"),
    ("MetaIncidenceRateRatio", new[] { ("pt1", exposed), ("a", events), ("pt2", control), ("b", controlEvents) }, new Dictionary<string, object>(), "strata", "stratum {0}"),
    ("MetaIncidenceRateDifference", new[] { ("pt1", exposed), ("a", events), ("pt2", control), ("b", controlEvents) }, new Dictionary<string, object>(), "strata", "stratum {0}"),
    ("Effect", new[] { ("en", new double[] { 34, 50, 39, 24, 41, 28 }), ("cn", new double[] { 39, 44, 35, 29, 48, 36 }), ("em", new double[] { 11, 8, 9, 10, 14, 13 }),
        ("es", new[] { 2.1, 2.5, 2.8, 3.4, 2.2, 2.6 }), ("cm", new double[] { 8, 10, 9, 8, 11, 8 }), ("cs", new[] { 1.8, 2, 3.1, 3.2, 2.9, 2.4 }) },
        new Dictionary<string, object> { ["type"] = "d", ["g"] = null }, "strata", "stratum {0}"),
    ("MetaSummary", new[] { ("y", new[] { .05, -.02, .10, .03, .08, -.04 }), ("se_y", new[] { .03, .04, .05, .02, .06, .03 }) },
        new Dictionary<string, object> { ["type"] = "riskDifference", ["use_ci"] = "false" }, "studies", "study {0}"),
    ("ProportionMeta", new[] { ("sn", exposed), ("sr", events) }, new Dictionary<string, object> { ["method"] = "arcsine" }, "strata", "stratum {0}")
};
foreach (var (operation, columns, settings, labels, format) in cases)
foreach (bool labelled in new[] { false, true })
{
    // the third row is blank in every column, so the analysis keeps five studies; with labels, the fifth row's is blank
    var inputs = new ParameterBag();
    inputs.AddInput("gamma", .95);
    foreach (var setting in settings) if (setting.Value is string text) inputs.AddInput(setting.Key, text);
    foreach (var column in columns) inputs.AddInput(column.name, F(column.values.Select((v, i) => i == 2 ? Constant.MISSING : v).ToArray()));
    if (labelled)
    {
        var names = new DataFrame();
        names.Variables.Add(new StringVariable(new[] { "Alpha", "Beta", "Gamma", "Delta", "", "Zeta" }, "Study names"));
        inputs.AddInput(labels, names);
    }
    ParameterBag bag = Run(operation, inputs);
    string[] expected = labelled ? new[] { "Alpha", "Beta", "Delta", string.Format(inv, format, 4), "Zeta" }
        : Enumerable.Range(1, 5).Select(i => string.Format(inv, format, i)).ToArray();
    var titles = new List<IList<string>>();
    foreach (ParameterBag chart in Meta539Rows(bag, "*chart"))
        if (chart.TryGetValue("chart", out FilledParameter value) && value.AsObject is StatsDirect.Charting.ChartDefinition definition)
        {
            if (definition.ChartOptions is StatsDirect.Charting.ForestishOptions forest) titles.Add(forest.Titles);
            else if (definition.ChartOptions is StatsDirect.Charting.CorrelationOptions correlation) titles.Add(correlation.Titles);
        }
    string label = operation + (labelled ? " with a blank label" : " without labels");
    Console.WriteLine("FOREST\t" + (titles.Count >= 1 && titles.All(t => t.Skip(1).Take(5).SequenceEqual(expected)) ? "1" : "0") + "\t"
        + label + ": the native forest plots label the kept studies " + string.Join(", ", expected) + " after a blank row"
        + (titles.Count > 0 ? "" : " (no forest plot)") + string.Concat(titles.Where(t => !t.Skip(1).Take(5).SequenceEqual(expected)).Take(1).Select(t => " [drawn: " + string.Join(", ", t.Skip(1).Take(5)) + "]"))
        + "\t" + operation + "\t" + B64(given) + "\t" + B64(string.Join(",", expected)));
}
'''

BIAS = r'''
double[][] two = { new double[] { 30, 120, 15, 110 }, new double[] { 12, 90, 20, 95 } };
double[][] three = { new double[] { 10, 50, 12, 50 }, new double[] { 25, 60, 10, 60 }, new double[] { 14, 70, 15, 70 } };
double[][] six = { new double[] { 20, 100, 12, 100 }, new double[] { 35, 150, 20, 140 }, new double[] { 10, 80, 12, 90 },
    new double[] { 60, 200, 30, 210 }, new double[] { 50, 120, 15, 115 }, new double[] { 23, 110, 18, 125 } };
// effect sizes, summary statistics, correlations and proportions: two studies that differ, three, and six
int[][] subsets = { new[] { 0, 4 }, new[] { 0, 1, 2 }, new[] { 0, 1, 2, 3, 4, 5 } };
double[] en = { 27, 16, 25, 62, 9, 63 }, em = { 18.5, 60, 10.72, 9.2, 3.75, 60 }, es = { 14.9, 29.2, 6.46, 6.16, 2.55, 13.3 };
double[] cn = { 17, 15, 66, 66, 22, 40 }, cm = { 5.4, 55, 6.92, 6.92, 1.05, 46.3 }, cs = { 17.3, 29.2, 6.83, 6.83, 2.12, 18.6 };
double[] y = { 1.5, .8, 2, 1.15, 2.6, 1.3 }, se = { .12, .18, .21, .15, .25, .2 };
double[] r = { .3, .52, .1, .45, .21, .6 }, n = { 50, 80, 40, 120, 60, 90 };
double[] total = { 311, 65, 67, 285, 73, 116 }, responders = { 214, 58, 59, 182, 65, 66 };
var analyses = new (string operation, string begg, bool harbord, string block)[]
{
    ("RelativeRiskMeta", "kt", true, "*egger"), ("RiskDifference", "begg", false, "*egger"), ("PetoMeta", "begg", true, "*egger"),
    ("Mantel", "begg", true, "*egger"), ("MantelHaenszelScreen", "begg", true, "*egger"), ("Effect", "begg", false, "*egger"),
    ("MetaSummary", "kt", false, "*bias"), ("MetaCorrelation", "bm", false, "*bias"), ("ProportionMeta", "begg", true, "*egger")
};
foreach (var (operation, beggName, harbord, block) in analyses)
{
    bool twoStudyInterval = false;
    for (int set = 0; set < 3; set++)
    foreach (double confidence in new[] { .8, .95, .99 })
    foreach (bool exact in new[] { false, true })
    {
        host.Preferences.MetaExact = exact;
        string label = operation + "-" + (set == 0 ? 2 : set == 1 ? 3 : 6) + "-studies-" + (exact ? "exact" : "approximate") + "-" + confidence.ToString(inv);
        // two studies that differ
        int[] take = set > 0 ? subsets[set] : operation == "Effect" ? new[] { 3, 4 } : operation == "MetaCorrelation" ? new[] { 2, 5 } : subsets[0];
        double[][] tables = set == 0 ? two : set == 1 ? three : six;
        double[] Pick(double[] values) => take.Select(i => values[i]).ToArray();
        var inputs = new ParameterBag();
        if (operation != "MantelHaenszelScreen") inputs.AddInput("gamma", confidence);
        switch (operation)
        {
            case "MantelHaenszelScreen":
                inputs.AddInput("cco", confidence); inputs.AddInput("try_exact", exact); inputs.AddInput("plot_forest", false);
                inputs.AddInput("data", F(tables.SelectMany(t => new[] { t[0], t[1] - t[0] }).ToArray(), tables.SelectMany(t => new[] { t[2], t[3] - t[2] }).ToArray()));
                break;
            case "Effect":
                inputs.AddInput("type", "d");
                inputs.AddInput("en", F(Pick(en))); inputs.AddInput("em", F(Pick(em))); inputs.AddInput("es", F(Pick(es)));
                inputs.AddInput("cn", F(Pick(cn))); inputs.AddInput("cm", F(Pick(cm))); inputs.AddInput("cs", F(Pick(cs)));
                break;
            case "MetaSummary":
                inputs.AddInput("type", "oddsRatio"); inputs.AddInput("use_ci", "false");
                inputs.AddInput("y", F(Pick(y))); inputs.AddInput("se_y", F(Pick(se)));
                break;
            case "MetaCorrelation":
                inputs.AddInput("r", F(Pick(r))); inputs.AddInput("n", F(Pick(n)));
                break;
            case "ProportionMeta":
                inputs.AddInput("method", "arcsine"); inputs.AddInput("sn", F(Pick(total))); inputs.AddInput("sr", F(Pick(responders)));
                break;
            default:
                // in the order the analysis asks for them, which is the order of its record: totals before events
                inputs.AddInput("sn", F(tables.Select(t => t[1]).ToArray())); inputs.AddInput("sr", F(tables.Select(t => t[0]).ToArray()));
                inputs.AddInput("xn", F(tables.Select(t => t[3]).ToArray())); inputs.AddInput("xr", F(tables.Select(t => t[2]).ToArray()));
                break;
        }
        ParameterBag bag = Run(operation, inputs);
        var checks = new System.Text.StringBuilder();
        checks.Append(Meta539Compare("I-squared", "i2", new[] { Meta539Find(bag, "isq") }))
              .Append(Meta539Compare("I-squared interval", "i2_ci", new[] { Meta539Find(bag, "llisq"), Meta539Find(bag, "ulisq") }, 1e-6));
        if (set == 0 && !exact)
        {
            if (Meta539Find(bag, "qc") > 2 == (Meta539Find(bag, "llisq") != Constant.MISSING))
                Check(true, label + ": two studies have the test-based I-squared interval exactly when Q > k");
            else Failure(label + ": the native report gives Q = " + Meta539Find(bag, "qc").ToString("R", inv) + " and the interval " +
                Meta539Value(Meta539Find(bag, "llisq")) + " to " + Meta539Value(Meta539Find(bag, "ulisq")));
            twoStudyInterval |= Meta539Find(bag, "llisq") != Constant.MISSING;
        }
        // the printed lines, as a reader sees them: the sentence of the report in place of the indicators, or Egger's and
        // Harbord's limits at the report's level
        void Printed(string line, ParameterBag figures, string level) =>
            checks.Append("line <- grep('^").Append(line).Append(": bias = ', printed, value = TRUE)\n")
                  .Append("expected <- paste0('(', ").Append(Meta539Value(Math.Round(Meta539Number(figures, level), 2))).Append(", '% CI = ', six(")
                  .Append(Meta539Value(Meta539Number(figures, "cl"))).Append("), ' to ', six(").Append(Meta539Value(Meta539Number(figures, "cu"))).Append("), ')')\n")
                  .Append("if (length(line) != 1 || !grepl(expected, line, fixed = TRUE)) stop('the printed ").Append(line)
                  .Append(" line differs: ', paste(line, collapse = ' | '), ' against ', expected)\n");
        if (Meta539Rows(bag, "*fewStrata").Count == 1)
            checks.Append("if (exists('egger_figures', inherits = FALSE) || exists('").Append(beggName)
                  .Append("', inherits = FALSE) || any(grepl('^Egger: ', printed))) stop('the replay gives bias indicators that the report withholds')\n")
                  .Append("if (!any(printed == 'Bias indicators need more than three studies with an estimate')) stop('the replay does not say why there are no bias indicators')\n");
        else
        {
            ParameterBag egger = Meta539Rows(bag, block)[0];
            checks.Append(Meta539Compare("Begg-Mazumdar", beggName + "$estimate, " + beggName + "$p.value", new[] { "tau", "p2" }.Select(key => Meta539Number(egger, key))));
            Printed("Egger", egger, "pc_egger");
            checks.Append(Meta539Compare("Egger", "egger_figures", new[] { "a", "cl", "cu", "p" }.Select(key => Meta539Number(egger, key))))
                  .Append(Meta539Compare("bias test level", "100 * bias_level", new[] { Meta539Number(egger, "pc_egger") }));
            if (harbord)
            {
                ParameterBag h = Meta539Rows(bag, "*harbord")[0];
                Printed(operation == "ProportionMeta" ? "Harbord" : "Harbord-Egger", h, "pc_harbord");
                checks.Append(Meta539Compare("Harbord", "harbord_figures", new[] { "a", "cl", "cu", "p" }.Select(key => Meta539Number(h, key))))
                      .Append(Meta539Compare("Harbord level", "100 * bias_level", new[] { Meta539Number(h, "pc_harbord") }));
            }
        }
        Check(set == 2 == (Meta539Rows(bag, "*fewStrata").Count == 0), label + ": the native report gives bias indicators only with more than three studies");
        Replay("bias/" + operation, label, " replays its recorded studies", true, operation, bag, checks.ToString());
    }
    if (twoStudyInterval) Check(true, operation + ": the two studies, which differ (Q > k), have the test-based I-squared interval in the report and the replay");
    else Failure(operation + ": the two studies, which differ (Q > k), have no test-based I-squared interval");
}
'''

SUMMARY = r'''
double[] y = { .05, -.02, .10, .03, .08, -.04 }, se = { .03, .04, .05, .02, .06, .03 };
foreach (string type in new[] { "riskDifference", "otherDifference" })
foreach (bool limits in new[] { false, true })
foreach (bool exact in new[] { false, true })
foreach (double confidence in new[] { .9, .95 })
{
    host.Preferences.MetaExact = exact;
    string label = "MetaSummary-" + type + (limits ? "-limits-" : "-se-") + (exact ? "exact" : "approximate") + "-" + confidence.ToString(inv);
    double[] lower = y.Select((v, i) => v - 1.6 * se[i]).ToArray(), upper = y.Select((v, i) => v + 1.6 * se[i]).ToArray();
    var inputs = new ParameterBag();
    inputs.AddInput("gamma", confidence); inputs.AddInput("type", type); inputs.AddInput("use_ci", limits ? "true" : "false"); inputs.AddInput("y", F(y));
    if (limits) { inputs.AddInput("ll_y", F(lower)); inputs.AddInput("ul_y", F(upper)); }
    else inputs.AddInput("se_y", F(se));
    ParameterBag bag = Run("MetaSummary", inputs);
    string stat = Convert.ToString(bag["stat"].AsObject, inv);
    string checks = Meta539Compare("fixed effects", "back(pooled), back(pooled + c(-1, 1) * z * se_pooled), z_fixed", new[] { "rmh", "from_fixed", "to_fixed", "z" }.Select(key => Meta539Number(bag, key)))
        + Meta539Compare("random effects", "back(pooled_dl), back(pooled_dl + c(-1, 1) * z * se_dl), z_dl", new[] { "dsrr", "dsll", "dsul", "dz" }.Select(key => Meta539Number(bag, key)))
        + Meta539Compare("heterogeneity", "q, tau2, i2", new[] { "qc", "tausq", "isq" }.Select(key => Meta539Number(bag, key)))
        + Meta539Compare("study limits", "lower, upper", Meta539Rows(bag, "*studies").Select(row => Meta539Number(row, "from")).Concat(Meta539Rows(bag, "*studies").Select(row => Meta539Number(row, "to"))))
        + Meta539Compare("Egger", "egger_figures", new[] { "a", "cl", "cu", "p" }.Select(key => Meta539Number(Meta539Rows(bag, "*bias")[0], key)))
        + "if (ratio || stat != " + StatsDirect.R.RScriptWriter.Vector(new object[] { stat }) + ") stop('the summary statistic is not ', " + StatsDirect.R.RScriptWriter.Vector(new object[] { stat }) + ")\n"
        + "printed <- capture.output(forest(w, pooled, se_pooled, 'check'))\n"
        + "if (!identical(par('xlog'), FALSE)) stop('a difference is drawn on a logarithmic axis')\n";
    Replay("summary-differences", label, " replays its acquired summaries", false, "MetaSummary", bag, checks);
}
'''

EMPTY = r'''
// events and total of the first group, events and total of the second, one row for each study
var sets = new (string name, double[][] rows)[]
{
    ("one.sided", new[] { new double[] { 10, 10, 0, 10 }, new double[] { 12, 50, 8, 50 }, new double[] { 20, 60, 15, 60 }, new double[] { 9, 40, 10, 40 } }),
    ("one.sided.control", new[] { new double[] { 0, 10, 10, 10 }, new double[] { 12, 50, 8, 50 }, new double[] { 20, 60, 15, 60 }, new double[] { 9, 40, 10, 40 } }),
    ("single.zero", new[] { new double[] { 0, 50, 4, 50 }, new double[] { 5, 60, 9, 60 }, new double[] { 8, 70, 10, 70 }, new double[] { 12, 80, 15, 80 } }),
    ("sparse01", new[] { new double[] { 0, 10, 0, 9 }, new double[] { 1, 29, 2, 11 }, new double[] { 0, 6, 1, 5 } }),
    ("sparse02", new[] { new double[] { 2, 19, 0, 8 }, new double[] { 1, 28, 3, 29 }, new double[] { 0, 17, 2, 11 }, new double[] { 0, 5, 1, 6 },
        new double[] { 0, 12, 0, 9 }, new double[] { 0, 10, 0, 5 }, new double[] { 0, 5, 1, 7 }, new double[] { 3, 23, 0, 6 } }),
    ("sparse05", new[] { new double[] { 0, 8, 3, 34 }, new double[] { 1, 14, 2, 8 }, new double[] { 0, 14, 0, 32 }, new double[] { 3, 31, 0, 15 },
        new double[] { 0, 10, 0, 8 }, new double[] { 1, 15, 3, 34 }, new double[] { 0, 17, 2, 8 }, new double[] { 0, 18, 0, 15 } }),
    ("sparse12", new[] { new double[] { 0, 7, 0, 33 }, new double[] { 0, 33, 0, 5 }, new double[] { 1, 16, 0, 8 }, new double[] { 0, 9, 1, 11 }, new double[] { 1, 7, 0, 11 } }),
    ("none.second", new[] { new double[] { 14, 23, 0, 26 }, new double[] { 3, 14, 0, 12 }, new double[] { 11, 29, 0, 30 }, new double[] { 9, 38, 0, 61 },
        new double[] { 10, 37, 0, 58 }, new double[] { 3, 26, 0, 76 } }),
    ("none.first", new[] { new double[] { 0, 22, 8, 65 }, new double[] { 0, 44, 15, 55 }, new double[] { 0, 120, 7, 32 }, new double[] { 0, 12, 3, 14 },
        new double[] { 0, 10, 9, 21 }, new double[] { 0, 63, 5, 21 } }),
    ("all.first", new[] { new double[] { 11, 11, 19, 69 }, new double[] { 48, 48, 5, 27 }, new double[] { 17, 17, 9, 41 }, new double[] { 76, 76, 28, 87 },
        new double[] { 32, 32, 3, 22 }, new double[] { 11, 11, 4, 23 } }),
    ("double.zero", new[] { new double[] { 15, 35, 10, 33 }, new double[] { 0, 52, 0, 53 }, new double[] { 3, 15, 48, 176 }, new double[] { 18, 30, 6, 23 },
        new double[] { 0, 28, 0, 30 }, new double[] { 22, 90, 3, 19 }, new double[] { 9, 15, 22, 58 } }),
    ("double.all", new[] { new double[] { 12, 35, 5, 21 }, new double[] { 8, 15, 7, 19 }, new double[] { 15, 15, 19, 19 }, new double[] { 16, 34, 7, 14 },
        new double[] { 1, 20, 4, 24 }, new double[] { 15, 40, 37, 75 }, new double[] { 8, 30, 10, 47 } }),
    ("one.each", new[] { new double[] { 16, 57, 6, 21 }, new double[] { 1, 1, 0, 1 }, new double[] { 4, 17, 8, 19 }, new double[] { 20, 54, 7, 27 }, new double[] { 3, 12, 36, 99 } }),
    ("empty.group", new[] { new double[] { 59, 172, 12, 35 }, new double[] { 11, 45, 23, 63 }, new double[] { 49, 148, 27, 42 }, new double[] { 0, 0, 3, 10 }, new double[] { 8, 40, 27, 63 } }),
    ("one.subject", new[] { new double[] { 1, 1, 0, 0 }, new double[] { 4, 17, 8, 32 }, new double[] { 13, 43, 25, 53 }, new double[] { 8, 25, 10, 41 }, new double[] { 1, 13, 6, 21 } }),
    // given the margins, the total of the a cells is exactly as probable at 10 as at the observed 3 (7056 ways each), so
    // the exact two sided P counts both, as the report does, whatever the rounding of the two probabilities
    ("tied.total", new[] { new double[] { 0, 6, 6, 9 }, new double[] { 3, 9, 2, 2 } })
};
var settings = new (bool exact, double cc, bool delay, double level)[]
{
    (true, -9, false, .95), (false, -9, false, .95), (true, .5, false, .9), (false, .5, false, .99),
    (true, .01, false, .99), (false, .01, false, .9), (true, -9, true, .95), (false, .5, true, .95), (false, -9, true, .9)
};
// the typed-in Mantel-Haenszel test pools the tables as the odds ratio meta-analysis does, with the exact methods of its
// own option: each table's exposed and unexposed columns, cases above non-cases
string operation = "@OPERATION";
foreach (var setting in settings)
{
    // the Peto odds ratio has no continuity correction, so it needs only the two methods
    if (operation == "PetoMeta" && (setting.cc != -9 || setting.delay)) continue;
    host.Preferences.MetaExact = setting.exact; host.Preferences.MetaCC = setting.cc; host.Preferences.DelayContinuityCorrection = setting.delay;
    string settingLabel = (setting.exact ? "exact" : "approximate") + "-cc" + setting.cc.ToString(inv) + (setting.delay ? "-delayed" : "") + "-" + setting.level.ToString(inv);
    foreach (var (name, rows) in sets)
    {
        string label = operation + "-" + name + "-" + settingLabel;
        var inputs = new ParameterBag();
        if (operation == "MantelHaenszelScreen")
        {
            inputs.AddInput("cco", setting.level); inputs.AddInput("try_exact", setting.exact); inputs.AddInput("plot_forest", false);
            inputs.AddInput("data", F(rows.SelectMany(r => new[] { r[0], r[1] - r[0] }).ToArray(), rows.SelectMany(r => new[] { r[2], r[3] - r[2] }).ToArray()));
        }
        else
        {
            inputs.AddInput("gamma", setting.level);
            // in the order the analysis asks for them, which is the order of its record: totals before events
            inputs.AddInput("sn", F(rows.Select(r => r[1]).ToArray())); inputs.AddInput("sr", F(rows.Select(r => r[0]).ToArray()));
            inputs.AddInput("xn", F(rows.Select(r => r[3]).ToArray())); inputs.AddInput("xr", F(rows.Select(r => r[2]).ToArray()));
        }
        ParameterBag bag;
        try { bag = Run(operation, inputs); }
        catch (Exception ex)
        {
            // every set has a study that can be pooled, so the native analysis must complete
            Failure(label + ": the native analysis refuses it (" + ex.GetBaseException().Message + ")");
            continue;
        }
        Replay("empty-cells/" + operation + "-" + settingLabel, label, " replays the acquired tables", false, operation,
            bag, Meta539Assertions(operation == "MantelHaenszelScreen" ? "Mantel" : operation, bag));
    }
}
'''

LIMITS = r'''
var proportions = new (string name, double[] n, double[] r)[]
{
    ("no-responder-equal", new double[] { 20, 20, 20, 20, 20 }, new double[] { 0, 0, 0, 0, 0 }),
    ("no-responder", new double[] { 12, 20, 35, 50, 80 }, new double[] { 0, 0, 0, 0, 0 }),
    ("all-responders-equal", new double[] { 20, 20, 20, 20, 20 }, new double[] { 20, 20, 20, 20, 20 }),
    ("all-responders", new double[] { 12, 20, 35, 50, 80 }, new double[] { 12, 20, 35, 50, 80 }),
    ("one-responder", new double[] { 12, 20, 35, 50, 80 }, new double[] { 0, 0, 1, 0, 0 }),
    ("ordinary", new double[] { 311, 65, 67, 285, 73, 116 }, new double[] { 214, 58, 59, 182, 65, 66 })
};
foreach (var (name, n, r) in proportions)
foreach (string method in new[] { "arcsine", "doubleArcsine" })
foreach (double confidence in new[] { .95, .8 })
foreach (bool exact in new[] { false, true })
{
    host.Preferences.MetaExact = exact;
    string label = "ProportionMeta-" + name + "-" + method + "-" + confidence.ToString(inv) + (exact ? "-exact" : "");
    var inputs = new ParameterBag();
    inputs.AddInput("gamma", confidence); inputs.AddInput("method", method); inputs.AddInput("sn", F(n)); inputs.AddInput("sr", F(r));
    ParameterBag bag = Run("ProportionMeta", inputs);
    ParameterBag egger = Meta539Rows(bag, "*egger").Single(), harbord = Meta539Rows(bag, "*harbord").Single();
    IEnumerable<double> Figures(params string[] keys) => keys.Select(key => Meta539Number(bag, key));
    string checks = "if (!identical(grep('^Pooled proportion = ', printed, value = TRUE)[1], paste0('Pooled proportion = ', six(" + Meta539Value(Meta539Number(bag, "rmh"))
        + "), ' (', pct, 'CI = ', six(" + Meta539Value(Meta539Number(bag, "from")) + "), ' to ', six(" + Meta539Value(Meta539Number(bag, "to"))
        + "), ')'))) stop('the printed fixed effects line differs: ', grep('^Pooled proportion = ', printed, value = TRUE)[1])\n"
        + Meta539Compare("fixed effects", "fixed", Figures("rmh", "from", "to"))
        + Meta539Compare("random effects", "inv(xr), inv(xr - z * se_r), inv(xr + z * se_r)", Figures("dspr", "from_ds", "to_ds"))
        + Meta539Compare("heterogeneity", "q, tau2, i2", Figures("qc", "tausq", "isq"))
        + Meta539Compare("I-squared interval", "i2_ci", Figures("llisq", "ulisq"), 1e-6)
        + Meta539Compare("study limits", "ci[, 1], ci[, 2]", Meta539Rows(bag, "*proportions").Select(row => Meta539Number(row, "from_y"))
            .Concat(Meta539Rows(bag, "*proportions").Select(row => Meta539Number(row, "to_y"))))
        + Meta539Compare("Begg-Mazumdar", "begg$estimate, begg$p.value", new[] { "tau", "p2" }.Select(key => Meta539Number(egger, key)))
        + Meta539Compare("Egger", "egger_figures", new[] { "a", "cl", "cu", "p" }.Select(key => Meta539Number(egger, key)))
        + Meta539Compare("Harbord", "harbord_figures", new[] { "a", "cl", "cu", "p" }.Select(key => Meta539Number(harbord, key)))
        + "if (sum(grepl('^Harbord: bias = ', printed)) != 1 || sum(grepl('^Egger: bias = ', printed)) != 1) stop('the replay prints the Egger and Harbord lines other than once each')\n";
    Replay("limits", label, " replays its acquired studies", true, "ProportionMeta", bag, checks);
}

// every one of the five types of summary statistic, with all of its limits, or two of them, selected the wrong way round
foreach (string type in new[] { "oddsRatio", "relativeRisk", "otherRatio", "riskDifference", "otherDifference" })
foreach (bool all in new[] { true, false })
foreach (bool exact in new[] { false, true })
{
    host.Preferences.MetaExact = exact;
    bool ratio = type.EndsWith("Ratio", StringComparison.Ordinal) || type == "relativeRisk";
    double[] y = ratio ? new[] { 1.5, .8, 2, 1.15, 2.6, 1.3 } : new[] { .05, -.02, .10, .03, .08, -.04 };
    double[] se = { .12, .18, .21, .15, .25, .2 };
    double[] lower = y.Select((v, i) => ratio ? Math.Exp(Math.Log(v) - 1.959964 * se[i]) : v - 1.959964 * se[i]).ToArray();
    double[] upper = y.Select((v, i) => ratio ? Math.Exp(Math.Log(v) + 1.959964 * se[i]) : v + 1.959964 * se[i]).ToArray();
    double[] first = lower.Select((v, i) => all || i % 3 == 1 ? upper[i] : v).ToArray(), second = upper.Select((v, i) => all || i % 3 == 1 ? lower[i] : v).ToArray();
    string label = "MetaSummary-" + type + (all ? "-all" : "-some") + "-limits-reversed" + (exact ? "-exact" : "");
    var inputs = new ParameterBag();
    inputs.AddInput("gamma", .95); inputs.AddInput("type", type); inputs.AddInput("use_ci", "true");
    inputs.AddInput("y", F(y)); inputs.AddInput("ll_y", F(first)); inputs.AddInput("ul_y", F(second));
    ParameterBag bag = Run("MetaSummary", inputs);
    IList<ParameterBag> studies = Meta539Rows(bag, "*studies");
    ParameterBag bias = Meta539Rows(bag, "*bias").Single();
    string checks = Meta539Compare("Egger", "egger_figures", new[] { "a", "cl", "cu", "p" }.Select(key => Meta539Number(bias, key)))
        + Meta539Compare("study limits and standard errors", "lower, upper, se", studies.Select(row => Meta539Number(row, "from"))
            .Concat(studies.Select(row => Meta539Number(row, "to"))).Concat(studies.Select(row => Meta539Number(row, "se"))))
        + Meta539Compare("fixed effects", "back(pooled), back(pooled + c(-1, 1) * z * se_pooled), z_fixed", new[] { "rmh", "from_fixed", "to_fixed", "z" }.Select(key => Meta539Number(bag, key)))
        + Meta539Compare("random effects", "back(pooled_dl), back(pooled_dl + c(-1, 1) * z * se_dl), z_dl", new[] { "dsrr", "dsll", "dsul", "dz" }.Select(key => Meta539Number(bag, key)))
        + Meta539Compare("heterogeneity", "q, tau2, i2, i2_ci", new[] { "qc", "tausq", "isq", "llisq", "ulisq" }.Select(key => Meta539Number(bag, key)), 1e-6)
        + Meta539Compare("Begg-Mazumdar", "kt$estimate, kt$p.value", new[] { "tau", "p2" }.Select(key => Meta539Number(bias, key)));
    Replay("limits", label, " replays its acquired summaries", false, "MetaSummary", bag, checks);
}
'''

EMPTY_OPERATIONS = ('RelativeRiskMeta', 'RiskDifference', 'PetoMeta', 'Mantel', 'MantelHaenszelScreen')
SCRIPTS = {
    'forest': [('forest', FOREST)],
    'bias': [('bias', BIAS)],
    'summary': [('summary', SUMMARY)],
    'empty': [('empty ' + operation, EMPTY.replace('@OPERATION', operation)) for operation in EMPTY_OPERATIONS],
    'limits': [('limits', LIMITS)],
}
VERDICTS = {
    'bias': 'bias indicator replays disagree with the native analysis',
    'summary': 'summary difference replays disagree with the native analysis',
    'empty': 'empty-cell replays disagree with the native analysis',
    'limits': 'replays at the limits of their data disagree with the native analysis',
}


def native(session, name, code):
    """One C# script in the operation host: the console lines of its checks, failures and replays."""
    ident = str(uuid.uuid4())
    try:
        started = session.request(action='start', id=ident, operation='UserScript', language='CSharp',
                                  script=PRELUDE + code + '\nConsole.WriteLine("DONE");\n', preferences=dict(PREFERENCES))
        if started.get('error'):
            raise AssertionError('FAIL the C# script of %s did not start: %s' % (name, started['error']))
        state = session.wait(ident)
    finally:
        session.close(ident)
    lines = (state.get('console') or '').splitlines()
    if state.get('state') != 'complete' or 'DONE' not in lines:
        raise AssertionError('FAIL the C# script of %s: %s %s\n%s' % (name, state.get('state'), state.get('error'), '\n'.join(lines)[-3000:]))
    return lines


def decoded(text):
    return base64.b64decode(text).decode('utf-8')


def number(text):
    if text == '':
        return None   # a blank cell
    value = float(text)
    return int(value) if value == int(value) else value


def asked(text):
    """The answers and the calculation options of a run of the C# script, for the same run at the operation's prompts: the confidence
    level as the prompt takes it, a percentage, and each frame as a worksheet selection."""
    answers, preferences = {}, dict(PREFERENCES)
    for item in text.split('|'):
        name, _, value = item.partition('=')
        kind, value = value[0], value[2:]
        if kind == 'd':
            value = number(value)
        elif kind == 'b':
            value = value == '1'
        elif kind == 'f':
            columns = [[number(v) for v in column.split(',')] for column in value.split(';')]
            value = sheet(['Column %d' % (i + 1) for i in range(len(columns))], columns)
        elif kind == 'l':
            value = sheet(['Study names'], [[v or None for v in value.split(',')]])
        if name.startswith('!'):
            preferences[name[1:]] = value
        else:
            answers[name] = value
    for name in ('gamma', 'cco'):
        if name in answers:
            answers[name] = number(repr(round(100 * answers[name], 8)))
    return answers, preferences


def prompted(session, operation, answers, preferences):
    """The operation through the Mac host's prompts, each answered by its name, as Windows's checking host answers its parameters.
    Returns (state, None) for a finished run, and (None, why) when the Mac's picker refuses a selection or the run does not finish."""
    ident, state = session.start(operation, preferences)
    try:
        for _ in range(100):
            if state.get('state') != 'input':
                break
            prompt = state['prompt']
            name = prompt.get('name')
            if prompt.get('error'):
                return None, '%s: %s' % (name, prompt['error'])
            if name not in answers and name not in OPTIONAL:
                raise AssertionError('FAIL %s asked for %s (%s), which these checks do not answer' % (operation, name, prompt.get('kind')))
            session.request(action='answer', id=ident, token=state['token'], value=answers.get(name, SKIP))
            state = session.wait(ident)
    finally:
        session.close(ident)
    if state.get('state') != 'complete' or not state.get('record'):
        return None, 'the run ended %s: %s' % (state.get('state'), state.get('error'))
    return state, None


LABEL = re.compile(r'^(?:(?:stratum|study) \d+|Alpha|Beta|Gamma|Delta|Zeta)$')


def forest_labels(html):
    """The study labels drawn in each plot of a report that draws any, from the top of the plot down."""
    plots = []
    for svg in re.findall(r'<svg\b.*?</svg>', html, flags=re.S):
        texts = [re.sub(r'<[^>]+>', '', text).strip() for text in re.findall(r'<text\b[^>]*>(.*?)</text>', svg, flags=re.S)]
        labels = [text for text in texts if LABEL.match(text)]
        if labels:
            plots.append(labels[::-1])   # a forest plot is drawn from its last study up
    return plots


def vector(text, name):
    """The numbers of a variable the R script sets from the record's data, or None if it does not set it so."""
    found = re.search(r'^%s <- c\(([^()]*)\)' % re.escape(name), text, flags=re.M)
    try:
        return [float(value) for value in found.group(1).split(',')] if found else None
    except ValueError:
        return None


def run_batch(folder, replays):
    """Meta539Batch's R process: the replays one after another, each in its own environment, with a mark for each that completes."""
    code = 'pdf(NULL)\n' + SAME + '\n'
    for label, replay in replays:
        code += ('local(tryCatch({\n' + replay + "\ncat('META_539_OK " + label + "\\n')\n"
                 + "}, error = function(e) cat('META_539_ERROR " + label + ": ', conditionMessage(e), '\\n', sep = '')))\n")
    folder.mkdir(parents=True, exist_ok=True)
    script = folder / 'script.R'
    script.write_text(code, encoding='utf-8')
    environment = dict(os.environ)
    for name in ('LC_ALL', 'LC_CTYPE'):
        if environment.get(name) == 'C.UTF-8':
            environment.pop(name)
    try:
        result = subprocess.run([RSCRIPT, '--vanilla', '--encoding=UTF-8', str(script)], cwd=folder, env=environment,
                                capture_output=True, text=True, timeout=600)
    except subprocess.TimeoutExpired:
        return 'R exceeded 600 seconds\n'
    (folder / 'stdout.txt').write_text(result.stdout)
    (folder / 'stderr.txt').write_text(result.stderr)
    return result.stdout.replace('\r\n', '\n')


def part(session, writer, name, folder):
    before, failed_before = checks + len(failed), len(failed)
    batches, failures, at_prompts, refusals = {}, [], 0, []
    for script_name, code in SCRIPTS[name]:
        for line in native(session, script_name, code):
            fields = line.split('\t')
            if fields[0] == 'CHECK':
                check(fields[1] == '1', fields[2])
            elif fields[0] == 'FAILURE':
                failures.append(fields[1])
            elif fields[0] == 'FOREST':
                # Windows's check, on the chart definitions of the builtin's bag, and the same labels as they are drawn in the report
                # of the same run at the operation's prompts, where the blank row and the blank label are worksheet cells
                ok, what, operation, given, expected = fields[1] == '1', fields[2], fields[3], decoded(fields[4]), decoded(fields[5]).split(',')
                state, refusal = prompted(session, operation, *asked(given))
                if state is None:
                    # only the refusal that is known and shared with Windows leaves the check to the chart definitions
                    drawn, shown = [], REFUSED_AT_PROMPTS.get(operation) == refusal
                    refusals.append('%s (%s)' % (what.split(':')[0], refusal))
                else:
                    drawn = forest_labels(state.get('html') or '')
                    shown = bool(drawn) and all(labels == expected for labels in drawn)
                    at_prompts += 1
                check(ok and shown, what + ('' if shown else ' [in the report of the run at the prompts: %s]' % (
                    refusal or '; '.join(', '.join(labels) for labels in drawn) or 'no forest plot')))
            elif fields[0] == 'REPLAY':
                batch, label, suffix, printed, record, assertions, operation, given = fields[1:]
                # the record of the real run: the operation at its own prompts, with the selection and options of the script's run
                # (Windows's Run); a selection the Mac's picker refuses has the record written from the bag instead
                state, refusal = prompted(session, operation, *asked(decoded(given)))
                if state is None:
                    refusals.append('%s (%s)' % (label, refusal))
                    failures.append('%s: the run was not made at the operation\'s prompts (%s)' % (label, refusal))
                else:
                    at_prompts += 1
                script = writer.write(decoded(record) if state is None else state['record'])
                check(bool(script.get('hasRecipe')) and not script.get('dataUnavailable'), label + suffix)
                text = script.get('text') or ''
                if '-limits-reversed' in label:
                    # Windows's selection: every limit the wrong way round, or the second and the fifth study's. The script must
                    # hold them as they were selected, or the replay does not try the correction the script itself makes
                    lower, upper = vector(text, 'lower'), vector(text, 'upper')
                    if not (lower and upper and len(lower) == len(upper) == 6
                            and [a > b for a, b in zip(lower, upper)] == ['-all-' in label or i % 3 == 1 for i in range(6)]):
                        failures.append(label + ': the script does not hold the limits as they were selected, the wrong way round')
                if name == 'summary':
                    check('type <- "%s"' % label.split('-')[1] in text, label + ' records the type of the summary statistic')
                if name == 'empty':
                    if ('delay_cc <- ' in text) == (not label.startswith('PetoMeta-')):
                        check(True, label + ' replays with the recorded continuity correction')
                    else:
                        failures.append(label + ': the replay does not take the recorded continuity correction')
                if printed == '1':
                    replay = 'printed <- capture.output({\n' + text + "\n})\ncat(printed, sep = '\\n')\n" + decoded(assertions)
                else:
                    replay = text + '\n' + decoded(assertions)
                batches.setdefault(batch, []).append((label, replay))
    with concurrent.futures.ThreadPoolExecutor(max_workers=WORKERS) as pool:
        outputs = dict(zip(batches, pool.map(lambda batch: run_batch(folder / batch, batches[batch]), batches)))
    for batch, replays in batches.items():
        lines = outputs[batch].split('\n')
        for label, _ in replays:
            if 'META_539_OK ' + label in lines:
                check(True, label + ': the replay completes with the native figures')
            else:
                failures.append(next((line for line in lines if line.startswith('META_539_ERROR ' + label + ':')), label + ': no result'))
    if name in VERDICTS:
        # every disagreement is listed before the check fails, so that one run shows them all
        for failure in failures:
            print('      ' + failure, flush=True)
        check(not failures, '%d %s' % (len(failures), VERDICTS[name]))
    done = checks + len(failed) - before
    for refusal in refusals:
        print('      not run at the prompts%s: %s' % ('' if name == 'forest' else ', its record is written from the bag', refusal), flush=True)
    print('%s: %d checks (Windows has %d); %d of %d %s of the run at the operation\'s prompts' % (
        name, done, WINDOWS_CHECKS[name], at_prompts, at_prompts + len(refusals),
        'label checks also read the report' if name == 'forest' else 'replays are of the record'), flush=True)
    if len(failed) == failed_before and done != WINDOWS_CHECKS[name]:
        fail('the %s part made %d checks where Windows makes %d' % (name, done, WINDOWS_CHECKS[name]))


if __name__ == '__main__':
    wanted = [name for name in os.environ.get('STATSDIRECT_META_REVIEW_539_PARTS', ','.join(PARTS)).split(',') if name]
    if any(name not in PARTS for name in wanted):
        sys.exit('STATSDIRECT_META_REVIEW_539_PARTS names parts among ' + ', '.join(PARTS))
    (ROOT / '.build').mkdir(exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix='meta-review-539-', dir=ROOT / '.build'))
    session, writer = Session(), Writer()
    passed = False
    started = time.monotonic()
    try:
        for name in PARTS:
            if name in wanted:
                part(session, writer, name, temporary / name)
        passed = not failed
        if failed:
            print('FAIL: %d of %d meta-analysis review checks failed' % (len(failed), checks + len(failed)), flush=True)
    except Exception as error:
        message = str(error)
        print(message if message.startswith('FAIL') else 'FAIL ' + traceback.format_exc(), flush=True)
    finally:
        writer.close()
        session.finish()
    if not passed:
        print('Retained test artifacts: ' + str(temporary), flush=True)
        sys.exit(1)
    shutil.rmtree(temporary)
    print('PASS: %d meta-analysis review checks in %.0f seconds' % (checks, time.monotonic() - started), flush=True)
