using System;
using System.Collections.Generic;

namespace StatsDirect.Templates
{
    public class Log10AxisScale: IAxisScale
    {
        public double MinimumDataValue { get; }
        public double MaximumDataValue { get; }
        public double MinimumScaleValue => Math.Pow(10, MinimumPower) * MinimumScaleTicMultiplier;
        public double MaximumScaleValue => Math.Pow(10, MaximumPower - 1) * MaximumScaleTicMultiplier;
        private int MinimumPower { get; }
        private int MinimumScaleTicMultiplier { get; }
        private int MaximumPower { get; }
        private int MaximumScaleTicMultiplier { get; }
        private IList<int> MinorTicMultipliers { get; }

        public Log10AxisScale(double minimumDataValue, double maximumDataValue, int minimumPower, int minimumScaleTicMultiplier, int maximumPower, int maximumScaleTicMultiplier, IList<int> minorTicMultipliers)
        {
            MinimumDataValue = minimumDataValue;
            MaximumDataValue = maximumDataValue;
            MinimumPower = minimumPower;
            MinimumScaleTicMultiplier = minimumScaleTicMultiplier;
            MaximumPower = maximumPower;
            MaximumScaleTicMultiplier = maximumScaleTicMultiplier;
            MinorTicMultipliers = minorTicMultipliers;
        }

        /// <summary>
        /// Returns a linear list of tics constructed according to the parameters.
        /// </summary>
        public IList<Tic> Tics()
        {
            List<Tic> tics = new();
            for (int power = MinimumPower; power < MaximumPower; power++)
            {
                double basePower = Math.Pow(10, power);
                if (basePower >= MinimumScaleValue && basePower <= MaximumScaleValue)
                    tics.Add(new Tic(basePower, basePower.ToString("G")));
                foreach (int multiplier in MinorTicMultipliers)
                {
                    double ticValue = basePower * multiplier;
                    if (ticValue >= MinimumScaleValue && ticValue <= MaximumScaleValue)
                        tics.Add(new Tic(ticValue, ticValue.ToString("G")));
                }
            }
            double lastMajorTicValue = Math.Pow(10, MaximumPower);
            if (lastMajorTicValue >= MinimumScaleValue && lastMajorTicValue <= MaximumScaleValue)
                tics.Add(new Tic(lastMajorTicValue, lastMajorTicValue.ToString("G")));
            return tics;
        }

        void IAxisScale.Accept(IAxisScaleVisitor visitor)
        {
            visitor.Visit(this);
        }
    }
}
