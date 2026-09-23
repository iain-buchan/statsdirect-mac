using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;

namespace Layout.Formatters
{
    public abstract class NumericFormat : Format
    {
        /// <summary>if true, 10^power portion will be placed on the axis title</summary>
        protected bool IsFactored { get; }
        /// <summary>if true, labels will be extended to the same number of decimal places</summary>
        protected bool DecimalExtend { get; }

        protected NumericFormat(bool isFactored, bool decimalExtend, double weight) : base(weight)
        {
            IsFactored = isFactored;
            DecimalExtend = decimalExtend;
        }

        public override double Score(IEnumerable<decimal> val)
        {
            return 0.9 * val.Select(x => x == 0 ? 1 : Weight * Score(x)).Average() + 0.1 * (DecimalExtend ? 1 : 0);
        }

        public abstract double Score(decimal d);

        public override Tuple<IEnumerable<string>, string> FormalLabels(IEnumerable<decimal> o)
        {
            return FormatLabels(o);
        }

        public abstract Tuple<IEnumerable<string>, string> FormatLabels(IEnumerable<decimal> d);

        protected int FloorLog10(decimal val)
        {
            return (int)Math.Floor(Math.Log10((double)Math.Abs(val)));
        }

        protected decimal Pow10(int i)
        {
            int modI = Math.Abs(i);
            decimal multiplier = i < 0 ? 0.1m : 10m;
            decimal a = 1m;
            for (int j = 0; j < modI; j++)
                a *= multiplier;
            return a;
        }

        protected int DecimalPlaces(decimal i)
        {
            string t = i.ToString("G29", CultureInfo.InvariantCulture);
            int s = t.IndexOf(".", StringComparison.Ordinal);
            return s < 0 ? 0 : t.Length - (s + 1);
        }
    }
}