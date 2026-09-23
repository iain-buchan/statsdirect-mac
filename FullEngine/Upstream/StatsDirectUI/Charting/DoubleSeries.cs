using System;
using StatsDirect.Numerics;

namespace StatsDirect.Charting
{
    public class DoubleSeries : ISeries
    {
        public double[] Data { get; set; }

        //  Similar to markers
        public MarkerType MarkerType { get; set; }

        private bool hasSum;
        private double sum;
        private bool hasStdDev;
        private double stdDev;
        private double min;
        private double minGreaterThanZero;
        private double max;
        private bool hasMinMax;

        public DoubleSeries()
        {
            MarkerType = new MarkerType();
        }

        public DoubleSeries(double[] data, string title)
            : this()
        {
            Data = data;
            Title = title;
        }

        public int Points => Data.Length;

        public double Sum
        {
            get
            {
                if (!hasSum)
                {
                    double s = 0.0;
                    for (int i = Data.GetLowerBound(0); i <= Data.GetUpperBound(0); i++)
                        if (Data[i] != Constant.MISSING)
                            s += Data[i];
                    sum = s;
                    hasSum = true;
                }
                return sum;
            }
        }

        public double StdDev
        {
            get
            {
                if (!hasStdDev)
                {
                    double avg = Sum / Convert.ToDouble(Points);
                    double ep = 0.0; double var = 0.0;
                    for (int C = Data.GetLowerBound(0); C <= Data.GetUpperBound(0); C++)
                    {
                        double s = Data[C] - avg;
                        ep += s;
                        var += s * s;
                    }
                    var = (var - Math.Pow(ep, 2.0) / Convert.ToDouble(Points)) / Convert.ToDouble(Points - 1);
                    stdDev = Math.Sqrt(var);
                    hasStdDev = true;
                }
                return stdDev;
            }
        }

        public double Min
        {
            get
            {
                if (!hasMinMax)
                    CalcMinMax();
                return min;
            }
        }

        public double MinGreaterThanZero
        {
            get
            {
                if (!hasMinMax)
                    CalcMinMax();
                return minGreaterThanZero;
            }
        }

        public double Max
        {
            get
            {
                if (!hasMinMax)
                    CalcMinMax();
                return max;
            }
        }

        public string Title { get; set; }

        private void CalcMinMax()
        {
            double mn = double.MaxValue;
            double mg0 = double.MaxValue;
            double mx = double.MinValue;
            for (int i = Data.GetLowerBound(0); i <= Data.GetUpperBound(0); i++)
            {
                double v = Data[i];
                if (v != Constant.MISSING)
                {
                    if (v < mn)
                        mn = v;
                    if (v > 0 && v < mg0)
                        mg0 = v;
                    if (v > mx)
                        mx = v;
                }
            }
            min = mn;
            minGreaterThanZero = mg0;
            max = mx;
            hasMinMax = true;
        }
    }
}
