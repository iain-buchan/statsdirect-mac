using System;
using System.Drawing;
using StatsDirect.Charting.Scales;
using StatsDirect.Numerics;

namespace StatsDirect.Charting.Renderer
{
    abstract class AbstractLinearRegressionChartRenderer : AbstractChartRenderer
    {
        public AbstractLinearRegressionChartRenderer(ChartDefinition cd, ICanvasFactory canvasFactory)
            : base(cd, canvasFactory)
        {
        }

        protected AxisScales PlotLinearRegression(string title, double slope, double intercept, bool fullWidth, string xAxisTitle, string yAxisTitle)
        {
            const int MARKER_SIZE = 6;

            AssignMarkersToSeries();
            AxisScales axisScales = LayoutChartAndDrawAxes(title,
                new AxisDefinition(xAxisTitle, AxisMode.Scale, Definition.ScaleParameters.X.ScaleType),
                new AxisDefinition(yAxisTitle, AxisMode.Scale, Definition.ScaleParameters.Y.ScaleType),
                ChartPreferences.DefaultBoxAxes, false);

            // plot points
            DoubleSeries xs = (DoubleSeries)Definition.XSeries[0];
            DoubleSeries ys = (DoubleSeries)Definition.YSeries[0];
            double[] xdat = xs.Data;
            double[] ydat = ys.Data;
            PointF[] xys = new PointF[xs.Data.Length];
            for (int r = 0; r < xs.Data.Length; r++)
            {
                if (xdat[r] != Constant.MISSING && ydat[r] != Constant.MISSING)
                {
                    xys[r].X = Convert.ToSingle(ToCanvasX(xdat[r]));
                    xys[r].Y = Convert.ToSingle(ToCanvasY(ydat[r]));
                }
                else
                {
                    xys[r].X = -1;
                    xys[r].Y = -1;
                }
            }
            DrawMarkerSeriesInCanvasCoordinates(xys, MARKER_SIZE, ys.MarkerType, false, true);

            double xstep = (axisScales.X.MaximumScaleValue - axisScales.X.MinimumScaleValue) / axisScales.X.Tics().Count / 2.0;

            // Plot regression
            double oldx = Constant.MISSING;
            double oldy = Constant.MISSING;
            for (double calcx = fullWidth ? axisScales.X.MinimumScaleValue : axisScales.X.MinimumDataValue; calcx <= (fullWidth ? axisScales.X.MaximumScaleValue : axisScales.X.MaximumDataValue); calcx += xstep)
            {
                double calcy = slope * calcx + intercept;
                MaybeDrawLineInChartCoordinates(axisScales, GrGreen, calcx, calcy, oldx, oldy);
                oldx = calcx;
                oldy = calcy;
            }
            MaybeDrawMarkerLines(axisScales);
            return axisScales;
        }
    }
}
