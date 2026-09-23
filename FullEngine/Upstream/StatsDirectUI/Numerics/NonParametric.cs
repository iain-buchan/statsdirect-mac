using System;

namespace StatsDirect.Numerics
{
    public static class NonParametric
    {
        ///  <summary>
        ///  
        ///  </summary>
        ///  <param name="x">1-based array of values</param>
        ///  <param name="nsum"></param>
        ///  <param name="n1"></param>
        ///  <param name="n2"></param>
        ///  <param name="ranks">Ranks corresponding to each element of x</param>
        ///  <param name="u"></param>
        ///  <param name="z">Standardised value</param>
        ///  <param name="xf"></param>
        ///  <param name="r1"></param>
        ///  <param name="fault"></param>
        ///  <remarks></remarks>
        public static void MannWhitneyUTest(double[] x, int nsum, int n1, int n2, out double[] ranks, out double u, out double z, out double xf, out double r1, out bool fault)
        {
            fault = false;
            if (nsum < 2 || n1 >= nsum || n1 < 1)
            {
                u = z = xf = r1 = Constant.MISSING;
                ranks = null;
                fault = true;
            }
            else
            {
                ranks = new double[x.Length];
                ExFortran.Rank(x, ranks, 1, nsum, 1, out xf);
                r1 = 0.0;
                for (int j = 1; j <= n1; j++)
                    r1 += ranks[j];
                double r2 = 0.0;
                for (int i = n1 + 1; i <= nsum; i++)
                    r2 += ranks[i];
                double fts = nsum;
                double f2 = n2;
                double fx = n1 * f2;
                u = fx + f2 * (f2 + 1) * 0.5 - r2;
                double se;
                if (xf != 0)
                {
                    se = fx / (12 * fts * (fts - 1.0));
                    se = Math.Sqrt(se * (Math.Pow(fts, 3.0) - fts - xf * 12.0));
                }
                else
                {
                    se = Math.Sqrt(fx * (fts + 1.0) / 12.0);
                }
                z = (u - 0.5 * fx) / se;
            }
        }

        ///  <summary>
        ///  Returns the lower tail probability p for the Wilcoxon-Mann-Whitney statistic U for sample sizes n1 and n2 for the case of ties in the pooled sample, or Constant.MISSING if there is a fault.
        ///  </summary>
        ///  <param name="n1">Sample size of group 1</param>
        ///  <param name="n2">Sample size of group 2</param>
        ///  <param name="ranks">A 1-based array of integer ranks; beware, this is destroyed during processing</param>
        ///  <param name="iv"></param>
        ///  <param name="fault">true if there was an error</param>
        ///  <remarks>
        ///  see procedure wmw_dist in
        ///  neumann, n. - some procedures for calculating the distributions of elementary nonparametric statistics. stat. software newsletter, vol. 14, no 3., 1988
        ///  </remarks>
        public static double WilcoxonMannWhitneyLowerTailProbability(int n1, int n2, int[] ranks, int iv)
        {
            bool change;
            int m1, m2;
            if (n1 < n2)
            {
                m1 = n1;
                m2 = n2;
                change = false;
            }
            else
            {
                m1 = n2;
                m2 = n1;
                change = true;
            }

            int nsum = n1 + n2;
            int l1 = nsum;
            int l2 = nsum + m1 + 1;
            int low = 0;
            int high = 0;
            int space = 0;
            ranks[l1 + 1] = 0;
            ranks[l2 + 1] = 0;
            for (int m = 1; m <= m1; m++)
            {
                ranks[l1 + m + 1] = 0;
                ranks[l2 + m + 1] = space + 1;
                low += ranks[m];
                high += ranks[nsum + 1 - m];
                int dummy = high - low + 1;
                space += dummy;
            }
            int mwmax;
            if (change)
                mwmax = nsum * (nsum + 1) - low;
            else
                mwmax = high;
            if (iv == mwmax - n1 * (n1 + 1))
                return 1.0;

            int nn = Math.Min(n1, n2);
            int nwrk = nn + nn * (nn + 1) * nsum - (int)Math.Floor(nn * (nn + 1) * (2 * nn + 1) / 3.0) + 1;
            double[] wrk = new double[nwrk + 1];
            for (int i = 0; i <= space; i++)
                wrk[i + 1] = 1.0;

            for (int n = 1; n <= nsum; n++)
            {
                int dummy = Math.Min(n, m1);
                for (int m = dummy; m >= 1; m--)
                {
                    int shift = ranks[n] - ranks[m];
                    ranks[l1 + m + 1] = ranks[l1 + m] + shift;
                    double lambda = Convert.ToDouble(m) / Convert.ToDouble(n);
                    int j;
                    for (j = 0; j <= ranks[l1 + m + 1]; j++)
                    {
                        int k = ranks[l2 + m + 1] + j;
                        wrk[k + 1] = (1.0 - lambda) * wrk[k + 1];
                        if (shift <= j)
                        {
                            wrk[k + 1] = wrk[k + 1] + lambda * wrk[ranks[l2 + m] + j - shift + 1];
                        }
                    }
                }
            }
            if (!change)
            {
                int ir1 = low - m1 * (m1 + 1);
                // below the smallest value U can take with these ties the lower tail is empty; without this the index falls
                // on the last cell of the previous block of wrk, which holds 1
                if (iv < ir1)
                    return 0.0;
                return wrk[ranks[l2 + m1 + 1] + iv - ir1 + 1];
            }
            else
            {
                int ir1 = nsum * (nsum + 1) - high - m2 * (m2 + 1);
                if (iv < ir1)
                    return 0.0;
                return 1.0 - wrk[ranks[l2 + m1 + 1] + ranks[l1 + m1 + 1] - iv + ir1];
            }
        }

    }
}
