using System;
using StatsDirect.Charting.Scales;
using StatsDirect.Templates;

namespace StatsDirect.Charting
{
    public static class AxisScalerFactory
    {
        public static IAxisScaler AxisScalerFor(ScaleType scaleType)
        {
            switch (scaleType)
            {
                case ScaleType.Category:
                    // We don't have an axis scaler for a category axis, but it's legitimate to ask us.
                    return null;
                case ScaleType.Date:
                    return new DateAxisScaler();
                case ScaleType.Linear:
                    return new TalbotLinHanrahanAxisScaler();
                case ScaleType.Log10:
                    return new Log10AxisScaler();
                case ScaleType.LogNatural:
                    return new LogNaturalAxisScaler();
                // case ScaleType.NotSet:
                default:
                    throw new ArgumentOutOfRangeException(nameof(scaleType), scaleType, "AxisScalerFactory doesn't know how to create an AxisScaler for this scale type");
            }
        }
    }
}
