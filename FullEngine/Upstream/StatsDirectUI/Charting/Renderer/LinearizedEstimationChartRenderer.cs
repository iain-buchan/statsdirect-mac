using StatsDirect.Charting.Scales;
using StatsDirect.Numerics;
using StatsDirect.Templates;
using System;
using System.Drawing;

namespace StatsDirect.Charting.Renderer
{
    class LinearizedEstimationChartRenderer : AbstractChartRenderer, IChartRenderer
    {
        public LinearizedEstimationChartRenderer(ChartDefinition definition, ICanvasFactory canvasFactory)
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

            LinearizedEstimationOptions options = (LinearizedEstimationOptions)Definition.ChartOptions;

            StartVectorPlot();
            AssignMarkersToSeries();
            //  What extra space do we need before the X axis?
            double xtra = 0;
            if (Definition.XSeries.Count > 1)
            {
                foreach (ISeries s in Definition.XSeries)
                {
                    double w = LegendWidthInCanvasCoordinates(s.Title);
                    if (w > xtra)
                        xtra = w;
                }
            }

            AxisScales axisScales = LayoutChartAndDrawAxes(options.Title,
                new AxisDefinition(options.XAxisTitle, AxisMode.Scale, Definition.ScaleParameters.X.ScaleType) { ExtraSpaceBeforeAxisStarts = xtra },
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
                if (xdat[r] != Constant.MISSING & ydat[r] != Constant.MISSING)
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

            double xstep = (axisScales.X.MaximumScaleValue - axisScales.X.MinimumScaleValue) / axisScales.X.Tics().Count / 2;

            // Plot regression
            PenDescriptor p = new(GrBlack, 2);
            double oldx = Constant.MISSING;
            double oldy = Constant.MISSING;
            for (double calcx = axisScales.X.MinimumScaleValue; calcx <= axisScales.X.MaximumScaleValue; calcx += xstep)
            {
                double calcy;
                switch (options.Model)
                {
                    case 0:
                        calcy = options.A * Math.Exp(options.B * calcx);
                        break;
                    case 1:
                        calcy = options.A * Math.Pow(calcx, options.B);
                        break;
                    case 2:
                        double denom = options.A + calcx * options.B;
                        if (denom == 0.0)
                            denom = 0.0000001;
                        calcy = calcx / denom;
                        break;
                    default:
                        throw new Exception("Unknown mode");
                }

                if (oldx >= axisScales.X.MinimumScaleValue && oldx <= axisScales.X.MaximumScaleValue
                    && calcy >= axisScales.Y.MinimumScaleValue && calcy <= axisScales.Y.MaximumScaleValue
                    && oldy >= axisScales.Y.MinimumScaleValue && oldy <= axisScales.Y.MaximumScaleValue)
                    DrawLineInChartCoordinates(p, calcx, calcy, oldx, oldy);
                oldx = calcx;
                oldy = calcy;
            }
            EndVectorPlot();
            return new ParameterBag();
        }
    }
}
