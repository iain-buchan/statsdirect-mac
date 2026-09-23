namespace StatsDirect.Charting
{
    public interface IChartSizable
    {
        void Accept(IChartSizableVisitor visitor);
    }
}
