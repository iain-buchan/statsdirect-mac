using System;
using StatsDirect.Charting.Scales;
using StatsDirect.Templates;

namespace StatsDirect.Charting.Renderer
{
    class LinearRegressionAndMaybeSeCiOrPredictionIntervalChartRenderer : AbstractLinearRegressionChartRenderer, IChartRenderer
    {
        public LinearRegressionAndMaybeSeCiOrPredictionIntervalChartRenderer(ChartDefinition cd, ICanvasFactory canvasFactory)
            : base(cd, canvasFactory)
        {
        }

        ScaleParameters IChartRenderer.GetScaleParameters()
        {
            return new ScaleParameters
            {
                X =
                    {
                        AllowedScaleTypes = new[] { ScaleType.Linear },
                        Max = DataMaxX,
                        Min = DataMinX
                    },
                Y =
                    {
                        AllowedScaleTypes = new[] { ScaleType.Linear },
                        Max = DataMaxY,
                        Min = DataMinY
                    }
            };
        }

        ParameterBag IChartRenderer.Plot(/* TODO: IPreferences*/ ITemplateHost _, bool isForReturnedParametersOnly)
        {
            if (isForReturnedParametersOnly)
                return new ParameterBag();

            LinearRegressionAndMaybeSeCiOrPredictionIntervalOptions options = (LinearRegressionAndMaybeSeCiOrPredictionIntervalOptions)Definition.ChartOptions;
            DoubleSeries xs = (DoubleSeries)Definition.XSeries[0];
            DoubleSeries ys = (DoubleSeries)Definition.YSeries[0];

            double maxpcon = double.MinValue;
            double minpcon = double.MaxValue;
            if (options.pert != 0)
            {
                for (double calcx = xs.Min; calcx <= xs.Max; calcx += (xs.Max - xs.Min) / 20.0)
                {
                    double calcy = options.Slope * calcx + options.Intercept;
                    double sey = Math.Sqrt(options.ms * (1.0 + (1.0 / Convert.ToDouble(options.nx) + Math.Pow(calcx - options.sumx / Convert.ToDouble(options.nx), 2.0) / options.ssx)));
                    double pconu = calcy + sey * options.pert;
                    double pconl = calcy - sey * options.pert;
                    if (pconu > maxpcon)
                        maxpcon = pconu;
                    if (pconl < minpcon)
                        minpcon = pconl;
                }
            }

            DataMinY = Math.Min(ys.Min, minpcon);
            DataMaxY = Math.Max(ys.Max, maxpcon);
            StartVectorPlot();
            AxisScales axisScales = PlotLinearRegression(options.Title, options.Slope, options.Intercept, options.FullWidth, options.XAxisTitle, options.YAxisTitle);
            if (options.pert != 0)
                PlotSeCiOrPredictionInterval(axisScales);
            EndVectorPlot();
            return new ParameterBag();
        }

        private void PlotSeCiOrPredictionInterval(AxisScales axisScales)
        {
            LinearRegressionAndMaybeSeCiOrPredictionIntervalOptions options = (LinearRegressionAndMaybeSeCiOrPredictionIntervalOptions)Definition.ChartOptions;
            double xstep = (axisScales.X.MaximumScaleValue - axisScales.X.MinimumScaleValue) / 20.0;

            if (options.isPredictionInterval)
            {
                if (options.pert != 0)
                {
                    double lastX1P = 0;
                    double lastY1P = 0;
                    double lastX1N = 0;
                    double lastY1N = 0;

                    bool first = true;
                    for (double calcx = axisScales.X.MinimumScaleValue; calcx <= axisScales.X.MaximumScaleValue; calcx += xstep)
                    {
                        double calcy = options.Slope * calcx + options.Intercept;
                        double sey = Math.Sqrt(options.ms * (1.0 + 1.0 / options.nx + Math.Pow(calcx - options.sumx / options.nx, 2.0) / options.ssx));
                        double pcon = calcy + sey * options.pert;
                        double x1P = calcx;
                        double y1P = pcon;
                        double ncon = calcy - sey * options.pert;
                        double x1N = calcx;
                        double y1N = ncon;
                        if (first)
                            first = false;
                        else
                        {
                            MaybeDrawLineInChartCoordinates(axisScales, GrBlack, lastX1P, lastY1P, x1P, y1P);
                            MaybeDrawLineInChartCoordinates(axisScales, GrBlack, lastX1N, lastY1N, x1N, y1N);
                        }
                        lastY1P = y1P;
                        lastX1P = x1P;
                        lastY1N = y1N;
                        lastX1N = x1N;
                    }
                }
            }
            else
            {
                if (options.pert != 0)
                {
                    double lastX1P = 0;
                    double lastY1P = 0;
                    double lastX1N = 0;
                    double lastY1N = 0;

                    bool first = true;
                    for (double calcx = axisScales.X.MinimumScaleValue; calcx <= axisScales.X.MaximumScaleValue; calcx += xstep)
                    {
                        double calcy = options.Slope * calcx + options.Intercept;
                        double sey = Math.Sqrt(options.ms * (1.0 / options.nx + Math.Pow(calcx - options.sumx / options.nx, 2.0) / options.ssx));
                        double pcon = calcy + sey * options.pert;
                        double x1P = calcx;
                        double y1P = pcon;
                        double ncon = calcy - sey * options.pert;
                        double x1N = calcx;
                        double y1N = ncon;
                        if (first)
                            first = false;
                        else
                        {
                            MaybeDrawLineInChartCoordinates(axisScales, GrBlack, lastX1P, lastY1P, x1P, y1P);
                            MaybeDrawLineInChartCoordinates(axisScales, GrBlack, lastX1N, lastY1N, x1N, y1N);
                        }
                        lastY1P = y1P;
                        lastX1P = x1P;
                        lastY1N = y1N;
                        lastX1N = x1N;
                    }

                    first = true;
                    for (double calcx = axisScales.X.MinimumScaleValue; calcx <= axisScales.X.MaximumScaleValue; calcx += xstep)
                    {
                        double calcy = options.Slope * calcx + options.Intercept;
                        double sey = Math.Sqrt(options.ms * (1.0 / options.nx + Math.Pow(calcx - options.sumx / options.nx, 2.0) / options.ssx));
                        double pcon = calcy + sey;
                        double x1P = calcx;
                        double y1P = pcon;
                        double ncon = calcy - sey;
                        double x1N = calcx;
                        double y1N = ncon;
                        if (first)
                            first = false;
                        else
                        {
                            MaybeDrawLineInChartCoordinates(axisScales, GrMagenta, lastX1P, lastY1P, x1P, y1P);
                            MaybeDrawLineInChartCoordinates(axisScales, GrMagenta, lastX1N, lastY1N, x1N, y1N);
                        }
                        lastY1P = y1P;
                        lastX1P = x1P;
                        lastY1N = y1N;
                        lastX1N = x1N;
                    }
                }
            }
        }
    }
}
