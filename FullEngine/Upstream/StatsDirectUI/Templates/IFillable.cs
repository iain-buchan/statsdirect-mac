namespace StatsDirect.Templates
{
    /// <summary>
    /// Marker interface for classes that can be passed to a template host for filling in
    /// </summary>
    public interface IFillable
    {
        string FillerToUse { get; }
    }
}
