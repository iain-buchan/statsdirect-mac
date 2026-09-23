using StatsDirect.Templates;

namespace StatsDirect.Charting.Renderer
{
    internal class GiniChartRenderer : AbstractChartRenderer, IChartRenderer
    {
        public GiniChartRenderer(ChartDefinition definition, ICanvasFactory canvasFactory)
            : base(definition, canvasFactory)
        {
        }

        ScaleParameters IChartRenderer.GetScaleParameters()
        {
            return new ScaleParameters
            {
                X =
                    {
                        AllowedScaleTypes = new[] { ScaleType.Linear },
                        Max = 1,
                        Min = 0
                    },
                Y =
                    {
                        AllowedScaleTypes = new[] { ScaleType.Linear },
                        Max = 1,
                        Min = 0
                    }
            };
        }

        ParameterBag IChartRenderer.Plot(/* TODO: IPreferences*/ ITemplateHost _, bool isForReturnedParametersOnly)
        {
            if (isForReturnedParametersOnly)
                return new ParameterBag();

            GiniOptions gOptions = (GiniOptions)Definition.ChartOptions;
            DoubleSeries xs0 = (DoubleSeries)Definition.XSeries[0];
            DoubleSeries ys0 = (DoubleSeries)Definition.YSeries[0];
            StartVectorPlot(gOptions);

            DataMinX = 0.0;
            DataMaxX = 1.0;
            DataMinY = 0.0;
            DataMaxY = 1.0;

            LayoutChartAndDrawAxes(gOptions.Title.Trim(),
                new AxisDefinition(gOptions.XAxisTitle, AxisMode.Scale, Definition.ScaleParameters.X.ScaleType),
                new AxisDefinition(gOptions.YAxisTitle, AxisMode.Scale, Definition.ScaleParameters.Y.ScaleType),
                true, false);

            // Draw equality line
            DrawLineInChartCoordinates(GrRed, 0, 0, 1, 1);

            // Draw Lorenz polygon
            PenDescriptor greenPen = new(GrGreen);
            double lastX = OffX;
            double lastY = OffY;
            for (int j = 0; j < xs0.Points; j++)
            {
                double x = ToCanvasX(xs0.Data[j]);
                double y = ToCanvasY(ys0.Data[j]);
                DrawLineInCanvasCoordinates(greenPen, lastX, lastY, x, y);
                lastX = x;
                lastY = y;
            }
            EndVectorPlot();
            return new ParameterBag();
        }
    }
}
