using System;
using System.Collections.Generic;

namespace StatsDirect.Charting
{
    [Serializable]
    public class BarOptions : GenericOptions
    {
        private bool showLegendIsRelevant;

        ///  <summary>
        ///  The widest a bar may be, as a fraction of its containing space.
        ///  </summary>
        public double MaxBarWidth { get; set; } = 0.5;

        ///  <summary>
        ///  If false, bars should be drawn side-by-side.  If true, bars should be drawn end-to-end.
        ///  </summary>
        public bool Stacked { get; set; }

        /// <summary>
        /// If false, stacked bar charts should be drawn per Excel.  If true, they should be drawn per StatsDirect.
        /// </summary>
        public bool RotateWhenStacked { get; set; } = true;

        ///  <summary>
        ///  If Stacked and true, bars should be drawn end-to-end scaled 0..1.  If Stacked and false, bars should be drawn end-to-end scaled to the largest bar.
        ///  If not Stacked, no effect.
        ///  </summary>
        public bool Stacked100Percent { get; set; }

        public void SetMarkers(IList<ISeries> seriesToUse)
        {
            //  Markers will be calculated automatically as required (though we need to force fills); we just need to set up the option descriptors.
            // ShouldForceIsFilled = True
            // ForcedIsFilled = True
            // ShouldForceFillStyle = True
            // ForcedFillStyle = FillStyle.None

            for (int i = 0; i < seriesToUse.Count; i++)
            {
                SeriesOptionsDescriptor soleOptions = new()
                {
                    SeriesName = seriesToUse[i].Title,
                    AllowChangeToMarkerSize = false,
                    AllowChangeToMarkerType = false,
                    AllowChangeToDashStyle = true,
                    AllowChangeToLineThickness = true,
                    AllowChangeToFill = true,
                    MarkerIndex = i
                };
                SeriesOptions.Add(soleOptions);
            }
            showLegendIsRelevant = Stacked || seriesToUse.Count > 1;
        }

        public override bool UsesChartTitle => true;

        public override bool UsesXAxisTitle => true;

        public override bool UsesYAxisTitle => true;

        public override bool UsesAutoscale => true;

        public override bool UsesAxisLabelFontDescriptor => true;

        public override bool UsesAxisTitleFontDescriptor => true;

        public override bool UsesBoxAxes => true;

        public override bool UsesOrientation => true;

        public override bool ShowBarOptions => true;

        public override string OrientationLabel => "Bar orientation";

        public override bool ShowLegendIsRelevant => showLegendIsRelevant;

        public override bool IsNaturalOrientation => Orientation == ChartOrientation.Vertical;

        public override void Accept(IChartOptionVisitor visitor)
        {
            visitor.Visit(this);
        }
    }
}
