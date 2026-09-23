using StatsDirect.Charting.Scales;
using StatsDirect.Numerics;
using StatsDirect.Templates;
using System;
using System.Drawing;

namespace StatsDirect.Charting.Renderer
{
    internal abstract class AbstractXYChartRenderer : AbstractChartRenderer
    {
        protected AbstractXYChartRenderer(ChartDefinition definition, ICanvasFactory canvasFactory)
            : base(definition, canvasFactory)
        {
        }

        /// <summary>
        ///  Plots an XY chart assuming an existing vector plot is open. This allows callers to use this then add other features to the chart before it is completed.
        /// </summary>
        /// <param name="x">The X co-ordinates of the points to plot.  Zero-based or 1-based.</param>
        /// <param name="y">The Y co-ordinates of the points to plot.  Zero-based or 1-based, same length as x.</param>
        /// <param name="xtxt">The X-axis title</param>
        /// <param name="ytxt">The y-axis title</param>
        /// <param name="title">The chart title</param>
        /// <param name="zPlot">If true, draw a line at the smallest Y value</param>
        /// <param name="minMaxY"></param>
        /// <param name="markerSize"></param>
        /// <param name="shape"></param>
        /// <param name="isFilled"></param>
        /// <param name="p"></param>
        /// <param name="useCalculatedScalesEvenWithDefinition"></param>
        /// <param name="chartAreaShape">If Square, the plot area will be square; if Default, it will be the default rectangular shape</param>
        /// <param name="presetXMin"></param>
        /// <param name="presetXMax"></param>
        /// <param name="presetYMin"></param>
        /// <param name="presetYMax"></param>
        /// <remarks></remarks>
        protected AxisScales PlotXYInternal(double[] x, double[] y, string xtxt, string ytxt, string title, bool zPlot, DataMinMax minMaxY, double markerSize, MarkerShape shape, bool isFilled, PenDescriptor p, bool useCalculatedScalesEvenWithDefinition, ChartAreaShape chartAreaShape, double presetXMin = 0, double presetXMax = 0, double presetYMin = 0, double presetYMax = 0)
        {
            ScaleType scaleTypeX = ScaleType.Linear;
            ScaleType scaleTypeY = ScaleType.Linear;
            if (HasScaleParameters)
            {
                scaleTypeX = Definition.ScaleParameters.X.ScaleType;
                scaleTypeY = Definition.ScaleParameters.Y.ScaleType;
            }

            //  If required, get the Min and Max for the data
            //  This is safe because we're using this function to plot our data.
            double axisXMin;
            double axisXMinGreaterThanZero;
            double axisXMax;
            double axisYMin;
            double axisYMinGreaterThanZero;
            double axisYMax;
            switch (minMaxY)
            {
                case DataMinMax.XPreset_YPreset:
                    axisXMin = presetXMin;
                    axisXMinGreaterThanZero = presetXMin;
                    axisXMax = presetXMax;
                    axisYMin = presetYMin;
                    axisYMinGreaterThanZero = presetYMin;
                    axisYMax = presetYMax;
                    break;
                case DataMinMax.XUseScaleParameters_YUseScaleParameters:
                    //  Take data from scale parameters
                    axisYMax = Definition.ScaleParameters.Y.Max;
                    axisYMinGreaterThanZero = Definition.ScaleParameters.Y.MinGreaterThanZero;
                    axisYMin = Definition.ScaleParameters.Y.Min;
                    axisXMax = Definition.ScaleParameters.X.Max;
                    axisXMinGreaterThanZero = Definition.ScaleParameters.X.MinGreaterThanZero;
                    axisXMin = Definition.ScaleParameters.X.Min;
                    break;
                case DataMinMax.XY_CalcTogether:
                    // X and Y must have the same scale
                    GetMinMaxArray(x, out axisXMin, out axisXMax, out axisXMinGreaterThanZero);
                    GetMinMaxArray(y, out axisYMin, out axisYMax, out axisYMinGreaterThanZero);
                    axisYMin = axisXMin = Math.Min(axisYMin, axisXMin);
                    axisYMinGreaterThanZero = axisXMinGreaterThanZero = Math.Min(axisYMinGreaterThanZero, axisXMinGreaterThanZero);
                    axisYMax = axisXMax = Math.Max(axisYMax, axisXMax);
                    break;
                case DataMinMax.XCalc_YCalc:
                    GetMinMaxArray(x, out axisXMin, out axisXMax, out axisXMinGreaterThanZero);
                    GetMinMaxArray(y, out axisYMin, out axisYMax, out axisYMinGreaterThanZero);
                    break;
                case DataMinMax.XCalc_YPreset:
                    GetMinMaxArray(x, out axisXMin, out axisXMax, out axisXMinGreaterThanZero);
                    axisYMin = presetYMin;
                    axisYMinGreaterThanZero = presetYMin;
                    axisYMax = presetYMax;
                    break;
                default:
                    throw new ArgumentOutOfRangeException(nameof(minMaxY), minMaxY, "Don't know how to plot using the given minMaxY");
            }

            DataMinY = axisYMin;
            DataMinGreaterThanZeroY = axisYMinGreaterThanZero;
            DataMaxY = axisYMax;
            DataMinX = axisXMin;
            DataMinGreaterThanZeroX = axisXMinGreaterThanZero;
            DataMaxX = axisXMax;

            AxisScales axisScales = LayoutChartAndDrawAxes(title,
                new AxisDefinition(xtxt, AxisMode.Scale, scaleTypeX),
                new AxisDefinition(ytxt, AxisMode.Scale, scaleTypeY),
                false, useCalculatedScalesEvenWithDefinition, null, chartAreaShape);

            if (zPlot)
                DrawQCanvas(OffY);

            // Plot the points
            int rows = x.Length;
            int xOffset = x.GetLowerBound(0);
            int yOffset = y.GetLowerBound(0);
            PointF[] xys = new PointF[rows];
            for (int r = 0; r < rows; r++)
            {
                if (x[r + xOffset] != Constant.MISSING && y[r + yOffset] != Constant.MISSING)
                {
                    xys[r].X = Convert.ToSingle(ToCanvasX(x[r + xOffset]));
                    xys[r].Y = Convert.ToSingle(ToCanvasY(y[r + yOffset]));
                }
                else
                {
                    //  Missing.  Any value less than zero is ignored by DrawMarkerSeries.
                    xys[r].X = -1;
                    xys[r].Y = -1;
                }
            }
            DrawMarkerSeriesInCanvasCoordinates(xys, markerSize, shape, isFilled, p, p, false, true);

            return axisScales;
        }
    }
}
