namespace StatsDirect.Templates
{
    public interface ILinearAxisScale: IAxisScale
    {
        double Interval { get; }

        double FirstMajorTicValue { get; }
    }
}
