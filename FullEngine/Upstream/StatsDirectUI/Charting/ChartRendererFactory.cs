using StatsDirect.Charting.Renderer;
using StatsDirect.Templates;

namespace StatsDirect.Charting
{
    /// <summary>
    /// Knows where to get the correct implementation of IChartRenderer for any given definition.
    /// </summary>
    public static class ChartRendererFactory
    {
        public static ICanvasFactory NULL_FACTORY = new NullCanvasFactory();

        public static ChartDefinition PrepForLater(ChartType chartType, ChartOptions options)
        {
            return PrepForLater(chartType, options, null, null);
        }

        public static ChartDefinition PrepForLater(ChartType chartType, ChartOptions options, DoubleSeries xSeries, DoubleSeries ySeries)
        {
            ChartDefinition cd = new() { ChartType = chartType, ChartOptions = options };
            if (null != xSeries)
                cd.AddXSeries(xSeries);
            if (null != ySeries)
                cd.AddYSeries(ySeries);
            // Called from code, and there's no other path for getting hold of the scale parameters, so force that here.
            _ = cd.ScaleParameters;
            return cd;
        }

        internal static ParameterBag PlotForResultsOnly(/* TODO: IPreferences*/ ITemplateHost host, ChartDefinition definition)
        {
            using IChartRenderer ch = ChartRendererFor(definition, NULL_FACTORY);
            return ch.Plot(host, true);
        }

        public static IChartRenderer ChartRendererFor(ChartDefinition chartDefinition, ICanvasFactory canvasFactory)
        {
            switch (chartDefinition.ChartType)
            {
                case ChartType.AgreementPair:
                    return new AgreementPairChartRenderer(chartDefinition, canvasFactory);
                case ChartType.Bar:
                    return new BarChartRenderer(chartDefinition, canvasFactory);
                case ChartType.BiasMA:
                    return new BiasMAChartRenderer(chartDefinition, canvasFactory);
                case ChartType.BoxWhisker:
                    return new BoxWhiskerChartRenderer(chartDefinition, canvasFactory);
                case ChartType.Control:
                    return new ControlChartRenderer(chartDefinition, canvasFactory);
                case ChartType.Correlation:
                    return new CorrelationChartRenderer(chartDefinition, canvasFactory);
                case ChartType.CoxSurvivalOrHazard:
                    return new CoxSurvivalOrHazardChartRenderer(chartDefinition, canvasFactory);
                case ChartType.Cox2:
                    return new Cox2ChartRenderer(chartDefinition, canvasFactory);
                case ChartType.Effect:
                    return new EffectChartRenderer(chartDefinition, canvasFactory);
                case ChartType.ErrorBar:
                    return new ErrorBarChartRenderer(chartDefinition, canvasFactory);
                case ChartType.Forest:
                    return new ForestChartRenderer(chartDefinition, canvasFactory);
                case ChartType.Gini:
                    return new GiniChartRenderer(chartDefinition, canvasFactory);
                case ChartType.Histogram:
                    return new HistogramChartRenderer(chartDefinition, canvasFactory);
                case ChartType.KaplanMeier:
                    return new KaplanMeierChartRenderer(chartDefinition, canvasFactory);
                case ChartType.LAbbe:
                    return new LAbbeChartRenderer(chartDefinition, canvasFactory);
                case ChartType.Ladder:
                    return new LadderChartRenderer(chartDefinition, canvasFactory);
                case ChartType.LinearizedEstimation:
                    return new LinearizedEstimationChartRenderer(chartDefinition, canvasFactory);
                case ChartType.LinearRegression:
                    return new LinearRegressionChartRenderer(chartDefinition, canvasFactory);
                case ChartType.LinearRegressionAndMaybeSeCiOrPredictionInterval:
                    return new LinearRegressionAndMaybeSeCiOrPredictionIntervalChartRenderer(chartDefinition, canvasFactory);
                case ChartType.LineXY:
                    return new ScatterChartRenderer(chartDefinition, canvasFactory);
                case ChartType.Logit:
                    return new LogitChartRenderer(chartDefinition, canvasFactory);
                case ChartType.MH:
                    return new MHChartRenderer(chartDefinition, canvasFactory);
                case ChartType.MHRD:
                    return new MHRDChartRenderer(chartDefinition, canvasFactory);
                case ChartType.Normal:
                    return new NormalChartRenderer(chartDefinition, canvasFactory);
                case ChartType.PolynomialRegression:
                    return new PolynomialRegressionChartRenderer(chartDefinition, canvasFactory);
                case ChartType.Pyramid:
                    return new PyramidChartRenderer(chartDefinition, canvasFactory);
                case ChartType.ROC:
                    return new RocChartRenderer(chartDefinition, canvasFactory);
                case ChartType.ScatterXY:
                    return new ScatterChartRenderer(chartDefinition, canvasFactory);
                case ChartType.Spread:
                    return new SpreadChartRenderer(chartDefinition, canvasFactory);
                case ChartType.StackedBar:
                case ChartType.StackedBar100Percent:
                    return new BarChartRenderer(chartDefinition, canvasFactory);
                case ChartType.Survival:
                    return new SurvivalChartRenderer(chartDefinition, canvasFactory);
                case ChartType.Ties:
                    return new TiesChartRenderer(chartDefinition, canvasFactory);
                case ChartType.Xy:
                    return new XyChartRenderer(chartDefinition, canvasFactory);
                case ChartType.Xy0To1:
                    return new Xy0To1ChartRenderer(chartDefinition, canvasFactory);
                case ChartType.Xyr:
                    return new XyrChartRenderer(chartDefinition, canvasFactory);
                case ChartType.Xyz:
                    return new XyzChartRenderer(chartDefinition, canvasFactory);
                default:
                    return new NotSetChartRenderer(chartDefinition, canvasFactory);
            }
        }
    }
}
