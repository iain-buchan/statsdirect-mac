using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using StatsDirect.Templates;

namespace StatsDirect.Charting.Scales
{
    public static class LinearAxisMasker
    {
        /// <summary>
        /// Work out a sensible axis mask for the given linear scale, whose tics are at the given values.
        /// The values are passed in rather than taken from axisScale.Tics(), because a scale calls this while building its tics and would otherwise recurse.
        /// </summary>
        public static string AxisMask(IAxisScale axisScale, IEnumerable<double> ticValues)
        {
            int numberOfDecimalPlaces = DecimalPlaces(ticValues);

            // Count characters before the decimal point
            int maxCharactersBeforeDecimalPoint = 1;
            double x = Math.Abs(axisScale.MaximumScaleValue);
            if (x > 0.0)
                maxCharactersBeforeDecimalPoint += Math.Abs((int)Math.Floor(Math.Log10(x)));

            // Add space for a leading minus sign if required
            if (axisScale.MinimumScaleValue < 0)
                maxCharactersBeforeDecimalPoint++;

            // If we're into the millions, exponent notation is shorter.  Similarly, if we have tiny intervals, exponent notation is shorter.
            if (maxCharactersBeforeDecimalPoint > 6 || numberOfDecimalPlaces > 6)
                return "E";

            // If we get here, we have 1 to 5 characters before the decimal point and a non-negative number of decimal places.  The most common case!
            string axisMask = new string('#', maxCharactersBeforeDecimalPoint - 1) + "0.";
            if (numberOfDecimalPlaces > 0)
                axisMask += new string('0', numberOfDecimalPlaces);

            // If the mask is over 9 characters long, again use exponent notation.
            if (axisMask.Length > 9)
                return "E";

            // Otherwise, use the calculated mask.
            return axisMask;
        }

        private static int DecimalPlaces(IEnumerable<double> ticValues)
        {
            return ticValues
                .Select(DecimalPlaces)
                .DefaultIfEmpty(0)
                .Max();
        }

        private static int DecimalPlaces(double value)
        {
            const string INVARIANT_DECP_CHAR = ".";

            // How many decimal places in the printed value?  Print to 10 and strip trailing zeros
            string q = value.ToString("F10", CultureInfo.InvariantCulture);
            int xp = q.IndexOf(INVARIANT_DECP_CHAR, StringComparison.Ordinal) + 1;
            int rightmostZero = q.Length;
            while (rightmostZero > 0 && q[rightmostZero - 1] == '0')
                --rightmostZero;
            return xp == 0 ? 0 : rightmostZero - xp;
        }
    }
}
