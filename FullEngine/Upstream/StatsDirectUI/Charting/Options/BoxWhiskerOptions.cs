using System;
using StatsDirect.Utilities;

namespace StatsDirect.Charting
{
    [Serializable]
    public class BoxWhiskerOptions : GenericOptions
    {
        public enum BoxWhiskerMethod
        {
            MedianQuartilesRange = 1,
            MeanStandardDeviationRange = 2,
            MeanConfidenceIntervalRange = 3,
            SevenNumberSummary = 4,
            BowleySummary = 5,
            MeanStandardErrorRange = 6
        }

        public BoxWhiskerMethod Method = BoxWhiskerMethod.MedianQuartilesRange;
        public bool MarkMeanAndMedian;
        public bool UseInnerFence;
        public bool UseOuterFence;

        public bool IsAscii;

        //  Display options
        public string AxisFontDescriptor;
        public double Cco;

        public void SetDefaultXAxisTitle()
        {
            //  This used to try to be cleverer, but it turns out that formatting for each combination is almost essential to allow variation.
            switch (Method)
            {
                case BoxWhiskerMethod.MedianQuartilesRange:
                    if (UseInnerFence)
                        XAxisTitle = UseOuterFence ? "min < LQ < median%MEAN% > UQ > max, fences (1.5 & 3.0 IQR)" : "min < LQ < median%MEAN% > UQ > max, fence (1.5 IQR)";
                    else
                        XAxisTitle = UseOuterFence ? "min < LQ < median%MEAN% > UQ > max, fence (3.0 IQR)" : "min < LQ < median%MEAN% > UQ > max";
                    break;
                case BoxWhiskerMethod.MeanStandardDeviationRange:
                    if (UseInnerFence)
                        XAxisTitle = UseOuterFence ? "min < 1 SD < mean%MEDIAN% > 1 SD > max, fences (1.96 SD, 2.58 SD)" : "min < 1 SD < mean%MEDIAN% > 1 SD > max, fence (1.96 SD)";
                    else
                        XAxisTitle = UseOuterFence ? "min < 1 SD < mean%MEDIAN% > 1 SD > max, fence (2.58 SD)" : "min < 1 SD < mean%MEDIAN% > 1 SD > max";
                    break;
                case BoxWhiskerMethod.MeanStandardErrorRange:
                    if (UseInnerFence)
                        XAxisTitle = UseOuterFence ? "min < 1 SE < mean%MEDIAN% > 1 SE > max, fences (1.96 SD, 2.58 SD)" : "min < 1 SE < mean%MEDIAN% > 1 SE > max, fence (1.96 SD)";
                    else
                        XAxisTitle = UseOuterFence ? "min < 1 SE < mean%MEDIAN% > 1 SE > max, fence (2.58 SD)" : "min < 1 SE < mean%MEDIAN% > 1 SE > max";
                    break;
                case BoxWhiskerMethod.MeanConfidenceIntervalRange:
                    string ci = Formatting.XRound(Cco * 100.0, 1) + "% confidence interval";
                    if (UseInnerFence)
                    {
                        if (UseOuterFence)
                            XAxisTitle = "min < mean%MEDIAN% ? " + ci + " > max, fences (1.96 SD, 2.58 SD)";
                        else
                            XAxisTitle = "min < mean%MEDIAN% ? " + ci + " > max, fence (1.96 SD)";
                    }
                    else
                    {
                        if (UseOuterFence)
                            XAxisTitle = "min < mean%MEDIAN% ? " + ci + " > max, fence (2.58 SD)";
                        else
                            XAxisTitle = "min < mean%MEDIAN% ? " + ci + " > max";
                    }
                    break;
                case BoxWhiskerMethod.SevenNumberSummary:
                    XAxisTitle = "min < [ 2nd < 9th < [ LQ < median%MEAN% > UQ | > 91st > 98th ] > max";
                    break;
                case BoxWhiskerMethod.BowleySummary:
                    XAxisTitle = "[ min < 10th < | LQ < median%MEAN% > UQ | > 90th > max ]";
                    break;
                default:
                    throw new ArgumentOutOfRangeException("options.Method", Method.ToString());
            }

            if (MarkMeanAndMedian)
            {
                XAxisTitle = XAxisTitle.Replace("%MEAN%", " & mean(x)");
                XAxisTitle = XAxisTitle.Replace("%MEDIAN%", " & median(x)");
            }
            else
            {
                XAxisTitle = XAxisTitle.Replace("%MEAN%", string.Empty);
                XAxisTitle = XAxisTitle.Replace("%MEDIAN%", string.Empty);
            }
        }

        public override bool ShowBoxWhiskerOptions => true;

        public override bool UsesAxisLabelFontDescriptor => true;

        public override bool UsesAxisTitleFontDescriptor => true;

        public override bool UsesBoxAxes => true;

        public override bool UsesChartTitle => true;

        public override bool UsesColour => false;

        public override bool UsesOrientation => true;

        public override bool UsesSeriesLabels => true;

        public override bool UsesShowLegend => false;

        public override bool UsesTitleFontDescriptor => true;

        public override bool UsesXAxisTitle => true;

        public override bool ShowLegendIsRelevant => false;

        public override bool IsNaturalOrientation => Orientation == ChartOrientation.Horizontal;

        public override void Accept(IChartOptionVisitor visitor)
        {
            visitor.Visit(this);
        }
    }
}
