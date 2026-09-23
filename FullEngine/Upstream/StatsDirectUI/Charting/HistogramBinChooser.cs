using System;
using StatsDirect.Charting.Scales;
using StatsDirect.Numerics;
using StatsDirect.Templates;

namespace StatsDirect.Charting
{
    public static class HistogramBinChooser
    {
        public static BinsDescriptor ChooseBins(double[] sortedX, int length, BinChoiceMethod binChoiceMethod)
        {
            switch (binChoiceMethod)
            {
                case BinChoiceMethod.Doane:
                    return ChooseBinsDoane(sortedX, length);
                case BinChoiceMethod.FreedmanDaconis:
                    return ChooseBinsFreedmanDaconis(sortedX, length);
                case BinChoiceMethod.OldStatsDirect:
                    return ChooseBinsOldStatsDirect(sortedX, length);
                case BinChoiceMethod.Shimazaki:
                    return ChooseBinsShimazaki(sortedX, length);
                case BinChoiceMethod.Stata:
                    return MkBinsDescriptor(sortedX, length, (int)Math.Min(Math.Sqrt(length), 10 * Math.Log10(length)));
                case BinChoiceMethod.Sturges:
                    return MkBinsDescriptor(sortedX, length, 1 + (int)Math.Ceiling(Log2(length)));
                case BinChoiceMethod.NotSet:
                default:
                    throw new ArgumentOutOfRangeException("Unknown bin choice method when choosing bins", binChoiceMethod, "binChoiceMethod");
            }
        }

        private static double Log2(double x)
        {
            return Math.Log(x) / Math.Log(2);
        }

        private static BinsDescriptor ChooseBinsFreedmanDaconis(double[] sortedX, int length)
        {
            Summary sx = new();
            sx.FullSummaryFromX(sortedX, length, null, 0.95, 5, 95, 1);

            // Note that this calculates the bin width, not the number of bins
            double h = 2 * sx.InterquartileRange / Math.Pow(length, 1.0 / 3.0);

            // Turn that width into a number of bins, +/- 0.5
            double xMin = sortedX[0];
            double xMax = sortedX[length - 1];
            double idealBinCount = (xMax - xMin) / h;
            return MkBinsDescriptor(sortedX, length, (int)Math.Round(idealBinCount));
        }

        private static BinsDescriptor ChooseBinsDoane(double[] sortedX, int length)
        {
            Summary sx = new();
            sx.FullSummaryFromX(sortedX, length, null, 0.95, 5, 95, 1);

            double sigmaG1 = Math.Sqrt(6.0 * (length - 2.0) / ((length + 1.0) * (length + 3.0)));
            double skewTerm = sx.Skewness == Constant.MISSING ? 0 : Math.Abs(sx.Skewness / sigmaG1);
            double k = 1 + Log2(length) + Log2(1 + skewTerm);
            return MkBinsDescriptor(sortedX, length, (int)Math.Round(k));
        }

        /// <summary>
        /// Create a descriptor of edges and counts given the original array+length, and the desired number of bins.
        /// </summary>
        /// <param name="sortedX"></param>
        /// <param name="length"></param>
        /// <param name="binCount"></param>
        /// <returns></returns>
        private static BinsDescriptor MkBinsDescriptor(double[] sortedX, int length, int binCount)
        {
            double xMin = sortedX[0];
            double xMax = sortedX[length - 1];
            double[] edges = Linspace(xMin, xMax, binCount); //  Bin edges
            int[] counts = SortedHist(sortedX, length, edges); //  Count # of events in bins
            return new BinsDescriptor { Edges = edges, Counts = counts };
        }

        /// <summary>
        /// Uses a cost function to estimate the optimal number of bins into which to place values sortedX[0] to sortedX[length - 1] to give an informative histogram.
        /// </summary>
        /// <returns>Edges for the most informative histogram according to the cost function.  Bin counts have also had to be calculated in order to estimate the cost function, so in order to save recalculation this returns the counts as well.</returns>
        /// <remarks>
        /// Histogram Binwidth Optimisation Method
        ///
        /// Shimazaki and Shinomoto, Neural Comput 19 1503-1527, 2007 
        /// 2006 Author Hideaki Shimazaki, Matlab
        /// Department of Physics, Kyoto University
        /// shimazaki at ton.scphys.kyoto-u.ac.jp
        /// Please feel free to use/modify this program.
        ///
        /// Version in python adapted Érbet Almeida Costa
        ///
        // /Bugfix by Takuma Torii 2.24.2013
        /// </remarks>
        private static BinsDescriptor ChooseBinsShimazaki(double[] sortedX, int length)
        {
            const int nMin = 4;   // Minimum number of bins (integer), N_MIN must be more than 1 (N_MIN > 1).
            const int nMax = 20;  // Maximum number of bins (integer)

            double xMin = sortedX[0];
            double xMax = sortedX[length - 1];

            double minCost = double.MaxValue;
            double[] bestCandidate = null;
            int[] bestCounts = null;
            for (int candidate = nMin; candidate <= nMax; candidate++)
            {
                double[] edges = Linspace(xMin, xMax, candidate + 1); //  Bin edges
                int[] ki = SortedHist(sortedX, length, edges); //  Count # of events in bins
                double k = Mean(ki); // Mean of event count
                double v = Variance(ki, k, candidate); // Variance of event count
                double d = (xMax - xMin) / candidate;
                double cost = (2 * k - v) / (d * d); // The cost function
                if (cost < minCost)
                {
                    minCost = cost;
                    bestCandidate = edges;
                    bestCounts = ki;
                }
            }

            return new BinsDescriptor { Edges = bestCandidate, Counts = bestCounts };
        }

        /// <summary>
        /// Returns an array of bin counts, placing values from sortedX[0] to sortedX[length - 1] into bins defined by edges.
        /// </summary>
        /// <param name="sortedX">Array of values to be counted into bins. PRECONDITION: This array must be sorted low to high by value.</param>
        /// <param name="edges">Bin edges.  The ith element in the returned array is the number of values in (edges[i], edges[i+1]]: a value equal to a bin's upper
        /// limit belongs to that bin, as the help describes.  Values at or below the lowest edge are counted in the first bin and values above the highest edge in the last.</param>
        public static int[] SortedHist(double[] sortedX, int length, double[] edges)
        {
            int bins = edges.Length - 1;
            int[] binCounts = new int[Math.Max(bins, 0)];
            if (bins < 1)
                return binCounts;
            //  Edges from Linspace carry floating-point error (0.6000000000000001 for 0.6), so a value exactly on an edge must be compared with a tolerance;
            //  without one the same chart counted the values on some edges upwards and those on others downwards.  The second term covers data whose
            //  magnitude dwarfs their range (values near 1e7 spanning less than 1), where the error sits in the edge's own last digits.
            double tolerance = Math.Max(Math.Abs(edges[bins] - edges[0]) * 1e-9, Math.Max(Math.Abs(edges[0]), Math.Abs(edges[bins])) * 1e-15);
            int bin = 0;
            for (int i = 0; i < length; i++)
            {
                while (bin < bins - 1 && sortedX[i] > edges[bin + 1] + tolerance)
                    bin++;
                binCounts[bin]++;
            }
            return binCounts;
        }

        /// <summary>
        /// Divide the number range [min, max] into pieces parts and return an array of pieces+1 values representing the lower and upper bounds of each piece.
        /// </summary>
        public static double[] Linspace(double min, double max, int pieces)
        {
            double[] edges = new double[pieces + 1];
            for (int i = 0; i < pieces; i++)
                edges[i] = min + (max - min) * (i / (double)pieces);
            edges[edges.Length - 1] = max;
            return edges;
        }

        /// <summary>
        /// Return the mean of the values in ki
        /// </summary>
        private static double Mean(int[] ki)
        {
            double sum = 0;
            for (int i = 0; i < ki.Length; i++)
                sum += ki[i];
            return sum / ki.Length;
        }

        /// <summary>
        /// Return the variance of the values in ki given that their mean is mean.
        /// </summary>
        /// <param name="ki"></param>
        /// <param name="mean"></param>
        /// <param name="divisor"></param>
        /// <returns></returns>
        private static double Variance(int[] ki, double mean, int divisor)
        {
            double sumSq = 0;
            for (int i = 0; i < ki.Length; i++)
                sumSq += (ki[i] - mean) * (ki[i] - mean);
            return sumSq / divisor;
        }

        private static void v_axis(double qmin, double qmax, int divisions, out double zMinimum, out double zInterval)
        {
            if (divisions > 0)
            {
                ILinearAxisScale output = LinearAxisScaler.v_axis(qmin, qmax, divisions);
                zMinimum = output.MinimumScaleValue;
                zInterval = output.Interval;
            }
            else
            {
                // 1 division of the whole range
                zMinimum = qmin;
                zInterval = qmax - qmin;
            }
        }

        ///  <summary>
        ///  
        ///  </summary>
        ///  <param name="oneOrMoreSeries">Input data. All data will be pooled for the purposes of calculating minimum and maximum values.</param>
        ///  <param name="binsFromUser">A user-entered bin count.</param>
        ///  <param name="calculateBinCount">If false, use the user-entered bin count.  If true, calculate from scratch.</param>
        ///  <param name="min">The lowest value in the input, minus 1 if there's only one value.</param>
        ///  <param name="max">The highest value in the input, plus 1 if there's only one value.</param>
        ///  <param name="bestMinimumMidpoint"></param>
        ///  <param name="bestMidpointInterval"></param>
        /// <param name="bestBinCount">The number of bins that should be used to plot the histogram.</param>
        /// <remarks></remarks>
        private static BinsDescriptor ChooseBinsOldStatsDirect(double[] sortedData, int length)
        {
            double minimumDataValue = sortedData[0];
            double maximumDataValue = sortedData[length - 1];

            //  Work out how many bins we should have at maximum: between 7 and 20, depending on the number of samples
            int maxBins = Convert.ToInt32(Math.Pow(length, 0.88) / 4.0);
            maxBins = Constrain(maxBins, 7, 20);

            int bestNonEmptyBins = 0;
            int bestBins = 0;
            for (int candidateBins = 1; candidateBins <= maxBins; candidateBins++)
            {
                v_axis(minimumDataValue, maximumDataValue, candidateBins - 1, out double candidateMinimumMidpoint, out double candidateMidpointInterval);

                // What about cm intervals (if cm < 10) or cm - 2 intervals (if cm >= 10)?
                int alternativeBins = candidateBins < 10 ? candidateBins + 1 : candidateBins - 1;
                v_axis(minimumDataValue, maximumDataValue, alternativeBins - 1, out double alternativeMinimumMidpoint, out double alternativeMidpointInterval);

                // Use whichever gives the "neater" axis (defined as shorter strings)
                int betterBinCount;
                double betterMidpointInterval;
                double betterMinimumMidpoint;
                if (alternativeMidpointInterval.ToString().Length + alternativeMinimumMidpoint.ToString().Length < candidateMidpointInterval.ToString().Length + candidateMinimumMidpoint.ToString().Length)
                {
                    betterMidpointInterval = alternativeMidpointInterval;
                    betterMinimumMidpoint = alternativeMinimumMidpoint;
                    betterBinCount = alternativeBins;
                }
                else
                {
                    betterMidpointInterval = candidateMidpointInterval;
                    betterMinimumMidpoint = candidateMinimumMidpoint;
                    betterBinCount = candidateBins;
                }

                // By the time we get here, betterBinCount, betterMinimumMidpoint, and betterMidpointInterval are set to the "neater" of the two options under consideration.
                // Now score this against our previous options: we prefer histograms with the largest number of non-empty bins, but we prefer smaller bin counts where the number of non-empty bins is equal.
                int firstIndexThisBin = 0;
                int nonEmptyBins = 0;
                for (int c = 1; c <= betterBinCount; c++)
                {
                    double high = betterMinimumMidpoint + betterMidpointInterval * (c - 1) + betterMidpointInterval / 2.0;
                    int firstIndexPastHigh;
                    for (firstIndexPastHigh = firstIndexThisBin; firstIndexPastHigh < length; firstIndexPastHigh++)
                    {
                        if (sortedData[firstIndexPastHigh] > high)
                            break;
                    }
                    int valuesInThisBin = firstIndexPastHigh - firstIndexThisBin;
                    if (valuesInThisBin > 0)
                        nonEmptyBins++;
                    firstIndexThisBin = firstIndexPastHigh;
                }
                if (nonEmptyBins > bestNonEmptyBins)
                {
                    bestNonEmptyBins = nonEmptyBins;
                    bestBins = betterBinCount;
                }
            }

            //  Ensure the total number of bins is between 1 and 20
            bestBins = Constrain(bestBins, 1, 20);

            // We didn't bother remembering our best minimum midpoint and midpoint intervals previously, so get them back now.
            v_axis(minimumDataValue, maximumDataValue, bestBins - 1, out double minimumMidpoint, out double midpointInterval);
            for (int c = 1; c <= 2; c++)
            {
                int nmp = bestBins - c;
                double nzmin;
                double nzint;
                if (nmp > 3)
                {
                    v_axis(minimumDataValue, maximumDataValue, nmp - 1, out nzmin, out nzint);
                    if (nzint.ToString().Length + nzmin.ToString().Length < midpointInterval.ToString().Length + minimumMidpoint.ToString().Length)
                    {
                        midpointInterval = nzint;
                        minimumMidpoint = nzmin;
                        bestBins = nmp;
                        break;
                    }
                }
                nmp = bestBins + c;
                if (nmp <= 20)
                {
                    v_axis(minimumDataValue, maximumDataValue, nmp - 1, out nzmin, out nzint);
                    if (nzint.ToString().Length + nzmin.ToString().Length < midpointInterval.ToString().Length + minimumMidpoint.ToString().Length)
                    {
                        midpointInterval = nzint;
                        minimumMidpoint = nzmin;
                        bestBins = nmp;
                        break;
                    }
                }
            }

            // Get rid of empty bins on the upper end of the histogram
            int c2 = length - 1;
            for (int c = bestBins - 1; c >= 0; --c)
            {
                double binLeft = minimumMidpoint + midpointInterval * c - midpointInterval / 2.0;
                bool thisBinHasData = false;
                for (int c1 = c2; c1 >= 0; c1--)
                {
                    if (sortedData[c1] > binLeft)
                    {
                        thisBinHasData = true;
                        c2 = c1;
                        break;
                    }
                }
                if (thisBinHasData)
                    break;
                else
                    --bestBins;
            }

            // Get rid of empty bins on the lower end of the histogram
            int emptyBinsLeft = 0;
            c2 = 0;
            for (int c = 0; c < bestBins; c++)
            {
                double binRight = minimumMidpoint + midpointInterval * c + midpointInterval / 2.0;
                bool thisBinHasData = false;
                for (int c1 = c2; c1 < length; c1++)
                {
                    if (sortedData[c1] <= binRight)
                    {
                        thisBinHasData = true;
                        c2 = c1 + 1;
                        break;
                    }
                }
                if (thisBinHasData)
                    break;
                else
                {
                    emptyBinsLeft++;
                    --bestBins;
                }
            }
            minimumMidpoint += midpointInterval * emptyBinsLeft;

            // Found what we're going to use; return the data.
            double[] edges = Linspace(minimumMidpoint - 0.5 * midpointInterval, minimumMidpoint + midpointInterval * (bestBins - 0.5), bestBins);
            int[] counts = SortedHist(sortedData, length, edges);
            BinsDescriptor descriptor = new() { Edges = edges, Counts = counts };
            return descriptor;
        }

        private static int Constrain(int value, int lowerBound, int upperBound)
        {
            if (value < lowerBound)
                return lowerBound;
            if (value > upperBound)
                return upperBound;
            return value;
        }
    }
}
