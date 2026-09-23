using System;
using System.Collections.Generic;
using StatsDirect.Charting;
using StatsDirect.Data;
using StatsDirect.Numerics;
using StatsDirect.Templates;
using StatsDirect.Utilities;
using static StatsDirect.Builtins.ExactBB;

namespace StatsDirect.Builtins
{
    public static class Tables
    {
        private class Namevar
        {
            public string Title { get; set;  }
            public double X { get; set;  }

            public Namevar(string title, double x)
            {
                Title = title;
                X = x;
            }
        }

        /// <summary>
        /// If both sides are numeric, compare as numbers.  Otherwise, compare as text.
        /// </summary>
        private class NamevarAscending : IComparer<Namevar>
        {
            public int Compare(Namevar x, Namevar y)
            {
                if (double.TryParse(x.Title, out double nx) && double.TryParse(y.Title, out double ny))
                    return nx.CompareTo(ny);
                return string.CompareOrdinal(x.Title, y.Title);
            }
        }

        ///  <summary>
        ///  Sort data in cat[lowerBound..lowerBound+cats-1] by label
        ///  </summary>
        ///  <param name="cats"></param>
        ///  <param name="cat"></param>
        /// <param name="lowerBound"></param>
        /// <remarks></remarks>
        private static void SortName(int cats, Namevar[] cat, int lowerBound) => Array.Sort(cat, lowerBound, cats, new NamevarAscending());

        public static ParameterBag SFisher(ref int a, ref int b, ref int c, ref int d, ref int fault)
        {
            ParameterBag outputParameters = new();
            outputParameters.AddOutput("tab_a1", a);
            outputParameters.AddOutput("tab_b1", b);
            outputParameters.AddOutput("tab_a2", c);
            outputParameters.AddOutput("tab_b2", d);
            if (a > d)
                Utilities.Utilities.Swap(ref a, ref d);
            if (b > c)
                Utilities.Utilities.Swap(ref b, ref c);
            int p = a + b;
            int q = c + d;
            int r = a + c;
            int s = b + d;
            int n = p + q;
            if (p <= 0 || q <= 0 || r <= 0 || s <= 0)
                throw new InvalidDataException();

            outputParameters.AddOutput("tab3_a1", a);
            outputParameters.AddOutput("tab3_b1", b);
            outputParameters.AddOutput("tab3_c1", p);
            outputParameters.AddOutput("tab3_a2", c);
            outputParameters.AddOutput("tab3_b2", d);
            outputParameters.AddOutput("tab3_c2", q);
            outputParameters.AddOutput("tab3_a3", r);
            outputParameters.AddOutput("tab3_b3", s);
            outputParameters.AddOutput("tab3_c3", n);
            double b0 = 1.0;
            double n1 = n;
            double s1 = s;
            do
            {
                if (b0 > 1.0E+300 || s1 <= 0.0)
                {
                    fault = 1;
                    break;
                }
                b0 = b0 * n1 / s1;
                s1 -= 1.0;
                n1 -= 1.0;
            }
            while (n1 > Convert.ToDouble(q));
            double e1 = Convert.ToDouble(p * r) / Convert.ToDouble(n);
            outputParameters.AddOutput("exp_a", e1);
            if (fault != 0)
            {
                Fisherp(a, b, c, d, out double zPone, out double ptwo, out fault);
                outputParameters.AddOutput("tail_1", string.Empty);
                if (fault != 0)
                {
                    outputParameters.AddOutput("p_1", "err");
                    outputParameters.AddOutput("p_1d", "err");
                    outputParameters.AddOutput("tail_2", string.Empty);
                    outputParameters.AddOutput("p_2", "err");
                }
                else
                {
                    outputParameters.AddOutput("p_1", zPone);
                    outputParameters.AddOutput("p_1d", zPone * 2.0);
                    outputParameters.AddOutput("tail_2", string.Empty);
                    outputParameters.AddOutput("p_2", ptwo);
                }
                const string x = "not possible, use Monte Carlo";
                outputParameters.AddOutput("mid_p", x);
                outputParameters.AddOutput("mid_p_2", x);
            }
            else
            {
                double[] f1 = new double[p + 2];
                double[] g1 = new double[p + 2];
                double[] h1 = new double[p + 2];
                int a1 = 0;
                int q1 = q - r;
                int p1 = p;
                int r1 = r;
                double h = 1.0 / b0;
                double f = h;
                f1[1] = f;
                h1[1] = h;
                g1[1] = 1.0;
                int a2;
                do
                {
                    a1 += 1;
                    q1 += 1;
                    h = h * Convert.ToDouble(p1) / Convert.ToDouble(a1) * Convert.ToDouble(r1) / Convert.ToDouble(q1);
                    f += h;
                    a2 = a1 + 1;
                    f1[a2] = f;
                    h1[a2] = h;
                    p1 -= 1;
                    r1 -= 1;
                }
                while (p1 > 0);
                // UPPER TAIL PROBABILITIES WOULD BE SUBJECT TO SUBTRACTION ERRORS
                // IF CALCULATED BY 1 - F. THEREFORE:
                double g = 0.0;
                int j;
                for (j = a2; j >= 2; j--)
                {
                    g += h1[j];
                    g1[j] = g;
                }
                a1 = a + 1;
                h = 1.0000000000001 * h1[a1];
                double midP;
                if (a > e1)
                {
                    g = g1[a1];
                    f = 0.0;
                    for (j = 1; j <= a2; j++)
                    {
                        if (h1[j] > h)
                            break;
                        f = f1[j];
                    }
                    double g2 = g * 2.0;
                    if (g2 > 1.0)
                        g2 = 1.0;
                    outputParameters.AddOutput("tail_1", "(upper tail)");
                    outputParameters.AddOutput("p_1", g);
                    outputParameters.AddOutput("p_1d", g2);
                    midP = g - h1[a1] / 2.0;
                }
                else
                {
                    f = f1[a1];
                    g = 0.0;
                    for (j = a2; j >= 1; j--)
                    {
                        if (h1[j] > h)
                            break;
                        g = g1[j];
                    }
                    double f2 = 2.0 * f;
                    if (f2 > 1.0)
                        f2 = 1.0;
                    outputParameters.AddOutput("tail_1", "(lower tail)");
                    outputParameters.AddOutput("p_1", f);
                    outputParameters.AddOutput("p_1d", f2);
                    midP = f - h1[a1] / 2.0;
                }
                double z = f + g;
                if (z > 1.0)
                    z = 1.0;
                outputParameters.AddOutput("tail_2", "(by summation)");
                outputParameters.AddOutput("p_2", z);
                outputParameters.AddOutput("mid_p", midP);
                outputParameters.AddOutput("mid_p_2", Math.Min(midP * 2.0, 1.0));
            }
            fault = 0;
            return outputParameters;
        }

        ///  <summary>
        ///  
        ///  </summary>
        ///  <param name="frame">One classifier variable per rater, one row of data per subject.</param>
        ///  <param name="poscat"></param>
        ///  <param name="k"></param>
        ///  <param name="mbar"></param>
        ///  <param name="mbarh"></param>
        ///  <param name="pbar"></param>
        ///  <param name="minm"></param>
        ///  <param name="maxm"></param>
        ///  <param name="medm"></param>
        ///  <remarks></remarks>
        private static void KappaHat(DataFrame frame, string poscat, out double k, out double mbar, out double mbarh, out double pbar, out double minm, out double maxm, out double medm, out double nRated)
        {
            int n = frame.Variables[0].Length;
            double[] qm = new double[n];
            double[] qx = new double[n];
            //  IEB Aug 2007: Corrected to allow for complete non-rating of a subject
            for (int i = 0; i < n; i++)
            {
                for (int j = 0; j < frame.VariableCount; j++)
                {
                    ClassifierVariable v = (ClassifierVariable)frame.Variables[j];
                    //  Find the first missing label
                    int m;
                    for (m = 0; m < v.GroupCount; m++)
                        if (v.Groups[m].Label == Formatting.MISSINGLABEL)
                            break;
                    if (v.Data[i] != Convert.ToDouble(m) && v.Data[i] != Constant.MISSING)
                        qm[i] += 1.0;
                    for (m = 0; m < v.GroupCount; m++)
                        if (v.Groups[m].Label == poscat)
                            break;
                    if (v.Data[i] == Convert.ToDouble(m) && v.Data[i] != Constant.MISSING)
                        qx[i] += 1.0;
                }
            }
            mbar = 0.0;
            mbarh = 0.0;
            double xn = 0;
            minm = double.MaxValue;
            maxm = double.MinValue;
            for (int i = 0; i < n; i++)
            {
                mbar += qm[i];
                if (qm[i] != 0.0)
                {
                    mbarh += 1.0 / qm[i];
                    xn += 1;
                }
                if (qm[i] != 0.0 && qm[i] < minm)
                    minm = qm[i];
                if (qm[i] > maxm)
                    maxm = qm[i];
            }
            medm = Describe.Median(qm, 0, n - 1);
            nRated = xn;
            mbar /= xn;
            mbarh = xn / mbarh;
            pbar = 0.0;
            for (int i = 0; i < n; i++)
                pbar += qx[i];
            pbar /= (xn * mbar);
            double bx = 0.0;
            double wx = 0.0;
            for (int i = 0; i < n; i++)
            {
                if (qm[i] != 0)
                {
                    bx += Math.Pow(qx[i] - qm[i] * pbar, 2.0) / qm[i];
                    wx += qx[i] * (qm[i] - qx[i]) / qm[i];
                }
            }
            bx /= xn;
            wx /= (xn * (mbar - 1.0));
            k = (bx - wx) / (bx + (mbar - 1.0) * wx);
        }

        private static void XSymmetriseXtab(ref int xcats, ref Namevar[] xcat, ref int ycats, ref Namevar[] ycat, int lowerBound)
        {
            Namevar[] maxcat = new Namevar[xcats + ycats + lowerBound];
            // fill in the gaps if non-contiguous series - 12/02/05 --->
            for (int i = lowerBound; i < xcats + lowerBound; i++)
                maxcat[i] = new Namevar(xcat[i].Title, xcat[i].X); // AUDIT FIX: copy, do not alias
            for (int i = lowerBound; i < ycats + lowerBound; i++)
                maxcat[xcats + i] = new Namevar(ycat[i].Title, ycat[i].X); // AUDIT FIX
            SortName(xcats + ycats, maxcat, lowerBound);
            for (int i = lowerBound + 1; i < xcats + ycats + lowerBound; i++)
                if (maxcat[i - 1].Title == maxcat[i].Title)
                    maxcat[i - 1].Title = string.Empty;
            SortName(xcats + ycats, maxcat, lowerBound);
            int g = 1;
            for (int i = xcats + ycats - 1 + lowerBound; i >= lowerBound; i--)
            {
                if (string.IsNullOrEmpty(maxcat[i].Title))
                {
                    g = i + 1;
                    break;
                }
            }
            int maxcats = xcats + ycats - g + lowerBound;
            // create temp variable for copying values 
            Namevar[] newXcat = new Namevar[maxcats + lowerBound];
            Array.Copy(xcat, newXcat, Math.Min(xcat.Length, newXcat.Length));
            xcat = newXcat;
            // create temp variable for copying values 
            Namevar[] newYcat = new Namevar[maxcats + lowerBound];
            Array.Copy(ycat, newYcat, Math.Min(ycat.Length, newYcat.Length));
            ycat = newYcat;
            for (int i = lowerBound; i < maxcats + lowerBound; i++)
            {
                if (xcat[i].Title != maxcat[g + i - lowerBound].Title)
                {
                    //  Shuffle the end of the array up
                    for (int j = maxcats - 2 + lowerBound; j >= i; j--)
                        xcat[j + 1] = xcat[j];
                    xcat[i] = new Namevar(maxcat[g + i - lowerBound].Title, -Constant.MISSING); // AUDIT FIX: new entry, not a shared object
                }
                if (ycat[i].Title != maxcat[g + i - lowerBound].Title)
                {
                    for (int j = maxcats - 2 + lowerBound; j >= i; j--)
                        ycat[j + 1] = ycat[j];
                    ycat[i] = new Namevar(maxcat[g + i - lowerBound].Title, -Constant.MISSING); // AUDIT FIX
                }
            }
            xcats = maxcats;
            ycats = maxcats;
        }

        public static void XKappaCI22(int n1, int n2, int n3, double z, out double ka, out double lwr, out double upr, out int fault)
        {
            //       This program calculates a Donner-Eliasziw goodness-of-fit
            //       CI for Scott-Cohen pi/kappa for one or more 2*2 tables.
            //       95% by default, else change z.

            //       Input:  3i6  n1 (1,1)
            //                    n2 (1,0) or (0,1)
            //                    n3(0, 0)
            // 
            //       Limitations:  data not accepted if n1+n2 or n2+n3 zero.
            // 
            //       Output:  point estimate and CI by closed form solution of cubic.
            //       If n2=0 and hence kappa=1, also give quadratic solution.
            fault = 2;
            double zsq = z * z;
            if (n1 + n2 == 0 || n2 + n3 == 0)
            {
                ka = Constant.MISSING;
                lwr = Constant.MISSING;
                upr = Constant.MISSING;
                return;
            }
            double a1 = Convert.ToDouble(n1);
            double a2 = Convert.ToDouble(n2);
            double a3 = Convert.ToDouble(n3);
            double an = a1 + a2 + a3;
            double p = (a1 + 0.5 * a2) / an;
            double pq = p * (1.0 - p);
            ka = 1.0 - a2 / (2.0 * an * pq);
            double den = pq * (zsq + an);
            double y3 = (a2 + (1.0 - 2.0 * pq) * zsq) / den - 1.0;
            den = 4.0 * an * pq * den;
            double y2 = (a2 * a2 - 4.0 * an * pq * (1.0 - 4.0 * pq) * zsq) / den - 1.0;
            double y1 = (Math.Pow(a2 - 2.0 * an * pq, 2.0) + 4.0 * an * an * pq * pq) / den - 1.0;
            double vv = Math.Pow(y3, 3.0) / 27.0 - (y2 * y3 - 3.0 * y1) / 6.0;
            double w = Math.Pow(y3, 2.0) / 9.0 - y2 / 3.0;
            w = Math.Pow(w, 1.5);
            double th = Math.Acos(vv / w);
            double th120 = (th + 2.0 * Constant.PI) / 3.0;
            double th300 = (th + 5.0 * Constant.PI) / 3.0;
            double b = Math.Pow(y3, 2.0) / 9.0 - y2 / 3.0;
            b = Math.Pow(b, 0.5);
            lwr = b * (Math.Cos(th120) + Math.Pow(3.0, 0.5) * Math.Sin(th120)) - y3 / 3.0;
            upr = 2.0 * b * Math.Cos(th300) - y3 / 3.0;
            if (n2 == 0)
            {
                upr = 1.0;
                double a = zsq * (Math.Pow(p, 2.0) + Math.Pow(1.0 - p, 2.0)) / pq;
                lwr = (-a + Math.Pow(Math.Pow(a, 2.0) - 4.0 * (zsq + an) * (zsq - an), 0.5)) / (2.0 * (zsq + an));
            }
            fault = 0;
        }

        /// <summary>
        /// Categorical agreement statistics for the case of two raters: Cohen's kappa, weighted kappa, Scott's Pi and Gwett's AC1
        /// </summary>
        /// <param name="o">(0..g-1, 0..g-1)-based array of values</param>
        /// <param name="w">(0..g-1, 0..g-1)-based array of weights</param>
        /// <param name="g">number of observations per rater</param>
        /// <param name="k">Cohen's kappa</param>
        /// <param name="sek">Standard error of kappa</param>
        /// <param name="sekci"></param>
        /// <param name="kcil">Lower confidence bound for kappa</param>
        /// <param name="kciu">Upper confidence bound for kappa</param>
        /// <param name="kw">Weighted kappa</param>
        /// <param name="sekw">Standard error of weighted kappa</param>
        /// <param name="sekwci"></param>
        /// <param name="kwcil">Lower confidence bound for weighted kappa</param>
        /// <param name="kwciu">Upper confidence bound for weighted kappa</param>
        /// <param name="po">Observed agreement for kappa</param>
        /// <param name="pe">Expected agreement for kappa</param>
        /// <param name="pow">Observed agreement for weighted kappa</param>
        /// <param name="pew">Expected agreement for weighted kappa</param>
        /// <param name="cit">Confidence level</param>
        /// <param name="spe">Expected agreement for Scott's Pi</param>
        /// <param name="spi">Scott's Pi</param>
        /// <param name="gama">Gwett's AC1</param>
        /// <param name="segama">Standard error of AC1</param>
        /// <param name="gamacil">Lower confidence bound for AC1</param>
        /// <param name="gamaciu">Upper confidence bound for AC1</param>
        /// <param name="pegama">Chance-independent agreement for Gwett's AC1</param>
        /// <param name="ierror"></param>
        /// <remarks>The double version</remarks>
        public static void Kappa(double[,] o, double[,] w, int g, out double k, out double sek, out double sekci, out double kcil, out double kciu, out double kw, out double sekw, out double sekwci, out double kwcil, out double kwciu, out double po, out double pe, out double pow, out double pew, double cit, out double spe, out double spi, out double gama, out double segama, out double gamacil, out double gamaciu, out double pegama, out bool ierror)
        {
            ierror = true;
            double[] pidot = new double[g];
            double[] pdotj = new double[g];
            double[] crtot = new double[g];
            double gt = 0.0;
            for (int i = 0; i < g; i++)
            {
                for (int j = 0; j < g; j++)
                {
                    pdotj[i] += o[i, j];
                    pidot[j] += o[i, j];
                    gt += o[i, j];
                }
            }
            for (int i = 0; i < g; i++)
                crtot[i] += pdotj[i] + pidot[i];
            if (gt <= 0.0)
                throw new InvalidDataException();

            //unweighted kappa
            po = 0.0;
            pe = 0.0;
            double px = 0.0;
            double pog = 0.0;
            double peg = 0.0;
            for (int i = 0; i < g; i++)
            {
                pdotj[i] = pdotj[i] / gt;
                pidot[i] = pidot[i] / gt;
                po += o[i, i] / gt;
                pe += pdotj[i] * pidot[i];
                px += pdotj[i] * pidot[i] * (pdotj[i] + pidot[i]);
                double pik = (pdotj[i] + pidot[i]) / 2.0;
                pog += o[i, i] / gt * (1.0 - pik);
                peg += pik * (1.0 - pik);
            }
            pegama = peg / (g - 1.0);
            gama = (po - pegama) / (1.0 - pegama);
            // gama is Gwett's AC1 statistic and pegama is the chance-independent agreement with po as the observed agreement
            k = (po - pe) / (1.0 - pe);
            // standard error for the z test
            sek = 1.0 / ((1.0 - pe) * Math.Sqrt(gt)) * Math.Sqrt(pe + pe * pe - px);
            // standard error for the confidence interval: after Fleiss, Cohen and Everitt 1969
            double sumpa = 0.0;
            double sumpb = 0.0;
            for (int i = 0; i < g; i++)
                sumpa += o[i, i] / gt * Math.Pow(1.0 - pe - (pdotj[i] + pidot[i]) * (1.0 - po), 2.0);
            for (int i = 0; i < g; i++)
                for (int j = 0; j < g; j++)
                    if (i != j)
                        sumpb += o[i, j] / gt * Math.Pow(pdotj[j] + pidot[i], 2.0);
            sekci = (sumpa + Math.Pow(1.0 - po, 2.0) * sumpb - Math.Pow(po * pe - 2.0 * pe + po, 2.0)) / (gt * Math.Pow(1.0 - pe, 4.0));
            sekci = Math.Sqrt(sekci);
            kcil = k - cit * sekci;
            if (kcil < -1.0)
                kcil = -1.0;
            kciu = k + cit * sekci;
            if (kciu > 1.0)
                kciu = 1.0;

            //weighted kappa
            pow = 0.0;
            pew = 0.0;
            double soma = 0.0;
            for (int i = 0; i < g; i++)
            {
                for (int j = 0; j < g; j++)
                {
                    double pkl = o[i, j] / gt;
                    pow += w[i, j] * pkl;
                    pew += w[i, j] * pidot[i] * pdotj[j];
                    soma += pkl * Math.Pow(1.0 - ((pdotj[i] + pidot[i]) / 2.0 + (pdotj[j] + pidot[j]) / 2.0) / 2.0, 2.0);
                }
            }
            kw = (pow - pew) / (1.0 - pew);
            sekw = 1.0 / ((1.0 - pew) * Math.Sqrt(gt));
            double f = 0.0;
            // set f to gt/population size if population size is known, otherwise assume an infinite inference population thus f = 0
            double vgama = (1.0 - f) / (gt * Math.Pow(1.0 - pegama, 2.0)) * (po * (1.0 - po) - 4.0 * (1.0 - gama) * (1.0 / (g - 1.0) * pog - po * pegama) + 4.0 * Math.Pow(1.0 - gama, 2.0) * (1.0 / Math.Pow(g - 1.0, 2.0) * soma - Math.Pow(pegama, 2.0)));
            segama = Math.Sqrt(vgama);
            gamacil = gama - cit * segama;
            gamaciu = gama + cit * segama;
            // vgamma is the variance of Gwett's AC1 statistic and epgamma its standard error
            double[] wibar = new double[g];
            double[] wjbar = new double[g];
            for (int i = 0; i < g; i++)
            {
                for (int j = 0; j < g; j++)
                {
                    wibar[i] += w[i, j] * pdotj[j];
                    wjbar[j] += w[i, j] * pidot[i];
                }
            }
            px = 0.0;
            for (int i = 0; i < g; i++)
                for (int j = 0; j < g; j++)
                    px += pidot[i] * pdotj[j] * Math.Pow(w[i, j] - (wibar[i] + wjbar[j]), 2.0);

            // standard error for z test
            sekw *= Math.Sqrt(px - Math.Pow(pew, 2.0));
            // standard error for confidence interval after Fleiss, Cohen and Everitt 1969
            double sumpw = 0.0;
            for (int i = 0; i < g; i++)
                for (int j = 0; j < g; j++)
                    sumpw += o[i, j] / gt * Math.Pow(w[i, j] * (1.0 - pew) - (wibar[j] + wjbar[i]) * (1.0 - pow), 2.0);
            sekwci = (sumpw - Math.Pow(pow * pew - 2.0 * pew + pow, 2.0)) / (gt * Math.Pow(1.0 - pew, 4.0));
            sekwci = Math.Sqrt(sekwci);
            kwcil = kw - cit * sekwci;
            if (kwcil < -1.0) kwcil = -1.0;
            kwciu = kw + cit * sekwci;
            if (kwciu > 1.0) kwciu = 1.0;

            // Scott's pi
            spe = 0.0;
            for (int i = 0; i < g; i++)
                spe += Math.Pow(crtot[i] / (gt * 2.0), 2.0);
            spi = (po - spe) / (1.0 - spe);
            ierror = false;
        }

        ///  <summary>
        ///  
        ///  </summary>
        /// <param name="host"></param>
        /// <param name="o">(0..g-1, 0..g-1)-based array of values</param>
        ///  <param name="w">(0..g-1, 0..g-1)-based array of weights</param>
        ///  <param name="g"></param>
        ///  <param name="k"></param>
        ///  <param name="sek"></param>
        /// <param name="sekci"></param>
        /// <param name="kcil"></param>
        ///  <param name="kciu"></param>
        ///  <param name="kw"></param>
        ///  <param name="sekw"></param>
        /// <param name="sekwci"></param>
        /// <param name="kwcil"></param>
        ///  <param name="kwciu"></param>
        ///  <param name="po"></param>
        ///  <param name="pe"></param>
        ///  <param name="pow"></param>
        ///  <param name="pew"></param>
        ///  <param name="cit"></param>
        ///  <param name="spe"></param>
        ///  <param name="spi"></param>
        ///  <param name="ierror"></param>
        ///  <remarks>The integer version</remarks>
        public static void Kappa(int[,] o, double[,] w, int g, ref double k, ref double sek, ref double sekci, ref double kcil, ref double kciu, ref double kw, ref double sekw, ref double sekwci, ref double kwcil, ref double kwciu, ref double po, ref double pe, ref double pow, ref double pew, ref double cit, ref double spe, ref double spi, out bool ierror)
        {
            // two rater kappa
            ierror = true;
            // get row and column totals
            double[] pidot = new double[g];
            double[] pdotj = new double[g];
            double[] crtot = new double[g];
            double gt = 0.0;
            for (int i = 0; i < g; i++)
            {
                for (int j = 0; j < g; j++)
                {
                    pdotj[i] += o[i, j];
                    pidot[j] += o[i, j];
                    gt += o[i, j];
                }
            }
            for (int i = 0; i < g; i++)
                crtot[i] += pdotj[i] + pidot[i];
            if (gt <= 0.0)
                throw new InvalidDataException();

            // unweighted kappa
            po = 0.0;
            pe = 0.0;
            double px = 0.0;
            for (int i = 0; i < g; i++)
            {
                pdotj[i] /= gt;
                pidot[i] /= gt;
                po += o[i, i] / gt;
                pe += pdotj[i] * pidot[i];
                px += pdotj[i] * pidot[i] * (pdotj[i] + pidot[i]);
            }
            k = (po - pe) / (1.0 - pe);
            // standard error for the z test
            sek = 1.0 / ((1.0 - pe) * Math.Sqrt(gt)) * Math.Sqrt(pe + pe * pe - px);
            // standard error for the confidence interval: after Fleiss, Cohen and Everitt 1969
            double sumpa = 0.0;
            double sumpb = 0.0;
            for (int i = 0; i < g; i++)
                sumpa += o[i, i] / gt * Math.Pow(1.0 - pe - (pdotj[i] + pidot[i]) * (1.0 - po), 2.0);
            for (int i = 0; i < g; i++)
                for (int j = 0; j < g; j++)
                    if (i != j)
                        sumpb += o[i, j] / gt * Math.Pow(pdotj[j] + pidot[i], 2.0);
            sekci = (sumpa + Math.Pow(1.0 - po, 2.0) * sumpb - Math.Pow(po * pe - 2.0 * pe + po, 2.0)) / (gt * Math.Pow(1.0 - pe, 4.0));
            sekci = Math.Sqrt(sekci);
            kcil = k - cit * sekci;
            if (kcil < -1.0) kcil = -1.0;
            kciu = k + cit * sekci;
            if (kciu > 1.0) kciu = 1.0;

            //weighted kappa
            pow = 0.0;
            pew = 0.0;
            for (int i = 0; i < g; i++)
            {
                for (int j = 0; j < g; j++)
                {
                    pow += w[i, j] * (o[i, j] / gt);
                    pew += w[i, j] * pidot[i] * pdotj[j];
                }
            }
            kw = (pow - pew) / (1.0 - pew);
            sekw = 1.0 / ((1.0 - pew) * Math.Sqrt(gt));
            double[] wibar = new double[g];
            double[] wjbar = new double[g];
            for (int i = 0; i < g; i++)
            {
                for (int j = 0; j < g; j++)
                {
                    wibar[i] += w[i, j] * pdotj[j];
                    wjbar[j] += w[i, j] * pidot[i];
                }
            }
            px = 0.0;
            for (int i = 0; i < g; i++)
                for (int j = 0; j < g; j++)
                    px += pidot[i] * pdotj[j] * Math.Pow(w[i, j] - (wibar[i] + wjbar[j]), 2.0);

            //standard error for the z test
            sekw *= Math.Sqrt(px - Math.Pow(pew, 2.0));
            // standard error for confidence interval after Fleiss, Cohen and Everitt 1969
            double sumpw = 0.0;
            for (int i = 0; i < g; i++)
                for (int j = 0; j < g; j++)
                    sumpw += o[i, j] / gt * Math.Pow(w[i, j] * (1.0 - pew) - (wibar[j] + wjbar[i]) * (1.0 - pow), 2.0);
            sekwci = (sumpw - Math.Pow(pow * pew - 2.0 * pew + pow, 2.0)) / (gt * Math.Pow(1.0 - pew, 4.0));
            sekwci = Math.Sqrt(sekwci);
            kwcil = kw - cit * sekwci;
            if (kwcil < -1.0) kwcil = -1.0;
            kwciu = kw + cit * sekwci;
            if (kwciu > 1.0) kwciu = 1.0;

            // Scott's pi
            spe = 0.0;
            for (int i = 0; i < g; i++)
                spe += Math.Pow(crtot[i] / (gt * 2.0), 2.0);
            spi = (po - spe) / (1.0 - spe);
            ierror = false;
        }

        ///  <param name="o">Zero-based array of values,dimensions (0..k-1, 0..k-1)</param>
        ///  <remarks>Maxwell AE. Comparing the classification of subjects by two independent judges. British Journal of Psychiatry 1970;116:651-655.</remarks>
        public static void Maxwell(double[,] o, int k, out double x2, out double x2M, out int dfm)
        {
            int i; int j; int ifault = 0;

            double[] rtot = new double[k];
            double[] ctot = new double[k];
            double[] d = new double[k];
            double[,] v = new double[k, k];
            double[,] z = new double[k, k];
            //  get row and column totals and delta vector
            for (i = 0; i < k; i++)
            {
                for (j = 0; j < k; j++)
                {
                    rtot[i] += o[i, j];
                    ctot[j] += o[i, j];
                }
            }
            for (i = 0; i < k; i++)
            {
                d[i] = rtot[i] - ctot[i];
            }
            //  get variance/covariance matrix and invert it
            for (i = 0; i < k; i++)
            {
                for (j = 0; j < k; j++)
                {
                    if (i == j)
                        v[i, i] = rtot[i] + ctot[i] - 2.0 * o[i, i];
                    else
                        v[j, i] = -(o[j, i] + o[i, j]);
                }
            }
            MathDbl.gaussj(v, 0, k - 1, z, 1, ref ifault);
            if (ifault != 0)
            {
                x2 = Constant.MISSING;
            }
            else
            {
                x2 = 0;
                //  cumulate the chi-square statistic
                for (i = 0; i <= k - 2; i++)
                    for (j = 0; j <= k - 2; j++)
                        x2 += v[i, j] * d[i] * d[j];
            }
            // general McNemar
            dfm = (int)Math.Floor(k / 2.0 * (k - 1));
            x2M = 0;
            for (i = 0; i <= k - 2; i++)
            {
                for (j = i + 1; j < k; j++)
                {
                    if (o[i, j] + o[j, i] > 0.0)
                    {
                        x2M += (o[i, j] - o[j, i]) * (o[i, j] - o[j, i]) / (o[i, j] + o[j, i]);
                        //   Else
                        //    x2m = MISSING
                        //    Exit sub
                    }
                }
            }
        }

        public static StepOutput RptKappa(IPreferences host, ParameterBag parameters)
        {
            double cco = parameters["ci"].AsDouble;
            double cit; double p;
            if (cco > 0)
            {
                p = (1.0 - cco) / 2.0;
                cit = PDF.gauinv(1.0 - p);
            }
            else
            {
                cco = 0.95;
                cit = PDF.gauinv(0.975);
            }

            DataFrame frame = parameters["responses"].AsDataFrame;
            int raters = frame.VariableCount;

            // ieb june05 update to exclude missing data categories
            // do crosstabs if two raters --->
            if (raters == 2)
            {
                ClassifierVariable v0 = (ClassifierVariable)frame.Variables[0];
                int n = v0.Length;
                int ycats = 0;
                double[] y = new double[n];
                Namevar[] ycat = new Namevar[v0.GroupCount];
                string ylab = v0.Title;
                for (int i = 0; i < v0.GroupCount; i++)
                {
                    if (v0.Groups[i].Label != Formatting.MISSINGLABEL)
                    {
                        ycat[ycats] = new Namevar(v0.Groups[i].Label, i);
                        ycats += 1;
                    }
                }
                // create temp variable for copying values 
                Namevar[] transTemp16 = new Namevar[ycats];
                Array.Copy(ycat, transTemp16, Math.Min(ycat.Length, transTemp16.Length));
                ycat = transTemp16;
                for (int i = 0; i < n; i++)
                    y[i] = v0.Data[i];
                SortName(ycats, ycat, 0);
                ClassifierVariable v1 = (ClassifierVariable)frame.Variables[1];
                int xcats = 0;
                double[] x = new double[n];
                Namevar[] xcat = new Namevar[v1.GroupCount];
                string xlab = v1.Title;
                for (int i = 0; i < v1.GroupCount; i++)
                {
                    if (v1.Groups[i].Label != Formatting.MISSINGLABEL)
                    {
                        xcat[xcats] = new Namevar(v1.Groups[i].Label, i);
                        xcats++;
                    }
                }
                // create temp variable for copying values 
                Namevar[] transTemp17 = new Namevar[xcats];
                Array.Copy(xcat, transTemp17, Math.Min(xcat.Length, xcats));
                xcat = transTemp17;
                for (int i = 0; i < n; i++)
                    x[i] = v1.Data[i];
                SortName(xcats, xcat, 0);
                XSymmetriseXtab(ref xcats, ref xcat, ref ycats, ref ycat, 0);

                double[,] xt = new double[xcats, ycats];
                for (int i = 0; i < xcats; i++)
                    for (int j = 0; j < ycats; j++)
                        for (int kv = 0; kv < n; kv++)
                            if (x[kv] == xcat[i].X && y[kv] == ycat[j].X)
                                xt[i, j] += 1;

                int g = Math.Max(xcats, ycats);
                double[,] o = new double[g, g];
                double[,] w = new double[g, g];
                for (int i = 0; i < g; i++)
                {
                    for (int j = 0; j < g; j++)
                    {
                        o[i, j] = 0.0;
                        w[i, j] = 0.0;
                    }
                }
                for (int i = 0; i < ycats; i++)
                    for (int j = 0; j < xcats; j++)
                        o[i, j] = xt[j, i];
                // <------- xtab

                //  xt, o and w are now zero-based, were 1-based.

                // weights --->
                int wtype = Parsing.Cint_Txt(parameters["method"].AsString);
                if (wtype == 3)
                {
                    DataFrame weights = parameters["weights"].AsDataFrame;
                    for (int i = 0; i < weights.VariableCount; i++)
                    {
                        DoubleVariable v = (DoubleVariable)weights.Variables[i];
                        for (int j = 0; j < v.Length; j++)
                        {
                            w[i, j] = v.Data[j];
                            if (w[i, j] == Constant.MISSING)
                                w[i, j] = 0.0;
                        }
                    }
                }
                // ---> write crosstab if 2 raters
                ParameterBag outputParameters = new();
                outputParameters.AddOutput("ylab", ylab);
                outputParameters.AddOutput("xlab", xlab);
                ICollection<ParameterBag> xList = new List<ParameterBag>();
                for (int i = 0; i < xcats; i++)
                {
                    ParameterBag xValues = new();
                    xValues.AddOutput("x", xcat[i].Title);
                    xList.Add(xValues);
                }
                outputParameters.AddOutput("*x", xList);
                ICollection<ParameterBag> yList = new List<ParameterBag>();
                for (int i = 0; i < ycats; i++)
                {
                    ParameterBag yValues = new();
                    yValues.AddOutput("y", ycat[i].Title);
                    ICollection<ParameterBag> totList = new List<ParameterBag>();
                    for (int j = 0; j < xcats; j++)
                    {
                        ParameterBag totValues = new();
                        totValues.AddOutput("tot", xt[j, i]);
                        totList.Add(totValues);
                    }
                    yValues.AddOutput("*tot", totList);
                    yList.Add(yValues);
                }
                outputParameters.AddOutput("*y", yList);
                // <--- xtab
                if (wtype != 3)
                {
                    for (int i = 0; i < g; i++)
                    {
                        for (int j = 0; j < g; j++)
                        {
                            switch (wtype)
                            {
                                case 2:
                                    w[i, j] = 1.0 - Math.Pow(Convert.ToDouble(i - j) / Convert.ToDouble(g - 1), 2.0);
                                    break;
                                default:
                                    w[i, j] = 1.0 - Convert.ToDouble(Math.Abs(i - j)) / Convert.ToDouble(g - 1);
                                    break;
                            }

                        }
                    }
                }
                Kappa(o, w, g, out double k, out double sek, out double sekci, out double kcil, out double kciu, out double kw, out double sekw, out double sekwci, out double kwcil, out double kwciu, out double po, out double pe, out double pow, out double pew, cit, out double spe, out double spi, out double gama, out double segama, out double gamacil, out double gamaciu, out double pegama, out bool ierror);
                if (!ierror)
                {
                    outputParameters.AddOutput("po", po * 100);
                    outputParameters.AddOutput("pe", pe * 100);
                    outputParameters.AddOutput("kappa", k);
                    outputParameters.AddInput("kDouble", k);
                    outputParameters.AddOutput("se", sek);
                    outputParameters.AddOutput("seci", sekci);
                    outputParameters.AddOutput("pc", cco * 100);
                    outputParameters.AddOutput("from", kcil);
                    outputParameters.AddOutput("to", kciu);
                    outputParameters.AddOutput("z", 0.0 == sek ? 0 : k / sek);
                    if (sek != 0.0)
                        p = 1.0 - PDF.alnorm(k / sek);
                    else
                        p = Constant.MISSING;
                    outputParameters.AddOutput("p", p);

                    switch (wtype)
                    {
                        case 3:
                            outputParameters.AddOutput("methodName", "user defined");
                            break;
                        case 2:
                            outputParameters.AddOutput("methodName", "1-[(i-j)/(1-k)]?");
                            break;
                        default:
                            outputParameters.AddOutput("methodName", "1-abs(i-j)/(1-k)");
                            break;
                    }

                    ICollection<ParameterBag> weightList = new List<ParameterBag>();
                    for (int i = 0; i < ycats; i++)
                    {
                        ParameterBag weightValues = new();
                        ICollection<ParameterBag> totList = new List<ParameterBag>();
                        for (int j = 0; j < xcats; j++)
                        {
                            ParameterBag totValues = new();
                            totValues.AddOutput("tot", w[i, j]);
                            totList.Add(totValues);
                        }
                        weightValues.AddOutput("*tot", totList);
                        weightList.Add(weightValues);
                    }
                    outputParameters.AddOutput("*weights", weightList);
                    outputParameters.AddOutput("pow", pow * 100);
                    outputParameters.AddOutput("pew", pew * 100);
                    outputParameters.AddOutput("kappaw", kw);
                    outputParameters.AddInput("kwDouble", kw);
                    outputParameters.AddOutput("sekw", sekw);
                    outputParameters.AddOutput("sekwci", sekwci);
                    outputParameters.AddOutput("pcw", cco * 100);
                    outputParameters.AddOutput("fromw", kwcil);
                    outputParameters.AddOutput("tow", kwciu);
                    outputParameters.AddOutput("zw", 0.0 == sekw ? 0 : kw / sekw);
                    p = sekw != 0.0
                        ? 1.0 - PDF.alnorm(kw / sekw)
                        : Constant.MISSING;
                    outputParameters.AddOutput("pw", p);
                    outputParameters.AddOutput("spe", spe * 100);
                    outputParameters.AddOutput("spi", spi);

                    if (g == 2)
                    {
                        XKappaCI22(Convert.ToInt32(o[0, 0]), Convert.ToInt32(o[0, 1] + o[1, 0]), Convert.ToInt32(o[1, 1]), cit, out double _, out double lwr, out double upr, out int fault);
                        if (fault == 0)
                        {
                            ICollection<ParameterBag> deciList = new List<ParameterBag>();
                            ParameterBag deciValues = new();
                            deciValues.AddOutput("pc", cco * 100.0);
                            deciValues.AddOutput("lwr", lwr);
                            deciValues.AddOutput("upr", upr);
                            deciList.Add(deciValues);
                            outputParameters.AddOutput("*deci", deciList);
                        }
                        else
                        {
                            outputParameters.AddOutput("*deci", null);
                        }
                    }
                    else
                    {
                        outputParameters.AddOutput("deci", null);
                    }

                    // Maxwell's test
                    Maxwell(o, g, out double x2, out double x2M, out int dfm);
                    if (x2 == Constant.MISSING)
                    {
                        outputParameters.AddOutput("x2", x2);
                        outputParameters.AddOutput("df", x2);
                        outputParameters.AddOutput("pmaxwell", x2);
                    }
                    else
                    {
                        outputParameters.AddOutput("x2", x2);
                        outputParameters.AddOutput("df", g - 1);
                        outputParameters.AddOutput("pmaxwell", PDF.chivalp(x2, g - 1));
                    }

                    // general McNemar
                    if (x2M == Constant.MISSING)
                    {
                        outputParameters.AddOutput("x2m", "[not calculated - zero cells]");
                        outputParameters.AddOutput("dfmcnemar", dfm);
                        outputParameters.AddOutput("pmcnemar", string.Empty);
                    }
                    else
                    {
                        outputParameters.AddOutput("x2m", x2M);
                        outputParameters.AddOutput("dfmcnemar", dfm);
                        outputParameters.AddOutput("pmcnemar", PDF.chivalp(x2M, dfm));
                    }

                    // Gwet's AC1
                    outputParameters.AddOutput("gama", gama);
                    outputParameters.AddOutput("gamapc", gama * 100.0);
                    outputParameters.AddOutput("segama", segama);
                    outputParameters.AddOutput("gamacil", gamacil);
                    outputParameters.AddOutput("gamaciu", gamaciu);
                    outputParameters.AddOutput("pegama", pegama);
                    outputParameters.AddOutput("pegamapc", pegama * 100.0);

                    return new StepOutput(outputParameters);
                }
                throw new InvalidDataException();
                // <----wt
            }
            else
            {
                //  More than two raters
                IList<string> categoryList = new List<string>();
                foreach (IVariable v in frame.Variables)
                {
                    foreach (Group gr in ((ClassifierVariable)v).Groups)
                    {
                        string nm = gr.Label;
                        if (!categoryList.Contains(nm) && !Formatting.MISSINGLABEL.Equals(nm))
                            categoryList.Add(nm);
                    }
                }
                int cats = categoryList.Count;
                string[] catz = new string[cats];
                for (int i = 0; i < cats; i++)
                    catz[i] = categoryList[i];
                Array.Sort(catz, 0, cats);
                ParameterBag outputParameters = new();
                outputParameters.AddOutput("categories", cats); //  To ensure that any test on the result can find the number of categories
                if (cats == 2)
                {
                    // ----> Fleiss Cuzick for > 2 raters and 2 responses
                    KappaHat(frame, catz[0], out double k, out double mbar, out double mbarh, out double pbar, out double minm, out double maxm, out double medm, out double nRated);
                    double n = nRated; // subjects with at least one rating (the same n that mbar, mbarh and pbar use)
                    double sek = 1.0 / ((mbar - 1.0) * Math.Sqrt(n * mbarh)) * Math.Sqrt(2.0 * (mbarh - 1.0) + (mbar - mbarh) * (1.0 - 4.0 * pbar * (1.0 - pbar)) / (mbar * pbar * (1.0 - pbar)));
                    double z = sek != 0.0 ? k / sek : Constant.MISSING;
                    string ratz;
                    if (minm == maxm)
                        ratz = Convert.ToInt64(minm).ToString();
                    else
                        ratz = Convert.ToInt64(minm).ToString() + " to " + Convert.ToInt64(maxm).ToString() + " (median " + host.RoundU(medm) + ")";
                    outputParameters.AddOutput("r", ratz);
                    outputParameters.AddOutput("k", k);
                    outputParameters.AddOutput("se", sek);
                    outputParameters.AddOutput("z", z);
                    outputParameters.AddOutput("p", 1.0 - PDF.alnorm(z));

                    double ll = k - cit * sek;
                    double ul = k + cit * sek;
                    outputParameters.AddOutput("pc", 100.0 * cco);
                    outputParameters.AddOutput("ll", ll);
                    outputParameters.AddOutput("ul", ul);
                    // <----wt m x 2
                }
                else
                {
                    // ----> Landis and Koch (Fleiss, Nee, Landis se) kappa for raters and categories > 2
                    double kbarn = 0.0;
                    double kbard = 0.0;
                    double se2 = 0.0;
                    double[] sej = new double[cats];
                    double[] kj = new double[cats];
                    double minm = 0;
                    double maxm = 0;
                    double medm = 0;
                    double n = 0; // subjects with at least one rating
                    double mx = 0; // ratings per subject (constant when minm == maxm)
                    for (int i = 0; i < cats; i++)
                    {
                        KappaHat(frame, catz[i], out double k, out double mbar, out double _, out double pbar, out minm, out maxm, out medm, out n);
                        mx = minm == maxm ? minm : mbar;
                        double qbar = 1.0 - pbar;
                        kj[i] = k;
                        kbarn += pbar * qbar * k;
                        kbard += pbar * qbar;
                        se2 += pbar * qbar * (qbar - pbar);
                    }
                    for (int i = 0; i < cats; i++)
                        sej[i] = Math.Sqrt(2.0 / (n * mx * (mx - 1.0)));
                    double kbar = kbard != 0.0 ? kbarn / kbard : Constant.MISSING;
                    double sek = Math.Pow(kbard, 2.0) - se2 < 0.0
                        ? Constant.MISSING
                        : Math.Sqrt(2.0) / (kbard * Math.Sqrt(n * mx * (mx - 1.0))) * Math.Sqrt(Math.Pow(kbard, 2.0) - se2);
                    double z = sek != 0.0 && sek != Constant.MISSING
                        ? kbar / sek
                        : Constant.MISSING;
                    outputParameters.AddOutput("cats", cats);
                    string ratz;
                    if (minm == maxm)
                        ratz = Convert.ToInt64(minm).ToString();
                    else
                        ratz = Convert.ToInt64(minm).ToString() + " to " + Convert.ToInt64(maxm).ToString() + " (median " + host.RoundU(medm) + ")";
                    outputParameters.AddOutput("r", ratz);
                    if (minm == maxm)
                    {
                        ICollection<ParameterBag> catList = new List<ParameterBag>();
                        for (int i = 0; i < cats; i++)
                        {
                            ParameterBag catValues = new();
                            catValues.AddOutput("resp", catz[i]);
                            catValues.AddOutput("k", kj[i]);
                            catValues.AddOutput("se", sej[i]);
                            double zz;
                            if (sej[i] != 0.0)
                                zz = kj[i] / sej[i];
                            else
                                zz = 0.0;
                            catValues.AddOutput("z", zz);
                            catValues.AddOutput("p", 1.0 - PDF.alnorm(zz));
                            catList.Add(catValues);
                        }
                        outputParameters.AddOutput("*cats", catList);
                        outputParameters.AddOutput("kc", kbar);
                        //  outputParameters.AddOutput("sec", host.RoundU(sek))
                        outputParameters.AddOutput("zc", z);
                        outputParameters.AddOutput("p",
                                                   z != Constant.MISSING
                                                       ? 1.0 - PDF.alnorm(z)
                                                       : Constant.MISSING);

                        double ll = kbar - cit * sek;
                        double ul = kbar + cit * sek;
                        outputParameters.AddOutput("pc", 100.0 * cco);
                        outputParameters.AddOutput("ll", ll);
                        outputParameters.AddOutput("ul", ul);
                    }
                    else
                    {
                        ICollection<ParameterBag> catList = new List<ParameterBag>();
                        for (int i = 0; i < cats; i++)
                        {
                            ParameterBag catValues = new();
                            catValues.AddOutput("resp", catz[i]);
                            catValues.AddOutput("k", kj[i]);
                            catValues.AddOutput("se", Constant.MISSING);
                            catValues.AddOutput("z", Constant.MISSING);
                            catValues.AddOutput("p", Constant.MISSING);
                            catList.Add(catValues);
                        }
                        outputParameters.AddOutput("*cats", catList);
                        outputParameters.AddOutput("kc", kbar);
                        outputParameters.AddOutput("sec", Constant.MISSING);
                        outputParameters.AddOutput("zc", Constant.MISSING);
                        outputParameters.AddOutput("p", "* number of ratings per subject not constant, so tests do not apply");
                        //  The report prints the interval line whether or not there is an interval: without these it reads "% CI:  to "
                        outputParameters.AddOutput("pc", 100.0 * cco);
                        outputParameters.AddOutput("ll", Constant.MISSING);
                        outputParameters.AddOutput("ul", Constant.MISSING);
                    }
                    // <----wt m x k
                }

                return new StepOutput(outputParameters);
            }
        }

        public static StepOutput RptKappaSimulateExactP(IProgressBarHost host, ParameterBag parameters)
        {
            int iter = parameters["iterations"].AsInt32;
            int seed = parameters["seed"].AsInt32;
            double cco = parameters["ci"].AsDouble;
            double originalK = parameters["kDouble"].AsDouble;
            double originalKw = parameters["kwDouble"].AsDouble;
            double cit;
            if (cco > 0)
            {
                double p = (1.0 - cco) / 2.0;
                cit = PDF.gauinv(1.0 - p);
            }
            else
            {
                cco = 0.95;
                cit = PDF.gauinv(0.975);
            }

            bool alreadyCrosstabbed = parameters.ContainsKey("responsesCrosstab");
            int g;
            int[,] o;
            if (alreadyCrosstabbed)
            {
                DataFrame frame = parameters["responsesCrosstab"].AsDataFrame;
                int rows = frame.MaxRows;
                int cols = frame.VariableCount;

                if (rows != cols)
                    throw new InvalidDataException("A crosstab for kappa exact P must be square");

                g = Math.Max(rows, cols);
                o = new int[g, g];

                for (int i = 0; i < g; i++)
                    for (int j = 0; j < g; j++)
                        o[i, j] = 0;

                for (int i = 0; i < rows; i++)
                    for (int j = 0; j < cols; j++)
                        o[i, j] = (int)Math.Floor(((DoubleVariable)frame.Variables[j]).Data[i]);
            }
            else
            {
                DataFrame frame = parameters["responses"].AsDataFrame;
                int raters = frame.VariableCount;
                if (raters != 2)
                    throw new NotImplementedException();

                ClassifierVariable v0 = (ClassifierVariable)frame.Variables[0];
                int n = v0.Length;
                int ycats = 0;
                double[] y = new double[n];
                Namevar[] ycat = new Namevar[v0.GroupCount];
                for (int i = 0; i < v0.GroupCount; i++)
                {
                    if (v0.Groups[i].Label != Formatting.MISSINGLABEL)
                    {
                        ycat[ycats] = new Namevar(v0.Groups[i].Label, i);
                        ycats += 1;
                    }
                }
                // create temp variable for copying values 
                Namevar[] transTemp18 = new Namevar[ycats];
                Array.Copy(ycat, transTemp18, Math.Min(ycat.Length, transTemp18.Length));
                ycat = transTemp18;
                for (int i = 0; i < n; i++)
                    y[i] = v0.Data[i];
                SortName(ycats, ycat, 0);
                ClassifierVariable v1 = (ClassifierVariable)frame.Variables[1];
                int xcats = 0;
                double[] x = new double[n];
                Namevar[] xcat = new Namevar[v1.GroupCount];
                for (int i = 0; i < v1.GroupCount; i++)
                {
                    if (v1.Groups[i].Label != Formatting.MISSINGLABEL)
                    {
                        xcat[xcats] = new Namevar(v1.Groups[i].Label, i);
                        xcats += 1;
                    }
                }
                // create temp variable for copying values 
                Namevar[] transTemp19 = new Namevar[xcats];
                Array.Copy(xcat, transTemp19, Math.Min(xcat.Length, transTemp19.Length));
                xcat = transTemp19;
                for (int i = 0; i < n; i++)
                    x[i] = v1.Data[i];
                SortName(xcats, xcat, 0);
                XSymmetriseXtab(ref xcats, ref xcat, ref ycats, ref ycat, 0);
                double[,] xt = new double[xcats, ycats];
                double tot = 0.0;
                for (int i = 0; i < xcats; i++)
                {
                    for (int j = 0; j < ycats; j++)
                    {
                        for (int kv = 0; kv < n; kv++)
                            if (x[kv] == xcat[i].X & y[kv] == ycat[j].X)
                                xt[i, j] = xt[i, j] + 1;
                        tot += xt[i, j];
                    }
                }
                g = Math.Max(xcats, ycats);
                o = new int[g, g];
                for (int i = 0; i < g; i++)
                    for (int j = 0; j < g; j++)
                        o[i, j] = 0;
                for (int i = 0; i < ycats; i++)
                    for (int j = 0; j < xcats; j++)
                        o[i, j] = Convert.ToInt32(xt[j, i]);
                // <------- xtab
            }


            // xt, o and w are now zero-based, were 1-based.

            // weights --->
            double[,] w = new double[g, g];
            for (int i = 0; i < g; i++)
                for (int j = 0; j < g; j++)
                    w[i, j] = 0.0;

            int wtype = Parsing.Cint_Txt(parameters["method"].AsString);
            if (wtype == 3)
            {
                DataFrame weights = parameters["weights"].AsDataFrame;
                for (int i = 0; i < weights.VariableCount; i++)
                {
                    DoubleVariable v = (DoubleVariable)weights.Variables[i];
                    for (int j = 0; j < v.Length; j++)
                    {
                        w[i, j] = v.Data[j];
                        if (w[i, j] == Constant.MISSING)
                            w[i, j] = 0.0;
                    }
                }
            }
            if (wtype != 3)
            {
                for (int i = 0; i < g; i++)
                {
                    for (int j = 0; j < g; j++)
                    {
                        switch (wtype)
                        {
                            case 2:
                                w[i, j] = 1.0 - Math.Pow((i - j) / (double)(g - 1), 2.0);
                                break;
                            default:
                                w[i, j] = 1.0 - Math.Abs(i - j) / (double)(g - 1);
                                break;
                        }

                    }
                }
            }
            int ierror = 0;
            int exactR = 0;
            int exactIter = 0;
            int exactRw = 0;
            int exactIterW = 0;
            KappaResample(host, o, w, g, cit, originalK, originalKw, iter, ref exactR, ref exactIter, ref exactRw, ref exactIterW, seed, ref ierror);

            ParameterBag outputParameters = new();
            if (ierror == 0)
            {
                //  Kappa
                double exactP = exactR / (double)exactIter;
                outputParameters.AddOutput("p", exactP);
                MathDbl.binci(exactR, exactIter, out double ll, out double ul, cco, out string warn);
                outputParameters.AddOutput("ll", ll);
                outputParameters.AddOutput("ul", ul);
                outputParameters.AddOutput("warn", warn);

                //  Weighted kappa
                double exactPw = exactRw / (double)exactIterW;
                outputParameters.AddOutput("pw", exactPw);
                MathDbl.binci(exactRw, exactIterW, out double llw, out double ulw, cco, out string warnw);
                outputParameters.AddOutput("llw", llw);
                outputParameters.AddOutput("ulw", ulw);
                outputParameters.AddOutput("warnw", warnw);

                //  Common
                outputParameters.AddOutput("pc", 100.0 * cco);
                outputParameters.AddOutput("k", iter);
            }
            else
            {
                outputParameters.AddOutput("p", "P = * (cancelled)");
            }
            return new StepOutput(outputParameters);
        }

        ///  <summary>
        ///  Simulated exact P for Cohen's Kappa
        ///  </summary>
        /// <param name="host"></param>
        /// <param name="o">(0..nrow-1,0..ncol-1) input table</param>
        ///  <param name="w">(0..nrow-1,0..ncol-1) input weights</param>
        ///  <param name="g">Number of rows and columns</param>
        /// <param name="cit"></param>
        /// <param name="originalK">K-value from original operation, for comparison</param>
        ///  <param name="originalKw">Weighted K from original operation, for comparison</param>
        ///  <param name="iter">Monte Carlo iterations</param>
        /// <param name="exactIterW"></param>
        /// <param name="iseed">RNG seed (0 for automatic)</param>
        ///  <param name="ierror">return non-zero if fault (-1 if interrupted)</param>
        /// <param name="exactR"></param>
        /// <param name="exactIter"></param>
        /// <param name="exactRw"></param>
        /// <remarks></remarks>
        private static void KappaResample(IProgressBarHost host, int[,] o, double[,] w, int g, double cit, double originalK, double originalKw, int iter, ref int exactR, ref int exactIter, ref int exactRw, ref int exactIterW, int iseed, ref int ierror)
        {
            int[] ncolt = new int[g];
            int[] nrowt = new int[g];
            int ntotal = 0;
            int i;
            int j;
            MersenneTwister rng = new();

            int bootsDivisor = Math.Max(1, iter / 1000);

            using IProgressBar progress = host.StartProgress("Simulating exact P", true);

            if (iseed != 0)
                rng.Seed(iseed);
            else
                rng.Seed();

            for (j = 0; j < g; j++)
            {
                for (i = 0; i < g; i++)
                {
                    nrowt[j] += o[j, i];
                    ncolt[i] += o[j, i];
                }
            }

            int maxtot = 5000000;
            bool primed = false;

            double[] fact = new double[g];
            int[] jwork = new int[g];

            int missingSek = 0;
            int missingSekw = 0;
            int r = 0;
            int rw = 0;
            double tol = 100.0 * Constant.EPSILON;
            for (i = 1; i <= iter; i++)
            {
                if (i % bootsDivisor == 0)
                {
                    if (progress.Update(i / (double)iter))
                    {
                        ierror = -1; //  Interrupted
                        break;
                    }
                }
                Chi.Rcont2(0, g, g, nrowt, ncolt, ref primed, ref o, ref fact, ref ntotal, ref maxtot, ref jwork, out ierror, ref rng);
                if (ierror != 0)
                    throw new InvalidDataException("Monte Carlo simulation not possible: all row and column totals must be be greater than zero");
                double k = 0.0;
                double sek = 0;
                double sekci = 0;
                double kcil = 0;
                double kciu = 0;
                double kw = 0;
                double sekw = 0;
                double sekwci = 0;
                double kwcil = 0;
                double kwciu = 0;
                double po = 0;
                double pe = 0;
                double pow = 0;
                double pew = 0;
                double spe = 0;
                double spi = 0;
                Kappa(o, w, g, ref k, ref sek, ref sekci, ref kcil, ref kciu, ref kw, ref sekw, ref sekwci, ref kwcil, ref kwciu, ref po, ref pe, ref pow, ref pew, ref cit, ref spe, ref spi, out bool wasError);
                if (!wasError)
                {
                    if (sek != 0.0)
                    {
                        if (k > originalK || Math.Abs(k - originalK) < tol)
                            r += 1;
                    }
                    else
                    {
                        missingSek += 1;
                    }

                    if (sekw != 0.0)
                    {
                        if (kw > originalKw || Math.Abs(kw - originalKw) < tol)
                            rw += 1;
                    }
                    else
                    {
                        missingSekw += 1;
                    }
                }
                else
                {
                    throw new InvalidDataException();
                }
            }

            //  Ensure we deal with zero results by removing them from numerator (already done, they never got in there) and denominator
            exactR = r;
            exactIter = iter - missingSek;
            exactRw = rw;
            exactIterW = iter - missingSekw;
        }

        public static StepOutput RptKappaSizeWeights(ParameterBag parameters)
        {
            DataFrame frame = parameters["responses"].AsDataFrame;

            ClassifierVariable v0 = (ClassifierVariable)frame.Variables[0];
            int n = v0.Length;
            int ycats = 0;
            double[] y = new double[n];
            Namevar[] ycat = new Namevar[v0.GroupCount];
            for (int i = 0; i < v0.GroupCount; i++)
            {
                if (v0.Groups[i].Label != Formatting.MISSINGLABEL)
                {
                    ycat[ycats] = new Namevar(v0.Groups[i].Label, i);
                    ycats += 1;
                }
            }
            // create temp variable for copying values 
            Namevar[] transTemp20 = new Namevar[ycats];
            Array.Copy(ycat, transTemp20, Math.Min(ycat.Length, transTemp20.Length));
            ycat = transTemp20;
            for (int i = 0; i < n; i++)
                y[i] = v0.Data[i];
            SortName(ycats, ycat, 0);
            ClassifierVariable v1 = (ClassifierVariable)frame.Variables[1];
            int xcats = 0;
            double[] x = new double[n];
            Namevar[] xcat = new Namevar[v1.GroupCount];
            for (int i = 0; i < v1.GroupCount; i++)
            {
                if (v1.Groups[i].Label != Formatting.MISSINGLABEL)
                {
                    xcat[xcats] = new Namevar(v1.Groups[i].Label, i);
                    xcats += 1;
                }
            }
            // create temp variable for copying values 
            Namevar[] transTemp21 = new Namevar[xcats];
            Array.Copy(xcat, transTemp21, Math.Min(xcat.Length, transTemp21.Length));
            xcat = transTemp21;
            for (int i = 0; i < n; i++)
                x[i] = v1.Data[i];
            SortName(xcats, xcat, 0);
            XSymmetriseXtab(ref xcats, ref xcat, ref ycats, ref ycat, 0);
            ParameterBag outputParameters = new();
            outputParameters.AddOutput("ycats", ycats);
            outputParameters.AddOutput("xcats", xcats);
            return new StepOutput(outputParameters);
        }

        public static StepOutput RptChiGfSimulateExactP(IPreferencesAndProgressBar host, ParameterBag parameters)
        {
            int iterations = parameters["iterations"].AsInt32;
            int seed = parameters["seed"].AsInt32;
            double ci = parameters["ci"].AsDouble;
            double x2 = parameters["x2"].AsDouble;
            DataFrame observedFrame = parameters["observed"].AsDataFrame;
            DoubleVariable observed = (DoubleVariable)observedFrame.Variables[0];
            DataFrame expectedFrame = parameters["expected"].AsDataFrame;
            DoubleVariable expected = (DoubleVariable)expectedFrame.Variables[0];

            // The same rows as the goodness of fit report uses: a row with a missing cell is left out of both columns. The whole
            // columns used to be taken here, so that a blank cell stopped the simulation or gave it a cell with a false probability,
            // while the chi-square it is compared with came from the rows used.
            if (observed.Length != expected.Length)
                throw new TemplateOperationCancelledException("The observed and expected columns must have the same number of rows.", "Chi-square goodness of fit test");
            DoubleArraysAndBooleans copiesRemovingMissingRows = Numerics.Utilities.RemoveMissingRows(new[] { observed.Data, expected.Data }, 0, observed.Length, 0);
            //  Observed data is grouped frequencies.
            double[] observedData = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[0];
            //  Expected data may be probabilities or counts; they are scaled to add up to 1.
            double[] expectedData = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[1];

            int nx = observedData.Length;

            int[] xn = new int[nx + 1];
            double[] p = new double[nx + 1];
            double expectedTotal = 0.0;
            for (int n = 0; n < nx; n++)
                expectedTotal += expectedData[n];
            expectedTotal = Math.Round(expectedTotal, 12);
            for (int n = 0; n < nx; n++)
            {
                xn[n + 1] = Convert.ToInt32(observedData[n]);
                p[n + 1] = expectedData[n] / expectedTotal;
            }

            ResampleX2Gf(host, xn, p, nx, x2, out int r, iterations, seed, out int actualIterations);

            ParameterBag outputParameters = new();
            double exactP = r / (double)actualIterations;
            outputParameters.AddOutput("p", exactP);
            //  CI
            MathDbl.binci(r, actualIterations, out double ll, out double ul, ci, out string warn);
            outputParameters.AddOutput("pc", 100.0 * ci);
            outputParameters.AddOutput("ll", ll);
            outputParameters.AddOutput("ul", ul);
            outputParameters.AddOutput("warn", warn);
            outputParameters.AddOutput("k", actualIterations);

            return new StepOutput(outputParameters);
        }

        ///  <summary>
        ///  Resample chi-square goodness of fit by random permutation of a total of ntot counts across k cells with cell probability p
        ///  </summary>
        /// <param name="host"></param>
        /// <param name="x">counts (1 to k). This is used as scrap storage so will be destroyed by this function</param>
        ///  <param name="p">p(k) probability of count in cell k</param>
        ///  <param name="k">cells</param>
        ///  <param name="x2">observed chi-square goodness of fit statistic</param>
        ///  <param name="r">Monte Carlo P numerator</param>
        ///  <param name="iter">Monte Carlo iterations requested</param>
        ///  <param name="iseed">RNG seed</param>
        /// <param name="actualIterations">The number of iterations that were actually run</param>
        /// <remarks></remarks>
        private static void ResampleX2Gf(IPreferencesAndProgressBar host, int[] x, double[] p, int k, double x2, out int r, int iter, int iseed, out int actualIterations)
        {
            int ntot = 0;
            for (int i = 1; i <= k; i++)
                ntot += x[i];
            double[] pp = new double[k + 1];
            pp[1] = Math.Round(p[1], 12);
            for (int i = 2; i <= k; i++)
                pp[i] = Math.Round(p[i] + pp[i - 1], 12);
            r = 0;
            using IProgressBar progress = host.StartProgress("Simulating exact P", true);
            MersenneTwister rng = new(iseed);
            for (int l = 1; l <= iter; l++)
            {
                Array.Clear(x, 1, k);
                for (int i = 1; i <= ntot; i++)
                {
                    double pr = rng.NextDouble();
                    int j;
                    for (j = 1; j <= k; j++)
                    {
                        if (pr <= pp[j])
                            break;
                    }
                    if (j > k)
                        j = k;
                    x[j]++;
                }
                if (X2Gf(x, p, k) >= x2)
                    r++;
                if (progress.Update(Convert.ToDouble(l) / iter))
                {
                    actualIterations = l;
                    return;
                }
            }
            actualIterations = iter;
        }

        ///  <summary>
        ///  Compute chi-square goodness of fit for k observed counts with probability p for each cell
        ///  </summary>
        ///  <param name="x"></param>
        ///  <param name="p"></param>
        ///  <param name="k"></param>
        ///  <returns></returns>
        ///  <remarks></remarks>
        private static double X2Gf(int[] x, double[] p, int k)
        {
            int nt = 0;
            for (int i = 1; i <= k; i++)
                nt += x[i];
            double x2 = 0.0;
            for (int i = 1; i <= k; i++)
            {
                double xe = nt * p[i];
                x2 += (x[i] - xe) * (x[i] - xe) / xe;
            }
            return x2;
        }

        public static StepOutput RptChiSquareGoodnessOfFit(ParameterBag parameters)
        {
            const string cgft = "Chi-square goodness of fit test";

            DataFrame observedFrame = parameters["observed"].AsDataFrame;
            DoubleVariable observed = (DoubleVariable)observedFrame.Variables[0];
            DataFrame expectedFrame = parameters["expected"].AsDataFrame;
            DoubleVariable expected = (DoubleVariable)expectedFrame.Variables[0];

            // A different number of rows used to stop the analysis with an index out of range.
            if (observed.Length != expected.Length)
                throw new TemplateOperationCancelledException("The observed and expected columns must have the same number of rows.", cgft);

            DoubleArraysAndBooleans copiesRemovingMissingRows = Numerics.Utilities.RemoveMissingRows(new[] { observed.Data, expected.Data }, 0, observed.Length, 0);
            //  Observed data is grouped frequencies.
            double[] observedData = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[0];
            //  Expected data may be probabilities or counts; we'll scale them later.
            double[] expectedData = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[1];

            int nx = observedData.Length;

            string[] names = null;
            if (parameters.ContainsKey("names"))
            {
                StringVariable namesVariable = (StringVariable)parameters["names"].AsDataFrame.Variables[0];
                // A shorter column of names stopped the analysis with an index out of range, as columns of different lengths did.
                if (namesVariable.Length != observed.Length)
                    throw new TemplateOperationCancelledException("The column of category names must have the same number of rows as the observed counts.", cgft);
                names = Numerics.Utilities.CopyValidRows(namesVariable.Data, copiesRemovingMissingRows.ValidRowsInOriginal, 0, expected.Length, 0, nx);
            }

            if (nx < 2)
                throw new TemplateOperationCancelledException("Too few categories, use at least three for the chi-square goodness of fit test.", cgft);
            if (nx == 2)
                throw new TemplateOperationCancelledException("Only two categories, use binomial methods such as the single proportion test.", cgft);

            double[] xn = new double[nx];
            double[] xe = new double[nx];
            // Totals are over the rows that are used. They used to be over the whole columns, so a row left out because one of
            // its cells was missing still counted: the expected frequencies then no longer added up to the observed total and
            // the chi-square was wrong.
            double observedTotal = 0.0;
            double expectedTotal = 0.0;
            for (int n = 0; n < nx; n++)
            {
                observedTotal += observedData[n];
                expectedTotal += expectedData[n];
            }
            // Probabilities (adding up to 1 or less) and percentages (adding up to 100) are scaled to the observed total without
            // comment; the help's own example gives the expected distribution as percentages.
            bool expectedIsProbability = expectedTotal <= 1.0 || Math.Abs(expectedTotal - 100.0) < 1e-6;
            // Expected values that add up to nothing gave a report of asterisks, and negative counts were accepted.
            if (!(expectedTotal > 0.0) || double.IsInfinity(expectedTotal))
                throw new TemplateOperationCancelledException("The expected values must add up to more than zero.", cgft);
            for (int n = 0; n < nx; n++)
            {
                if (observedData[n] < 0.0)
                    throw new TemplateOperationCancelledException("Observed counts cannot be negative.", cgft);
            }
            for (int n = 0; n < nx; n++)
            {
                xn[n] = observedData[n];
                xe[n] = expectedData[n] / expectedTotal * observedTotal;
            }
            //  At this point, we know that both xn and xe add up to observedTotal

            int df = nx - 1;

            int expectedsBelow5 = 0;
            for (int n = 0; n < nx; n++)
            {
                if (xe[n] <= 0)
                    throw new TemplateOperationCancelledException("Cannot have an expected value of zero or less.", cgft);
                if (xe[n] < 5)
                    expectedsBelow5 += 1;
            }
            string w2;
            // compared as numbers: conversion to a 32-bit integer stopped the analysis when a total reached 2,147,483,648
            if (!(expectedIsProbability || Math.Abs(expectedTotal - observedTotal) < 0.5))
                w2 = Formatting.WRNCOLON + "total expected not equal to total observed";
            else
                w2 = string.Empty;
            string warn = string.Empty;
            if (expectedsBelow5 > 0)
                warn += Formatting.XRound(100 * Convert.ToDouble(expectedsBelow5) / Convert.ToDouble(nx), 1) + "% of the expected frequencies < 5";
            if (observedTotal < 20)
            {
                if (warn.Length > 0)
                    warn += " and ";
                warn += "total number < 20";
            }
            if (warn.Length > 0)
                warn += Formatting.RTFCRLF + Formatting.WRNCOLON;
            if (observedTotal < 20 || (Convert.ToDouble(expectedsBelow5) / Convert.ToDouble(nx) > 0.2))
                warn += "TEST MAY NOT BE RELIABLE";
            if (w2.Length > 0)
                warn += "  *(" + w2 + ")*";
            ParameterBag outputParameters = new();
            outputParameters.AddOutput("ti", observed.Title);
            outputParameters.AddOutput("n", observedTotal);

            double x2 = 0.0;
            IList<ParameterBag> frequenciesList = new List<ParameterBag>();
            for (int i = 0; i < nx; i++)
            {
                ParameterBag frequenciesParameters = new();
                string tx = (i + 1).ToString();
                if (null != names)
                    tx = names[i];
                frequenciesParameters.AddOutput("x", tx);
                frequenciesParameters.AddOutput("o", xn[i]);
                frequenciesParameters.AddOutput("e", xe[i]);
                x2 += (xn[i] - xe[i]) * (xn[i] - xe[i]) / xe[i];
                frequenciesList.Add(frequenciesParameters);
            }

            outputParameters.AddOutput("*frequencies", frequenciesList);
            outputParameters.AddOutput("chi2", x2);
            outputParameters.AddOutput("df", df);
            outputParameters.AddOutput("p", PDF.chivalp(x2, df));
            if (warn.Length > 0)
            {
                IList<ParameterBag> warnList = new List<ParameterBag>();
                ParameterBag warnParameters = new();
                warnParameters.AddOutput("warn", warn);
                warnList.Add(warnParameters);
                outputParameters.AddOutput("*warn", warnList);
            }
            else
            {
                outputParameters.AddOutput("*warn", null);
            }

            //  Remember a few values in case the user then wants to simulate exact P
            outputParameters.AddInput("x2", x2);

            return new StepOutput(outputParameters);
        }

        public static StepOutput RptCrosstabsPreprocess(ITemplateHost host, ParameterBag parameters)
        {
            bool strat = false;

            //  First classifier
            DataFrame c1Frame = parameters["c1"].AsDataFrame;
            ClassifierVariable c1Variable = (ClassifierVariable)c1Frame.Variables[0];
            int ycats = c1Variable.GroupCount;
            Namevar[] ycat = new Namevar[ycats + 1];
            int cnt = 0;
            for (int i = 0; i < ycats; i++)
            {
                if (c1Variable.Groups[i].Label != Formatting.MISSINGLABEL)
                {
                    cnt++;
                    ycat[cnt] = new Namevar(c1Variable.Groups[i].Label, i);
                }
            }
            ycats = cnt;

            SortName(ycats, ycat, 1);

            //  Second classifier
            DataFrame c2Frame = parameters["c2"].AsDataFrame;

            // Maybe go to three factors if one column classifier
            if (c2Frame.VariableCount == 1)
            {
                strat = parameters.ContainsKey("c3") && parameters["c3"] != null;
                if (strat)
                {
                    DataFrame c3Frame = parameters["c3"].AsDataFrame;
                    ClassifierVariable c3Variable = (ClassifierVariable)c3Frame.Variables[0];
                    cnt = 0;
                    for (int i = 0; i < c3Variable.GroupCount; i++)
                        if (c3Variable.Groups[i].Label != Formatting.MISSINGLABEL)
                            cnt++;
                    strat = cnt > 1;
                }
            }

            ParameterBag outputParameters = new();
            outputParameters.AddInput("strat", strat);
            for (int c = 0; c < c2Frame.VariableCount; c++)
            {
                ClassifierVariable c2Variable = (ClassifierVariable)c2Frame.Variables[c];
                int xcats = c2Variable.GroupCount;
                Namevar[] xcat = new Namevar[xcats + 1];
                cnt = 0;
                for (int i = 0; i < xcats; i++)
                {
                    if (c2Variable.Groups[i].Label != Formatting.MISSINGLABEL)
                    {
                        cnt++;
                        xcat[cnt] = new Namevar(c2Variable.Groups[i].Label, i);
                    }
                }
                xcats = cnt;
                SortName(xcats, xcat, 1);

                bool ok = true;
                bool wasCancelled;
                if (ycats > 10 || xcats > 10)
                {
                    ok = host.GetBoolean($"Table is large: {ycats} rows by ${xcats} columns. Continue?", "Crosstabs: Large table warning", false, out wasCancelled);
                    if (wasCancelled)
                        throw new TemplateOperationCancelledException();
                }

                if (!XSymmetrical(xcats, xcat, ycats, ycat, false))
                {
                    bool symmetrise = host.GetBoolean("This table is asymmetrical. Force it to be symmetrical by adding empty columns or rows?", "Crosstabs: symmetry", false, out wasCancelled);
                    if (wasCancelled)
                        throw new TemplateOperationCancelledException();
                    if (symmetrise)
                        XSymmetriseXtab(ref xcats, ref xcat, ref ycats, ref ycat, 1);
                }

                if (!ok)
                    continue;

                if (strat)
                {
                    outputParameters.AddInput("xcats", xcats);
                    outputParameters.AddInput("ycats", ycats);
                }
            }
            return new StepOutput(outputParameters);
        }

        public static StepOutput RptCrosstabs(ITemplateHost host, ParameterBag parameters)
        {
            double[] z = null;
            string zLabel = null;
            int zCategoryCount = 0;
            bool isStratified = false;
            Namevar[] zcat = null;

            //  First classifier
            DataFrame c1Frame = parameters["c1"].AsDataFrame;
            ClassifierVariable c1Variable = (ClassifierVariable)c1Frame.Variables[0];
            int n = c1Variable.Length;

            double[] y = new double[n + 1];
            Array.Copy(c1Variable.Data, 0, y, 1, n);

            int yCategoryCount = c1Variable.GroupCount;
            Namevar[] ycat = new Namevar[yCategoryCount + 1];
            string yLabel = c1Variable.Title;
            int cnt = 0;
            for (int i = 0; i < yCategoryCount; i++)
            {
                if (c1Variable.Groups[i].Label != Formatting.MISSINGLABEL)
                {
                    cnt++;
                    ycat[cnt] = new Namevar(c1Variable.Groups[i].Label, i);
                }
            }
            yCategoryCount = cnt;

            SortName(yCategoryCount, ycat, 1);

            //  Second classifier(s)
            DataFrame c2Frame = parameters["c2"].AsDataFrame;

            // Allow stratification iff one column classifier
            if (c2Frame.VariableCount == 1)
            {
                isStratified = parameters.ContainsKey("c3") && parameters["c3"] != null;
                if (isStratified)
                {
                    DataFrame c3Frame = parameters["c3"].AsDataFrame;
                    ClassifierVariable c3Variable = (ClassifierVariable)c3Frame.Variables[0];
                    zCategoryCount = c3Variable.GroupCount;
                    z = new double[n + 1];
                    zcat = new Namevar[zCategoryCount + 1];
                    zLabel = c3Variable.Title;
                    cnt = 0;
                    for (int i = 0; i < zCategoryCount; i++)
                    {
                        if (c3Variable.Groups[i].Label != Formatting.MISSINGLABEL)
                        {
                            cnt++;
                            zcat[cnt] = new Namevar(c3Variable.Groups[i].Label, i);
                        }
                    }
                    zCategoryCount = cnt;
                    for (int r = 1; r <= n; r++)
                        z[r] = c3Variable.Data[r - 1];
                    SortName(zCategoryCount, zcat, 1);
                    isStratified = zCategoryCount > 1;
                }
            }

            ParameterBag outputParameters = new();
            List<ParameterBag> columnsList = new();
            outputParameters.AddOutput("*columns", columnsList);
            for (int c = 0; c < c2Frame.VariableCount; c++)
            {
                ClassifierVariable c2Variable = c2Frame.Variables[c] as ClassifierVariable;
                int xCategoryCount = c2Variable.GroupCount;
                double[] x = new double[n + 1];
                Namevar[] xcat = new Namevar[xCategoryCount + 1];
                string xLabel = c2Variable.Title;
                cnt = 0;
                for (int i = 0; i < xCategoryCount; i++)
                {
                    if (c2Variable.Groups[i].Label != Formatting.MISSINGLABEL)
                    {
                        cnt++;
                        xcat[cnt] = new Namevar(c2Variable.Groups[i].Label, i);
                    }
                }
                xCategoryCount = cnt;
                for (int r = 1; r <= n; r++)
                    x[r] = c2Variable.Data[r - 1];
                SortName(xCategoryCount, xcat, 1);

                bool ok = true;
                bool wasCancelled;
                if (yCategoryCount > 10 || xCategoryCount > 10)
                {
                    ok = host.GetBoolean("Table = " + yCategoryCount.ToString() + " rows by " + xCategoryCount.ToString() + " columns" + "\r\n" + "Continue?", "Crosstabs: Large table warning", false, out wasCancelled);
                    if (wasCancelled)
                        throw new TemplateOperationCancelledException();
                }

                if (!XSymmetrical(xCategoryCount, xcat, yCategoryCount, ycat, false))
                {
                    bool symmetrise = host.GetBoolean("This table is asymmetrical." + "\r\n" + "Force it to be symmetrical by adding empty columns or rows?", "Crosstabs: symmetry", false, out wasCancelled);
                    if (wasCancelled)
                        throw new TemplateOperationCancelledException();
                    if (symmetrise)
                        XSymmetriseXtab(ref xCategoryCount, ref xcat, ref yCategoryCount, ref ycat, 1);
                }

                if (!ok)
                    continue;

                ParameterBag columnsParameters = new();
                columnsList.Add(columnsParameters);
                double tot;
                if (isStratified)
                {
                    // three factor xtab ---->
                    double cco = parameters["cco"].AsDouble;
                    double[,,] zt = new double[xCategoryCount + 1, yCategoryCount + 1, zCategoryCount + 1];
                    tot = 0.0;
                    for (int i = 1; i <= xCategoryCount; i++)
                    {
                        for (int j = 1; j <= yCategoryCount; j++)
                        {
                            for (int m = 1; m <= zCategoryCount; m++)
                            {
                                for (int k = 1; k <= n; k++)
                                {
                                    if (x[k] == xcat[i].X && y[k] == ycat[j].X && z[k] == zcat[m].X)
                                        zt[i, j, m]++;
                                }
                                tot += zt[i, j, m];
                            }
                        }
                    }
                    y = null;
                    z = null;

                    List<ParameterBag> xtabzList = new();
                    columnsParameters.AddOutput("*xtabz", xtabzList);
                    ParameterBag xtabzParameters = new();
                    xtabzList.Add(xtabzParameters);
                    xtabzParameters.AddOutput("ylab", yLabel);
                    xtabzParameters.AddOutput("xlab", xLabel);
                    xtabzParameters.AddOutput("zlab", zLabel);
                    List<ParameterBag> zList = new();
                    xtabzParameters.AddOutput("*z", zList);
                    for (int m = 1; m <= zCategoryCount; m++)
                    {
                        ParameterBag zParameters = new();
                        zList.Add(zParameters);
                        zParameters.AddOutput("z", zcat[m].Title);
                        List<ParameterBag> xList = new();
                        zParameters.AddOutput("*x", xList);
                        for (int i = 1; i <= xCategoryCount; i++)
                        {
                            ParameterBag xParameters = new();
                            xList.Add(xParameters);
                            xParameters.AddOutput("x", xcat[i].Title);
                        }
                        List<ParameterBag> yList = new();
                        zParameters.AddOutput("*y", yList);
                        for (int i = 1; i <= yCategoryCount; i++)
                        {
                            ParameterBag yParameters = new();
                            yList.Add(yParameters);
                            yParameters.AddOutput("y", ycat[i].Title);
                            List<ParameterBag> totList = new();
                            yParameters.AddOutput("*tot", totList);
                            for (int j = 1; j <= xCategoryCount; j++)
                            {
                                ParameterBag totParameters = new();
                                totList.Add(totParameters);
                                totParameters.AddOutput("tot", zt[j, i, m]);
                            }
                        }
                    }
                    if (xCategoryCount == 2 && yCategoryCount == 2)
                    {
                        string studyType = parameters["study_type"].AsString;
                        if ("casecontrol".Equals(studyType))
                        {
                            ParameterBag mantelParameters = TabMh(host, cco, zCategoryCount, zt, zcat);
                            if (mantelParameters != null)
                            {
                                List<ParameterBag> mantelList = new();
                                columnsParameters.AddOutput("*mantel", mantelList);
                                mantelList.Add(mantelParameters);
                            }
                        }
                        else if ("cohort".Equals(studyType))
                        {
                            ParameterBag rrmetaParameters = TabRelativeRisk(host, cco, zCategoryCount, zt, zcat);
                            if (rrmetaParameters != null)
                            {
                                List<ParameterBag> rrmetaList = new();
                                columnsParameters.AddOutput("*rrmeta", rrmetaList);
                                rrmetaList.Add(rrmetaParameters);
                            }
                        }
                    }
                    else
                    {
                        ParameterBag gencmhParameters = TabCmh(parameters, zCategoryCount, yCategoryCount, xCategoryCount, zt, yLabel, xLabel, zLabel);
                        if (gencmhParameters != null)
                        {
                            List<ParameterBag> gencmhList = new();
                            columnsParameters.AddOutput("*gencmh", gencmhList);
                            gencmhList.Add(gencmhParameters);
                        }
                    }
                    // three factor  <-----
                }
                else
                {
                    // two factor xtab ---->
                    double cco = parameters["cco"].AsDouble;
                    double[,] xt = new double[xCategoryCount + 1, yCategoryCount + 1];
                    tot = 0.0;
                    for (int i = 1; i <= xCategoryCount; i++)
                    {
                        for (int j = 1; j <= yCategoryCount; j++)
                        {
                            for (int k = 1; k <= n; k++)
                                if (x[k] == xcat[i].X && y[k] == ycat[j].X)
                                    xt[i, j]++;
                            tot += xt[i, j];
                        }
                    }

                    List<ParameterBag> xtabList = new();
                    columnsParameters.AddOutput("*xtab", xtabList);
                    ParameterBag xtabParameters = new();
                    xtabList.Add(xtabParameters);
                    xtabParameters.AddOutput("ylab", yLabel);
                    xtabParameters.AddOutput("xlab", xLabel);
                    List<ParameterBag> xList = new();
                    xtabParameters.AddOutput("*x", xList);
                    for (int i = 1; i <= xCategoryCount; i++)
                    {
                        ParameterBag xParameters = new();
                        xList.Add(xParameters);
                        xParameters.AddOutput("x", xcat[i].Title);
                    }
                    List<ParameterBag> yList = new();
                    xtabParameters.AddOutput("*y", yList);
                    for (int i = 1; i <= yCategoryCount; i++)
                    {
                        ParameterBag yParameters = new();
                        yList.Add(yParameters);
                        yParameters.AddOutput("y", ycat[i].Title);
                        List<ParameterBag> totList = new();
                        yParameters.AddOutput("*tot", totList);
                        for (int j = 1; j <= xCategoryCount; j++)
                        {
                            ParameterBag totParameters = new();
                            totList.Add(totParameters);
                            totParameters.AddOutput("tot", xt[j, i]);
                        }
                    }
                    List<ParameterBag> chirxcList = new();
                    columnsParameters.AddOutput("*chirxc", chirxcList);
                    if (tot > 0.0)
                    {
                        double[,] w = MathDbl.Transpose(xt);
                        bool doExact = parameters["doExact"].AsBoolean;
                        bool doMonteCarlo = parameters["doMonteCarlo"].AsBoolean;
                        bool pc = parameters["show_pc"].AsBoolean;
                        bool xp = parameters["xp"].AsBoolean;
                        bool cs = parameters["cs"].AsBoolean;
                        bool xs = parameters["xs"].AsBoolean;
                        bool specifyScores = parameters["specify_scores"].AsBoolean;
                        int iterations = 1000000;
                        double mcci = 0.99;
                        int seed = 0;
                        if (doMonteCarlo)
                        {
                            iterations = parameters["iterations"].AsInt32;
                            mcci = parameters["ci"].AsDouble;
                            seed = parameters["seed"].AsInt32;
                        }

                        // w() was passed to a FORTRAN routine so must redim to (1 to c, 1 to r)
                        ParameterBag chirxcParameters = SChi(host, ref cco, w, yCategoryCount, xCategoryCount, doExact, doMonteCarlo, pc, xp, cs, xs, specifyScores, mcci, iterations, seed);
                        chirxcList.Add(chirxcParameters);
                    }
                } // two factor <-----
            }
            return new StepOutput(outputParameters);
        }

        private static ParameterBag TabCmh(ParameterBag parameters, int istrata, int irows, int icols, double[,,] zt, string ylab, string xlab, string zlab)
        {
            string ender;

            double[] tbl = new double[istrata * irows * icols + 1];
            int ctr = 0;
            double ntot = 0;
            string cscores = string.Empty;
            string rscores = string.Empty;
            for (int i = 1; i <= icols; i++)
            {
                for (int j = 1; j <= istrata; j++)
                {
                    for (int k = 1; k <= irows; k++)
                    {
                        ctr++;
                        tbl[ctr] = zt[i, k, j];
                        ntot += tbl[ctr];
                    }
                }
            }

            // Obtain scores - assume _preprocess has been run.  Note that the arrays passed in are 0-based
            double[] colScore0 = (double[])parameters["values1"].AsObject;
            double[] rowScore0 = (double[])parameters["values2"].AsObject;
            double[] colScore = new double[colScore0.Length + 1];
            Array.Copy(colScore0, 0, colScore, 1, colScore0.Length);
            double[] rowScore = new double[rowScore0.Length + 1];
            Array.Copy(rowScore0, 0, rowScore, 1, rowScore0.Length);
            /*
            double[] rowScore = new double[icols + 1];
            double[] colScore = new double[irows + 1];
            for (int i = 1; i <= irows; i++)
                colScore[i] = i;
            for (int i = 1; i <= icols; i++)
                rowScore[i] = i;
            // ask for scores --->
            ScoresOptions sOptions = new ScoresOptions { Title1 = ylab, Title2 = xlab };
            for (int i = 1; i <= icols; i++)
                sOptions.Values2.Add(rowScore[i]);
            for (int i = 1; i <= irows; i++)
                sOptions.Values1.Add(colScore[i]);
            bool userOk = null != host.Amend(sOptions, null);
            if (!userOk)
                return null;

            for (int i = 1; i <= icols; i++)
                rowScore[i] = sOptions.Values2[i - 1];
            for (int i = 1; i <= irows; i++)
                colScore[i] = sOptions.Values1[i - 1];
             */
            // <---
            Gencmh(istrata, irows, icols, tbl, rowScore, colScore, 3, out double x21, out double df1, out double p1, out int ierr);
            if (ierr != 0)
            {
                x21 = Constant.MISSING;
                p1 = Constant.MISSING;
            }
            Gencmh(istrata, irows, icols, tbl, rowScore, colScore, 2, out double x22, out double df2, out double p2, out ierr);
            if (ierr != 0)
            {
                x22 = Constant.MISSING;
                p2 = Constant.MISSING;
            }
            Gencmh(istrata, irows, icols, tbl, rowScore, colScore, 1, out double x23, out double df3, out double p3, out ierr);
            if (ierr != 0)
            {
                x23 = Constant.MISSING;
                p3 = Constant.MISSING;
            }
            //  note transposition of row and column scores
            //  row scores are scores for each column entry in the row and vice versa
            for (int i = 1; i <= icols; i++)
            {
                ender = i < icols ? ", " : string.Empty;
                cscores = cscores + rowScore[i].ToString() + ender;
            }
            for (int i = 1; i <= irows; i++)
            {
                ender = i < irows ? ", " : string.Empty;
                rscores = rscores + colScore[i].ToString() + ender;
            }

            ParameterBag outputParameters = new();
            outputParameters.AddOutput("ylab", ylab);
            outputParameters.AddOutput("xlab", xlab);
            outputParameters.AddOutput("zlab", zlab);
            outputParameters.AddOutput("rscore", rscores);
            outputParameters.AddOutput("cscore", cscores);
            outputParameters.AddOutput("x21", x21);
            outputParameters.AddOutput("df1", df1);
            outputParameters.AddOutput("p1", p1);
            outputParameters.AddOutput("x22", x22);
            outputParameters.AddOutput("df2", df2);
            outputParameters.AddOutput("p2", p2);
            outputParameters.AddOutput("x23", x23);
            outputParameters.AddOutput("df3", df3);
            outputParameters.AddOutput("p3", p3);
            outputParameters.AddOutput("nt", ntot);
            return outputParameters;
        }

        private static ParameterBag TabRelativeRisk(IPreferencesAndProgressBar host, double cco, int zcats, double[,,] zt, Namevar[] zcat)
        {
            const int lowerBound = 1;

            double cit;
            if (cco > 0)
            {
                double p = (1.0 - cco) / 2.0;
                cit = PDF.gauinv(1.0 - p);
            }
            else
            {
                cco = 0.95;
                cit = PDF.gauinv(0.975);
            }

            int k = zcats;
            string[] title = new string[k + lowerBound];
            for (int i = lowerBound; i < lowerBound + k; i++)
            {
                title[i] = zcat[i].Title;
                if (title[i].Length > 50)
                    title[i] = title[i].Substring(0, 50);
            }

            double[,] o = new double[k + 1, 4 + 1];
            double[] axll = new double[k + lowerBound];
            double[] axul = new double[k + lowerBound];
            for (int i = lowerBound; i < lowerBound + k; i++)
            {
                o[i, 4] = zt[1, 1, i];
                o[i, 3] = zt[1, 2, i];
                o[i, 2] = zt[2, 1, i];
                o[i, 1] = zt[2, 2, i];
            }

            Meta.RelativeRiskMA(host, lowerBound, k, out int realk, o, out double rmh, out double ll, out double ul, out double x2Rmh, cit, out double[] rkr, out double[] rkw, out double[] dsw, out double[] rkrl, out double[] rkru, out double[] rkx, out bool[] lerr, out bool[] uerr, out double qc, out double dsrr, out double dsx2, out double dsll, out double dsul, out double tausq, out bool[] cced, out bool[] included, out int ierr);
            if (ierr == -1)
                throw new InvalidDataException();

            ParameterBag outputParameters = new();

            List<ParameterBag> inputsList = new();
            outputParameters.AddOutput("*inputs", inputsList);
            for (int i = lowerBound; i < lowerBound + k; i++)
            {
                ParameterBag inputsParameters = new();
                inputsList.Add(inputsParameters);
                inputsParameters.AddOutput("st", i);
                inputsParameters.AddOutput("a", o[i, 1]);
                inputsParameters.AddOutput("b", o[i, 2]);
                inputsParameters.AddOutput("c", o[i, 3]);
                inputsParameters.AddOutput("d", o[i, 4]);
                inputsParameters.AddOutput("lb", title[i]);
            }
            outputParameters.AddOutput("pc", cco * 100);
            outputParameters.AddOutput("method", host.Preferences.MetaExact ? "Koopman" : "approximate");
            List<ParameterBag> risksList = new();
            outputParameters.AddOutput("*risks", risksList);
            for (int i = lowerBound; i < lowerBound + k; i++)
            {
                ParameterBag risksParameters = new();
                risksList.Add(risksParameters);
                risksParameters.AddOutput("st", i);
                risksParameters.AddOutput("rr", rkr[i]);
                risksParameters.AddOutput("yi", rkr[i] > 0 ? Math.Log(rkr[i]) : 0);
                risksParameters.AddOutput("vi", Meta.VarianceFromCI(rkrl[i], rkru[i], cit, true));
                risksParameters.AddOutput("lci", rkrl[i]);
                risksParameters.AddOutput("uci", rkru[i]);
                risksParameters.AddOutput("wt", 100 * rkw[i] / Formatting.dsum(rkw, 1));
                risksParameters.AddOutput("dwt", 100 * dsw[i] / Formatting.dsum(dsw, 1));
                risksParameters.AddOutput("lb", Meta.GetMetaLabel(host, o, i, true, cced, title));
            }
            outputParameters.AddOutput("rr", rmh);
            outputParameters.AddOutput("from", ll);
            outputParameters.AddOutput("to", ul);

            outputParameters.AddOutput("x2", x2Rmh);
            outputParameters.AddOutput("df", 1);
            outputParameters.AddOutput("xp", PDF.chivalp(x2Rmh, 1.0));

            outputParameters.AddOutput("qc", qc);
            outputParameters.AddOutput("df_cochran", realk - 1);
            outputParameters.AddOutput("xp_cochran", PDF.chivalp(qc, realk - 1));
            outputParameters.AddOutput("tausq", tausq);
            Meta.IsquareNcc(host, qc, realk, cco, cit, out double isq, out double llisq, out double ulisq);
            outputParameters.AddOutput("isq", isq);
            outputParameters.AddOutput("pc1", cco * 100);
            outputParameters.AddOutput("llisq", llisq);
            outputParameters.AddOutput("ulisq", ulisq);

            outputParameters.AddOutput("dsrr", dsrr);
            outputParameters.AddOutput("dsll", dsll);
            outputParameters.AddOutput("dsul", dsul);
            outputParameters.AddOutput("dsx2", dsx2);
            outputParameters.AddOutput("df_ds", 1);
            outputParameters.AddOutput("xp_ds", PDF.chivalp(dsx2, 1.0));

            Meta.GetAproxrrCI(host, o, k, cit, axll, axul);

            IList<ParameterBag> eggerList = new List<ParameterBag>();
            outputParameters.AddOutput("*egger", eggerList);
            ParameterBag eggerParameters = new();
            eggerList.Add(eggerParameters);
            Meta.Metabias(host, eggerParameters, rkr, axll, axul, k, ref cco, Transformation.Log);

            IList<ParameterBag> harbordList = new List<ParameterBag>();
            outputParameters.AddOutput("*harbord", harbordList);
            ParameterBag harbordParameters = new();
            harbordList.Add(harbordParameters);
            Meta.ModMetabias(host, harbordParameters, o, k, cco, 2);

            IList<ParameterBag> chartList = new List<ParameterBag>();
            outputParameters.AddOutput("*chart", chartList);
            ParameterBag chartParameters;

            if (k > 3)
            {
                chartParameters = new ParameterBag();
                chartList.Add(chartParameters);
                chartParameters.AddOutput("chart", ChartRendererFactory.PrepForLater(ChartType.BiasMA, new BiasMAOptions(rkr, rkx, rkw, k, "Relative risk", axll, axul, cco, cit, rmh, Transformation.Log, false)));
            }

            chartParameters = new ParameterBag();
            chartList.Add(chartParameters);
            chartParameters.AddOutput("chart", ChartRendererFactory.PrepForLater(ChartType.LAbbe, new LAbbeOptions(k, o, rmh)));

            chartParameters = new ParameterBag();
            chartList.Add(chartParameters);
            chartParameters.AddOutput("chart", ChartRendererFactory.PrepForLater(ChartType.MH, new MHOptions(1, k, rkw, title, rmh, ll, ul, cco, rkr, rkrl, rkru, lerr, uerr, included, "Relative risk meta-analysis plot (fixed effects)", 1, "relative risk")));

            chartParameters = new ParameterBag();
            chartList.Add(chartParameters);
            chartParameters.AddOutput("chart", ChartRendererFactory.PrepForLater(ChartType.MH, new MHOptions(1, k, dsw, title, dsrr, dsll, dsul, cco, rkr, rkrl, rkru, lerr, uerr, included, "Relative risk meta-analysis plot (random effects)", 1, "relative risk")));

            return outputParameters;
        }

        public static ParameterBag SChi(ITemplateHost host, ref double cco, double[,] o, int rows, int cols, bool doExact, bool doMonteCarlo, bool pc, bool xp, bool cs, bool xs, bool specifyScores, double mcci, int iterations, int seed)
        {
            double ul; double ll; double p; double c1;
            double p2 = 0; double p1 = 0;
            double vt = 0;
            double gtot = 0;

            double[,] ex = new double[rows + 1, cols + 1];
            double[,] cx = new double[rows + 1, cols + 1];
            double[,] dx = new double[rows + 1, cols + 1];
            double[] rtot = new double[rows + 1];
            double[] ctot = new double[cols + 1];
            double[] rowScore = new double[rows + 1];
            double[] colScore = new double[cols + 1];

            if (cco >= 1.0 || cco <= 0.0)
                cco = 0.95;
            double cit = PDF.gauinv(1.0 - (1.0 - cco) / 2.0);

            for (int r = 1; r <= rows; r++)
                rowScore[r] = r;
            for (int c = 1; c <= cols; c++)
                colScore[c] = c;
            /*
            bool sparse = false;
            for (int r = 1; r <= rows; r++)
            {
                for (int C = 1; C <= cols; C++)
                {
                    if (o[r, C] < 10.0)
                    {
                        sparse = true;
                    }
                }
            }
             */
            if (specifyScores)
            {
                xs = true;
                ScoresOptions sOptions = new() { Title1 = "Column Scores", Title2 = "Row Scores" };
                for (int r = 1; r <= rows; r++)
                    sOptions.Values1.Add(r);
                for (int c = 1; c <= cols; c++)
                    sOptions.Values2.Add(c);
                bool userOk = null != host.Amend(sOptions, null);
                if (userOk)
                {
                    for (int r = 1; r <= rows; r++)
                        rowScore[r] = sOptions.Values1[r - 1];
                    for (int c = 1; c <= cols; c++)
                        colScore[c] = sOptions.Values2[c - 1];
                }
                else
                {
                    specifyScores = false;
                }
            }

            double sumWeighted = 0;
            for (int r = 1; r <= rows; r++)
            {
                for (int c = 1; c <= cols; c++)
                {
                    rtot[r] += o[r, c];
                    ctot[c] += o[r, c];
                    gtot += o[r, c];
                    if (o[r, c] != Math.Floor(o[r, c]))
                        doExact = false;
                    sumWeighted += o[r, c] * rowScore[r] * colScore[c];
                }
            }
            if (gtot > 100000)
                doExact = false;

            double sumWtCol = 0.0;
            double sumWtSqCol = 0.0;
            int nzCols = 0;
            for (int c = 1; c <= cols; c++)
            {
                sumWtCol += ctot[c] * colScore[c];
                sumWtSqCol += ctot[c] * colScore[c] * colScore[c];
                if (ctot[c] > 0.0)
                    nzCols += 1;
            }

            double sumWtRow = 0.0;
            double sumWtSqRow = 0.0;
            int nzRows = 0;
            for (int r = 1; r <= rows; r++)
            {
                sumWtRow += rtot[r] * rowScore[r];
                sumWtSqRow += rtot[r] * rowScore[r] * rowScore[r];
                if (rtot[r] > 0.0)
                    nzRows += 1;
            }

            double dsrs = 0.0;
            for (int c = 1; c <= cols; c++)
            {
                double xi = 0.0;
                for (int r = 1; r <= rows; r++)
                    xi += rowScore[r] * o[r, c];
                if (ctot[c] != 0.0)
                    dsrs += xi * xi / ctot[c];
            }

            double sxx = sumWtSqRow - sumWtRow * sumWtRow / gtot;
            //  ANOVA style equality of variance test
            double x2Eq = (gtot - 1.0) / sxx * (dsrs - sumWtRow * sumWtRow / gtot);
            double syy = sumWtSqCol - sumWtCol * sumWtCol / gtot;
            double sxy = sumWeighted - sumWtCol * sumWtRow / gtot;
            //  Chi-square for linear trend
            double x2Trend = (gtot - 1.0) * (sxy * sxy) / (sxx * syy);

            //  sample correlation
            double corr = sumWeighted - sumWtRow * sumWtCol / gtot;
            corr /= Math.Sqrt((sumWtSqRow - Math.Pow(sumWtRow, 2.0) / gtot) * (sumWtSqCol - Math.Pow(sumWtCol, 2.0) / gtot));
            //  m2 from Agresti = x2trend from Armitage
            //  m2 = (gtot - 1) * corr * corr

            double x2 = 0.0;
            double g2 = 0.0;
            double n2 = Convert.ToDouble(nzRows - 1) * Convert.ToDouble(nzCols - 1);
            double n = Convert.ToDouble(nzRows) * Convert.ToDouble(nzCols);
            int trueN = rows * cols;
            int n1 = 0;
            int n5 = 0;

            // gamma - see Spiegel p293 & p58 Agresti
            double cc = 0.0;
            double dc = 0.0;
            for (int r = 1; r <= rows; r++)
            {
                for (int c = 1; c <= cols; c++)
                {
                    // concord
                    double conc = 0.0;
                    int i;
                    int j;
                    for (i = r + 1; i <= rows; i++)
                        for (j = c + 1; j <= cols; j++)
                            conc += o[i, j];
                    for (i = r - 1; i >= 1; i--)
                        for (j = c - 1; j >= 1; j--)
                            conc += o[i, j];
                    cc += o[r, c] * conc;
                    cx[r, c] = conc;
                    // discord
                    double disc = 0.0;
                    for (i = r + 1; i <= rows; i++)
                        for (j = c - 1; j >= 1; j--)
                            disc += o[i, j];
                    for (i = r - 1; i >= 1; i--)
                        for (j = c + 1; j <= cols; j++)
                            disc += o[i, j];
                    dc += o[r, c] * disc;
                    dx[r, c] = disc;
                }
            }
            double gamma = (cc - dc) / (cc + dc);

            //  variance of gamma
            double vg = 0.0;
            double vgi = 0.0;
            for (int r = 1; r <= rows; r++)
            {
                for (int c = 1; c <= cols; c++)
                {
                    vg += o[r, c] * Math.Pow(dc * cx[r, c] - cc * dx[r, c], 2.0);
                    vgi += o[r, c] * Math.Pow(cx[r, c] - dx[r, c], 2.0);
                }
            }
            vgi -= 1.0 / gtot * Math.Pow(cc - dc, 2.0);
            double seg = 4.0 / Math.Pow(cc + dc, 2.0) * Math.Sqrt(vg);
            double segi = 2.0 / (cc + dc) * Math.Sqrt(vgi);

            // tau-b
            double drx = 0.0;
            for (int r = 1; r <= rows; r++)
                drx += rtot[r] * rtot[r];
            drx = gtot * gtot - drx;
            double dcx = 0.0;
            for (int r = 1; r <= cols; r++)
                dcx += ctot[r] * ctot[r];
            dcx = gtot * gtot - dcx;
            double taub = (cc - dc) / Math.Sqrt(drx * dcx);

            // variance of tau-b
            double tsdd = 2.0 * Math.Sqrt(drx * dcx);
            for (int r = 1; r <= rows; r++)
            {
                for (int c = 1; c <= cols; c++)
                {
                    double vij = rtot[r] * dcx + ctot[c] * drx;
                    vt += o[r, c] * Math.Pow(tsdd * (cx[r, c] - dx[r, c]) + taub * vij, 2.0);
                }
            }
            vt -= Math.Pow(gtot, 3.0) * Math.Pow(taub, 2.0) * Math.Pow(drx + dcx, 2.0);
            double setaub = 1.0 / (drx * dcx) * Math.Sqrt(vt);
            double setaubi = 2.0 * Math.Sqrt(vgi / (drx * dcx));

            ParameterBag outputParameters = new();
            List<ParameterBag> rowsList = new();
            outputParameters.AddOutput("*rows", rowsList);
            for (int r = 1; r <= rows; r++)
            {
                ParameterBag rowsParameters = new();
                rowsList.Add(rowsParameters);

                List<ParameterBag> obsList = new();
                rowsParameters.AddOutput("*obs", obsList);
                // observed counts
                for (int c = 1; c <= cols; c++)
                {
                    ParameterBag obsParameters = new();
                    obsList.Add(obsParameters);
                    obsParameters.AddOutput("obs", o[r, c]);
                }

                // Use the last field for the totals
                List<ParameterBag> rtotList = new();
                rowsParameters.AddOutput("*rtot", rtotList);
                ParameterBag rtotParameters = new();
                rtotList.Add(rtotParameters);
                rtotParameters.AddOutput("rtot", rtot[r]);

                // trend score for row
                if (xs)
                {
                    List<ParameterBag> scoreList = new();
                    rowsParameters.AddOutput("*score", scoreList);
                    ParameterBag scoreParameters = new();
                    scoreList.Add(scoreParameters);
                    scoreParameters.AddOutput("score", rowScore[r]);
                }

                // expectation calculations
                for (int c = 1; c <= cols; c++)
                {
                    double ef = rtot[r] * ctot[c] / gtot;
                    ex[r, c] = ef;
                    if (ef < 1.0)
                        n1 += 1;
                    if (ef < 5.0)
                        n5 += 1;
                }

                // expected value for cell
                if (xp)
                {
                    List<ParameterBag> expsList = new();
                    rowsParameters.AddOutput("*exps", expsList);
                    ParameterBag expsParameters = new();
                    expsList.Add(expsParameters);
                    List<ParameterBag> expList = new();
                    expsParameters.AddOutput("*exp", expList);
                    for (int c = 1; c <= cols; c++)
                    {
                        ParameterBag expParameters = new();
                        expList.Add(expParameters);
                        expParameters.AddOutput("exp", ex[r, c]);
                    }
                }
                else
                {
                    rowsParameters.AddOutput("*exps", null);
                }

                // chi-square calculations
                for (int c = 1; c <= cols; c++)
                {
                    double ef = rtot[r] * ctot[c] / gtot;
                    if (ef != 0.0)
                    {
                        x2 += Math.Pow(o[r, c] - ef, 2.0) / ef;
                        if (o[r, c] != 0.0)
                            g2 += o[r, c] * Math.Log(o[r, c] / ef);
                    }
                }

                // cell chi-square
                if (cs)
                {
                    List<ParameterBag> chisList = new();
                    rowsParameters.AddOutput("*chis", chisList);
                    ParameterBag chisParameters = new();
                    chisList.Add(chisParameters);
                    List<ParameterBag> chiList = new();
                    chisParameters.AddOutput("*chi", chiList);
                    for (int c = 1; c <= cols; c++)
                    {
                        double dchi2 = ex[r, c] != 0.0 ? Math.Pow(o[r, c] - ex[r, c], 2.0) / ex[r, c] : Constant.MISSING;
                        ParameterBag chiParameters = new();
                        chiList.Add(chiParameters);
                        chiParameters.AddOutput("chi", dchi2);
                    }
                }

                // cell, row and column percentages
                if (pc)
                {
                    List<ParameterBag> pcrsList = new();
                    rowsParameters.AddOutput("*pcrs", pcrsList);
                    ParameterBag pcrsParameters = new();
                    pcrsList.Add(pcrsParameters);

                    List<ParameterBag> pcrList = new();
                    pcrsParameters.AddOutput("*pcr", pcrList);
                    for (int c = 1; c <= cols; c++)
                    {
                        ParameterBag pcrParameters = new();
                        pcrList.Add(pcrParameters);
                        pcrParameters.AddOutput("pcr", rtot[r] != 0.0 ? 100.0 * o[r, c] / rtot[r] : Constant.MISSING);
                    }

                    List<ParameterBag> pccList = new();
                    pcrsParameters.AddOutput("*pcc", pccList);
                    ParameterBag pccParameters;
                    for (int c = 1; c <= cols; c++)
                    {
                        pccParameters = new ParameterBag();
                        pccList.Add(pccParameters);
                        pccParameters.AddOutput("pcc", ctot[c] != 0.0 ? 100.0 * o[r, c] / ctot[c] : Constant.MISSING);
                    }
                    pccParameters = new ParameterBag();
                    pccList.Add(pccParameters);
                    pccParameters.AddOutput("pcc", 100.0 * rtot[r] / gtot);
                }
            }

            List<ParameterBag> totList = new();
            outputParameters.AddOutput("*tot", totList);
            ParameterBag totParameters;
            for (int c = 1; c <= cols; c++)
            {
                totParameters = new ParameterBag();
                totList.Add(totParameters);
                totParameters.AddOutput("tot", ctot[c]);
            }

            // Use the last col for the totals
            totParameters = new ParameterBag();
            totList.Add(totParameters);
            totParameters.AddOutput("tot", gtot);

            if (pc)
            {
                List<ParameterBag> pcgsList = new();
                outputParameters.AddOutput("*pcgs", pcgsList);
                ParameterBag pcgsParameters = new();
                pcgsList.Add(pcgsParameters);
                List<ParameterBag> pcgList = new();
                pcgsParameters.AddOutput("*pcg", pcgList);
                for (int c = 1; c <= cols; c++)
                {
                    ParameterBag pcgParameters = new();
                    pcgList.Add(pcgParameters);
                    pcgParameters.AddOutput("pcg", 100.0 * (ctot[c] / gtot));
                }
            }

            // trend scores for cols
            if (xs)
            {
                List<ParameterBag> scoresList = new();
                outputParameters.AddOutput("*scores", scoresList);
                ParameterBag scoresParameters = new();
                scoresList.Add(scoresParameters);
                List<ParameterBag> scoreList = new();
                scoresParameters.AddOutput("*score", scoreList);
                for (int c = 1; c <= cols; c++)
                {
                    ParameterBag scoreParameters = new();
                    scoreList.Add(scoreParameters);
                    scoreParameters.AddOutput("score", colScore[c]);
                }
            }

            outputParameters.AddOutput("tot", n);

            List<ParameterBag> warnList = new();
            outputParameters.AddOutput("*warn", warnList);
            if (n1 > 0)
            {
                ParameterBag warnParameters = new();
                warnList.Add(warnParameters);
                warnParameters.AddOutput("warn", Formatting.WRNCOLON + n1 + " out of " + trueN + " cells have EXPECTATION < 1");
            }

            if (n5 > 0)
            {
                ParameterBag warnParameters = new();
                warnList.Add(warnParameters);
                warnParameters.AddOutput("warn", Formatting.WRNCOLON + n5 + " out of " + trueN + " cells have EXPECTATION < 5");
            }

            g2 = 2.0 * g2;

            // Fisher's - by network algorithm
            // crashes if non integer observations or too large
            string lb = string.Empty;
            if (doExact && rows > 1 && cols > 1)
            {
                double emin = 1.0;
                double percnt = 80.0;
                Rcexact(rows, cols, o, 0.0, percnt, emin, ref p1, ref p2, out int ierr);
                if (ierr != 0)
                {
                    //  try hybrid approximation
                    lb = "(hybrid approximation)";
                    emin = 1.0; //  In case reset by first call
                    percnt = 80.0; //  In case reset by first call
                    Rcexact(rows, cols, o, 5.0, percnt, emin, ref p1, ref p2, out ierr);
                }
                if (ierr != 0)
                {
                    lb = string.Empty;
                    outputParameters.AddOutput("p2", "not possible, use Monte Carlo");
                }
                else
                {
                    outputParameters.AddOutput("p2", p2);
                }
            }
            else
            {
                lb = string.Empty;
                outputParameters.AddOutput("p2", "not calculated");
            }
            outputParameters.AddOutput("lb", lb);

            // Monte Carlo if required
            if (doMonteCarlo)
            {
                int ierrormc = 0;

                Chi.ChiRCResample(host, o, rowScore, colScore, rows, cols, iterations, x2, out int rx2, x2Eq, out int rx2Eq, x2Trend, out int rx2Trend, g2, out int rg2, out int actualIterations, seed, ref ierrormc);
                outputParameters.AddOutput("*pmcx2", new List<ParameterBag>() { Chi.MCResults(ierrormc, rx2, actualIterations, seed, mcci) });
                outputParameters.AddOutput("*pmcx2eq", new List<ParameterBag>() { Chi.MCResults(ierrormc, rx2Eq, actualIterations, seed, mcci) });
                outputParameters.AddOutput("*pmcx2trend", new List<ParameterBag>() { Chi.MCResults(ierrormc, rx2Trend, actualIterations, seed, mcci) });
                outputParameters.AddOutput("*pmcg2", new List<ParameterBag>() { Chi.MCResults(ierrormc, rg2, actualIterations, seed, mcci) });
            }

            // overall
            outputParameters.AddOutput("chio", x2);
            outputParameters.AddOutput("dfo", n2);
            outputParameters.AddOutput("po", PDF.chivalp(x2, n2));
            outputParameters.AddOutput("g2", g2);
            outputParameters.AddOutput("pog2", PDF.chivalp(g2, n2));

            // equality ANOVA (see Armitage)
            outputParameters.AddOutput("chie", x2Eq);
            outputParameters.AddOutput("dfe", nzCols - 1);
            outputParameters.AddOutput("pe", PDF.chivalp(x2Eq, nzCols - 1));

            // linear trend MH type (see Armitage)
            outputParameters.AddOutput("r", corr);
            outputParameters.AddOutput("chit", x2Trend);
            outputParameters.AddOutput("pt", PDF.chivalp(x2Trend, 1));

            // coefficients
            double phi = Math.Sqrt(x2 / gtot);
            outputParameters.AddOutput("phi", phi);
            p1 = Math.Sqrt(x2 / (x2 + gtot));
            outputParameters.AddOutput("pearson", p1);
            if (rows == 2 && cols == 2)
            {
                c1 = (o[1, 1] * o[2, 2] - o[1, 2] * o[2, 1]) / Math.Sqrt(rtot[1] * rtot[2] * ctot[1] * ctot[2]);
                outputParameters.AddOutput("cramer", c1);
                outputParameters.AddOutput("cramernote", "  (signed)");
            }
            else
            {
                c1 = Math.Sqrt(x2 / gtot / Math.Min(rows - 1, cols - 1));
                outputParameters.AddOutput("cramer", c1);
            }

            // ordinal
            outputParameters.AddOutput("gamma", gamma);
            if (seg != 0.0)
            {
                p = 1.0 - PDF.alnorm(gamma / seg);
                if (p > 1.0 - p)
                    p = 2.0 * (1.0 - p);
                else
                    p = 2.0 * p;
                ll = gamma - cit * seg;
                ul = gamma + cit * seg;
            }
            else
            {
                p = Constant.MISSING;
                ll = Constant.MISSING;
                ul = Constant.MISSING;
            }
            outputParameters.AddOutput("seg", seg);
            outputParameters.AddOutput("pg", p);
            outputParameters.AddOutput("pc", cco * 100.0);
            outputParameters.AddOutput("llg", ll);
            outputParameters.AddOutput("ulg", ul);

            if (segi != 0.0)
            {
                p = 1.0 - PDF.alnorm(gamma / segi);
                if (p > 1.0 - p)
                    p = 2.0 * (1.0 - p);
                else
                    p = 2.0 * p;
                ll = gamma - cit * segi;
                ul = gamma + cit * segi;
            }
            else
            {
                p = Constant.MISSING;
                ll = Constant.MISSING;
                ul = Constant.MISSING;
            }
            outputParameters.AddOutput("segi", segi);
            outputParameters.AddOutput("pgi", p);
            outputParameters.AddOutput("llgi", ll);
            outputParameters.AddOutput("ulgi", ul);

            outputParameters.AddOutput("taub", taub);
            if (setaub != 0.0)
            {
                p = 1.0 - PDF.alnorm(taub / setaub);
                if (p > 1.0 - p)
                    p = 2.0 * (1.0 - p);
                else
                    p = 2.0 * p;
                ll = taub - cit * setaub;
                ul = taub + cit * setaub;
            }
            else
            {
                p = Constant.MISSING;
                ll = Constant.MISSING;
                ul = Constant.MISSING;
            }
            outputParameters.AddOutput("setaub", setaub);
            outputParameters.AddOutput("ptaub", p);
            outputParameters.AddOutput("lltaub", ll);
            outputParameters.AddOutput("ultaub", ul);

            //  outputParameters.AddOutput("taub", taub)
            if (setaubi != 0.0)
            {
                p = 1.0 - PDF.alnorm(taub / setaubi);
                if (p > 1.0 - p)
                    p = 2.0 * (1.0 - p);
                else
                    p = 2.0 * p;
                ll = taub - cit * setaubi;
                ul = taub + cit * setaubi;
            }
            else
            {
                p = Constant.MISSING;
                ll = Constant.MISSING;
                ul = Constant.MISSING;
            }
            outputParameters.AddOutput("setaubi", setaubi);
            outputParameters.AddOutput("ptaubi", p);
            outputParameters.AddOutput("lltaubi", ll);
            outputParameters.AddOutput("ultaubi", ul);
            return outputParameters;
        }

        private static ParameterBag TabMh(IPreferencesAndProgressBar host, double cco, int zcats, double[,,] zt, Namevar[] zcat)
        {
            const int lowerBound = 1;

            if (cco <= 0)
                cco = 0.95;
            double cit = PDF.gauinv(1.0 - ((1.0 - cco) / 2.0));
            int k = zcats;
            string[] title = new string[k + lowerBound];
            for (int i = lowerBound; i < lowerBound + k; i++)
            {
                title[i] = zcat[i].Title;
                if (title[i].Length > 50)
                    title[i] = title[i].Substring(0, 50);
            }

            double[,] o = new double[k + lowerBound, 4 + 1];
            double[] axll = new double[k + lowerBound];
            double[] axul = new double[k + lowerBound];
            for (int i = lowerBound; i < lowerBound + k; i++)
            {
                o[i, 4] = zt[1, 1, i];
                o[i, 3] = zt[1, 2, i];
                o[i, 2] = zt[2, 1, i];
                o[i, 1] = zt[2, 2, i];
            }

            Meta.Mantel(host, lowerBound, k, out int realk, o, out double rmh, out double ll, out double ul, out double x2, out double sk, cit, cco, out double[] odr, out double[] odw, out double[] dswt, out double[] odrl, out double[] odru, out double[] odx, out bool[] lerr, out bool[] uerr, out double qc, out double bd, out double dsor, out double dsx2, out double dsll, out double dsul, out bool[] cced, out double tausq, out bool[] included, out int ierr);
            if (ierr != 0)
            {
                if (ierr != 99)
                    throw new InvalidDataException();
                return null;
            }

            // Try exact Mantel
            Rec2X2[] tbl = new Rec2X2[k + lowerBound];
            for (int i = lowerBound; i < lowerBound + k; i++)
            {
                tbl[i].Freq = 1;
                tbl[i].A = o[i, 1];
                tbl[i].M1 = o[i, 1] + o[i, 2];
                tbl[i].N1 = o[i, 1] + o[i, 3];
                tbl[i].N0 = o[i, 2] + o[i, 4];
                tbl[i].IsInformative = o[i, 1] * o[i, 4] != 0.0 || o[i, 2] * o[i, 3] != 0.0;
            }
            bool useLogScale = false;
            new ExactBB().Exact22K(host, lowerBound, k, Exact22KDataType.Type1, tbl, cco, out double eor, out double ulf, out double llf, out double ulm, out double llm, out double p1F, out double p2F, out double p1M, out double p2M, ref useLogScale, out ierr);
            if (ierr != 0)
            {
                eor = Constant.MISSING;
                ulf = Constant.MISSING;
                llf = Constant.MISSING;
                ulm = Constant.MISSING;
                llm = Constant.MISSING;
                p1F = Constant.MISSING;
                p2F = Constant.MISSING;
                p1M = Constant.MISSING;
                p2M = Constant.MISSING;
            }

            ParameterBag outputParameters = new();
            List<ParameterBag> inputsList = new();
            outputParameters.AddOutput("*inputs", inputsList);
            for (int i = lowerBound; i < lowerBound + k; i++)
            {
                ParameterBag inputsParameters = new();
                inputsList.Add(inputsParameters);
                inputsParameters.AddOutput("st", i);
                inputsParameters.AddOutput("a", o[i, 1]);
                inputsParameters.AddOutput("b", o[i, 2]);
                inputsParameters.AddOutput("c", o[i, 3]);
                inputsParameters.AddOutput("d", o[i, 4]);
                inputsParameters.AddOutput("lb", string.Empty);
            }
            outputParameters.AddOutput("pc", cco * 100);
            outputParameters.AddOutput("method", host.Preferences.MetaExact ? "CML" : "logit");

            List<ParameterBag> orList = new();
            outputParameters.AddOutput("*or", orList);
            for (int i = lowerBound; i < lowerBound + k; i++)
            {
                ParameterBag orParameters = new();
                orList.Add(orParameters);
                orParameters.AddOutput("st", i);
                orParameters.AddOutput("or", odr[i]);
                orParameters.AddOutput("yi", odr[i] > 0 ? Math.Log(odr[i]) : 0);
                orParameters.AddOutput("vi", Meta.VarianceFromCI(odrl[i], odru[i], cit, true));
                orParameters.AddOutput("lci", odrl[i]);
                orParameters.AddOutput("uci", odru[i]);
                orParameters.AddOutput("wt", 100 * odw[i] / Formatting.dsum(odw, 1));
                orParameters.AddOutput("dwt", 100 * dswt[i] / Formatting.dsum(dswt, 1));
                string tmp = Meta.GetMetaLabel(host, o, i, true, cced, title);
                if (host.Preferences.DelayContinuityCorrection)
                    tmp = tmp.Replace("[CC", "[late CC");
                orParameters.AddOutput("lb", tmp);

                //orParameters.AddOutput("lb", Meta.GetMetaLabel(host, o, i,  true, cced, title));
                //if (host.Preferences.MetaExact & ((i) == Constant.MISSING | odru[i] == Constant.MISSING))
                //{
                //    Meta.OrciCorn(host, ref cco, ref o[i, 1], ref o[i, 2], ref o[i, 3], ref o[i, 4], out odr[i], out odrl[i], out odru[i]);
                //    orParameters = new ParameterBag();
                //    orList.Add(orParameters);
                //    orParameters.AddOutput("st", "* " + i.ToString());
                //    orParameters.AddOutput("or", string.Empty);
                //    orParameters.AddOutput("lci", host.RoundU(odrl[i]));
                //    orParameters.AddOutput("uci", host.RoundU(odru[i]));
                //    orParameters.AddOutput("wt", string.Empty);
                //    orParameters.AddOutput("dwt", string.Empty);
                //    orParameters.AddOutput("lb", " * [Cornfield limits]");
                //}
            }

            if (sk == 0)
            {
                outputParameters.AddOutput("meth", "Sato");
                outputParameters.AddOutput("odds", "undefined");
                outputParameters.AddOutput("from", ll);
                outputParameters.AddOutput("to", double.PositiveInfinity);
            }
            else
            {
                outputParameters.AddOutput("meth", "Robins-Breslow-Greenland");
                outputParameters.AddOutput("odds", rmh);
                outputParameters.AddOutput("from", ll);
                outputParameters.AddOutput("to", ul);
            }
            outputParameters.AddOutput("chi_mantel", x2);
            outputParameters.AddOutput("chi_p", PDF.chivalp(x2, 1.0));

            List<ParameterBag> cmlList = new();
            outputParameters.AddOutput("*cml", cmlList);
            if (ierr != -9)
            {
                ParameterBag cmlParameters = new();
                cmlList.Add(cmlParameters);
                cmlParameters.AddOutput("eor", eor);
                cmlParameters.AddOutput("pc", cco * 100);
                cmlParameters.AddOutput("llf", llf);
                cmlParameters.AddOutput("ulf", ulf);
                cmlParameters.AddOutput("p1f", p1F);
                cmlParameters.AddOutput("p2f", p2F);
                cmlParameters.AddOutput("llm", llm);
                cmlParameters.AddOutput("ulm", ulm);
                cmlParameters.AddOutput("p1m", p1M);
                cmlParameters.AddOutput("p2m", p2M);
            }

            outputParameters.AddOutput("bd", bd);
            outputParameters.AddOutput("df", realk - 1);
            outputParameters.AddOutput("xp", PDF.chivalp(bd, realk - 1));

            outputParameters.AddOutput("qc", qc);
            outputParameters.AddOutput("df_cochran", realk - 1);
            outputParameters.AddOutput("xp_cochran", PDF.chivalp(qc, realk - 1));
            outputParameters.AddOutput("tausq", tausq);
            Meta.IsquareNcc(host, qc, realk, cco, cit, out double isq, out double llisq, out double ulisq);
            outputParameters.AddOutput("isq", isq);
            outputParameters.AddOutput("pc1", cco * 100);
            outputParameters.AddOutput("llisq", llisq);
            outputParameters.AddOutput("ulisq", ulisq);

            outputParameters.AddOutput("dsor", dsor);
            outputParameters.AddOutput("dsll", dsll);
            outputParameters.AddOutput("dsul", dsul);
            outputParameters.AddOutput("dsx2", dsx2);
            outputParameters.AddOutput("df_ds", 1);
            outputParameters.AddOutput("xp_ds", PDF.chivalp(dsx2, 1.0));

            Meta.GetLogitCi(host, o, k, cit, axll, axul);

            IList<ParameterBag> eggerList = new List<ParameterBag>();
            outputParameters.AddOutput("*egger", eggerList);
            ParameterBag eggerParameters = new();
            eggerList.Add(eggerParameters);
            Meta.Metabias(host, eggerParameters, odr, axll, axul, k, ref cco, Transformation.Log);

            IList<ParameterBag> harbordList = new List<ParameterBag>();
            outputParameters.AddOutput("*harbord", harbordList);
            ParameterBag harbordParameters = new();
            harbordList.Add(harbordParameters);
            Meta.ModMetabias(host, harbordParameters, o, k, cco, 1);

            IList<ParameterBag> chartList = new List<ParameterBag>();
            outputParameters.AddOutput("*chart", chartList);
            ParameterBag chartParameters;

            if (k > 3)
            {
                chartParameters = new ParameterBag();
                chartList.Add(chartParameters);
                chartParameters.AddOutput("chart", ChartRendererFactory.PrepForLater(ChartType.BiasMA, new BiasMAOptions(odr, odx, odw, k, "Odds ratio", axll, axul, cco, cit, rmh, Transformation.Log, false)));
            }

            chartParameters = new ParameterBag();
            chartList.Add(chartParameters);
            chartParameters.AddOutput("chart", ChartRendererFactory.PrepForLater(ChartType.LAbbe, new LAbbeOptions(k, o, rmh)));

            if (sk != 0)
            {
                chartParameters = new ParameterBag();
                chartList.Add(chartParameters);
                chartParameters.AddOutput("chart", ChartRendererFactory.PrepForLater(ChartType.MH, new MHOptions(1, k, odw, title, rmh, ll, ul, cco, odr, odrl, odru, lerr, uerr, included, "Odds ratio meta-analysis plot [fixed effects]", 1, "odds ratio")));

                chartParameters = new ParameterBag();
                chartList.Add(chartParameters);
                chartParameters.AddOutput("chart", ChartRendererFactory.PrepForLater(ChartType.MH, new MHOptions(1, k, dswt, title, dsor, dsll, dsul, cco, odr, odrl, odru, lerr, uerr, included, "Odds ratio meta-analysis plot [random effects]", 1, "odds ratio")));
            }

            return outputParameters;
        }

        private static bool XSymmetrical(int xcats, Namevar[] xcat, int ycats, Namevar[] ycat, bool strict)
        {
            if (strict)
            {
                for (int i = 1; i <= Math.Min(xcats, ycats); i++)
                    if (xcat[i].Title != ycat[i].Title)
                        return false;
            }
            return xcats == ycats;
        }


        ///  <summary>
        ///  Generalised Cochran Mantel Haenszel test
        ///  </summary>
        public static void Gencmh(int istrata, int irows, int icols, double[] table, double[] rowscr, double[] colscr, int itype, out double x2, out double df, out double p, out int ierr)
        {
            double[,] stat = new double[istrata + 2, 3 + 1];
            int[] nclval = new int[3 + 1];
            const int indcol = 1;
            nclval[indcol] = icols;
            const int indrow = 3;
            nclval[indrow] = irows;
            nclval[2] = istrata;
            Cmhexec(3, nclval, table, indrow, indcol, itype, 0, 0, rowscr, colscr, stat, istrata + 1, out ierr);
            x2 = stat[istrata + 1, 1];
            df = stat[istrata + 1, 2];
            p = stat[istrata + 1, 3];
        }

        public static void Cmhexec(int nclvar, int[] nclval, double[] table, int indrow, int indcol, int itype, int irowsc, int icolsc, double[] rowscr, double[] colscr, double[,] res, int ldres, out int ierr)
        {

            int i;

            ierr = 0;
            if (nclvar <= 1)
            {
                ierr = 1;
                return;
            }
            if (indrow <= 0 || indrow > nclvar)
            {
                ierr = 2;
                return;
            }
            if (indcol <= 0 || indcol > nclvar)
            {
                ierr = 3;
                return;
            }
            if (itype < 1 || itype > 3)
            {
                ierr = 4;
                return;
            }
            int iq = 1;
            for (i = 1; i <= nclvar; i++)
            {
                if (nclval[i] <= 0)
                {
                    ierr = 5;
                    return;
                }
                iq *= nclval[i];
            }
            int ir = nclval[indrow];
            if (ir <= 1)
            {
                ierr = 6;
                return;
            }
            int ic = nclval[indcol];
            if (ic <= 1)
            {
                ierr = 7;
                return;
            }
            if (ir > 1 && ic > 1)
            {
                iq = (int)Math.Floor((double)iq / (ir * ic));
                if (ldres <= iq)
                {
                    ierr = 8;
                    return;
                }
            }
            // redim(workspace)
            ir = nclval[indrow];
            ic = nclval[indcol];
            int[] ix = new int[nclvar + 1];
            double[] f = new double[2 * ir * ic + 1];
            double[] rowsum = new double[2 * ir + 1];
            double[] colsum = new double[2 * ic + 1];
            double[] difvec = new double[2 + 1];
            double[] difsum = new double[2 + 1];
            double[] cov = new double[2 + 1];
            double[] covsum = new double[2 + 1];
            double[] awk = new double[2 + 1];
            double[] bwk = new double[2 + 1];
            if (itype == 1)
            {
                int itmp = (ir - 1) * (ic - 1);
                try
                {
                    difvec = new double[2 * itmp + 1];
                    difsum = new double[2 * itmp + 1];
                    cov = new double[2 * itmp * itmp + 1];
                    covsum = new double[2 * itmp * itmp + 1];
                    awk = new double[2 * (ir - 1) * (ir - 1) + 1];
                    bwk = new double[2 * (ic - 1) * (ic - 1) + 1];
                }
                catch (OutOfMemoryException)
                {
                    ierr = 9;
                    return;
                }
            }
            else if (itype == 2)
            {
                try
                {
                    difvec = new double[2 * ir + 1];
                    difsum = new double[2 * ir + 1];
                    cov = new double[2 * ir * ir + 1];
                    covsum = new double[2 * ir * ir + 1];
                    awk = new double[2 * ir + 1];
                }
                catch (OutOfMemoryException)
                {
                    ierr = 10;
                    return;
                }
            }
            // call(kernel)
            Cmhgo(nclvar, nclval, table, indrow, indcol, itype, irowsc, icolsc, rowscr, colscr, res, ldres, ix, f, colsum, rowsum, difvec, difsum, cov, covsum, awk, bwk, ref ierr);
        }

        public static void Cmhgo(int nclvar, int[] nclval, double[] table, int indrow, int indcol, int itype, int irowsc, int icolsc, double[] rowscr, double[] colscr, double[,] stat, int ldstat, int[] ix, double[] f, double[] colsum, double[] rowsum, double[] difvec, double[] difsum, double[] cov, double[] covsum, double[] awk, double[] bwk, ref int ierr)
        {
            int i, iq = 0;

            if (nclvar <= 1)
            {
                ierr = 1;
                return;
            }
            if (indrow <= 0 || indrow > nclvar)
            {
                ierr = 2;
                return;
            }
            if (indcol <= 0 || indcol > nclvar)
            {
                ierr = 3;
                return;
            }
            if (itype < 1 || itype > 3)
            {
                ierr = 4;
                return;
            }
            int lentbl = 1;
            for (i = 1; i <= nclvar; i++)
            {
                if (nclval[i] <= 0)
                {
                    ierr = 5;
                    return;
                }
                lentbl *= nclval[i];
            }
            int ir = nclval[indrow];
            if (ir <= 1)
            {
                ierr = 6;
                return;
            }
            int ic = nclval[indcol];
            if (ic <= 1)
            {
                ierr = 7;
                return;
            }
            if (ir > 1 & ic > 1)
            {
                iq = (int)Math.Floor((double)lentbl / (ir * ic));
                if (ldstat <= iq)
                {
                    ierr = 8;
                    return;
                }
            }
            bool aleqal;
            if (irowsc < 0 || irowsc > 5)
            {
                ierr = 9;
                return;
            }
            if (irowsc == 0 & (itype == 2 | itype == 3) & ic >= 2)
            {
                i = 2;
                do
                {
                    if (rowscr[1] != rowscr[i])
                    {
                        aleqal = false;
                        break;
                    }
                    if (i < ic)
                        i++;
                } while (true);
                if (aleqal)
                {
                    ierr = 10;
                    return;
                }
            }
            if (icolsc < 0 || icolsc > 5)
            {
                ierr = 11;
                return;
            }
            if (icolsc == 0 & itype == 3 & ir >= 2)
            {
                i = 2;
                do
                {
                    if (colscr[1] != colscr[i])
                    {
                        aleqal = false;
                        break;
                    }
                    if (i < ir)
                        i++;
                }
                while (true);
                if (aleqal)
                {
                    ierr = 12;
                    return;
                }
            }
            for (i = 1; i <= lentbl; i++)
            {
                if (table[i] < 0.0)
                {
                    ierr = 13;
                    return;
                }
            }
            i = nclvar;
            int incrow = 1;
            int inccol = 1;
            do
            {
                if (i > indrow && i > 1)
                {
                    incrow *= nclval[i];
                    i -= 1;
                }
                else
                {
                    break;
                }
            }
            while (true);
            i = nclvar;
            do
            {
                if (i > indcol & i > 1)
                {
                    inccol *= nclval[i];
                    i -= 1;
                }
                else
                {
                    break;
                }
            }
            while (true);
            if (itype == 1)
            {
                // method based on each whole table
                Cmhall(nclvar, nclval, table, indrow, indcol, stat, ldstat, incrow, inccol, f, ix, colsum, rowsum, difvec, difsum, cov, covsum, awk, bwk, ref ierr);
            }
            else
            {
                int m;
                int j;
                if (irowsc == 1)
                {
                    for (j = 1; j <= ic; j++)
                        rowscr[j] = j;
                }
                else if (irowsc == 2)
                {
                    for (j = 1; j <= ic; j++)
                        colsum[j] = 0.0;
                    for (j = 1; j <= nclvar; j++)
                        ix[j] = 1;
                    for (m = 1; m <= iq; m++)
                    {
                        if (m > 1)
                            Cmhidx(nclvar, nclval, indrow, indcol, ix);
                        Cmhgetct(table, ir, ic, incrow, inccol, indrow, indcol, nclvar, nclval, f, ix);
                        for (j = 1; j <= ic; j++)
                            for (i = ir * (j - 1) + 1; i <= ir * (j - 1) + ir; i++)
                                colsum[j] = colsum[j] + f[i];
                    }
                    Cmhrcs(irowsc, ic, lentbl, colsum, table, rowscr);
                    for (j = 1; j <= nclvar; j++)
                        ix[j] = 1;
                }
                if (itype == 2)
                {
                    //        method based on table mean scores
                    Cmhmean(nclvar, nclval, table, indrow, indcol, irowsc, rowscr, stat, ldstat, incrow, inccol, f, ix, colsum, rowsum, difvec, difsum, cov, covsum, awk, ref ierr);
                }
                else
                {
                    if (icolsc == 1)
                    {
                        for (i = 1; i <= ir; i++)
                            colscr[i] = i;
                    }
                    else if (icolsc == 2)
                    {
                        for (j = 1; j <= ir; j++)
                            rowsum[j] = 0.0;
                        for (j = 1; j <= nclvar; j++)
                            ix[j] = 1;
                        for (m = 1; m <= iq; m++)
                        {
                            if (m > 1)
                                Cmhidx(nclvar, nclval, indrow, indcol, ix);
                            Cmhgetct(table, ir, ic, incrow, inccol, indrow, indcol, nclvar, nclval, f, ix);
                            for (i = 1; i <= ir; i++)
                            {
                                for (j = i; j < i + ic * ir; j += ir)
                                {
                                    rowsum[i] = rowsum[i] + f[j];
                                }
                                // rowsum(i) = rowsum(i) + dsum(ic, f(i), ir)
                            }
                        }
                        Cmhrcs(icolsc, ir, lentbl, rowsum, table, colscr);
                        for (j = 1; j <= nclvar; j++)
                            ix[j] = 1;
                    }
                    //        method based on each table's correlation
                    Cmhcorr(nclvar, nclval, table, indrow, indcol, irowsc, icolsc, rowscr, colscr, stat, ldstat, incrow, inccol, f, ix, colsum, rowsum, out difsum[1], out covsum[1], ref ierr);
                }
            }

        }

        public static void Cmhall(int nclvar, int[] nclval, double[] table, int indrow, int indcol, double[,] res, int ldres, int incrow, int inccol, double[] f, int[] ix, double[] colsum, double[] rowsum, double[] difvec, double[] difsum, double[] cov, double[] covsum, double[] awk, double[] bwk, ref int ierr)
        {
            int i, j, m;

            double tol = Math.Sqrt(Constant.EPSILON);
            int ir = nclval[indrow];
            int ic = nclval[indcol];
            int lentbl = 1;
            for (i = 1; i <= nclvar; i++)
                lentbl *= nclval[i];
            int iq = (int)Math.Floor((double)lentbl / (ir * ic));
            int nzt = iq;
            int lm1 = (ir - 1) * (ic - 1);
            int lm2 = lm1 * lm1;
            for (i = 1; i <= lm2; i++)
                covsum[i] = 0.0;
            for (i = 1; i <= lm1; i++)
                difsum[i] = 0.0;
            for (i = 1; i <= nclvar; i++)
                ix[i] = 1;
            //      loop through each table
            for (m = 1; m <= iq; m++)
            {
                // extract(table)
                if (m > 1)
                    Cmhidx(nclvar, nclval, indrow, indcol, ix);
                Cmhgetct(table, ir, ic, incrow, inccol, indrow, indcol, nclvar, nclval, f, ix);
                // totals()
                double rnh = 0.0;
                int nzc = ic;
                int j1 = 1;
                double tmp;
                for (j = 1; j <= ic; j++)
                {
                    tmp = 0.0;
                    for (i = j1; i < j1 + ir; i++)
                        tmp += f[i];
                    rnh += tmp;
                    colsum[j] = tmp;
                    if (colsum[j] < tol)
                    {
                        nzc -= 1;
                        colsum[j] = 0.0;
                    }
                    j1 += ir;
                }
                if (rnh < tol)
                {
                    res[m, 1] = Constant.MISSING;
                    res[m, 2] = Constant.MISSING;
                    res[m, 3] = Constant.MISSING;
                    nzt -= 1;
                }
                else
                {
                    int nzr = ir;
                    for (i = 1; i <= ir; i++)
                    {
                        rowsum[i] = 0.0;
                        for (int k = i; k < i + ic * ir; k += ir)
                            rowsum[i] = rowsum[i] + f[k];
                        if (rowsum[i] < tol)
                        {
                            nzr -= 1;
                            rowsum[i] = 0.0;
                        }
                    }
                    // main(stats)
                    tmp = 0.0;
                    int ij = 1;
                    for (j = 1; j <= ic; j++)
                    {
                        for (i = 1; i <= ir; i++)
                        {
                            if (colsum[j] > tol & rowsum[i] > tol)
                                tmp += Math.Pow(f[ij] - colsum[j] * rowsum[i] / rnh, 2.0) / (colsum[j] * rowsum[i] / rnh);
                            ij += 1;
                        }
                    }
                    res[m, 1] = (rnh - 1) / rnh * tmp;
                    res[m, 2] = (nzr - 1) * (nzc - 1);
                    if (res[m, 2] < tol)
                        res[m, 3] = Constant.MISSING;
                    else
                        res[m, 3] = PDF.chivalp(res[m, 1], res[m, 2]);
                    // covariance()
                    if (rnh != 1.0)
                    {
                        Cmhcov(ir, ic, lm1, rowsum, colsum, rnh, f, difvec, cov, awk, bwk);
                        for (j = 1; j <= lm1; j++)
                            difsum[j] = difsum[j] + difvec[j];
                        tmp = rnh * rnh / (rnh - 1.0);
                        j1 = 1;
                        for (j = 1; j <= lm1; j++)
                        {
                            for (i = j1; i < j1 + lm1; i++)
                                covsum[i] = covsum[i] + tmp * cov[i];
                            j1 += lm1;
                        }
                    }
                }
            }
            if (nzt > 0)
            {
                tol = 100 * Constant.EPSILON;
                Matrix.mxfac(lm1, covsum, lm1, tol, ref m, cov, lm1, ref ierr);
                Matrix.transrxb(lm1, cov, lm1, difsum, lm1, ref m, difvec, lm1, cov, lm1, ref ierr);
                res[iq + 1, 2] = m;
                res[iq + 1, 1] = 0.0;
                for (j = 1; j <= lm1; j++)
                    res[iq + 1, 1] = res[iq + 1, 1] + difvec[j] * difvec[j];
                if (res[iq + 1, 2] > 0.0)
                    res[iq + 1, 3] = PDF.chivalp(res[iq + 1, 1], res[iq + 1, 2]);
                else
                    res[iq + 1, 3] = Constant.MISSING;
            }
            else
            {
                res[iq + 1, 1] = Constant.MISSING;
                res[iq + 1, 2] = Constant.MISSING;
                res[iq + 1, 3] = Constant.MISSING;
            }
        }

        private static void Cmhmean(int nclvar, int[] nclval, double[] table, int indrow, int indcol, int irowsc, double[] rowscr, double[,] res, int ldres, int incrow, int inccol, double[] f, int[] ix, double[] colsum, double[] rowsum, double[] difvec, double[] difsum, double[] cov, double[] covsum, double[] fh, ref int ierr)
        {
            int ij;
            double tol = Math.Sqrt(Constant.EPSILON);
            int ir = nclval[indrow];
            int ic = nclval[indcol];
            int lentbl = 1;
            for (int i = 1; i <= nclvar; i++)
                lentbl *= nclval[i];
            int iq = (int)Math.Floor((double)lentbl / (ir * ic));
            int nzt = iq;
            for (int i = 1; i <= ir * ir; i++)
                covsum[i] = 0.0;
            for (int i = 1; i <= ir; i++)
                difsum[i] = 0.0;
            for (int i = 1; i <= nclvar; i++)
                ix[i] = 1;
            //      loop thro table stats
            for (int m = 1; m <= iq; m++)
            {
                //       find first element of table and pack it into matrix
                if (m > 1)
                    Cmhidx(nclvar, nclval, indrow, indcol, ix);
                Cmhgetct(table, ir, ic, incrow, inccol, indrow, indcol, nclvar, nclval, f, ix);
                // totals()
                double rnh = 0.0;
                int j1 = 1;
                for (int j = 1; j <= ic; j++)
                {
                    colsum[j] = 0.0;
                    for (int i = j1; i < j1 + ir; i++)
                        colsum[j] = colsum[j] + f[i];
                    rnh += colsum[j];
                    j1 += ir;
                }
                if (rnh < tol)
                {
                    //        all counts 0 so exclude table
                    res[m, 1] = Constant.MISSING;
                    res[m, 2] = Constant.MISSING;
                    res[m, 3] = Constant.MISSING;
                    nzt -= 1;
                }
                else
                {
                    int nzr = ir;
                    for (int i = 1; i <= ir; i++)
                    {
                        rowsum[i] = 0.0;
                        for (int j = i; j < i + ic * ir; j += ir)
                            rowsum[i] = rowsum[i] + f[j];
                        if (rowsum[i] < tol)
                        {
                            nzr -= 1;
                            rowsum[i] = 0.0;
                        }
                    }
                    //       scores and their means
                    if (irowsc > 2)
                    {
                        lentbl = ir * ic;
                        Cmhrcs(irowsc, ic, lentbl, colsum, f, rowscr);
                    }
                    double tmp;
                    for (int i = 1; i <= ir; i++)
                    {
                        ij = i;
                        if (rowsum[i] < tol)
                        {
                            fh[i] = 0.0;
                        }
                        else
                        {
                            tmp = 0.0;
                            for (int j = 1; j <= ic; j++)
                            {
                                tmp += rowscr[j] * f[ij];
                                ij += ir;
                            }
                            fh[i] = tmp / rowsum[i];
                        }
                    }
                    double abar = 0.0;
                    for (int j = 1; j <= ic; j++)
                        abar += rowscr[j] * colsum[j] / rnh;

                    // total(variance)
                    double dela = 0.0;
                    for (int j = 1; j <= ic; j++)
                        dela += Math.Pow(rowscr[j] - abar, 2.0) * colsum[j] / rnh;

                    //       between populations variance
                    double delf = 0.0;
                    for (int i = 1; i <= ir; i++)
                        delf += Math.Pow(fh[i] - abar, 2.0) * rowsum[i] / rnh;
                    if (dela > tol)
                    {
                        res[m, 1] = (rnh - 1.0) * delf / dela;
                        res[m, 2] = nzr - 1;
                        if (res[m, 2] > tol)
                            res[m, 3] = PDF.chivalp(res[m, 1], res[m, 2]);
                        else
                            res[m, 3] = Constant.MISSING;
                    }
                    else
                    {
                        // zero(variance)
                        res[m, 1] = 0.0;
                        res[m, 2] = 0.0;
                        res[m, 3] = Constant.MISSING;
                    }
                    //       row col score covariance
                    if (rnh != 1.0)
                    {
                        tmp = dela * rnh * rnh / (rnh - 1.0);
                        for (int i = 1; i <= ir; i++)
                        {
                            ij = i;
                            for (int j = 1; j <= ir; j++)
                            {
                                if (i == j)
                                    cov[ij] = rowsum[i] / rnh;
                                else
                                    cov[ij] = 0.0;
                                cov[ij] = tmp * (cov[ij] - rowsum[i] * rowsum[j] / (rnh * rnh));
                                covsum[ij] = covsum[ij] + cov[ij];
                                ij += ir;
                            }
                            // obs(-exp)
                            difvec[i] = rowsum[i] * (fh[i] - abar);
                            difsum[i] = difsum[i] + difvec[i];
                        }
                    }
                }
            }
            //      covariance matrix of different estimates
            ij = 1;
            int irir = ir * ir;
            int irj = ir;
            int iir = (ir - 1) * ir;
            for (int j = 1; j < ir; j++)
            {
                difvec[j] = difsum[j] - difsum[ir];
                for (int i = 1; i < ir; i++)
                {
                    cov[ij] = covsum[ij] - covsum[irj] - covsum[iir + i] + covsum[irir];
                    ij += 1;
                }
                ij += 1;
                irj += ir;
            }
            if (nzt > 0)
            {
                tol = 100 * Constant.EPSILON;
                int m = 0;
                Matrix.mxfac(ir - 1, cov, ir, tol, ref m, cov, ir, ref ierr);
                Matrix.transrxb(ir - 1, cov, ir, difvec, ir, ref m, difvec, ir, cov, ir, ref ierr);
                res[iq + 1, 2] = m;
                res[iq + 1, 1] = 0.0;
                for (int i = 1; i < ir; i++)
                    res[iq + 1, 1] = res[iq + 1, 1] + difvec[i] * difvec[i];
                if (res[iq + 1, 2] > 0.0)
                    res[iq + 1, 3] = PDF.chivalp(res[iq + 1, 1], res[iq + 1, 2]);
                else
                    res[iq + 1, 3] = Constant.MISSING;
            }
            else
            {
                res[iq + 1, 1] = Constant.MISSING;
                res[iq + 1, 2] = Constant.MISSING;
                res[iq + 1, 3] = Constant.MISSING;
            }

        }

        private static void Cmhcorr(int nclvar, int[] nclval, double[] table, int indrow, int indcol, int irowsc, int icolsc, double[] rowscr, double[] colscr, double[,] res, int ldres, int incrow, int inccol, double[] f, int[] ix, double[] colsum, double[] rowsum, out double difsum, out double covsum, ref int ierr)
        {
            double tol = Math.Sqrt(Constant.EPSILON);
            int ir = nclval[indrow];
            int ic = nclval[indcol];
            int lentbl = 1;
            for (int i = 1; i <= nclvar; i++)
            {
                lentbl *= nclval[i];
            }
            int iq = (int)Math.Floor((double)lentbl / (ir * ic));
            difsum = 0.0;
            covsum = 0.0;
            for (int i = 1; i <= nclvar; i++)
            {
                ix[i] = 1;
            }
            //      loop through stratum stats
            for (int m = 1; m <= iq; m++)
            {
                //       find first element of table and pack table into a matrix
                if (m > 1)
                {
                    Cmhidx(nclvar, nclval, indrow, indcol, ix);
                }
                Cmhgetct(table, ir, ic, incrow, inccol, indrow, indcol, nclvar, nclval, f, ix);
                // totals()
                double rnh = 0.0;
                int j1 = 1;
                int j;
                for (j = 1; j <= ic; j++)
                {
                    colsum[j] = 0.0;
                    for (int i = j1; i < j1 + ir; i++)
                    {
                        colsum[j] = colsum[j] + f[i];
                    }
                    rnh += colsum[j];
                    j1 += ir;
                }
                if (rnh < tol)
                {
                    //        all frequencies zero - exclude stratum
                    res[m, 1] = Constant.MISSING;
                    res[m, 2] = Constant.MISSING;
                    res[m, 3] = Constant.MISSING;
                }
                else
                {

                    for (int i = 1; i <= ir; i++)
                    {
                        rowsum[i] = 0.0;
                        for (j = i; j < i + ic * ir; j += ir)
                        {
                            rowsum[i] = rowsum[i] + f[j];
                        }
                    }
                    //       row and col scores and their means
                    if (icolsc > 2)
                    {
                        lentbl = ir * ic;
                        Cmhrcs(icolsc, ir, lentbl, rowsum, f, colscr);
                    }
                    if (irowsc > 2)
                    {
                        lentbl = ir * ic;
                        Cmhrcs(irowsc, ic, lentbl, colsum, f, rowscr);
                    }
                    double abar = 0.0;
                    for (j = 1; j <= ic; j++)
                    {
                        abar += rowscr[j] * colsum[j] / rnh;
                    }
                    double bbar = 0.0;
                    for (int i = 1; i <= ir; i++)
                    {
                        bbar += colscr[i] * rowsum[i] / rnh;
                    }
                    //       row score variance
                    double dela = 0.0;
                    for (j = 1; j <= ic; j++)
                    {
                        dela += Math.Pow(rowscr[j] - abar, 2.0) * colsum[j] / rnh;
                    }
                    //       col score variance
                    double delb = 0.0;
                    for (int i = 1; i <= ir; i++)
                    {
                        delb += Math.Pow(colscr[i] - bbar, 2.0) * rowsum[i] / rnh;
                    }
                    //       row and col score covariance
                    double delab = 0.0;
                    for (int i = 1; i <= ir; i++)
                    {
                        int ij = i;
                        for (j = 1; j <= ic; j++)
                        {
                            delab += (rowscr[j] - abar) * (colscr[i] - bbar) * f[ij] / rnh;
                            ij += ir;
                        }
                    }
                    if (dela > tol & delb > tol)
                    {
                        res[m, 1] = (rnh - 1.0) * delab * delab / (dela * delb);
                        res[m, 2] = 1.0;
                        res[m, 3] = PDF.chivalp(res[m, 1], res[m, 2]);
                    }
                    else
                    {
                        // zero(variance)
                        res[m, 1] = 0.0;
                        res[m, 2] = 0.0;
                        res[m, 3] = Constant.MISSING;
                    }
                    if (rnh != 1.0)
                    {
                        difsum += rnh * delab;
                        covsum += rnh * rnh * dela * delb / (rnh - 1.0);
                    }
                }
            }
            if (covsum > tol)
            {
                res[iq + 1, 1] = difsum * difsum / covsum;
                res[iq + 1, 2] = 1.0;
                res[iq + 1, 3] = PDF.chivalp(res[iq + 1, 1], res[iq + 1, 2]);
            }
            else
            {
                res[iq + 1, 1] = Constant.MISSING;
                res[iq + 1, 2] = Constant.MISSING;
                res[iq + 1, 3] = Constant.MISSING;
            }

        }

        ///  <summary>
        ///  unpack stratified contingency table into y
        ///  </summary>
        public static void Cmhgetct(double[] table, int ir, int ic, int incrow, int inccol, int indrow, int indcol, int nclvar, int[] nclval, double[] y, int[] ix)
        {
            int i1 = ix[nclvar];
            int iprod = 1;

            for (int j = nclvar - 1; j >= 1; j--)
            {
                iprod *= nclval[j + 1];
                i1 += (ix[j] - 1) * iprod;
            }
            int ii = 1;
            for (int i = 1; i <= ic; i++)
            {
                y[ii] = table[i1];
                for (int j = 2; j <= ir; j++)
                {
                    ii += 1;
                    y[ii] = table[i1 + (j - 1) * incrow];
                }
                i1 += inccol;
                ii += 1;
            }

        }

        ///  <summary>
        ///  o-e covariance
        ///  </summary>
        public static void Cmhcov(int ir, int ic, int lm1, double[] rowsum, double[] colsum, double rnh, double[] f, double[] difvec, double[] cov, double[] a, double[] b)
        {
            int irx = ir - 1;
            int icx = ic - 1;
            for (int i = 1; i <= irx; i++)
                for (int j = 1; j <= irx; j++)
                    a[j + (i - 1) * ir] = 0.0;
            for (int j = 1; j <= icx; j++)
                for (int i = 1; i <= icx; i++)
                    b[i + (j - 1) * ic] = 0.0;
            for (int i = 1; i <= irx; i++)
            {
                double tmp = rowsum[i] / (rnh * rnh);
                a[i + (i - 1) * ir] = rnh * tmp;
                for (int j = 1; j < ir; j++)
                {
                    int ii = i + (j - 1) * ir;
                    a[ii] = a[ii] - tmp * rowsum[j];
                }
            }
            for (int i = 1; i <= icx; i++)
            {
                double tmp = colsum[i] / (rnh * rnh);
                b[i + (i - 1) * ic] = rnh * tmp;
                for (int j = 1; j <= icx; j++)
                {
                    int ii = i + (j - 1) * ic;
                    b[ii] = b[ii] - tmp * colsum[j];
                }
            }
            int icount = 0;
            int jcount = 0;
            for (int i = 1; i <= irx; i++)
            {
                for (int j = 1; j <= icx; j++)
                {
                    icount += 1;
                    difvec[icount] = f[i + (j - 1) * ir] - rowsum[i] * colsum[j] / rnh;
                    int k;
                    for (k = 1; k <= irx; k++)
                    {
                        int ii = i + (k - 1) * ir;
                        for (int l = 1; l <= icx; l++)
                        {
                            jcount += 1;
                            cov[jcount] = a[ii] * b[j + (l - 1) * ic];
                        }
                    }
                }
            }
        }

        ///  <summary>
        ///  row and column scores
        ///  </summary>
        public static void Cmhrcs(int iscore, int len, int lentbl, double[] sum, double[] table, double[] ab)
        {
            double tblsum = 0;

            if (iscore != 3)
            {
                tblsum = 0.0;
                for (int i = 1; i <= lentbl; i++)
                    tblsum += table[i];
            }
            if (iscore == 5)
            {
                ab[1] = 1.0 - sum[1] / tblsum;
                for (int i = 2; i <= len; i++)
                {
                    tblsum -= sum[i - 1];
                    if (tblsum != 0.0)
                        ab[i] = ab[i - 1] - sum[i] / tblsum;
                    else
                        ab[i] = Constant.MISSING; // nan
                }
            }
            else
            {
                double cumsum = 0.0;
                for (int i = 1; i <= len; i++)
                {
                    ab[i] = (sum[i] + 1.0) / 2.0 + cumsum;
                    if (iscore != 3)
                        ab[i] = ab[i] / tblsum;
                    cumsum += sum[i];
                }
            }
        }

        ///  <summary>
        ///  finds the index entry of a contingency table in the vector ix
        ///  </summary>
        ///  <param name="nclvar"></param>
        ///  <param name="nclval"></param>
        ///  <param name="indrow"></param>
        ///  <param name="indcol"></param>
        ///  <param name="ix"></param>
        ///  <remarks></remarks>
        public static void Cmhidx(int nclvar, int[] nclval, int indrow, int indcol, int[] ix)
        {
            int im = nclvar;
            do
            {
                bool skip = false;
                if (im == indrow || im == indcol)
                {
                    im--;
                    if (im > 0)
                        skip = true;
                }
                if (!skip)
                {
                    if (ix[im] < nclval[im])
                    {
                        if (im != nclvar)
                        {
                            for (int i = im + 1; i <= nclvar; i++)
                                ix[i] = 1;
                        }
                        ix[im] = ix[im] + 1;
                        break;
                    }
                    im--;
                    if (im <= 0)
                        break;
                }
            }
            while (true);

        }

        ///  <summary>
        ///   fisher exact test and hybrid approximation (if expect is not 0)
        ///  </summary>
        ///  <remarks>
        ///   using mehta and patel network algorithm with clarkson and fan modifications for the cumulative probability of a table at least as extreme
        ///   derived from:
        ///   ALGORITHM 643, COLLECTED ALGORITHMS FROM ACM. VOL.19(4), DECEMBER, 1993, PP. 484-488.
        ///  </remarks>
        private static void Rcexact(int nrow, int ncol, double[,] table, double expect, double percnt, double emin, ref double prt, ref double pre, out int ierr)
        {
            ierr = 0;
            try
            {
                int i;
                int ldkey, ldstp;
                int[] ifrq; int[] ipoin;
                int[] key; int[] key2;
                double[] dlp; double[] dsp;
                double[] stp; double[] tm;
                int ntot = 0;
                for (i = 1; i <= nrow; i++)
                {
                    int j;
                    for (j = 1; j <= ncol; j++)
                    {
                        if (table[i, j] < 0.0)
                        {
                            ierr = 1;
                            return;
                        }
                        ntot += (int)Math.Floor(table[i, j]);
                    }
                }
                if (ntot == 0)
                {
                    ierr = 2;
                    prt = Constant.MISSING;
                    pre = Constant.MISSING;
                    return;
                }
                int nco = Math.Max(nrow, ncol);
                int nro = Math.Min(nrow, ncol);
                // int k = nrow + ncol + 1; 
                // int kk = k * Math.Max( nrow, ncol );
                double[] fact = new double[2 * (ntot + 1) + 1];
                int[] ico = new int[nco + 1];
                int[] iro = new int[nco + 1];
                int[] kyy = new int[nco + 1];
                int[] idif = new int[nro + 1];
                int[] irn = new int[nro + 1];
                //IEB 23 Dec 14 increased from 2000000
                int i4 = 20000000;
                int i5 = 20000000;
                if (i4 != i5)
                    ldkey = (i4 - 17) / 318;
                else
                    ldkey = (i4 - 17) / 254;
                do
                {
                    ldstp = 30 * ldkey;
                    try
                    {
                        key = new int[2 * ldkey + 1];
                        ipoin = new int[2 * ldkey + 1];
                        stp = new double[4 * ldstp + 1];
                        ifrq = new int[6 * ldstp + 1];
                        dlp = new double[4 * ldkey + 1];
                        dsp = new double[4 * ldkey + 1];
                        tm = new double[4 * ldkey + 1];
                        key2 = new int[2 * ldkey + 1];
                        break;
                    }
                    catch (Exception)
                    {
                        ldkey /= 2;
                    }
                }
                while (true);

                RcExactGo(nrow, ncol, table, expect, percnt, emin, ref prt, out pre, ref fact, ref ico, ref iro, ref kyy, ref idif, ref irn, ref key, ref ldkey, ref ipoin, ref stp, ref ldstp, ref ifrq, ref dlp, ref dsp, ref tm, ref key2, ref ierr);
            }
            //IEB 23 Dec 14: don't just catch overflow error so change from catch (OverflowException) to catch (Exception)
            catch (Exception)
            {
                ierr = int.MaxValue;
                prt = Constant.MISSING;
                pre = Constant.MISSING;
            }
        }

        ///  <summary>
        ///   fisher exact test and hybrid approximation (if expect is not 0)
        ///  </summary>
        ///  <remarks>
        ///   using mehta and patel network algorithm with clarkson and fan modifications for the cumulative probability of a table at least as extreme
        ///   derived from:
        ///   ALGORITHM 643, COLLECTED ALGORITHMS FROM ACM. VOL.19(4), DECEMBER, 1993, PP. 484-488.
        ///  </remarks>
        private static void RcExactGo(int nrow, int ncol, double[,] table, double expect, double percnt, double emin, ref double prt, out double pre, ref double[] fact, ref int[] ico, ref int[] iro, ref int[] kyy, ref int[] idif, ref int[] irn, ref int[] key, ref int ldkey, ref int[] ipoin, ref double[] stp, ref int ldstp, ref int[] ifrq, ref double[] dlp, ref double[] dsp, ref double[] tm, ref int[] key2, ref int ierr)
        {
            bool chisq = false;
            double tmp = 0;
            int i;
            int itp = 0,
                itpx = 0,
                j, kmax, kval = 0, nco;
            int nro;

            int ircmax = Math.Max(nrow, ncol);
            int ircmin = Math.Min(nrow, ncol);
            int ircp1 = nrow + ncol + 1;
            int k = Math.Max(ircp1, ircmax);
            // internal
            int[] icx = new int[ircmax + 1];
            int[] irx = new int[ircmin + 1];
            // longpath
            // IEB 23 Dec 14: extended workspace as over shoot in long path with Big_Fisher.xls test data second set
            //int[,] iiwk1 = new int[ircmax + 1, ircmax + 1];
            int[,] iiwk1 = new int[ircp1 + 1, ircp1 + 1];
            int[,] iiwk2 = new int[nrow + 1, ircp1 + 1];
            // shortpath
            int[] iwk1 = new int[k + 1];
            int[] iwk2 = new int[k + 1];
            int[] iwk3 = new int[k + 1];
            int[] iwk4 = new int[k + 1];
            int[] iwk5 = new int[k + 1];
            int[] iwk6 = new int[ircmax + 1];
            int[] iwk7 = new int[ircmax + 1];
            // IEB 23 Dec 14 extended workspace from 400 to 4000 as example second from end in big Fisher.xls over ran
            int[] iwk8 = new int[4000 + 1];
            int[] iwk9 = new int[4000 + 1];
            double[] rwk1 = new double[4000 + 1];
            double[] rwk2 = new double[k + 1];

            double tol = Math.Sqrt(Constant.EPSILON);
            //                                   initialize key array
            for (i = 1; i <= 2 * ldkey; i++)
            {
                key[i] = -9999;
                key2[i] = -9999;
            }
            //                                   initialize parameters
            pre = 0.0;
            int itop = 0;
            double emn = expect > 0.0 ? emin : int.MaxValue;

            //                                   compute row marginals and total
            int ntot = 0;
            for (i = 1; i <= nrow; i++)
            {
                iro[i] = 0;
                for (j = 1; j <= ncol; j++)
                {
                    if (table[i, j] < 0.0)
                    {
                        ierr = 1;
                        return;
                    }
                    double transTemp9 = table[i, j];
                    iro[i] = iro[i] + (int)Math.Floor(transTemp9);
                    ntot += (int)Math.Floor(transTemp9);
                }
            }

            if (ntot == 0)
            {
                prt = Constant.MISSING;
                pre = Constant.MISSING;
                ierr = 2;
                return;
            }
            //                                   column marginals
            for (i = 1; i <= ncol; i++)
            {
                ico[i] = 0;
                for (j = 1; j <= nrow; j++)
                {
                    double transTemp11 = table[j, i];
                    ico[i] = ico[i] + (int)Math.Floor(transTemp11);
                }
            }
            // (sort)
            Array.Sort(iro, 1, nrow);
            Array.Sort(ico, 1, ncol);

            //                                   determine row and column marginals

            if (nrow > ncol)
            {
                nro = ncol;
                nco = nrow;
                for (i = 1; i <= nrow; i++)
                    kyy[i] = iro[i];
                for (i = 1; i <= ncol; i++)
                    iro[i] = ico[i];
                for (i = 1; i <= nrow; i++)
                    ico[i] = kyy[i];
            }
            else
            {
                nro = nrow;
                nco = ncol;
            }

            //                                   get multiplers for stack
            kyy[1] = 1;

            j = int.MaxValue; // largest integer magnitude
            for (i = 2; i <= nro; i++)
            {
                //                                   hash table multipliers
                if (iro[i - 1] + 1 <= j / kyy[i - 1])
                {
                    kyy[i] = kyy[i - 1] * (iro[i - 1] + 1);
                    j /= kyy[i - 1];
                }
                else
                {
                    ierr = 5;
                    return;
                }
            }
            //                                   maximum product
            if (iro[nro - 1] + 1 <= j / kyy[nro - 1])
            {
                kmax = (iro[nro] + 1) * kyy[nro - 1];
            }
            else
            {
                ierr = 6;
                return;
            }
            //                                   compute log factorials
            fact[0] = 0.0;
            fact[1] = 0.0;
            if (ntot >= 2)
                fact[2] = Math.Log(2.0);
            for (i = 3; i <= ntot; i += 2)
            {
                fact[i] = fact[i - 1] + Math.Log(Convert.ToDouble(i));
                j = i + 1;
                if (j <= ntot)
                    fact[j] = fact[i] + fact[2] + fact[j / 2] - fact[j / 2 - 1];
            }
            //                                   compute observed path length: obs
            double obs = tol;
            ntot = 0;
            for (j = 1; j <= nco; j++)
            {
                double dd = 0.0;
                for (i = 1; i <= nro; i++)
                {
                    if (nrow <= ncol)
                    {
                        double transTemp12 = table[i, j];
                        dd += fact[(int)Math.Floor(transTemp12)];
                    }
                    else
                    {
                        double transTemp13 = table[j, i];
                        dd += fact[(int)Math.Floor(transTemp13)];
                    }
                }
                obs = obs + fact[ico[j]] - dd;
                ntot += ico[j];
            }
            //      denominator of observed table, dro, as multinomial coefficient from log factorials
            double dro = fact[ntot];
            for (i = 1; i <= nro; i++)
                dro -= fact[iro[i]];

            prt = Math.Exp(obs - dro);
            //                                   initialize pointers
            k = nco;
            int last = ldkey + 1;
            int jkey = ldkey + 1;
            int jstp = ldstp + 1;
            int jstp2 = 3 * ldstp + 1;
            int jstp3 = 4 * ldstp + 1;
            int jstp4 = 5 * ldstp + 1;
            int ikkey = 0;
            int ikstp = 0;
            int ikstp2 = 2 * ldstp;
            int ipo = 1;
            ipoin[1] = 1;
            stp[1] = 0.0;
            ifrq[1] = 1;
            ifrq[ikstp2 + 1] = -1;

            do
            {
                int kb = nco - k + 1;
                int ks = 0;
                int n = ico[kb];
                int kd = nro + 1;
                kmax = nro;
                //                                   idif is the difference in going to the daughter
                for (i = 1; i <= nro; i++)
                {
                    idif[i] = 0;
                }
                //                                   generate the first daughter
                do
                {
                    kd -= 1;
                    ntot = Math.Min(n, iro[kd]);
                    idif[kd] = ntot;
                    if (idif[kmax] == 0)
                    {
                        kmax -= 1;
                    }
                    n -= ntot;
                    if (n <= 0 | kd == 1)
                    {
                        break;
                    }
                }
                while (true);
                int iflag;
                if (n == 0)
                {

                    int k1 = k - 1;
                    n = ico[kb];
                    ntot = 0;
                    for (i = kb + 1; i <= nco; i++)
                    {
                        ntot += ico[i];
                    }

                    // outer
                    do
                    {
                        //                                   arc to daughter length = ico(kb)
                        for (i = 1; i <= nro; i++)
                        {
                            irn[i] = iro[i] - idif[i];
                        }
                        //                                   sort irn
                        int nro2;
                        int nrb;
                        int ii;
                        if (k1 <= 1)
                        {
                            nrb = 1;
                            nro2 = nro;
                        }
                        else
                        {
                            if (nro == 2)
                            {
                                if (irn[1] > irn[2])
                                {
                                    ii = irn[1];
                                    irn[1] = irn[2];
                                    irn[2] = ii;
                                }
                            }
                            else if (nro == 3)
                            {
                                ii = irn[1];
                                if (ii > irn[3])
                                {
                                    if (ii <= irn[2])
                                    {
                                        irn[1] = irn[3];
                                        irn[3] = irn[2];
                                        irn[2] = ii;
                                    }
                                    else if (irn[2] > irn[3])
                                    {
                                        irn[1] = irn[3];
                                        irn[3] = ii;
                                    }
                                    else
                                    {
                                        irn[1] = irn[2];
                                        irn[2] = irn[3];
                                        irn[3] = ii;
                                    }
                                }
                                else if (ii > irn[2])
                                {
                                    irn[1] = irn[2];
                                    irn[2] = ii;
                                }
                                else if (irn[2] > irn[3])
                                {
                                    ii = irn[2];
                                    irn[2] = irn[3];
                                    irn[3] = ii;
                                }
                            }
                            else
                            {
                                for (j = 2; j <= nro; j++)
                                {
                                    i = j - 1;
                                    ii = irn[j];
                                    do
                                    {
                                        if (ii >= irn[i])
                                        {
                                            break;
                                        }
                                        irn[i + 1] = irn[i];
                                        i -= 1;
                                        if (i <= 0)
                                        {
                                            break;
                                        }
                                    }
                                    while (true);
                                    irn[i + 1] = ii;
                                }
                            }
                            //                                   adjust start for zero
                            for (i = 1; i <= nro; i++)
                            {
                                if (irn[i] != 0)
                                {
                                    break;
                                }
                            }
                            nrb = i;
                            nro2 = nro - i + 1;
                        }
                        //                                   some table values
                        double ddf = fact[n];
                        for (i = 1; i <= nro; i++)
                        {
                            ddf -= fact[idif[i]];
                        }

                        double drn = fact[ntot];
                        for (i = nrb; i < nrb + nro2; i++)
                            drn -= fact[irn[i]];
                        drn = drn - dro + ddf;
                        //                                   get hash value
                        if (k1 > 1)
                        {
                            kval = irn[1] + irn[2] * kyy[2];
                            for (i = 3; i <= nro; i++)
                                kval += irn[i] * kyy[i];
                            //                                   get hash table entry
                            i = kval % 2 * ldkey + 1;
                            //                                   search for unused location
                            bool found = false;
                            for (itp = i; itp <= 2 * ldkey; itp++)
                            {
                                ii = key2[itp];
                                if (ii == kval)
                                {
                                    found = true;
                                    break;
                                }
                                if (ii < 0)
                                {
                                    key2[itp] = kval;
                                    dlp[itp] = 1.0;
                                    dsp[itp] = 1.0;
                                    found = true;
                                    break;
                                }
                            }

                            if (!found)
                            {
                                for (itp = 1; itp < i; itp++)
                                {
                                    ii = key2[itp];
                                    if (ii == kval)
                                    {
                                        found = true;
                                        break;
                                    }
                                    if (ii < 0)
                                    {
                                        key2[itp] = kval;
                                        dlp[itp] = 1.0;
                                        found = true;
                                        break;
                                    }
                                }
                            }

                            if (found == false)
                            {
                                ierr = 7;
                                return;
                            }
                        }

                        bool ipsh = true;
                        //                                   recover pastp
                        int ipn = ipoin[ipo + ikkey];
                        double pastp = stp[ipn + ikstp];
                        int ifreq = ifrq[ipn + ikstp];
                        //                                   compute shortest and longest path
                        double df;
                        double obs2;
                        double obs3;
                        if (k1 <= 1)
                        {
                            obs2 = obs - drn - dro;
                            obs3 = obs2;
                        }
                        else
                        {
                            obs2 = obs - fact[ico[kb + 1]] - fact[ico[kb + 2]] - ddf;
                            for (i = 3; i <= k1; i++)
                            {
                                obs2 -= fact[ico[kb + i]];
                            }

                            if (dlp[itp] > 0.0)
                            {
                                double dspt = obs - obs2 - ddf;
                                //                                   compute shortest path
                                dlp[itp] = 0.0;
                                for (i = 1; i <= irn.Length - nrb; i++)
                                {
                                    irx[i] = irn[nrb - 1 + i];
                                }
                                for (i = 1; i <= ico.Length - (kb + 1); i++)
                                {
                                    icx[i] = ico[kb + i];
                                }
                                Shortpath(nro2, irx, k1, icx, ref dlp[itp], ntot, fact, tol, ref ierr, iwk1, iwk2, iwk3, iwk4, iwk5, iwk6, iwk7, iwk8, iwk9, rwk2, rwk1);
                                if (ierr != 0)
                                {
                                    return;
                                }
                                dlp[itp] = Math.Min(0.0, dlp[itp]);
                                //                                   compute longest path
                                dsp[itp] = dspt;
                                Longpath(ircmax, nro2, irx, k1, icx, ref dsp[itp], fact, tol, iiwk1, iwk1, iwk2, iwk3, iwk4, iwk5, iiwk2, rwk2);
                                dsp[itp] = Math.Min(0.0, dsp[itp] - dspt);
                                //                                   use chi-squared approximation?
                                if (Convert.ToDouble(irn[nrb] * ico[kb + 1]) / Convert.ToDouble(ntot) <= emn)
                                {
                                    tm[itp] = Constant.MISSING;
                                }
                                else
                                {
                                    int ncell = 0;
                                    for (i = 1; i <= nro2; i++)
                                    {
                                        for (j = 1; j <= k1; j++)
                                        {
                                            if (irn[nrb + i - 1] * ico[kb + j] >= ntot * expect)
                                            {
                                                ncell += 1;
                                            }
                                        }
                                    }
                                    if (ncell * 100 < k1 * nro2 * percnt)
                                    {
                                        tm[itp] = Constant.MISSING;
                                    }
                                    else
                                    {
                                        tmp = 0.0;
                                        for (i = 1; i <= nro2; i++)
                                        {
                                            tmp = tmp + fact[irn[nrb + i - 1]] - fact[irn[nrb + i - 1] - 1];
                                        }
                                        tmp *= (k1 - 1);
                                        for (j = 1; j <= k1; j++)
                                        {
                                            tmp += (nro2 - 1) * (fact[ico[kb + j]] - fact[ico[kb + j] - 1]);
                                        }
                                        df = (nro2 - 1) * (k1 - 1);
                                        tmp += df * 1.8378770664093456; // 1.83787706640934548356065947281
                                        tmp -= (nro2 * k1 - 1) * (fact[ntot] - fact[ntot - 1]);
                                        tm[itp] = -2.0 * (obs - dro) - tmp;
                                    }
                                }
                            }
                            obs3 = obs2 - dlp[itp];
                            obs2 -= dsp[itp];
                            if (tm[itp] == Constant.MISSING)
                            {
                                chisq = false;
                            }
                            else
                            {
                                chisq = true;
                                tmp = tm[itp];
                            }
                        }
                        // inner
                        do
                        {
                            //                                   process node with new pastp
                            if (pastp <= obs3)
                            {
                                //                                   update pre
                                pre += Convert.ToDouble(ifreq) * Math.Exp(pastp + drn);

                            }
                            else if (pastp < obs2)
                            {
                                if (chisq)
                                {
                                    df = (nro2 - 1) * (k1 - 1);
                                    double pv = PDF.chivalp(Math.Max(0.0, tmp + 2.0 * (pastp + drn)), df);
                                    pre += Convert.ToDouble(ifreq) * Math.Exp(pastp + drn) * pv;
                                }
                                else
                                {
                                    //                                   put daughter on queue
                                    Pushnode(pastp + ddf, tol, kval, key, jkey, ldkey, ipoin, stp, jstp, ldstp, ifrq, jstp2, jstp3, jstp4, ifreq, ref itop, ipsh, ref itpx, ref ierr);
                                    ipsh = false;
                                    if (ierr != 0)
                                    {
                                        return;
                                    }
                                }
                            }

                            // get next pastp on chain
                            ipn = ifrq[ipn + ikstp2];
                            if (ipn > 0)
                            {
                                pastp = stp[ipn + ikstp];
                                ifreq = ifrq[ipn + ikstp];
                            }
                            else
                            {
                                // make a new sibling node
                                Sibling(kmax, iro, idif, ref kd, ref ks, out iflag);
                                break; // exit the inner loop and then exit the outer loop if ifag is set to 1
                            }
                        }
                        while (true);
                        if (iflag == 1)
                        {
                            break;
                        }

                    }
                    while (true);

                }
                do
                {

                    //            fetch a new parent from stage k
                    iflag = 1;
                    Popnode(nro, iro, ref iflag, kyy, key, ldkey, ref last, ref ipo, ikkey + 1);

                    //                                   update pointers
                    if (iflag != 3)
                    {
                        break;
                    }
                    k -= 1;
                    itop = 0;
                    ikkey = jkey - 1;
                    ikstp = jstp - 1;
                    ikstp2 = jstp2 - 1;
                    jkey = ldkey - jkey + 2;
                    jstp = ldstp - jstp + 2;
                    jstp2 = 2 * ldstp + jstp;
                    for (i = 1; i <= 2 * ldkey; i++)
                    {
                        key2[i] = -9999;
                    }
                    if (k < 2)
                    {
                        return;
                    }
                }
                while (true);

            }
            while (true);

        }

        /// <summary>
        /// longest path for a given table (network algorithm)
        /// </summary>
        private static void Longpath(int kd, int nrow, int[] irow, int ncol, int[] icol, ref double dsp, double[] fact, double tol, int[,] icstk, int[] ncstk, int[] lstk, int[] mstk, int[] nstk, int[] nrstk, int[,] irstk, double[] ystk)
        {
            if (nrow == 1)
            {
                for (int i = 1; i <= ncol; i++)
                    dsp -= fact[icol[i]];
                return;
            }
            if (ncol == 1)
            {
                for (int i = 1; i <= nrow; i++)
                    dsp -= fact[irow[i]];
                return;
            }
            if (nrow * ncol == 4)
            {
                if (irow[2] <= icol[2])
                    dsp = dsp - fact[irow[2]] - fact[icol[1]] - fact[icol[2] - irow[2]];
                else
                    dsp = dsp - fact[icol[2]] - fact[irow[1]] - fact[irow[2] - icol[2]];
                return;
            }
            for (int i = 1; i <= nrow; i++)
                irstk[i, 1] = irow[nrow - i + 1];
            for (int j = 1; j <= ncol; j++)
                icstk[j, 1] = icol[ncol - j + 1];
            int nro = nrow;
            int nco = ncol;
            nrstk[1] = nro;
            ncstk[1] = nco;
            ystk[1] = 0.0;
            double y = 0.0;
            int istk = 1;
            int l = 1;
            double amx = 0.0;
            int ir1 = irstk[1, istk];
            int ic1 = icstk[1, istk];
            int m, n;
            if (ir1 > ic1)
            {
                if (nro >= nco)
                {
                    m = nco - 1;
                    n = 2;
                }
                else
                {
                    m = nro;
                    n = 1;
                }
            }
            else if (ir1 < ic1)
            {
                if (nro <= nco)
                {
                    m = nro - 1;
                    n = 1;
                }
                else
                {
                    m = nco;
                    n = 2;
                }
            }
            else
            {
                if (nro <= nco)
                {
                    m = nro - 1;
                    n = 1;
                }
                else
                {
                    m = nco - 1;
                    n = 2;
                }
            }
            do
            {
                int i, j;
                if (n == 1)
                {
                    i = l;
                    j = 1;
                }
                else
                {
                    i = 1;
                    j = l;
                }
                int irt = irstk[i, istk];
                int ict = icstk[j, istk];
                int mn = irt;
                if (mn > ict)
                {
                    mn = ict;
                }
                y += fact[mn];
                int k;
                if (irt == ict)
                {
                    nro -= 1;
                    nco -= 1;
                    for (k = 1; k < i; k++)
                        irstk[k, istk + 1] = irstk[k, istk];
                    for (k = i; k <= nro; k++)
                        irstk[k, istk + 1] = irstk[k + 1, istk];
                    for (k = 1; k < j; k++)
                        icstk[k, istk + 1] = icstk[k, istk];
                    for (k = j; k <= nco; k++)
                        icstk[k, istk + 1] = icstk[k + 1, istk];
                }
                else
                {
                    bool skip;
                    if (irt > ict)
                    {
                        nco -= 1;
                        for (k = 1; k < j; k++)
                            icstk[k, istk + 1] = icstk[k, istk];
                        for (k = j; k <= nco; k++)
                            icstk[k, istk + 1] = icstk[k + 1, istk];
                        for (k = 1; k < i; k++)
                            irstk[k, istk + 1] = irstk[k, istk];
                        skip = false;
                        for (k = i; k < nro; k++)
                        {
                            if (irt - ict >= irstk[k + 1, istk])
                            {
                                skip = true;
                                break;
                            }
                            irstk[k, istk + 1] = irstk[k + 1, istk];
                        }
                        if (!skip)
                            k = nro;
                        irstk[k, istk + 1] = irt - ict;
                        do
                        {
                            k += 1;
                            if (k > nro)
                                break;
                            irstk[k, istk + 1] = irstk[k, istk];
                        }
                        while (true);
                    }
                    else
                    {
                        nro -= 1;
                        for (k = 1; k < i; k++)
                            irstk[k, istk + 1] = irstk[k, istk];
                        for (k = i; k <= nro; k++)
                            irstk[k, istk + 1] = irstk[k + 1, istk];
                        for (k = 1; k < j; k++)
                            icstk[k, istk + 1] = icstk[k, istk];
                        skip = false;
                        for (k = j; k < nco; k++)
                        {
                            if (ict - irt >= icstk[k + 1, istk])
                            {
                                skip = true;
                                break;
                            }
                            icstk[k, istk + 1] = icstk[k + 1, istk];
                        }
                        if (!skip)
                            k = nco;
                        icstk[k, istk + 1] = ict - irt;
                        do
                        {
                            k += 1;
                            if (k > nco)
                                break;
                            icstk[k, istk + 1] = icstk[k, istk];
                        }
                        while (true);
                    }
                }
                bool skip3;
                if (nro == 1)
                {
                    for (k = 1; k <= nco; k++)
                        y += fact[icstk[k, istk + 1]];
                    skip3 = false;
                }
                else if (nco == 1)
                {
                    for (k = 1; k <= nro; k++)
                        y += fact[irstk[k, istk + 1]];
                    skip3 = false;
                }
                else
                {
                    lstk[istk] = l;
                    mstk[istk] = m;
                    nstk[istk] = n;
                    istk += 1;
                    nrstk[istk] = nro;
                    ncstk[istk] = nco;
                    ystk[istk] = y;
                    l = 1;
                    if (ir1 > ic1)
                    {
                        if (nro >= nco)
                        {
                            m = nco - 1;
                            n = 2;
                        }
                        else
                        {
                            m = nro;
                            n = 1;
                        }
                    }
                    else if (ir1 < ic1)
                    {
                        if (nro <= nco)
                        {
                            m = nro - 1;
                            n = 1;
                        }
                        else
                        {
                            m = nco;
                            n = 2;
                        }
                    }
                    else
                    {
                        if (nro <= nco)
                        {
                            m = nro - 1;
                            n = 1;
                        }
                        else
                        {
                            m = nco - 1;
                            n = 2;
                        }
                    }
                    skip3 = true;
                }

                if (skip3 == false)
                {
                    if (y > amx)
                    {
                        amx = y;
                        if (dsp - amx <= tol)
                        {
                            dsp = 0.0;
                            return;
                        }
                    }
                    bool skip2 = false;
                    do
                    {
                        if (skip2 == false)
                        {
                            do
                            {
                                istk -= 1;
                                if (istk == 0)
                                {
                                    dsp -= amx;
                                    if (dsp - amx <= tol)
                                        dsp = 0.0;
                                    return;
                                }
                                l = lstk[istk] + 1;
                                if (l <= mstk[istk])
                                    break;
                            }
                            while (true);
                        }

                        n = nstk[istk];
                        nro = nrstk[istk];
                        nco = ncstk[istk];
                        y = ystk[istk];
                        if (n == 1)
                        {
                            if (irstk[l, istk] < irstk[l - 1, istk])
                                break;
                        }
                        else if (n == 2)
                        {
                            if (icstk[l, istk] < icstk[l - 1, istk])
                                break;
                        }
                        l += 1;
                        skip2 = l <= mstk[istk];

                    }
                    while (true);
                }
            }
            while (true);
        }

        /// <summary>
        /// shortest path length
        /// </summary>
        private static void Shortpath(int nrow, int[] irow, int ncol, int[] icol, ref double dlp, int mm, double[] fact, double tol, ref int ierr, int[] ico, int[] iro, int[] it, int[] lb, int[] nr, int[] nt, int[] nu, int[] itc, int[] ist, double[] alen, double[] stv)
        {
            int i;
            int n11, n12;
            const int ldst = 200; int nst = 0; int nitc = 0;

            int nco;
            int nro;

            for (i = 0; i <= ncol; i++)
            {
                alen[i] = 0.0;
            }
            for (i = 1; i <= 400; i++)
            {
                ist[i] = -1;
            }
            // (nrow Is 1)
            if (nrow <= 1)
            {
                if (nrow > 0)
                {
                    dlp -= fact[icol[1]];
                    for (i = 2; i <= ncol; i++)
                    {
                        dlp -= fact[icol[i]];
                    }
                }
                return;
            }
            // c(ncol Is 1)
            if (ncol <= 1)
            {
                if (ncol > 0)
                {
                    dlp = dlp - fact[irow[1]] - fact[irow[2]];
                    for (i = 3; i <= nrow; i++)
                    {
                        dlp -= fact[irow[i]];
                    }
                }
                return;
            }
            //                                   2 by 2 table
            if (nrow * ncol == 4)
            {
                n11 = (irow[1] + 1) * (icol[1] + 1) / (mm + 2);
                n12 = irow[1] - n11;
                dlp = dlp - fact[n11] - fact[n12] - fact[icol[1] - n11] - fact[icol[2] - n12];
                return;
            }
            //                                   test for optimal table
            double val = 0.0;
            bool xmin = false;
            if (irow[nrow] <= irow[1] + ncol)
            {
                Shortie(nrow, irow, 1, ncol, icol, 1, ref val, ref xmin, fact, lb, nu, nr);
            }
            if (xmin == false)
            {
                if (icol[ncol] <= icol[1] + nrow)
                {
                    Shortie(ncol, icol, 1, nrow, irow, 1, ref val, ref xmin, fact, lb, nu, nr);
                }
            }

            if (xmin)
            {
                dlp -= val;
                return;
            }
            //                                   setup for dynamic programming
            int nn = mm;
            //                                   minimize ncol
            if (nrow >= ncol)
            {
                nro = nrow;
                nco = ncol;

                for (i = 1; i <= nrow; i++)
                {
                    iro[i] = irow[i];
                }

                ico[1] = icol[1];
                nt[1] = nn - ico[1];
                for (i = 2; i <= ncol; i++)
                {
                    ico[i] = icol[i];
                    nt[i] = nt[i - 1] - ico[i];
                }
            }
            else
            {
                nro = ncol;
                nco = nrow;

                ico[1] = irow[1];
                nt[1] = nn - ico[1];
                for (i = 2; i <= nrow; i++)
                {
                    ico[i] = irow[i];
                    nt[i] = nt[i - 1] - ico[i];
                }

                for (i = 1; i <= ncol; i++)
                {
                    iro[i] = icol[i];
                }
            }
            //                                   initialize pointers
            double vmn = 10000000000.0;
            int nc1S = nco - 1;
            int irl = 1;
            int ks = 0;
            int k = ldst;
            int kyy = ico[nco] + 1;

            // outer
            do
            {
                bool cycleouter = false;
                //                                   setup to generate new node
                int lev = 1;
                int nr1 = nro - 1;
                int nrt = iro[irl];
                int nct = ico[1];
                lb[1] = Convert.ToInt32(Math.Floor(Convert.ToDouble((nrt + 1) * (nct + 1)) / Convert.ToDouble(nn + nr1 * nc1S + 1) - tol) - 1);
                nu[1] = Convert.ToInt32(Math.Floor(Convert.ToDouble((nrt + nc1S) * (nct + nr1)) / Convert.ToDouble(nn + nr1 + nc1S)) - lb[1] + 1);
                nr[1] = nrt - lb[1];
                // inner
                do
                {
                    int itp;
                    int key;
                    do
                    {
                        //                                   generate a node
                        nu[lev] = nu[lev] - 1;
                        if (nu[lev] != 0)
                        {
                            lb[lev] = lb[lev] + 1;
                            nr[lev] = nr[lev] - 1;
                            break;
                        }
                        if (lev != 1)
                        {
                            lev -= 1;
                        }
                        else
                        {
                            do
                            {
                                //                                   pop item from stack
                                if (nitc > 0)
                                {
                                    //                                   stack index
                                    itp = itc[nitc + k] + k;
                                    nitc -= 1;
                                    val = stv[itp];
                                    key = ist[itp];
                                    ist[itp] = -1;
                                    //                                   compute marginals
                                    for (i = nco; i >= 2; i--)
                                    {
                                        ico[i] = key % kyy;
                                        key /= kyy;
                                    }
                                    ico[1] = key;
                                    //                                   set up nt array
                                    nt[1] = nn - ico[1];
                                    for (i = 2; i <= nco; i++)
                                    {
                                        nt[i] = nt[i - 1] - ico[i];
                                    }
                                    //                                   test for optimality
                                    xmin = false;
                                    if (iro[nro] <= iro[irl] + nco)
                                    {
                                        Shortie(nro, iro, irl, nco, ico, 1, ref val, ref xmin, fact, lb, nu, nr);
                                    }
                                    if (xmin == false)
                                    {
                                        if (ico[nco] <= ico[1] + nro)
                                        {
                                            Shortie(nco, ico, 1, nro, iro, irl, ref val, ref xmin, fact, lb, nu, nr);
                                        }
                                    }

                                    if (xmin == false)
                                    {
                                        cycleouter = true;
                                        break;
                                    }

                                    if (val < vmn)
                                    {
                                        vmn = val;
                                    }

                                }
                                else if (nro > 2 & nst > 0)
                                {
                                    //                                   go to next level
                                    nitc = nst;
                                    nst = 0;
                                    k = ks;
                                    ks = ldst - ks;
                                    nn -= iro[irl];
                                    irl += 1;
                                    nro -= 1;
                                }
                                else
                                {

                                    dlp -= vmn;
                                    return;
                                }

                            }
                            while (true);

                            if (cycleouter)
                                break;
                        }
                    }
                    while (true);

                    if (cycleouter == false)
                    {
                        int nn1;
                        do
                        {
                            alen[lev] = alen[lev - 1] + fact[lb[lev]];
                            if (lev >= nc1S)
                            {
                                break;
                            }
                            nn1 = nt[lev];
                            nrt = nr[lev];
                            lev += 1;
                            int nc1 = nco - lev;
                            nct = ico[lev];
                            lb[lev] = (int)Math.Floor(Convert.ToDouble((nrt + 1) * (nct + 1)) / Convert.ToDouble(nn1 + nr1 * nc1 + 1) - tol);
                            nu[lev] = Convert.ToInt32(Math.Floor(Convert.ToDouble((nrt + nc1) * (nct + nr1)) / Convert.ToDouble(nn1 + nr1 + nc1)) - lb[lev] + 1);
                            nr[lev] = nrt - lb[lev];
                        }
                        while (true);

                        alen[nco] = alen[lev] + fact[nr[lev]];
                        lb[nco] = nr[lev];

                        double v = val + alen[nco];
                        if (nro == 2)
                        {
                            //                                only 1 row left
                            v = v + fact[ico[1] - lb[1]] + fact[ico[2] - lb[2]];
                            for (i = 3; i <= nco; i++)
                            {
                                v += fact[ico[i] - lb[i]];
                            }
                            if (v < vmn)
                            {
                                vmn = v;
                            }
                        }
                        else if (nro == 3 & nco == 2)
                        {
                            //                                3 rows and 2 columns
                            nn1 = nn - iro[irl] + 2;
                            int ic1 = ico[1] - lb[1];
                            int ic2 = ico[2] - lb[2];
                            n11 = (iro[irl + 1] + 1) * (ic1 + 1) / nn1;
                            n12 = iro[irl + 1] - n11;
                            v = v + fact[n11] + fact[n12] + fact[ic1 - n11] + fact[ic2 - n12];
                            if (v < vmn)
                            {
                                vmn = v;
                            }
                        }
                        else
                        {
                            //                                column marginals are new node
                            for (i = 1; i <= nco; i++)
                            {
                                it[i] = ico[i] - lb[i];
                            }
                            //                                sort column marginals
                            int ii;
                            if (nco == 2)
                            {
                                if (it[1] > it[2])
                                {
                                    ii = it[1];
                                    it[1] = it[2];
                                    it[2] = ii;
                                }
                            }
                            else if (nco == 3)
                            {
                                ii = it[1];
                                if (ii > it[3])
                                {
                                    if (ii <= it[2])
                                    {
                                        it[1] = it[3];
                                        it[3] = it[2];
                                        it[2] = ii;
                                    }
                                    else if (it[2] > it[3])
                                    {
                                        it[1] = it[3];
                                        it[3] = ii;
                                    }
                                    else
                                    {
                                        it[1] = it[2];
                                        it[2] = it[3];
                                        it[3] = ii;
                                    }
                                }
                                else if (ii > it[2])
                                {
                                    it[1] = it[2];
                                    it[2] = ii;
                                }
                                else if (it[2] > it[3])
                                {
                                    ii = it[2];
                                    it[2] = it[3];
                                    it[3] = ii;
                                }
                            }
                            else
                            {
                                // Call iqsort(nco, it, it)
                                Array.Sort(it, 1, nco);
                            }
                            //                                compute hash value
                            key = it[1] * kyy + it[2];
                            for (i = 3; i <= nco; i++)
                            {
                                key = it[i] + key * kyy;
                            }
                            //                                table index
                            int ipn = key % ldst + 1;
                            //                                find empty position
                            itp = ipn - 1;
                            bool cycleinner = false;
                            int idum;
                            for (idum = 1; idum <= ldst; idum++)
                            {
                                itp += 1;
                                if (itp > ldst)
                                {
                                    itp = 1;
                                }
                                ii = ks + itp;
                                //IEB 23 Dec 14 avoid situation where ii is negative see sencond from last example in big Fisher.xls
                                if (ii >= 0)
                                {
                                    if (ist[ii] < 0)
                                    {
                                        //                                push onto stack
                                        ist[ii] = key;
                                        stv[ii] = v;
                                        nst += 1;
                                        ii = nst + ks;
                                        itc[ii] = itp;
                                        cycleinner = true;
                                        break;
                                    }
                                    if (ist[ii] == key)
                                    {
                                        //                                marginals already on stack
                                        stv[ii] = Math.Min(v, stv[ii]);
                                        cycleinner = true;
                                        break;
                                    }
                                }
                                //IEB if added
                            }

                            if (cycleinner == false)
                            {
                                ierr = 4;
                                return;
                            }
                        }
                    }
                    else
                    {
                        break;
                    }
                }
                while (true); // inner
            }
            while (true); // outer

        }

        /// <summary>
        /// shortest path length (network algorithm)
        /// </summary>
        private static void Shortie(int nrow, int[] irow, int irx, int ncol, int[] icol, int icx, ref double val, ref bool xmin, double[] fact, int[] nd, int[] ne, int[] m)
        {
            int ix1 = irx - 1;
            int ix2 = icx - 1;

            for (int i = 1; i < nrow; i++)
            {
                nd[i] = 0;
            }
            int iz = icol[ix2 + 1] / nrow;
            ne[1] = iz;
            int ix = icol[ix2 + 1] - nrow * iz;
            m[1] = ix;
            //IEB 23 Dec 14 big Fisher.xls example ix was negative so changed from ix !=0
            if (ix > 0)
            {
                nd[ix] = nd[ix] + 1;
            }
            for (int i = 2; i <= ncol; i++)
            {
                ix = icol[ix2 + i] / nrow;
                ne[i] = ix;
                iz += ix;
                ix = icol[ix2 + i] - nrow * ix;
                m[i] = ix;
                //IEB 23 Dec 14 big Fisher.xls example ix was negative so changed from ix !=0
                if (ix > 0)
                {
                    nd[ix] = nd[ix] + 1;
                }
            }
            for (int i = nrow - 2; i >= 1; i--)
            {
                nd[i] = nd[i] + nd[i + 1];
            }
            ix = 0;
            int nrw1 = nrow + 1;
            for (int i = nrow; i >= 2; i--)
            {
                ix = ix + iz + nd[nrw1 - i] - irow[ix1 + i];
                if (ix < 0)
                {
                    return;
                }
            }
            for (int i = 1; i <= ncol; i++)
            {
                ix = ne[i];
                iz = m[i];
                val = val + iz * fact[ix + 1] + (nrow - iz) * fact[ix];
            }
            xmin = true;
        }

        /// <summary>generate new nodes based on marginal totals (fisher network algorithm)</summary>
        private static void Sibling(int nrow, int[] imax, int[] idif, ref int k, ref int ks, out int iflag)
        {
            int m;

            // 
            iflag = 0;
            //      find the node, ks, that can be incremented
            if (ks == 0)
            {
                do
                {
                    ks += 1;
                    if (idif[ks] != imax[ks])
                    {
                        break;
                    }
                }
                while (true);
            }

            //      find a node, > ks, that can be decremented
            if (idif[k] > 0 & k > ks)
            {
                idif[k] = idif[k] - 1;
                do
                {
                    k -= 1;
                    if (imax[k] != 0)
                    {
                        break;
                    }
                }
                while (true);
                m = k;
                //       find a node, >= ks, than can be incremented
                do
                {
                    if (idif[m] >= imax[m])
                    {
                        m -= 1;
                    }
                    else
                    {
                        break;
                    }
                }
                while (true);
                idif[m] = idif[m] + 1;
                // new(ks)
                if (m == ks)
                {
                    if (idif[m] == imax[m])
                    {
                        ks = k;
                    }
                }
            }
            else
            {
                //       done?
                int k1;
                do
                {
                    bool skip = false;
                    for (k1 = k + 1; k1 <= nrow; k1++)
                    {
                        if (idif[k1] > 0)
                        {
                            skip = true;
                            break;
                        }
                    }
                    if (skip == false)
                    {
                        iflag = 1;
                        return;
                    }
                    // reallocate(counts)
                    int mm = 1;
                    int i;
                    for (i = 1; i <= k; i++)
                    {
                        mm += idif[i];
                        idif[i] = 0;
                    }
                    k = k1;
                    do
                    {
                        k -= 1;
                        m = Math.Min(mm, imax[k]);
                        idif[k] = m;
                        mm -= m;
                        if (mm <= 0 | k == 1)
                        {
                            break;
                        }
                    }
                    while (true);
                    //        done?
                    if (mm > 0)
                    {
                        if (k1 != nrow)
                        {
                            k = k1;
                            //          loop back to reallocate if all counts not reallocated
                        }
                        else
                        {
                            iflag = 1;
                            return;
                        }
                    }
                    else
                    {
                        break;
                    }

                }
                while (true);

                // fetch(ks)
                idif[k1] = idif[k1] - 1;
                ks = 0;
                do
                {
                    ks += 1;
                    if (ks > k)
                    {
                        return;
                    }
                    if (idif[ks] < imax[ks])
                    {
                        break;
                    }
                }
                while (true);
            }


        }

        /// <summary>
        /// pop a node off the stack
        /// </summary>
        private static void Popnode(int nrow, int[] irow, ref int iflag, int[] kyy, int[] key, int ldkey, ref int last, ref int ipn, int istart)
        {
            do
            {
                last += 1;
                if (last <= ldkey)
                {
                    if (key[istart + last - 1] >= 0)
                    {
                        int kval = key[istart + last - 1];
                        key[istart + last - 1] = -9999;
                        for (int j = nrow; j >= 2; j--)
                        {
                            irow[j] = kval / kyy[j];
                            kval -= irow[j] * kyy[j];
                        }
                        irow[1] = kval;
                        ipn = last;
                        break;
                    }
                }
                else
                {
                    last = 0;
                    iflag = 3;
                    break;
                }
            }
            while (true);
        }

        /// <summary>
        /// push a node onto the stack (network algorithm)
        /// </summary>
        private static void Pushnode(double pastp, double tol, int kval, int[] key, int jkey, int ldkey, int[] ipoin, double[] stp, int jstp, int ldstp, int[] ifrq, int jstp2, int jstp3, int jstp4, int ifreq, ref int itop, bool ipsh, ref int itp, ref int ifault)
        {
            // offset into stp() and ifrq
            int ix1 = jstp - 1;
            int ix2 = jstp2 - 1;
            int ix3 = jstp3 - 1;
            int ix4 = jstp4 - 1;

            if (ipsh)
            {
                int ird = kval % ldkey + 1;
                int jq = 0;
                for (itp = jkey - 1 + ird; itp < jkey + ldkey; itp++)
                {
                    if (key[itp] == kval)
                    {
                        jq = 2;
                        break;
                    }
                    if (key[itp] < 0)
                    {
                        jq = 1;
                        break;
                    }
                }
                if (jq == 0)
                {
                    for (itp = jkey; itp <= jkey - 2 + ird; itp++)
                    {
                        if (key[itp] == kval)
                        {
                            jq = 2;
                            break;
                        }
                        if (key[itp] < 0)
                        {
                            jq = 1;
                            break;
                        }
                    }
                }

                if (jq == 0)
                {
                    ifault = 1;
                    return;
                }
                if (jq == 1)
                {
                    key[itp] = kval;
                    itop += 1;
                    ipoin[itp] = itop;
                    if (itop > ldstp)
                    {
                        ifault = 1;
                        return;
                    }
                    ifrq[ix2 + itop] = -1;
                    ifrq[ix3 + itop] = -1;
                    ifrq[ix4 + itop] = -1;
                    stp[ix1 + itop] = pastp;
                    ifrq[ix1 + itop] = ifreq;
                    return;
                }
            }
            int ipn = ipoin[itp];
            double test1 = pastp - tol;
            double test2 = pastp + tol;
            do
            {
                if (stp[ix1 + ipn] < test1)
                {
                    ipn = ifrq[ix4 + ipn];
                    if (ipn <= 0)
                    {
                        break;
                    }
                }
                else if (stp[ix1 + ipn] > test2)
                {
                    ipn = ifrq[ix3 + ipn];
                    if (ipn <= 0)
                    {
                        break;
                    }
                }
                else
                {
                    ifrq[ix1 + ipn] = ifrq[ix1 + ipn] + ifreq;
                    return;
                }
            }
            while (true);
            itop += 1;
            if (itop > ldstp)
            {
                ifault = 1;
                return;
            }
            ipn = ipoin[itp];
            int itmp;
            do
            {
                if (stp[ix1 + ipn] < test1)
                {
                    itmp = ipn;
                    ipn = ifrq[ix4 + ipn];
                    if (ipn <= 0)
                    {
                        ifrq[ix4 + itmp] = itop;
                        break;
                    }
                }
                else if (stp[ix1 + ipn] > test2)
                {
                    itmp = ipn;
                    ipn = ifrq[ix3 + ipn];
                    if (ipn <= 0)
                    {
                        ifrq[ix3 + itmp] = itop;
                        break;
                    }
                }
            }
            while (true);
            ifrq[ix2 + itop] = ifrq[ix2 + itmp];
            ifrq[ix2 + itmp] = itop;
            stp[ix1 + itop] = pastp;
            ifrq[ix1 + itop] = ifreq;
            ifrq[ix4 + itop] = -1;
            ifrq[ix3 + itop] = -1;

        }

        public static void Fisherp(int aa, int bb, int cc, int dd, out double p1, out double p2, out int ifault)
        {
            double zp = 0;

            int[,] table = new int[3, 3];
            double[,] expect = new double[4, 4];
            table[1, 1] = aa;
            table[2, 1] = cc;
            table[1, 2] = bb;
            table[2, 2] = dd;
            expect[1, 3] = table[1, 1] + table[1, 2];
            expect[2, 3] = table[2, 1] + table[2, 2];
            expect[3, 1] = table[1, 1] + table[2, 1];
            expect[3, 2] = table[1, 2] + table[2, 2];
            expect[3, 3] = expect[1, 3] + expect[2, 3];
            double rn = expect[3, 3];
            int i = expect[1, 3] < expect[2, 3] ? 1 : 2;
            int j = expect[3, 1] < expect[3, 2] ? 1 : 2;
            double xmin = expect[i, 3] < expect[3, j] ? expect[i, 3] : expect[3, j];
            if (xmin <= 0.001)
            {
                ifault = 10;
                p1 = Constant.MISSING;
                p2 = Constant.MISSING;
                return;
            }
            i = 3 - i;
            j = 1;
            if (table[i, 2] / expect[i, 3] >= table[3 - i, 2] / expect[3 - i, 3])
            {
                j = 2;
            }
            int it = Convert.ToInt32(table[i, j] + 0.1);
            int k = it;
            int ind = Convert.ToInt32(expect[3, j] + 0.1);
            int il = Convert.ToInt32(rn + 0.1);
            int inn = Convert.ToInt32(expect[i, 3] + 0.1);
            if (it >= 1)
            {
                it -= 1;
            }
            p1 = Hypergeo(it, inn, ind, il, ref zp, out ifault);
            if (zp != -99)
            {
                p1 = zp;
            }
            else { p1 = 1.0 - p1; }
            it = (int)Math.Floor((2.0 * expect[i, 3] * expect[3, j] - rn * table[i, j]) / rn + 0.00001);
            if (k == it)
            {
                p2 = 1.0;
            }
            else
            {
                if (it < 0)
                {
                    it = 0;
                }
                p2 = p1 + Hypergeo(it, inn, ind, il, ref zp, out ifault);
            }
        }

        private static double Hypergeo(int k, int n, int m, int l, ref double zp, out int ifault)
        {
            int iflag; int j;
            int mm; int mm1;
            // int ner = 0;
            double a; double a1; double aa;
            double b1; double bb;
            double u;

            // ner = 1; 
            ifault = 0;
            if (n < 1)
            {
                ifault = 1;
                return -99;
            }
            if (m < 0)
            {
                ifault = 2;
                return -99;
            }
            if (l < n)
            {
                ifault = 3;
                return -99;
            }
            if (l < m)
            {
                ifault = 4;
                return -99;
            }
            if (k < 0)
            {
                return 0.0;
            }
            if (k > n)
            {
                return 1.0;
            }
            if (k >= m)
            {
                return 1.0;
            }
            if (n - k > l - m)
            {
                return 0.0;
            }
            if (m == l & k == n)
            {
                return 1.0;
            }
            double p = 1.0;
            double al = l;
            int nmmin = n < m ? n : m;
            double anmmin = nmmin;
            int nmmax = n > m ? n : m;
            double anmmax = nmmax;
            double xval1 = k * (l + 2);
            double xval2 = (m + 1) * (n + 1);
            if (xval1 <= xval2)
            {
                iflag = 0;
                aa = anmmax - anmmin;
                bb = al - anmmax - anmmin;
                int k0 = n + (m - l);
                if (k0 < 0)
                {
                    k0 = 0;
                }
                double aj = k0;
                a1 = anmmin - aj;
                b1 = aj + 1.0;
                mm1 = k - k0;
                a = al - anmmax + aj;
                mm = nmmin - k0;
            }
            else
            {
                iflag = 1;
                aa = al - anmmax - anmmin;
                bb = anmmax - anmmin;
                a1 = anmmin;
                b1 = 1.0;
                mm1 = nmmin - k;
                mm = l - nmmax;
                a = al - anmmin;
                if (nmmin < mm)
                {
                    mm = nmmin;
                    a = anmmax;
                }
            }
            int icnt = 0;
            const double sml = Constant.SPREAL * 10.0;
            if (mm != 0)
            {
                for (j = 1; j <= mm; j++)
                {
                    u = a / al;
                    if (u * p < sml)
                    {
                        p /= sml;
                        icnt += 1;
                    }
                    p *= u;
                    a -= 1.0;
                    al -= 1.0;
                }
            }
            double sp = 0.0;
            if (mm1 != 0)
            {
                for (j = 1; j <= mm1; j++)
                {
                    if (icnt == 0)
                    {
                        sp += p;
                    }
                    u = a1 * (a1 + aa) / (b1 * (b1 + bb));
                    p = u * p;
                    if (p >= 1.0)
                    {
                        p *= sml;
                        icnt -= 1;
                    }
                    a1 -= 1.0;
                    b1 += 1.0;
                }
            }
            if (icnt != 0)
            {
                p = 0.0;
            }
            if (iflag == 0)
            {
                zp = -99;
                sp += p;
            }
            else
            {
                zp = sp;
                sp = 1.0 - sp;
            }
            return sp;
        }

        private static void WoolfStratum(ParameterBag outputParameters, bool showIntermediates, double a1, double b1, double c1, double d1, double vs, double cit, out double y, out double w)
        {
            double cco = 0;

            double x = a1 * d1 / (b1 * c1);
            y = Math.Log(x);
            double e = Math.Sqrt(vs);
            w = 1.0 / vs;
            double x1 = y * Math.Sqrt(w);
            double x2 = x1 * x1;
            const double n2 = 1.0;
            double y1 = y - cit * e;
            double y2 = y + cit * e;
            if (y1 > y2)
                Utilities.Utilities.Swap(ref y1, ref y2);
            if (showIntermediates)
            {
                outputParameters.AddOutput(new Dictionary<string, object>
                {
                    { "odds", x},
                    { "log", y },
                    { "var", vs },
                    { "se", e },
                    { "weight", w },
                    { "chi_2", x2 },
                    { "chi", x1 },
                    { "chi_p", PDF.chivalp(x2, n2) },
                    { "pc", cco * 100 },
                    { "ci_from", y1 },
                    { "ci_to", y2 },
                    { "odds_from", Math.Exp(y1) },
                    { "odds_to", Math.Exp(y2) }
                });
            }
        }

        public static ParameterBag Woolf(double[,] o, int k, bool showIntermediates, double cit, double cco, out bool ierr)
        {
            ierr = true;

            ParameterBag outputParameters = new();
            outputParameters.AddOutput("pc", cco * 100);
            List<ParameterBag> tableList = new();
            outputParameters.AddOutput("*table", tableList);
            double s1X = 0; double s1 = 0; double t1 = 0; double t1X = 0; double w1 = 0; double w1X = 0; double n1 = 0; double n1X = 0;
            for (int idx = 1; idx <= k; idx++)
            {
                double a = o[idx, 1];
                double b = o[idx, 2];
                double c = o[idx, 3];
                double d = o[idx, 4];
                double p = a + b;
                double q = c + d;
                double r = a + c;
                double s = b + d;
                double n = p + q;
                if (p <= 0.0 || n <= 0.0 || q <= 0.0)
                    throw new InvalidDataException();

                ParameterBag tableParameters = new();
                if (showIntermediates)
                {
                    tableList.Add(tableParameters);
                    tableParameters.AddOutput("table", idx);
                    tableParameters.AddOutput("pc_a", 100.0 * a / p);
                    tableParameters.AddOutput("pc_c", 100.0 * c / q);
                    tableParameters.AddOutput("pc_t", 100.0 * r / n);
                }
                double e1 = p * r / n;
                double e2 = p * s / n;
                double e3 = q * r / n;
                double e4 = q * s / n;
                if (e1 < 5 || e2 < 5 || e3 < 5 || e4 < 5)
                {
                    if (showIntermediates)
                    {
                        List<ParameterBag> warnSmallList = new();
                        tableParameters.AddOutput("*warn_small", warnSmallList);
                        warnSmallList.Add(new ParameterBag());
                    }
                }
                else
                {
                    if (showIntermediates)
                    {
                        List<ParameterBag> warnSmallList = new();
                        tableParameters.AddOutput("*warn_small", warnSmallList);
                    }
                }
                double f = a * d - b * c;
                double i = Math.Sign(f);
                double x2 = f * f * n / (p * q * r * s);
                double x1 = i * Math.Sqrt(x2);
                if (showIntermediates)
                {
                    tableParameters.AddOutput("table_chi_2", x2);
                    tableParameters.AddOutput("table_chi", x1);
                }
                f = Math.Abs(f) - n / 2.0;
                if (f < 0.0)
                    f = 0.0;
                x2 = f * f * n / (p * q * r * s);
                x1 = i * Math.Sqrt(x2);
                const double n2 = 1;
                if (showIntermediates)
                {
                    tableParameters.AddOutput("yates_chi_2", x2);
                    tableParameters.AddOutput("yates_chi", x1);
                    tableParameters.AddOutput("yates_chi_p", PDF.chivalp(x2, n2));
                }
                double w;
                double y;
                double vs;
                double d1;
                double c1;
                double b1;
                double a1;

                if (a > 0 && b > 0 && c > 0 && d > 0)
                {
                    ParameterBag noHaldaneParameters = new();
                    if (showIntermediates)
                    {
                        List<ParameterBag> noHaldaneList = new();
                        tableParameters.AddOutput("*no_haldane", noHaldaneList);
                        noHaldaneList.Add(noHaldaneParameters);
                        List<ParameterBag> warnNoHaldaneList = new();
                        tableParameters.AddOutput("*warn_no_haldane", warnNoHaldaneList);
                    }
                    a1 = a;
                    b1 = b;
                    c1 = c;
                    d1 = d;
                    vs = 1.0 / a + 1.0 / b + 1.0 / c + 1.0 / d;
                    WoolfStratum(noHaldaneParameters, showIntermediates, a1, b1, c1, d1, vs, cit, out y, out w);
                    n1X += 1.0;
                    w1X += w;
                    t1X += w * y;
                    s1X += w * y * y;
                }
                else
                {
                    if (showIntermediates)
                    {
                        List<ParameterBag> noHaldaneList = new();
                        tableParameters.AddOutput("*no_haldane", noHaldaneList);
                        List<ParameterBag> warnNoHaldaneList = new();
                        tableParameters.AddOutput("*warn_no_haldane", warnNoHaldaneList);
                        warnNoHaldaneList.Add(new ParameterBag());
                    }
                }
                a1 = a + 0.5;
                b1 = b + 0.5;
                c1 = c + 0.5;
                d1 = d + 0.5;
                vs = 1.0 / (a + 1.0) + 1.0 / (b + 1.0) + 1.0 / (c + 1.0) + 1.0 / (d + 1.0);
                ParameterBag haldaneParameters = new();
                List<ParameterBag> haldaneList = new();
                tableParameters.AddOutput("*haldane", haldaneList);
                haldaneList.Add(haldaneParameters);
                WoolfStratum(haldaneParameters, showIntermediates, a1, b1, c1, d1, vs, cit, out y, out w);
                n1 += 1.0;
                w1 += w;
                t1 += w * y;
                s1 += w * y * y;
            }

            List<ParameterBag> combinedNoHaldaneList = new();
            outputParameters.AddOutput("*combined_no_haldane", combinedNoHaldaneList);
            if (n1 > 1 && n1X == n1)
            {
                ParameterBag combinedNoHaldaneParameters = new();
                combinedNoHaldaneList.Add(combinedNoHaldaneParameters);
                combinedNoHaldaneParameters.AddOutput("tables", n1);
                double m1X = t1X / w1X;
                combinedNoHaldaneParameters.AddOutput("mean", m1X);
                combinedNoHaldaneParameters.AddOutput("odds", Math.Exp(m1X));
                double v1X = 1.0 / w1X;
                double e1X = Math.Sqrt(v1X);
                combinedNoHaldaneParameters.AddOutput("var", v1X);
                combinedNoHaldaneParameters.AddOutput("se", e1X);
                double y1X = m1X - cit * e1X;
                double y2X = m1X + cit * e1X;
                if (y1X > y2X)
                {
                    double ytx = y1X;
                    y1X = y2X;
                    y2X = ytx;
                }
                combinedNoHaldaneParameters.AddOutput("pc", cco * 100);
                combinedNoHaldaneParameters.AddOutput("ci_from", y1X);
                combinedNoHaldaneParameters.AddOutput("ci_to", y2X);
                combinedNoHaldaneParameters.AddOutput("odds_from", Math.Exp(y1X));
                combinedNoHaldaneParameters.AddOutput("odds_to", Math.Exp(y2X));
                double u1X = m1X / e1X;
                double x2X = u1X * u1X;
                double n2X = 1.0;
                combinedNoHaldaneParameters.AddOutput("chi_2", x2X);
                combinedNoHaldaneParameters.AddOutput("chi", u1X);
                combinedNoHaldaneParameters.AddOutput("chi_p", PDF.chivalp(x2X, n2X));
                n2X = n1X - 1.0;
                x2X = s1X - t1X * t1X / w1X;
                combinedNoHaldaneParameters.AddOutput("het_chi_2", x2X);
                combinedNoHaldaneParameters.AddOutput("df", n2X);
                combinedNoHaldaneParameters.AddOutput("het_chi_p", PDF.chivalp(x2X, n2X));
            }

            List<ParameterBag> combinedWithHaldaneList = new();
            outputParameters.AddOutput("*combined_with_haldane", combinedWithHaldaneList);
            if (n1 > 1)
            {
                ParameterBag combinedWithHaldaneParameters = new();
                combinedWithHaldaneList.Add(combinedWithHaldaneParameters);
                combinedWithHaldaneParameters.AddOutput("tablesx", n1);
                double m1 = t1 / w1;
                combinedWithHaldaneParameters.AddOutput("meanx", m1);
                combinedWithHaldaneParameters.AddOutput("oddsx", Math.Exp(m1));
                double v1 = 1.0 / w1;
                double e1 = Math.Sqrt(v1);
                combinedWithHaldaneParameters.AddOutput("varx", v1);
                combinedWithHaldaneParameters.AddOutput("sex", e1);
                double y1 = m1 - cit * e1;
                double y2 = m1 + cit * e1;
                if (y1 > y2)
                {
                    double yt = y1;
                    y1 = y2;
                    y2 = yt;
                }
                combinedWithHaldaneParameters.AddOutput("pc", cco * 100);
                combinedWithHaldaneParameters.AddOutput("ci_fromx", y1);
                combinedWithHaldaneParameters.AddOutput("ci_tox", y2);
                combinedWithHaldaneParameters.AddOutput("odds_fromx", Math.Exp(y1));
                combinedWithHaldaneParameters.AddOutput("odds_tox", Math.Exp(y2));
                double u1 = m1 / e1;
                double x2 = u1 * u1;
                double n2 = 1;
                combinedWithHaldaneParameters.AddOutput("chi_2x", x2);
                combinedWithHaldaneParameters.AddOutput("chix", u1);
                combinedWithHaldaneParameters.AddOutput("chi_px", PDF.chivalp(x2, n2));
                n2 = n1 - 1.0;
                x2 = s1 - t1 * t1 / w1;
                combinedWithHaldaneParameters.AddOutput("het_chi_2x", x2);
                combinedWithHaldaneParameters.AddOutput("dfx", n2);
                combinedWithHaldaneParameters.AddOutput("het_chi_px", PDF.chivalp(x2, n2));
            }
            return outputParameters;
        }

        public static StepOutput RptChiWoolfWorksheet(ParameterBag parameters)
        {
            double cco = parameters["cco"].AsDouble;
            if (cco <= 0)
                cco = 0.95;
            double p = (1.0 - cco) / 2.0;
            double cit = PDF.gauinv(1.0 - p);
            DataFrame snFrame = parameters["sn"].AsDataFrame;
            DoubleVariable snVariable = (DoubleVariable)snFrame.Variables[0];
            DataFrame srFrame = parameters["sr"].AsDataFrame;
            DoubleVariable srVariable = (DoubleVariable)srFrame.Variables[0];
            DataFrame xnFrame = parameters["xn"].AsDataFrame;
            DoubleVariable xnVariable = (DoubleVariable)xnFrame.Variables[0];
            DataFrame xrFrame = parameters["xr"].AsDataFrame;
            DoubleVariable xrVariable = (DoubleVariable)xrFrame.Variables[0];
            int k = snVariable.Length;
            double[,] o = new double[k + 1, 5];
            for (int i = 1; i <= k; i++)
            {
                double sn = snVariable.Data[i - 1];
                double sr = srVariable.Data[i - 1];
                double xn = xnVariable.Data[i - 1];
                double xr = xrVariable.Data[i - 1];
                o[i, 1] = sr;
                o[i, 2] = sn - sr;
                if (sr < 0 || sn < 0 || sn < sr)
                    throw new InvalidDataException();
                o[i, 3] = xr;
                o[i, 4] = xn - xr;
                if (xr < 0 || xn < 0 || xn < xr)
                    throw new InvalidDataException();
            }

            bool showIntermediates = parameters["show_intermediates"].AsBoolean;
            return new StepOutput(Woolf(o, k, showIntermediates, cit, cco, out bool _));
        }

        public static StepOutput ShtDetabulate(ParameterBag parameters)
        {
            int i; int j;

            DataFrame data = parameters["data"].AsDataFrame;

            double gtot = 0.0;
            int maxrows = 0;
            for (i = 0; i < data.VariableCount; i++)
            {
                gtot += ((DoubleVariable)data.Variables[i]).Sum;
                if (data.Variables[i].Length > maxrows)
                    maxrows = data.Variables[i].Length;
            }
            if (gtot > 1000000)
                throw new TemplateOperationCancelledException("Number of observations exceeds row limit of worksheet.", "Detabulate");

            int[,] xt = new int[maxrows + 1, data.VariableCount + 1];
            for (i = 0; i < data.VariableCount; i++)
                for (j = 1; j <= maxrows; j++)
                    xt[j, i] = 0;
            for (i = 0; i < data.VariableCount; i++)
            {
                DoubleVariable v = (DoubleVariable)data.Variables[i];
                for (j = 1; j <= v.Length; j++)
                    xt[j, i] = Convert.ToInt32(v.Data[j - 1]);
            }
            DataFrame outputFrame = new();
            DoubleVariable rowVariable = new() { Title = "Row Category" };
            //  TODO: Some attempt to size to avoid repeated redims

            outputFrame.Variables.Add(rowVariable);
            DoubleVariable columnVariable = new() { Title = "Column Category" };

            outputFrame.Variables.Add(columnVariable);
            int ctr = 0;
            for (j = 1; j <= maxrows; j++)
            {
                for (i = 0; i < data.VariableCount; i++)
                {
                    if (xt[j, i] > 0)
                    {
                        int k;
                        for (k = 1; k <= xt[j, i]; k++)
                        {
                            rowVariable.SetData(ctr, j);
                            columnVariable.SetData(ctr, i + 1);
                            ctr += 1;
                        }
                    }
                }
            }
            ParameterBag outputParameters = new();
            outputParameters.AddOutput("output", outputFrame);
            return new StepOutput(outputParameters);
        }

        public static StepOutput ShtTabulate(ParameterBag parameters)
        {
            DataFrame rowsFrame = parameters["rows"].AsDataFrame;
            ClassifierVariable rowsVariable = (ClassifierVariable)rowsFrame.Variables[0];
            int n = rowsVariable.Length;
            int ycats = rowsVariable.GroupCount;
            double[] y = new double[n + 1];
            Namevar[] ycat = new Namevar[ycats + 1];
            string ylab = rowsVariable.Title;
            for (int i = 1; i <= ycats; i++)
                ycat[i] = new Namevar(rowsVariable.Groups[i - 1].Label, i - 1);
            for (int i = 1; i <= n; i++)
                y[i] = rowsVariable.Data[i - 1];

            DataFrame columnsFrame = parameters["columns"].AsDataFrame;
            bool sorted = parameters["sorted"].AsBoolean;
            DataFrame outputFrame = new();
            StringVariable v = new();
            outputFrame.Variables.Add(v);
            int pos = 0;
            for (int c = 0; c < columnsFrame.VariableCount; c++)
            {
                ClassifierVariable cv = (ClassifierVariable)columnsFrame.Variables[c];
                int xcats = cv.GroupCount;
                double[] x = new double[n + 1];
                Namevar[] xcat = new Namevar[xcats + 1];
                string xlab = cv.Title;
                for (int i = 1; i <= xcats; i++)
                    xcat[i] = new Namevar(cv.Groups[i - 1].Label, i - 1);
                for (int i = 1; i <= n; i++)
                    x[i] = cv.Data[i - 1];
                if (sorted)
                {
                    SortName(ycats, ycat, 1);
                    SortName(xcats, xcat, 1);
                }
                int[,] xt = new int[xcats + 1, ycats + 1];
                int tot = 0;
                for (int i = 1; i <= xcats; i++)
                {
                    for (int j = 1; j <= ycats; j++)
                    {
                        for (int k = 1; k <= n; k++)
                            if (x[k] == xcat[i].X && y[k] == ycat[j].X)
                                xt[i, j] += 1;
                        tot += xt[i, j];
                    }
                }
                v.SetData(pos, "(n = " + tot.ToString() + ")");
                for (int j = 1; j <= ycats; j++)
                    v.SetData(pos + j, ylab + ":" + ycat[j].Title);
                for (int i = 1; i <= xcats; i++)
                {
                    StringVariable vv;
                    if (outputFrame.VariableCount > i)
                    {
                        vv = (StringVariable)outputFrame.Variables[i];
                    }
                    else
                    {
                        vv = new StringVariable();
                        outputFrame.Variables.Add(vv);
                    }
                    vv.SetData(pos, xlab + ":" + xcat[i].Title);
                    for (int j = 1; j <= ycats; j++)
                        vv.SetData(pos + j, xt[i, j].ToString());
                }
                pos += ycats + 2;
            }
            ParameterBag outputParameters = new();
            outputParameters.AddOutput("output", outputFrame);
            return new StepOutput(outputParameters);
        }
    }

    public class ChiSquareGoodnessOfFitOptions : IFillable
    {
        public int Df { get; set; }
        public int Categories { get; set; }
        public int N { get; set; }
        public double Total { get; set; }
        public IList<string> X { get; }
        public IList<double> Xn { get; }
        public IList<double> Xe { get; }

        public ChiSquareGoodnessOfFitOptions()
        {
            X = new List<string>();
            Xn = new List<double>();
            Xe = new List<double>();
        }

        public string FillerToUse => "ChiSquareGoodnessOfFit";
    }

    public class ScoresOptions : IFillable
    {
        public string Title1 { get; set; }
        public string Title2 { get; set; }
        public List<double> Values1 { get; }
        public List<double> Values2 { get; }

        public ScoresOptions()
        {
            Values1 = new List<double>();
            Values2 = new List<double>();
        }

        public string FillerToUse => "Scores";
    }
}
