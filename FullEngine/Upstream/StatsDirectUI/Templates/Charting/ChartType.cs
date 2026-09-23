namespace StatsDirect.Templates
{
    /// <summary>
    /// The type of chart that will be plotted
    /// </summary>
    public enum ChartType
    {
        NotSet = 0,
        AgreementPair,
        Bar,
        BiasMA,
        BoxWhisker,
        Control,
        Correlation,
        Cox2, // TODO: Better name
        CoxSurvivalOrHazard,
        Effect,
        ErrorBar,
        Forest,
        Gini,
        Histogram,
        KaplanMeier,
        LAbbe,
        Ladder,
        LinearizedEstimation,
        LinearRegression,
        LinearRegressionAndMaybeSeCiOrPredictionInterval,
        LineXY,
        Logit,
        MH,
        MHRD,
        Normal,
        PolynomialRegression,
        Pyramid,
        ROC,
        ScatterXY,
        Spread,
        StackedBar,
        StackedBar100Percent,
        Survival,
        Ties,
        Xy,
        Xy0To1,
        Xyr,
        Xyz
    };
}
