using System;
using System.Collections.Generic;
using System.Text.Json;
using StatsDirect.Templates;

// The native host persists these six Analysis Options. Each running analysis
// holds its own snapshot, so changing defaults cannot change an open analysis.
internal static class AnalysisDefaults {
    internal static HeadlessPreferences Snapshot(SDPreferences p) => new() {
        CanDefaultConfidenceInterval=p.CanDefaultConfidenceInterval, DefaultConfidenceInterval=p.DefaultConfidenceInterval,
        DisplayDecimalPlaces=p.DisplayDecimalPlaces, PDecimalPlaces=p.PDecimalPlaces,
        UseScientificNotationForSmallPValues=p.UseScientificNotationForSmallPValues, SelectGroupsByIdentifier=p.SelectGroupsByIdentifier,
        MetaCC=p.MetaCC, MetaExact=p.MetaExact, MetaPlotCI=p.MetaPlotCI, MetaPlotMethod=p.MetaPlotMethod,
        DelayContinuityCorrection=p.DelayContinuityCorrection, ShouldUseColour=p.ShouldUseColour
    };
    internal static Dictionary<string, object> Values(SDPreferences p) => new() {
        ["use-default-ci"]=p.CanDefaultConfidenceInterval,
        ["default-ci"]=(p.DefaultConfidenceInterval*100).ToString(System.Globalization.CultureInfo.InvariantCulture),
        ["selectGroupsByIdentifier"]=p.SelectGroupsByIdentifier,
        ["decp"]=p.DisplayDecimalPlaces.ToString(), ["pdecp"]=p.PDecimalPlaces.ToString(),
        ["use-scientific-notation-for-small-p-values"]=p.UseScientificNotationForSmallPValues
    };
    internal static void Apply(SDPreferences target, JsonElement options) {
        if (options.ValueKind == JsonValueKind.Undefined || options.ValueKind == JsonValueKind.Null) return;
        if (options.ValueKind != JsonValueKind.Object) throw new ArgumentException("Invalid saved analysis options.");
        bool useDefault=options.GetProperty("use-default-ci").GetBoolean();
        double confidence=HostParameters.Number(options.GetProperty("default-ci"));
        int decimals=(int)HostParameters.Number(options.GetProperty("decp"));
        int pDecimals=(int)HostParameters.Number(options.GetProperty("pdecp"));
        bool groups=options.GetProperty("selectGroupsByIdentifier").GetBoolean();
        bool scientific=options.GetProperty("use-scientific-notation-for-small-p-values").GetBoolean();
        if (confidence is not (80 or 85 or 90 or 95 or 99) || decimals<2 || decimals>12 || pDecimals<3 || pDecimals>7)
            throw new ArgumentException("Invalid analysis defaults. Choose a listed confidence level and decimal precision.");
        if (groups) throw new ArgumentException("Selection by group identifier is not yet available on Mac. Use separate columns.");
        target.CanDefaultConfidenceInterval=useDefault; target.DefaultConfidenceInterval=confidence/100;
        target.DisplayDecimalPlaces=decimals; target.PDecimalPlaces=pDecimals;
        target.SelectGroupsByIdentifier=false; target.UseScientificNotationForSmallPValues=scientific;
    }
}
