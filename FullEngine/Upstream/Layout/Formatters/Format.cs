using System;
using System.Collections.Generic;

namespace Layout.Formatters
{
    public abstract class Format
    {
        protected double Weight { get; }

        protected Format(double weight)
        {
            Weight = weight;
        }

        public abstract double Score(IEnumerable<decimal> val);

        public abstract Tuple<IEnumerable<string>, string> FormalLabels(IEnumerable<decimal> o);
    }
}