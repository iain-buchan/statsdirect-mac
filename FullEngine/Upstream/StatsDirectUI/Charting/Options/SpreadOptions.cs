using System;
using System.Collections.Generic;

namespace StatsDirect.Charting
{
    [Serializable]
    public class SpreadOptions : GenericOptions
    {

        public SpreadOptions()
        {

            MarkerTypes = new List<MarkerType>();
            int mkr = SeriesNumberToMarkerNumber(0);
            MarkerType markerType = ChartPreferences.MarkerTypes[mkr].Clone();
            markerType.MarkerSize = 6;
            MarkerTypes.Add(markerType);

            //  A spread plot has a single series with no lines.
            SeriesOptionsDescriptor soleOptions = new()
            {
                SeriesName = "Markers",
                AllowChangeToDashStyle = false,
                AllowChangeToLineThickness = false,
                MarkerIndex = 0
            };
            SeriesOptions.Add(soleOptions);
        }

        public override bool UsesAutoscale => true;

        public override bool UsesBoxAxes => true;

        public override bool UsesChartTitle => true;

        public override bool UsesSeriesLabels => true;

        public override bool UsesXAxisTitle => true;

        public override bool UsesYAxisTitle => false;

        public override bool UsesAxisLabelFontDescriptor => true;

        public override bool UsesAxisTitleFontDescriptor => true;

        public override bool UsesOrientation => true;

        public override bool ShowLegendIsRelevant => false;

        public override bool IsNaturalOrientation => Orientation == ChartOrientation.Horizontal;

        public override void Accept(IChartOptionVisitor visitor)
        {
            visitor.Visit(this);
        }
    }
}
