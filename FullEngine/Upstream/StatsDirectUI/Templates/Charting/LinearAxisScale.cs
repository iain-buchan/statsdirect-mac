using StatsDirect.Charting;
using System.Collections.Generic;
using StatsDirect.Charting.Scales;

namespace StatsDirect.Templates
{
    public class LinearAxisScale: ILinearAxisScale
    {
        public double MinimumDataValue { get; }
        public double MaximumDataValue { get; }
        public double MinimumScaleValue { get; }
        public double MaximumScaleValue { get; }
        /// The number of intervals between tics (one less than the number of tics).  20 intervals = 21 tics - one extra at the end.
        public int Intervals { get; }
        public double Interval => (MaximumScaleValue - MinimumScaleValue) / Intervals;

        public double FirstMajorTicValue => MinimumScaleValue + Interval;

        public LinearAxisScale(double minimumDataValue, double maximumDataValue, double minimumScaleValue, double maximumScaleValue, int intervals)
        {
            MinimumDataValue = minimumDataValue;
            MaximumDataValue = maximumDataValue;
            MinimumScaleValue = minimumScaleValue;
            MaximumScaleValue = maximumScaleValue;
            Intervals = intervals;
        }

        /// <summary>
        /// Returns a linear list of tics constructed according to the parameters.
        /// </summary>
        public virtual IList<Tic> Tics()
        {
            double interval = (MaximumScaleValue - MinimumScaleValue) / Intervals;
            double[] values = new double[Intervals + 1];
            for (int i = 0; i <= Intervals; i++)
                values[i] = MinimumScaleValue + interval * i;
            //  The mask is chosen from the values: the masker used to ask this scale for its Tics() to find them, which recursed until the stack overflowed.
            string msk = LinearAxisMasker.AxisMask(this, values);
            List<Tic> tics = new(Intervals + 1);
            foreach (double value in values)
                tics.Add(new Tic(value, value.ToString(msk)));
            return tics;
        }

        public override string ToString()
        {
            return $"LinearAxisScale({MinimumScaleValue}, {Intervals} * {Interval}, {MaximumScaleValue})";
        }

        void IAxisScale.Accept(IAxisScaleVisitor visitor)
        {
            visitor.Visit(this);
        }
    }
}
