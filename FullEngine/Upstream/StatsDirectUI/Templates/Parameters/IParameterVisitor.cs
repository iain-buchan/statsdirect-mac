namespace StatsDirect.Templates
{
    public interface IParameterVisitor
    {
        void Visit(BooleanParameter parameter);
        void Visit(UI.ChartOptionsParameter parameter);
        void Visit(ConfidenceIntervalParameter parameter);
        void Visit(DateParameter parameter);
        void Visit(Double2By2Parameter parameter);
        void Visit(Double2By2ByKParameter parameter);
        void Visit(DoubleParameter parameter);
        void Visit(EditGridParameter parameter);
        void Visit(UI.FillableParameter parameter);
        void Visit(Frame2DParameter parameter);
        void Visit(FrameParameter parameter);
        void Visit(GroupedCovarianceParameter parameter);
        void Visit(IntegerParameter parameter);
        void Visit(OptionParameter parameter);
        void Visit(OptionsParameter parameter);
        void Visit(PickFromListParameter parameter);
        void Visit(PickVariablesParameter parameter);
        void Visit(SpecialParameter parameter);
        void Visit(StringParameter parameter);
    }
}
