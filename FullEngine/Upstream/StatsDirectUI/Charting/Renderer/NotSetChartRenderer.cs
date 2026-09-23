using System;
using StatsDirect.Templates;

namespace StatsDirect.Charting.Renderer
{
    class NotSetChartRenderer : AbstractChartRenderer, IChartRenderer
    {
        public NotSetChartRenderer(ChartDefinition definition, ICanvasFactory canvasFactory)
            : base(definition, canvasFactory)
        {
        }

        ScaleParameters IChartRenderer.GetScaleParameters()
        {
            throw new NotImplementedException();
        }

        ParameterBag IChartRenderer.Plot(/* TODO: IPreferences*/ ITemplateHost _, bool isForReturnedParametersOnly)
        {
            throw new NotImplementedException();
        }
    }
}
