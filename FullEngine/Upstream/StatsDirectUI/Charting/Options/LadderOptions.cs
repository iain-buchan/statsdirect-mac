using System;
using System.Collections.Generic;

namespace StatsDirect.Charting
{
    [Serializable]
    public class LadderOptions : GenericOptions
    {

        public LadderOptions()
        {
            //  A ladder plot's markers are derived from the first two series.
            MarkerTypes = new List<MarkerType>();
            MarkerType leftHandMarkerType = ChartPreferences.MarkerTypes[0].Clone();
            MarkerType rightHandMarkerType = ChartPreferences.MarkerTypes[1].Clone();
            leftHandMarkerType.MarkerSize = 6;
            rightHandMarkerType.MarkerSize = 6;
            MarkerTypes.Add(leftHandMarkerType);
            MarkerTypes.Add(rightHandMarkerType);

            //  A ladder plot has a left-hand and a right-hand series, connected by a line.
            //  The line uses the left-hand marker's line type and thickness
            SeriesOptionsDescriptor leftHandOptions = new()
            {
                SeriesName = "Left hand markers",
                AllowChangeToDashStyle = false,
                AllowChangeToLineThickness = false,
                AllowChangeToLineColour = false,
                MarkerIndex = 0
            };
            SeriesOptions.Add(leftHandOptions);

            SeriesOptionsDescriptor ladderRungOptions = new()
            {
                SeriesName = "Ladder rungs",
                AllowChangeToMarkerColour = false,
                AllowChangeToMarkerSize = false,
                AllowChangeToMarkerType = false,
                MarkerIndex = 0
            };
            SeriesOptions.Add(ladderRungOptions);

            SeriesOptionsDescriptor rightHandOptions = new()
            {
                SeriesName = "Right hand markers",
                AllowChangeToDashStyle = false,
                AllowChangeToLineThickness = false,
                AllowChangeToLineColour = false,
                MarkerIndex = 1
            };
            SeriesOptions.Add(rightHandOptions);
        }

        public override bool UsesAutoscale => true;

        public override bool UsesBoxAxes => true;

        public override bool UsesChartTitle => true;

        public override bool UsesSeriesLabels => true;

        public override bool UsesYAxisTitle => true;

        public override bool UsesAxisTitleFontDescriptor => true;

        public override bool UsesAxisLabelFontDescriptor => true;

        public override bool ShowLegendIsRelevant => false;

        public override void Accept(IChartOptionVisitor visitor)
        {
            visitor.Visit(this);
        }
    }
}
