using StatsDirect.Charting.Scales;
using StatsDirect.Numerics;
using StatsDirect.Templates;
using System;
using System.Drawing;

namespace StatsDirect.Charting.Renderer
{
    class LogitChartRenderer : AbstractXYZChartRenderer, IChartRenderer
    {
        public LogitChartRenderer(ChartDefinition definition, ICanvasFactory canvasFactory)
            : base(definition, canvasFactory)
        {
        }

        ScaleParameters IChartRenderer.GetScaleParameters()
        {
            LogitOptions options = (LogitOptions)Definition.ChartOptions;
            return new ScaleParameters
            {
                X = new AxisScaleParameters { ScaleType = options.modelIsLog10 ? ScaleType.Log10 : ScaleType.Linear },
                Y = new AxisScaleParameters { ScaleType = ScaleType.Linear }
            };
        }

        ParameterBag IChartRenderer.Plot(/* TODO: IPreferences*/ ITemplateHost _, bool isForReturnedParametersOnly)
        {
            if (isForReturnedParametersOnly)
                return new ParameterBag();

            LogitOptions options = (LogitOptions)Definition.ChartOptions;
            const int MARKER_SIZE = 6;

            DoubleSeries xs = (DoubleSeries)Definition.XSeries[0];
            DoubleSeries ys = (DoubleSeries)Definition.YSeries[0];
            double[] xdat = xs.Data;
            double[] ydat = ys.Data;

            double cl = 0;
            int nx = 0;
            foreach (double v in xdat)
            {
                if (v != Constant.MISSING)
                {
                    cl += options.modelIsLog10 ? Math.Log10(v) : v;
                    nx++;
                }
            }
            double xm = cl / nx;

            StartVectorPlot();
            AssignMarkersToSeries();
            if (DataMaxY - DataMinY > 0.25)
            {
                DataMaxY = 1;
                DataMinY = 0;
            }
            AxisScales axisScales = LayoutChartAndDrawAxes(options.Title,
                new AxisDefinition(options.XAxisTitle, AxisMode.Scale, Definition.ScaleParameters.X.ScaleType),
                new AxisDefinition(options.YAxisTitle, AxisMode.Scale, Definition.ScaleParameters.Y.ScaleType),
                false, false);

            // plot points
            PointF[] xys = new PointF[Math.Min(xdat.Length, ydat.Length)];
            for (int r = 0; r < Math.Min(xdat.Length, ydat.Length); r++)
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

            // Aim for 100 steps across the chart - anything coarser gives terrible resolution for tight curves (e.g. log10 of the sample data).
            double xstepCanvas = (ToCanvasWidth(axisScales.X.MaximumScaleValue) - ToCanvasWidth(axisScales.X.MinimumScaleValue)) / 100.0;

            // Draw central curve
            double oldx = Constant.MISSING;
            double oldy = Constant.MISSING;
            for (double xCanvas = ToCanvasWidth(axisScales.X.MinimumScaleValue); xCanvas <= ToCanvasWidth(axisScales.X.MaximumScaleValue); xCanvas += xstepCanvas)
            {
                double x = FromCanvasWidth(xCanvas);
                double calcX = options.modelIsLog10 ? Math.Log10(x) : x;
                double calcY = options.a + options.b * calcX;
                calcY = Remodel(options.model, calcY);
                MaybeDrawLineInChartCoordinates(axisScales, GrGreen, x, calcY, oldx, oldy);
                oldx = x;
                oldy = calcY;
            }

            // Draw upper and lower curves
            oldx = Constant.MISSING;
            oldy = Constant.MISSING;
            for (double calcxCanvas = ToCanvasWidth(axisScales.X.MinimumScaleValue); calcxCanvas <= ToCanvasWidth(axisScales.X.MaximumScaleValue); calcxCanvas += xstepCanvas)
            {
                double x = FromCanvasWidth(calcxCanvas);
                double calcX = options.modelIsLog10 ? Math.Log10(x) : x;
                cl = options.t * Math.Sqrt(1.0 / options.sw + Math.Pow(calcX - xm, 2.0) / options.s1);
                double calcY = options.a + options.b * calcX + cl;
                calcY = Remodel(options.model, calcY);
                MaybeDrawLineInChartCoordinates(axisScales, GrMagenta, x, calcY, oldx, oldy);
                oldx = x;
                oldy = calcY;
            }
            // Draw lower curve
            oldx = Constant.MISSING;
            oldy = Constant.MISSING;
            for (double calcxCanvas = ToCanvasWidth(axisScales.X.MinimumScaleValue); calcxCanvas <= ToCanvasWidth(axisScales.X.MaximumScaleValue); calcxCanvas += xstepCanvas)
            {
                double x = FromCanvasWidth(calcxCanvas);
                double calcX = options.modelIsLog10 ? Math.Log10(x) : x;
                cl = options.t * Math.Sqrt(1.0 / options.sw + Math.Pow(calcX - xm, 2.0) / options.s1);
                double calcY = options.a + options.b * calcX - cl;
                calcY = Remodel(options.model, calcY);
                MaybeDrawLineInChartCoordinates(axisScales, GrMagenta, x, calcY, oldx, oldy);
                oldx = x;
                oldy = calcY;
            }
            EndVectorPlot();
            return new ParameterBag();
        }

        private static double Remodel(int model, double calcY)
        {
            if (model == 1)
                return PDF.alnorm(calcY);
            return Math.Exp(calcY * 2.0) / (1.0 + Math.Exp(calcY * 2.0));
        }
    }
}
