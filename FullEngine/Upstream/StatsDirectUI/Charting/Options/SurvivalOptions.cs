using System;
using System.Collections.Generic;

namespace StatsDirect.Charting
{
    [Serializable]
    public class SurvivalOptions : GenericOptions
    {
        [Serializable]
        public class SurvivalSeries
        {
            public double[] XDat;
            public double[] YDat;
            public double[] YDatL;
            public double[] YDatU;
            public int[] CDat;
            //  Titles are carried in SeriesTitles
        }


        public IList<SurvivalSeries> Series;
        public bool ShowCensorshipTics;
        public bool ShowEventMarkers;
        public bool UseSeriesColourForConfidenceIntervals;

        public SurvivalOptions()
        {
            Series = new List<SurvivalSeries>();
        }

        ///  <summary>
        ///  Set up markers for the series that are known
        ///  </summary>
        ///  <remarks>Precondition: All series have been set</remarks>
        public void SetMarkers()
        {
            MarkerTypes = new List<MarkerType>();

            //  One marker type per series
            for (int seriesIndex = 0; seriesIndex < SeriesTitles.Length; seriesIndex++)
            {
                int mkr = SeriesNumberToMarkerNumber(seriesIndex);
                MarkerType markerType = ChartPreferences.MarkerTypes[mkr].Clone();
                MarkerTypes.Add(markerType);

                SeriesOptionsDescriptor sod = new()
                {
                    MarkerIndex = seriesIndex,
                    SeriesName = SeriesTitles[seriesIndex]
                };
                SeriesOptions.Add(sod);
            }

            //  Now add one more for the CIs
            MarkerType ciMarkerType = ChartPreferences.MarkerTypes[10].Clone();
            MarkerTypes.Add(ciMarkerType);

            SeriesOptionsDescriptor cisod = new()
            {
                AllowChangeToMarkerSize = false,
                AllowChangeToMarkerType = false,
                MarkerIndex = SeriesTitles.Length,
                SeriesName = "Confidence intervals"
            };
            SeriesOptions.Add(cisod);
        }

        public override bool UsesChartTitle => true;

        public override bool UsesSeriesLabels => true;

        public override bool UsesAxisLabelFontDescriptor => true;

        public override bool UsesAxisTitleFontDescriptor => true;

        public override bool UsesYAxisTitle => true;

        public override bool ShowSurvivalOptions => true;

        public override bool ShowLegendIsRelevant => Series.Count > 1;

        public override void Accept(IChartOptionVisitor visitor)
        {
            visitor.Visit(this);
        }
    }
}
