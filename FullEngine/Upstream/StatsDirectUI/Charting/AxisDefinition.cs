using System.Collections.Generic;
using StatsDirect.Templates;

namespace StatsDirect.Charting
{
    /// <summary>
    /// Describes the features defining one axis (horizontal or vertical) on a chart.
    /// </summary>
    public class AxisDefinition
    {
        public string Title { get; set; }

        public AxisMode Mode { get; set; }

        public bool Reverse => (Mode & AxisMode.Reverse) != 0;

        ///  <summary>
        ///  Space by which the axis should be shifted in or the canvas enlarged, depending on the renderer
        ///  </summary>
        public double ExtraSpaceBeforeAxisStarts { get; set; }
        ///  <summary>
        ///  Space by which the axis should be shifted in or the canvas enlarged, depending on the renderer
        ///  </summary>
        public double ExtraSpaceAfterAxisEnds { get; set; }

        public ScaleType ScaleType { get; set; }

        /// <summary>
        /// For ScaleType.Series, this is the series to use for the names
        /// </summary>
        public IList<ISeries> Series { get; set; }
        public IList<string> Labels { get; set; }

        public AxisDefinition(string title, AxisMode mode, ScaleType scaleType)
        {
            Title = title;
            Mode = mode;
            ScaleType = scaleType;
        }
    }
}