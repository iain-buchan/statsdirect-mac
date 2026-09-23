namespace StatsDirect.Templates
{
    public interface IAxisScaleVisitor
    {
        void Visit(CategoryAxisScale _);
        void Visit(DateAxisScale _);
        void Visit(LinearAxisScale _);
        void Visit(Log10AxisScale _);
        void Visit(Log2AxisScale _);
        void Visit(TalbotLinHanrahanAxisScale _);
    }
}