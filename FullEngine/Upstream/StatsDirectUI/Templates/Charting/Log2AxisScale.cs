using System;
using System.Collections.Generic;

namespace StatsDirect.Templates
{
    public class Log2AxisScale: IAxisScale
    {
        public double MinimumDataValue { get; }
        public double MaximumDataValue { get; }
        public double MinimumScaleValue => Math.Pow(2, MinimumPower);
        public double MaximumScaleValue => Math.Pow(2, MaximumPower);

        /// The number of intervals between tics (one less than the number of tics).  20 intervals = 21 tics - one extra at the end.
        private int MinimumPower { get; }
        private int MaximumPower { get; }

        public Log2AxisScale(double minimumDataValue, double maximumDataValue, int minimumPower, int maximumPower)
        {
            MinimumDataValue = minimumDataValue;
            MaximumDataValue = maximumDataValue;
            MinimumPower = minimumPower;
            MaximumPower = maximumPower;
        }

        /// <summary>
        /// Returns a linear list of tics constructed according to the parameters.
        /// </summary>
        public IList<Tic> Tics()
        {
            List<Tic> tics = new();
            for (int power = MinimumPower; power <= MaximumPower; power++)
            {
                double value = Math.Pow(2, power);
                tics.Add(new Tic(value, value.ToString("G")));
            }
            return tics;
        }

        void IAxisScale.Accept(IAxisScaleVisitor visitor)
        {
            visitor.Visit(this);
        }
    }
}