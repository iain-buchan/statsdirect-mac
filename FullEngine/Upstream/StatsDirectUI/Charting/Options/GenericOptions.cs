using System;
using System.Collections.Generic;

namespace StatsDirect.Charting
{
    [Serializable]
    public abstract class GenericOptions : ChartOptions
    {
        public bool ShouldAutoscale;
        public bool ShouldBoxAxes;
        public string[] SeriesTitles;
        public FontDescriptor TitleFontDescriptor { get; set; }
        public FontDescriptor AxisTitleFontDescriptor { get; set; }
        public FontDescriptor AxisLabelFontDescriptor { get; set; }
        public FontDescriptor LegendFontDescriptor { get; set; }
        public IList<SeriesOptionsDescriptor> SeriesOptions;
        public ChartOrientation Orientation;
        public bool ShouldForceIsFilled;
        public bool ForcedIsFilled;
        ///  <summary>
        ///  If true, the fill style in ForcedFillStyle should be used for all fill styles, overriding the markers' own styles.
        ///  </summary>
        public bool ShouldForceFillStyle { get; set; }
        public FillStyle ForcedFillStyle { get; set; }

        protected GenericOptions()
        {
            SeriesOptions = new List<SeriesOptionsDescriptor>();
            if (UsesAxisLabelFontDescriptor)
                AxisLabelFontDescriptor = ChartPreferences.DefaultAxisLabelFont;
            if (UsesAxisTitleFontDescriptor)
                AxisTitleFontDescriptor = ChartPreferences.DefaultAxisTitleFont;
            if (UsesLegendFontDescriptor)
                LegendFontDescriptor = ChartPreferences.DefaultLegendFont;
            if (UsesTitleFontDescriptor)
                TitleFontDescriptor = ChartPreferences.DefaultTitleFont;
        }

        public virtual bool UsesChartTitle => false;
        public virtual bool UsesAutoscale => false;
        public virtual bool UsesBoxAxes => false;
        public virtual bool UsesSeriesLabels => false;
        public virtual bool UsesAxisLabelFontDescriptor => false;
        public virtual string AxisLabelFontLabel => "Axis Label";
        public virtual bool UsesAxisTitleFontDescriptor => false;
        public virtual bool UsesLegendFontDescriptor => false;
        public virtual string LegendFontLabel => "Legend";
        public virtual string OrientationLabel => "Orientation";

        ///  <summary>
        ///  True if the chart can only be drawn in one orientation or if the orientation matches its preferred orientation.
        ///  False if the chart will be drawn in a non-preferred orientation.
        ///  </summary>
        public virtual bool IsNaturalOrientation => true;
        public virtual bool UsesTitleFontDescriptor => true;
        public virtual bool UsesOrientation => false;

        ///  <summary>
        ///  Should the extra items for the bar chart be shown?
        ///  </summary>
        ///  <returns>True if the extra options should be shown, False if not.</returns>
        public virtual bool ShowBarOptions => false;

        ///  <summary>
        ///  Should the extra items for the box+whisker chart be shown?
        ///  </summary>
        ///  <returns>True if the extra options should be shown, False if not.</returns>
        public virtual bool ShowBoxWhiskerOptions => false;

        ///  <summary>
        ///  Should the extra items for the control chart be shown?
        ///  </summary>
        ///  <returns>True if the extra options should be shown, False if not.</returns>
        public virtual bool ShowControlOptions => false;

        ///  <summary>
        ///  Should the extra items for the scatter plot be shown?
        ///  </summary>
        ///  <returns>True if the extra options should be shown, False if not.</returns>
        public virtual bool ShowErrorBarOptions => false;

        ///  <summary>
        ///  Should the extra items for the forest plot be shown?
        ///  </summary>
        ///  <returns>True if the extra options should be shown, False if not.</returns>
        public virtual bool ShowForestOptions => false;

        ///  <summary>
        ///  Should the extra items for the histogram plot be shown?
        ///  </summary>
        ///  <returns>True if the extra options should be shown, False if not.</returns>
        public virtual bool ShowHistogramOptions => false;

        ///  <summary>
        ///  Should the extra items for the normal plot be shown?
        ///  </summary>
        ///  <returns>True if the extra options should be shown, False if not.</returns>
        public virtual bool ShowNormalOptions => false;

        ///  <summary>
        ///  Should the extra items for the pyramid plot be shown?
        ///  </summary>
        ///  <returns>True if the extra options should be shown, False if not.</returns>
        public virtual bool ShowPyramidOptions => false;

        ///  <summary>
        ///  Should the extra items for the ROC plot be shown?
        ///  </summary>
        ///  <returns>True if the extra options should be shown, False if not.</returns>
        public virtual bool ShowRocOptions => false;

        ///  <summary>
        ///  Should the extra items for the scatter plot be shown?
        ///  </summary>
        ///  <returns>True if the extra options should be shown, False if not.</returns>
        public virtual bool ShowScatterXYOptions => false;

        ///  <summary>
        ///  Should the extra items for the scatter plot be shown?
        ///  </summary>
        ///  <returns>True if the extra options should be shown, False if not.</returns>
        public virtual bool ShowSurvivalOptions => false;

        public override ChartOptions Clone()
        {
            GenericOptions theClone = (GenericOptions)base.Clone();
            if (null != SeriesOptions)
                theClone.SeriesOptions = new List<SeriesOptionsDescriptor>(SeriesOptions);
            return theClone;
        }

    }
}
