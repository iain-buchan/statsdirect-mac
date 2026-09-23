using System;
using StatsDirect.Templates;

namespace StatsDirect.Charting.Scales
{
    public class LogNaturalAxisScaler: IAxisScaler
    {
        ///  <summary>
        ///  Try to get a neat axis division suitable for values between qmin and qmax.
        ///  </summary>
        ///  <param name="minimumDataValue">The smallest value likely to be plotted on the axis. OUTPUT: May be modified if there are no values so that it is 0; will never otherwise be modified.</param>
        ///  <param name="minimumDataValueGreaterThanZero">The smallest value greater than zero likely to be plotted on the axis. Used for log scales; may be zero if scaleType is known to be Linear.</param>
        ///  <param name="maximumDataValue">The largest value likely to be plotted on the axis. OUTPUT: May be modified if there are no values so that it is 1; will never otherwise be modified.</param>
        public IAxisScale QAxis(double _, double minimumDataValueGreaterThanZero, double maximumDataValue, bool isYAxis, bool useDataValuesAsScaleValues)
        {
            if (minimumDataValueGreaterThanZero <= 0)
                throw new Exception("Cannot create a log axis with a minimum value less than or equal to zero");

            //  Start at the first power of 2 smaller than or equal to qmin, stop at the first power of 2 greater than or equal to qmax.
            double scaler = 1.0 / Math.Log(2.0);
            int minPower = (int)Math.Floor(Math.Log(minimumDataValueGreaterThanZero) * scaler);
            int maxPower = maximumDataValue <= 0 ? int.MinValue : (int)Math.Ceiling(Math.Log(Math.Max(maximumDataValue, minimumDataValueGreaterThanZero)) * scaler);
            return new Log2AxisScale(minimumDataValueGreaterThanZero, maximumDataValue, minPower, maxPower);
        }
    }
}
