using System;
using System.Collections.Generic;

namespace StatsDirect.Charting
{
    public abstract class ForestishOptions : GenericOptions
    {
        public double cco { get; set; }
        public IList<double> GroupSizes { get; set; }
        public int k { get; set; }
        public IList<double> OddsRatios { get; set; }
        public IList<double> OddsRatioLcis { get; set; }
        public IList<double> OddsRatioUcis { get; set; }
        public IList<string> Titles { get; set; }
        public bool MarkCentres { get; set; } = true;

        protected ForestishOptions()
        {
            //  A forest plot has one marker for the study and a second for the pooled effect
            MarkerTypes = new List<MarkerType>();
            MarkerType studyMarkerType = new()
            {
                MarkerColor = ColorDescriptor.Gray,
                LineColor = ColorDescriptor.Black,
                IsMarkerFilled = true,
                MarkerShape = MarkerShape.Square,
                LineDashStyle = DashStyleDescriptor.Solid,
                Width = 1
            };
            MarkerTypes.Add(studyMarkerType);
            MarkerType pooledMarkerType = new()
            {
                MarkerColor = ColorDescriptor.Gray,
                LineColor = ColorDescriptor.Black,
                IsMarkerFilled = true,
                MarkerShape = MarkerShape.Diamond,
                LineDashStyle = DashStyleDescriptor.Solid,
                Width = 1
            };
            MarkerTypes.Add(pooledMarkerType);

            SeriesOptionsDescriptor studyOptions = new()
            {
                SeriesName = "Study",
                AllowChangeToDashStyle = false,
                AllowChangeToMarkerSize = false,
                AllowChangeToLineThickness = false,
                MarkerIndex = 0
            };
            SeriesOptions.Add(studyOptions);

            SeriesOptionsDescriptor pooledOptions = new()
            {
                SeriesName = "Pooled effect",
                AllowChangeToDashStyle = false,
                AllowChangeToMarkerSize = false,
                AllowChangeToLineThickness = false,
                MarkerIndex = 1
            };
            SeriesOptions.Add(pooledOptions);
        }

        public override bool UsesShowLegend => false;

        public override bool ShowLegendIsRelevant => false;
    }
}
