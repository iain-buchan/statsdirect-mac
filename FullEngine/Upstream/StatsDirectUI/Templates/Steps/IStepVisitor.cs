namespace StatsDirect.Templates
{
    public interface IStepVisitor
    {
        void Visit(BuiltinStep step);
        void Visit(ChartStep step);
        void Visit(IterationStep step);
        void Visit(OutputFrameStep step);
        void Visit(ParametersStep step);
        void Visit(ReportStep step);
        void Visit(ScriptStep step);
        void Visit(TestStep step);
    }
}
