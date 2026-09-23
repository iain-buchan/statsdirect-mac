using System;
using System.Collections.Generic;

namespace StatsDirect.Templates
{
    /// <summary>
    /// The x axis of a histogram: it runs from the lowest bin edge to the highest, with a tic at the mid-point of every bin.  That is how the bins are
    /// specified in the histogram dialog and how the help describes the axis, and it is what earlier versions drew; a scale of neat round values put the
    /// labels between the bars.  Labels are written with the fewest decimals that place them within a twentieth of a bin of the mid-point, and when they
    /// would crowd the axis only every second, third ... mid-point is labelled (the tics stay).  Visitors see an ordinary linear scale with one interval per bin.
    /// </summary>
    public class HistogramAxisScale : LinearAxisScale
    {
        private const int MaximumLabelledTics = 20;
        private const int CharactersAcrossAxis = 100; // the axis is about 950 canvas units wide and a digit of the axis font about 10 units

        public HistogramAxisScale(double lowestEdge, double highestEdge, int bins)
            : base(lowestEdge, highestEdge, lowestEdge, highestEdge, Math.Max(bins, 1))
        {
        }

        public override IList<Tic> Tics()
        {
            double[] midpoints = new double[Intervals];
            for (int i = 0; i < Intervals; i++)
            {
                double midpoint = MinimumScaleValue + Interval * (i + 0.5);
                //  A mid-point that should be zero can come out as -2.8e-17, which would be labelled "-0.0"
                midpoints[i] = Math.Abs(midpoint) < Math.Abs(Interval) * 1e-9 ? 0.0 : midpoint;
            }
            //  Exact mid-points when they are short (typed bins: 0.0, 0.4 ... or 0.125, 0.375 ...); otherwise the fewest decimals that put every label within a
            //  fortieth of a bin of its mid-point (automatic bins: 0.27, 0.61 ...); otherwise (values around 1e-8) three significant figures.
            int decimals = DecimalsToLabelWithin(midpoints, Math.Abs(Interval) * 1e-9, 4);
            if (decimals < 0)
                decimals = DecimalsToLabelWithin(midpoints, Math.Abs(Interval) / 40.0, 6);
            string format = decimals < 0 ? "G3" : decimals == 0 ? "0" : "0." + new string('0', decimals);
            string[] labels = new string[Intervals];
            int longest = 0;
            for (int i = 0; i < Intervals; i++)
            {
                labels[i] = Label(midpoints[i], format, decimals);
                longest = Math.Max(longest, labels[i].Length);
            }
            int labelEvery = Math.Max((Intervals + MaximumLabelledTics - 1) / MaximumLabelledTics,
                                      (Intervals * (longest + 1) + CharactersAcrossAxis - 1) / CharactersAcrossAxis);
            List<Tic> tics = new(Intervals);
            for (int i = 0; i < Intervals; i++)
                tics.Add(new Tic(midpoints[i], i % labelEvery == 0 ? labels[i] : string.Empty));
            return tics;
        }

        /// <summary>
        /// The fewest decimal places, up to the maximum, at which every value rounds to within the allowed error of itself, or -1 if the maximum is not enough.
        /// The generic axis mask switched to exponent notation ("2.692308E-001") as soon as a value had more than six decimals, which the mid-points of
        /// automatically chosen bins usually have.
        /// </summary>
        private static int DecimalsToLabelWithin(double[] values, double allowedError, int maximumDecimals)
        {
            for (int decimals = 0; decimals <= maximumDecimals; decimals++)
            {
                bool closeEnough = true;
                foreach (double value in values)
                {
                    if (Math.Abs(Math.Round(value, decimals) - value) > allowedError)
                    {
                        closeEnough = false;
                        break;
                    }
                }
                if (closeEnough)
                    return decimals;
            }
            return -1;
        }

        private static string Label(double value, string format, int decimals)
        {
            double shown = decimals >= 0 ? Math.Round(value, decimals) : value;
            if (shown == 0.0)
                shown = 0.0; // a negative zero would print as "-0.0"
            return shown.ToString(format);
        }
    }
}
