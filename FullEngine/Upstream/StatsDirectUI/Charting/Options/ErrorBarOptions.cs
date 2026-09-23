using System;
using System.Collections.Generic;

namespace StatsDirect.Charting
{
    [Serializable]
    public class ErrorBarOptions : GenericOptions
    {
        public bool PlotMarkers { get; set; } = true;
        public bool JoinMarkersWithLines { get; set; }
        public List<MultiDoubleSeries> Series { get; set; }
        public bool ShouldCheckForOffsets { get; set; } = true;

        public void SetMarkers()
        {
            MarkerTypes = new List<MarkerType>();
            for (int i = 0; i < Series.Count; i++)
            {
                int mkr = SeriesNumberToMarkerNumber(i);
                MarkerType markerType = ChartPreferences.MarkerTypes[mkr].Clone();
                markerType.MarkerSize = 6;
                MarkerTypes.Add(markerType);

                //  An error plot has series with possible lines.
                SeriesOptionsDescriptor soleOptions = new()
                {
                    SeriesName = Series[i].Title,
                    AllowChangeToDashStyle = true,
                    AllowChangeToLineThickness = true,
                    MarkerIndex = i
                };
                SeriesOptions.Add(soleOptions);
            }
        }

        public override bool UsesChartTitle => true;

        public override bool UsesXAxisTitle => true;

        public override bool UsesYAxisTitle => true;

        public override bool UsesAutoscale => true;

        public override bool UsesAxisLabelFontDescriptor => true;

        public override bool UsesAxisTitleFontDescriptor => true;

        public override bool UsesBoxAxes => true;

        public override bool UsesSeriesLabels => true;

        public override bool ShowErrorBarOptions => true;

        public override bool ShowLegendIsRelevant => Series.Count > 1;

        public override bool UsesLegendFontDescriptor => true;

        public override void Accept(IChartOptionVisitor visitor)
        {
            visitor.Visit(this);
        }
    }
}
