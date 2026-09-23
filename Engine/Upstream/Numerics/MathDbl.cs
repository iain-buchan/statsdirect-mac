using System;

namespace StatsDirect.Numerics
{
    public class MathDbl
    {
        //     Public Function ExpMinus1(ByVal x As Double) As Double
        //         ' Exp x - 1
        //         Dim y As Double, a As Double
        //         
        //         a = Abs(x)
        //         If a < EPSILON Then
        //             ExpMinus1 = x
        //             Exit Function
        //         End If
        //         If a > 0.697 Then
        //             ExpMinus1 = Exp(x) - 1.0
        //             Exit Function
        //         End If
        //         If a > 0.00000001 Then
        //             y = Exp(x) - 1.0
        //         Else
        //             y = (x / 2.0 + 1.0) * x
        //         End If
        //         y = y - (1.0 + y) * (DLNREL(y) - x)
        //         ExpMinus1 = y
        //     End Function

        //     Public Function ceil(ByVal Value As Double) As Double
        //         
        //         ceil = CDbl(CLng(Value + 0.5))
        //     End Function

        ///  <summary>
        ///  Returns Pearson's product moment correlation coefficient r or rho from a matching pair of vectors.
        ///  </summary>
        ///  <param name="x">Vector of independent observations</param>
        ///  <param name="y">Matching vector of dependent observations</param>
        ///  <param name="lowerBound">LowerBound-based input vector of n values</param>
        ///  <param name="n">Number of observations</param>
        /// <param name="noMissing"></param>
        /// <remarks></remarks>
        public static double corr(double[] x, double[] y, int lowerBound, int n, bool noMissing)
        {
            // Return a Pearson correlation coefficient. The sums of squares and products are taken about the means, in a
            // second pass: formed from the raw sums they lost digits when a mean was large compared with the spread, which
            // moved the Shapiro-Wilk and Shapiro-Francia statistics for values of about 1e6 or more.
            double sumx = 0.0;
            double sumy = 0.0;
            double nx = 0.0;
            for (int i = lowerBound; i < n + lowerBound; i++)
            {
                if (noMissing || (x[i] != Constant.MISSING & y[i] != Constant.MISSING))
                {
                    nx += 1.0;
                    sumx += x[i];
                    sumy += y[i];
                }
            }
            if (nx < 2.0)
            {
                return Constant.MISSING;
            }
            double meanx = sumx / nx;
            double meany = sumy / nx;
            double ssx = 0.0;
            double ssy = 0.0;
            double xy = 0.0;
            for (int i = lowerBound; i < n + lowerBound; i++)
            {
                if (noMissing || (x[i] != Constant.MISSING & y[i] != Constant.MISSING))
                {
                    double dx = x[i] - meanx;
                    double dy = y[i] - meany;
                    ssx += dx * dx;
                    ssy += dy * dy;
                    xy += dx * dy;
                }
            }
            double r = xy / Math.Sqrt(ssx * ssy);
            // rounding can take r just beyond 1 in size; it was set to +1 whichever the sign
            if (r > 1.0)
            {
                r = 1.0;
            }
            else if (r < -1.0)
            {
                r = -1.0;
            }
            return r;
        }


        //     Public Function pow10(ByVal x As Double) As Double
        //         If x > 307.0 Then
        //             pow10 = LMREAL
        //         ElseIf x < -307.0 Then
        //             pow10 = SPREAL
        //         Else
        //             pow10 = 10.0 ^ x
        //         End If
        //     End Function

        ///  <summary>
        ///  get 100*qc'th quantile from sorted 1-based vector r
        ///  </summary>
        ///  <param name="r"></param>
        ///  <param name="rx"></param>
        ///  <param name="qc"></param>
        ///  <returns></returns>
        ///  <remarks></remarks>
        public static double QuantileFromSorted(double[] r, int rx, double qc)
        {
            double iq = qc * (rx + 1);
            if (iq > rx)
            {
                iq = rx;
            }
            // below the first order statistic the quantile is the minimum; "iq < 0" could never be true, and r[0] is not an observation
            if (iq < 1)
            {
                iq = 1;
            }
            if (iq - Math.Floor(iq) == 0)
            {
                return r[Convert.ToInt32(iq)];
            }
            if (iq - Math.Floor(iq) != 0)
            {
                return r[(int)Math.Floor(iq)] + (r[(int)Math.Floor(iq) + 1] - r[(int)Math.Floor(iq)]) * (iq - Math.Floor(iq));
            }
            return 0;
        }

        public static double trapezoid_xy_roc(double[] rx, double[] ry, int lowerBound, int N)
        {
            if (N < 2)
                return Constant.MISSING;
            double s = 0.0;
            double[] xx = new double[N + 2];
            double[] yy = new double[N + 2];
            for (int i = 0; i < N; i++)
            {
                xx[1 + i] = rx[i + lowerBound];
                yy[1 + i] = ry[i + lowerBound];
            }
            xx[0] = 1.0;
            yy[0] = 1.0;
            xx[N + 1] = 0.0;
            yy[N + 1] = 0.0;
            for (int i = N + 1; i >= 1; i--)
            {
                double x = Math.Abs(xx[i] - xx[i - 1]);
                double y1 = yy[i];
                double y2 = yy[i - 1];
                s += x * y1 + x * Math.Abs(y2 - y1) / 2.0;
            }
            return s;
        }

        public static void Wilson(int ia, int ib, int ic, int id, out double cl, out double cu, double z, out bool fault)
        {
            fault = false;
            double zsq = z * z;
            int inl = ia + ib + ic + id;
            if (ia >= 0 && ib >= 0 && ic >= 0 && id >= 0 && inl > 0)
            {
                double a = Convert.ToDouble(ia);
                double b = Convert.ToDouble(ib);
                double c = Convert.ToDouble(ic);
                double d = Convert.ToDouble(id);
                double N = Convert.ToDouble(inl);
                double th = (b - c) / N;
                double temp;
                double ph;
                if (b + c + a * d == 0.0)
                {
                    // icase = 3; 
                    ph = 0.0;
                }
                else if (a + d + b * c == 0.0)
                {
                    // icase = 4; 
                    ph = 0.0;
                }
                else if ((a + b) * (c + d) * (a + c) * (b + d) == 0.0)
                {
                    // icase = 2; 
                    ph = 0.0;
                }
                else
                {
                    // icase = 1; 
                    ph = a * d - b * c;
                    if (ph > 0)
                    {
                        if (ph - N / 2 > 0.0)
                        {
                            temp = ph - N / 2.0;
                        }
                        else { temp = 0.0; }
                        ph = temp / Math.Sqrt((a + b) * (c + d) * (a + c) * (b + d));
                    }
                    else
                    {
                        ph /= Math.Sqrt((a + b) * (c + d) * (a + c) * (b + d));
                    }
                }
                double den = N + zsq;
                double u2 = (a + b + 0.5 * (zsq + z * Math.Sqrt(zsq + 4.0 * (a + b) * (c + d) / N))) / den;
                double l2 = (a + b + 0.5 * (zsq - z * Math.Sqrt(zsq + 4.0 * (a + b) * (c + d) / N))) / den;
                double u3 = (a + c + 0.5 * (zsq + z * Math.Sqrt(zsq + 4.0 * (a + c) * (b + d) / N))) / den;
                double l3 = (a + c + 0.5 * (zsq - z * Math.Sqrt(zsq + 4.0 * (a + c) * (b + d) / N))) / den;
                double dl2 = (a + b) / N - l2;
                double du2 = u2 - (a + b) / N;
                double dl3 = (a + c) / N - l3;
                double du3 = u3 - (a + c) / N;
                if (Math.Pow(dl2, 2.0) - 2.0 * ph * dl2 * du3 + Math.Pow(du3, 2.0) > 0.0)
                {
                    temp = Math.Pow(dl2, 2.0) - 2.0 * ph * dl2 * du3 + Math.Pow(du3, 2.0);
                }
                else { temp = 0.0; }
                cl = th - Math.Sqrt(temp);
                if (Math.Pow(du2, 2.0) - 2.0 * ph * du2 * dl3 + Math.Pow(dl3, 2.0) > 0.0)
                {
                    temp = Math.Pow(du2, 2.0) - 2.0 * ph * du2 * dl3 + Math.Pow(dl3, 2.0);
                }
                else { temp = 0.0; }
                cu = th + Math.Sqrt(temp);
            }
            else
            {
                cl = Constant.MISSING;
                cu = Constant.MISSING;
                fault = true;
            }
        }

        ///  <summary>
        ///  Large sample approximation for Spearman Rho P
        ///  </summary>
        ///  <param name="N"></param>
        ///  <param name="dix"></param>
        ///  <param name="ifault"></param>
        ///  <returns></returns>
        public static double bigprho(long N, double dix, out int ifault)
        {
            ifault = 1;
            if (N <= 1)
                return 1.0;

            ifault = 0;
            if (dix <= 0.0)
                return 1.0;

            if (dix > Convert.ToDouble(N) * (Convert.ToDouble(N) * Convert.ToDouble(N) - 1.0) / 3.0)
                return 0.0;

            double djs = Math.Floor(dix);
            if (djs != 2.0 * (djs / 2.0))
                djs += 1.0;
            double b = 1.0 / Convert.ToDouble(N);
            double x = (6.0 * (djs - 1.0) * b / (1.0 / (b * b) - 1.0) - 1.0) * Math.Sqrt(1.0 / b - 1.0);
            double y = x * x;
            double z = y * b * (0.0879 + 0.0151 * b - y * (0.0072 - 0.0831 * b + y * b * (0.0131 - 0.00046 * y)));
            double u = x * b * (0.2274 + b * (0.2531 + 0.1745 * b) + y * (-0.0758 + b * (0.1033 + 0.3932 * b) - z));
            double bigprhoReturn = u / Math.Exp(y / 2.0) + 1.0 - PDF.alnorm(x);
            if (bigprhoReturn < 0.0)
                return 0.0;
            if (bigprhoReturn > 1.0)
                return 1.0;
            return bigprhoReturn;
        }


        ///  <summary>
        ///  
        ///  </summary>
        ///  <param name="a">Array, used dimensions (LowerBound..LowerBound+N-1, LowerBound..LowerBound+N-1?)</param>
        /// <param name="lowerBound"></param>
        /// <param name="N"></param>
        ///  <param name="b">0-based array, dimensions (LowerBound..LowerBound+M-1, LowerBound+..LowerBound+M-1)</param>
        ///  <param name="M"></param>
        ///  <param name="ifault"></param>
        ///  <remarks></remarks>
        public static void gaussj(double[,] a, int lowerBound, int N, double[,] b, int M, ref int ifault)
        {
            int icol = 0; int irow = 0;

            int[] indxc = new int[lowerBound + N];
            int[] indxr = new int[lowerBound + N];
            long[] ipiv = new long[lowerBound + N];
            if (N > a.GetUpperBound(0) + 1 || N > a.GetUpperBound(1) + 1 || M > b.GetUpperBound(1) + 1 || N > b.GetUpperBound(0) + 1)
            {
                ifault = 1;
                return;
            }
            for (int j = lowerBound; j < lowerBound + N; j++)
            {
                ipiv[j] = 0;
            }
            for (int i = lowerBound; i < lowerBound + N; i++)
            {
                double BIG = 0.0;
                for (int j = lowerBound; j < lowerBound + N; j++)
                {
                    if (ipiv[j] != 1)
                    {
                        for (int k = lowerBound; k < lowerBound + N; k++)
                        {
                            if (ipiv[k] == 0)
                            {
                                if (Math.Abs(a[j, k]) >= BIG)
                                {
                                    BIG = Math.Abs(a[j, k]);
                                    irow = j;
                                    icol = k;
                                }
                            }
                            else if (ipiv[k] > 1)
                            {
                                //  singularity
                                ifault = 2;
                                return;
                            }
                        }
                    }
                }
                ipiv[icol] = ipiv[icol] + 1;
                if (irow != icol)
                {
                    for (int L = lowerBound; L < lowerBound + N; L++)
                    {
                        double dum = a[irow, L];
                        a[irow, L] = a[icol, L];
                        a[icol, L] = dum;
                    }
                    for (int L = lowerBound; L < lowerBound + M; L++)
                    {
                        double dum = b[irow, L];
                        b[irow, L] = b[icol, L];
                        b[icol, L] = dum;
                    }
                }
                indxr[i] = irow;
                indxc[i] = icol;
                if (a[icol, icol] == 0)
                {
                    // singularity
                    ifault = 3;
                    return;
                }
                double pivinv = 1.0 / a[icol, icol];
                a[icol, icol] = 1.0;
                for (int L = lowerBound; L < lowerBound + N; L++)
                {
                    a[icol, L] = a[icol, L] * pivinv;
                }
                for (int L = lowerBound; L < lowerBound + M; L++)
                {
                    b[icol, L] = b[icol, L] * pivinv;
                }
                for (int ll = lowerBound; ll < lowerBound + N; ll++)
                {
                    if (ll != icol)
                    {
                        double dum = a[ll, icol];
                        a[ll, icol] = 0.0;
                        for (int L = lowerBound; L < lowerBound + N; L++)
                        {
                            a[ll, L] = a[ll, L] - a[icol, L] * dum;
                        }
                        for (int L = lowerBound; L < lowerBound + M; L++)
                        {
                            b[ll, L] = b[ll, L] - b[icol, L] * dum;
                        }
                    }
                }
            }
            for (int L = lowerBound + N - 1; L >= lowerBound; L--)
            {
                if (indxr[L] != indxc[L])
                {
                    for (int k = lowerBound; k < lowerBound + N; k++)
                    {
                        double dum = a[k, indxr[L]];
                        a[k, indxr[L]] = a[k, indxc[L]];
                        a[k, indxc[L]] = dum;
                    }
                }
            }
        }


        ///  <summary>
        ///  Calculate and return the mean and standard deviation of the doubles in x[0] to x[k - 1] inclusive.
        ///  </summary>
        ///  <param name="x">The array of values</param>
        ///  <param name="k">The number of values.  Set to the number of non-MISSING values.</param>
        ///  <param name="xmean">The output mean, or Constant.MISSING</param>
        ///  <param name="xsd">The output standard deviation, or Constant.MISSING</param>
        ///  <remarks></remarks>
        public static void MeanSD(double[] x, ref int k, out double xmean, out double xsd)
        {

            double xsum = 0.0;
            int ctr = 0;
            for (int i = 0; i < k; i++)
            {
                if (x[i] != Constant.MISSING)
                {
                    ctr++;
                    xsum += x[i];
                }
            }
            if (ctr < 2)
            {
                xmean = Constant.MISSING;
                xsd = Constant.MISSING;
                return;
            }
            xmean = xsum / ctr;
            double xss = 0.0;
            for (int i = 0; i < k; i++)
                if (x[i] != Constant.MISSING)
                    xss += (x[i] - xmean) * (x[i] - xmean);
            double xvar = xss / (ctr - 1);
            xsd = xvar >= 0 ? Math.Sqrt(xvar) : Constant.MISSING;
            k = ctr;
        }

        //     Function chivalp(ByVal x As Double, ByVal df As Double) As Double
        //         Dim fault As Long
        //         
        //         If x = MISSING Then
        //             chivalp = MISSING
        //         Else
        //             fault = 0
        //             chivalp = 1.0 - GAMMAD(x / 2.0, df / 2.0, fault)
        //             If fault <> 0 Then chivalp = MISSING
        //         End If
        //     End Function

        //     Function fvalp(ByVal f As Double, ByVal dfn As Double, ByVal dfd As Double) As Double
        //         Dim fault As Long
        //         
        //         fault = 0
        //         fvalp = BETAIN(dfd / (dfd + dfn * f), dfd / 2.0, dfn / 2.0, fault)
        //         If fault <> 0 Then fvalp = MISSING
        //     End Function

        public static double taufromp(double P, out double pu, out int ix, ref int nx, out int ifault)
        {
            double taufrompReturn = 0;
            ix = -5;
            do
            {
                ix += 10;
                ifault = 0;
                pu = kendp(ix, nx, ref ifault);
                if (pu < P)
                    break;
                // The search used to stop at a score of 1000, so the quantile could never be larger than about 1000. The
                // quantile grows as n to the power 1.5 and passes 1000 at about 133 pairs for a two sided 95% interval,
                // after which intervals built on it (the slope in nonparametric regression) became far too narrow.
                // The largest possible score is n(n - 1)/2.
                if (ix > Convert.ToDouble(nx) * Convert.ToDouble(nx - 1) / 2.0)
                    break;
            }
            while (true);
            do
            {
                ix -= 1;
                ifault = 0;
                pu = kendp(ix, nx, ref ifault);
                if (ifault == 0 & (pu > P || Math.Abs(pu - P) < 0.00000000000001))
                {
                    taufrompReturn = Convert.ToDouble(ix) / (Convert.ToDouble(nx) * Convert.ToDouble(nx - 1) / 2.0);
                    break;
                }
                if (ix < 3)
                {
                    ifault = 1;
                    break;
                }
            }
            while (true);
            return taufrompReturn;
        }

        public static T[,] Transpose<T>(T[,] x)
        {
            int cols = x.GetUpperBound(0);
            int rows = x.GetUpperBound(1);
            T[,] z = new T[rows + 1, cols + 1];
            for (int c = 1; c <= cols; c++)
                for (int r = 1; r <= rows; r++)
                    z[r, c] = x[c, r];
            return z;
        }

        ///  <summary>
        ///  A version of kendp that gives a boolean error value rather than an integer error value.
        ///  </summary>
        ///  <param name="k"></param>
        ///  <param name="N"></param>
        ///  <param name="ifault"></param>
        ///  <returns></returns>
        ///  <remarks></remarks>
        public static double kendp(int k, int N, out bool ifault)
        {
            int my_ifault = 0;
            double result = kendp(k, N, ref my_ifault);
            ifault = my_ifault != 0;
            return result;
        }

        public static double kendp(int k, int N, ref int ifault)
        {
            double kendpReturn = 0;
            int i;
            double y = 0;
            double x = 0;
            double[] wksp; double[] freq;
            try
            {
                if (N > 50)
                {
                    //  Edgeworth series for n>50
                    double[] h = new double[16];
                    double dn = Convert.ToDouble(N);
                    x = Convert.ToDouble(k - 1) / Math.Sqrt((6.0 + dn * (5.0 - dn * (3.0 + 2.0 * dn))) / -18.0);
                    h[1] = x;
                    h[2] = x * x - 1.0;
                    for (i = 3; i <= 15; i++)
                    {
                        h[i] = x * h[i - 1] - Convert.ToDouble(i - 1) * h[i - 2];
                    }
                    double r = 1.0 / dn;
                    double sc1 = h[3] * (-0.09 + r * (0.045 + r * (-0.5325 + r * 0.506)));
                    double sc2 = h[5] * (0.036735 + r * (-0.036735 + r * 0.3214)) + h[7] * (0.00405 + r * (-0.023336 + r * 0.07787));
                    double sc3 = h[9] * (-0.0033061 - r * 0.0065166) + h[11] * (-0.0001215 + r * 0.0025927) + r * (h[13] * 0.00014878 + h[15] * 0.0000027338);
                    double sc = r * (sc1 + r * (sc2 + r * sc3));
                    kendpReturn = 1.0 - PDF.alnorm(x) + sc * 0.398942 * Math.Exp(-0.5 * x * x);
                    if (kendpReturn < 0.0)
                    {
                        kendpReturn = 0.0;
                    }
                    if (kendpReturn > 1.0)
                    {
                        kendpReturn = 1.0;
                    }
                    return kendpReturn;
                }

                //  If we get here, use exact permutation by summation and division
                const int nmax = 55;
                if (N <= 1 | N > nmax)
                {
                    ifault = 1;
                    return kendpReturn;
                }
                //  In the following lines, CInt always works because one of N, N-1 or N-2 is always even, so the result is always integer.  PJC 21/11/2007
                int nwk = Convert.ToInt32((N - 1) * (N - 2) / 2 + 1);
                wksp = new double[2 * nwk]; //  Originally (2 ^ ((4 / 2) -1 )) * nwk
                freq = new double[Convert.ToInt32(N * (N - 1) / 2 + 1) + 1];
            }
            catch (Exception)
            {
                ifault = 2;
                return kendpReturn;
            }
            int kmax = Math.Abs(Convert.ToInt32(N * (N - 1) / 2));
            if (Math.Abs(k) > kmax)
            {
                ifault = 3;
                return kendpReturn;
            }
            int ic = 2;
            int kc = 1;
            freq[1] = 1;
            freq[2] = 1;
            while (ic != N)
            {
                ic += 1;
                kc += ic;
                int jc = (int)Math.Floor((double)(kc + 1) / 2);
                int I1;
                for (i = 1; i <= jc; i++)
                {
                    double sum = 0.0;
                    wksp[i] = freq[i];
                    int jst = i - ic + 1;
                    if (jst < 1)
                    {
                        jst = 1;
                    }
                    for (I1 = jst; I1 <= i; I1++)
                    {
                        sum += wksp[I1];
                    }
                    freq[i] = sum;
                }
                if (ic > 3)
                {
                    kc -= 1;
                }
                int i2 = kc;
                I1 = kc - jc;
                for (i = 1; i <= I1; i++)
                {
                    freq[i2] = freq[i];
                    i2 -= 1;
                }
            }
            ic = 1;
            //  In the following line, CInt always works because one of N or N-1 is always even, so the result is always integer.  PJC 21/11/2007
            int M = Convert.ToInt32(-N * (N - 1) * 0.5);
            int L = -M + 1;
            while (k > M)
            {
                M += 2;
                ic += 1;
            }
            for (i = 1; i <= L; i++)
            {
                y += freq[i];
            }
            for (i = ic; i <= L; i++)
            {
                x += freq[i];
            }
            kendpReturn = x / y;
            return kendpReturn;
        }

        /// <summary>
        /// Upper-side P for Spearman's rho: P(S &lt;= ix), including ix, where S is the sum of squared rank differences.
        /// </summary>
        /// <remarks>
        /// ExFortran.prho gives P(S &gt;= ix), including ix, and treats an odd ix as the next even number because S is always even.
        /// The complement of P(S &lt;= ix) is therefore P(S &gt;= the next attainable score above that), as in RptSpearman.
        /// </remarks>
        public static double prhoUpper(int nx, int ix, out int ifault)
        {
            //  Below the smallest score, or so far above the largest that the next score does not fit an int: prho is called only to validate nx
            long next = (long)ix + (ix & 1) + 2;
            if (ix < 0 || next > int.MaxValue)
            {
                ExFortran.prho(nx, -1, out ifault);
                return ix < 0 ? 0.0 : 1.0;
            }
            return 1.0 - ExFortran.prho(nx, (int)next, out ifault);
        }

        /// <summary>
        /// Critical value of Spearman's rho: the rho of the largest score ix whose upper-side P, P(S &lt;= ix), does not exceed P.
        /// </summary>
        /// <param name="P">Upper-side probability</param>
        /// <param name="pu">The upper-side P attained at ix, which is at most P</param>
        /// <param name="ix">The critical score, the sum of squared rank differences</param>
        /// <param name="nx">Number of pairs of observations</param>
        /// <param name="ifault">Non-zero if there is no such score (even rho = 1 has an upper-side P above P) or nx is out of range</param>
        public static double rhofromp(double P, out double pu, out int ix, int nx, out int ifault)
        {
            const double tolerance = 0.00000000000001;
            ix = 0;
            //  S is always even and runs from 0 (rho = 1) to n(n^2 - 1)/3 (rho = -1)
            double maxScore = Convert.ToDouble(nx) * (Convert.ToDouble(nx) * Convert.ToDouble(nx) - 1.0) / 3.0;
            pu = prhoUpper(nx, 0, out ifault);
            if (ifault != 0)
                return 0;
            if (maxScore > int.MaxValue - 4 || pu > P + tolerance)
            {
                ifault = 1;
                return 0;
            }

            //  P(S <= ix) does not decrease with ix, so bisect on the half scores: low always satisfies the condition, high never does
            int low = 0;
            int high = Convert.ToInt32(maxScore / 2.0);
            if (prhoUpper(nx, 2 * high, out ifault) <= P + tolerance)
                low = high;
            while (high - low > 1)
            {
                int mid = low + (high - low) / 2;
                if (prhoUpper(nx, 2 * mid, out ifault) <= P + tolerance)
                    low = mid;
                else
                    high = mid;
            }
            ix = 2 * low;
            pu = prhoUpper(nx, ix, out ifault);
            return 1.0 - Convert.ToDouble(ix) / (maxScore / 2.0);
        }


        //     Function tvalp(ByVal t As Double, ByVal df As Double) As Double
        //         
        //         If t = MISSING Then
        //             tvalp = MISSING
        //             Exit Function
        //         End If
        //         tvalp = fvalp(t * t, 1.0, df)
        //         If tvalp = MISSING Then
        //             Exit Function
        //         Else
        //             tvalp = tvalp * 0.5
        //             If t < 0.0 Then tvalp = 1.0 - tvalp
        //         End If
        //     End Function

        public static void z_profile(int ia, int im, int ib, int z_in, int ic, int id, double M, double N, double u, double v, double a, double b, double C, double D, double thhat, double psihat, double th, out double ps, double th1, double th2, int k, double f, out double hth, double z, ref bool ifault)
        {
            const double tol10 = 0.0000000001;
            const double tol12 = 0.000000000001;
            ps = 0.5;
            hth = 0.5 * th;
            if (Math.Abs(th) > 1.0 + tol12)
            {
                ifault = true;
                return;
            }
            if (Math.Abs(th) > 1.0 - tol12)
            {
                return;
            }
            if (ia == 0 || ib == 0 || ic == 0 || id == 0)
            {
                double aa = M + N;
                double cc;
                double bb;
                double ths;
                if (ib == 0)
                {
                    ths = (aa - Math.Sqrt(Math.Pow(aa, 2.0) - 4.0 * a * D)) * 0.5 / D;
                    ps = hth;
                    if (th >= ths)
                    {
                        return;
                    }
                    bb = D * (1.0 + th) + C;
                    cc = hth * ((D - C) * (1.0 + hth) - a * hth);
                }
                else if (ic == 0)
                {
                    ths = (aa - Math.Sqrt(Math.Pow(aa, 2.0) - 4.0 * a * D)) * 0.5 / a;
                    ps = 1.0 - hth;
                    if (th >= ths)
                    {
                        return;
                    }
                    bb = a * (1.0 + th) + b;
                    cc = hth * ((a - b) * (1.0 + hth) - D * hth);
                }
                else if (id == 0)
                {
                    ths = -(aa - Math.Sqrt(Math.Pow(aa, 2.0) - 4.0 * b * C)) * 0.5 / b;
                    ps = 1.0 + hth;
                    if (th < ths)
                    {
                        return;
                    }
                    bb = b * (1.0 - th) + a;
                    cc = -hth * ((b - a) * (1.0 - hth) + C * hth);
                }
                else
                {
                    ths = -(aa - Math.Sqrt(Math.Pow(aa, 2.0) - 4.0 * b * C)) * 0.5 / C;
                    ps = -hth;
                    if (th <= ths)
                    {
                        return;
                    }
                    bb = C * (1.0 - th) + D;
                    cc = -hth * ((C - D) * (1.0 - hth) + b * hth);
                }
                ps = (bb + Math.Sqrt(Math.Pow(bb, 2.0) - 4.0 * aa * cc)) * 0.5 / aa;
                if (ia == 0 | ib == 0)
                {
                    ps = 1.0 - ps;
                }
            }
            else if ((ia == 0 & ib == 0) | (ic == 0 & id == 0))
            {
                ps = Math.Abs(hth);
                if (ic == 0)
                {
                    ps = 1.0 - ps;
                }
            }
            else if ((ib == 0 & ic == 0) | (ia == 0 & id == 0))
            {
                if (im == z_in)
                {
                    return;
                }
                if (im < z_in)
                {
                    if (N * th < M)
                    {
                        ps = (M + (M - N) * hth) / (M + N);
                    }
                    else
                    {
                        ps = hth;
                    }
                }
                else if (M * th < N)
                {
                    ps = (M + (M - N) * hth) / (M + N);
                }
                else if (ia == 0)
                {
                    if (z_in < im)
                    {
                        if (M * -th < N)
                        {
                            ps = (N + (M - N) * hth) / (M + N);
                        }
                        else
                        {
                            ps = -hth;
                        }
                    }
                    else
                    {
                        if (N * -th < M)
                        {
                            ps = (N + (M - N) * hth) / (M + N);
                        }
                        else
                        {
                            ps = 1.0 + hth;
                        }
                    }
                }
                else
                {
                    ps = 1.0 - hth;
                }
            }
            else
            {
                double psimin = Math.Abs(hth);
                double psimax = 1.0 - psimin;
                do
                {
                    double P1 = ps + hth;
                    double P2 = ps - hth;
                    double Q1 = 1.0 - P1;
                    double Q2 = 1.0 - P2;
                    if (P1 < tol12 | P2 < tol12 | Q1 < tol12 | Q2 < tol12)
                    {
                        ifault = true;
                        return;
                    }
                    double deriv1 = a / P1 + b / P2 - C / Q1 - D / Q2;
                    double deriv2 = -a / Math.Pow(P1, 2.0) - b / Math.Pow(P2, 2.0) - C / Math.Pow(Q1, 2.0) - D / Math.Pow(Q2, 2.0);
                    double oldps = ps;
                    ps -= deriv1 / deriv2;
                    if (ps <= psimin + tol10)
                    {
                        ps = 0.5 * (psimin + oldps);
                    }
                    if (ps > psimax - tol10)
                    {
                        ps = 0.5 * (psimax + oldps);
                    }
                    if (Math.Abs(ps - oldps) <= tol12)
                    {
                        break;
                    }
                }
                while (true);
            }
        }

        public static void pone(double p0, double dpsi, double r, out double dp1, out bool imposs)
        {
            double Q0 = 1.0 - p0;
            double temp1 = 2 * Math.Pow(dpsi, 2.0) * Math.Pow(p0, 2.0) + 2.0 * dpsi * p0 * Q0 + Math.Pow(dpsi - 1.0, 2.0) * p0 * Q0 * Math.Pow(r, 2.0);
            double temp2 = (dpsi - 1.0) * p0 * Q0 * r * Math.Sqrt(Math.Pow(r, 2.0) * Math.Pow(dpsi - 1.0, 2.0) + 4.0 * dpsi);
            double temp3 = 2.0 * (Math.Pow(dpsi * p0 + Q0, 2.0) + Math.Pow(r, 2.0) * Math.Pow(dpsi - 1.0, 2.0) * p0 * Q0);
            dp1 = (temp1 - temp2) / temp3;
            double Q1 = 1.0 - dp1;
            Q0 = 1.0 - p0;
            double temp4 = r * Math.Sqrt(dp1 * p0 * Q0 * Q1);
            double p00 = Q1 * Q0 + temp4;
            double p11 = dp1 * p0 + temp4;
            double p10 = dp1 * Q0 - temp4;
            double p01 = p0 * Q1 - temp4;
            double min = p00;
            double max = p00;
            if (p11 > max)
                max = p11;
            if (p10 > max)
                max = p10;
            if (p01 > max)
                max = p01;
            if (p11 < min)
                min = p11;
            if (p10 < min)
                min = p10;
            if (p01 < min)
                min = p01;
            double pl = min;
            double pu = max;
            imposs = (pl < 0.0 || pu > 1.0);
        }

        public static void uppci(int ia, int im, int ib, int z_in, out double xl, out double xu, double z, double Conf)
        {
            int k;
            double f = 0;
            double ps = 0;
            bool fault = false;

            double[] thb = new double[2 + 1];
            double[] PP = new double[2 + 1];
            thb[1] = -1.0;
            thb[2] = 1.0;
            int ic = im - ia;
            int id = z_in - ib;
            if (ia < 0 | ib < 0 | ic < 0 | id < 0 | im <= 0 | z_in <= 0)
            {
                xu = Constant.MISSING;
                xl = Constant.MISSING;
                return;
            }
            double M = Convert.ToDouble(im);
            double N = Convert.ToDouble(z_in);
            double u = (1.0 / M + 1.0 / N) / 4.0;
            double v = (1.0 / M - 1.0 / N) / 4.0;
            double a = Convert.ToDouble(ia);
            double b = Convert.ToDouble(ib);
            double C = Convert.ToDouble(ic);
            double D = Convert.ToDouble(id);
            double thhat = a / M - b / N;
            double psihat = 0.5 * (a / M + b / N);
            double[] x = new double[2 + 1];
            double[] e = new double[2 + 1];
            for (k = 1; k <= 2; k++)
            {
                double th;
                if ((k == 1 & ia == 0 & id == 0) | (k == 2 & ib == 0 & ic == 0))
                {
                    th = thb[k];
                    ps = 0.5;
                }
                else
                {
                    double th1 = thhat;
                    double th2 = thb[k];
                    th = (th1 + th2) * 0.5;
                    int iter;
                    for (iter = 1; iter <= 40; iter++)
                    {
                        z_profile(ia, im, ib, z_in, ic, id, M, N, u, v, a, b, C, D, thhat, psihat, th, out ps, th1, th2, k, f, out double hth, z, ref fault);
                        if (fault)
                        {
                            xl = Constant.MISSING;
                            xu = Constant.MISSING;
                            return;
                        }
                        PP[1] = ps + hth;
                        PP[2] = ps - hth;
                        f = Math.Pow((th - thhat) / z, 2.0);
                        f *= (1.0 - 1.0 / (M + N));
                        f = PP[1] * (1 - PP[1]) / M + PP[2] * (1 - PP[2]) / N - f;
                        if (f < 0.0)
                        {
                            th2 = th;
                        }
                        else { th1 = th; }
                        th = (th1 + th2) * 0.5;
                    }
                }
                e[k] = ps;
                x[k] = th;
            }
            xl = x[1];
            xu = x[2];
        }

        public static void binci(double r, double N, out double pil, out double piu, double cco, out string warn)
        {

            double rp1l = 2.0 * N - 2.0 * r + 2.0;
            double rp2l = 2.0 * r;
            double rp1u = 2.0 * r + 2.0;
            double rp2u = 2.0 * N - 2.0 * r;
            if (r == 0.0)
            {
                pil = 0.0;
            }
            else
            {
                double fivl = PDF.ffromp(rp2l, rp1l, (1.0 - cco) / 2.0);
                if (fivl == Constant.MISSING)
                    pil = Constant.MISSING;
                else
                    pil = r / (r + (N - r + 1.0) * fivl);
            }
            if (r == N)
            {
                piu = 1.0;
            }
            else
            {
                double fivu = PDF.ffromp(rp2u, rp1u, (1.0 - cco) / 2.0);
                if (fivu == Constant.MISSING)
                    piu = Constant.MISSING;
                else
                    piu = (r + 1.0) / (r + 1.0 + (N - r) * (1.0 / fivu));
            }
            if (r == 0.0 || r == N)
                warn = " [" + StatsDirect.Utilities.Formatting.XRound(100.0 * (cco + (1.0 - cco) / 2.0), 1) + "% one-sided CI]";
            else
                warn = string.Empty;
        }

        public static void civ(long df, out double cit, double GAMMA, out double P0)
        {
            double P;

            if (df == 0)
            {
                P = (1.0 - GAMMA) / 2.0;
                cit = PDF.gauinv(1.0 - P);
                P0 = 1.0 - GAMMA;
            }
            else
            {
                P = (1.0 - GAMMA) / 2.0;
                P0 = 1.0 - GAMMA;
                if (P > 1.0 - P)
                    P = 1.0 - P;
                cit = PDF.tfromp(P, Convert.ToDouble(df));
            }
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="fp"></param>
        /// <param name="tp"></param>
        /// <param name="column2total"></param>
        /// <param name="column1total"></param>
        /// <param name="zc"></param>
        /// <param name="thetal"></param>
        /// <param name="thetau"></param>
        /// <remarks>agrees with Agresti's algorithm at http://web.stat.ufl.edu/~aa/cda/R/two_sample/R2/</remarks>
        public static void lr_ci(double fp, double tp, double column2total, double column1total, double zc, out double thetal, out double thetau)
        {
            double lastz = 0;

            if (fp == 0.0 && tp == 0.0 || fp == column2total && tp == column1total)
            {
                thetal = 0.0;
                thetau = double.PositiveInfinity;
            }
            else
            {
                double x0 = fp;
                double x1 = tp;
                double n0 = column2total;
                if (n0 == x0)
                {
                    n0 += 0.5;
                }
                double n1 = column1total;
                if (n1 == x1)
                {
                    n1 += 0.5;
                }
                if (n1 == 0.0 | n0 == 0.0)
                {
                    thetal = Constant.MISSING;
                    thetau = Constant.MISSING;
                    return;
                }
                double P0 = x0 / n0;
                double P1 = x1 / n1;
                double uhat = 1.0 / (x1 + 0.5) + 1.0 / (x0 + 0.5) - 1.0 / (n0 + 0.5) - 1.0 / (n1 + 0.5);
                double N = n0 + n1;
                double logthetahat = Math.Log((x1 + 0.5) / (n1 + 0.5)) - Math.Log((x0 + 0.5) / (n0 + 0.5));
                thetau = Math.Exp(logthetahat) * Math.Exp(zc * Math.Sqrt(uhat));
                thetal = Math.Exp(logthetahat) * Math.Exp(-zc * Math.Sqrt(uhat));
                int i;
                for (i = 1; i <= 2; i++)
                {
                    double za2 = zc;
                    double temptheta1 = i == 1 ? thetau : thetal;
                    double temptheta2 = 0.9 * temptheta1;
                    double ztemp1 = lr_z(ref temptheta1, out double a, out double b, out double c, ref N, ref n0, ref n1, ref x0, ref x1);
                    double diff1 = Math.Abs(za2 - Math.Abs(ztemp1));
                    double ztemp2 = lr_z(ref temptheta2, out a, out b, out c, ref N, ref n0, ref n1, ref x0, ref x1);
                    double diff2 = Math.Abs(za2 - Math.Abs(ztemp2));
                    lr_diff(diff1, diff2, out double theta1, out double theta0, temptheta1, temptheta2, out double z1, out double z0, ztemp1, ztemp2, out double zcritical);
                    int cnt = 0;
                    double theta2;
                    do
                    {
                        if (i == 1)
                        {
                            za2 = -zc;
                        }
                        theta2 = Math.Exp(Math.Log(theta0) + (za2 - z0) / (z1 - z0) * Math.Log(theta1 / theta0));
                        temptheta1 = theta1;
                        temptheta2 = theta2;
                        ztemp2 = lr_z(ref temptheta2, out a, out b, out c, ref N, ref n0, ref n1, ref x0, ref x1);
                        if (ztemp2 == Constant.MISSING)
                        {
                            cnt = 5001;
                            break;
                        }
                        ztemp1 = z1;
                        diff1 = Math.Abs(za2 - ztemp1);
                        diff2 = Math.Abs(za2 - ztemp2);
                        lr_diff(diff1, diff2, out theta1, out theta0, temptheta1, temptheta2, out z1, out z0, ztemp1, ztemp2, out zcritical);
                        cnt += 1;
                        if (cnt > 5000)
                        {
                            break;
                        }
                        if (zcritical == lastz & zcritical < 0.001)
                            break;
                        lastz = zcritical;
                    }
                    while (!(zcritical < 0.0000001));
                    if (i == 1)
                    {
                        if (cnt < 5000)
                        {
                            thetau = theta2;
                        }
                        else
                        {
                            thetau = P0 == 0.0 ? double.PositiveInfinity : Constant.MISSING;
                        }
                    }
                    else
                    {
                        if (cnt < 5000)
                        {
                            thetal = theta2;
                        }
                        else
                        {
                            thetal = P1 == 0.0 ? 0.0 : Constant.MISSING;
                        }
                    }
                }
            }
        }


        // TRANSMISSINGCOMMENT: Method lr_diff
        public static void lr_diff(double diff1, double diff2, out double theta1, out double theta0, double temptheta1, double temptheta2, out double z1, out double z0, double ztemp1, double ztemp2, out double zcritical)
        {
            if (diff1 < diff2)
            {
                theta1 = temptheta1;
                theta0 = temptheta2;
                z1 = ztemp1;
                z0 = ztemp2;
                zcritical = diff1;
            }
            else
            {
                theta0 = temptheta1;
                theta1 = temptheta2;
                z0 = ztemp1;
                z1 = ztemp2;
                zcritical = diff2;
            }
        }


        // TRANSMISSINGCOMMENT: Method lr_ptilde
        public static double lr_ptilde(double theta, double a, double b, double C)
        {
            double pest1 = (-b + Math.Sqrt(b * b - 4.0 * a * C)) / 2.0 / a;
            double pest2 = (-b - Math.Sqrt(b * b - 4.0 * a * C)) / 2.0 / a;
            if (pest1 > 1.0 | pest1 < 0.0)
                return pest2;
            if (pest2 > 1.0 | pest2 < 0.0)
                return pest1;
            if (pest1 * theta > 1.0 | pest1 * theta < 0.0)
                return pest2;
            return pest1;
        }


        // TRANSMISSINGCOMMENT: Method lr_z
        public static double lr_z(ref double thetahat, out double a, out double b, out double C, ref double N, ref double n0, ref double n1, ref double x0, ref double x1)
        {
            double vtilde = 0;

            a = N * thetahat;
            b = -((x0 + n1) * thetahat + x1 + n0);
            C = x0 + x1;
            double p0tilde = lr_ptilde(thetahat, a, b, C);
            double p1tilde = p0tilde * thetahat;
            double q0tilde = 1.0 - p0tilde;
            double q1tilde = 1.0 - p1tilde;
            if (p0tilde == 0.0 || q1tilde == 0.0 || vtilde < 0.0)
            {
                return Constant.MISSING;
            }
            double utilde = q0tilde / (n0 * p0tilde) + q1tilde / (n1 * p1tilde);
            vtilde = 1.0 / utilde;
            return (x1 - n1 * p1tilde) / q1tilde / Math.Sqrt(vtilde);
        }

        ///  <summary>
        ///  
        ///  </summary>
        ///  <param name="xz"></param>
        ///  <returns></returns>
        ///  <remarks>Changed from SD2 version - this returns a double, the old one also formatted that to a pval.  It's now up to the caller to format.</remarks>
        public static double zvalp2(double xz)
        {
            double P = 1.0 - PDF.alnorm(xz);
            if (P > 1.0 - P)
            {
                P = 1.0 - P;
            }
            return P * 2.0;
        }


        public double vector_max(double[] x, int start, int fin)
        {
            double z = double.MinValue;

            for (int i = start; i <= fin; i++)
            {
                if (x[i] > z)
                {
                    z = x[i];
                }
            }
            return z;
        }


        // TRANSMISSINGCOMMENT: Method vector_min
        public static double vector_min(double[] x, int start, int fin)
        {
            double z = double.MaxValue;
            for (int i = start; i <= fin; i++)
            {
                if (x[i] < z)
                {
                    z = x[i];
                }
            }
            return z;
        }


        // TRANSMISSINGCOMMENT: Method rtoz
        public static double rtoz(double r)
        {
            return 0.5 * Math.Log((1 + r) / (1 - r));
        }


        // TRANSMISSINGCOMMENT: Method ztor
        public static double ztor(double z)
        {
            return (Math.Exp(2.0 * z) - 1) / (Math.Exp(2.0 * z) + 1);
        }


        ///  <summary>
        ///  empirical cumulative distribution function ecdf from a vector x
        ///  </summary>
        ///  <param name="x"></param>
        ///  <param name="fn">Output variable, must be assigned to be at least x.Length </param>
        ///  <param name="err"></param>
        ///  <remarks></remarks>
        public static void ecdf(double[] x, double[] fn, out int err)
        {
            int n = x.Length - 1;
            if (n < 3)
            {
                err = 1;
                return;
            }
            err = 0;
            int[] f = new int[n + 1];
            double[] xc = new double[n + 1];
            double[] z = new double[n + 1];
            int i, j;
            int ii = 0;
            for (i = 0; i <= n; i++)
            {
                if (x[i] != Constant.MISSING)
                {
                    z[ii] = x[i];
                    ii += 1;
                }
                else
                {
                    fn[i] = Constant.MISSING;
                }
            }
            n = ii - 1;
            Array.Sort(z, 0, ii);
            i = 0;
            ii = 0;
            do
            {
                int k = 1;
                for (j = i + 1; j <= n; j++)
                {
                    if (z[j] == z[i])
                        k += 1;
                    else
                        break;
                }
                f[ii] = k;
                xc[ii] = z[i];
                if (i + k > n)
                {
                    break;
                }
                i += k;
                ii += 1;
            }
            while (true);
            double[] pecdf = new double[ii + 1];
            n += 1;
            pecdf[0] = 10000.0 * (f[0] / Convert.ToDouble(n)) / 10000.0;
            for (i = 1; i <= ii; i++)
            {
                // allow for rounding error
                pecdf[i] = 10000.0 * (pecdf[i - 1] + f[i] / Convert.ToDouble(n)) / 10000.0;
            }
            for (i = 0; i < x.Length; i++)
            {
                for (j = 0; j <= ii; j++)
                {
                    if (x[i] == xc[j])
                    {
                        fn[i] = pecdf[j];
                        break;
                    }
                }
            }
        }

        public static void zscore(double[] x, ref double[] z, bool doecdf, out int err)
        {
            int n = x.Length - 1;
            if (n < 3)
            {
                err = 1;
                return;
            }
            err = 0;
            if (doecdf == false)
            {
                double mu = 0;
                int i;
                int nx = 0;
                for (i = 0; i <= n; i++)
                {
                    if (x[i] != Constant.MISSING)
                    {
                        mu += x[i];
                        nx += 1;
                    }
                }
                mu /= Convert.ToDouble(nx);
                double sd = 0;
                for (i = 0; i <= n; i++)
                {
                    if (sd > 1.0E+300)
                    {
                        err = 2;
                        return;
                    }
                    if (x[i] != Constant.MISSING)
                    {
                        sd += Math.Pow(x[i] - mu, 2.0);
                    }
                }
                sd /= Convert.ToDouble(nx - 1);
                sd = Math.Sqrt(sd);
                z = new double[n + 1];
                for (i = 0; i <= n; i++)
                {
                    if (x[i] == Constant.MISSING)
                    {
                        z[i] = Constant.MISSING;
                    }
                    else
                    {
                        z[i] = (x[i] - mu) / sd;
                    }
                }

            }
            else
            {
                double[] fn = new double[n + 1];
                ecdf(x, fn, out err);
                if (err != 0)
                {
                    err = 3;
                    return;
                }
                int i;
                for (i = 0; i <= n; i++)
                {
                    double qp = fn[i];
                    if (qp == Constant.MISSING)
                    {
                        z[i] = Constant.MISSING;
                    }
                    else
                    {
                        if (qp <= 0.0)
                        {
                            qp = 0.0000000000001;
                        }
                        if (qp >= 1.0)
                        {
                            qp = 0.9999999999999;
                        }
                        double qz = Math.Abs(PDF.gauinv(qp, out int fault));
                        if (qp < 0.5)
                        {
                            qz = -qz;
                        }
                        if (fault == 0)
                        {
                            z[i] = qz;
                        }
                        else { z[i] = Constant.MISSING; }
                    }
                }
            }
        }
    }
}
