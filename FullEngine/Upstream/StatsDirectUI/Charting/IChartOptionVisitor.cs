namespace StatsDirect.Charting
{
    public interface IChartOptionVisitor
    {
        void Visit(AgreementOptions options);
        void Visit(BiasMAOptions options);
        void Visit(BarOptions options);
        void Visit(BoxWhiskerOptions options);
        void Visit(ControlOptions options);
        void Visit(CorrelationOptions options);
        void Visit(Cox2Options options);
        void Visit(CoxSurvivalOrHazardOptions options);
        void Visit(ErrorBarOptions options);
        void Visit(EffectOptions options);
        void Visit(ForestOptions options);
        void Visit(GiniOptions options);
        void Visit(HistogramOptions options);
        void Visit(KaplanMeierOptions options);
        void Visit(LAbbeOptions options);
        void Visit(LadderOptions options);
        void Visit(LinearizedEstimationOptions options);
        void Visit(LinearRegressionOptions options);
        void Visit(LinearRegressionAndMaybeSeCiOrPredictionIntervalOptions options);
        void Visit(LogitOptions options);
        void Visit(MHOptions options);
        void Visit(NormalOptions options);
        void Visit(PolynomialRegressionOptions options);
        void Visit(PyramidOptions options);
        void Visit(ROCOptions options);
        void Visit(ScatterXYOptions options);
        void Visit(SpreadOptions options);
        void Visit(SurvivalOptions options);
        void Visit(TiesOptions options);
        void Visit(XyOptions options);
        void Visit(XyrOptions options);
        void Visit(XyzOptions options);
    }
}
