using Microsoft.CodeAnalysis.VisualBasic.Syntax;
using StatsDirect.Data;
using StatsDirect.Numerics;
using StatsDirect.Templates;
using StatsDirect.Utilities;
using System;
using System.Collections.Generic;

namespace StatsDirect.Builtins
{
    public static class Nonparametric
    {

        ///  <summary>
        ///  Returns a list containing a single blank results dictionary.  A handy helper where a template needs to show an error message in a block, but the message has no parameters.
        ///  </summary>
        private static IList<ParameterBag> OneOutputElement() => new List<ParameterBag> { new ParameterBag() };

        ///  <summary>
        ///  
        ///  </summary>
        ///  <param name="x">Input 1-dimensional 1-based array of values.</param>
        ///  <param name="lx">Number of values in x</param>
        ///  <param name="l">Input 1-based array containing lengths of columns</param>
        ///  <param name="cols">Number of columns in L</param>
        ///  <param name="h"></param>
        ///  <param name="ha"></param>
        ///  <param name="t"></param>
        ///  <param name="w1">Output 1-based ranked array (x, ranked)</param>
        ///  <param name="fault">0: Success. 1: At least 2 columns required. 2: Negative column length.3: column lengths don't add up to lx.</param>
        ///  <remarks></remarks>
        private static void XKwt(double[] x, int lx, int[] l, int cols, out double h, ref double ha, ref double t, ref double[] w1, out int fault)
        {
            XPreprocessKwt(x, lx, l, cols, ref t, ref w1, out fault);
            XRunKwt(w1, lx, l, cols, out h, ref ha, t);
        }

        ///  <summary>
        ///  
        ///  </summary>
        ///  <param name="w1">Input 1-dimensional 1-based array of ranks.</param>
        ///  <param name="lx">Number of values in x</param>
        ///  <param name="l">Input 1-based array containing lengths of columns</param>
        ///  <param name="cols">Number of columns in L</param>
        ///  <param name="h"></param>
        ///  <param name="ha">h, adjusted for ties</param>
        ///  <param name="t">Input correction factor from Rank</param>
        ///  <remarks></remarks>
        private static void XRunKwt(double[] w1, int lx, int[] l, int cols, out double h, ref double ha, double t)
        {
            double rs = 0.0;
            for (int i = 1; i <= cols; i++)
            {
                int l1 = 1;
                if (i != 1)
                {
                    int i1 = i - 1;
                    for (int j = 1; j <= i1; j++)
                        l1 += l[j];
                }
                int l2 = l1 + l[i] - 1;
                double rj = 0.0;
                for (int j = l1; j <= l2; j++)
                    rj += w1[j];
                rj = rj * rj / Convert.ToDouble(l[i]);
                rs += rj;
            }

            double xn = lx;
            h = 12.0 * rs / (xn * (xn + 1.0)) - 3.0 * (xn + 1.0);

            if (t != 0.0)
            {
                double s2 = 1.0 - 12.0 * t / (xn * xn * xn - xn);
                if (s2 <= 0.0)
                    ha = Constant.MISSING;
                else
                    ha = h / s2;
            }
        }

        ///  <summary>
        ///  
        ///  </summary>
        ///  <param name="x">Input 1-dimensional 1-based array of values.</param>
        ///  <param name="lx">Number of values in x</param>
        ///  <param name="l">Input 1-based array containing lengths of columns</param>
        ///  <param name="cols">Number of columns in L</param>
        ///  <param name="t"></param>
        ///  <param name="w1">Output 1-based ranked array (x, ranked)</param>
        ///  <param name="fault">0: Success. 1: At least 2 columns required. 2: Negative column length.3: column lengths don't add up to lx. 4: Unknown.</param>
        ///  <remarks></remarks>
        private static void XPreprocessKwt(double[] x, int lx, int[] l, int cols, ref double t, ref double[] w1, out int fault)
        {
            int i;

            fault = 1;
            if (cols < 2)
                return;
            fault = 2;
            int lsum = 0;
            for (i = 1; i <= cols; i++)
            {
                if (l[i] <= 0)
                    return;
                lsum += l[i];
            }

            fault = 3;
            if (lsum != lx)
                return;

            for (i = 2; i <= lx; i++)
            {
                if (x[i] != x[1])
                    break;
                if (i == lx)
                {
                    i = lx + 1;
                    break;
                }
            }
            if (i > lx)
            {
                fault = 4;
                return;
            }

            ExFortran.Rank(x, w1, 1, lx, 1, out t);
            fault = 0;
        }

        public static void XQci(double qc, int rx, double[] r, ref double xq, double gamma, out double ll, out double ul, out double cover, bool conservative, out bool capUpper, out bool capLower, out int fault)
        {
            // get 100*qc'th quantile from sorted vector r
            double iq = qc * (rx + 1);
            if (iq > rx)
                iq = rx;
            // below the first order statistic the quantile is the minimum; "iq < 0" could never be true, and r[0] is not an observation
            if (iq < 1)
                iq = 1;
            if (iq - Math.Floor(iq) == 0)
                xq = r[Convert.ToInt32(iq)];
            if (iq - Math.Floor(iq) != 0)
                xq = r[(int)Math.Floor(iq)] + (r[(int)Math.Floor(iq) + 1] - r[(int)Math.Floor(iq)]) * (iq - Math.Floor(iq));
            double z = Math.Abs(PDF.gauinv((1.0 - gamma) / 2.0, out fault));
            if (fault != 0)
            {
                ll = Constant.MISSING;
                ul = Constant.MISSING;
                capLower = false;
                capUpper = false;
                cover = Constant.MISSING;
                return;
            }
            double rxs = Convert.ToDouble(rx);
            capLower = false;
            capUpper = false;
            if (rx > 200)
            {
                double llId = rxs * qc - z * Math.Sqrt(rxs * qc * (1 - qc));
                double ulId = rxs * qc + z * Math.Sqrt(rxs * qc * (1 - qc));
                if (llId < 1.0)
                {
                    llId = 0.0;
                    capLower = true;
                }
                if (ulId + 1 > rxs)
                {
                    ulId = rxs - 1;
                    capUpper = true;
                }
                if (conservative)
                {
                    // The conservative option was ignored above 200 observations, although the line was still labelled
                    // "(conservative)". As for smaller samples, move each limit outwards until no more than (1 - gamma) / 2 lies
                    // beyond it.
                    double tailArea = (1.0 - gamma) / 2.0;
                    while (llId >= 1.0)
                    {
                        ExFortran.bino(rx, qc, (int)Math.Floor(llId), out double _, out double below, out double _, out _);
                        if (below <= tailArea)
                            break;
                        llId -= 1.0;
                    }
                    if (llId < 1.0)
                    {
                        llId = 0.0;
                        capLower = true;
                    }
                    while (ulId + 1.0 < rxs)
                    {
                        ExFortran.bino(rx, qc, (int)Math.Floor(ulId), out double _, out double upTo, out double _, out _);
                        if (upTo >= 1.0 - tailArea)
                            break;
                        ulId += 1.0;
                    }
                    if (ulId + 1.0 >= rxs)
                    {
                        ulId = rxs - 1.0;
                        capUpper = true;
                    }
                }
                ll = r[(int)Math.Floor(llId) + 1];
                ul = r[(int)Math.Floor(ulId) + 1];
                // The limits are the order statistics numbered floor(llId) + 1 and floor(ulId) + 1, so the interval covers the
                // quantile with probability P(Y <= floor(ulId)) - P(Y <= floor(llId)), as in the branch for smaller samples below.
                // "Id - 1" rounded to the nearest whole number was used here, which is a different term of the binomial
                // distribution whenever the fraction is under a half: the level reported for 400 values was 95.48% where the
                // interval printed has 94.54%.
                ExFortran.bino(rx, qc, (int)Math.Floor(ulId), out double _, out double ulPlox, out double _, out _);
                ExFortran.bino(rx, qc, (int)Math.Floor(llId), out _, out double llPlox, out _, out fault);
                cover = (ulPlox - llPlox) * 100.0;
            }
            else
            {
                double[] plox = new double[rx + 1 /* VB to C# conversion */ ];
                for (int q = 0; q <= rx; q++)
                {
                    ExFortran.bino(rx, qc, q, out double _, out plox[q], out double _, out fault);
                    if (fault != 0)
                    {
                        ll = Constant.MISSING;
                        ul = Constant.MISSING;
                        cover = Constant.MISSING;
                        return;
                    }
                }
                double llCut;
                double ulCut;
                double llMin;
                double ulMin;
                double ulPlox;
                double llPlox;
                double ulId = 0.0;
                double llId = 0.0;
                if (conservative)
                {
                    ulMin = 99;
                    llMin = 99;
                    ulPlox = 0.0;
                    llPlox = 0.0;
                    ulCut = 1.0 - (1.0 - gamma) / 2.0;
                    llCut = (1.0 - gamma) / 2.0;
                    for (int q = 0; q <= rx; q++)
                    {
                        if (Math.Abs(plox[q] - ulCut) < ulMin & plox[q] >= ulCut)
                        {
                            ulMin = Math.Abs(plox[q] - ulCut);
                            ulPlox = plox[q];
                            ulId = q;
                        }
                        if (Math.Abs(plox[q] - llCut) < llMin & plox[q] <= llCut)
                        {
                            llMin = Math.Abs(plox[q] - llCut);
                            llPlox = plox[q];
                            llId = q;
                        }
                    }
                }
                else
                {
                    ulMin = 99;
                    llMin = 99;
                    ulPlox = 0.0;
                    llPlox = 0.0;
                    ulCut = 1.0 - (1.0 - gamma) / 2.0;
                    llCut = (1.0 - gamma) / 2.0;
                    for (int q = 0; q <= rx; q++)
                    {
                        if (Math.Abs(plox[q] - ulCut) < ulMin)
                        {
                            ulMin = Math.Abs(plox[q] - ulCut);
                            ulPlox = plox[q];
                            ulId = q;
                        }
                        if (Math.Abs(plox[q] - llCut) < llMin)
                        {
                            llMin = Math.Abs(plox[q] - llCut);
                            llPlox = plox[q];
                            llId = q;
                        }
                    }
                }
                if (llId < 1.0)
                {
                    llId = 0.0;
                    capLower = true;
                    ExFortran.bino(rx, qc, Convert.ToInt32(llId), out double _, out llPlox, out double _, out fault);
                }
                if (ulId + 1.0 > rxs)
                {
                    ulId = rxs - 1.0;
                    capUpper = true;
                    ExFortran.bino(rx, qc, Convert.ToInt32(ulId), out double _, out ulPlox, out double _, out fault);
                }
                ll = r[(int)Math.Floor(llId) + 1];
                ul = r[(int)Math.Floor(ulId) + 1];
                cover = (ulPlox - llPlox) * 100.0;
            }
            if (fault != 0)
            {
                ll = Constant.MISSING;
                ul = Constant.MISSING;
            }
        }

        private static void XKstwo(double[] d1, int n1, double[] d2, int n2, out double d, out double dp, out double dn)
        {
            Array.Sort(d1, 1, n1);
            Array.Sort(d2, 1, n2);
            double en1 = Convert.ToDouble(n1);
            double en2 = Convert.ToDouble(n2);
            int j1 = 1;
            int j2 = 1;
            double f1N = 0.0;
            double f2N = 0.0;
            dp = 0.0;
            dn = 0.0;
            while (j1 <= n1 & j2 <= n2)
            {
                double dt;
                if (d1[j1] < d2[j2])
                {
                    f1N = Convert.ToDouble(j1) / en1;
                    dt = f1N - f2N;
                    if (dt > dp)
                    {
                        dp = dt;
                    }
                    j1 += 1;
                }
                else if (d1[j1] > d2[j2])
                {
                    f2N = Convert.ToDouble(j2) / en2;
                    dt = f2N - f1N;
                    if (dt > dn)
                    {
                        dn = dt;
                    }
                    j2 += 1;
                }
                else
                {
                    f1N = Convert.ToDouble(j1) / en1;
                    j1 += 1;
                    f2N = Convert.ToDouble(j2) / en2;
                    j2 += 1;
                    while (j1 <= n1)
                    {
                        if (d1[j1] == d1[j1 - 1])
                        {
                            f1N = Convert.ToDouble(j1) / en1;
                            j1 += 1;
                        }
                        else
                        {
                            break;
                        }
                    }
                    while (j2 <= n2)
                    {
                        if (d2[j2] == d2[j2 - 1])
                        {
                            f2N = Convert.ToDouble(j2) / en2;
                            j2 += 1;
                        }
                        else
                        {
                            break;
                        }
                    }
                    dt = f1N - f2N;
                    if (dt > dp)
                    {
                        dp = dt;
                    }
                    dt = f2N - f1N;
                    if (dt > dn)
                    {
                        dn = dt;
                    }
                }
            }
            dp = Math.Max(0, dp);
            dn = Math.Max(0, dn);
            d = Math.Max(dp, dn);
        }

        private static void XDokend(IProgressBarHost host, double cit, int nx, double[] x, double[] y, ref int nxx, out double p, out double q, ref double s, ref double hn, out double siga, out double sigb, ref double varf, ref double tau, ref double ll, ref double ul, out bool fault)
        {
            double sigbt3 = 0; double sigbt2 = 0; double sigbt1 = 0;
            int ytvn = 0; double sigat3 = 0; double sigat2 = 0; double sigat1 = 0;
            int xtvn = 0;

            double[] xtv = new double[nx + 1];
            double[] ytv = new double[nx + 1];
            double[] c = new double[nx + 1];
            fault = true;
            siga = 0;
            sigb = 0;
            p = 0.0;
            q = 0.0;
            if (nx >= 2)
            {
                nxx = nx;
                double gd = cit > 0.0
                    ? (nxx - 1) * 2.0
                    : nxx - 1.0;
                using IProgressBar progress = host.StartProgress("Calculating Kendall", true);
                int n;
                int pn;
                for (pn = 1; pn < nxx; pn++)
                {
                    if (progress.Update(Convert.ToDouble(pn) / gd))
                        throw new TemplateOperationCancelledException();
                    int xtie = 0;
                    int ytie = 0;
                    for (n = pn + 1; n <= nxx; n++)
                    {
                        if ((x[pn] > x[n] && y[pn] > y[n]) || (x[pn] < x[n] && y[pn] < y[n]))
                            p += 1;
                        if ((x[pn] > x[n] && y[pn] < y[n]) || (x[pn] < x[n] && y[pn] > y[n]))
                            q += 1;
                        if (x[pn] == x[n])
                            xtie += 1;
                        if (y[pn] == y[n])
                            ytie += 1;
                    }
                    int count = xtie + 1;
                    bool ok;
                    if (count > 1)
                    {
                        ok = true;
                        for (n = 1; n <= xtvn; n++)
                        {
                            if (x[pn] == xtv[n])
                            {
                                ok = false;
                                break;
                            }
                        }
                        if (ok)
                        {
                            xtvn += 1;
                            xtv[xtvn] = x[pn];
                            siga += count * (count - 1) / 2.0;
                            sigat1 += Convert.ToDouble(count) * Convert.ToDouble(count - 1);
                            sigat2 += Convert.ToDouble(count) * Convert.ToDouble(count - 1) * Convert.ToDouble(count - 2);
                            sigat3 += Convert.ToDouble(count) * Convert.ToDouble(count - 1) * Convert.ToDouble(2 * count + 5);
                        }
                    }
                    count = ytie + 1;
                    if (count > 1)
                    {
                        ok = true;
                        for (n = 1; n <= ytvn; n++)
                        {
                            if (y[pn] == ytv[n])
                            {
                                ok = false;
                                break;
                            }
                        }
                        if (ok)
                        {
                            ytvn += 1;
                            ytv[ytvn] = y[pn];
                            sigb += Convert.ToDouble(count) * Convert.ToDouble(count - 1) / 2.0;
                            sigbt1 += Convert.ToDouble(count) * Convert.ToDouble(count - 1);
                            sigbt2 += Convert.ToDouble(count) * Convert.ToDouble(count - 1) * Convert.ToDouble(count - 2);
                            sigbt3 += Convert.ToDouble(count) * Convert.ToDouble(count - 1) * Convert.ToDouble(2 * count + 5);
                        }
                    }
                }
                s = p - q;
                double xn = Convert.ToDouble(nx);
                hn = xn * (xn - 1.0) / 2.0;
                double tievar1 = (xn * (xn - 1.0) * (2.0 * xn + 5.0) - sigat3 - sigbt3) / 18.0;
                double tievar2 = sigat2 * sigbt2 / (9.0 * xn * (xn - 1.0) * (xn - 2.0));
                double tievar3 = sigat1 * sigbt1 / (2.0 * xn * (xn - 1.0));
                double tievar = tievar1 + tievar2 + tievar3;
                double kendvar = xn * (xn - 1.0) * (2.0 * xn + 5.0) / 18.0;
                varf = siga != 0 || sigb != 0 ? tievar : kendvar;
                tau = s / Math.Sqrt((hn - siga) * (hn - sigb));
                if (cit > 0.0)
                {
                    // Hollander & Wolfe P383 - Samara-Randles confidence interval
                    double dnx = Convert.ToDouble(nxx);
                    double cbar = 2.0 * s / dnx;
                    double cix = 0;
                    for (pn = 1; pn <= nxx; pn++)
                    {
                        if (progress.Update(dnx + Convert.ToDouble(pn) / gd))
                            throw new TemplateOperationCancelledException();
                        for (n = 1; n <= nxx; n++)
                        {
                            if (pn != n)
                            {
                                if ((x[pn] > x[n] & y[pn] > y[n]) | (x[pn] < x[n] & y[pn] < y[n]))
                                    c[pn] = c[pn] + 1;
                                if ((x[pn] > x[n] & y[pn] < y[n]) | (x[pn] < x[n] & y[pn] > y[n]))
                                    c[pn] = c[pn] - 1;
                            }
                        }
                        cix += (c[pn] - cbar) * (c[pn] - cbar);
                    }
                    double vr = 2.0 / (dnx * (dnx - 1.0)) * (2.0 * (dnx - 2.0) / (dnx * (dnx - 1.0) * (dnx - 1.0)) * cix + 1.0 - tau * tau);
                    ll = tau - cit * Math.Sqrt(vr);
                    if (ll < -1.0)
                        ll = -1.0;
                    ul = tau + cit * Math.Sqrt(vr);
                    if (ul > 1.0)
                        ul = 1.0;
                }
                else
                {
                    ll = Constant.MISSING;
                    ul = Constant.MISSING;
                }
            }
            fault = false;
        }

        private static void XInvu(int n2, int n1, double gamma, ref double lev, ref int k, out bool fault)
        {
            double pcum = 0;
            double total = 0;
            int q;

            double alphat = (1 - gamma) / 2;
            if ((n1 > 30 & n2 > 30) | n1 > 100 | n2 > 100)
            {
                double n1S = Convert.ToDouble(n1);
                double n2S = Convert.ToDouble(n2);
                double transTemp0 = PDF.gauinv(alphat) * Math.Sqrt(n1S * n2S * (n1S + n2S) / 12.0);
                k = Convert.ToInt32(n1S * (n1S + n2S + 1.0) / 2.0) + (int)Math.Floor(transTemp0);
                k -= Convert.ToInt32(n1S * ((n1S + 1.0) / 2.0));
                lev = alphat;
            }
            int min = n2 < n1 ? n2 : n1;
            int lfr = n2 * n1 + 1;
            int lwrk = 1 + min + (int)Math.Floor((double)(n2 * n1) / 2);
            if (lfr > 200000 | lwrk > 100000)
            {
                //  make do with the approximate k above
                fault = true;
                return;
            }
            double[] frqncy = new double[lfr + 1 /* VB to C# conversion */];
            double[] work = new double[lwrk + 1 /* VB to C# conversion */];
            XUdist(n2, n1, ref frqncy, ref lfr, ref work, ref lwrk, out fault);
            for (q = 1; q <= lfr; q++)
            {
                total += frqncy[q];
            }
            double unitd = 1.0 / total;
            for (q = 0; q <= lfr; q++)
            {
                pcum += unitd * frqncy[q + 1];
                if (pcum > alphat)
                {
                    break;
                }
            }
            lev = pcum - unitd * frqncy[q + 1];
            k = q;
        }

        private static void XUdist(int m, int n, ref double[] frqncy, ref int lfr, ref double[] work, ref int lwrk, out bool fault)
        {
            fault = true;
            try
            {
                int min = Math.Min(m, n);
                if (min < 1)
                {
                    return;
                }
                int mn1 = m * n + 1;
                if (lfr < mn1)
                {
                    return;
                }
                int max = Math.Max(m, n);
                int n1 = max + 1;
                int i;
                for (i = 1; i <= n1; i++)
                {
                    frqncy[i] = 1;
                }
                if (min == 1)
                {
                    fault = false;
                    return;
                }
                if (lwrk < Math.Floor((double)(min + 1) / 2) + min)
                {
                    return;
                }
                n1 += 1;
                for (i = n1; i <= mn1; i++)
                {
                    frqncy[i] = 0;
                }
                work[1] = 0;
                int zIn = max;
                for (i = 2; i <= min; i++)
                {
                    work[i] = 0;
                    zIn += max;
                    n1 = zIn + 2;
                    double l = 1 + zIn / 2;
                    int k = i;
                    int j;
                    for (j = 1; j <= (int)Math.Floor(l); j++)
                    {
                        k += 1;
                        n1 -= 1;
                        double sum = frqncy[j] + work[j];
                        frqncy[j] = sum;
                        work[k] = sum - frqncy[n1];
                        frqncy[n1] = sum;
                    }
                }
                fault = false;
            }
            catch (OverflowException)
            {
                fault = true;
            }
        }

        ///  <summary>
        ///      LOWER TAIL PROBABILITY P FOR MANN-WHINEY STATISTIC IV
        ///      CASE WHERE THERE ARE NO TIES in THE POOLED SAMPLE
        ///  </summary>
        ///  <param name="n1"></param>
        ///  <param name="n2"></param>
        ///  <param name="iv"></param>
        ///  <param name="p"></param>
        ///  <remarks>
        ///      NEUMANN, N. - SOME PROCEDURES FOR CALCULATING THE
        ///                    DISTRIBUTIONS OF ELEMENTARY NONPARAMETRIC
        ///                    STATISTICS.
        ///      STAT. SOFTWARE NEWSLETTER, VOL. 14, NO 3., 1988
        /// </remarks>
        private static void XMwupNtLtp(int n1, int n2, int iv, out double p)
        {
            int j;
            int i;
            int m2; int m1;

            // at least iv + 2 cells: the product alone is too small when n1 is 1, or 2 with n2 odd, and U is at the centre
            double[] wrk = new double[Math.Max(n1 * ((int)Math.Floor((double)n2 / 2) + 1), iv + 2)];
            if (n1 < n2)
            {
                m1 = n1;
                m2 = n2;
            }
            else
            {
                m1 = n2;
                m2 = n1;
            }
            int lim = iv + 1;
            double binom = 1;
            wrk[1] = 1;
            for (i = 1; i <= m1; i++)
            {
                binom = binom * Convert.ToDouble(m2 + i) / Convert.ToDouble(i);
                int upper;
                if (i * m2 + 1 < lim)
                    upper = i * m2 + 1;
                else
                    upper = lim;
                int lower = i + m2 + 1;
                for (j = upper; j >= lower; j--)
                    wrk[j] = wrk[j] - wrk[j - lower + 1];
                for (j = i + 1; j <= upper; j++)
                    wrk[j] = wrk[j] + wrk[j - i];
            }
            wrk[1] = wrk[1] / binom;
            for (j = 2; j <= lim; j++)
                wrk[j] = wrk[j - 1] + wrk[j] / binom;
            p = wrk[iv + 1];
            if (p > 1)
                p = 1;
            if (p < 0)
                p = 0;
        }

        /// <summary>
        /// Exact one sided P values for the Mann-Whitney U statistic without ties: lower = P(U &lt;= u), upper = P(U &gt;= u),
        /// each including the observed value, so they sum to more than 1.
        /// </summary>
        /// <remarks>
        /// The lower tail routine is only good up to the middle of the distribution, so the tail on the far side of u is
        /// found from the symmetry of U about n1 * n2 / 2. This function used to return whichever tail was the smaller, which
        /// the report then labelled as the lower side: wrong whenever u was above n1 * n2 / 2.
        /// </remarks>
        private static void XMwupNt(int n1, int n2, double u, out double lower, out double upper)
        {
            lower = Constant.MISSING;
            upper = Constant.MISSING;
            if (n1 < 1 || n2 < 1 || u < 0)
                return;

            int nm = n1 * n2;
            int iv = (int)Math.Floor(u);
            if (iv > nm)
                return;
            if (2 * iv <= nm)
            {
                XMwupNtLtp(n1, n2, iv, out lower);
                // P(U >= u) = 1 - P(U <= u - 1)
                if (iv == 0)
                    upper = 1.0;
                else
                {
                    XMwupNtLtp(n1, n2, iv - 1, out double below);
                    upper = 1.0 - below;
                }
            }
            else
            {
                // P(U >= u) = P(U <= nm - u), and P(U <= u) = 1 - P(U >= u + 1) = 1 - P(U <= nm - u - 1)
                XMwupNtLtp(n1, n2, nm - iv, out upper);
                if (iv == nm)
                    lower = 1.0;
                else
                {
                    XMwupNtLtp(n1, n2, nm - iv - 1, out double above);
                    lower = 1.0 - above;
                }
            }
        }

        /// <summary>
        /// Exact one sided P values for the Mann-Whitney U statistic with ties: lower = P(U &lt;= u), upper = P(U &gt;= u), each
        /// including the observed value. See <see cref="XMwupNt"/> for why both are returned.
        /// </summary>
        /// <param name="n1"></param>
        /// <param name="n2"></param>
        /// <param name="ranks">1-based array of ranks, with ties represented as x.5 values</param>
        /// <param name="u">Mann-Whitney U statistic</param>
        /// <param name="lower"></param>
        /// <param name="upper"></param>
        private static void XMwupTi(int n1, int n2, double[] ranks, double u, out double lower, out double upper)
        {
            lower = Constant.MISSING;
            upper = Constant.MISSING;
            if (n1 < 1 || n2 < 1 || u < 0)
                return;

            int nsum = n1 + n2;
            int[] iRanks = new int[2 * (n1 + n2 + 1) + 1]; //  1-based
            for (int i = 1; i <= nsum; i++)
                iRanks[i] = Convert.ToInt32(2 * ranks[i]);
            Array.Sort(iRanks, 1, nsum);
            // everything is doubled so that mid-ranks are whole numbers; the tail routine destroys its copy of the ranks
            int nm = 2 * n1 * n2;
            int iv = Convert.ToInt32(2.0 * u);
            if (iv > nm)
                return;
            if (2 * iv <= nm)
            {
                lower = NonParametric.WilcoxonMannWhitneyLowerTailProbability(n1, n2, (int[])iRanks.Clone(), iv);
                if (iv == 0)
                    upper = 1.0;
                else
                {
                    double below = NonParametric.WilcoxonMannWhitneyLowerTailProbability(n1, n2, (int[])iRanks.Clone(), iv - 1);
                    upper = below == Constant.MISSING ? Constant.MISSING : 1.0 - below;
                }
            }
            else
            {
                // with ties U is not symmetrical, but U for the other sample is nm - U, so its lower tail is this one's upper
                upper = NonParametric.WilcoxonMannWhitneyLowerTailProbability(n2, n1, (int[])iRanks.Clone(), nm - iv);
                if (iv == nm)
                    lower = 1.0;
                else
                {
                    double above = NonParametric.WilcoxonMannWhitneyLowerTailProbability(n2, n1, (int[])iRanks.Clone(), nm - iv - 1);
                    lower = above == Constant.MISSING ? Constant.MISSING : 1.0 - above;
                }
            }
        }

        private static ParameterBag MannWhitneyExactConfidence(ITemplateHost host, double[] x, int k, int n1, int n2)
        {
            double median = 0; double kl = 0;
            int midl; int midu;
            ParameterBag outputParameters = new();

            if (k == -99)
            {
                host.Error("Sample is too large for exact confidence interval calculation.", "Mann-Whitney");
                outputParameters.AddOutput("median", Constant.MISSING);
                outputParameters.AddOutput("from", Constant.MISSING);
                outputParameters.AddOutput("to", Constant.MISSING);
                return outputParameters;
            }
            int limit = n1 * n2;
            if (limit % 2 == 0)
            {
                midu = (int)Math.Floor((double)limit / 2) + 1;
                midl = (int)Math.Floor((double)limit / 2);
            }
            else
            {
                midu = (int)Math.Floor((double)(limit + 1) / 2);
                midl = midu;
            }
            using (IProgressBar progress = host.StartProgress("Calculating Confidence Interval", true))
            {
                int[] xx = new int[n1 + 1];
                int[] yy = new int[n2 + 1];
                Array.Sort(x, n1 + 1, n2);
                Array.Sort(x, 1, n1);

                //  Find the largest value in size (both samples are sorted, so it is at an end of one of them)...
                double bigx = Math.Max(Math.Max(Math.Abs(x[1]), Math.Abs(x[n1])), Math.Max(Math.Abs(x[n1 + 1]), Math.Abs(x[n1 + n2])));
                //  ... and set a scale so that every value fits within the range of an Integer. Only the largest value used to be
                //  looked at, not the largest in size, so negative values below about -21,000 overflowed and the whole report was
                //  lost; the scale could not go below 1, so values above about 2e8 gave no interval; and it could not go above
                //  100000, so very small values gave limits of 0.
                double scaler = 100000.0;
                while (bigx * scaler >= int.MaxValue / 10.0)
                    scaler /= 10.0;
                while (bigx > 0.0 && bigx * scaler < 1000.0 && scaler < 1e300)
                    scaler *= 10.0;
                for (int j = 1; j <= n1; j++)
                    xx[j] = Convert.ToInt32(x[j] * scaler);
                for (int j = 1; j <= n2; j++)
                    yy[j] = Convert.ToInt32(x[n1 + j] * scaler);
                bool domed = true;
                bool dokl = true;
                int goal = midu + k;
                int c = xx[1] - yy[n2] - 1;
                int i = 0;
                while (i < midu)
                {
                    c = ExFortran.findnext(out int occurrences, c, xx, n1, yy, n2);
                    i += occurrences;
                    if (progress.Update(i / (double)goal))
                    {
                        outputParameters.AddOutput("median", Constant.MISSING);
                        outputParameters.AddOutput("from", Constant.MISSING);
                        outputParameters.AddOutput("to", Constant.MISSING);
                        return outputParameters;
                    }
                    if (i >= k)
                    {
                        if (dokl)
                        {
                            dokl = false;
                            kl = c / (double)scaler;
                        }
                    }
                    if (i >= midl)
                    {
                        if (domed)
                        {
                            domed = false;
                            median = c / (double)scaler;
                        }
                    }
                }
                if (midu != midl)
                    median = domed ? c / (double)scaler : (median + c / (double)scaler) / 2;
                for (int j = 1; j <= n1; j++)
                    xx[j] = -xx[j];
                for (int j = 1; j <= n2; j++)
                    yy[j] = -yy[j];
                Array.Sort(xx, 1, n1);
                Array.Sort(yy, 1, n2);
                c = xx[1] - yy[n2] - 1;
                i = 0;
                while (i < k)
                {
                    c = ExFortran.findnext(out int occurrences, c, xx, n1, yy, n2);
                    i += occurrences;
                    if (progress.Update((midu + i) / (double)goal))
                    {
                        outputParameters.AddOutput("median", Constant.MISSING);
                        outputParameters.AddOutput("from", Constant.MISSING);
                        outputParameters.AddOutput("to", Constant.MISSING);
                        return outputParameters;
                    }
                }
                double ku = -c / (double)scaler;
                outputParameters.AddOutput("median", median);
                outputParameters.AddOutput("from", kl);
                outputParameters.AddOutput("to", ku);
            }
            return outputParameters;
        }

        private static double XXmdn(double[] x, int nx, int n1, int n2)
        {
            int n;
            double[] ax;

            if (n2 == 1)
            {
                ax = new double[n1 + 1];
                for (int j = 1; j <= n1; j++)
                    ax[j] = x[j];
                n = n1;
            }
            else
            {
                ax = new double[n2 + 1];
                for (int j = n1 + 1; j <= nx; j++)
                    ax[j - n1] = x[j];
                n = n2;
            }
            if (n >= 2)
            {
                Array.Sort(ax, 1, n);
                double mdn = 0.5 * (n + 1);
                if (mdn - Math.Floor(mdn) != 0)
                    return (ax[Convert.ToInt32(mdn - 0.5)] + ax[Convert.ToInt32(mdn + 0.5)]) / 2.0;
                else
                    return ax[Convert.ToInt32(mdn)];
            }
            return 0;
        }

        public static StepOutput RptCuzick(ParameterBag parameters)
        {
            double varz = 0; double ez = 0; double st = 0; int n = 0; int count = 0;

            DataFrame frame = parameters["data"].AsDataFrame;
            double[] t = new double[2];
            int[] gn = new int[frame.VariableCount];
            for (int j = 0; j < frame.VariableCount; j++)
            {
                int chuck = 0;
                DoubleVariable v = (DoubleVariable)frame.Variables[j];
                for (int k = 0; k < v.Length; k++)
                {
                    if (v.Data[k] != Constant.MISSING)
                    {
                        n++;
                        // create temp variable for copying values 
                        double[] transTemp2 = new double[n + 1];
                        Array.Copy(t, transTemp2, Math.Min(t.Length, transTemp2.Length));
                        t = transTemp2; // TODO: This could be sped up by allocating t in larger blocks and trimming after the loop.
                        t[n] = v.Data[k];
                    }
                    else
                    {
                        chuck++;
                    }
                }
                gn[j] = v.Length - chuck;
            }

            // Fill in scores
            double[] score = new double[frame.VariableCount];
            for (int j = 0; j < frame.VariableCount; j++)
                score[j] = j + 1;

            // If non-default scores exist, fill them in
            if (parameters.ContainsKey("scores") && null != parameters["scores"].AsObject)
            {
                DataFrame scoreFrame = parameters["scores"].AsDataFrame;
                DoubleVariable scoreVariable = (DoubleVariable)scoreFrame.Variables[0];
                for (int j = 0; j < Math.Min(frame.VariableCount, scoreVariable.Length); j++)
                    score[j] = scoreVariable.Data[j];
            }

            double[] r = new double[n + 1];
            ExFortran.Rank(t, r, 1, n, 1, out double tie);
            for (int j = 0; j < frame.VariableCount; j++)
            {
                for (int k = 1; k <= gn[j]; k++)
                {
                    count++;
                    st += r[count] * score[j];
                }
                ez += score[j] * Convert.ToDouble(gn[j]) / Convert.ToDouble(n);
                varz += score[j] * score[j] * Convert.ToDouble(gn[j]) / Convert.ToDouble(n);
            }
            varz -= ez * ez;
            double et = Convert.ToDouble(n) / 2.0 * Convert.ToDouble(n + 1) * ez;
            double vart = Convert.ToDouble(n) * Convert.ToDouble(n) * Convert.ToDouble(n + 1) / 12.0 * varz;
            double stat = (st - et) / Math.Sqrt(vart);

            ParameterBag outputParameters = new();
            outputParameters.AddOutput("groups", frame.VariableCount);
            outputParameters.AddOutput("obs", n);
            string qtq = string.Empty;
            for (int j = 0; j < frame.VariableCount; j++)
            {
                qtq += frame.Variables[j].Title + " (" + score[j] + ")";
                if (j != frame.VariableCount - 1)
                    qtq += ", ";
            }
            outputParameters.AddOutput("order", qtq);
            outputParameters.AddOutput("ez", ez);
            outputParameters.AddOutput("varz", varz);
            outputParameters.AddOutput("t", st);
            outputParameters.AddOutput("et", et);
            outputParameters.AddOutput("vart", vart);
            outputParameters.AddOutput("z", stat);
            double p = 1.0 - PDF.alnorm(Math.Abs(stat));
            if (p > 1.0 - p)
                p = 1.0 - p;
            outputParameters.AddOutput("p_1", p);
            outputParameters.AddOutput("p_2", p * 2.0);
            if (tie != 0)
            {
                ParameterBag tiesParameters = new();
                IList<ParameterBag> tiesList = new List<ParameterBag> { tiesParameters };
                outputParameters.AddOutput("*ties", tiesList);
                vart *= (1.0 - tie * 12.0 / (Convert.ToDouble(n) * (Convert.ToDouble(n) * Convert.ToDouble(n) - 1.0)));
                stat = (st - et) / Math.Sqrt(vart);
                tiesParameters.AddOutput("varttie", vart);
                tiesParameters.AddOutput("ztie", stat);
                p = 1.0 - PDF.alnorm(Math.Abs(stat));
                if (p > 1.0 - p)
                    p = 1.0 - p;
                tiesParameters.AddOutput("p_1tie", p);
                tiesParameters.AddOutput("p_2tie", p * 2.0);
            }
            else
            {
                outputParameters.AddOutput("*ties", null);
            }
            return new StepOutput(outputParameters);
        }

        public static StepOutput RptDiversity(IPreferencesAndProgressBar host, ParameterBag parameters)
        {
            double bias = 0; double biasx = 0;
            double thetase = 0; double thetasex = 0;

            DataFrame frame = parameters["data"].AsDataFrame;
            double gamma = parameters["gamma"].AsDouble;
            int boots = parameters["boots"].AsInt32;
            int bootsDivisor = Math.Max(1, boots / 1000);
            if (gamma <= 0)
                throw new TemplateOperationCancelledException();

            MathDbl.civ(0, out double cit, gamma, out _);
            MersenneTwister rnd = new(); //  Self-seeded
            double[] r = new double[frame.MaxRows + 1];

            ParameterBag outputParameters = new();
            IList<ParameterBag> varList = new List<ParameterBag>();
            outputParameters.AddOutput("*var", varList);
            for (int k = 0; k < frame.VariableCount; k++)
            {
                DoubleVariable v = (DoubleVariable)frame.Variables[k];
                using IProgressBar progress = host.StartProgress("Bootstrapping diversity indices for " + v.Title, true);
                int rx = 0;
                double sumn = 0.0;
                double sumnx = 0.0;
                double sumnp2 = 0.0;
                double sumnp3 = 0.0;
                double sumnlogn = 0.0;
                double sumnlognsq = 0.0;
                int singletons = 0;
                int doubletons = 0;
                foreach (double val in v.Data)
                {
                    if (val != Constant.MISSING & val > 0.0 && val == Math.Floor(val))
                    {
                        rx += 1;
                        r[rx] = val;
                        sumn += r[rx];
                        sumnx += r[rx] * (r[rx] - 1.0);
                        sumnlogn += r[rx] * Math.Log(r[rx]);
                        sumnlognsq += r[rx] * Math.Pow(Math.Log(r[rx]), 2.0);
                        if (Convert.ToInt32(r[rx]) == 1)
                            singletons += 1;
                        if (Convert.ToInt32(r[rx]) == 2)
                            doubletons += 1;
                    }
                }
                if (rx < 3)
                    throw new TemplateOperationCancelledException("Too few observations.  Please use three or more non-zero positive integers.", "Diversity indices");

                double simpson = 1.0 - sumnx / (sumn * (sumn - 1.0));
                double shannon = (sumn * Math.Log(sumn) - sumnlogn) / sumn;
                double np;
                for (int j = 1; j <= rx; j++)
                {
                    np = r[j] / sumn;
                    sumnp2 += Math.Pow(np, 2.0);
                    sumnp3 += Math.Pow(np, 3.0);
                }
                double simvars = (4.0 * sumn * (sumn - 1.0) * (sumn - 2.0) * sumnp3 + 2.0 * sumn * (sumn - 1.0) * sumnp2 - 2.0 * sumn * (sumn - 1.0) * (2.0 * sumn - 3.0) * Math.Pow(sumnp2, 2.0)) / Math.Pow(sumn * (sumn - 1.0), 2.0);
                double simvar = (sumnp3 - Math.Pow(sumnp2, 2.0)) / (0.25 * sumn);
                double simcl;
                double simcu;
                double simse;
                if (simvar < 0.0)
                {
                    simse = Constant.MISSING;
                    simcl = Constant.MISSING;
                    simcu = Constant.MISSING;
                }
                else
                {
                    simse = Math.Sqrt(simvar);
                    simcl = simpson - cit * simse;
                    simcu = simpson + cit * simse;
                }
                double shanvars = (sumnlognsq - Math.Pow(sumnlogn, 2.0) / sumn) / Math.Pow(sumn, 2.0) + Convert.ToDouble(rx - 1) / (2.0 * Math.Pow(sumn, 2.0));
                double shanvar = (sumnlognsq - Math.Pow(sumnlogn, 2.0) / sumn) / Math.Pow(sumn, 2.0);
                double shancl;
                double shancu;
                double shanse;
                if (shanvar < 0.0)
                {
                    shanse = Constant.MISSING;
                    shancl = Constant.MISSING;
                    shancu = Constant.MISSING;
                }
                else
                {
                    shanse = Math.Sqrt(shanvar);
                    shancl = shannon - cit * shanse;
                    shancu = shannon + cit * shanse;
                }
                int gtot = Convert.ToInt32(sumn);

                double[] rb = new double[rx + 1];
                int[] cx = new int[rx + 1];
                double[] simpsonb = new double[boots + 1];
                double[] shannonb = new double[boots + 1];
                double[] simpsonbz = new double[boots + 1];
                double[] shannonbz = new double[boots + 1];
                // get resample boots times
                double theta = 0.0;
                double thetax = 0.0;
                int ctr = 0;
                int ctrx = 0;
                bool ok = true;
                bool studentfault = false;
                // work out cut-offs for scaling pick points
                cx[1] = Convert.ToInt32(r[1]);
                for (int j = 2; j <= rx; j++)
                    cx[j] = cx[j - 1] + Convert.ToInt32(r[j]);

                int pick;
                for (int i = 1; i <= boots; i++)
                {
                    sumn = 0.0;
                    sumnx = 0.0;
                    sumnp2 = 0.0;
                    sumnp3 = 0.0;
                    sumnlogn = 0.0;
                    sumnlognsq = 0.0;
                    for (int j = 1; j <= rx; j++)
                        rb[j] = 0.0;

                    // get N members at random
                    for (int j = 1; j <= gtot; j++)
                    {
                        pick = Math.Min(gtot, (int)Math.Floor(gtot * rnd.NextDouble()) + 1);
                        for (int jj = 1; jj <= rx; jj++)
                        {
                            if (pick <= cx[jj])
                            {
                                rb[jj] = rb[jj] + 1;
                                break;
                            }
                        }
                    }
                    for (int j = 1; j <= rx; j++)
                    {
                        if (rb[j] > 0.0)
                        {
                            sumn += rb[j];
                            sumnx += rb[j] * (rb[j] - 1.0);
                            sumnlogn += rb[j] * Math.Log(rb[j]);
                            sumnlognsq += rb[j] * Math.Pow(Math.Log(rb[j]), 2.0);
                        }
                    }
                    for (int j = 1; j <= rx; j++)
                    {
                        np = rb[j] / sumn;
                        sumnp2 += Math.Pow(np, 2.0);
                        sumnp3 += Math.Pow(np, 3.0);
                    }
                    simpsonb[i] = 1.0 - sumnx / (sumn * (sumn - 1.0));
                    shannonb[i] = (sumn * Math.Log(sumn) - sumnlogn) / sumn;
                    double xse = (sumnp3 - Math.Pow(sumnp2, 2.0)) / (0.25 * sumn);
                    if (xse > 0.0)
                    {
                        // simpsonbz(i) = Abs((simpsonb(i) - simpson) / Sqr(xse))
                        simpsonbz[i] = (simpsonb[i] - simpson) / Math.Sqrt(xse);
                    }
                    else
                    {
                        studentfault = true;
                    }
                    xse = (sumnlognsq - Math.Pow(sumnlogn, 2.0) / sumn) / Math.Pow(sumn, 2.0);
                    if (xse > 0.0)
                    {
                        // shannonbz(i) = Abs((shannonb(i) - shannon) / Sqr(xse))
                        shannonbz[i] = (shannonb[i] - shannon) / Math.Sqrt(xse);
                    }
                    else
                    {
                        studentfault = true;
                    }
                    theta += simpsonb[i];
                    thetax += shannonb[i];
                    if (simpsonb[i] <= simpson)
                        ctr += 1;
                    if (shannonb[i] <= shannon)
                        ctrx += 1;
                    if (i % bootsDivisor == 0)
                    {
                        if (progress.Update(i / (double)boots))
                        {
                            ok = false;
                            break;
                        }
                    }
                }
                double nbcl;
                double nbcu;
                double nbclx;
                double nbcux;
                double blt;
                double bltx;
                double but;
                double butx;
                if (ok)
                {
                    //  get bias and bootstrap variance
                    theta /= Convert.ToDouble(boots);
                    thetax /= Convert.ToDouble(boots);
                    double thetasq = 0.0;
                    double thetasqx = 0.0;
                    for (int i = 1; i <= boots; i++)
                    {
                        thetasq += Math.Pow(simpsonb[i] - theta, 2.0);
                        thetasqx += Math.Pow(shannonb[i] - thetax, 2.0);
                    }
                    thetase = Math.Sqrt(1.0 / Convert.ToDouble(boots - 1) * thetasq);
                    thetasex = Math.Sqrt(1.0 / Convert.ToDouble(boots - 1) * thetasqx);
                    bias = simpson - theta;
                    biasx = shannon - thetax;
                    //  sort boostrap arrays
                    Array.Sort(simpsonb, 1, boots);
                    Array.Sort(shannonb, 1, boots);
                    Array.Sort(simpsonbz, 1, boots);
                    Array.Sort(shannonbz, 1, boots);
                    double alpha = 1.0 - gamma;
                    // ------------------------------------------
                    // 'percentile
                    // q = alpha / 2#
                    // pick = CLng(CDbl(boots - 1) * q) + 1
                    // bl = simpsonb(pick)
                    // blx = shannonb(pick)
                    // pick = CLng(CDbl(boots - 1) * (1# - q)) + 1
                    // bu = simpsonb(pick)
                    // bux = shannonb(pick)
                    // ------------------------------------------
                    // normal
                    MathDbl.civ(boots - 1, out double citt, gamma, out _);
                    nbcl = simpson - citt * thetase;
                    nbcu = simpson + citt * thetase;
                    nbclx = shannon - citt * thetasex;
                    nbcux = shannon + citt * thetasex;
                    // bootstrap-t
                    double q = alpha / 2.0;
                    pick = Convert.ToInt32(Convert.ToDouble(boots - 1) * q) + 1;
                    if (studentfault || simse == Constant.MISSING)
                        but = Constant.MISSING;
                    else
                        but = simpson - simpsonbz[pick] * simse;
                    if (studentfault || shanse == Constant.MISSING)
                        butx = Constant.MISSING;
                    else
                        butx = shannon - shannonbz[pick] * shanse;
                    pick = Convert.ToInt32(Convert.ToDouble(boots - 1) * (1.0 - q)) + 1;
                    if (studentfault || simse == Constant.MISSING)
                        blt = Constant.MISSING;
                    else
                        blt = simpson - simpsonbz[pick] * simse;
                    if (studentfault || shanse == Constant.MISSING)
                        bltx = Constant.MISSING;
                    else
                        bltx = shannon - shannonbz[pick] * shanse;
                    // centred
                    double av;
                    if (but != Constant.MISSING && blt != Constant.MISSING)
                    {
                        av = (but - blt) / 2.0;
                        blt = simpson - av;
                        but = simpson + av;
                    }
                    else
                    {
                        blt = Constant.MISSING;
                        but = Constant.MISSING;
                    }
                    if (butx != Constant.MISSING && bltx != Constant.MISSING)
                    {
                        av = (butx - bltx) / 2.0;
                        bltx = shannon - av;
                        butx = shannon + av;
                    }
                    else
                    {
                        bltx = Constant.MISSING;
                        butx = Constant.MISSING;
                    }
                    // symmetrized bootstrap-t, Vives et al 2002
                    // q = alpha / 2#
                    // pick = CLng(CDbl(boots - 1) * q) + 1
                    // If studentfault = True Or simse = Constant.MISSING Then
                    //  blt = Constant.MISSING
                    // Else
                    //  blt = simpson - simpsonbz(pick) * simse
                    // End If
                    // If studentfault = True Or shanse = Constant.MISSING Then
                    //  bltx = Constant.MISSING
                    // Else
                    //  bltx = shannon - shannonbz(pick) * shanse
                    // End If
                    // If studentfault = True Or simse = Constant.MISSING Then
                    //  but = Constant.MISSING
                    // Else
                    //  but = simpson + simpsonbz(pick) * simse
                    // End If
                    // If studentfault = True Or shanse = Constant.MISSING Then
                    //  butx = Constant.MISSING
                    // Else
                    //  butx = shannon + shannonbz(pick) * shanse
                    // End If
                    // --------------------------------------
                    // 'BC
                    // z0 = CDbl(ctr / boots)
                    // z0 = GAUINV(z0, 0)
                    // p1 = ALNORM(2# * z0 - cit)
                    // p2 = ALNORM(2# * z0 + cit)
                    // pick = CLng(CDbl(boots - 1) * p1) + 1
                    // bcal = simpsonb(pick)
                    // pick = CLng(CDbl(boots - 1) * p2) + 1
                    // bcau = simpsonb(pick)
                    // z0 = CDbl(ctrx / boots)
                    // z0 = GAUINV(z0, 0)
                    // p1 = ALNORM(2# * z0 - cit)
                    // p2 = ALNORM(2# * z0 + cit)
                    // pick = CLng(CDbl(boots - 1) * p1) + 1
                    // bcalx = shannonb(pick)
                    // pick = CLng(CDbl(boots - 1) * p2) + 1
                    // bcaux = shannonb(pick)
                    // ---------------------------------------
                    // 'BCa
                    // 'get influence moments - Armitage P 303
                    // iter = 0
                    // For i = 1 To rx
                    //  sumn = 0#
                    //  sumnx = 0#
                    //  sumnlogn = 0#
                    //  sumnlognsq = 0#
                    //  For j = 1 To rx
                    //   If j = i Then rm1 = r(j) - 1# Else rm1 = r(j)
                    //   If rm1 > 0# Then
                    //    sumn = sumn + rm1
                    //    sumnx = sumnx + rm1 * (rm1 - 1#)
                    //    sumnlogn = sumnlogn + rm1 * Log(rm1)
                    //    sumnlognsq = sumnlognsq + rm1 * Log(rm1) ^ 2#
                    //   End If
                    //  Next
                    //  sumsim = sumsim + (1# - sumnx / (sumn * (sumn - 1#))) * r(i)
                    //  sumshan = sumshan + ((sumn * Log(sumn) - sumnlogn) / sumn) * r(i)
                    // Next
                    // simbar = sumsim / CDbl(gtot - 1)
                    // shanbar = sumshan / CDbl(gtot - 1)
                    // For i = 1 To rx
                    //  sumn = 0#
                    //  sumnx = 0#
                    //  sumnlogn = 0#
                    //  sumnlognsq = 0#
                    //  For j = 1 To rx
                    //   If j = i Then rm1 = r(j) - 1# Else rm1 = r(j)
                    //   If rm1 > 0# Then
                    //    sumn = sumn + rm1
                    //    sumnx = sumnx + rm1 * (rm1 - 1#)
                    //    sumnlogn = sumnlogn + rm1 * Log(rm1)
                    //    sumnlognsq = sumnlognsq + rm1 * Log(rm1) ^ 2#
                    //   End If
                    //  Next
                    //  sim2 = sim2 + ((1# - sumnx / (sumn * (sumn - 1#))) - simbar) ^ 2#
                    //  sim3 = sim3 + ((1# - sumnx / (sumn * (sumn - 1#))) - simbar) ^ 3#
                    //  shan2 = shan2 + (((sumn * Log(sumn) - sumnlogn) / sumn) - shanbar) ^ 2#
                    //  shan3 = shan3 + (((sumn * Log(sumn) - sumnlogn) / sumn) - shanbar) ^ 3#
                    // Next
                    // accel = sim3 / (6# * sim2 ^ 1.5)
                    // accelx = shan3 / (6# * shan2 ^ 1.5)
                    // z0 = CDbl(ctr / boots)
                    // z0 = GAUINV(z0, 0)
                    // p1 = ALNORM(z0 + (z0 - cit) / (1# - accel * (z0 - cit)))
                    // p2 = ALNORM(z0 + (z0 + cit) / (1# - accel * (z0 + cit)))
                    // pick = CLng(CDbl(boots - 1) * p1) + 1
                    // bcal = simpsonb(pick)
                    // pick = CLng(CDbl(boots - 1) * p2) + 1
                    // bcau = simpsonb(pick)
                    // z0 = CDbl(ctrx / boots)
                    // z0 = GAUINV(z0, 0)
                    // p1 = ALNORM(z0 + (z0 - cit) / (1# - accelx * (z0 - cit)))
                    // p2 = ALNORM(z0 + (z0 + cit) / (1# - accelx * (z0 + cit)))
                    // pick = CLng(CDbl(boots - 1) * p1) + 1
                    // bcalx = shannonb(pick)
                    // pick = CLng(CDbl(boots - 1) * p2) + 1
                    // bcaux = shannonb(pick)
                }
                else
                {
                    //bl = Constant.MISSING; 
                    //bu = Constant.MISSING; 
                    //blx = Constant.MISSING; 
                    //bux = Constant.MISSING; 
                    nbcl = Constant.MISSING;
                    nbcu = Constant.MISSING;
                    nbclx = Constant.MISSING;
                    nbcux = Constant.MISSING;
                    blt = Constant.MISSING;
                    but = Constant.MISSING;
                    bltx = Constant.MISSING;
                    butx = Constant.MISSING;
                    //bcal = Constant.MISSING; 
                    //bcau = Constant.MISSING; 
                    //bcalx = Constant.MISSING; 
                    //bcaux = Constant.MISSING; 
                }

                // Chao 1984 extrapolation
                if (singletons < 1)
                    singletons = 1;
                if (doubletons < 1)
                    doubletons = 1;
                double a = Convert.ToDouble(singletons);
                double b = Convert.ToDouble(doubletons);
                int stotal = rx + Convert.ToInt32(Math.Pow(a, 2.0) / (2.0 * b));
                // Chao (1987): var = f2 * (r^4 / 4 + r^3 + r^2 / 2) where r = f1 / f2; the divisors apply to the powers, not inside them
                double stotalvar = b * (Math.Pow(a / b, 4.0) / 4.0 + Math.Pow(a / b, 3.0) + Math.Pow(a / b, 2.0) / 2.0);
                int stotalcl;
                int stotalcu;
                if (stotalvar < 0.0)
                {
                    stotalcl = -1;
                    stotalcu = -1;
                }
                else
                {
                    // Chao's (1987) log-normal interval: the number of classes NOT seen,
                    // S - s = a^2 / 2b, is treated as log-normal, so the lower limit cannot fall below the s classes observed.
                    // C = exp(z sqrt(ln(1 + var / (S - s)^2))); limits s + (S - s) / C and s + (S - s) C.
                    // A symmetrical normal interval was printed before, which often went below s and could be negative.
                    double unseen = Math.Pow(a, 2.0) / (2.0 * b);
                    double c = Math.Exp(cit * Math.Sqrt(Math.Log(1.0 + stotalvar / (unseen * unseen))));
                    stotalcl = Convert.ToInt32(rx + unseen / c);
                    stotalcu = Convert.ToInt32(rx + unseen * c);
                }

                ParameterBag varParameters = new();
                varList.Add(varParameters);
                varParameters.AddOutput("ti", v.Title);
                varParameters.AddOutput("n", gtot);
                if (rx != v.Length)
                    varParameters.AddOutput("msg", "(note " + (v.Length - rx) + " other observations not used)");
                else
                    varParameters.AddOutput("msg", string.Empty);
                varParameters.AddOutput("s", rx);
                varParameters.AddOutput("stotal", stotal);
                varParameters.AddOutput("se-largeSample", Base.SafeSqrt(stotalvar));
                varParameters.AddOutput("pc", gamma * 100);
                varParameters.AddOutput("from-largeSample", stotalcl == -1 ? Formatting.ASTERISK : stotalcl.ToString());
                varParameters.AddOutput("to-largeSample", stotalcu == -1 ? Formatting.ASTERISK : stotalcu.ToString());

                varParameters.AddOutput("simpson", simpson);
                varParameters.AddOutput("dom", 1.0 - simpson);
                varParameters.AddOutput("ds",
                        simpson != 1.0
                            ? 1.0 / (1.0 - simpson)
                            : Constant.MISSING);
                varParameters.AddOutput("se-simpson-largeSample", Base.SafeSqrt(simvar));
                varParameters.AddOutput("ses-simpson", Base.SafeSqrt(simvars));
                varParameters.AddOutput("from-simpson-largeSample", simcl);
                varParameters.AddOutput("to-simpson-largeSample", simcu);
                varParameters.AddOutput("boots", boots);
                varParameters.AddOutput("bias-simpson", bias);
                varParameters.AddOutput("se-simpson-bootstrap", thetase);
                varParameters.AddOutput("from-simpson-bootstrap", nbcl);
                varParameters.AddOutput("to-simpson-bootstrap", nbcu);
                varParameters.AddOutput("from-simpson-bootstrap-t", blt);
                varParameters.AddOutput("to-simpson-bootstrap-t", but);

                varParameters.AddOutput("shannon", shannon);
                varParameters.AddOutput("se-shannon-largeSample", Base.SafeSqrt(shanvar));
                varParameters.AddOutput("ses-shannon", Base.SafeSqrt(shanvars));
                varParameters.AddOutput("from-shannon-largeSample", shancl);
                varParameters.AddOutput("to-shannon-largeSample", shancu);
                varParameters.AddOutput("bias-shannon", biasx);
                varParameters.AddOutput("se-shannon-bootstrap", thetasex);
                varParameters.AddOutput("from-shannon-bootstrap", nbclx);
                varParameters.AddOutput("to-shannon-bootstrap", nbcux);
                varParameters.AddOutput("from-shannon-bootstrap-t", bltx);
                varParameters.AddOutput("to-shannon-bootstrap-t", butx);
            }

            return new StepOutput(outputParameters);
        }

        public static StepOutput RptMannWhitney(ITemplateHost host, ParameterBag parameters)
        {
            double gamma = parameters["gamma"].AsDouble;
            if (gamma <= 0)
                return StepOutput.Empty();

            DataFrame frame = parameters["data"].AsDataFrame;
            DoubleVariable v0 = (DoubleVariable)frame.Variables[0];
            DoubleVariable v1 = (DoubleVariable)frame.Variables[1];
            double[] x = new double[v0.Length + v1.Length + 1];

            int n = 0;
            for (int i = 0; i < v0.Length; i++)
            {
                if (v0.Data[i] != Constant.MISSING)
                {
                    n++;
                    x[n] = v0.Data[i];
                }
            }
            int n1 = n;

            for (int i = 0; i < v1.Length; i++)
            {
                if (v1.Data[i] != Constant.MISSING)
                {
                    n++;
                    x[n] = v1.Data[i];
                }
            }
            int n2 = n - n1;

            NonParametric.MannWhitneyUTest(x, n, n1, n2, out double[] ranks, out double u, out double z, out double xf, out double r1, out bool fault);
            double uprime = n1 * n2 - u;

            ParameterBag outputParameters = new();

            outputParameters.AddOutput("sample_1", v0.Title);
            outputParameters.AddOutput("obs_1", n1);
            outputParameters.AddOutput("median_1", XXmdn(x, n, n1, 1));
            outputParameters.AddOutput("ranksum", r1);

            outputParameters.AddOutput("sample_2", v1.Title);
            outputParameters.AddOutput("obs_2", n2);
            outputParameters.AddOutput("median_2", XXmdn(x, n, n1, n2));

            outputParameters.AddOutput("u", u);
            outputParameters.AddOutput("u_prime", uprime);

            if (!fault)
            {
                string adj = xf > 0 ? " (adjusted for ties)" : string.Empty;
                double n1D = n1;
                double nd = n;
                double dimlim = n1D + n1D * (n1D + 1.0) * nd - n1D * (n1D + 1.0) * (2.0 * n1D + 1.0) / 3.0 + 1.0;
                double p;
                double pl;
                if (n1 > 100 && n2 > 100 || xf != 0 && dimlim > 1000000 || xf == 0 && n1 * ((int)Math.Floor((double)n2 / 2) + 1) > 1000000)
                {
                    outputParameters.AddOutput("stats", "Normalised statistic = " + host.RoundU(z) + adj);
                    pl = PDF.alnorm(z);
                    if (pl > 1.0 - pl)
                        p = 1.0 - pl;
                    else
                        p = pl;
                    outputParameters.AddOutput("p_l", pl);
                    outputParameters.AddOutput("p_u", 1.0 - pl);
                    outputParameters.AddOutput("p_2", p * 2.0);
                }
                else
                {
                    outputParameters.AddOutput("stats", "Exact probability" + adj + ":");
                    // Lower side is P(U <= u), for H1 that x tends to be less than y; upper side is P(U >= u). Each includes the
                    // observed U. Two sided is twice the smaller, at most 1. The smaller tail used to be printed as the
                    // lower side whichever side it was on.
                    double pu;
                    if (xf == 0)
                        XMwupNt(n1, n2, u, out pl, out pu);
                    else
                        XMwupTi(n1, n2, ranks, u, out pl, out pu);
                    if (pl == Constant.MISSING || pu == Constant.MISSING)
                        p = Constant.MISSING;
                    else
                        p = Math.Min(1.0, 2.0 * Math.Min(pl, pu));
                    outputParameters.AddOutput("p_l", pl);
                    outputParameters.AddOutput("p_u", pu);
                    outputParameters.AddOutput("p_2", p);
                }

                outputParameters.AddOutput("pc0", gamma * 100);
                outputParameters.AddOutput("theta", uprime / (n1 * n2));
                outputParameters.AddOutput("tll", ThetaLl(uprime, n1, n2, gamma));
                outputParameters.AddOutput("tul", ThetaUl(uprime, n1, n2, gamma));

                double lev = 0;
                int k = 0;
                bool approx = false;
                if (n1 >= 4 && n2 >= 4)
                    XInvu(n2, n1, gamma, ref lev, ref k, out approx);

                if (n1 < 4 || n2 < 4 || k == 0)
                {
                    // K is 0 when even the widest interval, from the smallest to the largest difference, falls short of the
                    // confidence asked for (4 v 4 at 99%). That used to be printed as a 100% interval with a false upper limit.
                    ParameterBag noconfParameters = new();
                    noconfParameters.AddOutput("reason", n1 < 4 || n2 < 4
                        ? "confidence interval not calculated with fewer than 4 observations in either sample"
                        : "confidence interval not calculated: the samples are too small for " + Formatting.XRound(gamma * 100, 1) + "% confidence");
                    IList<ParameterBag> noconfList = new List<ParameterBag> { noconfParameters };
                    outputParameters.AddOutput("*noconf", noconfList);
                    outputParameters.AddOutput("*conf", null);
                }
                else
                {
                    IList<ParameterBag> confList = new List<ParameterBag>();
                    ParameterBag confParameters = MannWhitneyExactConfidence(host, x, k, n1, n2);
                    confParameters.AddOutput("pc", (1 - lev * 2) * 100);
                    if (approx)
                        confParameters.AddOutput("k", k + " (approx)");
                    else
                        confParameters.AddOutput("k", k);
                    confList.Add(confParameters);
                    outputParameters.AddOutput("*conf", confList);
                    outputParameters.AddOutput("*noconf", null);
                }
            }
            return new StepOutput(outputParameters);
        }

        /// <summary>
        /// Newcombe's Method 5 quadratic minimization for the Mann-Whitney theta (U/mn)
        /// </summary>
        /// <param name="upper"></param>
        /// <param name="tzpre"></param>
        /// <param name="ypre"></param>
        /// <param name="lp"></param>
        /// <param name="ln"></param>
        /// <param name="z"></param>
        /// <param name="t"></param>
        /// <param name="m"></param>
        /// <param name="n"></param>
        /// <returns></returns>
        private static double ThetaTzmin(bool upper, double tzpre, double ypre, double lp, double ln, double z, double t, int m, int n)
        {
            const double prec = double.Epsilon * 10;
            double y = 0;
            for (int i = 1; i <= 100; i++)
            {
                if (tzpre < 0)
                    y = (lp + ypre) / 2;
                else
                    y = (ln + ypre) / 2;
                double tz = ThetaTzfn(upper, y, z, t, m, n);
                if (tzpre >= 0) lp = ypre;
                if (tzpre <= 0) ln = ypre;
                ypre = y;
                tzpre = tz;
                if (Math.Abs(tz) < prec) break;
            }
            return y;
        }

        private static double ThetaTzfn(bool upper, double y, double z, double t, int m, int n)
        {
            double offset = z * Math.Sqrt(y * (1.0 - y) * (1.0 + (0.5 * (m + n) - 1.0) * ((1.0 - y) / (2.0 - y) + y / (1.0 + y))) / (m * n));
            return upper ? y - offset - t : y + offset - t;
        }

        /// <summary>
        /// Newcombe's Method 5 lower confidence limit for the Mann-Whitney theta (U'/mn)
        /// </summary>
        /// <param name="u"></param>
        /// <param name="m"></param>
        /// <param name="n"></param>
        /// <param name="gamma"></param>
        /// <returns></returns>
        private static double ThetaLl(double u, int m, int n, double gamma)
        {
            double alpha = (1.0 - gamma) / 2.0;
            double z = PDF.gauinv(1.0 - alpha);

            double t = u / (m * n);

            if (t == 0)
                return 0;

            if (t < 0 || t > 1)
                return double.NaN;

            const double y0 = 0;
            double tz0 = ThetaTzfn(false, y0, z, t, m, n);
            const double y1 = 1;
            double tz1 = ThetaTzfn(false, y1, z, t, m, n);
            const double y2 = 0.5;
            double tz2 = ThetaTzfn(false, y2, z, t, m, n);
            double lp = tz1 < 0 ? double.NaN : y1;
            double ln = tz0 > 0 ? double.NaN : y0;
            if (double.IsNaN(lp) || double.IsNaN(ln))
                return double.NaN;
            else
                return ThetaTzmin(false, tz2, y2, lp, ln, z, t, m, n);
        }

        /// <summary>
        /// Newcombe's Method 5 upper confidence limit for the Mann-Whitney theta (U'/mn)
        /// </summary>
        /// <param name="u"></param>
        /// <param name="m"></param>
        /// <param name="n"></param>
        /// <param name="gamma"></param>
        /// <returns></returns>
        private static double ThetaUl(double u, int m, int n, double gamma)
        {
            double alpha = (1.0 - gamma) / 2.0;
            double z = PDF.gauinv(1.0 - alpha);

            double t = u / (m * n);

            if (t == 1)
                return 1;

            if (t < 0 || t > 1)
                return double.NaN;

            const double y0 = 0;
            double tz0 = ThetaTzfn(true, y0, z, t, m, n);
            const double y1 = 1;
            double tz1 = ThetaTzfn(true, y1, z, t, m, n);
            const double y2 = 0.5;
            double tz2 = ThetaTzfn(true, y2, z, t, m, n);
            double lp = tz1 < 0 ? double.NaN : y1;
            double ln = tz0 > 0 ? double.NaN : y0;
            if (double.IsNaN(lp) || double.IsNaN(ln))
                return double.NaN;
            return ThetaTzmin(true, tz2, y2, lp, ln, z, t, m, n);
        }

        /// <summary>
        /// True when the first n values of a 1-based array are all equal, so that they cannot be ranked against anything.
        /// </summary>
        private static bool AllTheSame(double[] values, int n)
        {
            for (int i = 2; i <= n; i++)
            {
                if (values[i] != values[1])
                    return false;
            }
            return true;
        }

        public static StepOutput RptSpearman(ParameterBag parameters)
        {
            double gamma = parameters["gamma"].AsDouble;
            if (gamma <= 0)
                throw new Exception("Gamma must be greater than zero");

            DataFrame frame = parameters["data"].AsDataFrame;
            DoubleVariable v0 = (DoubleVariable)frame.Variables[0];
            DoubleVariable v1 = (DoubleVariable)frame.Variables[1];
            double[] prk = new double[v0.Length + 1];
            double[] prk1 = new double[v0.Length + 1];
            int nx = 0;
            for (int n = 0; n < v0.Length; n++)
            {
                if (v0.Data[n] != Constant.MISSING && v1.Data[n] != Constant.MISSING)
                {
                    nx++;
                    prk[nx] = v0.Data[n];
                    prk1[nx] = v1.Data[n];
                }
            }
            if (nx < 2)
                return StepOutput.Empty();

            // With every value of a column the same there is nothing to rank and rho is 0/0, which used to stop the analysis
            // with an arithmetic overflow.
            if (AllTheSame(prk, nx) || AllTheSame(prk1, nx))
                throw new TemplateOperationCancelledException("Rank correlation cannot be calculated when all of the values in a column are the same.", "Spearman rank correlation");

            double[] rka = new double[nx + 1];
            double[] rkb = new double[nx + 1];

            ExFortran.Rank(prk, rka, 1, nx, 1, out double xf);
            ExFortran.Rank(prk1, rkb, 1, nx, 1, out double xf1);
            bool hasTies = xf != 0.0 || xf1 != 0.0;

            double srkd2 = 0;
            double srksq = 0;
            double srksqa = 0;
            double srksqb = 0;
            for (int n = 1; n <= nx; n++)
            {
                srkd2 += (rka[n] - rkb[n]) * (rka[n] - rkb[n]);
                srksq += rka[n] * rkb[n];
                srksqa += rka[n] * rka[n];
                srksqb += rkb[n] * rkb[n];
            }
            double corr = nx * Math.Pow((nx + 1.0) / 2.0, 2.0);
            double sr = (srksq - corr) / (Math.Sqrt(srksqa - corr) * Math.Sqrt(srksqb - corr));
            double cit = PDF.gauinv(gamma + (1 - gamma) / 2);
            int nnx = nx;
            ParameterBag outputParameters = new();
            outputParameters.AddOutput("sample_1", v0.Title);
            outputParameters.AddOutput("sample_2", v1.Title);
            outputParameters.AddOutput("obs", nx);
            outputParameters.AddOutput("rho", sr);

            outputParameters.AddOutput("*ties", hasTies ? OneOutputElement() : null);

            if (nx < 4)
            {
                // Fisher's interval divides by the square root of n - 3, so there is none for 3 pairs (it used to be printed as
                // "-1 to *"); the report already says that the sample is too small.
                outputParameters.AddOutput("*noci", null);
                outputParameters.AddOutput("*ci", null);
            }
            else if (1.0 - Math.Abs(sr) < 1e-12)
            {
                // CI not calculated when rho is 1 or -1. Rho worked out from ranks can miss 1 by a rounding error, which used to
                // give the interval "1 to 1".
                outputParameters.AddOutput("*noci", OneOutputElement());
                outputParameters.AddOutput("*ci", null);
            }
            else
            {
                outputParameters.AddOutput("*noci", null);
                IList<ParameterBag> ciList = new List<ParameterBag>();
                ParameterBag ciParameters = new();
                ciList.Add(ciParameters);
                outputParameters.AddOutput("*ci", ciList);
                double fz = 0.5 * Math.Log((1.0 + sr) / (1.0 - sr));
                double fz1 = fz - cit / Math.Sqrt(nx - 3.0);
                double fz2 = fz + cit / Math.Sqrt(nx - 3.0);
                double con1 = (Math.Exp(2.0 * fz1) - 1.0) / (Math.Exp(2.0 * fz1) + 1.0);
                double con2 = (Math.Exp(2.0 * fz2) - 1.0) / (Math.Exp(2.0 * fz2) + 1.0);
                ciParameters.AddOutput("pc", 100 * gamma);
                ciParameters.AddOutput("from", con1);
                ciParameters.AddOutput("to", con2);
            }
            if (nx < 4)
            {
                // Can not consider probability with very small samples (n < 4)
                outputParameters.AddOutput("*lown", OneOutputElement());
                outputParameters.AddOutput("*results", null);
                outputParameters.AddOutput("ix", Constant.MISSING);
            }
            else
            {
                outputParameters.AddOutput("*lown", null);
                IList<ParameterBag> resultsList = new List<ParameterBag>();
                ParameterBag resultsParameters = new();
                resultsList.Add(resultsParameters);
                outputParameters.AddOutput("*results", resultsList);
                double nxs = nnx;
                double dix = (1.0 - sr) * (nxs * (nxs * nxs - 1.0)) / 6.0;
                outputParameters.AddOutput("ix", dix);
                double qix = nxs * (nxs * nxs - 1.0) / 3.0;
                int fault;
                double pl;
                double pu;
                // prho gives P(S >= ix); the upper side P(S <= ix) includes the observed statistic, so it is 1 - P(S >= ix + 2) as S is even
                if (dix >= int.MaxValue || qix >= int.MaxValue)
                {
                    pl = MathDbl.bigprho(Convert.ToInt64(nxs), dix, out fault);
                    pu = 1.0 - MathDbl.bigprho(Convert.ToInt64(nxs), dix + 2.0, out fault);
                }
                else
                {
                    pl = ExFortran.prho(Convert.ToInt32(nxs), Convert.ToInt32(dix), out fault);
                    pu = 1.0 - ExFortran.prho(Convert.ToInt32(nxs), Convert.ToInt32(dix) + 2, out fault);
                }
                double p = pu < pl ? pu : pl;

                if (fault != 0)
                {
                    // P not calculable
                    resultsParameters.AddOutput("*nop", OneOutputElement());
                    resultsParameters.AddOutput("*results", null);
                }
                else
                {
                    resultsParameters.Add("*nop", null);
                    IList<ParameterBag> results2List = new List<ParameterBag>();
                    ParameterBag results2Parameters = new();
                    results2List.Add(results2Parameters);
                    resultsParameters.AddOutput("*results", results2List);
                    if (hasTies)
                    {
                        // With rho of 1 or -1 the t statistic is infinite and its tail area is 0; tvalp gave a missing value there,
                        // which printed all three P values as "P = *".
                        double p1Approximate = 1.0 - sr * sr <= 1e-12
                            ? 0.0
                            : PDF.tvalp(Math.Abs(sr) * Math.Sqrt(nx - 2) / Math.Sqrt(1.0 - sr * sr), nx - 2);
                        if (p1Approximate > 1.0 - p1Approximate)
                            p1Approximate = 1.0 - p1Approximate;
                        double p2Approximate = Math.Min(1.0, 2.0 * p1Approximate);
                        // p1Approximate is the smaller tail of the t approximation, which lies on the side of the sign of rho. The
                        // one sided values used to be left out with ties, and were printed as "P = *".
                        double puApproximate = sr > 0 ? p1Approximate : sr < 0 ? 1.0 - p1Approximate : 0.5;
                        double plApproximate = sr > 0 ? 1.0 - p1Approximate : sr < 0 ? p1Approximate : 0.5;
                        results2Parameters.AddOutput("p_u", puApproximate);
                        results2Parameters.AddOutput("p_l", plApproximate);
                        results2Parameters.AddOutput("p_2", p2Approximate);
                    }
                    else
                    {
                        results2Parameters.AddOutput("p_u", pu);
                        results2Parameters.AddOutput("p_l", pl);
                        results2Parameters.AddOutput("p_2", Math.Min(1.0, p * 2.0));
                    }
                }
            }
            return new StepOutput(outputParameters);
        }

        public static StepOutput RptNpRegression(IProgressBarHost host, ParameterBag parameters)
        {
            double intercept = 0;
            double uci; double lci; double mdn = 0;
            int index = 0;
            double ptau; double tauUl = 0; double tauLl = 0;
            double tau = 0; double varf = 0; double hn = 0; double s = 0; int nxx = 0; double ymdn = 0; double xmdn = 0;
            string taulab;


            double gamma = parameters["gamma"].AsDouble;
            if (gamma <= 0.0)
                gamma = 0.95;
            double cit = PDF.gauinv(1.0 - (1.0 - gamma) / 2.0, out int ifault);

            DataFrame outcomeFrame = parameters["outcome"].AsDataFrame;
            DoubleVariable v0 = (DoubleVariable)outcomeFrame.Variables[0];
            int rows = v0.Length;
            string ytitle = v0.Title;

            // If index <> 2 Then
            DataFrame predictorFrame = parameters["predictor"].AsDataFrame;
            DoubleVariable v1 = (DoubleVariable)predictorFrame.Variables[0];

            string xtitle = v1.Title;
            // Else
            // Exit Function
            // End If

            double[] x = new double[rows + 1];
            double[] y = new double[rows + 1];
            int ctr = 0;
            for (int i = 1; i <= rows; i++)
            {
                if (index == 2)
                {
                    if (v1.Data[i - 1] != Constant.MISSING)
                    {
                        ctr += 1;
                        x[ctr] = v1.Data[i - 1];
                    }
                }
                else
                {
                    if (v1.Data[i - 1] != Constant.MISSING & v0.Data[i - 1] != Constant.MISSING)
                    {
                        ctr += 1;
                        x[ctr] = v1.Data[i - 1];
                        y[ctr] = v0.Data[i - 1];
                    }
                }
            }
            rows = ctr;

            if (rows <= 4)
                throw new TemplateOperationCancelledException("Too few observations", "Nonparametric Regression");

            // With every predictor value the same no pair of points gives a slope, which used to stop the analysis with an index
            // out of range.
            if (AllTheSame(x, rows))
                throw new TemplateOperationCancelledException("A slope cannot be calculated when all of the predictor values are the same.", "Nonparametric Regression");
            // With every outcome value the same the rank correlation is 0/0 and the chart has no vertical scale.
            if (AllTheSame(y, rows))
                throw new TemplateOperationCancelledException("Nonparametric regression cannot be calculated when all of the outcome values are the same.", "Nonparametric Regression");

            // get x and y medians in order to calculate intercepts later
            double[] axo = new double[rows + 1];
            double[] ayo = new double[rows + 1];
            for (int i = 1; i <= rows; i++)
            {
                axo[i] = x[i];
                ayo[i] = y[i];
            }
            Array.Sort(axo, 1, rows);
            Array.Sort(ayo, 1, rows);
            double imdn = 0.5 * (rows + 1);
            if (imdn < 1)
                imdn = 1;
            if (imdn > rows)
                imdn = rows;
            int fiximdn = (int)Math.Floor(imdn);
            if (imdn - Math.Floor(imdn) == 0)
                xmdn = axo[fiximdn];
            if (imdn - Math.Floor(imdn) != 0)
                xmdn = axo[fiximdn] + (axo[fiximdn + 1] - axo[fiximdn]) * (imdn - Math.Floor(imdn));
            if (imdn - Math.Floor(imdn) == 0)
                ymdn = ayo[fiximdn];
            if (imdn - Math.Floor(imdn) != 0)
                ymdn = ayo[fiximdn] + (ayo[fiximdn + 1] - ayo[fiximdn]) * (imdn - Math.Floor(imdn));

            // rank correlation
            XDokend(host, cit, rows, x, y, ref nxx, out double _, out double _, ref s, ref hn, out double siga, out double sigb, ref varf, ref tau, ref tauLl, ref tauUl, out bool fault);
            if (fault)
            {
                tau = Constant.MISSING;
                taulab = string.Empty;
                ptau = Constant.MISSING;
            }
            else
            {
                taulab = 0 != siga || 0 != sigb
                    ? "tau b"
                    : "tau";
                // the continuity correction moves the score one step towards zero, and leaves a score of zero where it is
                double kz = s < 0
                    ? (s + 1.0) / Math.Sqrt(varf)
                    : s > 0 ? (s - 1.0) / Math.Sqrt(varf) : 0.0;
                double pl = PDF.alnorm(kz);
                ptau = pl < 1.0 - pl
                    ? pl * 2.0
                    : (1.0 - pl) * 2.0;
            }

            string ciNote = string.Empty;
            // regression
            double p = (1.0 - gamma) / 2.0;
            if (p < 0 || p > 1)
                p = 0.025;
            MathDbl.taufromp(p, out double _, out int ix, ref rows, out ifault);
            int cnt = Convert.ToInt32(rows * (rows - 1) / 2);
            if (cnt < 2000000)
            {
                double[] pws = new double[cnt + 1];
                if (ifault == 0)
                {
                    cnt = 0;
                    for (int i = 1; i < rows; i++)
                    {
                        for (int j = i + 1; j <= rows; j++)
                        {
                            if (x[i] != x[j])
                            {
                                cnt++;
                                // adding zero turns a slope of minus zero, which was printed as "-0", into zero
                                if (x[i] != Constant.MISSING & y[j] != Constant.MISSING)
                                    pws[cnt] = (y[i] - y[j]) / (x[i] - x[j]) + 0.0;
                            }
                        }
                    }
                    Array.Sort(pws, 1, cnt);
                    // Conover (1999): with N slopes and w the quantile of Kendall's statistic, the limits are the rth smallest
                    // and the rth largest slope, r = (N - w) / 2 rounded down; the rth largest is the (N + 1 - r)th smallest.
                    // The (N + w) / 2 th was taken for the upper limit, one ordered slope too low, so the interval was too
                    // short at the top and its coverage fell below the level asked for (94.6% for a 95% interval with 12 pairs).
                    int ri = (int)Math.Floor(0.5 * (cnt - ix));
                    int si = cnt + 1 - ri;
                    imdn = 0.5 * (cnt + 1);
                    fiximdn = (int)Math.Floor(imdn);
                    if (imdn < 1)
                        imdn = 1;
                    if (imdn > cnt)
                        imdn = cnt;
                    if (imdn - Math.Floor(imdn) == 0)
                        mdn = pws[fiximdn];
                    if (imdn - Math.Floor(imdn) != 0)
                        mdn = pws[fiximdn] + (pws[fiximdn + 1] - pws[fiximdn]) * (imdn - Math.Floor(imdn));
                    if (ri < 1)
                    {
                        // Too few slopes for an interval at this level of confidence (5 pairs at 99%, or fewer slopes because
                        // of ties in x): r is 0 or less. The limits used to be read from outside the ordered slopes, which
                        // printed a false limit of 0 or stopped the analysis.
                        lci = Constant.MISSING;
                        uci = Constant.MISSING;
                        ciNote = "  (too few pairs for an interval at this level of confidence)";
                    }
                    else
                    {
                        lci = pws[ri];
                        uci = pws[si];
                    }
                    intercept = ymdn - mdn * xmdn;
                }
                else
                {
                    mdn = Constant.MISSING;
                    lci = Constant.MISSING;
                    uci = Constant.MISSING;
                }
            }
            else
            {
                mdn = Constant.MISSING;
                lci = Constant.MISSING;
                uci = Constant.MISSING;
            }

            ParameterBag outputParameters = new();
            outputParameters.AddOutput("ytitle", ytitle);
            outputParameters.AddOutput("xtitle", xtitle);
            outputParameters.AddOutput("obs", rows);

            if (mdn == Constant.MISSING)
            {
                // not enough memory or other error for regression
                outputParameters.AddOutput("*cannotcalculate", OneOutputElement());
                outputParameters.AddOutput("*results", null);
            }
            else
            {
                outputParameters.AddOutput("*cannotcalculate", null);
                ParameterBag resultsParameters = new();
                IList<ParameterBag> resultsList = new List<ParameterBag> { resultsParameters };
                outputParameters.AddOutput("*results", resultsList);
                resultsParameters.AddOutput("pc", 100 * gamma);
                resultsParameters.AddOutput("mdn", mdn);
                resultsParameters.AddOutput("from", lci);
                resultsParameters.AddOutput("to", uci);
                resultsParameters.AddOutput("cinote", ciNote);
                resultsParameters.AddOutput("intercept", intercept);
            }

            outputParameters.AddOutput("taulab", taulab);
            outputParameters.AddOutput("tau", tau);
            outputParameters.AddOutput("p_2", ptau);

            //  Cache a few values for the chart
            outputParameters.AddOutput("mdnValue", mdn);
            outputParameters.AddOutput("interceptValue", intercept);

            return new StepOutput(outputParameters);
        }

        public static StepOutput RptWilcoxon(ITemplateHost host, ParameterBag parameters)
        {
            double gamma = parameters["gamma"].AsDouble;
            if (gamma <= 0)
                throw new Exception("Gamma must be greater than zero");

            DataFrame frame = parameters["data"].AsDataFrame;
            DoubleVariable v0 = (DoubleVariable)frame.Variables[0];
            double[] x = new double[v0.Length + 1];
            double[] y = new double[v0.Length + 1];

            int n;
            string txc;
            if (frame.VariableCount == 1)
            {
                int cnt = 0;
                for (n = 0; n < v0.Length; n++)
                {
                    if (v0.Data[n] != Constant.MISSING)
                    {
                        ++cnt;
                        y[cnt] = 0;
                        x[cnt] = v0.Data[n];
                    }
                }
                n = cnt;
                txc = "(N/A * differences used)";
            }
            else
            {
                int cnt = 0;
                DoubleVariable v1 = (DoubleVariable)frame.Variables[1];
                for (n = 0; n < v0.Length; n++)
                {
                    if (v0.Data[n] != Constant.MISSING && v1.Data[n] != Constant.MISSING)
                    {
                        ++cnt;
                        y[cnt] = v1.Data[n];
                        x[cnt] = v0.Data[n];
                    }
                }
                n = cnt;
                txc = v1.Title;
            }

            if (n < 2)
                throw new TemplateOperationCancelledException();

            double xf, ned, w, pl, pu, p2;
            int n1;
            try
            {
                XWilcoxonSignedRanks(x, y, n, out w, out n1, out ned, out xf, out pl, out pu, out p2);
            }
            catch (Exception)
            {
                throw new TemplateOperationCancelledException("Calculation Error", "Wilcoxon");
            }

            ParameterBag outputParameters = new();
            outputParameters.AddOutput("sample_1", v0.Title);
            outputParameters.AddOutput("sample_2", txc);
            outputParameters.AddOutput("non_0", n1);

            // w is the sum of ranks for positive differences whichever way P is found; with more than 200 pairs it used to be
            // printed as the sum of signed ranks, which it is not.
            outputParameters.AddOutput("sum", "Sum of ranks for positive differences = " + host.RoundU(w));

            string adj = xf != 0 ? " (adjusted for ties)" : string.Empty;

            // The normal approximation is used with more than 200 non-zero differences, as in XWilcoxonSignedRanks; a normalised
            // statistic of exactly zero used to be taken for the exact test.
            if (n1 > 200)
                outputParameters.AddOutput("stats", "Normalised statistic" + adj + " = " + host.RoundU(ned));
            else
                outputParameters.AddOutput("stats", "Exact probability" + adj + ":");

            outputParameters.AddOutput("p_l", pl);
            outputParameters.AddOutput("p_u", pu);
            outputParameters.AddOutput("p_2", p2);

            int k = 0;
            double lev = 0;
            if (n1 >= 4)
                Xsrk(n, gamma, out k, out lev);

            if (n1 < 4 || k == 0)
            {
                // K is 0 when even the widest interval, from the smallest to the largest average of two differences, falls
                // short of the confidence asked for (4 or 5 pairs at 95%). That used to be printed as a 100% interval with
                // a false upper limit.
                ParameterBag noconfParameters = new();
                noconfParameters.AddOutput("reason", n1 < 4
                    ? "confidence interval not calculated with fewer than 4 non-zero differences"
                    : "confidence interval not calculated: there are too few pairs for " + Formatting.XRound(gamma * 100, 1) + "% confidence");
                IList<ParameterBag> noconfList = new List<ParameterBag> { noconfParameters };
                outputParameters.AddOutput("*noconf", noconfList);
                outputParameters.AddOutput("*conf", null);
            }
            else
            {
                IList<ParameterBag> confList = new List<ParameterBag>();
                ParameterBag confParameters = XSrcon(host, n, k, x, y);

                // Xsrk takes K from a normal approximation from 200 pairs, and above 1000 pairs gives the level asked for rather
                // than the level achieved. K is printed again (the template had lost it), labelled when it is approximate.
                string level = n > 1000 ? "Approximate " + Formatting.XRound(gamma * 100, 1) : Formatting.XRound(lev * 100, 1);
                confParameters.AddOutput("pc", level + "% confidence interval for difference between population medians:");
                confParameters.AddOutput("k", "K = " + k + (n >= 200 ? " (approx)" : string.Empty));
                confList.Add(confParameters);
                outputParameters.AddOutput("*conf", confList);
                outputParameters.AddOutput("*noconf", null);
            }

            return new StepOutput(outputParameters);
        }

        /// <summary>
        /// Calculate Wilcoxon signed ranks.
        /// </summary>
        /// <param name="x">1-based array of values</param>
        /// <param name="y">1-based array of values</param>
        /// <param name="n">Number of values in x and y</param>
        /// <param name="w"></param>
        /// <param name="nonzero"></param>
        /// <param name="ned"></param>
        /// <param name="xf"></param>
        /// <param name="pLower"></param>
        /// <param name="pUpper"></param>
        /// <param name="p2"></param>
        private static void XWilcoxonSignedRanks(double[] x, double[] y, int n, out double w, out int nonzero, out double ned, out double xf, out double pLower, out double pUpper, out double p2)
        {

            if (n < 1)
                throw new ArgumentException("At least one pair of values required", nameof(n));

            //count the number of non-zero differences and record their signs and absolute values
            nonzero = 0;
            double[] d = new double[n + 1];
            bool[] isPositiveDifference = new bool[n + 1];
            int nz = 0;
            for (int i = 1; i <= n; i++)
            {
                double delta = x[i] - y[i];
                if (delta != 0.0)
                {
                    ++nonzero;
                    d[nonzero] = Math.Abs(delta);
                    isPositiveDifference[nonzero] = delta > 0.0;
                }
                else
                {
                    nz++;
                }
            }
            if (nonzero < 1)
                throw new ArgumentException("All differences are zero; at least one nonzero difference is required", "x, y");

            //rank the non-zero differences and calculate the tie correction factor (ties^3-ties)/12
            double[] r = new double[nonzero + 1];
            ExFortran.Rank(d, r, 1, nonzero, 1, out xf);

            //compute the test statistic as a sum of ranks for positive differences
            w = 0.0;
            for (int i = 1; i <= nonzero; i++)
            {
                if (isPositiveDifference[i])
                    w += r[i];
            }
            double wmax = nonzero * (nonzero + 1) / 2.0;

            // The method depends on the number of differences that are ranked, not on the number of pairs: with many pairs the same
            // and a handful of differences, n > 200 used to give a normal approximation from as few as five ranks.
            if (nonzero > 200)
            {
                //compute the normalized test
                double var = 0.0;
                double q = 0.0;
                for (int i = 1; i <= nonzero; i++)
                {
                    var += r[i] * r[i];
                    if (!isPositiveDifference[i])
                        q += r[i] * -1;
                    else
                        q += r[i];
                }
                ned = q / Math.Sqrt(var);

                // The three P values follow from the normalised statistic that the report prints (Conover 1999). The one sided
                // values used to divide by the sum of squared ranks rather than its square root, and the upper side took a
                // lower tail area when the statistic was negative, so both came out near 0.5.
                pLower = PDF.alnorm(ned);
                pUpper = PDF.alnorm(-ned);
                p2 = Math.Min(1.0, 2.0 * Math.Min(pLower, pUpper));
            }
            else
            {
                //compute the exact test
                int iwmax = Convert.ToInt32(wmax);

                int[] ir = new int[nonzero + 1];
                int iw;
                if (xf == 0.0)
                {
                    for (int i = 1; i <= nonzero; i++)
                        ir[i] = Convert.ToInt32(r[i]);
                    iw = Convert.ToInt32(w);
                }
                else
                {
                    for (int i = 1; i <= nonzero; i++)
                        ir[i] = Convert.ToInt32(2 * r[i]);
                    iw = Convert.ToInt32(2 * w);
                    iwmax = 2 * iwmax;
                }
                Array.Sort(ir, 1, nonzero);

                //lower tail P
                if (iw == iwmax)
                {
                    pLower = 1.0;
                }
                else if (2 * iw > iwmax)
                {
                    pLower = XWilcoxonSignedRankLowerTailProbability(ir, iwmax - iw - 1, nonzero);
                    pLower = 1.0 - pLower;
                }
                else
                {
                    pLower = XWilcoxonSignedRankLowerTailProbability(ir, iw, nonzero);
                }

                //upper tail P
                if (iw == 0)
                {
                    pUpper = 1.0;
                }
                else if (2 * iw > iwmax)
                {
                    pUpper = XWilcoxonSignedRankLowerTailProbability(ir, iwmax - iw, nonzero);
                }
                else
                {
                    pUpper = XWilcoxonSignedRankLowerTailProbability(ir, iw - 1, nonzero);
                    pUpper = 1.0 - pUpper;
                }

                //two tailed P		
                if (2 * iw > iwmax)
                    p2 = 2.0 * XWilcoxonSignedRankLowerTailProbability(ir, iwmax - iw, nonzero);
                else
                    p2 = 2.0 * XWilcoxonSignedRankLowerTailProbability(ir, iw, nonzero);

                if (p2 > 1.0)
                    p2 = 1.0;

                ned = 0;
            }
        }

        /// <summary>
        /// Given a vector of ranks and the Wilcoxon signed ranks test statistic
        /// this calculates a lower side probability based on Norbert Neumann's
        /// shift algorithm in Statistical Software Newsletter 1988.
        /// </summary>
        /// <param name="rank"></param>
        /// <param name="score"></param>
        /// <param name="n"></param>
        /// <returns></returns>
        private static double XWilcoxonSignedRankLowerTailProbability(int[] rank, int score, int n)
        {

            int iwork = n * (n / 2) + n / 2 + 100;
            double[] prob = new double[iwork + 1];
            for (int i = 1; i <= score + 1; i++)
                prob[i] = 1.0;

            score = Math.Abs(score);

            int upper = 0;
            for (int j = 1; j <= n; j++)
            {
                int shift = rank[j];
                if (shift >= score + 1)
                {
                    prob[score + 1] = prob[score + 1] / Math.Pow(2, n - j + 1);
                    break;
                }
                upper += shift;
                int limit = upper + 1;
                if (upper > score)
                    limit = score + 1;
                for (int k = limit; k >= 1; k--)
                {
                    prob[k] *= 0.5;
                    if (shift < k)
                        prob[k] += 0.5 * prob[k - shift];
                }
            }
            double p = prob[score + 1];
            if (p < 0.0)
                p = 0.0;
            if (p > 1.0)
                p = 1.0;
            return p;
        }

        private static void Xsrk(int sizei, double gamma, out int k, out double lev)
        {
            double alpha = (1 - gamma) / 2;
            if (sizei < 4)
                k = -99;
            else if (sizei >= 4 && sizei < 200)
                k = WilcoxonSignedRankInverse(alpha, sizei);
            else
            {
                double s = Convert.ToDouble(sizei);
                k = Convert.ToInt32(Math.Floor(s * (s + 1) / 4 + PDF.gauinv(alpha) * Math.Sqrt(s * (s + 1) * (2 * s + 1) / 24))) + 1;
            }
            if (k == -99)
            {
                lev = -99;
                return;
            }
            if (sizei > 1000)
            {
                lev = 1.0 - alpha * 2.0;
                return;
            }
            double p = WilcoxonSignedRankP(k - 1, sizei);
            if (p > 0.5)
                p = 1.0 - p;
            lev = 1.0 - p * 2.0;
        }

        /// <summary>
        /// upper tail P for Wilcoxon signed rank statistic x and sample size n
        /// </summary>
        /// <param name="x"></param>
        /// <param name="n"></param>
        /// <returns></returns>
        private static double WilcoxonSignedRankP(double x, int n)
        {
            if (n <= 0)
                return double.NaN;
            x = Math.Floor(x + 1e-7);
            if (x < 0.0)
                return 0.0;
            if (x >= n * (n + 1) / 2.0)
                return 1.0;

            double[] w = new double[n * (n + 1) / 2 / 2 + 1];

            double f = Math.Exp(-n * Math.Log(2.0));
            double p = 0;
            if (x <= n * (n + 1) / 4.0)
            {
                for (int i = 0; i <= x; i++)
                    p += WsrEnum(i, n, ref w) * f;
            }
            else
            {
                x = n * (n + 1) / 2.0 - x;
                for (int i = 0; i < x; i++)
                    p += WsrEnum(i, n, ref w) * f;
            }

            return p;
        }

        /// <summary>
        /// Inverse of Wilcoxon signed ranks statistic distribution for sample size n and upper tail probability p.
        /// </summary>
        /// <param name="x"></param>
        /// <param name="n"></param>
        /// <returns></returns>
        private static int WilcoxonSignedRankInverse(double x, int n)
        {
            if (n <= 0)
                return -99;
            if (x <= 0)
                return 0;
            if (x >= 1)
                return n * (n + 1) / 2;

            double[] w = new double[n * (n + 1) / 2 / 2 + 1];

            double f = Math.Exp(-n * Math.Log(2.0));
            double p = 0;
            int q = 0;
            if (x <= 0.5)
            {
                x -= 10 * double.Epsilon;
                for (; ; )
                {
                    p += WsrEnum(q, n, ref w) * f;
                    if (p >= x)
                        break;
                    q++;
                }
            }
            else
            {
                x = 1 - x + 10 * double.Epsilon;
                for (; ; )
                {
                    p += WsrEnum(q, n, ref w) * f;
                    if (p > x)
                    {
                        q = n * (n + 1) / 2 - q;
                        break;
                    }
                    q++;
                }
            }

            return q;
        }

        /// <summary>
        /// enumeration within the Wilcoxon signed ranks statistic distribution
        /// </summary>
        /// <param name="k"></param>
        /// <param name="n"></param>
        /// <param name="w"></param>
        /// <returns></returns>
        private static double WsrEnum(int k, int n, ref double[] w)
        {
            int u = n * (n + 1) / 2;
            int c = u / 2;

            if (k < 0 || k > u) return 0;
            if (k > c) k = u - k;

            if (n == 1) return 1.0;
            if (w[0] == 1.0) return w[k];

            w[0] = w[1] = 1.0;
            for (int j = 2; j < n + 1; ++j)
            {
                int fin = Math.Min(j * (j + 1) / 2, c);
                for (int i = fin; i >= j; --i)
                {
                    w[i] += w[i - j];
                }
            }

            return w[k];
        }

        private static ParameterBag XSrcon(ITemplateHost host, int size, int k, double[] x, double[] y)
        {
            ParameterBag outputParameters = new();
            long limit = size * (size + 1) / 2;
            if (limit > int.MaxValue)
            {
                host.Error("Sample is too large for exact confidence interval calculation.", "Signed Ranks");
                outputParameters.AddOutput("from", Constant.MISSING);
                outputParameters.AddOutput("to", Constant.MISSING);
                outputParameters.AddOutput("med_diff", Constant.MISSING);
                return outputParameters;
            }
            using (IProgressBar progress = host.StartProgress("Calculating Confidence Interval", true))
            {
                double bigx = x[1];
                for (int j = 1; j <= size; j++)
                {
                    if (x[j] > bigx)
                        bigx = x[j];
                    if (y[j] > bigx)
                        bigx = y[j];
                }

                // the largest value in size, of the data and of their differences (only the largest value used to be looked at, so
                // large negative values overflowed)
                for (int j = 1; j <= size; j++)
                    bigx = Math.Max(bigx, Math.Max(Math.Max(Math.Abs(x[j]), Math.Abs(y[j])), Math.Abs(x[j] - y[j])));
                double scaler = 100000;
                do
                {
                    if (bigx * scaler < Convert.ToDouble(long.MaxValue) / 10.0)
                        break;
                    scaler /= 10;
                }
                while (true);
                // very small values used to give limits of 0, because the scale could not go above 100000
                while (bigx > 0.0 && bigx * scaler < 1000.0 && scaler < 1e300)
                    scaler *= 10;

                long[] xx = new long[size + 1];
                for (int j = 1; j <= size; j++)
                    xx[j] = Convert.ToInt64((x[j] - y[j]) * scaler);
                Array.Sort(xx, 1, size);
                int midu, midl;
                if (limit % 2 == 0)
                {
                    midu = Convert.ToInt32(Math.Floor(limit / 2.0) + 1);
                    midl = (int)Math.Floor(limit / 2.0);
                }
                else
                {
                    midu = (int)Math.Floor((double)(limit + 1) / 2);
                    midl = midu;
                }
                bool domed = true;
                bool dokl = true;
                int goal = midu + k;
                long c = 2 * xx[1] - 1;
                int i = 0;
                double median = 0;
                double kl = 0;
                while (i < midu)
                {
                    c = ExFortran.pairnext(out int occurences, c, xx, size);
                    i += occurences;
                    if (progress.Update(i / (double)goal))
                    {
                        outputParameters.AddOutput("from", Constant.MISSING);
                        outputParameters.AddOutput("to", Constant.MISSING);
                        outputParameters.AddOutput("med_diff", Constant.MISSING);
                        return outputParameters;
                    }
                    if (i >= k)
                    {
                        if (dokl)
                        {
                            dokl = false;
                            kl = c / scaler / 2.0;
                        }
                    }
                    if (i >= midl)
                    {
                        if (domed)
                        {
                            domed = false;
                            median = c / scaler / 2.0;
                        }
                    }
                }
                if (midu != midl)
                {
                    if (domed)
                        median = c / scaler / 2.0;
                    else
                        median = (median + c / scaler / 2.0) / 2.0;
                }
                for (int j = 1; j <= size; j++)
                    xx[j] = -xx[j];
                Array.Sort(xx, 1, size);
                c = 2 * xx[1] - 1;
                i = 0;
                while (i < k)
                {
                    c = ExFortran.pairnext(out int occurences, c, xx, size);
                    i += occurences;
                    if (progress.Update((midu + i) / (double)goal))
                    {
                        outputParameters.AddOutput("from", Constant.MISSING);
                        outputParameters.AddOutput("to", Constant.MISSING);
                        outputParameters.AddOutput("med_diff", Constant.MISSING);
                        return outputParameters;
                    }
                }
                double ku = -c / scaler / 2.0;
                outputParameters.AddOutput("from", kl);
                outputParameters.AddOutput("to", ku);
                outputParameters.AddOutput("med_diff", median);
            }
            return outputParameters;
        }

        public static StepOutput RptSmirnov(ParameterBag parameters)
        {
            int n1 = 0; int n2 = 0;

            DataFrame frame = parameters["data"].AsDataFrame;
            DoubleVariable v0 = (DoubleVariable)frame.Variables[0];
            DoubleVariable v1 = (DoubleVariable)frame.Variables[1];

            double[] d1 = new double[v0.Length + 1];
            double[] d2 = new double[v1.Length + 1];
            foreach (double v in v0.Data)
            {
                if (v != Constant.MISSING)
                {
                    n1 += 1;
                    d1[n1] = v;
                }
            }
            foreach (double v in v1.Data)
            {
                if (v != Constant.MISSING)
                {
                    n2 += 1;
                    d2[n2] = v;
                }
            }
            ParameterBag outputParameters = new();
            outputParameters.AddOutput("x", v0.Title);
            outputParameters.AddOutput("y", v1.Title);
            XKstwo(d1, n1, d2, n2, out double d, out double dp, out double dn);
            outputParameters.AddOutput("d", d);
            // Exact P values conditional on the observed ties (permutation distribution of the
            // statistic over all relabellings of the pooled sample; Schroer and Trenkler, 1995).
            // With no ties this equals the classical exact distribution (ExFortran.ksp2).
            double[] x0 = new double[n1];
            double[] y0 = new double[n2];
            Array.Copy(d1, 1, x0, 0, n1);
            Array.Copy(d2, 1, y0, 0, n2);
            double p = KsTies.TwoSided(x0, y0, d);
            outputParameters.AddOutput("p", p);
            outputParameters.AddOutput("sample_1", v0.Title);
            outputParameters.AddOutput("sample_2", v1.Title);
            outputParameters.AddOutput("d_l", dp);
            // One-sided P values are the exact upper tails of D+ and D-, not half the two-sided P.
            p = KsTies.OneSided(x0, y0, dp);
            outputParameters.AddOutput("p_l", p);
            outputParameters.AddOutput("d_r", dn);
            p = KsTies.OneSided(y0, x0, dn);
            outputParameters.AddOutput("p_r", p);

            return new StepOutput(outputParameters);
        }

        public static StepOutput RptQuantile(ParameterBag parameters)
        {
            bool doConservative = parameters["conservative-ci"].AsBoolean;
            double gamma = parameters["gamma"].AsDouble;
            double qc = parameters["quantile"].AsDouble;
            if (qc >= 1 || qc <= 0)
                qc = 0.5;

            DataFrame frame = parameters["data"].AsDataFrame;

            double[] r = new double[frame.MaxRows + 1];

            ParameterBag outputParameters = new();
            IList<ParameterBag> variableList = new List<ParameterBag>();
            outputParameters.AddOutput("*variable", variableList);
            for (int k = 0; k < frame.VariableCount; k++)
            {
                DoubleVariable v = (DoubleVariable)frame.Variables[k];
                int rx = 0;
                foreach (double val in v.Data)
                {
                    if (val != Constant.MISSING)
                    {
                        rx++;
                        r[rx] = val;
                    }
                }
                Array.Sort(r, 1, rx);

                double xq = 0;
                XQci(qc, rx, r, ref xq, gamma, out double ll, out double ul, out double cover, doConservative, out bool capUpper, out bool capLower, out int _);

                ParameterBag variableParameters = new();
                variableParameters.AddOutput("sample", v.Title);
                variableParameters.AddOutput("size", rx);
                variableParameters.AddOutput("quantile_name", qc == 0.5 ? "median" : qc.ToString());
                variableParameters.AddOutput("value", xq);
                variableParameters.AddOutput("pc", gamma * 100);
                variableParameters.AddOutput("type", doConservative ? "(conservative)" : "(non-conservative)");
                variableParameters.AddOutput("note_from", capLower ? "* " : string.Empty);
                variableParameters.AddOutput("from", ll);
                variableParameters.AddOutput("note_to", capUpper ? "* " : string.Empty);
                variableParameters.AddOutput("to", ul);
                variableParameters.AddOutput("exact", cover);
                variableParameters.AddOutput("note_text", capLower || capUpper ? "  (* limit capped at min/max)" : string.Empty);
                variableList.Add(variableParameters);
            }

            return new StepOutput(outputParameters);
        }

        public static StepOutput RptKendall(IProgressBarHost host, ParameterBag parameters)
        {
            int nxx = 0; int n;
            double ps;
            double gam; double tauUl = 0; double tauLl = 0; double tau = 0;
            double varf = 0; double hn = 0; double s = 0;
            double gamma = parameters["gamma"].AsDouble;
            if (gamma <= 0.0)
                gamma = 0.95;
            double cit = PDF.gauinv(1.0 - (1.0 - gamma) / 2.0, out int ifault);

            DataFrame frame = parameters["data"].AsDataFrame;
            DoubleVariable v0 = (DoubleVariable)frame.Variables[0];
            DoubleVariable v1 = (DoubleVariable)frame.Variables[1];
            int rx = v0.Length;
            double[] x = new double[rx + 1];
            double[] y = new double[rx + 1];
            int nx = 0;
            for (n = 0; n < rx; n++)
            {
                if (v0.Data[n] != Constant.MISSING & v1.Data[n] != Constant.MISSING)
                {
                    nx += 1;
                    x[nx] = v0.Data[n];
                    y[nx] = v1.Data[n];
                }
            }
            // With every value of a column the same all pairs are tied, tau b is 0/0 and the variance of the score is zero: the
            // report used to give a continuity corrected z of minus infinity and "P < 0.0001".
            // With fewer than two complete pairs (two columns entered in different rows, say) the same false result used to appear.
            if (nx < 2)
                throw new TemplateOperationCancelledException("Too few pairs of observations: rank correlation needs at least two rows with a value in both columns.", "Kendall rank correlation");
            if (AllTheSame(x, nx) || AllTheSame(y, nx))
                throw new TemplateOperationCancelledException("Rank correlation cannot be calculated when all of the values in a column are the same.", "Kendall rank correlation");

            XDokend(host, cit, nx, x, y, ref nxx, out double p, out double q, ref s, ref hn, out double siga, out double sigb, ref varf, ref tau, ref tauLl, ref tauUl, out bool fault);
            if (fault)
                throw new TemplateOperationCancelledException();

            ParameterBag outputParameters = new();
            outputParameters.AddOutput("sample_1", v0.Title);
            outputParameters.AddOutput("sample_2", v1.Title);
            outputParameters.AddOutput("obs", nxx);
            outputParameters.AddOutput("con", p);
            outputParameters.AddOutput("dis", q);
            outputParameters.AddOutput("tie", Convert.ToInt64(siga + sigb));
            outputParameters.AddOutput("s", s);
            outputParameters.AddOutput("ses", Math.Sqrt(varf));
            if (p + q > 0)
                gam = (p - q) / (p + q);
            else
                gam = Constant.MISSING;
            outputParameters.AddOutput("gam", gam);

            outputParameters.AddOutput("tb", (siga != 0 || sigb != 0) ? "tau b": "tau");
            outputParameters.AddOutput("tau", tau);
            outputParameters.AddOutput("pc", gamma * 100);
            outputParameters.AddOutput("ll", tauLl);
            outputParameters.AddOutput("ul", tauUl);

            if (siga != 0 || sigb != 0)
                outputParameters.AddOutput("adj", " (adjusted for ties)");
            else
                outputParameters.AddOutput("adj", string.Empty);
            IList<ParameterBag> smallSampleList = nxx < 11 ? new List<ParameterBag> { new ParameterBag() } : null;
            outputParameters.AddOutput("*smallsample", smallSampleList);
            // not used simpler variance in Conover
            // kzl = ((s - 1#) * Sqr(18#)) / Sqr(CDbl(nxx) * (CDbl(nxx) - 1#) * (2# * CDbl(nxx) + 5#))
            double kz = s / Math.Sqrt(varf);
            double pl = PDF.alnorm(kz);
            if (pl < 1.0 - pl)
                ps = pl;
            else
                ps = 1.0 - pl;
            outputParameters.AddOutput("kz", kz);
            outputParameters.AddOutput("p_u", 1.0 - pl);
            outputParameters.AddOutput("p_l", pl);
            outputParameters.AddOutput("p_2", ps * 2.0);
            // the continuity correction moves the score one step towards zero, and leaves a score of zero where it is (it used to
            // be moved to -1, which gave a two sided P of 0.73 for a score of exactly 0 with four pairs)
            if (s < 0)
                kz = (s + 1.0) / Math.Sqrt(varf);
            else if (s > 0)
                kz = (s - 1.0) / Math.Sqrt(varf);
            else
                kz = 0.0;
            pl = PDF.alnorm(kz);
            if (pl < 1.0 - pl)
                ps = pl;
            else
                ps = 1.0 - pl;
            outputParameters.AddOutput("kzcc", kz);
            outputParameters.AddOutput("p_ucc", 1.0 - pl);
            outputParameters.AddOutput("p_lcc", pl);
            outputParameters.AddOutput("p_2cc", ps * 2.0);

            ifault = 0;
            int ls = Convert.ToInt32(s);
            //if ( Information.Err().Number != 0 ) 
            //{ 
            //    ps = Constant.MISSING; 
            //} 
            //else 
            double puExact;
            {
                //  kendp gives P(S' >= ls), including ls; the distribution of S is symmetric about zero, so the lower side P(S' <= ls) is P(S' >= -ls).
                //  The lower side was 1 - P(S' >= ls), which left the observed score out, so it and the two sided P were too small whenever tau was negative.
                puExact = MathDbl.kendp(ls, nxx, ref ifault);
                pl = ifault != 0 ? Constant.MISSING : MathDbl.kendp(-ls, nxx, ref ifault);
                if (ifault != 0)
                {
                    ps = Constant.MISSING;
                    pl = Constant.MISSING;
                    puExact = Constant.MISSING;
                }
                else
                {
                    ps = Math.Min(pl, puExact);
                }
            }
            if (siga != 0 || sigb != 0)
                outputParameters.AddOutput("adjexact", " (NOT adjusted for ties)");
            else
                outputParameters.AddOutput("adjexact", string.Empty);
            outputParameters.AddOutput("p_uexact", puExact);
            outputParameters.AddOutput("p_lexact", pl);
            outputParameters.AddOutput("p_2exact", ps == Constant.MISSING ? Constant.MISSING : Math.Min(1.0, ps * 2));

            return new StepOutput(outputParameters);
        }

        public static StepOutput RptFriedmanSimulateExactP(IProgressBarHost host, ParameterBag parameters)
        {
            DataFrame frame = parameters["data"].AsDataFrame;
            int iterations = parameters["iterations"].AsInt32;
            double ci = parameters["ci"].AsDouble;
            int seed = parameters["seed"].AsInt32;
            int bootsDivisor = Math.Max(1, iterations / 1000);

            using IProgressBar progress = host.StartProgress("Simulating exact P", true);
            PreprocessFriedman(frame, out double[,] x, out int n, out int treatments, out bool allAreBinary, out bool numbersAreSmall);

            double a2 = 0;
            double b2 = 0;
            double t1 = 0;
            double t2 = 0;
            double nd = 0;
            double[] w2 = new double[treatments + 1];
            CalcFriedman(x, w2, n, treatments, ref a2, ref b2, ref t1, ref t2, ref nd);
            double actualT = allAreBinary ? t1 : t2;

            int q = 0;
            MersenneTwister rnd = new(seed);
            int iteration;
            for (iteration = 1; iteration <= iterations; iteration++)
            {
                if (iteration % bootsDivisor == 0)
                    if (progress.Update(iteration / (double)iterations))
                        break;
                ShuffleValuesWithinRows(x, rnd, treatments, n);
                CalcFriedman(x, w2, n, treatments, ref a2, ref b2, ref t1, ref t2, ref nd);
                double t = allAreBinary ? t1 : t2;
                if (t >= actualT)
                    q += 1;
            }
            int actualIterations = iteration - 1;

            ParameterBag outputParameters = new();
            double p = q / (double)actualIterations;
            outputParameters.AddOutput("p", p);
            //  CI
            MathDbl.binci(q, actualIterations, out double ll, out double ul, ci, out string warn);
            outputParameters.AddOutput("pc", 100.0 * ci);
            outputParameters.AddOutput("ll", ll);
            outputParameters.AddOutput("ul", ul);
            outputParameters.AddOutput("warn", warn);
            outputParameters.AddOutput("k", actualIterations.ToString());
            outputParameters.AddOutput("seed_fmt", seed);
            return new StepOutput(outputParameters);
        }

        ///  <summary>
        ///  Randomly move values in each row of x between columns.  Values will never be moved between rows.
        ///  </summary>
        ///  <param name="x">The (1,1)-based array whose values are to be shuffled</param>
        ///  <param name="rnd">The random number generator from which to take values</param>
        /// <param name="cols"></param>
        /// <param name="rows"></param>
        public static void ShuffleValuesWithinRows(double[,] x, MersenneTwister rnd, int cols, int rows)
        {
            for (int row = 1; row <= rows; row++)
            {
                //  TODO: Is there a "better" shuffle than this?
                for (int col = 1; col <= cols; col++)
                {
                    int from = rnd.NextInteger(1, cols);
                    double tmp = x[col, row];
                    x[col, row] = x[from, row];
                    x[from, row] = tmp;
                }
            }
        }

        ///  <summary>
        ///  Randomly shuffle values between lowerBound and upperBound in x.
        ///  </summary>
        ///  <param name="x">The lowerBound-based array whose values are to be shuffled</param>
        ///  <param name="rnd">The random number generator from which to take values</param>
        /// <param name="lowerBound"></param>
        /// <param name="upperBound"></param>
        public static void ShuffleValuesWithinArray(double[] x, MersenneTwister rnd, int lowerBound, int upperBound)
        {
            for (int i = lowerBound; i <= upperBound; i++)
            {
                int from = rnd.NextInteger(lowerBound, upperBound);
                double tmp = x[i];
                x[i] = x[from];
                x[from] = tmp;
            }
        }

        public static StepOutput RptFriedman(ParameterBag parameters)
        {
            DataFrame frame = parameters["data"].AsDataFrame;

            double a2 = 0;
            double b2 = 0;
            double t1 = 0;
            double t2 = 0;
            double nd = 0;
            CalcFriedman(frame, out double[] w2, out int n, ref a2, ref b2, ref t1, ref t2, ref nd, out bool allAreBinary, out bool numbersAreSmall);

            string tlist = string.Empty; string rlist = string.Empty;
            for (int d = 0; d < frame.VariableCount; d++)
            {
                if (d == 0)
                {
                    tlist = frame.Variables[d].Title;
                    rlist = Formatting.XRound(w2[d + 1] / nd, 2);
                }
                else
                {
                    tlist = tlist + ", " + frame.Variables[d].Title;
                    rlist = rlist + ", " + Formatting.XRound(w2[d + 1] / nd, 2);
                }
            }
            ParameterBag outputParameters = new();
            outputParameters.AddOutput("tlist", tlist);
            outputParameters.AddOutput("rlist", rlist);

            outputParameters.AddOutput("a2", a2);
            outputParameters.AddOutput("nb", n);
            outputParameters.AddOutput("t1", t1);
            outputParameters.AddOutput("df", frame.VariableCount - 1);

            outputParameters.AddOutput("t2", t2);

            int df = (n - 1) * (frame.VariableCount - 1);
            double dfn = frame.VariableCount - 1;
            double dfd = df;
            double p;
            if (allAreBinary)
            {
                p = PDF.chivalp(t1, dfn);
                outputParameters.AddOutput("testName", "Cochran");
            }
            else
            {
                p = PDF.fvalp(t2, dfn, dfd);
                outputParameters.AddOutput("testName", "Friedman");
            }
            outputParameters.AddOutput("p", p);

            if (p <= 0.05)
            {
                ParameterBag messageParameters = new();
                messageParameters.AddOutput("msg", "At least one of your sample populations tends to yield larger observations than at least one other sample population.");
                IList<ParameterBag> messageList = new List<ParameterBag> { messageParameters };
                outputParameters.AddOutput("*message", messageList);

            }
            else
            {
                outputParameters.AddOutput("*message", null);
            }

            if (p <= 0.05)
            {
                ParameterBag warnParameters = new();
                warnParameters.AddOutput("warning", "Numbers are small: use simulated exact probability instead.");
                List<ParameterBag> warnList = new() { warnParameters };
                outputParameters.AddOutput("*warn", warnList);

            }
            else
            {
                outputParameters.AddOutput("*warn", null);
            }

            //  Cache values for possible further calculation
            outputParameters.AddInput("w2", w2);
            outputParameters.AddInput("N", n);
            outputParameters.AddInput("A2", a2);
            outputParameters.AddInput("B2", b2);

            return new StepOutput(outputParameters);
        }

        private static void PreprocessFriedman(DataFrame frame, out double[,] x, out int n, out int treatments, out bool allAreBinary, out bool numbersAreSmall)
        {
            x = new double[frame.VariableCount + 1, frame.Variables[0].Length + 1];
            allAreBinary = true;
            int qty = 0;
            int positiveCellCount = 0;
            for (int j = 0; j < frame.Variables[0].Length; j++)
            {
                bool skip = false;
                for (int d = 0; d < frame.VariableCount; d++)
                {
                    if (((DoubleVariable)frame.Variables[d]).Data[j] == Constant.MISSING)
                        skip = true;
                }
                if (!skip)
                {
                    qty += 1;
                    for (int d = 0; d < frame.VariableCount; d++)
                    {
                        double dat = ((DoubleVariable)frame.Variables[d]).Data[j];
                        x[d + 1, qty] = dat;
                        if (dat > 0)
                            positiveCellCount += 1;
                        if (allAreBinary && !(dat == 1.0 || dat == 0.0))
                            allAreBinary = false;
                    }
                }
            }

            n = qty;
            treatments = frame.VariableCount;
            numbersAreSmall = positiveCellCount < 25;
        }

        ///  <summary>
        ///  Calculate and set w2, N, A2, B2 from the values in frame.
        ///  </summary>
        ///  <param name="frame"></param>
        ///  <param name="w2"></param>
        ///  <param name="n"></param>
        ///  <param name="a2"></param>
        ///  <param name="b2"></param>
        /// <param name="t1"></param>
        /// <param name="t2"></param>
        /// <param name="nd"></param>
        /// <param name="allAreBinary"></param>
        /// <param name="numbersAreSmall"></param>
        private static void CalcFriedman(DataFrame frame, out double[] w2, out int n, ref double a2, ref double b2, ref double t1, ref double t2, ref double nd, out bool allAreBinary, out bool numbersAreSmall)
        {
            PreprocessFriedman(frame, out double[,] x, out n, out int treatments, out allAreBinary, out numbersAreSmall);
            w2 = new double[treatments + 1];
            CalcFriedman(x, w2, n, treatments, ref a2, ref b2, ref t1, ref t2, ref nd);
        }

        ///  <summary>
        ///  Calculate and set w2, N, A2, B2 from the values in x, N and treatments.
        ///  </summary>
        ///  <param name="x"></param>
        ///  <param name="w2">Values will be set.  Must already be defained and of length treatments.</param>
        ///  <param name="n"></param>
        ///  <param name="treatments"></param>
        ///  <param name="a2"></param>
        ///  <param name="b2"></param>
        ///  <param name="t1"></param>
        ///  <param name="t2"></param>
        ///  <param name="nd"></param>
        ///  <remarks></remarks>
        private static void CalcFriedman(double[,] x, double[] w2, int n, int treatments, ref double a2, ref double b2, ref double t1, ref double t2, ref double nd)
        {
            double[] w1 = new double[treatments + 1];

            if (n > 1)
            {
                double[] x1D = new double[treatments + 1];
                for (int col = 1; col <= treatments; col++)
                {
                    x1D[col] = x[col, 1];
                }
                ExFortran.Rank(x1D, w2, 1, treatments, 0, out double xf);
                a2 = 0;
                for (int g = 1; g <= treatments; g++)
                {
                    a2 += w2[g] * w2[g];
                }

                if (n != 1)
                {
                    for (int j = 2; j <= n; j++)
                    {
                        for (int col = 1; col <= treatments; col++)
                        {
                            x1D[col] = x[col, j];
                        }
                        ExFortran.Rank(x1D, w1, 1, treatments, 0, out xf);
                        for (int g = 1; g <= treatments; g++)
                        {
                            w2[g] += w1[g];
                            a2 += w1[g] * w1[g];
                        }
                    }
                }

                b2 = 0;
                for (int g = 1; g <= treatments; g++)
                {
                    b2 += w2[g] * w2[g];
                }

                nd = Convert.ToDouble(n);
                double kd = Convert.ToDouble(treatments);
                b2 /= nd;
                //  Conover P 370
                double c1 = nd * kd * (kd + 1.0) * (kd + 1.0) / 4.0;
                t2 = (nd - 1.0) * (b2 - c1) / (a2 - b2);
                t1 = (kd - 1.0) * (b2 * nd - nd * c1) / (a2 - c1);
            }
        }

        public static StepOutput RptFrMultiple(ParameterBag parameters)
        {
            DataFrame frame = parameters["data"].AsDataFrame;
            double confidence = parameters["confidence"].AsDouble;

            double[] w2;
            int n;
            double a2 = 0;
            double b2 = 0;
            // moved variable nd definition here so can be used in mean value calculations;
            double nd = 0;
            if (parameters.ContainsKey("w2") && parameters.ContainsKey("N") && parameters.ContainsKey("A2") && parameters.ContainsKey("B2"))
            {
                w2 = (double[])parameters["w2"].AsObject;
                n = parameters["N"].AsInt32;

                // added as part of #27 
                nd = Convert.ToDouble(parameters["N"].AsInt32);

                a2 = parameters["A2"].AsDouble;
                b2 = parameters["B2"].AsDouble;
            }
            else
            {
                //  Calculate parameters
                double t1 = 0;
                double t2 = 0;

                CalcFriedman(frame, out w2, out n, ref a2, ref b2, ref t1, ref t2, ref nd, out bool allAreBinary, out bool numbersAreSmall);
            }

            ParameterBag outputParameters = new();
            double dfq = (n - 1) * (frame.VariableCount - 1);
            double p = confidence;

            // Evaluates the input parameters for the sided value
            // The output "sided" is used to change which creole file is used.
            int sided = 2;
            if (parameters["sided"].HasData)
            {
                sided = Parsing.Cint_Txt(parameters["sided"].AsString);
                if (sided == 1)
                {
                    outputParameters.AddOutput("sidedoutput", "one");
                }
                else if (sided == 2)
                {
                    outputParameters.AddOutput("sidedoutput", "two");
                }
            }

            if (p == 0)
                p = 0.05;

            if (p > 1.0 - p)
                p = 1.0 - p;

            // 1-sided test extension, issue #19
            if (sided == 2)
                p /= 2.0;

            double tval = PDF.tfromp(p, dfq);
            double tcriq = Math.Pow(Math.Abs(2 * n * (a2 - b2) / dfq), 0.5);
            double tcrit = tcriq * tval;

            outputParameters.AddOutput("df", dfq);
            outputParameters.AddOutput("t", tval);

            // 1-sided
            if (sided == 1)
            {
                IList<ParameterBag> pairList = new List<ParameterBag>();
                for (int g = 1; g < frame.VariableCount; g++)
                {
                    for (int j = g + 1; j <= frame.VariableCount; j++)
                    {
                        ParameterBag pairParameters = new();
                        double stata = w2[g] - w2[j];
                        pairParameters.AddOutput("t1", frame.Variables[g - 1].Title);
                        pairParameters.AddOutput("t2", frame.Variables[j - 1].Title);
                        pairParameters.AddOutput("diff", Math.Abs(stata) > tcrit ? "significant" : "not significant");
                        pairParameters.AddOutput("stata", stata);
                        pairParameters.AddOutput("tcrit", tcrit);
                        p = PDF.tvalp(Math.Abs(stata / tcriq), dfq);
                        if (p > 1.0 - p)
                            p = 1.0 - p;
                        // 1-sided variant suggested by Norman Grover
                        pairParameters.AddOutput("p", p);
                       
                        pairList.Add(pairParameters);

                        // determine the tail direction for reporting the variable names big > small
                        double meanRank1 = w2[g] / nd;
                        double meanRank2 = w2[j] / nd;

                        if (meanRank1 > meanRank2)
                            pairParameters.AddOutput("compare", ">");
                        else
                            pairParameters.AddOutput("compare", "<");
                        // 
                    }
                }
                outputParameters.AddOutput("*pair", pairList);
            }
            else // 2-sided
            {
                IList<ParameterBag> pairList = new List<ParameterBag>();
                for (int g = 1; g < frame.VariableCount; g++)
                {
                    for (int j = g + 1; j <= frame.VariableCount; j++)
                    {
                        ParameterBag pairParameters = new();
                        double stata = w2[g] - w2[j];
                        pairParameters.AddOutput("t1", frame.Variables[g - 1].Title);
                        pairParameters.AddOutput("t2", frame.Variables[j - 1].Title);
                        pairParameters.AddOutput("diff", Math.Abs(stata) > tcrit ? "significant" : "not significant");
                        pairParameters.AddOutput("stata", stata);
                        pairParameters.AddOutput("tcrit", tcrit);
                        p = PDF.tvalp(Math.Abs(stata / tcriq), dfq);
                        if (p > 1.0 - p)
                            p = 1.0 - p;
                        pairParameters.AddOutput("p", 2.0 * p);
                        pairList.Add(pairParameters);
                    }
                }
                outputParameters.AddOutput("*pair", pairList);

            }
            return new StepOutput(outputParameters);
        }

        public static StepOutput RptKruskal(ParameterBag parameters)
        {
            DataFrame frame = parameters["data"].AsDataFrame;

            int prelx = 0;
            foreach (IVariable v in frame.Variables)
            {
                prelx += v.Length;
            }
            double[] x = new double[prelx + 1];
            int[] l = new int[frame.VariableCount + 1];

            int qty = 0;
            for (int d = 0; d < frame.VariableCount; d++)
            {
                int cnt = 0;
                DoubleVariable v = (DoubleVariable)frame.Variables[d];
                foreach (double val in v.Data)
                {
                    if (val != Constant.MISSING)
                    {
                        qty += 1;
                        cnt += 1;
                        x[qty] = val;
                    }
                }
                l[d + 1] = cnt;
            }
            int lx = qty;

            // With every observation the same there is nothing to rank; the report used to give mean ranks of 0 and
            // T = -3(N + 1), a negative chi-square.
            if (lx >= 2 && AllTheSame(x, lx))
                throw new TemplateOperationCancelledException("The Kruskal-Wallis test cannot be calculated when all of the observations are the same.", "Kruskal-Wallis");

            double[] w1 = new double[lx + 1];
            double ha = 0;
            double t = 0;
            XKwt(x, lx, l, frame.VariableCount, out double h, ref ha, ref t, ref w1, out int ifault);

            string tlist = string.Empty;
            for (int d = 0; d < frame.VariableCount; d++)
            {
                if (d > 0)
                {
                    tlist += ", ";
                }
                tlist += frame.Variables[d].Title;
            }

            string rlist = string.Empty;
            double meanrank;
            int ik = 0;
            for (int d = 0; d < frame.VariableCount; d++)
            {
                if (d > 0)
                {
                    rlist += ", ";
                }
                meanrank = 0.0;
                for (int i = 0; i < l[d+1]; i++)
                {
                    ik += 1;
                    meanrank += w1[ik];
                }
                meanrank = meanrank/l[d+1];
                rlist += Formatting.XRound(meanrank, 2);
            }

            ParameterBag outputParameters = new();
            outputParameters.AddOutput("tlist", tlist);
            outputParameters.AddOutput("rlist", rlist);

            int df = frame.VariableCount - 1;
            outputParameters.AddOutput("grps", frame.VariableCount);
            outputParameters.AddOutput("df", df);
            outputParameters.AddOutput("tot_obs", lx);

            outputParameters.AddOutput("*fault", ifault != 0 ? OneOutputElement() : null);
            outputParameters.AddOutput("t", h);
            double p = h == Constant.MISSING ? Constant.MISSING : PDF.chivalp(h, df);
            outputParameters.AddOutput("p", p);

            if (t != 0)
            {
                ParameterBag tiesParameters = new();
                List<ParameterBag> tiesList = new() { tiesParameters };
                outputParameters.AddOutput("*ties", tiesList);
                tiesParameters.AddOutput("t_ties", ha);
                p = ha == Constant.MISSING ? Constant.MISSING : PDF.chivalp(ha, df);
                tiesParameters.AddOutput("p_ties", p);
            }
            else
            {
                outputParameters.AddOutput("*ties", null);
            }

            if (p <= 0.05)
            {

                ParameterBag messageParameters = new();
                messageParameters.AddOutput("msg", "At least one of your sample populations tends to yield larger observations than at least one other sample population.");
                IList<ParameterBag> messageList = new List<ParameterBag> { messageParameters };
                outputParameters.AddOutput("*message", messageList);
            }
            else
            {
                outputParameters.AddOutput("*message", null);
            }

            return new StepOutput(outputParameters);
        }

        public static StepOutput RptKruskalSimulateExactP(IProgressBarHost host, ParameterBag parameters)
        {
            DataFrame frame = parameters["data"].AsDataFrame;
            int iterations = parameters["iterations"].AsInt32;
            double ci = parameters["ci"].AsDouble;
            int seed = parameters["seed"].AsInt32;
            int bootsDivisor = Math.Max(1, iterations / 1000);

            using IProgressBar progress = host.StartProgress("Simulating exact P", true);

            int prelx = 0;
            foreach (IVariable v in frame.Variables)
                prelx += v.Length;
            double[] x = new double[prelx + 1];
            int[] l = new int[frame.VariableCount + 1];

            int qty = 0;
            for (int d = 0; d < frame.VariableCount; d++)
            {
                int cnt = 0;
                DoubleVariable v = (DoubleVariable)frame.Variables[d];
                foreach (double val in v.Data)
                {
                    if (val != Constant.MISSING)
                    {
                        qty++;
                        cnt++;
                        x[qty] = val;
                    }
                }
                l[d + 1] = cnt;
            }
            int lx = qty;

            double[] w1 = new double[lx + 1];
            double t = 0;
            int cols = frame.VariableCount;
            XPreprocessKwt(x, lx, l, cols, ref t, ref w1, out int _);

            //  Without ties
            double actualha = 0; //  With ties
            XRunKwt(w1, lx, l, cols, out double actualh, ref actualha, t);

            double actual = t != 0 ? actualha : actualh;

            int r = 0;
            MersenneTwister rnd = new(seed);
            int iteration;
            for (iteration = 1; iteration <= iterations; iteration++)
            {
                if (iteration % bootsDivisor == 0)
                    if (progress.Update(iteration / (double)iterations))
                        break;
                ShuffleValuesWithinArray(w1, rnd, 1, lx);
                double ha = 0;
                XRunKwt(w1, lx, l, cols, out double h, ref ha, t);
                double thisOne = t != 0 ? ha : h;
                if (thisOne >= actual)
                    r += 1;
            }
            int actualIterations = iteration - 1;

            ParameterBag outputParameters = new();
            double p = r / (double)actualIterations;
            outputParameters.AddOutput("p", p);
            //  CI
            MathDbl.binci(r, actualIterations, out double ll, out double ul, ci, out string warn);
            outputParameters.AddOutput("pc", 100.0 * ci);
            outputParameters.AddOutput("ll", ll);
            outputParameters.AddOutput("ul", ul);
            outputParameters.AddOutput("warn", warn);
            outputParameters.AddOutput("k", actualIterations);
            outputParameters.AddOutput("seed_fmt", seed);
            return new StepOutput(outputParameters);
        }

        public static StepOutput RptKwMultiple(ParameterBag parameters)
        {
            double[] ri;
            double[] x;

            DataFrame frame = parameters["data"].AsDataFrame;
            double confidence = parameters["confidence"].AsDouble;

           ParameterBag outputParameters = new();

            double p = confidence;

            // Issue #19: Extended to accommodate 1-sided (Conover-Iman)
            // The output "sided" is used to change which creole file is used.
            int sided = 2;
            if (parameters["sided"].HasData)
            {
                sided = Parsing.Cint_Txt(parameters["sided"].AsString);
                if (sided == 1)
                {
                    outputParameters.AddOutput("sidedoutput", "one");
                }
                else if (sided == 2)
                {
                    outputParameters.AddOutput("sidedoutput", "two");
                }
            }

            ////////////////////////////////////////////////////////////////////////
            // MOVED CODE SO GET ACCESS TO l
            //  Re-do Kruskal-Wallis test (from rpt_kruskal)
            int prelx = 0;
            int[] l = new int[frame.VariableCount + 1];
            foreach (IVariable varbl in frame.Variables)
                prelx += varbl.Length;
            x = new double[prelx + 1];


            int qty = 0;
            for (int d = 0; d < frame.VariableCount; d++)
            {
                int cnt = 0;
                DoubleVariable varbl = (DoubleVariable)frame.Variables[d];
                foreach (double val in varbl.Data)
                {
                    if (val != Constant.MISSING)
                    {
                        qty += 1;
                        cnt += 1;
                        x[qty] = val;
                    }
                }
                l[d + 1] = cnt;
            }
            int lx = qty;

            if (lx >= 2 && AllTheSame(x, lx))
                throw new TemplateOperationCancelledException("Comparisons cannot be calculated when all of the observations are the same.", "Kruskal-Wallis");

            double[] w1 = new double[lx + 1];
            double ha = 0;
            double t = 0;
            XKwt(x, lx, l, frame.VariableCount, out double h, ref ha, ref t, ref w1, out int _);
            //  End copy from rpt_kruskal
            //////////////////////////////////////////////////////////////////////////////

            // treatment groups
            int k = frame.VariableCount;

            // 2 sided
            // Steel-Dwass-Critchlow-Fligner method
            if (sided != 1)
            {
                if (p == 0)
                    p = 0.95;
                double qval = PDF.quantsr(p, k, 1000000.0);

                outputParameters.AddOutput("q", qval);

                IList<ParameterBag> variableList = new List<ParameterBag>();
                for (int i = 1; i < frame.VariableCount; i++)
                {
                    for (int j = i + 1; j <= k; j++)
                    {

                        int i0 = i - 1;
                        int j0 = j - 1;
                        int kn = frame.Variables[i0].Length + frame.Variables[j0].Length;
                        x = new double[kn + 1];
                        ri = new double[kn + 1];

                        int ki = 0;
                        foreach (double val in ((DoubleVariable)frame.Variables[i0]).Data)
                        {
                            if (val != Constant.MISSING)
                            {
                                ki += 1;
                                x[ki] = val;
                            }
                        }

                        int kj = 0;
                        foreach (double val in ((DoubleVariable)frame.Variables[j0]).Data)
                        {
                            if (val != Constant.MISSING)
                            {
                                kj += 1;
                                x[ki + kj] = val;
                            }
                        }

                        kn = ki + kj;
                        ExFortran.Rank(x, ri, 1, kn, 5, out double ct);

                        double sr1 = 0.0;
                        double sr2 = 0.0;
                        for (int n = 1; n <= ki; n++)
                            sr1 += ri[n];
                        for (int n = ki + 1; n <= ki + kj; n++)
                            sr2 += ri[n];
                        double njj;
                        double nii;
                        double wij;
                        if (ki < kj)
                        {
                            wij = sr1;
                            nii = ki;
                            njj = kj;
                        }
                        else
                        {
                            wij = sr2;
                            nii = kj;
                            njj = ki;
                        }

                        double v = nii * njj / 24.0;
                        v *= (nii + njj + 1.0 - ct / ((nii + njj) * (nii + njj - 1.0)));
                        double wx = (wij - nii * (nii + njj + 1) / 2.0) / Math.Sqrt(v);

                        ParameterBag variableParameters = new();
                        variableParameters.AddOutput("t1", frame.Variables[i0].Title);
                        variableParameters.AddOutput("t2", frame.Variables[j0].Title);
                        variableParameters.AddOutput("diff", Math.Abs(wx) > qval ? "significant" : "not significant");
                        variableParameters.AddOutput("wx", wx);
                        variableParameters.AddOutput("qval", qval);
                        p = 1.0 - PDF.probsr(Math.Abs(wx), k, 1000000.0);
                        variableParameters.AddOutput("p", p);
                                                
                        variableList.Add(variableParameters);
                    }
                }
                outputParameters.AddOutput("*dwass", variableList);
            }

            // Conover-Iman method
            p = confidence;
            if (p == 0)
                p = 0.05;
            if (p > 1.0 - p)
                p = 1.0 - p;
            // updates p as per issue #19 - Norman Grover suggested 1-sided version of Conover-Iman test
            if (sided != 1)
                p /= 2.0;
            double df = lx - frame.VariableCount;
            double tval = PDF.tfromp(p, df);
            outputParameters.AddOutput("df", df);
            outputParameters.AddOutput("t", tval);

            // get rank sums for each group
            ri = new double[k + 1];
            qty = 0;
            for (int d = 1; d <= k; d++)
            {
                for (int n = 1; n <= l[d]; n++)
                {
                    qty++;
                    ri[d] = ri[d] + w1[qty];
                }
            }

            // get inequalities (Fisher LSD on ranks) for each pair
            // Conover (1999), Practical Nonparametric Statistics, 3rd edition: the variance of the ranks
            // allows for ties, S2 = (sum of squared ranks - N(N+1)^2/4) / (N - 1), which is N(N+1)/12 when there are none, and the
            // Kruskal-Wallis statistic is the one adjusted for ties. N(N+1)/12 and the unadjusted statistic were used before,
            // ties or not, which made the comparisons slightly conservative with tied data.
            double sumSquaredRanks = 0.0;
            for (int n = 1; n <= lx; n++)
                sumSquaredRanks += w1[n] * w1[n];
            double s2 = (sumSquaredRanks - lx * (lx + 1.0) * (lx + 1.0) / 4.0) / (lx - 1.0);
            double hForTies = t != 0.0 && ha != Constant.MISSING ? ha : h;
            double s2X = s2 * (lx - 1.0 - hForTies) / (lx - frame.VariableCount);

            IList<ParameterBag> inequalityList = new List<ParameterBag>();
            for (int i = 1; i < frame.VariableCount; i++)
            {
                for (int j = i + 1; j <= k; j++)
                {
                    double stata = Math.Abs(ri[i] / l[i] - ri[j] / l[j]);
                    double statq = Math.Sqrt(s2X) * Math.Sqrt(1.0 / l[i] + 1.0 / l[j]);
                    double statb = tval * statq;

                    ParameterBag inequalityParameters = new();

                    if (sided == 1){
                        // determine the tail direction for reporting the variable names big > small
                        double meanrank1 = ri[i] / l[i];
                        double meanrank2 = ri[j] / l[j];
                        if (meanrank1 > meanrank2)
                            inequalityParameters.AddOutput("compare", ">");
                        else
                            inequalityParameters.AddOutput("compare", "<");
                        // 
                    } else
                    {
                        inequalityParameters.AddOutput("compare", "vs");
                    }
                    inequalityParameters.AddOutput("t1", frame.Variables[i - 1].Title);
                    inequalityParameters.AddOutput("t2", frame.Variables[j - 1].Title);
                    inequalityParameters.AddOutput("diff", stata > statb ? "significant" : "not significant");
                    inequalityParameters.AddOutput("stata", stata);
                    inequalityParameters.AddOutput("statb", statb);

                    p = PDF.tvalp(Math.Abs(stata / statq), df);
                    if (p > 1.0 - p)
                        p = 1.0 - p;
                    // update as per issue #19
                    if ( sided == 1 )
                       inequalityParameters.AddOutput("p", p);
                    else
                       inequalityParameters.AddOutput("p", 2.0 * p);
                    inequalityList.Add(inequalityParameters);
                }
            }
            outputParameters.AddOutput("*conover", inequalityList);
            return new StepOutput(outputParameters);
        }

        public static StepOutput RptSqRank(ParameterBag parameters)
        {
            double ru = 0;

            DataFrame frame = parameters["data"].AsDataFrame;

            double confidence = parameters["confidence"].AsDouble;

            double[] mean = new double[frame.VariableCount];
            int[] l = new int[frame.VariableCount];
            double[] sj = new double[frame.VariableCount];
            int nx = 0;
            for (int d = 0; d < frame.VariableCount; d++)
            {
                int cnt = 0;
                double sum = 0;
                DoubleVariable varbl = (DoubleVariable)frame.Variables[d];
                foreach (double val in varbl.Data)
                {
                    if (val != Constant.MISSING)
                    {
                        cnt += 1;
                        nx += 1;
                        sum += val;
                    }
                }
                l[d] = cnt;
                mean[d] = sum / cnt;
            }
            double[] x = new double[nx + 1];
            double[] r = new double[nx + 1];

            int qty = 0;
            for (int d = 0; d < frame.VariableCount; d++)
            {
                DoubleVariable varbl = (DoubleVariable)frame.Variables[d];
                foreach (double val in varbl.Data)
                {
                    if (val != Constant.MISSING)
                    {
                        qty += 1;
                        x[qty] = Math.Abs(val - mean[d]);
                    }
                }
            }

            ExFortran.Rank(x, r, 1, nx, 1, out double _);

            ParameterBag outputParameters = new();
            if (frame.VariableCount > 2)
            {
                int cnt = 0;
                double sbar = 0;
                double r4 = 0;
                double sj2N = 0;
                for (int d = 0; d < frame.VariableCount; d++)
                {
                    for (int n = 1; n <= l[d]; n++)
                    {
                        cnt += 1;
                        sj[d] = sj[d] + r[cnt] * r[cnt];
                        r4 += Math.Pow(r[cnt], 4.0);
                    }
                    sbar += sj[d];
                    sj2N += sj[d] * sj[d] / l[d];
                }
                sbar /= nx;
                double d2 = 1.0 / (nx - 1) * (r4 - nx * sbar * sbar);
                double t2 = 1.0 / d2 * (sj2N - nx * sbar * sbar);
                double x2 = t2;
                int df = frame.VariableCount - 1;

                outputParameters.AddOutput("x2", x2);
                outputParameters.AddOutput("df", df);
                double p = PDF.chivalp(x2, df);
                outputParameters.AddOutput("p", p);

                //  The pairwise contrasts are shown only when the overall test rejects at the level the parameter implies
                //  (it is given as a confidence level, 0.95 for a 5% test)
                double alphaLevel = confidence;
                if (alphaLevel == 0)
                    alphaLevel = 0.05;
                if (alphaLevel > 1 - alphaLevel)
                    alphaLevel = 1 - alphaLevel;
                if (p <= alphaLevel)
                {
                    IList<ParameterBag> pairwiseList = new List<ParameterBag>();
                    ParameterBag pairwiseParameters = new();
                    pairwiseList.Add(pairwiseParameters);
                    p = alphaLevel / 2;
                    df = nx - frame.VariableCount;
                    double tval = PDF.tfromp(p, df);
                    pairwiseParameters.AddOutput("df", df);
                    pairwiseParameters.AddOutput("t", tval);
                    IList<ParameterBag> pairList = new List<ParameterBag>();
                    pairwiseParameters.AddOutput("*pair", pairList);
                    for (int i = 0; i <= frame.VariableCount - 2; i++)
                    {
                        for (int j = i + 1; j < frame.VariableCount; j++)
                        {
                            double stata = Math.Abs(sj[i] / l[i] - sj[j] /l[j]);
                            double statq = Math.Sqrt(d2 * ((nx - 1.0 - t2) / (nx - frame.VariableCount))) * Math.Sqrt(1.0 / l[i] + 1.0 / l[j]);
                            double statb = tval * statq;
                            p = PDF.tvalp(Math.Abs(stata / statq), df);
                            if (p > 1.0 - p)
                                p = 1.0 - p;
                            ParameterBag pairParameters = new();
                            pairList.Add(pairParameters);
                            pairParameters.AddOutput("t1", frame.Variables[i].Title);
                            pairParameters.AddOutput("t2", frame.Variables[j].Title);
                            pairParameters.AddOutput("dif",
                                stata > statb
                                    ? "VARIANCES SEEM DIFFERENT"
                                    : "variances not different");
                            pairParameters.AddOutput("stata", stata);
                            pairParameters.AddOutput("statb", statb);
                            pairParameters.AddOutput("p_pair", 2.0 * p);
                        }
                    }
                    outputParameters.AddOutput("*pairwise", pairwiseList);
                }
                else
                {
                    outputParameters.AddOutput("*pairwise", null);
                }
            }
            else
            {
                int cnt = 0;
                double sbar = 0;
                double r4 = 0;
                double sj2N = 0;
                for (int d = 0; d < frame.VariableCount; d++)
                {
                    for (int n = 1; n <= l[d]; n++)
                    {
                        cnt += 1;
                        sj[d] = sj[d] + r[cnt] * r[cnt];
                        r4 += Math.Pow(r[cnt], 4.0);
                    }
                    sbar += sj[d];
                    if (d == 0)
                        ru = sj[d];
                    sj2N += sj[d] * sj[d] / l[d];
                }
                sbar /= nx;
                int nm = l[0] * l[1];
                double t1 = (ru - l[0] * sbar) / Math.Sqrt(Convert.ToDouble(nm) / Convert.ToDouble(nx * (nx - 1)) * r4 - nm / (nx - 1.0) * sbar * sbar);
                double z = t1;
                outputParameters.AddOutput("z", z);
                double p = 1.0 - PDF.alnorm(Math.Abs(z));
                if (p > 1 - p)
                    p = 1 - p;
                outputParameters.AddOutput("p2", p * 2);
                outputParameters.AddOutput("p1", p);
            }
            return new StepOutput(outputParameters);
        }

        public static StepOutput RptGini(IProgressBarHost host, ParameterBag parameters)
        {
            DataFrame dataFrame = parameters["data"].AsDataFrame;
            DataFrame weightsFrame = parameters.ContainsKey("weights") ? parameters["weights"].AsDataFrame : null;
            double gamma = parameters["gamma"].AsDouble;
            if (gamma <= 0)
                throw new TemplateOperationCancelledException();
            int boots = parameters["boots"].AsInt32;
            int bootsDivisor = Math.Max(1, boots / 1000);

            MathDbl.civ(0, out double cit, gamma, out double _);

            ParameterBag outputParameters = new();
            List<ParameterBag> outputList = new();
            outputParameters.AddOutput("*data", outputList);

            MersenneTwister rng = new(); // Seeds itself
            for (int k = 0; k < dataFrame.VariableCount; k++)
            {
                DoubleVariable v = (DoubleVariable)dataFrame.Variables[k];
                double[] weightsData;
                if (null == weightsFrame)
                {
                    // No weight data; weight everything equally
                    weightsData = new double[v.Length];
                    for (int i = 0; i < weightsData.Length; i++)
                        weightsData[i] = 1;
                }
                else
                {
                    weightsData = ((DoubleVariable)weightsFrame.Variables[k]).Data;
                }
                using IProgressBar progress = host.StartProgress("Bootstrapping Gini coefficient for " + v.Title, true);

                DoubleArraysAndBooleans copiesRemovingMissingRows = Numerics.Utilities.RemoveMissingRows(new[] { v.Data, weightsData, }, 0, v.Length, 0);
                double[] rawR = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[0];
                double[] w = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[1];
                // Only positive values are used, as the help says and as the report's count is labelled; zeros had been included
                // (and re-samples of zeros alone made the bootstrap 0 / 0). They are counted with the observations not used.
                int positive = 0;
                for (int i = 0; i < rawR.Length; i++)
                    if (rawR[i] > 0.0)
                        positive++;
                if (positive != rawR.Length)
                {
                    double[] rawPositive = new double[positive];
                    double[] wPositive = new double[positive];
                    int kept = 0;
                    for (int i = 0; i < rawR.Length; i++)
                    {
                        if (rawR[i] > 0.0)
                        {
                            rawPositive[kept] = rawR[i];
                            wPositive[kept] = w[i];
                            kept++;
                        }
                    }
                    rawR = rawPositive;
                    w = wPositive;
                }

                // Handle the weights by replicating each value the appropriate number of times.  This pre-calculates the required array length, then copies.
                double vtot = 0;
                int totalWeights = 0;
                for (int i = 0; i < rawR.Length; i++)
                {
                    vtot += rawR[i] * Math.Floor(w[i]);
                    totalWeights += (int)Math.Floor(w[i]);
                }
                double[] r = new double[totalWeights + 1];
                int nx = 0;
                for (int i = 0; i < rawR.Length; i++)
                    for (int repeats = 0; repeats < (int)Math.Floor(w[i]); repeats++)
                        r[++nx] = rawR[i];

                // By now, r contains the values, repeated the correct number of times.
                int rx = r.Length - 1;
                double vmean = vtot / rx;
                Array.Sort(r, 1, rx);

                double sumx = 0;
                double sumy = 0;
                double sumsqdev = 0;
                for (int j = 1; j <= rx; j++)
                {
                    // ascending order required
                    sumx += r[j];
                    sumy += (2 * j - rx - 1) * r[j];
                    sumsqdev += (r[j] - vmean) * (r[j] - vmean);
                }
                double gini = sumy / (rx * sumx);

                double drxm1 = rx - 1;
                double cv = Math.Sqrt(sumsqdev / drxm1) / vmean;

                double[] rb = new double[rx + 1];
                double[] ginib = new double[boots + 1];

                // get resample boots times
                double theta = 0.0;
                int ctr = 0;
                bool ok = true;
                int pick;
                for (int i = 1; i <= boots; i++)
                {
                    for (int j = 1; j <= rx; j++)
                    {
                        pick = Math.Min(rx, (int)Math.Floor(rx * rng.NextDouble()) + 1);
                        rb[j] = r[pick];
                    }
                    Array.Sort(rb, 1, rx);
                    sumx = 0.0;
                    sumy = 0.0;
                    for (int j = 1; j <= rx; j++)
                    { // ascending order required

                        sumx += rb[j];
                        sumy += (2 * j - rx - 1) * rb[j];
                    }
                    ginib[i] = sumy / (rx * sumx);
                    theta += ginib[i];
                    if (ginib[i] < gini)
                        ctr++;   //  for the bias correction: the re-sampled coefficients below the observed one, ties excluded
                    if (i % bootsDivisor == 0)
                    {
                        if (progress.Update(i / (double)boots))
                        {
                            ok = false;
                            break;
                        }
                    }
                }
                double bl;
                double bu;
                double thetase;
                double bias;
                double bcal;
                double bcau;
                string bcaNote = string.Empty;
                if (ok)
                {
                    // get bias and bootstrap variance
                    theta /= boots;
                    double thetasq = 0.0;
                    for (int i = 1; i <= boots; i++)
                        thetasq += Math.Pow(ginib[i] - theta, 2.0);
                    thetase = boots > 1 ? Math.Sqrt(thetasq / (boots - 1)) : Constant.MISSING;   //  a sum of squares: zero when every re-sample gives the same coefficient, which is not a fault
                    bias = gini - theta;
                    // sort bootstraps
                    Array.Sort(ginib, 1, boots);
                    double q = 1.0 - gamma > gamma ? 1.0 - gamma : gamma;
                    q = (1.0 - q) / 2.0;
                    // percentile
                    pick = Convert.ToInt32((boots - 1) * q) + 1;
                    bl = ginib[pick];
                    pick = Convert.ToInt32((boots - 1) * (1.0 - q)) + 1;
                    bu = ginib[pick];
                    // BCa: the acceleration from the jackknife (Efron and Tibshirani 1993, equation 14.15, as the help gives it). Each
                    // leave-one-out coefficient is calculated on the n - 1 remaining values with their own ranks; the original ranks
                    // and n had been kept, so those values were wrong, and the cubed differences had the opposite sign to the
                    // reference, which moved the BCa limits (0.443 to 0.671 for one sample of 20 where 0.484 to 0.711 is right).
                    double[] jack = new double[rx + 1];
                    double jackMean = 0.0;
                    for (int i = 1; i <= rx; i++)
                    {
                        sumx = 0.0;
                        sumy = 0.0;
                        int rank = 0;
                        for (int j = 1; j <= rx; j++)
                        {
                            if (j != i)
                            {
                                rank++;
                                sumx += r[j];
                                sumy += (2 * rank - rx) * r[j]; // 2 rank - (rx - 1) - 1
                            }
                        }
                        jack[i] = sumy / ((rx - 1) * sumx);
                        jackMean += jack[i];
                    }
                    jackMean /= rx;
                    double bgini2 = 0;
                    double bgini3 = 0;
                    for (int i = 1; i <= rx; i++)
                    {
                        bgini2 += Math.Pow(jackMean - jack[i], 2.0);
                        bgini3 += Math.Pow(jackMean - jack[i], 3.0);
                    }
                    double accel = bgini2 > 0.0 ? bgini3 / (6.0 * Math.Pow(bgini2, 1.5)) : 0.0;
                    double z0 = PDF.gauinv(ctr / (double)boots, out int z0Fault);
                    if (z0Fault != 0)
                    {
                        //  Every re-sampled coefficient is on one side of the observed one, so the bias correction is infinite and
                        //  the BCa interval is not defined (the fault had been ignored and zero used as the correction)
                        bcal = Constant.MISSING;
                        bcau = Constant.MISSING;
                        bcaNote = " (the BCa interval is not defined: no re-sampled coefficient lies below the observed coefficient, or every one does)";
                    }
                    else
                    {
                        double p1 = PDF.alnorm(z0 + (z0 - cit) / (1.0 - accel * (z0 - cit)));
                        double p2 = PDF.alnorm(z0 + (z0 + cit) / (1.0 - accel * (z0 + cit)));
                        pick = Convert.ToInt32(Convert.ToDouble(boots - 1) * p1) + 1;
                        bcal = ginib[pick];
                        pick = Convert.ToInt32(Convert.ToDouble(boots - 1) * p2) + 1;
                        bcau = ginib[pick];
                    }
                }
                else
                {
                    bl = Constant.MISSING;
                    bu = Constant.MISSING;
                    bcal = Constant.MISSING;
                    bcau = Constant.MISSING;
                    thetase = 0;
                    bias = 0;
                }

                ParameterBag varParameters = new();
                outputList.Add(varParameters);
                varParameters.AddOutput("ti", v.Title);
                varParameters.AddOutput("n", rx);
                if (rawR.Length != v.Length)
                    varParameters.AddOutput("msg", "(note " + (v.Length - rawR.Length) + " other observation(s) not used)" + bcaNote);
                else
                    varParameters.AddOutput("msg", bcaNote.TrimStart());
                varParameters.AddOutput("cv", cv);
                varParameters.AddOutput("boots", boots);
                varParameters.AddOutput("bias", bias);
                varParameters.AddOutput("se", thetase);

                varParameters.AddOutput("gini", gini);
                varParameters.AddOutput("pc", gamma * 100);
                varParameters.AddOutput("from", bl);
                varParameters.AddOutput("to", bu);
                varParameters.AddOutput("BCafrom", bcal);
                varParameters.AddOutput("BCato", bcau);

                double unbias = rx / (rx - 1.0);
                varParameters.AddOutput("gini-unbiased", gini * unbias);
                varParameters.AddOutput("from-unbiased", bl == Constant.MISSING ? Constant.MISSING : bl * unbias);
                varParameters.AddOutput("to-unbiased", bu == Constant.MISSING ? Constant.MISSING : bu * unbias);
                varParameters.AddOutput("BCafrom-unbiased", bcal == Constant.MISSING ? Constant.MISSING : bcal * unbias);
                varParameters.AddOutput("BCato-unbiased", bcau == Constant.MISSING ? Constant.MISSING : bcau * unbias);

                //  In the single-variable case, plot as well.  Only evaluate on the first time through, to prevent us removing placeholders multiple times!
                if (k == 0)
                {
                    if (dataFrame.VariableCount == 1)
                    {
                        double[] x = new double[rx];
                        double[] y = new double[rx];
                        double sum = 0.0;
                        for (int j = 1; j <= rx; j++)
                        {
                            sum += r[j];
                            x[j - 1] = j / (double)rx;
                        }
                        double runningTotal = 0.0;
                        for (int j = 1; j <= rx; j++)
                        {
                            runningTotal += r[j] / sum;
                            y[j - 1] = runningTotal;
                        }
                        outputParameters.AddOutput("X", new DataFrame(new DoubleVariable(x), dataFrame.Variables[0].Title));
                        outputParameters.AddOutput("Y", new DataFrame(new DoubleVariable(y), dataFrame.Variables[0].Title));
                    }
                    else
                    {
                        outputParameters.AddOutput("chart", null);
                    }
                }

            }
            return new StepOutput(outputParameters);
        }
    }
}
