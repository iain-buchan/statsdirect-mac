using System;
using StatsDirect.Numerics;

namespace StatsDirect.Data
{
    [Serializable]
    public class DoubleVariable : GenericVariable<double>
    {
        private double sum;
        private double min;
        private double max;
        private bool hasSummaries;

        public DoubleVariable()
        {
        }

        public DoubleVariable(double[] data)
            : base(data)
        {
        }

        public DoubleVariable(double[] data, string title)
            : base(data, title)
        {
        }

        public DoubleVariable(int length, string title)
            : base(length, title)
        {
        }

        protected override void Invalidate()
        {
            base.Invalidate();
            hasSummaries = false;
        }

        public double Sum
        {
            get
            {
                if (!hasSummaries)
                    CalculateSummaries();
                return sum;
            }
        }

        public double Min
        {
            get
            {
                if (!hasSummaries)
                    CalculateSummaries();
                return min;
            }
        }

        public double Max
        {
            get
            {
                if (!hasSummaries)
                    CalculateSummaries();
                return max;
            }
        }

        private void CalculateSummaries()
        {
            min = double.MaxValue;
            max = double.MinValue;
            sum = 0;
            foreach (double d in Data)
            {
                if (d != Constant.MISSING)
                {
                    sum += d;
                    if (d < min)
                        min = d;
                    if (d > max)
                        max = d;
                }
            }
            hasSummaries = true;
        }

        public override void Accept(IVariableVisitor visitor)
        {
            visitor.Visit(this);
        }

        public override void EnsureLengthAndPadWithMissing(int minimumLength)
        {
            EnsureLength(minimumLength, Constant.MISSING);
        }
    }
}
