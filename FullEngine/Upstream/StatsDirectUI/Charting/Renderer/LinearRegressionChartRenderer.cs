using StatsDirect.Templates;

namespace StatsDirect.Charting.Renderer
{
    class LinearRegressionChartRenderer : AbstractLinearRegressionChartRenderer, IChartRenderer
    {
        public LinearRegressionChartRenderer(ChartDefinition cd, ICanvasFactory canvasFactory)
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

            LinearRegressionOptions options = (LinearRegressionOptions)Definition.ChartOptions;
            StartVectorPlot();
            PlotLinearRegression(options.Title, options.Slope, options.Intercept, options.FullWidth, options.XAxisTitle, options.YAxisTitle);
            EndVectorPlot();
            return new ParameterBag();
        }
    }
}
