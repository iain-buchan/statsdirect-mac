using System;
using StatsDirect.Numerics;
using StatsDirect.Templates;

namespace StatsDirect.Charting.Scales
{
    public class LinearAxisScaler: IAxisScaler
    {
        // Numbers of divisions to try in Q_Axis, in preference order
        private static readonly int[] DIVISIONS_TO_TRY = { 20, 15, 25, 16, 24 };
        // Scalers to try in ShiftMinMax, in preference order.
        private static readonly double[] AXIS_SCALERS = { 1.0, 0.5, 0.1, 0.2, 0.3, 0.4, 0.6, 0.8, 0.7, 0.9, 0.15, 0.25, 0.75, 0.05 };

        ///  <summary>
        ///  Try to get a neat axis division suitable for values between qmin and qmax.
        ///  </summary>
        ///  <param name="minimumDataValue">The smallest value likely to be plotted on the axis.</param>
        ///  <param name="minimumDataValueGreaterThanZero">The smallest value greater than zero likely to be plotted on the axis. Used for log scales; not used for LinearAxisScaler.</param>
        ///  <param name="maximumDataValue">The largest value likely to be plotted on the axis.</param>
        /// <param name="isYAxis"></param>
        /// <remarks></remarks>
        public IAxisScale QAxis(double minimumDataValue, double minimumDataValueGreaterThanZero, double maximumDataValue, bool isYAxis, bool useDataValuesAsScaleValues)
        {
            //  If we have no points at all, the choice is irrelevant so we might as well do it the easy way.
            if (minimumDataValue > maximumDataValue)
            {
                minimumDataValue = 0.0;
                maximumDataValue = 1.0;
            }

            // Short-circuit for the common case of a 0 to 1 axis.
            if (minimumDataValue == 0.0 && maximumDataValue == 1.0)
                return new LinearAxisScale(minimumDataValue, maximumDataValue, minimumDataValue, maximumDataValue, 5);

            int bestScoreSoFar = int.MaxValue; // Lower is better
            ILinearAxisScale bestScaleSoFar = null;
            foreach (int candidateDivisions in DIVISIONS_TO_TRY)
            {
                LinearAxisScale unshiftedAxisScale = Axis(minimumDataValue, maximumDataValue, candidateDivisions);
                ILinearAxisScale shiftedAxisScale = ShiftMinMax(minimumDataValue, maximumDataValue, unshiftedAxisScale, out int shiftedScore);
                NeatnessComparison neater = CompareNeatness(bestScaleSoFar, shiftedAxisScale);
                if (neater == NeatnessComparison.Second || neater == NeatnessComparison.Equal && shiftedScore < bestScoreSoFar)
                {
                    bestScoreSoFar = shiftedScore;
                    bestScaleSoFar = shiftedAxisScale;
                }
            }
            return bestScaleSoFar;
        }

        private enum NeatnessComparison
        {
            First,
            Equal,
            Second
        }

        private static NeatnessComparison CompareNeatness(ILinearAxisScale first, ILinearAxisScale second)
        {
            // If one of the scales doesn't exist (first won't on the first iteration), the other is automatically better
            if (null == first)
                return NeatnessComparison.Second;
            if (null == second)
                return NeatnessComparison.First;

            // Score the neatness of the two scales - lower is better.
            int firstScore = SignificantDigits(first.MinimumScaleValue) + SignificantDigits(first.FirstMajorTicValue);
            int secondScore = SignificantDigits(second.MinimumScaleValue) + SignificantDigits(second.FirstMajorTicValue);

            // If the axis doesn't span zero, that's it.
            if (!(first.MinimumScaleValue < 0.0 && first.MaximumScaleValue > 0.0))
                return secondScore == firstScore ? NeatnessComparison.Equal : secondScore < firstScore ? NeatnessComparison.Second : NeatnessComparison.First;

            // The axis spans zero. In this case, prefer the scale that hits zero on the way past, if there is one.  If neither do, use the earlier preference.
            const double tolerance = Constant.EPSNEG * 10.0;
            bool firstAxisScaleHitsZero = false;
            foreach (Tic tic in first.Tics())
                if (Math.Abs(tic.Value) < tolerance)
                {
                    firstAxisScaleHitsZero = true;
                    break;
                }

            if (secondScore < firstScore || !firstAxisScaleHitsZero)
            {
                foreach (Tic tic in second.Tics())
                    if (Math.Abs(tic.Value) < tolerance)
                        return NeatnessComparison.Second;

                // If we get here, the second scale doesn't hit zero. Either the second score is better or the first scale doesn't hit it either, however!
                return secondScore == firstScore ? NeatnessComparison.Equal : secondScore < firstScore ? NeatnessComparison.Second : NeatnessComparison.First;
            }

            // If we get here, secondScore is worse than firstScore and firstAxisScaleHitsZero, so the first scale is unambiguously better.
            return NeatnessComparison.First;
        }

        /// <summary>
        /// Given x, return the number of significant digits less 1 (the number of decimal places if the number was represented as n.nnnnnEnnn).
        /// </summary>
        /// <param name="x"></param>
        private static int SignificantDigits(double x)
        {
            if (x == 0.0)
                return 0;

            int ipow = (int)Math.Floor(Math.Log10(Math.Abs(x))) + 1;
            double sc = x / Math.Pow(10.0, ipow);
            if (sc == 1.0)
                return 1;
            return sc.ToString().Length - 2;
        }

        ///  <summary>
        ///  
        ///  </summary>
        ///  <param name="qmin">Smallest data value</param>
        ///  <param name="qmax">Largest data value</param>
        /// <param name="unshiftedAxisScale"></param>
        /// <param name="score">A score on an arbitrary scale of the "look" of this axis; lower scores are better</param>
        private static LinearAxisScale ShiftMinMax(double qmin, double qmax, LinearAxisScale unshiftedAxisScale, out int score)
        {
            // shift zmin to a nice spot
            double minimumScaleValue = unshiftedAxisScale.MinimumScaleValue;
            int div = unshiftedAxisScale.Intervals;
            double zint = unshiftedAxisScale.Interval;
            if (minimumScaleValue != 0.0)
            {
                // ipow is the first power of 10 above zmin. We can then scale by scalers from 0 to 1 (in ztry) to get values of the same order of magnitude as zmin.
                int ipow = (int)Math.Floor(Math.Log10(Math.Abs(minimumScaleValue))) + 1;
                // Scalers to try, in preference order.  We stop when we find the first one that meets the requirements.
                foreach (double candidate in AXIS_SCALERS)
                {
                    double nzmin = candidate * Math.Pow(10.0, ipow);
                    if (minimumScaleValue < 0.0)
                        nzmin = -nzmin;
                    double nzmax = nzmin + zint * div;
                    if (CheckCoverage(qmin, qmax, nzmin, nzmax))
                    { 
                            minimumScaleValue = nzmin;
                            break;
                    }
                    // The data values don't fit within the axis values.  If the problem is at the minimum end, there's not much
                    // we can do; if at the maximum end, we might be able to extend the axis by adding another major interval.
                    if (qmin < nzmin)
                        continue;

                    if (div % 5 == 0)
                    {
                        if (div < 25)
                        {
                            nzmax = nzmin + zint * (div + 5);
                            if (CheckCoverage(qmin, qmax, nzmin, nzmax))
                            {
                                minimumScaleValue = nzmin;
                                div += 5;
                                break;
                            }
                        }
                    }
                    else
                    {
                        if (div < 24)
                        {
                            nzmax = nzmin + zint * (div + 4);
                            if (CheckCoverage(qmin, qmax, nzmin, nzmax))
                            {
                                minimumScaleValue = nzmin;
                                div += 4;
                                break;
                            }
                        }
                    }
                }
            }

            // score the look of the ticks and labelled intervals
            score = ScoreIntervalLook(zint);
            int intervalsPerMajorTic = div % 5 == 0 ? 5 : 4;
            score += ScoreIntervalLook(minimumScaleValue + zint * intervalsPerMajorTic);

            return new LinearAxisScale(qmin, qmax, minimumScaleValue, minimumScaleValue + div * zint, div / intervalsPerMajorTic);
        }

        /// <summary>
        /// Returns true iff [qmin, qmax] fits within [nzmin, nzmax] and covers at least 70% of it.
        /// </summary>
        private static bool CheckCoverage(double qmin, double qmax, double nzmin, double nzmax)
        {
            // data must cover target% of interval
            const double TARGET_COVERAGE = 0.7;

            if (!(nzmin <= qmin && nzmax >= qmax))
                return false;
            double coverage = Math.Abs(qmax - qmin) / Math.Abs(nzmax - nzmin);
            return coverage > TARGET_COVERAGE;
        }

        /// <summary>
        /// Returns a score for the expected look to a human of the given interval. Lower scores are better.
        /// </summary>
        private static int ScoreIntervalLook(double interval)
        {
            int ipow = (int)Math.Floor(Math.Log10(Math.Abs(interval))) + 1;
            double scaled = interval / Math.Pow(10.0, ipow);
            // PJC: Many of the inputs have tiny calculation errors; ignore these in the scoring
            scaled = Math.Round(scaled, 10);
            if (scaled == 0.0 || scaled == 1.0)
                return 0;
            if (scaled == 0.5 || scaled == 0.1)
                return 1;
            if (scaled == 0.15 || scaled == 0.2 || scaled == 0.25 || scaled == 0.3)
                return 2;
            if (scaled == 0.4 || scaled == 0.6)
                return 3;
            return 4;
        }

        private static LinearAxisScale Axis(double minimumDataValue, double maximumDataValue, int divisions)
        {
            double zmin = minimumDataValue;
            double zmax = maximumDataValue;
            // Check for crazy values
            if (zmin == Constant.MISSING || zmax == Constant.MISSING || double.IsInfinity(zmin) || double.IsInfinity(zmax) || double.IsNaN(zmin) || double.IsNaN(zmax) || divisions < 1)
                return new LinearAxisScale(0, 0, 0, 0, 1);

            if (Math.Abs(zmin - zmax) < 1e-10)
            {
                zmin -= 1.0;
                zmax += 1.0;
            }

            double rint = (zmax - zmin) / (divisions + 0.1);
            if (rint <= 0.0)
                return new LinearAxisScale(0, 0, 0, 0, 1);

            // Nothing too crazy going on.  What can we make?
            double[] r = { 0.1, 0.15, 0.2, 0.25, 0.4, 0.5, 0.6, 0.75, 0.8 };
            double znmin, znmax, zstep;
            do
            {
                int mint = Convert.ToInt32(Math.Log10(rint) - 2.0);
                double tenn = Math.Pow(10.0, mint);
                bool jump = false;
                double ar = 0;
                for (int j = 1; j <= 11; j++)
                {
                    foreach (double candidate in r)
                    {
                        if (candidate * tenn >= rint)
                        {
                            ar = candidate;
                            jump = true;
                            break;
                        }
                    }
                    if (jump)
                        break;
                    tenn *= 10.0;
                }
                zstep = tenn * ar;

                ar = zstep * Math.Floor((1.0 + 2.0 * Constant.EPSNEG) * zmin / zstep);
                if (double.IsInfinity(ar))
                    return new LinearAxisScale(0, 0, 0, 0, 1);

                while (!(ar - zstep * 0.05 <= zmin))
                    ar -= zstep;
                znmin = ar;
                znmax = znmin + zstep * (divisions + 0.04);
                if (znmax >= zmax)
                    break;
                rint *= 1.05;
            }
            while (true);

            int maxA = Convert.ToInt32(Math.Log10(Math.Abs(znmax)) + 1.0);
            if (Math.Abs(znmin) > Math.Abs(znmax))
                maxA = Convert.ToInt32(Math.Log10(Math.Abs(znmin)) + 1.0);
            if (maxA < 0)
                maxA = 0;
            int maxB = Convert.ToInt32(Math.Log10(zstep) - 2.5);
            if (maxB > 0)
                maxB = 0;
            maxB = -maxB;
            if (maxA + maxB >= 10)
                return new LinearAxisScale(minimumDataValue, maximumDataValue, znmin, znmin + zstep * divisions, divisions);
            double znm = znmin;
            for (int i = 0; i <= 9; i++)
            {
                if (znm + zstep * (divisions + 0.04) < zmax)
                    break;
                znmin = znm;
                znm = znmin * Math.Pow(10.0, maxB - i);
                if (znm < 0.0)
                    znm -= 1.0;
                znm = Math.Floor(znm) / Math.Pow(10.0, maxB - i);
            }
            return new LinearAxisScale(minimumDataValue, maximumDataValue, znmin, znmin + zstep * divisions, divisions);
        }

        public static ILinearAxisScale v_axis(double qmin, double qmax, int divisions)
        {
            if (divisions > 0)
                return Axis(qmin, qmax, divisions);
            return new LinearAxisScale(qmin, qmax, qmin, qmax, 1);
        }
    }
}
