using StatsDirect.Templates;

namespace StatsDirect.Charting.Scales
{
    public class DateAxisScaler: IAxisScaler
    {
        public IAxisScale QAxis(double minimumDataValue, double _, double maximumDataValue, bool isYAxis, bool useDataValuesAsScaleValues)
        {
            return new DateAxisScale(minimumDataValue, maximumDataValue, minimumDataValue, maximumDataValue);
        }
    }
}
