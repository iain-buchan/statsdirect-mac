using StatsDirect.Templates;

namespace StatsDirect.Charting.Renderer
{
    class XyzChartRenderer : AbstractXYZChartRenderer, IChartRenderer
    {
        public XyzChartRenderer(ChartDefinition definition, ICanvasFactory canvasFactory)
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

            XyzOptions options = (XyzOptions)Definition.ChartOptions;
            PlotXYZ(options.x, options.y, options.z, 1, options.x.Length - 1, options.XAxisTitle, options.YAxisTitle, options.Title, options.zPlot, options.minMaxY, new MarkerType { MarkerShape = MarkerShape.Circle, IsMarkerFilled = false, MarkerColor = ColorDescriptor.Black });
            return new ParameterBag();
        }
    }
}
