using System;

namespace StatsDirect.Numerics
{
    /// <summary>
    /// Exact two-sample Smirnov (Kolmogorov-Smirnov) P values conditional on the observed ties.
    ///
    /// The null distribution is the permutation distribution of the statistic over all
    /// C(n1+n2, n1) relabellings of the pooled sample. Each relabelling is a lattice path from
    /// (0,0) to (n1,n2); the statistic is the largest |F1 - F2| (or F1 - F2) evaluated at the
    /// points where the pooled sorted sample changes value. Ties are handled as Schroer and
    /// Trenkler (1995, Computational Statistics and Data Analysis 20:185-202) describe: the
    /// boundary test at lattice position (i, j) is applied only when the (i+j)-th pooled
    /// order statistic differs from the (i+j+1)-th, so that steps taken inside a block of tied
    /// values cannot contribute to the statistic. With no ties every position is tested and
    /// the result is identical to the classical untied exact distribution (ExFortran.ksp2).
    ///
    /// Numerics: the recursion is the "upper" form of Viehmann (2021, arXiv:2102.08037):
    ///   u(i,j) = 1 if the boundary is hit at (i,j), else i/(i+j) u(i-1,j) + j/(i+j) u(i,j-1),
    /// i.e. u(i,j) is the probability that a uniformly random path to (i,j) has already hit the
    /// boundary. Every value is a convex combination of values in [0,1], so plain doubles cannot
    /// overflow or underflow for any sample sizes, and P is obtained directly rather than as
    /// 1 - P (no cancellation for small P). Cost is O(n1 * n2) time and O(n2) memory.
    /// </summary>
    public static class KsTies
    {
        /// <summary>Exact P(D &gt;= d) for the two-sided statistic D = max |F1 - F2|, conditional on ties.</summary>
        public static double TwoSided(double[] x, double[] y, double d)
        {
            return Exact(x, y, d, true);
        }

        /// <summary>Exact P(D+ &gt;= dplus) for the one-sided statistic D+ = max (F1 - F2), conditional on ties.
        /// For D- = max (F2 - F1) call OneSided(y, x, dminus).</summary>
        public static double OneSided(double[] x, double[] y, double dplus)
        {
            return Exact(x, y, dplus, false);
        }

        /// <summary>Computes D, D+ and D- from the two samples, evaluating the ECDF difference only at
        /// distinct pooled values (the same definition as StatsDirect's XKstwo).</summary>
        public static void Statistics(double[] x, double[] y, out double d, out double dplus, out double dminus)
        {
            int m = x.Length, n = y.Length;
            double[] pooled = new double[m + n];
            bool[] isX = new bool[m + n];
            for (int i = 0; i < m; i++) { pooled[i] = x[i]; isX[i] = true; }
            for (int j = 0; j < n; j++) { pooled[m + j] = y[j]; isX[m + j] = false; }
            Array.Sort(pooled, isX);
            int cx = 0, cy = 0;
            dplus = 0.0; dminus = 0.0;
            for (int k = 0; k < m + n; k++)
            {
                if (isX[k]) cx++; else cy++;
                if (k == m + n - 1 || pooled[k] != pooled[k + 1])
                {
                    double diff = (double)cx / m - (double)cy / n;
                    if (diff > dplus) dplus = diff;
                    if (-diff > dminus) dminus = -diff;
                }
            }
            d = Math.Max(dplus, dminus);
        }

        /// <summary>
        /// Builds the change mask from the pooled sample: change[k] (k = 1..N-1) is true when the
        /// k-th and (k+1)-th pooled order statistics differ; change[0] = false, change[N] = true.
        /// </summary>
        public static bool[] ChangeMask(double[] x, double[] y)
        {
            int m = x.Length, n = y.Length, N = m + n;
            double[] pooled = new double[N];
            Array.Copy(x, 0, pooled, 0, m);
            Array.Copy(y, 0, pooled, m, n);
            Array.Sort(pooled);
            bool[] change = new bool[N + 1];
            change[0] = false;
            for (int k = 1; k < N; k++) change[k] = pooled[k] != pooled[k - 1];
            change[N] = true;
            return change;
        }

        private static double Exact(double[] x, double[] y, double q, bool twoSided)
        {
            if (x == null || y == null || x.Length < 1 || y.Length < 1)
                throw new ArgumentException("both samples must be non-empty");
            if (double.IsNaN(q)) return double.NaN;
            if (q <= 0.0) return 1.0;
            if (q > 1.0) return 0.0;
            return UpperTail(x.Length, y.Length, q, ChangeMask(x, y), twoSided);
        }

        /// <summary>
        /// P(statistic &gt;= q) by lattice-path counting. m = n1 (sample whose ECDF is F1), n = n2.
        /// change may be null (no ties: every lattice position is tested).
        /// </summary>
        public static double UpperTail(int m, int n, double q, bool[] change, bool twoSided)
        {
            double md = m, nd = n;
            // Shift q to the midpoint below the nearest attainable value k/(mn) so that
            // floating-point rounding cannot turn "equal to q" into "less than q". For an attained
            // statistic k/(mn) this tests >= (k - 0.5)/(mn); for an unattainable q strictly between
            // k/(mn) and (k+1)/(mn) it tests >= (k + 0.5)/(mn), i.e. P(stat >= q) exactly.
            q = (0.5 + Math.Floor(q * md * nd - 1e-7)) / (md * nd);

            double[] u = new double[n + 1];
            u[0] = 0.0;
            for (int j = 1; j <= n; j++)
            {
                if (Hit(twoSided, q, 0.0, j / nd) && Changes(change, j))
                    u[j] = 1.0;
                else
                    u[j] = u[j - 1];
            }
            for (int i = 1; i <= m; i++)
            {
                if (Hit(twoSided, q, i / md, 0.0) && Changes(change, i))
                    u[0] = 1.0;
                for (int j = 1; j <= n; j++)
                {
                    if (Hit(twoSided, q, i / md, j / nd) && Changes(change, i + j))
                        u[j] = 1.0;
                    else
                    {
                        double v = (double)i / (i + j);
                        double w = (double)j / (i + j);
                        u[j] = v * u[j] + w * u[j - 1];
                    }
                }
            }
            double p = u[n];
            if (p < 0.0) p = 0.0;
            if (p > 1.0) p = 1.0;
            return p;
        }

        private static bool Changes(bool[] change, int k) => change == null || change[k];

        private static bool Hit(bool twoSided, double q, double r, double s)
        {
            return twoSided ? Math.Abs(r - s) >= q : (r - s) >= q;
        }

    }
}
