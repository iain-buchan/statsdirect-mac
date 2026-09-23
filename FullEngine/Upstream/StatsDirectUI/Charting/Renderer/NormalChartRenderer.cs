using System;
using Layout;
using StatsDirect.Builtins;
using StatsDirect.Charting.Scales;
using StatsDirect.Numerics;
using StatsDirect.Templates;

namespace StatsDirect.Charting.Renderer
{
    internal class NormalChartRenderer : AbstractXYChartRenderer, IChartRenderer
    {
        public NormalChartRenderer(ChartDefinition cd, ICanvasFactory canvasFactory)
            : base(cd, canvasFactory)
        {
        }

        ScaleParameters IChartRenderer.GetScaleParameters()
        {
            NormalOptions nOptions = (NormalOptions)Definition.ChartOptions;
            NormalOptions.ScoreMethod method = nOptions.Method;

            DoubleSeries xs0 = (DoubleSeries)Definition.XSeries[0];
            int rows = xs0.Points;

            double[] x = new double[rows];
            ExFortran.Rank(xs0.Data, x, 0, rows, 0, out double _);

            if (method == NormalOptions.ScoreMethod.ExpectedNormalOrder)
                if (rows > 4000)
                    method = NormalOptions.ScoreMethod.VanDerWaerden;

            int nn = xs0.Points;
            for (int j = 0; j < rows; j++)
            {
                int ifault;
                switch (method)
                {
                    case NormalOptions.ScoreMethod.VanDerWaerden:
                        //  van der Waerden, Conover P 396
                        x[j] = PDF.gauinv(x[j] / (Convert.ToDouble(nn) + 1.0), out ifault);
                        if (ifault != 0)
                            x[j] = Constant.MISSING;
                        break;
                    case NormalOptions.ScoreMethod.Blom:
                        //  Blom - Altman p143
                        x[j] = PDF.gauinv((x[j] - 0.375) / (Convert.ToDouble(nn) + 0.25), out ifault);
                        if (ifault != 0)
                            x[j] = Constant.MISSING;
                        break;
                    case NormalOptions.ScoreMethod.ExpectedNormalOrder:
                        //  expected normal order
                        x[j] = PDF.expnos(Convert.ToInt32(x[j]), nn);
                        break;
                    default:
                        throw new Exception("Unexpected score method");
                }
            }

            Layout.Range xRange = GetMinMaxArray(x, ScaleType.Linear);
            Layout.Range yRange = GetMinMaxArray(xs0.Data, ScaleType.Linear);
            return new ScaleParameters
            {
                X = { AllowedScaleTypes = new[] { ScaleType.Linear }, ScaleType = ScaleType.Linear, Min = xRange.Min, Max = xRange.Max },
                Y = { AllowedScaleTypes = new[] { ScaleType.Linear }, ScaleType = ScaleType.Linear, Min = yRange.Min, Max = yRange.Max }
            };
        }

        ///  <summary>
        ///  Plot normal scores for a single variable in XSeries.
        ///  </summary>
        ParameterBag IChartRenderer.Plot(/* TODO: IPreferences*/ ITemplateHost _, bool isForReturnedParametersOnly)
        {
            return PlotNormal(((DoubleSeries)Definition.XSeries[0]).Data, isForReturnedParametersOnly);
        }

        ///  <summary>
        ///  Plot normal scores for a single variable in XSeries.
        ///  </summary>
        ///  <remarks></remarks>
        internal ParameterBag PlotNormal(double[] y, bool isForReturnedParametersOnly)
        {
            NormalOptions nOptions = (NormalOptions)Definition.ChartOptions;
            NormalOptions.ScoreMethod method = nOptions.Method;
            bool shouldScaleZ = nOptions.ShouldScaleZ;

            int rows = y.Length;

            double sy = 0;
            for (int j = 0; j < rows; j++)
                sy += y[j];
            double ybar = sy / rows;
            double ssy = 0;
            for (int j = 0; j < rows; j++)
            {
                double d = y[j] - ybar;
                ssy += d * d;
            }
            double vary = ssy / rows;
            double sdy = Math.Sqrt(vary);

            double[] x = new double[rows];
            ExFortran.Rank(y, x, 0, rows, 0, out double _);

            if (method == NormalOptions.ScoreMethod.ExpectedNormalOrder)
                if (rows > 4000)
                    method = NormalOptions.ScoreMethod.VanDerWaerden;

            // Set label
            string lab = shouldScaleZ
                ? "Normal (" + Definition.XSeries[0].Title + ")"
                : method switch
                {
                    NormalOptions.ScoreMethod.VanDerWaerden => "Normal scores (van der Waerden)",
                    NormalOptions.ScoreMethod.Blom => "Normal scores (Blom)",
                    NormalOptions.ScoreMethod.ExpectedNormalOrder => "Expected normal order scores",
                    _ => throw new Exception("Unexpected score method"),
                };
            int nn = y.Length;
            for (int j = 0; j < rows; j++)
            {
                switch (method)
                {
                    case NormalOptions.ScoreMethod.VanDerWaerden:
                        {
                            //  van der Waerden, Conover P 396
                            x[j] = PDF.gauinv(x[j] / (nn + 1.0), out int ifault);
                            if (ifault != 0)
                                x[j] = Constant.MISSING;
                            break;
                        }
                    case NormalOptions.ScoreMethod.Blom:
                        {
                            //  Blom - Altman p143
                            x[j] = PDF.gauinv((x[j] - 0.375) / (nn + 0.25), out int ifault);
                            if (ifault != 0)
                                x[j] = Constant.MISSING;
                            break;
                        }
                    case NormalOptions.ScoreMethod.ExpectedNormalOrder:
                        //  expected normal order
                        x[j] = PDF.expnos(Convert.ToInt32(x[j]), nn);
                        break;
                    default:
                        throw new Exception("Unexpected score method");
                }
                if (shouldScaleZ && x[j] != Constant.MISSING)
                    x[j] = x[j] * sdy + ybar;
            }

            StartVectorPlot(nOptions);
            AssignMarkersToSeries(Definition.XSeries, nOptions);

            DataMinMax selectMinMaxY = DataMinMax.XCalc_YCalc;
            if (shouldScaleZ)
                selectMinMaxY = DataMinMax.XY_CalcTogether;
            MarkerType mt = ChartPreferences.MarkerTypes[0];
            if (null != nOptions.MarkerTypes && nOptions.MarkerTypes.Count >= 1)
                mt = nOptions.MarkerTypes[0];
            AxisScales axisScales = PlotXYInternal(x, y, lab, "Observed (" + Definition.XSeries[0].Title + ")", nOptions.Title, false, selectMinMaxY, mt.MarkerSize, mt.MarkerShape, mt.IsMarkerFilled, GetMarkerPen(mt), true, ChartAreaShape.Square);
            if (shouldScaleZ)
                DrawLineInChartCoordinates(AxisPen, axisScales.X.MinimumScaleValue, axisScales.Y.MinimumScaleValue, axisScales.X.MaximumScaleValue, axisScales.Y.MaximumScaleValue);
            EndVectorPlot();

            // Regression results
            SimpleLinearRegressionContext context = new(x, y, string.Empty, string.Empty);
            context.CalculateLeastSquaresMethod();
            return new ParameterBag("context", FilledParameterFactory.Output(context));
        }
    }
}
