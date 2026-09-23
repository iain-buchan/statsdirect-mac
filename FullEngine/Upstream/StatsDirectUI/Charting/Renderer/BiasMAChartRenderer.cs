using Layout;
using StatsDirect.Charting.Scales;
using StatsDirect.Numerics;
using StatsDirect.Templates;
using System;

namespace StatsDirect.Charting.Renderer
{
    class BiasMAChartRenderer : AbstractChartRenderer, IChartRenderer
    {
        public BiasMAChartRenderer(ChartDefinition definition, ICanvasFactory canvasFactory)
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

        ParameterBag IChartRenderer.Plot(/* TODO: IPreferences*/ ITemplateHost host, bool isForReturnedParametersOnly)
        {
            if (isForReturnedParametersOnly)
                return new ParameterBag();

            BiasMAOptions options = (BiasMAOptions)Definition.ChartOptions;
            bool useCi = false;
            int rows = options.rows;
            double cit = options.cit;
            double cco = options.cco;
            double[] x = options.x;
            GetMAOrdinate(host, out double[] y, options.yy, options.yw, options.cl, options.cu, ref cco, rows, out string title, out string ytxt, options.XAxisTitle, out int plotMethod, options.xform, out bool reverse, ref useCi);

            double[] xx = new double[rows + 1];
            xx[0] = Constant.MISSING;
            switch (options.xform)
            {
                case Transformation.Log:
                    for (int r = 1; r <= rows; r++)
                    {
                        if (x[r] > 0.0 && x[r] != Constant.MISSING)
                            xx[r] = Math.Log(x[r]);
                        else
                            xx[r] = Constant.MISSING;
                    }
                    break;
                case Transformation.Z:
                    for (int r = 1; r <= rows; r++)
                    {
                        if (x[r] != Constant.MISSING)
                            xx[r] = MathDbl.rtoz(x[r]);
                        else
                            xx[r] = Constant.MISSING;
                    }
                    break;
                case Transformation.None:
                    for (int r = 1; r <= rows; r++)
                        xx[r] = x[r];
                    break;
            }


            // get the Min and Max for the data
            Layout.Range dataRangeX = GetMinMaxArray(xx, ScaleType.Linear);
            DataMinX = dataRangeX.Min;
            DataMaxX = dataRangeX.Max;
            Layout.Range dataRangeY = GetMinMaxArray(y, ScaleType.Linear);
            DataMinY = dataRangeY.Min;
            DataMaxY = dataRangeY.Max;
            double pool = options.xform switch
            {
                Transformation.Log => Math.Log(options.rmh),
                Transformation.Z => MathDbl.rtoz(options.rmh),
                Transformation.None => options.rmh,
                _ => throw new ArgumentException("Unexpected transform: only Log, None, Z known")
            };
            ILinearAxisScale axisScale = (ILinearAxisScale)AxisScalerFactory.AxisScalerFor(ScaleType.Linear).QAxis(DataMinY, 0, DataMaxY, true, false);
            DataMinY = axisScale.MinimumDataValue;
            DataMaxY = axisScale.MaximumDataValue;
            double ymn = axisScale.MinimumScaleValue;
            double ymx = axisScale.MaximumScaleValue;
            double minInterval = Math.Min(axisScale.Interval, DataMinY);
            if (useCi)
            {
                double se = MAPlotStandardError(plotMethod == 2 ? ymn : ymx, minInterval, plotMethod);
                if (DataMaxX < pool + se * cit)
                    DataMaxX = pool + se * cit;
                if (DataMinX > pool - se * cit)
                    DataMinX = pool - se * cit;
            }

            string xtxt = options.XAxisTitle;
            switch (options.xform)
            {
                case Transformation.Log:
                    xtxt = "Log(" + xtxt + ")";
                    break;
                case Transformation.Z:
                    xtxt = "Fisher Z(" + xtxt + ")";
                    break;
                case Transformation.None:
                    //  Do nothing
                    break;
            }

            StartVectorPlot();
            // Peto plots are boxed
            AxisScales axisScales = LayoutChartAndDrawAxes(title,
                new AxisDefinition(xtxt, AxisMode.Scale, ScaleType.Linear),
                new AxisDefinition(ytxt, reverse ? AxisMode.ReverseScale : AxisMode.Scale, ScaleType.Linear),
                !reverse && options.diagonal, false);

            // plot the points
            for (int r = 1; r <= rows; r++)
                if (xx[r] != Constant.MISSING && y[r] != Constant.MISSING)
                    DrawMarkerInChartCoordinates(xx[r], y[r], 6, ChartPreferences.MarkerTypes[0]);

            if (!options.diagonal)
            {
                // mark pooled value
                DrawLineInChartCoordinates(GrBlack, pool, axisScales.Y.MinimumScaleValue, pool, axisScales.Y.MaximumScaleValue);
            }

            if ((plotMethod == 1 || plotMethod == 2 || plotMethod == 7) && !options.diagonal && useCi)
            {
                // plot confidence interval
                int incs = plotMethod == 1 ? 1 : 300;
                double yinc = (axisScales.Y.MaximumScaleValue - axisScales.Y.MinimumScaleValue) / incs;
                if (plotMethod == 2)
                {
                    double ynow = axisScales.Y.MaximumScaleValue;
                    double xnow = pool + MAPlotStandardError(ynow, minInterval, plotMethod) * cit;
                    double y1 = ynow;
                    double x1 = xnow;
                    for (int r = 1; r <= incs; r++)
                    {
                        ynow -= yinc;
                        xnow = pool + MAPlotStandardError(ynow, minInterval, plotMethod) * cit;
                        if (xnow >= axisScales.X.MinimumScaleValue && xnow <= axisScales.X.MaximumScaleValue)
                        {
                            MaybeDrawLineInChartCoordinates(axisScales, GrBlack, x1, y1, xnow, ynow);
                            y1 = ynow;
                            x1 = xnow;
                        }
                    }
                    ynow = axisScales.Y.MaximumScaleValue;
                    xnow = pool - MAPlotStandardError(ynow, minInterval, plotMethod) * cit;
                    y1 = ynow;
                    x1 = xnow;
                    for (int r = 1; r <= incs; r++)
                    {
                        ynow -= yinc;
                        xnow = pool - MAPlotStandardError(ynow, minInterval, plotMethod) * cit;
                        if (xnow >= axisScales.X.MinimumScaleValue && xnow <= axisScales.X.MaximumScaleValue)
                        {
                            MaybeDrawLineInChartCoordinates(axisScales, GrBlack, x1, y1, xnow, ynow);
                            y1 = ynow;
                            x1 = xnow;
                        }
                    }
                }
                else
                {
                    // Plot funnel
                    double ynow = axisScales.Y.MinimumScaleValue;
                    double xnow = pool;
                    double y1 = ynow;
                    double x1 = xnow;
                    for (int r = 1; r <= incs; r++)
                    {
                        ynow += yinc;
                        xnow = pool + MAPlotStandardError(ynow, minInterval, plotMethod) * cit;
                        if (xnow >= axisScales.X.MinimumScaleValue && xnow <= axisScales.X.MaximumScaleValue)
                        {
                            DrawLineInChartCoordinates(GrBlack, x1, y1, xnow, ynow);
                            y1 = ynow;
                            x1 = xnow;
                        }
                    }
                    ynow = axisScales.Y.MinimumScaleValue;
                    xnow = pool;
                    y1 = ynow;
                    x1 = xnow;
                    for (int r = 1; r <= incs; r++)
                    {
                        ynow += yinc;
                        xnow = pool - MAPlotStandardError(ynow, minInterval, plotMethod) * cit;
                        if (xnow >= axisScales.X.MinimumScaleValue && xnow <= axisScales.X.MaximumScaleValue)
                        {
                            DrawLineInChartCoordinates(GrBlack, x1, y1, xnow, ynow);
                            y1 = ynow;
                            x1 = xnow;
                        }
                    }
                }
            }

            if (options.diagonal)
                DrawLineInChartCoordinates(GrBlack, axisScales.X.MinimumScaleValue, axisScales.Y.MinimumScaleValue, axisScales.X.MaximumScaleValue, axisScales.Y.MaximumScaleValue);
            EndVectorPlot();
            return new ParameterBag();
        }

        private static void GetMAOrdinate(IPreferences host, out double[] y, double[] yy, double[] yw, double[] cl, double[] cu, ref double cco, int rows, out string title, out string ytx, string xtxt, out int plotMethod, Transformation xform, out bool reverse, ref bool useCi)
        {
            y = new double[rows + 1];
            y[0] = Constant.MISSING;
            if (xtxt == "Peto weights")
            {
                ytx = "Observed-Expected";
                title = "Peto O-E vs. V plot";
                plotMethod = 2;
                for (int r = 1; r <= rows; r++)
                {
                    if (yw[r] == 0.0 || yw[r] == Constant.MISSING)
                        y[r] = Constant.MISSING;
                    else
                        y[r] = 1.0 / yw[r];
                }
                reverse = false;
                return;
            }

            bool usept = xtxt.Contains("Incidence");
            useCi = host.Preferences.MetaPlotCI;

            if (cco <= 0.0)
                cco = 0.95;
            double cit = PDF.gauinv(1.0 - (1.0 - cco) / 2.0);

            plotMethod = host.Preferences.MetaPlotMethod;

            switch (plotMethod)
            {
                case 1:
                    reverse = true;
                    ytx = "Standard error";
                    switch (xform)
                    {
                        case Transformation.Log:
                            for (int r = 1; r <= rows; r++)
                            {
                                if (cu[r] == Constant.MISSING || cl[r] == Constant.MISSING || cu[r] <= 0.0 || cl[r] <= 0.0)
                                    y[r] = Constant.MISSING;
                                else
                                    y[r] = (Math.Log(cu[r]) - Math.Log(cl[r])) / 2.0 / cit;
                            }
                            break;
                        case Transformation.Z:
                            for (int r = 1; r <= rows; r++)
                            {
                                if (cu[r] == Constant.MISSING || cl[r] == Constant.MISSING)
                                    y[r] = Constant.MISSING;
                                else
                                    y[r] = (MathDbl.rtoz(cu[r]) - MathDbl.rtoz(cl[r])) / 2.0 / cit;
                            }
                            break;
                        case Transformation.None:
                            for (int r = 1; r <= rows; r++)
                            {
                                if (cu[r] == Constant.MISSING || cl[r] == Constant.MISSING)
                                    y[r] = Constant.MISSING;
                                else
                                    y[r] = (cu[r] - cl[r]) / 2.0 / cit;
                            }
                            break;
                    }

                    break;
                case 2:
                    reverse = false;
                    ytx = "Precision";
                    switch (xform)
                    {
                        case Transformation.Log:
                            for (int r = 1; r <= rows; r++)
                            {
                                if (cu[r] == Constant.MISSING || cl[r] == Constant.MISSING || cu[r] <= 0.0 || cl[r] <= 0.0)
                                    y[r] = Constant.MISSING;
                                else
                                    y[r] = (Math.Log(cu[r]) - Math.Log(cl[r])) / 2.0 / cit;
                                if (y[r] != 0.0 && y[r] != Constant.MISSING)
                                    y[r] = 1.0 / y[r];
                                else
                                    y[r] = Constant.MISSING;
                            }
                            break;
                        case Transformation.Z:
                            for (int r = 1; r <= rows; r++)
                            {
                                if (cu[r] == Constant.MISSING || cl[r] == Constant.MISSING)
                                    y[r] = Constant.MISSING;
                                else
                                    y[r] = (MathDbl.rtoz(cu[r]) - MathDbl.rtoz(cl[r])) / 2.0 / cit;
                                if (y[r] != 0.0 && y[r] != Constant.MISSING)
                                    y[r] = 1.0 / y[r];
                                else
                                    y[r] = Constant.MISSING;
                            }
                            break;
                        case Transformation.None:
                            for (int r = 1; r <= rows; r++)
                            {
                                if (cu[r] == Constant.MISSING || cl[r] == Constant.MISSING)
                                    y[r] = Constant.MISSING;
                                else
                                    y[r] = (cu[r] - cl[r]) / 2.0 / cit;
                                if (y[r] != 0.0 && y[r] != Constant.MISSING)
                                    y[r] = 1.0 / y[r];
                                else
                                    y[r] = Constant.MISSING;
                            }
                            break;
                    }

                    break;
                case 3:
                    reverse = true;
                    ytx = "1/Sample size";
                    for (int r = 1; r <= rows; r++)
                    {
                        if (yy[r] == 0.0)
                            y[r] = Constant.MISSING;
                        else
                            y[r] = 1.0 / yy[r];
                    }
                    break;
                case 4:
                    reverse = false;
                    ytx = "Sample size";
                    for (int r = 1; r <= rows; r++)
                        y[r] = yy[r];
                    break;
                case 5:
                    reverse = true;
                    ytx = "1/Log(sample size)";
                    for (int r = 1; r <= rows; r++)
                    {
                        if (yy[r] <= 0.0 || yy[r] == 1.0)
                            y[r] = Constant.MISSING;
                        else
                            y[r] = 1.0 / Math.Log10(yy[r]);
                    }
                    break;
                case 6:
                    reverse = false;
                    ytx = "Log(sample size)";
                    for (int r = 1; r <= rows; r++)
                    {
                        if (yy[r] <= 0.0)
                            y[r] = Constant.MISSING;
                        else
                            y[r] = Math.Log10(yy[r]);
                    }
                    break;
                case 7:
                    reverse = true;
                    ytx = "1/MH weight";
                    for (int r = 1; r <= rows; r++)
                    {
                        if (yw[r] == 0.0)
                            y[r] = Constant.MISSING;
                        else
                            y[r] = 1.0 / yw[r];
                    }
                    break;
                default:
                    throw new NotImplementedException("Unknown meta plot method");
            }

            if (usept)
                ytx = ytx.Replace("sample size", "person-time");
            title = "Bias assessment plot";
        }

        private static double MAPlotStandardError(double y, double z, int plotMethod)
            => plotMethod switch
            {
                1 => y,
                2 => y == 0.0
                    ? 1.0 / z
                    : 1.0 / y,
                7 => y < 0.0
                    ? 0.0
                    : Math.Sqrt(y),
                _ => 0,
            };
    }
}
