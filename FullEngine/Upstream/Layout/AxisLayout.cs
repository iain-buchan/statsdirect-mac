using System;
using System.Drawing;
using Layout.AxisLabelers;

namespace Layout
{
    public class AxisLayout
    {
        public static double AxisDensity = 1.0 / 150;
        public static double AxisFontSize = 12.0;

        public AxisLabeler.Options Options;

        public AxisLayout(bool isYAxis, Range dataRange, Range visibleRange, Func<string, decimal, Axis, RectangleF> computeLabelRect, RectangleF screen)
        {
            Options = new AxisLabeler.Options
            {
                Direction = isYAxis ? AxisDirection.Vertical : AxisDirection.Horizontal,
                DataRange = dataRange,
                VisibleRange = visibleRange,
                FontSize = (int)AxisFontSize,
                ComputeLabelRect = computeLabelRect,
                Screen = screen
            };
        }

        public Axis LayoutAxis(Graphics g)
        {
            AxisLabeler labeler = new ExtendedAxisLabeler(g);
            return labeler.Generate(Options, AxisDensity);
        }
    }
}
