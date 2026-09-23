using System;

namespace StatsDirect.Charting
{
    [Serializable]
    public class MarkerType
    {
        public MarkerShape MarkerShape { get; set; }
        public ColorDescriptor MarkerColor { get; set; }
        public ColorDescriptor LineColor { get; set; }
        public float Width { get; set; }

        /// <summary>
        /// The dash style used for lines (markers always use solid lines)
        /// </summary>
        public DashStyleDescriptor LineDashStyle { get; set; }

        ///  <summary>
        ///  If true, the marker shape is filled; if false, it is hollow.
        ///  </summary>
        public bool IsMarkerFilled { get; set; }

        ///  <summary>
        ///  Sizes are defined in co-ordinate sizes.  If the canvas gets larger, marker sizes get relatively smaller.
        ///  </summary>
        public double MarkerSize { get; set; }
        public FillStyle MarkerFillStyle { get; set; }

        public MarkerType Clone()
        {
            MarkerType m = new()
            {
                                   MarkerColor = MarkerColor,
                                   LineColor = LineColor,
                                   MarkerShape = MarkerShape,
                                   LineDashStyle = LineDashStyle,
                                   Width = Width,
                                   IsMarkerFilled = IsMarkerFilled,
                                   MarkerSize = MarkerSize,
                                   MarkerFillStyle = MarkerFillStyle
                               };
            return m;
        }
    }
}
