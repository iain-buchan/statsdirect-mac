using StatsDirect.Templates;

namespace StatsDirect.Charting.Renderer
{
    class LAbbeChartRenderer : AbstractXYZChartRenderer, IChartRenderer
    {
        public LAbbeChartRenderer(ChartDefinition definition, ICanvasFactory canvasFactory)
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

            LAbbeOptions options = (LAbbeOptions)Definition.ChartOptions;
            double[] y = new double[options.k + 1];
            double[] x = new double[options.k + 1];
            double[] w = new double[options.k + 1];
            for (int i = 1; i <= options.k; i++)
            {
                if (options.o[i, 1] + options.o[i, 3] == 0)
                    y[i] = 0;
                else
                    y[i] = options.o[i, 1] / (options.o[i, 1] + options.o[i, 3]);
                if (options.o[i, 2] + options.o[i, 4] == 0)
                    x[i] = 0;
                else
                    x[i] = options.o[i, 2] / (options.o[i, 2] + options.o[i, 4]);
                w[i] = options.o[i, 1] + options.o[i, 2] + options.o[i, 3] + options.o[i, 4];
            }
            PlotXYZ(x, y, w, 1, options.k, "control percent", "experimental percent", "L'Abbe plot (symbol size represents sample size)", false, 0, ChartPreferences.MarkerTypes[0], options.rmh);
            return new ParameterBag();
        }
    }
}
