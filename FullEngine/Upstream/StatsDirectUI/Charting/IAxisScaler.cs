using StatsDirect.Templates;

namespace StatsDirect.Charting
{
    public interface IAxisScaler
    {
        IAxisScale QAxis(double minimumDataValue, double minimumDataValueGreaterThanZero, double maximumDataValue, bool isYAxis, bool useDataValuesAsScaleValues);
    }
}