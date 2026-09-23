using System;
using StatsDirect.Numerics;

namespace StatsDirect.Charting
{
    [Serializable]
    public class ControlOptions : GenericOptions
    {
        public bool UseMean { get; set; }
        public bool Use1SD { get; set; }
        public bool Use2SD { get; set; }
        public bool Use3SD { get; set; }
        public bool HasUserSpecifiedMeanAndSD { get; set; }
        public double UserSpecifiedMean { get; set; }
        public double UserSpecifiedSD { get; set; }
        public bool HasUserSpecifiedLimits { get; set; }
        public double LowerWarningLimit { get; set; } = Constant.MISSING;
        public double UpperWarningLimit { get; set; } = Constant.MISSING;
        public double LowerControlLimit { get; set; } = Constant.MISSING;
        public double UpperControlLimit { get; set; } = Constant.MISSING;
        public int ObservationsToUse { get; set; }
        public int RightHandDecimalPlaces { get; set; }

        public override bool ShowControlOptions => true;

        public override bool UsesAutoscale => true;

        public override bool UsesBoxAxes => true;

        public override bool UsesChartTitle => true;

        public override bool UsesXAxisTitle => true;

        public override bool UsesYAxisTitle => true;

        public override bool UsesAxisLabelFontDescriptor => true;

        public override bool UsesAxisTitleFontDescriptor => true;

        public override bool UsesLegendFontDescriptor => true;

        public override string LegendFontLabel => "Control Label";

        public override bool ShowLegendIsRelevant => false;

        public override void Accept(IChartOptionVisitor visitor)
        {
            visitor.Visit(this);
        }
    }
}
