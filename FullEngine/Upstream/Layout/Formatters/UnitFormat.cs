using System;
using System.Collections.Generic;
using System.Linq;

namespace Layout.Formatters
{
    public class UnitFormat : NumericFormat
    {
        private readonly decimal unit;
        private readonly string name;
        private readonly Range potRange;

        public UnitFormat(decimal unit, string name, Range potRange, bool factored, bool decimalExtend, double weight)
            : base(factored, decimalExtend, weight)
        {
            this.unit = unit;
            this.name = name;
            this.potRange = potRange;
        }

        public override double Score(decimal d)
        {
            return FloorLog10(d) >= potRange.Min && FloorLog10(d) <= potRange.Max ? 1 : 0;
        }

        public override Tuple<IEnumerable<string>, string> FormatLabels(IEnumerable<decimal> d)
        {
            IEnumerable<decimal> r = from x in d select x / unit;
            int decimals = (from x in r select DecimalPlaces(x)).Max();
            return new Tuple<IEnumerable<string>, string>(from x in r select x.ToString(DecimalExtend ? "N" + decimals : "G29") + (IsFactored ? "" : name), IsFactored ? name : "");
        }
    }
}