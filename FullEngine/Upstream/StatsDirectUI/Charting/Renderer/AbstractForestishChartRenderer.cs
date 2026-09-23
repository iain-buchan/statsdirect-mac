using StatsDirect.Charting.Scales;
using StatsDirect.Numerics;
using StatsDirect.Templates;
using StatsDirect.Utilities;
using System;
using System.Drawing;

namespace StatsDirect.Charting.Renderer
{
    internal abstract class AbstractForestishChartRenderer : AbstractChartRenderer
    {
        protected const double featureHeight = 0.667; // 2/3
        protected const double arrowWidth = 0.125; // 1/8
        /// <summary>
        /// Default study marker type; may be overwritten if a subclass prefers different details.
        /// </summary>
        protected MarkerType studyMarkerType = new()
        {
            MarkerColor = ColorDescriptor.Gray,
            LineColor = ColorDescriptor.Black,
            IsMarkerFilled = true,
            MarkerShape = MarkerShape.Square,
            LineDashStyle = DashStyleDescriptor.Solid,
            Width = 1
        };
        /// <summary>
        /// Default pooled marker type; may be overwritten if a subclass prefers different details.
        /// </summary>
        protected MarkerType pooledMarkerType = new()
        {
            MarkerColor = ColorDescriptor.Gray,
            LineColor = ColorDescriptor.Black,
            IsMarkerFilled = true,
            MarkerShape = MarkerShape.Diamond,
            LineDashStyle = DashStyleDescriptor.Solid,
            Width = 1
        };

        protected AbstractForestishChartRenderer(ChartDefinition definition, ICanvasFactory canvasFactory)
            : base(definition, canvasFactory)
        {
            if (null != definition.ChartOptions.MarkerTypes)
            {
                if (definition.ChartOptions.MarkerTypes.Count >= 1)
                    studyMarkerType = definition.ChartOptions.MarkerTypes[0];
                if (definition.ChartOptions.MarkerTypes.Count >= 2)
                    pooledMarkerType = definition.ChartOptions.MarkerTypes[1];
            }
        }

        protected static string RangeLabel(double odr, double odrl, double odru, double absMin) => Formatting.RoundMeta(odr, absMin) + " (" + Formatting.RoundMeta(odrl, absMin) + ", " + Formatting.RoundMeta(odru, absMin) + ")";

        protected void DrawRowLabelInChartCoordinates(string title, double yc) => DrawStringLabel(title, XAxisCanvas - 15, ToCanvasY(yc), StringAlignment.Far, StringAlignment.Center);
        protected void DrawRangeLabelInChartCoordinates(double odr, double odrl, double odru, double absMin, double yc) => DrawStringLabel(RangeLabel(odr, odrl, odru, absMin), XAxisCanvas + XExtCanvas + 10, ToCanvasY(yc), StringAlignment.Near, StringAlignment.Center);
        protected void DrawRangeLabelInChartCoordinates(string label, double yc) => DrawStringLabel(label, XAxisCanvas + XExtCanvas + 10, ToCanvasY(yc), StringAlignment.Near, StringAlignment.Center);
        protected void DrawExcludedRangeLabelInChartCoordinates(double yc) => DrawRangeLabelInChartCoordinates("* (excluded)", yc);

        protected void PlotPooledMarker(double odr, double odrl, double odru, double absMin, double saveYc, string label)
        {
            PenDescriptor pooledCiPen = GetLinePen(pooledMarkerType, true);
            PenDescriptor pooledEffectPen = GetLinePen(ChartPreferences.MarkerTypes[10], false);

            double yc = 0.5;
            // Pooled effect marker line - draw first so that it's behind the marker and its lower end is therefore hidden.
            DrawLineInChartCoordinates(pooledEffectPen, odr, saveYc, odr, yc);

            DrawMarkerInChartCoordinates(odr, yc, ToCanvasHeight(featureHeight / 2), pooledMarkerType);
            // pooled marker
            DrawLineInChartCoordinates(pooledCiPen, odru, yc, odrl, yc);
            // pool label
            DrawStringLabel(ComboTi(label), XAxisCanvas - 15, ToCanvasY(yc), StringAlignment.Far, StringAlignment.Center);
            DrawRangeLabelInChartCoordinates(odr, odrl, odru, absMin, yc);
        }

        protected void PlotNoEffectMarker(AxisScales axisScales)
        {
            switch (Definition.ScaleParameters.X.ScaleType)
            {
                case ScaleType.Linear:
                    if (axisScales.X.MinimumScaleValue <= 0 && axisScales.X.MaximumScaleValue >= 0)
                        DrawLineInChartCoordinates(GrBlack, 0, axisScales.Y.MinimumScaleValue, 0, axisScales.Y.MaximumScaleValue);
                    break;
                case ScaleType.Log10:
                case ScaleType.LogNatural:
                    if (axisScales.X.MinimumScaleValue <= 1 && axisScales.X.MaximumScaleValue >= 1)
                        DrawLineInChartCoordinates(GrBlack, 1, axisScales.Y.MinimumScaleValue, 1, axisScales.Y.MaximumScaleValue);
                    break;
            }
        }

        protected double MaxIgnoringMissingAndInfinities(params double[] values)
        {
            double maxSoFar = double.MinValue;
            foreach (double value in values)
                if (!(double.IsNaN(value) || double.IsInfinity(value) || value == Constant.MISSING))
                    maxSoFar = Math.Max(maxSoFar, value);
            return maxSoFar;
        }

        protected double MinIgnoringMissingAndInfinities(params double[] values)
        {
            double minSoFar = double.MaxValue;
            foreach (double value in values)
                if (!(double.IsNaN(value) || double.IsInfinity(value) || value == Constant.MISSING))
                    minSoFar = Math.Min(minSoFar, value);
            return minSoFar;
        }

        protected void DrawRowInChartCoordinates(string title, double odr, double odrl, double odru, double variance, double absMin, double yc, double xm, double xl, double xr, bool arrowL, bool arrowU, bool markCentres)
        {
            PenDescriptor ciPen = GetLinePen(studyMarkerType, true);
            PenDescriptor dotPen = GetMarkerPen(ChartPreferences.MarkerTypes[10]);

            // Weight blob.  Draw this first so that the line appears in front of it in the case of short lines (#994).
            // #688: Make blob size proportional to sqrt(1/variance) rather than 1/variance
            double blobSize = (5 + ToCanvasHeight(featureHeight * Math.Sqrt(variance))) * 0.7;
            DrawMarkerInChartCoordinates(xm, yc, blobSize / 2, studyMarkerType);

            // CI line
            DrawLineInChartCoordinates(ciPen, xl, yc, xr, yc);

            // Arrow ends if not plottable
            if (arrowL)
            {
                DrawLineInCanvasCoordinates(ciPen, ToCanvasX(xl) + ToCanvasHeight(arrowWidth), ToCanvasY(yc) + ToCanvasHeight(arrowWidth), ToCanvasX(xl), ToCanvasY(yc));
                DrawLineInCanvasCoordinates(ciPen, ToCanvasX(xl), ToCanvasY(yc), ToCanvasX(xl) + ToCanvasHeight(arrowWidth), ToCanvasY(yc) - ToCanvasHeight(arrowWidth));
            }
            if (arrowU)
            {
                DrawLineInCanvasCoordinates(ciPen, ToCanvasX(xr) - ToCanvasHeight(arrowWidth), ToCanvasY(yc) + ToCanvasHeight(arrowWidth), ToCanvasX(xr), ToCanvasY(yc));
                DrawLineInCanvasCoordinates(ciPen, ToCanvasX(xr), ToCanvasY(yc), ToCanvasX(xr) - ToCanvasHeight(arrowWidth), ToCanvasY(yc) - ToCanvasHeight(arrowWidth));
            }
            // Centre mark.  Draw this last so that it appears in front of the line.
            if (markCentres)
                DrawMarkerInChartCoordinates(xm, yc, 2, MarkerShape.Circle, true, dotPen);

            DrawRowLabelInChartCoordinates(title, yc);
            DrawRangeLabelInChartCoordinates(odr, odrl, odru, absMin, yc);
        }

        protected void DrawExcludedInChartCoordinates(string title, double yc)
        {
            DrawRowLabelInChartCoordinates(title, yc);
            DrawExcludedRangeLabelInChartCoordinates(yc);
        }

        protected bool Included(MHOptions options, int i) => (null == options.Included) || options.Included[i];

        public static string ComboTi(string cap)
        {
            string x = "combined";
            if (cap.Contains("fixed effects"))
                x += " [fixed]";
            else if (cap.Contains("random effects"))
                x += " [random]";
            return x;
        }

    }
}
