using StatsDirect.UI;
using System;
using System.Collections.Generic;

namespace StatsDirect.Charting
{
    [Serializable]
    public abstract class ChartOptions
    {
        public string Title { get; set; }
        public string XAxisTitle { get; set; }
        public string YAxisTitle { get; set; }
        public float AxisLineThickness { get; set; }
        public bool ShowLegend { get; set; }
        public bool UseColour { get; set; } = SdApplication.SoleInstance.Preferences.ShouldUseColour;
        ///  <summary>
        ///  Marker details.
        ///  </summary>
        ///  <remarks>Explicitly allowed: one marker type may be referenced multiple times in the list.  This is used, for example, by the Ladder plot, which uses marker type 1 for slots 1 and 2 so that it can show a UI for the markers in slot 1, and the lines in slot 2.</remarks>
        public IList<MarkerType> MarkerTypes { get; set; }

        ///  <summary>
        ///  Given a series index (13 for the 14th series, for example) return the marker that should be used for that series.
        ///  </summary>
        ///  <param name="seriesNumber"></param>
        ///  <returns></returns>
        ///  <remarks>This used to be considerably more complex; Peter has simplified.</remarks>
        public static int SeriesNumberToMarkerNumber(int seriesNumber) => seriesNumber % 10;

        public virtual bool UsesAxisLineThickness => true;
        public virtual bool UsesColour => true;
        public virtual bool UsesShowLegend => true;
        public virtual bool UsesXAxisOptions => true;
        public virtual bool UsesXAxisTitle => false;
        public virtual bool UsesYAxisOptions => true;
        public virtual bool UsesYAxisTitle => false;

        public abstract void Accept(IChartOptionVisitor visitor);

        public abstract bool ShowLegendIsRelevant { get; }

        public virtual ChartOptions Clone()
        {
            ChartOptions theClone = (ChartOptions)MemberwiseClone();
            if (null != MarkerTypes)
                theClone.MarkerTypes = new List<MarkerType>(MarkerTypes);
            return theClone;
        }
    }
}
