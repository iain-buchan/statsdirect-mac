using StatsDirect.Templates;

namespace StatsDirect.Charting.Renderer
{
    class Xy0To1ChartRenderer : AbstractXYChartRenderer, IChartRenderer
    {
        public Xy0To1ChartRenderer(ChartDefinition definition, ICanvasFactory canvasFactory)
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
            if (isForReturnedParametersOnly)
                return new ParameterBag();

            XyOptions options = (XyOptions)Definition.ChartOptions;
            StartVectorPlot();
            PlotXYInternal(options.X, options.Y, options.XAxisTitle, options.YAxisTitle, options.Title, options.ZPlot, options.MinMaxY, 6, MarkerShape.Circle, false, PenDescriptor.Black, false, ChartAreaShape.Default, 0, 1, 0, 1);
            EndVectorPlot();
            return new ParameterBag();
        }
    }
}
