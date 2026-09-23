using System;
using System.Collections.Generic;

namespace StatsDirect.Charting
{
    [Serializable]
    public class ROCOptions : GenericOptions
    {
        public bool ShowCutOffCalculator;
        public bool ShowOptimumCutOff;
        public double GAMMA;
        public double Weight;
        public Comparison Comparison;
        private readonly bool showLegendIsRelevant;

        public ROCOptions(IList<ISeries> seriesToUse)
        {

            //  The ROC plot uses two series per ROC series.  Series 1 is the markers, series 2 is the optimum cut-off marker.
            //  All the "normal" series are set up first, then all the "optimum cut-off" series.
            MarkerTypes = new List<MarkerType>();
            for (int markerIndex = 0; markerIndex < seriesToUse.Count; markerIndex++)
            {
                ISeries series = seriesToUse[markerIndex];
                int mkr = SeriesNumberToMarkerNumber(markerIndex);
                MarkerType markerType = ChartPreferences.MarkerTypes[mkr].Clone();
                markerType.MarkerSize = 6;
                MarkerTypes.Add(markerType);

                //  Can change the shape, size and filled/unfilled for series
                SeriesOptionsDescriptor descriptor = new()
                {
                    SeriesName = series.Title,
                    AllowChangeToDashStyle = false,
                    AllowChangeToLineThickness = false,
                    MarkerIndex = MarkerTypes.Count - 1
                };
                SeriesOptions.Add(descriptor);
            }

            //  Now the cut-offs
            for (int markerIndex = 0; markerIndex < seriesToUse.Count; markerIndex++)
            {
                ISeries series = seriesToUse[markerIndex];
                int mkr = SeriesNumberToMarkerNumber(markerIndex);
                MarkerType markerType = ChartPreferences.MarkerTypes[mkr].Clone();
                //  Increase the size of the optimum cut-off indicators by default
                markerType.MarkerSize = 12;
                MarkerTypes.Add(markerType);

                //  Can change the shape, size and filled/unfilled for series
                SeriesOptionsDescriptor descriptor = new()
                {
                    SeriesName = series.Title + " optimum cut-off",
                    AllowChangeToDashStyle = false,
                    AllowChangeToLineThickness = false,
                    MarkerIndex = MarkerTypes.Count - 1
                };
                SeriesOptions.Add(descriptor);
            }

            showLegendIsRelevant = seriesToUse.Count > 2; //  2 series per ROC series
        }

        public override bool UsesChartTitle => true;
        public override bool UsesSeriesLabels => true;
        public override bool UsesAxisLabelFontDescriptor => true;
        public override bool UsesAxisTitleFontDescriptor => true;
        public override bool ShowRocOptions => true;
        public override bool UsesLegendFontDescriptor => true;
        public override bool ShowLegendIsRelevant => showLegendIsRelevant;

        public override void Accept(IChartOptionVisitor visitor)
        {
            visitor.Visit(this);
        }
    }
}
