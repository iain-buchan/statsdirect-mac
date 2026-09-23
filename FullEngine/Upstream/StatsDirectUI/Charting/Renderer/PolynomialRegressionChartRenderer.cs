using StatsDirect.Charting.Scales;
using StatsDirect.Numerics;
using StatsDirect.Templates;
using System;
using System.Drawing;

namespace StatsDirect.Charting.Renderer
{
    class PolynomialRegressionChartRenderer : AbstractXYZChartRenderer, IChartRenderer
    {
        public PolynomialRegressionChartRenderer(ChartDefinition definition, ICanvasFactory canvasFactory)
            : base(definition, canvasFactory)
        {
        }

        ScaleParameters IChartRenderer.GetScaleParameters()
        {
            return new ScaleParameters
            {
                X = new AxisScaleParameters { ScaleType = ScaleType.Linear },
                Y = new AxisScaleParameters { ScaleType = ScaleType.Linear }
            };
        }

        ParameterBag IChartRenderer.Plot(/* TODO: IPreferences*/ ITemplateHost _, bool isForReturnedParametersOnly)
        {
            const int MARKER_SIZE = 6;

            if (isForReturnedParametersOnly)
                return new ParameterBag();

            PolynomialRegressionOptions options = (PolynomialRegressionOptions)Definition.ChartOptions;

            StartVectorPlot();
            AssignMarkersToSeries();

            AxisScales axisScales = LayoutChartAndDrawAxes(options.Title,
                new AxisDefinition(options.XAxisTitle, AxisMode.Scale, Definition.ScaleParameters.X.ScaleType),
                new AxisDefinition(options.YAxisTitle, AxisMode.Scale, Definition.ScaleParameters.Y.ScaleType),
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

            MathDbl.civ(options.nx - options.p, out double cit, options.gamma, out double _);
            double rdf = Convert.ToDouble(options.nx - 1 - (options.p - 1));
            double rms = options.rss / rdf;
            double[] px = new double[options.p + 1];
            px[1] = 1.0;
            //  Fine enough for the curve and its bands to look curved: two steps a tic (16 segments in the help's example) was visibly angular.
            //  Not much finer than this, though: EmfCanvas rounds the ends of each line to whole pixels, which shows as a wobble when the segments are only a few pixels long.
            double xstep = (axisScales.X.MaximumScaleValue - axisScales.X.MinimumScaleValue) / 64.0;

            // This routine has changed from the original
            // It is more efficient in drawing - but bigger in code
            // Draw the base line
            {
                double oldx = Constant.MISSING;
                double oldy = Constant.MISSING;
                for (double calcx = axisScales.X.MinimumScaleValue; calcx <= axisScales.X.MaximumScaleValue; calcx += xstep)
                {
                    double calcy = 0;
                    for (int jj = 1; jj <= options.p; jj++)
                        calcy += options.bd[jj] * Math.Pow(calcx, Convert.ToDouble(jj - 1));
                    double x1 = calcx;
                    double y1 = calcy;
                    MaybeDrawLineInChartCoordinates(axisScales, GrGreen, x1, y1, oldx, oldy);
                    oldx = x1;
                    oldy = y1;
                }
            }
            if (options.mode > 0)
            {
                double oldx = Constant.MISSING;
                double oldy = Constant.MISSING;
                // Draw -Lines
                for (double calcx = axisScales.X.MinimumScaleValue; calcx <= axisScales.X.MaximumScaleValue; calcx += xstep)
                {
                    double calcy = 0;
                    for (int jj = 1; jj <= options.p; jj++)
                        calcy += options.bd[jj] * Math.Pow(calcx, jj - 1);
                    px[1] = 1.0;
                    for (int k = 2; k <= options.p; k++)
                        px[k] = Math.Pow(calcx, k - 1);
                    double xcx = 0;
                    for (int i = 1; i <= options.p; i++)
                    {
                        double s = 0;
                        for (int k = 1; k <= options.p; k++)
                            s += options.xtxi[i, k] * px[k];
                        xcx += s * px[i];
                    }
                    double sey = Math.Sqrt(options.mode == 1 ? Math.Abs(rms * xcx) : Math.Abs(rms * (1.0 + xcx)));
                    double cl = cit * sey;
                    double x1 = calcx;
                    double y1 = calcy - cl;
                    MaybeDrawLineInChartCoordinates(axisScales, GrBlack, x1, y1, oldx, oldy);
                    oldx = x1;
                    oldy = y1;
                }
                // Draw +Lines
                oldx = Constant.MISSING;
                oldy = Constant.MISSING;
                for (double calcx = axisScales.X.MinimumScaleValue; calcx <= axisScales.X.MaximumScaleValue; calcx += xstep)
                {
                    double calcy = 0;
                    for (int jj = 1; jj <= options.p; jj++)
                        calcy += options.bd[jj] * Math.Pow(calcx, jj - 1);
                    px[1] = 1.0;
                    for (int k = 2; k <= options.p; k++)
                        px[k] = Math.Pow(calcx, k - 1);
                    double xcx = 0;
                    for (int i = 1; i <= options.p; i++)
                    {
                        double s = 0;
                        for (int k = 1; k <= options.p; k++)
                            s += options.xtxi[i, k] * px[k];
                        xcx += s * px[i];
                    }
                    double sey = Math.Sqrt(options.mode == 1 ? Math.Abs(rms * xcx) : Math.Abs(rms * (1.0 + xcx)));
                    double cl = cit * sey;
                    double x1 = calcx;
                    double y1 = calcy + cl;
                    MaybeDrawLineInChartCoordinates(axisScales, GrBlack, x1, y1, oldx, oldy);
                    oldx = x1;
                    oldy = y1;
                }
            }
            EndVectorPlot();
            return new ParameterBag();
        }
    }
}
