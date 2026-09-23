using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
// using Layout.Formatters;

namespace Layout.AxisLabelers
{
    /// <remarks>Implements the axis labeling routine described in 
    /// Talbot, Lin, and Hanrahan. An Extension of Wilkinson's Algorithm for Positioning Tick Labels on Axes, Infovis 2010.
    /// </remarks>
    internal class ExtendedAxisLabeler : AxisLabeler
    {
        private static readonly List<decimal> Q = new List<decimal> { 1m, 5m, 2m, 2.5m, 4m, 3m };
        private static readonly int Q_COUNT = Q.Count;
        private static readonly List<double> W = new List<double> { 0.25, 0.2, 0.5, 0.05 };
        // private static readonly List<Format> FORMATS;

        // private QuantitativeFormatter formatter;

        /*
        private static void AddUnitFormat(decimal unit, string name, Range logRange, double weight, double factoredWeight)
        {
            FORMATS.Add(new UnitFormat(unit, name, logRange, false, false, weight));
            FORMATS.Add(new UnitFormat(unit, name, logRange, false, true, weight));
            FORMATS.Add(new UnitFormat(unit, name, logRange, true, false, factoredWeight));
            FORMATS.Add(new UnitFormat(unit, name, logRange, true, true, factoredWeight));
        }

        private static void AddUnitFormat(decimal unit, string name, Range logRange, double factoredWeight)
        {
            FORMATS.Add(new UnitFormat(unit, name, logRange, true, false, factoredWeight));
            FORMATS.Add(new UnitFormat(unit, name, logRange, true, true, factoredWeight));
        }

        static ExtendedAxisLabeler()
        {
            FORMATS = new List<Format>();
            FORMATS.Add(new UnitFormat(1m, "", new Range(-4, 6), false, false, 1));
            AddUnitFormat(1000m, "K", new Range(3, 6), 0.75, 0.4);
            AddUnitFormat(1000000m, "M", new Range(6, 9), 0.75, 0.4);
            AddUnitFormat(1000000000m, "B", new Range(9, 12), 0.75, 0.4);
            AddUnitFormat(100m, "hundred", new Range(2, 3), 0.35);
            AddUnitFormat(1000m, "thousand", new Range(3, 6), 0.5);
            AddUnitFormat(1000000m, "million", new Range(6, 9), 0.5);
            AddUnitFormat(1000000000m, "billion", new Range(9, 12), 0.5);
            AddUnitFormat(0.01m, "hundredth", new Range(-2, -3), 0.3);
            AddUnitFormat(0.001m, "thousandth", new Range(-3, -6), 0.5);
            AddUnitFormat(0.000001m, "millionth", new Range(-6, -9), 0.5);
            AddUnitFormat(0.000000001m, "billionth", new Range(-9, -12), 0.5);
            FORMATS.Add(new ScientificFormat(true, false, 0.3));
            FORMATS.Add(new ScientificFormat(true, true, 0.3));
            FORMATS.Add(new ScientificFormat(false, false, 0.25));
            FORMATS.Add(new ScientificFormat(false, true, 0.25));
        }
        */

        public ExtendedAxisLabeler(Graphics g)
        {
            // formatter = new QuantitativeFormatter(g);
        }

        protected decimal FlooredMod(decimal a, decimal n)
        {
            return a - n * Math.Floor(a / n);
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

        protected double Simplicity(decimal q, int j, decimal lmin, decimal lmax, decimal lstep)
        {
            const decimal eps = 1e-10m;
            double n = Q_COUNT;
            double i = Q.IndexOf(q) + 1; // Assume 1-based index for scoring
            double v = FlooredMod(lmin, lstep) < eps && lmin <= 0 && lmax >= 0 ? 1 : 0;
            return 1 - i / n - j + v;
        }

        protected double MaxSimplicity(decimal q, int j)
        {
            double n = Q_COUNT;
            double i = Q.IndexOf(q) + 1; // Assume 1-based index for scoring
            const double v = 1;
            return 1 - i / n - j + v;
        }

        protected double Coverage(decimal dmin, decimal dmax, decimal lmin, decimal lmax)
        {
            return 1 - 0.5 * (double)(((dmax - lmax) * (dmax - lmax) + (dmin - lmin) * (dmin - lmin)) / (0.1m * (dmax - dmin) * 0.1m * (dmax - dmin)));
        }

        protected double MaxCoverage(decimal dataRange, decimal span)
        {
            if (span > dataRange)
            {
                decimal half = (span - dataRange) / 2;
                return 1 - 0.5 * (double)((half * half + half * half) / (0.1m * dataRange * 0.1m * dataRange));
            }
            return 1;
        }

        protected double Density(double r, double rt)
        {
            return 2 - Math.Max(r / rt, rt / r);
        }

        protected double MaxDensity(double r, double rt)
        {
            return r >= rt ? 2 - r / rt : 1;
        }

        private static double Weight(double simplicity, double coverage, double density, double legibility)
        {
            return W[0] * simplicity + W[1] * coverage + W[2] * density + W[3] * legibility;
        }

        public override Axis Generate(Options options, double density)
        {
            double space = options.Direction == AxisDirection.Horizontal ? options.Screen.Width : options.Screen.Height;

            decimal dmax = (decimal)options.DataRange.Max;
            decimal dmin = (decimal)options.DataRange.Min;

            if (dmax <= dmin)
                return null;

            Axis best = null;
            double bestScore = -2;
            decimal dataRange = dmax - dmin;

            for (int j = 1; j < int.MaxValue; j++)
            {
                foreach (decimal q in Q)
                {
                    double sm = MaxSimplicity(q, j);
                    if (Weight(sm, 1, 1, 1) < bestScore)
                    {
                        j = int.MaxValue - 1;
                        break;
                    }

                    for (int k = 2; k < int.MaxValue; k++)
                    {
                        double dm = MaxDensity(k / space, density);

                        if (Weight(sm, 1, dm, 1) < bestScore)
                            break;

                        decimal delta = dataRange / (k + 1) / (j * q);
                        
                        for (int z = (int)Math.Ceiling(Math.Log10((double)delta)); z < int.MaxValue; z++)
                        {
                            decimal step = j * q * Pow10(z);
                            double cm = MaxCoverage(dataRange, step * (k - 1));

                            if (Weight(sm, cm, dm, 1) < bestScore)
                                break;

                            int minStart = (int)Math.Floor(dmax / step) * j - (k - 1) * j;
                            int maxStart = (int)Math.Ceiling(dmin / step) * j;
                            if (minStart > maxStart)
                                continue;

                            for (int start = minStart; start <= maxStart; start++)
                            {
                                decimal lmin = start * step / j;
                                decimal lmax = lmin + step * (k - 1);

                                double s = Simplicity(q, j, lmin, lmax, step);
                                double d = Density(k / space, density);
                                double c = Coverage(dmin, dmax, lmin, lmax);

                                if (Weight(s, c, d, 1) < bestScore)
                                    continue;

                                Axis option = options.DefaultAxis();

                                List<decimal> stepSequence = Enumerable.Range(0, k).Select(x => lmin + x * step).ToList();
                                List<Tuple<decimal, string>> newlabels = stepSequence.Select(value => new Tuple<decimal, string>(value, value.ToString())).ToList();

                                option.Labels = newlabels;
                                option.Density = d;
                                option.Coverage = c;
                                option.Simplicity = s;
                                option.Score = Weight(option.Simplicity, option.Coverage, option.Density, /* option.Legibility */ 1);

                                /*
                                //format and choose best
                                List<Axis> subPossibilities = new List<Axis>() { option };
                                Axis optionFormatted = formatter.Format(
                                    formatter.VaryOrientation(formatter.VaryFontSize(subPossibilities, options)),
                                    formats,
                                    options,
                                    a => w[0] * a.Simplicity + w[1] * a.Coverage + w[2] * a.Granularity + w[3] * a.Legibility,
                                    bestScore);

                                double score = w[0] * optionFormatted.Simplicity + w[1] * optionFormatted.Coverage +
                                               w[2] * optionFormatted.Granularity + w[3] * optionFormatted.Legibility;

                                if (score > bestScore)
                                {
                                    bestScore = score;
                                    optionFormatted.Score = score;
                                    best = optionFormatted;
                                }
                                */
                                if (option.Score > bestScore)
                                {
                                    bestScore = option.Score;
                                    best = option;
                                }
                            }
                        }
                    }
                }
            }

            if (best == null)
                Console.WriteLine("WARNING: Extended algorithm found 0 solutions");
            else
                best.VisibleRange = new Range(Math.Min(options.VisibleRange.Min, (double)best.Labels.Min(t => t.Item1)), Math.Max(options.VisibleRange.Max, (double)best.Labels.Max(t => t.Item1)));
            return best;
        }
    }

}
