using System;
using System.Collections.Generic;

namespace StatsDirect.Charting
{
    [Serializable]
    public class ScatterXYOptions : GenericOptions
    {

        public bool PlotMarkers { get; set; }
        public bool IsAscii { get; set; }
        private readonly bool showLegendIsRelevant;
        public bool JoinMarkersWithLines { get; set; }

        public ScatterXYOptions(IList<ISeries> xSeries, bool useLines)
        {
            JoinMarkersWithLines = useLines;
            PlotMarkers = true;

            MarkerTypes = new List<MarkerType>();
            for (int i = 0; i < xSeries.Count; i++)
            {
                int mkr = SeriesNumberToMarkerNumber(i);
                MarkerType markerType = ChartPreferences.MarkerTypes[mkr].Clone();
                markerType.MarkerSize = 6;
                MarkerTypes.Add(markerType);

                //  A scatter plot has series with no lines.
                SeriesOptionsDescriptor soleOptions = new()
                {
                    SeriesName = xSeries[i].Title,
                    AllowChangeToDashStyle = useLines,
                    AllowChangeToLineColour = useLines,
                    AllowChangeToLineThickness = useLines,
                    MarkerIndex = i
                };
                SeriesOptions.Add(soleOptions);
            }
            showLegendIsRelevant = xSeries.Count > 1;
        }

        public override bool UsesChartTitle => true;

        public override bool UsesXAxisTitle => true;

        public override bool UsesYAxisTitle => true;

        public override bool UsesAutoscale => true;

        public override bool UsesAxisLabelFontDescriptor => true;

        public override bool UsesAxisTitleFontDescriptor => true;

        public override bool UsesSeriesLabels => true;

        public override bool ShowScatterXYOptions => true;

        public override bool ShowLegendIsRelevant => showLegendIsRelevant;

        public override void Accept(IChartOptionVisitor visitor)
        {
            visitor.Visit(this);
        }
    }
}
