using System;
using System.Collections.Generic;

using StatsDirect.Numerics;
using StatsDirect.Data;
using StatsDirect.Templates;
using StatsDirect.Utilities;

namespace StatsDirect.Builtins
{
    public static class Anova
    {
        ///  <summary>
        ///  TWO-WAY HIERARCHICAL ANOVA - OK FOR UNEQUAL SUBGROUPS
        ///  </summary>
        private static void XTwoHier(DataFrame2D frame, double[] y, int N, int[] nobs, int L, ref int[] ngp, ref double[] gbar, ref double[] sgbar, ref double gm, ref double[] ss, ref int[] idf, ref double[] f, ref double[] fp, out bool fault)
        {
            fault = true;
            if (frame.VariableCount < 2)
                return;

            //  Check the expected number of subgroups
            int lsum = 0;
            for (int i = 0; i < frame.VariableCount; i++)
                lsum += frame.Variables[i].Count;
            if (lsum != L)
                return;

            //  Check the expected number of observations
            int nsum = 0;
            for (int i = 1; i <= L; i++)
            {
                if (nobs[i] <= 0)
                    return;
                nsum += nobs[i];
            }
            if (nsum != N)
                return;

            int nlo = 1;
            int nsub = 0;
            double ydd = 0.0;
            double s4 = 0.0;

            ngp = new int[frame.VariableCount + 1];
            gbar = new double[frame.VariableCount + 1];
            for (int i = 0; i < frame.VariableCount; i++)
            {
                int ngpi = 0;
                double yid = 0.0;
                for (int j = 0; j < frame.Variables[i].Count; j++)
                {
                    double yij = 0.0;
                    nsub += 1;
                    int nij = nobs[nsub];
                    ngpi += nij;
                    int nhi = nlo + nij - 1;
                    for (int M = nlo; M <= nhi; M++)
                    {
                        double yy = y[M];
                        ydd += yy;
                        yid += yy;
                        yij += yy;
                    }
                    sgbar[nsub] = yij / Convert.ToDouble(nij);
                    nlo += nij;
                }
                ngp[i + 1] = ngpi;
                gbar[i + 1] = yid / Convert.ToDouble(ngpi);
            }

            gm = ydd / Convert.ToDouble(N);
            for (int i = 1; i <= N; i++)
            {
                double z = y[i] - gm;
                s4 += z * z;
            }

            for (int i = 1; i <= 4; i++)
                ss[i] = 0.0;
            if (s4 <= 0.0)
                return;

            double S1 = 0.0;
            double S2 = 0.0;
            nsub = 0;

            for (int i = 0; i < frame.VariableCount; i++)
            {
                double z = gbar[i + 1] - gm;
                S1 += z * z * Convert.ToDouble(ngp[i + 1]);
                for (int j = 0; j < frame.Variables[i].Count; j++)
                {
                    nsub += 1;
                    z = sgbar[nsub] - gbar[i + 1];
                    S2 += z * z * Convert.ToDouble(nobs[nsub]);
                }
            }

            ss[1] = S1;
            ss[2] = S2;
            ss[3] = s4 - S2 - S1;
            ss[4] = s4;

            idf[1] = frame.VariableCount - 1;
            idf[2] = L - frame.VariableCount;
            idf[3] = N - L;
            idf[4] = N - 1;
            if (ss[3] <= 0.0)
                return;

            double fden = ss[3] / Convert.ToDouble(idf[3]);
            for (int i = 1; i <= 2; i++)
            {
                double ff = ss[i] / Convert.ToDouble(idf[i]);
                f[i] = ff / fden;
                fp[i] = PDF.fvalp(f[i], Convert.ToDouble(idf[i]), Convert.ToDouble(idf[3]));
            }
            fault = false;
        }

        private static void XTwoWay(double[,,] y, out double[] col, int nr, int nc, int nm, out double ssrow, out double sscol, out double ssint, out double sstot, out double ssres, out int dfrow, out int dfcol, out int dfint, out int dftot, out int dfres, out int fault)
        {
            fault = 1;
            if (nr <= 1 || nc <= 1 || nm < 1)
            {
                ssrow = Constant.MISSING;
                sscol = Constant.MISSING;
                ssint = Constant.MISSING;
                sstot = Constant.MISSING;
                ssres = Constant.MISSING;
                dfrow = 0;
                dfcol = 0;
                dfint = 0;
                dftot = 0;
                dfres = 0;
                col = null;
                return;
            }
            double dnr = Convert.ToDouble(nr);
            double dnc = Convert.ToDouble(nc);
            double dnm = Convert.ToDouble(nm);
            double yt = 0.0;
            double[,] cell = new double[nr + 1, nc + 1];
            double[] row = new double[nr + 1];
            col = new double[nc + 1];
            for (int i = 1; i <= nr; i++)
            {
                double yr = 0.0;
                for (int j = 1; j <= nc; j++)
                {
                    double yc = 0.0;
                    for (int k = 1; k <= nm; k++)
                    {
                        yt += y[k, i, j];
                        yr += y[k, i, j];
                        yc += y[k, i, j];
                    }
                    cell[i, j] = yc / dnm;
                }
                row[i] = yr / (dnm * dnc);
            }
            double gm = yt / (dnm * dnr * dnc);
            sscol = 0.0;
            ssrow = 0.0;
            ssint = 0.0;
            sstot = 0.0;
            for (int j = 1; j <= nc; j++)
            {
                yt = 0.0;
                for (int i = 1; i <= nr; i++)
                {
                    yt += cell[i, j];
                }
                col[j] = yt / dnr;
                sscol += (col[j] - gm) * (col[j] - gm);
            }
            for (int i = 1; i <= nr; i++)
            {
                ssrow += (row[i] - gm) * (row[i] - gm);
                for (int j = 1; j <= nc; j++)
                {
                    ssint += (cell[i, j] - (row[i] - gm) - col[j]) * (cell[i, j] - (row[i] - gm) - col[j]);
                    for (int k = 1; k <= nm; k++)
                        sstot += (y[k, i, j] - gm) * (y[k, i, j] - gm);
                }
            }
            fault = 2;
            if (sstot <= 0.0)
            {
                ssrow = Constant.MISSING;
                sscol = Constant.MISSING;
                ssint = Constant.MISSING;
                sstot = Constant.MISSING;
                ssres = Constant.MISSING;
                dfrow = 0;
                dfcol = 0;
                dfint = 0;
                dftot = 0;
                dfres = 0;
                return;
            }
            ssrow = dnc * dnm * ssrow;
            sscol = dnr * dnm * sscol;
            ssint = dnm * ssint;
            // sstot = sstot; 
            ssres = nm == 1 ? ssint : Math.Max(0.0, sstot - ssrow - sscol - ssint);
            dfrow = nr - 1;
            dfcol = nc - 1;
            dfint = (nr - 1) * (nc - 1);
            dfres = (nm - 1) * nr * nc;
            dftot = nm * nr * nc - 1;
            if (nm == 1)
            {
                dfres = dfint;
            }
            for (int j = 1; j <= nc; j++)
                col[j - 1] = col[j];
            fault = 0;
        }

        /// <summary>
        /// Tie test for XAgreeKendall: the means and standard deviations compared are computed values,
        /// so two values that agree to a relative tolerance of 1e-12 are treated as tied
        /// </summary>
        private static bool XAgreeTied(double a, double b)
        {
            return a == b || Math.Abs(a - b) <= 1e-12 * Math.Max(Math.Abs(a), Math.Abs(b));
        }

        /// <summary>
        /// Records a tied value so that each tie group is credited once (cf. RptKendall); returns false if already recorded
        /// </summary>
        /// <param name="v">tied value</param>
        /// <param name="tv">1-based list of tie group values already counted</param>
        /// <param name="tvn">number of values in tv</param>
        private static bool XAgreeNewTie(double v, double[] tv, ref int tvn)
        {
            for (int n = 1; n <= tvn; n++)
            {
                if (XAgreeTied(v, tv[n]))
                    return false;
            }
            tvn += 1;
            tv[tvn] = v;
            return true;
        }

        ///  <summary>
        ///  
        ///  </summary>
        ///  <param name="host"></param>
        ///  <param name="ssd">0-based array</param>
        ///  <param name="av">0-based array</param>
        /// <param name="lowerBound"></param>
        /// <param name="rx">Number of valid elements in ssd and av (from 0 to rx-1)</param>
        ///  <param name="tau"></param>
        ///  <param name="p2"></param>
        ///  <remarks></remarks>
        public static void XAgreeKendall(IProgressBarHost host, double[] ssd, double[] av, int lowerBound, ref int rx, out double tau, out double p2, out bool isLowPower, out bool isTauB)
        {
            int nxx = 0; int ls = 0;
            double sigat1 = 0; double sigat2 = 0; double sigat3 = 0;
            double sigbt1 = 0; double sigbt2 = 0; double sigbt3 = 0;
            double ps; double s = 0; double varf = 0;
            double hn = 0;
            //  Note: x and y are 1-based
            double[] x = new double[rx + 1];
            double[] y = new double[rx + 1];
            tau = Constant.MISSING;
            p2 = Constant.MISSING;
            isLowPower = false;
            isTauB = false;
            bool fault = true;
            double siga = 0;
            double sigb = 0;
            double p = 0;
            double q = 0;
            int nx = 0;
            for (int n = lowerBound; n < rx + lowerBound; n++)
            {
                if (ssd[n] != Constant.MISSING && av[n] != Constant.MISSING)
                {
                    nx += 1;
                    x[nx] = ssd[n];
                    y[nx] = av[n];
                }
            }
            try
            {
                if (nx >= 2)
                {
                    nxx = nx;
                    double gd = nxx - 1;
                    //  Tie group values already counted (1-based), so each tie group is credited once
                    double[] xtv = new double[nxx + 1];
                    double[] ytv = new double[nxx + 1];
                    int xtvn = 0;
                    int ytvn = 0;
                    using (IProgressBar progress = host.StartProgress("Calculating Kendall", true))
                    {
                        int pn;
                        for (pn = 1; pn < nxx; pn++)
                        {
                            if (progress.Update(Convert.ToDouble(pn) / gd))
                                return;

                            int xtie = 0;
                            int ytie = 0;
                            for (int N = pn + 1; N <= nxx; N++)
                            {
                                bool xTied = XAgreeTied(x[pn], x[N]);
                                bool yTied = XAgreeTied(y[pn], y[N]);
                                if (!xTied && !yTied)
                                {
                                    if ((x[pn] > x[N] && y[pn] > y[N]) || (x[pn] < x[N] && y[pn] < y[N]))
                                        p += 1.0;
                                    if ((x[pn] > x[N] && y[pn] < y[N]) || (x[pn] < x[N] && y[pn] > y[N]))
                                        q += 1.0;
                                }
                                if (xTied)
                                    xtie += 1;
                                if (yTied)
                                    ytie += 1;
                            }
                            int cnt = xtie + 1;
                            if (cnt > 1 && XAgreeNewTie(x[pn], xtv, ref xtvn))
                            {
                                siga += cnt * (cnt - 1) / 2.0;
                                sigat1 += cnt * (cnt - 1);
                                sigat2 += cnt * (cnt - 1) * (cnt - 2);
                                sigat3 += cnt * (cnt - 1) * (2 * cnt + 5);
                            }
                            cnt = ytie + 1;
                            if (cnt > 1 && XAgreeNewTie(y[pn], ytv, ref ytvn))
                            {
                                sigb += cnt * (cnt - 1) / 2.0;
                                sigbt1 += cnt * (cnt - 1);
                                sigbt2 += cnt * (cnt - 1) * (cnt - 2);
                                sigbt3 += cnt * (cnt - 1) * (2 * cnt + 5);
                            }
                        }
                    }
                    s = p - q;
                    double xn = nx;
                    hn = xn * (xn - 1.0) / 2.0;
                    double tievar1 = (xn * (xn - 1.0) * (2.0 * xn + 5.0) - sigat3 - sigbt3) / 18.0;
                    double tievar2 = sigat2 * sigbt2 / (9.0 * xn * (xn - 1.0) * (xn - 2.0));
                    double tievar3 = sigat1 * sigbt1 / (2.0 * xn * (xn - 1.0));
                    double tievar = tievar1 + tievar2 + tievar3;
                    double kendvar = xn * (xn - 1.0) * (2.0 * xn + 5.0) / 18.0;
                    if (siga != 0 || sigb != 0)
                        varf = tievar;
                    else
                        varf = kendvar;
                }
            }
            catch (Exception ex)
            {
                throw new TemplateOperationCancelledException(ex);
            }

            bool wasException = false;
            try
            {
                isTauB = siga != 0 || sigb != 0;
                if (isTauB)
                {
                    //  Every value of one variable tied: tau b is undefined
                    double denom = (hn - siga) * (hn - sigb);
                    if (denom <= 0.0)
                        throw new ArithmeticException("Kendall's tau b is undefined");
                    tau = s / Math.Sqrt(denom);
                }
                else
                    tau = s / Math.Sqrt(hn * hn);
                fault = false;
                ls = Convert.ToInt32(s);
            }
            catch (Exception)
            {
                wasException = true;
            }
            if (wasException)
            {
                ps = Constant.MISSING;
            }
            else
            {
                //  kendp gives P(S' >= ls), including ls, and the distribution of S is symmetric about zero, so the tail at and beyond a negative score is P(S' >= -ls).
                //  Folding P(S' >= ls) with its complement instead left the observed score out of that tail, so P was too small whenever tau was negative.
                ps = MathDbl.kendp(Math.Abs(ls), nxx, out fault);
                if (fault)
                    ps = Constant.MISSING;
            }
            if (wasException)
            {
                p2 = Constant.MISSING;
            }
            else if (ps == Constant.MISSING || fault || siga != 0 || sigb != 0)
            {
                double kzc = (Math.Abs(s) - 1.0) / Math.Sqrt(varf);
                double pvs = 1.0 - PDF.alnorm(kzc);
                if (pvs > 1.0 - pvs)
                    pvs = 1.0 - pvs;
                p2 = pvs * 2;
            }
            else
            {
                p2 = Math.Min(1.0, ps * 2);
            }
            isLowPower = nxx < 11;
        }

        public static StepOutput RptAgreement(IProgressBarHost host, ParameterBag parameters)
        {
            long ntot = 0;
            double sum;
            double sumvr = 0;
            double totsq = 0;
            double tot = 0;
            double sqtot = 0; double sum2tot = 0; double sumtot = 0;

            double GAMMA = parameters["ci"].AsDouble;
            if (GAMMA <= 0)
                return null;

            DataFrame frame = parameters["data"].AsDataFrame;
            int rows = frame.Variables[0].Length;
            int cols = frame.VariableCount;
            double[][] ARR2 = new double[cols][];
            for (int c = 0; c < cols; c++)
                ARR2[c] = ((DoubleVariable)frame.Variables[c]).Data;

            double[] av = new double[rows + 1];
            double[] mxd = new double[rows + 1];
            double[] xd = new double[rows + 1];
            double[] vr = new double[rows + 1];
            double[] ssd = new double[rows + 1];
            double[] xxm = new double[rows + 1];

            // Get Min, Max range (into xd) for all rows
            int rx = 0;
            for (int r = 0; r < rows; r++)
            {
                bool ok = true;
                for (int c = 0; c < cols; c++)
                {
                    if (ARR2[c][r] == Constant.MISSING)
                        ok = false;
                }
                if (ok)
                {
                    double mx = ARR2[0][r] - ARR2[1][r];
                    int cnt = 0;
                    for (int c = 0; c < cols - 1; c++)
                    {
                        for (int j = c + 1; j < cols; j++)
                        {
                            double xq = ARR2[c][r] - ARR2[j][r];
                            if (Math.Abs(xq) > Math.Abs(mx))
                                mx = xq;
                            cnt++;
                        }
                    }
                    xd[rx] = mx / cnt;
                    mxd[rx] = mx;
                    sum = 0;
                    double sumsq = 0;
                    for (int c = 0; c < cols; c++)
                    {
                        sum += ARR2[c][r];
                        sumsq += ARR2[c][r] * ARR2[c][r];
                    }
                    double avg = sum / Convert.ToDouble(cols);
                    double sumsqdev = 0;
                    for (int c = 0; c < cols; c++)
                    {
                        if (Math.Abs(sumsqdev) > 1.0E+300)
                        {
                            sumsqdev = Constant.MISSING;
                            break;
                        }
                        sumsqdev += (ARR2[c][r] - avg) * (ARR2[c][r] - avg);
                    }
                    if (sumsqdev == Constant.MISSING)
                        vr[rx] = Constant.MISSING;
                    else
                        vr[rx] = sumsqdev / Convert.ToDouble(cols - 1);
                    ssd[rx] = Math.Sqrt(vr[rx]);
                    sumvr += vr[rx];
                    av[rx] = avg;
                    tot += xd[rx];
                    totsq += xd[rx] * xd[rx];
                    for (int c = 0; c < cols; c++)
                        xxm[rx] += Math.Abs(ARR2[c][r] - av[rx]);
                    rx++;
                }
            }
            double meanvr = sumvr / rx;
            double mean = tot / rx;
            double ss = totsq - tot * tot / rx;
            double sd = Math.Sqrt(ss / (rx - 1));
            double z = PDF.gauinv(1 - (1 - GAMMA) / 2);
            // create temp variable for copying values 
            double[] transTemp0 = new double[rx];
            Array.Copy(av, transTemp0, Math.Min(av.Length, transTemp0.Length));
            av = transTemp0;
            // create temp variable for copying values 
            double[] transTemp1 = new double[rx];
            Array.Copy(mxd, transTemp1, Math.Min(mxd.Length, transTemp1.Length));
            mxd = transTemp1;
            // xd not used from here
            // double[] transTemp2 = new double[rx]; 
            // Array.Copy( xd, transTemp2, Math.Min( xd.Length, transTemp2.Length ) ); 
            // xd = transTemp2; 
            // vr not used from here
            // double[] transTemp3 = new double[rx]; 
            // Array.Copy( vr, transTemp3, Math.Min( vr.Length, transTemp3.Length ) ); 
            // vr = transTemp3; 
            // create temp variable for copying values 
            double[] transTemp4 = new double[rx];
            Array.Copy(ssd, transTemp4, Math.Min(ssd.Length, transTemp4.Length));
            ssd = transTemp4;
            // create temp variable for copying values 
            double[] transTemp5 = new double[rx];
            Array.Copy(xxm, transTemp5, Math.Min(xxm.Length, transTemp5.Length));
            xxm = transTemp5;
            double wssd = Math.Sqrt(meanvr);
            double rep = Math.Sqrt(2) * z * wssd;
            MathDbl.civ(0, out double cit, GAMMA, out double P0);
            double lla = mean - cit * sd;
            double ula = mean + cit * sd;
            for (int r = 0; r < rows; r++)
            {
                long nx = 0;
                double sq = 0.0;
                sum = 0.0;
                for (int c = 0; c < cols; c++)
                {
                    if (ARR2[c][r] != Constant.MISSING)
                    {
                        nx++;
                        sum += ARR2[c][r];
                        sq += ARR2[c][r] * ARR2[c][r];
                    }
                }
                if (nx != cols)
                    continue; // ICC uses the same complete rows as the rest of the report
                sqtot += sq;
                if (nx != 0)
                    sum2tot += sum * sum / nx;
                ntot += nx;
                sumtot += sum;
            }
            string tlist = string.Empty;
            for (int c = 0; c < cols; c++)
            {
                if (c > 0)
                    tlist += ", ";
                tlist += frame.Variables[c].Title;
            }
            double cc = sumtot * sumtot / ntot;
            double sstot = sqtot - cc;
            double ssgroup = sum2tot - cc;
            double m = cols;
            //  One-way random effects ANOVA estimator ICC(1) = (MSB - MSW) / (MSB + (m - 1) MSW)
            //  with the exact F-based confidence interval (Shrout & Fleiss 1979; McGraw & Wong 1996)
            double n = rx;
            double icc_df1 = n - 1.0;
            double icc_df2 = n * (m - 1.0);
            double msb = ssgroup / icc_df1;
            double msw = (sstot - ssgroup) / icc_df2;
            double icc = (msb - msw) / (msb + (m - 1.0) * msw);
            double fratio = msb / msw;
            //  PDF.ffromp(dfd, dfn, p) returns the F quantile whose upper tail area is p
            double fupper = PDF.ffromp(icc_df2, icc_df1, (1.0 - GAMMA) / 2.0);
            double flower = PDF.ffromp(icc_df2, icc_df1, 1.0 - (1.0 - GAMMA) / 2.0);
            double icc_lcl = (fratio / fupper - 1.0) / (fratio / fupper + m - 1.0);
            double icc_ucl = (fratio / flower - 1.0) / (fratio / flower + m - 1.0);
            double icc_min = -1.0 / (m - 1.0);
            icc_lcl = Math.Max(icc_min, Math.Min(1.0, icc_lcl));
            icc_ucl = Math.Max(icc_min, Math.Min(1.0, icc_ucl));
            double tau;
            double p2;
            bool isLowPower = false;
            bool isTauB = false;
            if (rx > 2)
            {
                XAgreeKendall(host, ssd, av, 0, ref rx, out tau, out p2, out isLowPower, out isTauB);
            }
            else
            {
                tau = Constant.MISSING;
                p2 = Constant.MISSING;
            }

            ParameterBag outputParameters = new();

            outputParameters.AddOutput("tlist", tlist);
            if (cols == 2)
            {
                ParameterBag blockParameters = new();
                blockParameters.AddOutput("pc", 100 * (1 - P0));
                blockParameters.AddOutput("from", lla);
                blockParameters.AddOutput("to", ula);
                IList<ParameterBag> allResults = new List<ParameterBag>();
                allResults.Add(blockParameters);
                //  The name after the asterisk must match agree.creole's <block name="all">, or the limits of agreement are not printed
                outputParameters.AddOutput("*all", allResults);
            }
            outputParameters.AddOutput("icc", icc);
            outputParameters.AddOutput("icc_pc", 100 * GAMMA);
            outputParameters.AddOutput("icc_lcl", icc_lcl);
            outputParameters.AddOutput("icc_ucl", icc_ucl);
            outputParameters.AddOutput("icc_df1", icc_df1);
            outputParameters.AddOutput("icc_df2", icc_df2);
            outputParameters.AddOutput("wssd", wssd);
            outputParameters.AddOutput("tau_b_addendum", isTauB ? "b " : string.Empty);
            outputParameters.AddOutput("tau", tau);
            outputParameters.AddOutput("p2", p2);
            outputParameters.AddOutput("low_power_warn", isLowPower ? " (low power)" : string.Empty);
            outputParameters.AddOutput("pc", 1 - GAMMA);
            outputParameters.AddOutput("rep", rep);

            //  Add our derived arrays to the output so that charts can be plotted from them
            outputParameters.AddOutput("av", new DataFrame(new DoubleVariable(av)));
            outputParameters.AddOutput("ssd", new DataFrame(new DoubleVariable(ssd)));
            outputParameters.AddOutput("mxd", new DataFrame(new DoubleVariable(mxd)));
            outputParameters.AddOutput("P0", P0);
            outputParameters.AddOutput("mean", mean);
            outputParameters.AddOutput("lla", lla);
            outputParameters.AddOutput("ula", ula);
            //  Repeatability
            //  SDChart.PlotXY(av, ssd, rx, "subject mean", "subject standard deviation", "Repeatability Plot", False, -1)
            //  Agreement plot (elided)
            //  Q-Q plot
            const double p_start = 0.01;
            const double p_finish = 0.99;
            double p_inc = (p_finish - p_start) / (rx - 1);
            double P = p_start;
            double df = cols - 1;
            double[] pvalues = new double[rx];
            for (int r = 0; r < rx; r++)
            {
                pvalues[r] = PDF.ppchi2(P, df, out int fault);
                P += p_inc;
            }
            Array.Sort(xxm);
            outputParameters.AddOutput("df", df);
            outputParameters.AddOutput("pvalues", new DataFrame(new DoubleVariable(pvalues)));
            outputParameters.AddOutput("xxm", new DataFrame(new DoubleVariable(xxm)));
            return new StepOutput(outputParameters);
        }

        public static StepOutput RptOneWay(ParameterBag parameters)
        {
            DataFrame frame = parameters["data"].AsDataFrame;

            int[] tnx = new int[frame.VariableCount];
            double[] mean = new double[frame.VariableCount];
            double sumtot = 0.0;
            int ntot = 0;
            string tlist = string.Empty;
            for (int d = 0; d < frame.VariableCount; d++)
            {
                DoubleVariable v = frame.Variables[d]as DoubleVariable;
                int nx = 0;
                double sum = 0;
                foreach (double val in v.Data)
                {
                    if (val != Constant.MISSING)
                    {
                        nx++;
                        sum += val;
                    }
                }
                tnx[d] = nx;
                ntot += nx;
                mean[d] = sum / nx;
                sumtot += sum;

                if (d > 0)
                    tlist += ", ";
                tlist += v.Title;
            }

            double gm = sumtot / ntot;
            double sstot = 0;
            for (int d = 0; d < frame.VariableCount; d++)
            {
                DoubleVariable v = frame.Variables[d]as DoubleVariable;
                foreach (double val in v.Data)
                    if (val != Constant.MISSING)
                        sstot += (val - gm) * (val - gm);
            }

            double ssgroup = 0;
            for (int d = 0; d < frame.VariableCount; d++)
                ssgroup += (mean[d] - gm) * (mean[d] - gm) * tnx[d];

            int dftot = ntot - 1;
            int dfgroup = frame.VariableCount - 1;
            double sserror = 0;   // within groups, accumulated directly rather than by subtraction from the total
            for (int d = 0; d < frame.VariableCount; d++)
            {
                DoubleVariable v = frame.Variables[d] as DoubleVariable;
                foreach (double val in v.Data)
                    if (val != Constant.MISSING)
                        sserror += (val - mean[d]) * (val - mean[d]);
            }
            int dferr = ntot - frame.VariableCount;
            double msgroup = ssgroup / dfgroup;
            double mserr = sserror / dferr;

            ParameterBag outputParameters = new();
            outputParameters.AddOutput("tlist", tlist);
            outputParameters.AddOutput("b_sum", ssgroup);
            outputParameters.AddOutput("b_df", dfgroup);
            outputParameters.AddOutput("b_mean", msgroup);

            outputParameters.AddOutput("w_sum", sserror);
            outputParameters.AddOutput("w_df", dferr);
            outputParameters.AddOutput("w_mean", mserr);

            outputParameters.AddOutput("t_sum", sstot);
            outputParameters.AddOutput("t_df", dftot);

            outputParameters.AddOutput("f", msgroup / mserr);
            double P = PDF.fvalp(msgroup / mserr, dfgroup, dferr);
            outputParameters.AddOutput("p", P);

            //  For other operations
            outputParameters.AddInput("dfres", dferr);
            outputParameters.AddInput("msres", mserr);
            outputParameters.AddInput("mean", mean);
            outputParameters.AddInput("tnx", tnx);
            return new StepOutput(outputParameters);
        }

        ///  <summary>
        ///  Given one or more data columns and a grouping column: split each data column in turn into variables based on the grouping column, and run one one-way ANOVA for each data column.
        ///  </summary>
        public static StepOutput RptGroupedOneWay(ParameterBag parameters)
        {
            DataFrame data = parameters["data"].AsDataFrame;
            DataFrame groupFrame = parameters["groups"].AsDataFrame;
            ClassifierVariable groupVariable = groupFrame.Variables[0] as ClassifierVariable;

            ParameterBag outputParameters = new();
            List<ParameterBag> aList = new();
            outputParameters.AddOutput("*a", aList);
            foreach (DoubleVariable v in data.Variables)
            {
                DataFrame oneWayFrame = new();
                foreach (Group g in groupVariable.Groups)
                {
                    double groupId = g.Id;
                    string oneWayTitle = g.Label;
                    DoubleVariable oneWayVariable = new(g.NBin, oneWayTitle);
                    int oneWayIndex = 0;
                    //  Use the shorter of the group variable and the data variable
                    int vLimit = Math.Min(groupVariable.Length - 1, v.Length - 1);
                    for (int vIndex = 0; vIndex <= vLimit; vIndex++)
                    {
                        if (groupVariable.Data[vIndex] == groupId && v.Data[vIndex] != Constant.MISSING)
                        {
                            oneWayVariable.SetData(oneWayIndex, v.Data[vIndex]);
                            oneWayIndex++;
                        }
                    }
                    //  By now, oneWayIndex contains the number of non-MISSING elements.  Truncate the variable if required.
                    oneWayVariable.TruncateDataToLength(oneWayIndex);
                    oneWayFrame.Variables.Add(oneWayVariable);
                }

                ParameterBag oneWayParameters = new() { {"data", FilledParameterFactory.Input(oneWayFrame)}};
                StepOutput oneWayResult = RptOneWay(oneWayParameters);
                oneWayResult.ParameterBag.AddOutput("variableName", v.Title);
                aList.Add(oneWayResult.ParameterBag);
            }
            return new StepOutput(outputParameters);
        }

        ///  <summary>
        ///  Given one or more data columns, a row grouping column and a column grouping column: split each data column in turn into variables based on the grouping columns, and run one two-way ANOVA for each data column.
        ///  </summary>
        public static StepOutput RptGroupedTwoWay(ParameterBag parameters)
        {
            DataFrame data = parameters["data"].AsDataFrame;
            DataFrame blocksFrame = parameters["blocks"].AsDataFrame;
            ClassifierVariable blocksVariable = blocksFrame.Variables[0] as ClassifierVariable;
            DataFrame treatmentsFrame = parameters["treatments"].AsDataFrame;
            ClassifierVariable treatmentsVariable = treatmentsFrame.Variables[0] as ClassifierVariable;

            ParameterBag outputParameters = new();
            List<ParameterBag> aList = new();
            outputParameters.AddOutput("*a", aList);
            int maxBlocks = blocksVariable.GroupCount;
            foreach (DoubleVariable v in data.Variables)
            {
                DataFrame twoWayFrame = new();
                //  One variable per treatment - this assumes the groups are ordered with their IDs starting from 0 at index 0.
                //  All are initially filled with Constant.MISSING
                foreach (Group g in treatmentsVariable.Groups)
                {
                    DoubleVariable newV = new(maxBlocks, g.Label);
                    for (int i = 0; i < maxBlocks; i++)
                        newV.Data[i] = Constant.MISSING;
                    twoWayFrame.Variables.Add(newV);
                }
                // Use the shorter of the group variables (which are guaranteed to be the same length) and the data variable
                int vLimit = Math.Min(blocksVariable.Length - 1, v.Length - 1);
                for (int vIndex = 0; vIndex <= vLimit; vIndex++)
                {
                    if (v.Data[vIndex] != Constant.MISSING)
                    {
                        int blockIndex = Convert.ToInt32(blocksVariable.Data[vIndex]);
                        int treatmentIndex = Convert.ToInt32(treatmentsVariable.Data[vIndex]);
                        DoubleVariable treatmentVariable = twoWayFrame.Variables[treatmentIndex]as DoubleVariable;
                        treatmentVariable.SetData(blockIndex, v.Data[vIndex]);
                    }
                }

                ParameterBag twoWayParameters = new() { {"data", FilledParameterFactory.Input(twoWayFrame)}};
                StepOutput twoWayResult = RptTwoWay(twoWayParameters);
                twoWayResult.ParameterBag.AddOutput("variableName", v.Title);
                aList.Add(twoWayResult.ParameterBag);
            }
            return new StepOutput(outputParameters);
        }

        ///  <remarks>Precondition: the frame passed in has equal-length columns.</remarks>
        public static StepOutput RptTwoWay(ParameterBag parameters)
        {
            DataFrame frame = parameters["data"].AsDataFrame;
            DoubleVariable v0 = frame.Variables[0]as DoubleVariable;

            int nc = frame.VariableCount;
            int nr = 0;
            int[] tnx = new int[nc + 1];
            double[,,] y = new double[2, v0.Length + 1, nc + 1];

            int skipped = 0;
            for (int N = 0; N < v0.Length; N++)
            {
                bool skip = false;
                for (int d = 0; d < frame.VariableCount; d++)
                {
                    if ((frame.Variables[d] as DoubleVariable).Data[N] == Constant.MISSING)
                    {
                        skip = true;
                        skipped++;
                        break;
                    }
                }
                if (!skip)
                {
                    nr++;
                    for (int d = 0; d < frame.VariableCount; d++)
                        y[1, nr, d + 1] = (frame.Variables[d] as DoubleVariable).Data[N];
                }
            }
            for (int d = 0; d < frame.VariableCount; d++)
                tnx[d] = nr;

            string wrn;
            if (skipped != 0)
                wrn = "   (" + Formatting.WRNCOLON + skipped + " out of " + (skipped + nr) + " rows were skipped due to missing values)";
            else
                wrn = string.Empty;

            XTwoWay(y, out double[] mean, nr, nc, 1, out double ssrow, out double sscol, out double scrap, out double sstot, out double ssres, out int dfrow, out int dfcol, out int iscrap, out int dftot, out int dfres, out int fault);

            if (fault != 0)
                throw new Exception("Invalid calculation");

            string tlist = string.Empty;
            for (int d = 0; d < frame.VariableCount; d++)
            {
                //  Col(0).AddItem(frame.Variables(D).Title & " (" & Formatting.XRound(mean(D), 4) & ")")
                if (d == 0)
                    tlist = frame.Variables[d].Title;
                else
                    tlist = tlist + ", " + frame.Variables[d].Title;
            }

            double msrow = ssrow / Convert.ToDouble(dfrow);
            double mscol = sscol / Convert.ToDouble(dfcol);
            double msres = ssres / Convert.ToDouble(dfres);

            if (wrn.Length > 0)
                tlist = tlist + "\r\n" + wrn;
            ParameterBag outputParameters = new();
            outputParameters.AddOutput("tlist", tlist);
            outputParameters.AddOutput("sub_sum", ssrow);
            outputParameters.AddOutput("sub_df", dfrow);
            outputParameters.AddOutput("sub_mean", msrow);
            outputParameters.AddOutput("grp_sum", sscol);
            outputParameters.AddOutput("grp_df", dfcol);
            outputParameters.AddOutput("grp_mean", mscol);
            outputParameters.AddOutput("res_sum", ssres);
            outputParameters.AddOutput("res_df", dfres);
            outputParameters.AddOutput("res_mean", msres);
            outputParameters.AddOutput("tot_sum", sstot);
            outputParameters.AddOutput("tot_df", dftot);
            outputParameters.AddOutput("sub_vr", msrow / msres);
            outputParameters.AddOutput("sub_p", PDF.fvalp(msrow / msres, Convert.ToDouble(dfrow), Convert.ToDouble(dfres)));
            outputParameters.AddOutput("grp_vr", mscol / msres);
            double P = PDF.fvalp(mscol / msres, Convert.ToDouble(dfcol), Convert.ToDouble(dfres));
            outputParameters.AddOutput("grp_p", P);

            //  Add our calculated values for potential later consumption by other functions
            outputParameters.AddInput("dfres", dfres);
            outputParameters.AddInput("mean", mean);
            outputParameters.AddInput("msres", msres);
            outputParameters.AddInput("ssgp", sscol);
            outputParameters.AddInput("sstot", sstot);
            outputParameters.AddInput("tnx", tnx);
            return new StepOutput(outputParameters);
        }

        public static StepOutput RptTwoMulti(ParameterBag parameters)
        {
            DataFrame2D frame = parameters["data2d"].AsDataFrame2D;

            int nc = frame.Variables[0].Count;
            int nr = frame.VariableCount;
            int nm = frame.MaxRows;
            double[] tnx = new double[nc + 1];
            double[,,] y = new double[nm + 1, nr + 1, nc + 1];
            int absconders = 0;

            DataFrame outputFrame = new();
            outputFrame.EnsureVariables(nc);   //  one column per treatment, whatever the number of blocks

            for (int d = 0; d < nc; d++)
            {
                int missingInTreatment = 0;
                double sumOfReciprocals = 0.0;   //  of the cell counts, over the blocks
                for (int n = 1; n <= nr; n++)
                {
                    int adit = 0;
                    double adsum = 0;
                    IVariable candidate = frame.Variables[n - 1][d];
                    if (candidate == null)   //  a block and treatment combination with no rows at all (data selected by group identifiers)
                        throw new TemplateOperationCancelledException("Invalid data: a few repeat observations can be missing but not whole cells.", "Replicated Two Way ANOVA");
                    {
                        DoubleVariable v = candidate as DoubleVariable;
                        for (int q = 0; q < nm; q++)
                        {
                            if (v.Data[q] != Constant.MISSING)
                            {
                                adit++;
                                adsum += v.Data[q];
                            }
                            else
                            {
                                absconders++;
                            }
                        }
                        if (adit <= 0)
                            throw new TemplateOperationCancelledException("Invalid data: a few repeat observations can be missing but not whole cells.", "Replicated Two Way ANOVA");
                        double spare = adsum / adit;
                        for (int q = 0; q < nm; q++)
                        {
                            double item = v.Data[q] == Constant.MISSING ? spare : v.Data[q];
                            y[q + 1, n, d + 1] = item;
                        }
                        missingInTreatment += nm - adit;
                        sumOfReciprocals += 1.0 / adit;
                    }
                }
                //  Observations per treatment, for the multiple comparison methods that may follow. A treatment mean is the average
                //  of its cell means, so its variance is the residual mean square times the sum over the blocks of 1/(cell count),
                //  divided by the square of the number of blocks. The methods take the size that gives that variance: blocks squared
                //  over the sum, which is blocks times repeats when no repeat is missing. A missing repeat is replaced by the mean of
                //  its cell, which adds no information, so the nominal count would make the intervals too narrow.
                tnx[d] = missingInTreatment == 0 ? nr * nm : nr * nr / sumOfReciprocals;
                string title = "Treatment " + (1 + d).ToString();
                outputFrame.Variables[d] = new DoubleVariable(null, title);
            }

            XTwoWay(y, out double[] mean, nr, nc, nm, out double ssrow, out double sscol, out double ssint, out double sstot, out double ssres, out int dfrow, out int dfcol, out int dfint, out int dftot, out int dfres, out int fault);

            string tlist = string.Empty;
            for (int d = 0; d < nc; d++)
            {
                //  Col(0).AddItem(CDAT1(D).title & " (" & Formatting.XRound(mean(D), 4) & ")")
                if (d == 0)
                    tlist = outputFrame.Variables[d].Title;
                else
                    tlist = tlist + ", " + outputFrame.Variables[d].Title;
            }

            if (fault != 0)
                throw new Exception("Invalid calculation");

            if (absconders > 0)
            {
                //  A missing repeat observation was replaced by the mean of the others in its cell, so it adds nothing to
                //  the residual sum of squares and earns no residual (or total) degree of freedom
                dfres -= absconders;
                dftot -= absconders;
                if (dfres < 1)
                    throw new TemplateOperationCancelledException("Too many missing repeat observations: no residual degrees of freedom remain.", "Replicated Two Way ANOVA");
            }

            double msrow = ssrow / Convert.ToDouble(dfrow);
            double mscol = sscol / Convert.ToDouble(dfcol);
            double msint = ssint / Convert.ToDouble(dfint);
            double msres = ssres / Convert.ToDouble(dfres);
            // double mstot = sstot / Convert.ToDouble( dftot ); mstot is unused.  PJC 2012/04/09

            ParameterBag outputParameters = new();
            outputParameters.AddOutput("tlist", frame.Name);

            outputParameters.AddOutput("sub_sum", ssrow);
            outputParameters.AddOutput("sub_df", dfrow);
            outputParameters.AddOutput("sub_mean", msrow);

            outputParameters.AddOutput("grp_sum", sscol);
            outputParameters.AddOutput("grp_df", dfcol);
            outputParameters.AddOutput("grp_mean", mscol);

            outputParameters.AddOutput("int_sum", ssint);
            outputParameters.AddOutput("int_df", dfint);
            outputParameters.AddOutput("int_mean", msint);

            outputParameters.AddOutput("res_sum", ssres);
            outputParameters.AddOutput("res_df", dfres);
            outputParameters.AddOutput("res_mean", msres);

            outputParameters.AddOutput("tot_sum", sstot);
            outputParameters.AddOutput("tot_df", dftot);

            outputParameters.AddOutput("sub_vr", msrow / msres);
            outputParameters.AddOutput("sub_p", PDF.fvalp(msrow / msres, Convert.ToDouble(dfrow), Convert.ToDouble(dfres)));

            outputParameters.AddOutput("grp_vr", mscol / msres);
            double P = PDF.fvalp(mscol / msres, Convert.ToDouble(dfcol), Convert.ToDouble(dfres));
            outputParameters.AddOutput("grp_p", P);

            outputParameters.AddOutput("int_vr", msint / msres);
            outputParameters.AddOutput("int_p", PDF.fvalp(msint / msres, Convert.ToDouble(dfint), Convert.ToDouble(dfres)));

            if (absconders != 0)
            {
                IList<ParameterBag> warnList = new List<ParameterBag>();
                ParameterBag warnParameters = new();
                warnParameters.AddOutput("warn", "WARNING - " + absconders.ToString() + " missing data - substitution made, residual degrees of freedom reduced by " + absconders.ToString());
                warnList.Add(warnParameters);
                outputParameters.AddOutput("*warn", warnList);
            }
            else
            {
                outputParameters.AddOutput("*warn", null);
            }

            //  Add our calculated values for potential later consumption by other functions
            outputParameters.AddInput("dfres", dfres);
            outputParameters.AddInput("mean", mean);
            outputParameters.AddInput("msres", msres);
            outputParameters.AddInput("ssgp", sscol);
            outputParameters.AddInput("sstot", sstot);
            outputParameters.AddInput("tnx", tnx);
            outputParameters.AddInput("equivalent_sizes", absconders > 0);
            outputParameters.AddInput("data", outputFrame);

            return new StepOutput(outputParameters);
        }

        public static StepOutput RptTwoNest(ParameterBag parameters)
        {
            DataFrame2D frame = parameters["data2d"].AsDataFrame2D;

            int ivar = 0;
            for (int j = 0; j < frame.VariableCount; j++)
                ivar += frame.Variables[j].Count;
            int[] nobs = new int[ivar + 1];
            double[] sgbar = new double[ivar + 1];
            ivar = 0;
            int ctr = 0;
            string tlist = string.Empty;
            double[] y = new double[1 + 1];
            for (int j = 0; j < frame.VariableCount; j++)
            {
                tlist += " (";
                for (int i = 0; i < frame.Variables[j].Count; i++)
                {
                    //  Input variables may be jagged; ensure that null variables don't cause issues
                    IVariable v = frame.Variables[j][i];
                    if (v != null)
                    {
                        if (i == 0)
                            tlist += v.Title;
                        else
                            tlist += ", " + v.Title;
                        ivar += 1;
                        int eobs = 0;
                        DoubleVariable dv = v as DoubleVariable;
                        foreach (double val in dv.Data)
                        {
                            if (val != Constant.MISSING)
                            {
                                ctr += 1;
                                eobs += 1;
                                // create temp variable for copying values 
                                double[] transTemp6 = new double[ctr + 1];
                                Array.Copy(y, transTemp6, Math.Min(y.Length, transTemp6.Length));
                                y = transTemp6;
                                y[ctr] = val;
                            }
                        }
                        nobs[ivar] = eobs;
                    }
                }
                tlist += ")";
            }

            double[] ss = new double[5 + 1];
            int[] idf = new int[5 + 1];
            double[] f = new double[3 + 1];
            double[] fp = new double[3 + 1];
            int[] ngp = null;
            double[] gbar = null;
            double gm = 0;
            XTwoHier(frame, y, ctr, nobs, ivar, ref ngp, ref gbar, ref sgbar, ref gm, ref ss, ref idf, ref f, ref fp, out bool fault);

            ParameterBag outputParameters = new();
            if (!fault)
            {
                outputParameters.AddOutput("tlist", tlist);

                outputParameters.AddOutput("grp_sum", ss[1]);
                outputParameters.AddOutput("grp_df", idf[1]);
                outputParameters.AddOutput("grp_mean", ss[1] / Convert.ToDouble(idf[1]));

                outputParameters.AddOutput("sub_sum", ss[2]);
                outputParameters.AddOutput("sub_df", idf[2]);
                outputParameters.AddOutput("sub_mean", ss[2] / Convert.ToDouble(idf[2]));

                outputParameters.AddOutput("res_sum", ss[3]);
                outputParameters.AddOutput("res_df", idf[3]);
                outputParameters.AddOutput("res_mean", ss[3] / Convert.ToDouble(idf[3]));

                outputParameters.AddOutput("tot_sum", ss[4]);
                outputParameters.AddOutput("tot_df", idf[4]);

                outputParameters.AddOutput("f_1", f[1]);
                outputParameters.AddOutput("p_1", fp[1]);

                double xx = ss[1] / Convert.ToDouble(idf[1]) / (ss[2] / Convert.ToDouble(idf[2]));
                outputParameters.AddOutput("f_2", xx);
                outputParameters.AddOutput("p_2", PDF.fvalp(xx, Convert.ToDouble(idf[1]), Convert.ToDouble(idf[2])));

                outputParameters.AddOutput("f_3", f[2]);
                outputParameters.AddOutput("p_3", fp[2]);
            }
            else
            {
                throw new TemplateOperationCancelledException("Each subgroup must contain at least one observation, and there must be at least two groups.", "Nested ANOVA");
            }

            //  Add our calculated values for potential later consumption by other functions
            outputParameters.AddInput("ctr", ctr);
            outputParameters.AddInput("ngp", ngp);
            outputParameters.AddInput("gbar", gbar);
            outputParameters.AddInput("sgbar", sgbar);
            outputParameters.AddInput("gm", gm);

            return new StepOutput(outputParameters);
        }

        public static StepOutput RptBonferroni(ParameterBag parameters)
        {
            DataFrame frame = parameters["data"].AsDataFrame;
            double GAMMA = parameters["gamma"].AsDouble;
            int[] variables = (int[])parameters["variables"].AsObject;
            int z_va = variables[0];
            int z_vb = variables[1];
            int comparisons = parameters["comparisons"].AsInt32;

            ParameterCarrier carrier = FindOrCalculateParameters(parameters);
            if (carrier.Dferr < 1)
                throw new TemplateOperationCancelledException("These comparisons need at least one residual degree of freedom.", "Bonferroni Comparisons");

            if (comparisons < 1)
                comparisons = 1;

            double means = carrier.Mean[z_va] - carrier.Mean[z_vb];
            double se = Math.Sqrt(carrier.Msx * (1.0 / carrier.Tnx[z_vb] + 1.0 / carrier.Tnx[z_va]));
            double tav = means / se;
            MathDbl.civ(carrier.Dferr, out double cit, GAMMA, out double P0);
            //  Simultaneous (Bonferroni-adjusted) interval: each of the k comparisons at confidence 1 - alpha/k
            MathDbl.civ(carrier.Dferr, out double citAdj, 1.0 - (1.0 - GAMMA) / comparisons, out double P0Adj);

            ParameterBag outputParameters = new();
            outputParameters.AddOutput("var_a", frame.Variables[z_va].Title);
            outputParameters.AddOutput("var_b", frame.Variables[z_vb].Title);
            outputParameters.AddOutput("a-b", means);
            outputParameters.AddOutput("std_err", se);
            outputParameters.AddOutput("groups", frame.VariableCount);
            outputParameters.AddOutput("pc", 100 * (1 - P0));
            outputParameters.AddOutput("from", means - cit * se);
            outputParameters.AddOutput("to", means + cit * se);
            outputParameters.AddOutput("adj_pc", 100 * (1 - P0Adj));
            outputParameters.AddOutput("adj_from", means - citAdj * se);
            outputParameters.AddOutput("adj_to", means + citAdj * se);
            outputParameters.AddOutput("t", tav);
            outputParameters.AddOutput("df", carrier.Dferr);
            double P = PDF.tvalp(Math.Abs(tav), carrier.Dferr);
            if (P > 1.0 - P)
                P = 1.0 - P;
            outputParameters.AddOutput("p", P * 2.0);
            string qx = comparisons + " comparison" + (comparisons == 1 ? string.Empty : "s");
            outputParameters.AddOutput("comp", qx);
            outputParameters.AddOutput("bonf", (1.0 - GAMMA) / comparisons);
            return new StepOutput(outputParameters);
        }

        public static StepOutput RptTukey(ParameterBag parameters)
        {
            DataFrame frame = parameters["data"].AsDataFrame;
            double gamma = parameters["gamma"].AsDouble;
            ParameterCarrier carrier = FindOrCalculateParameters(parameters);
            double[] tnx = carrier.Tnx;
            double[] mean = carrier.Mean;
            double mserr = carrier.Msx;
            if (carrier.Dferr < 1)
                throw new TemplateOperationCancelledException("These comparisons need at least one residual degree of freedom.", "Tukey Contrasts");

            int k = frame.VariableCount - 1;
            int kn = k + 1;
            double[] lam = new double[k + 1]; //  1-based
            Contraster[] hold = new Contraster[kn * (int)Math.Floor((kn - 1) / 2.0 + 0.5) + 1]; //  1-based

            bool nSame = true;
            double ntot = 0;
            double lastTnx = 0;
            for (int n = 0; n <= k; n++)
            {
                ntot += tnx[n];
                if (n > 0 && nSame && !SameSize(tnx[n], lastTnx))
                    nSame = false;
                lastTnx = tnx[n];
            }
            int nu = carrier.Dferr;   //  the residual degrees of freedom of the analysis these comparisons follow (one way, or two way)
            double pse = Math.Sqrt(mserr);

            for (int i = 1; i <= k; i++)
                lam[i] = 1.0 / Math.Sqrt(2.0);

            double dalpha = 1.0 - gamma;
            if (dalpha <= 0.0 || dalpha > 1.0)
                dalpha = 0.05;
            double cc = 1.0 - dalpha;

            int ifault;
            double q = PDF.quantsr(cc, Convert.ToDouble(k + 1), Convert.ToDouble(nu));
            if (q == Constant.MISSING)
                throw new TemplateOperationCancelledException("Fault in calculation", "Tukey Contrasts");
            double d = q / Math.Sqrt(2.0); //  Hsu's |q*|, the two-sided critical value for all the pairwise comparisons: with equal correlations, as here, the Studentized range point over root 2

            ParameterBag outputParameters = new();

            string lab = nSame ? "Tukey" : "Tukey-Kramer";
            outputParameters.AddOutput("method", lab);
            outputParameters.AddOutput("q", q);
            outputParameters.AddOutput("d", d);
            outputParameters.AddOutput("psd", pse);
            outputParameters.AddOutput("cn", tnx[0]);
            outputParameters.AddOutput("pc", 100 * cc);

            int ctr = 0;
            for (int i = 0; i < k; i++)
            {
                for (int j = i + 1; j <= k; j++)
                {
                    ctr++;
                    double delta = mean[i] - mean[j];
                    hold[ctr] = new Contraster { Delta = delta, Lab1 = frame.Variables[i].Title, Lab2 = frame.Variables[j].Title, Mean1 = mean[i], Mean2 = mean[j] };
                    double t;
                    if (nSame)
                        t = 1.0 / Math.Sqrt(tnx[0]) * pse;
                    else
                        t = Math.Sqrt(mserr / 2.0 * (1.0 / tnx[j] + 1.0 / tnx[i]));
                    // The Shaffer-Holm statistic p 18 Hsu: the Studentized range statistic |L| / (s / root n), or its Tukey-Kramer form.
                    // With no residual variation (t = 0) a zero difference gets 0 and any other difference infinity.
                    hold[ctr].Absdelta = t > 0.0 ? Math.Abs(delta / t) : (delta == 0.0 ? 0.0 : double.PositiveInfinity);
                    // Lci = delta - d * pse * Sqr(1# / tnx(j) + 1# / tnx(i))
                    double lci = delta - t * q;
                    hold[ctr].Ll = lci;
                    // Uci = delta + d * pse * Sqr(1# / tnx(j) + 1# / tnx(i))
                    double uci = delta + t * q;
                    hold[ctr].Ul = uci;
                    // Call PPQ2(CLng(k), lam(1), NU, py, delta / (pse * Sqr(1# / tnx(j) + 1# / tnx(i))), ifault)
                    // py = 1# - Abs(py)
                    double px;
                    if (t > 0.0)
                    {
                        px = PDF.probsr(hold[ctr].Absdelta, Convert.ToDouble(k + 1), Convert.ToDouble(nu));
                        if (px != Constant.MISSING)
                        {
                            px = 1.0 - px;
                        }
                        else
                        {
                            ExFortran.ppq2(k, lam, nu, out px, delta / (pse * Math.Sqrt(1.0 / Convert.ToDouble(tnx[j]) + 1.0 / Convert.ToDouble(tnx[i]))), out ifault);
                            if (ifault == 0)
                                px = 1.0 - Math.Abs(px);
                            else
                                px = Constant.MISSING;
                        }
                    }
                    else
                    {
                        px = delta == 0.0 ? 1.0 : 0.0;
                    }
                    hold[ctr].P = px;
                    hold[ctr].Significant = px != Constant.MISSING && px < dalpha;
                }
            }

            //  Sort in descending order of ABSDELTA
            Array.Sort(hold, 1, ctr);

            IList<ParameterBag> differencesList = new List<ParameterBag>();
            bool halted = false;
            for (int i = 1; i <= ctr; i++)
            {
                ParameterBag differencesParameters = new();
                differencesList.Add(differencesParameters);
                differencesParameters.AddOutput("cf1", hold[i].Lab1);
                differencesParameters.AddOutput("cf2", hold[i].Lab2);
                differencesParameters.AddOutput("delta", hold[i].Delta);
                differencesParameters.AddOutput("lci", hold[i].Ll);
                differencesParameters.AddOutput("uci", hold[i].Ul);
                differencesParameters.AddOutput("t", hold[i].Absdelta);
                if (!halted && hold[i].P >= dalpha)
                {
                    halted = true;
                    differencesParameters.AddOutput("stop_marker", " {stop}");
                }
                differencesParameters.AddOutput("p", hold[i].P);
            }
            outputParameters.AddOutput("*differences", differencesList);
            outputParameters.AddOutput("*summary", ContrasterSummary(hold, 1, ctr, dalpha));
            return new StepOutput(outputParameters);
        }

        public static StepOutput RptScheffe(ParameterBag parameters)
        {
            DataFrame frame = parameters["data"].AsDataFrame;
            double gamma = parameters["gamma"].AsDouble;
            ParameterCarrier carrier = FindOrCalculateParameters(parameters);
            double[] tnx = carrier.Tnx;
            double[] mean = carrier.Mean;
            double msx = carrier.Msx;
            if (carrier.Dferr < 1)
                throw new TemplateOperationCancelledException("These comparisons need at least one residual degree of freedom.", "Scheffe Contrasts");

            int kn = frame.VariableCount;
            Contraster[] hold = new Contraster[kn * (int)Math.Floor((kn - 1) / 2.0 + 0.5) + 1]; //  1-based

            double totn = 0;
            for (int n = 0; n < kn; n++)
                totn += tnx[n];

            double palpha = 1.0 - gamma;
            if (palpha <= 0 || palpha >= 1)
                palpha = 0.05;

            double dfn = kn - 1;
            double dfd = carrier.Dferr;   //  the residual degrees of freedom of the analysis these comparisons follow
            double f = PDF.ffromp(dfd, dfn, palpha);
            double crit = Math.Sqrt(dfn * f);
            if (f == Constant.MISSING)
                crit = Constant.MISSING;

            ParameterBag outputParameters = new();
            outputParameters.AddOutput("critical", crit);

            int ctr = 0;
            for (int i = 0; i < frame.VariableCount; i++)
            {
                for (int j = i + 1; j < frame.VariableCount; j++)
                {
                    ctr += 1;
                    double DELTA = mean[i] - mean[j];
                    double se = Math.Sqrt(msx * (1.0 / Convert.ToDouble(tnx[i]) + 1.0 / Convert.ToDouble(tnx[j])));
                    //  With no residual variation (se = 0) a zero difference gets 0 and any other difference infinity, as in RptTukey
                    double L = se > 0.0 ? DELTA / se : (DELTA == 0.0 ? 0.0 : double.PositiveInfinity);
                    double lci = DELTA - crit * se;
                    double uci = DELTA + crit * se;
                    double pScheffe = se > 0.0 ? PDF.fvalp(L * L / dfn, dfn, dfd) : (DELTA == 0.0 ? 1.0 : 0.0);
                    hold[ctr] = new Contraster
                    {
                        Lab1 = frame.Variables[i].Title,
                        Lab2 = frame.Variables[j].Title,
                        Mean1 = mean[i],
                        Mean2 = mean[j],
                        Delta = DELTA,
                        Absdelta = Math.Abs(L),
                        P = pScheffe,
                        Significant = pScheffe != Constant.MISSING && pScheffe < palpha,
                        Ll = lci,
                        Ul = uci
                    };
                }
            }

            //  Sort in descending order of ABSDELTA
            Array.Sort(hold, 1, ctr);

            outputParameters.AddOutput("pc", 100.0 * (1.0 - palpha));
            IList<ParameterBag> differencesList = new List<ParameterBag>();
            bool halted = false;
            for (int i = 1; i <= ctr; i++)
            {
                ParameterBag differencesParameters = new();
                differencesList.Add(differencesParameters);
                differencesParameters.AddOutput("cf1", hold[i].Lab1);
                differencesParameters.AddOutput("cf2", hold[i].Lab2);
                differencesParameters.AddOutput("delta", hold[i].Delta);
                differencesParameters.AddOutput("lci", hold[i].Ll);
                differencesParameters.AddOutput("uci", hold[i].Ul);
                differencesParameters.AddOutput("t", hold[i].Absdelta);
                if (!halted && hold[i].P >= palpha)
                {
                    halted = true;
                    differencesParameters.AddOutput("stop_marker", " {stop}");
                }
                differencesParameters.AddOutput("p", hold[i].P);
            }
            outputParameters.AddOutput("*differences", differencesList);
            outputParameters.AddOutput("*summary", ContrasterSummary(hold, 1, ctr, palpha));
            return new StepOutput(outputParameters);
        }

        /// <summary>
        /// Return a list suitable for inserting into an output ParameterBag of significant contrasts between variables.
        /// </summary>
        /// <param name="contrasters">Contrasts between pairs</param>
        /// <param name="lowerBound">The lowest index in contrasters containing a valid value</param>
        /// <param name="upperBound">The highest index in contrasters containing a valid value</param>
        /// <param name="palpha">The value below which values are considered significant</param>
        /// <returns></returns>
        private static List<ParameterBag> ContrasterSummary(Contraster[] contrasters, int lowerBound, int upperBound, double palpha)
        {
            Dictionary<string, SignificantContrasts> contrasts = new();
            for (int i = lowerBound; i <= upperBound; i++)
            {
                Contraster contraster = contrasters[i];
                // Ensure there's always an entry for each label - do this both ways round so that we get labels early enough
                if (!contrasts.TryGetValue(contraster.Lab1, out SignificantContrasts contrast1))
                {
                    contrast1 = new SignificantContrasts { Mean = contraster.Mean1 };
                    contrasts.Add(contraster.Lab1, contrast1);
                }
                if (!contrasts.TryGetValue(contraster.Lab2, out SignificantContrasts contrast2))
                {
                    contrast2 = new SignificantContrasts { Mean = contraster.Mean2 };
                    contrasts.Add(contraster.Lab2, contrast2);
                }
                if (contraster.Significant)
                {
                    // Significant
                    if (!contrast1.Significant.Contains(contraster.Lab2))
                        contrast1.Significant.Add(contraster.Lab2);
                    if (!contrast2.Significant.Contains(contraster.Lab1))
                        contrast2.Significant.Add(contraster.Lab1);
                }
            }
            List<ParameterBag> outputList = new(contrasts.Count);
            foreach (KeyValuePair<string, SignificantContrasts> pair in contrasts)
            {
                ParameterBag output = new();
                outputList.Add(output);
                output.AddOutput("cf1", pair.Key);
                output.AddOutput("mean", pair.Value.Mean);
                output.AddOutput("sigs", pair.Value.Significant.Count == 0 ? "none" : string.Join(", ", pair.Value.Significant.ToArray()));
            }
            return outputList;
        }

        public static StepOutput RptNewmanKeuls(ParameterBag parameters)
        {
            DataFrame frame = parameters["data"].AsDataFrame;
            double gamma = parameters["gamma"].AsDouble;
            ParameterCarrier carrier = FindOrCalculateParameters(parameters);
            double[] tnx = carrier.Tnx;
            double[] mean = carrier.Mean;
            double msx = carrier.Msx;
            double dferr = carrier.Dferr;
            if (carrier.Dferr < 1)
                throw new TemplateOperationCancelledException("These comparisons need at least one residual degree of freedom.", "Newman-Keuls Contrasts");

            int kn = frame.VariableCount;
            Contraster[] hold = new Contraster[kn * (int)Math.Floor((kn - 1) / 2.0 + 0.5) + 1]; //  1-based

            double palpha = 1.0 - gamma;
            if (palpha <= 0 || palpha >= 1)
                palpha = 0.05;

            double qx = 0;
            for (int n = 0; n < frame.VariableCount; n++)
            {
                if (n != 0 && !SameSize(tnx[n], qx))
                    throw new TemplateOperationCancelledException(carrier.EquivalentSizes
                        ? "All group sizes must be equal for the Newman-Keuls method: after a replicated two way analysis with missing repeat observations the equivalent treatment sizes differ, so use Tukey comparisons instead (Tukey-Kramer with unequal sizes)."
                        : "All group sizes must be equal for the Newman-Keuls method.", "Newman-Keuls Contrasts");
                qx = tnx[n];
            }

            double se = Math.Sqrt(msx / Convert.ToDouble(qx));
            int ctr = 0;
            for (int i = 0; i < frame.VariableCount - 1; i++)
            {
                for (int j = i + 1; j < frame.VariableCount; j++)
                {
                    ctr += 1;
                    double delta = mean[i] - mean[j];
                    //  With no residual variation a zero difference gets 0 and any other difference infinity, as in RptTukey
                    double q = msx > 0.0 ? Math.Abs(delta) / se : (delta == 0.0 ? 0.0 : double.PositiveInfinity);
                    hold[ctr] = new Contraster
                    {
                        Lab1 = frame.Variables[i].Title,
                        Lab2 = frame.Variables[j].Title,
                        Mean1 = mean[i],
                        Mean2 = mean[j],
                        Delta = delta,
                        Absdelta = Math.Abs(delta),
                        Q = q
                    };
                    // find separation of contrast, ties are included in separation
                    double a;
                    double b;
                    if (mean[i] < mean[j])
                    {
                        a = mean[i];
                        b = mean[j];
                    }
                    else
                    {
                        b = mean[i];
                        a = mean[j];
                    }
                    int ismaller = 0;
                    int ibigger = 0;
                    for (int l = 0; l < frame.VariableCount; l++)
                    {
                        if (mean[l] < a)
                            ismaller += 1;
                        if (mean[l] > b)
                            ibigger += 1;
                    }
                    hold[ctr].Gps = kn - ismaller - ibigger;
                    hold[ctr].Lo = ismaller + 1;
                    hold[ctr].Hi = kn - ibigger;
                    // calculate P(q)
                    double P = msx > 0.0 ? 1.0 - PDF.probsr(hold[ctr].Q, Convert.ToDouble(hold[ctr].Gps), dferr) : (delta == 0.0 ? 1.0 : 0.0);
                    hold[ctr].P = P;
                    hold[ctr].Significant = P != Constant.MISSING && P < palpha;
                }
            }

            //  The Newman-Keuls step-down: a pair of means inside a wider range of ordered means that is not significant
            //  is not tested, whatever its own P value, so it is not declared different. Ranges are settled from the
            //  widest down.
            for (int span = kn; span >= 2; span--)
                for (int i = 1; i <= ctr; i++)
                    if (hold[i].Gps == span)
                        for (int j = 1; j <= ctr; j++)
                            if (hold[j].Gps > span && hold[j].Lo <= hold[i].Lo && hold[i].Hi <= hold[j].Hi && !hold[j].Significant)
                            {
                                hold[i].NotTested = true;
                                hold[i].Significant = false;
                                break;
                            }

            //  sort descending on |diff| between means
            Array.Sort(hold, 1, ctr);

            ParameterBag outputParameters = new();
            IList<ParameterBag> differencesList = new List<ParameterBag>();
            for (int i = 1; i <= ctr; i++)
            {
                ParameterBag differencesParameters = new();
                differencesList.Add(differencesParameters);
                differencesParameters.AddOutput("cf1", hold[i].Lab1);
                differencesParameters.AddOutput("cf2", hold[i].Lab2);
                differencesParameters.AddOutput("delta", hold[i].Delta);
                differencesParameters.AddOutput("gps", hold[i].Gps);
                differencesParameters.AddOutput("t", hold[i].Q);
                if (hold[i].NotTested)
                    differencesParameters.AddOutput("stop_marker", " {not tested}");
                differencesParameters.AddOutput("p", hold[i].P);
            }
            outputParameters.AddOutput("*differences", differencesList);
            outputParameters.AddOutput("*summary", ContrasterSummary(hold, 1, ctr, palpha));
            return new StepOutput(outputParameters);
        }

        public static StepOutput RptDunnett(ParameterBag parameters)
        {
            DataFrame frame = parameters["data"].AsDataFrame;
            double gamma = parameters["gamma"].AsDouble;
            int[] indexvariable = (int[])parameters["indexvariable"].AsObject;
            int ic = indexvariable[0];
            ParameterCarrier carrier = FindOrCalculateParameters(parameters);
            double[] tnx = carrier.Tnx;
            double[] mean = carrier.Mean;
            double mserr = carrier.Msx;

            int kn = frame.VariableCount;

            double dalpha = 1.0 - gamma;
            if (dalpha <= 0 || dalpha >= 1)
                dalpha = 0.05;

            int k = kn - 1;
            Contraster[] hold = new Contraster[kn + 2]; //  1-based
            double[] lam = new double[kn];

            int nu = carrier.Dferr;   //  the residual degrees of freedom of the analysis these comparisons follow
            double pse = Math.Sqrt(mserr);

            int ctr = 0;
            for (int i = 0; i < kn; i++)
            {
                if (i != ic)
                {
                    ctr++;
                    lam[ctr] = Math.Pow(1 + Convert.ToDouble(tnx[ic]) / Convert.ToDouble(tnx[i]), -0.5);
                }
            }

            double cc = 1.0 - dalpha;

            ExFortran.dmcc(k, lam, nu, cc, out double d, out int ifault);
            if (ifault != 0)
                throw new TemplateOperationCancelledException(ifault == 7 ? "Dunnett's method needs at least two residual degrees of freedom." : "Fault in calculation", "Dunnett Contrasts");

            ParameterBag outputParameters = new();
            outputParameters.AddOutput("d", d);
            outputParameters.AddOutput("psd", pse);
            outputParameters.AddOutput("control", frame.Variables[ic].Title);
            outputParameters.AddOutput("cn", WholeOrEquivalentSize(tnx[ic]));
            if (carrier.EquivalentSizes)
            {
                ParameterBag noteParameters = new();
                noteParameters.AddOutput("note", "The sizes in brackets are equivalent sizes, because repeat observations were missing from the analysis before.");
                outputParameters.AddOutput("*sizes_note", new List<ParameterBag> { noteParameters });
            }
            else
            {
                outputParameters.AddOutput("*sizes_note", null);
            }
            outputParameters.AddOutput("pc", 100.0 * cc);

            ctr = 0;
            for (int i = 0; i < kn; i++)
            {
                if (i != ic)
                {
                    ctr++;
                    double delta = mean[i] - mean[ic];
                    hold[ctr] = new Contraster
                    {
                        Delta = delta,
                        Absdelta = Math.Abs(delta),
                        Lab1 = frame.Variables[i].Title,
                        N = tnx[i]
                    };
                    double lci = delta - d * pse * Math.Sqrt(1.0 / Convert.ToDouble(tnx[ic]) + 1.0 / Convert.ToDouble(tnx[i]));
                    hold[ctr].Ll = lci;
                    double uci = delta + d * pse * Math.Sqrt(1.0 / Convert.ToDouble(tnx[ic]) + 1.0 / Convert.ToDouble(tnx[i]));
                    hold[ctr].Ul = uci;
                    ExFortran.ppd2(k, lam, nu, out double px, delta / (pse * Math.Sqrt(1.0 / Convert.ToDouble(tnx[ic]) + 1.0 / Convert.ToDouble(tnx[i]))), out ifault);
                    px = 1.0 - Math.Abs(px);
                    hold[ctr].P = px;
                }
            }

            //  sort descending on |diff| between means
            Array.Sort(hold, 1, ctr);

            IList<ParameterBag> differencesList = new List<ParameterBag>();
            for (int i = 1; i <= k; i++)
            {
                ParameterBag differencesParameters = new();
                differencesList.Add(differencesParameters);
                differencesParameters.AddOutput("level", hold[i].Lab1);
                differencesParameters.AddOutput("cn", WholeOrEquivalentSize(hold[i].N));
                differencesParameters.AddOutput("delta", hold[i].Delta);
                differencesParameters.AddOutput("lci", hold[i].Ll);
                differencesParameters.AddOutput("uci", hold[i].Ul);
                differencesParameters.AddOutput("p", hold[i].P);
            }
            outputParameters.AddOutput("*differences", differencesList);
            return new StepOutput(outputParameters);
        }

        public static StepOutput RptEqualityOfVariance(ParameterBag parameters)
        {
            DataFrame frame = parameters["data"].AsDataFrame;

            double[] ao = new double[frame.MaxRows + 1];
            int[] reali = new int[frame.VariableCount];
            double[] mdn = new double[frame.VariableCount];

            for (int d = 0; d < frame.VariableCount; d++)
            {
                DoubleVariable v = frame.Variables[d]as DoubleVariable;
                foreach (double val in v.Data)
                {
                    if (val != Constant.MISSING)
                    {
                        reali[d] += 1;
                        ao[reali[d]] = val;
                    }
                }
                if (reali[d] > 1)
                {
                    Array.Sort(ao, 1, reali[d]);
                    double imdn = 0.5 * (reali[d] + 1);
                    if (imdn - Math.Floor(imdn) == 0)
                    {
                        mdn[d] = ao[Convert.ToInt32(imdn)];
                    }
                    else
                    {
                        int iimdn = (int)Math.Floor(imdn);
                        mdn[d] = ao[iimdn] + (ao[iimdn + 1] - ao[iimdn]) * (imdn - Math.Floor(imdn));
                    }
                }
                else
                {
                    throw new TemplateOperationCancelledException("Each group needs at least two observations for the equality of variance tests.", "Homogeneity of Variance");
                }
            }

            double[] sums = new double[frame.VariableCount];
            double[] sum2 = new double[frame.VariableCount];
            long[] tnx = new long[frame.VariableCount];
            double[] means = new double[frame.VariableCount];
            double lns = 0;
            double sbar = 0;
            double svii = 0;
            double svi = 0;
            double sumtot = 0;
            int ntot = 0;
            double sum2tot = 0;
            double sqtot = 0;

            for (int d = 0; d < frame.VariableCount; d++)
            {
                DoubleVariable v = frame.Variables[d]as DoubleVariable;
                int nx = 0;
                double sq = 0.0;
                double sum = 0.0;
                foreach (double val in v.Data)
                {
                    if (val != Constant.MISSING)
                    {
                        nx++;
                        sum += val;
                        sqtot += val * val;
                        sq += val * val;
                    }
                }
                tnx[d] = nx;
                sums[d] = sum;
                means[d] = sum / nx;
                sum2[d] = sum * sum / nx;
                sum2tot += sum2[d];
                ntot += nx;
                sumtot += sum;
                double df = tnx[d] - 1;
                svi += df;
                svii += 1.0 / df;
            }
            // The following code fragment produces values that are never used.  PJC 2012/04/09
            // cc = ( sumtot * sumtot ) / Convert.ToDouble( ntot ); 
            // sstot = sqtot - cc; 
            // int dftot = ntot - 1; 
            // ssgroup = sum2tot - cc; 
            // dfgroup = frame.VariableCount - 1; 
            // sserror = sstot - ssgroup; 
            // dferr = ntot - frame.VariableCount; 
            // msgroup = ssgroup / Convert.ToDouble( dfgroup ); 
            // mserr = sserror / Convert.ToDouble( dferr ); 
            double[] sumMdnDiffs = new double[frame.VariableCount]; //  Force to zeroes
            double[] sum2MdnDiffs = new double[frame.VariableCount]; //  Force to zeroes
            double[] variances = new double[frame.VariableCount]; //  Force to zeroes
            double sum2MdnDiffTot = 0.0;
            double sumMdnDiffTot = 0.0;
            double sqMdnDiffTot = 0.0;

            for (int d = 0; d < frame.VariableCount; d++)
            {
                DoubleVariable v = frame.Variables[d]as DoubleVariable;
                double sumMdnDiff = 0.0;
                double sqMeanDiffTot = 0.0;
                foreach (double val in v.Data)
                {
                    if (val != Constant.MISSING)
                    {
                        double mdnDiff = val - mdn[d];
                        sumMdnDiff += Math.Abs(mdnDiff);
                        sqMdnDiffTot += mdnDiff * mdnDiff;
                        double meanDiff = val - means[d];
                        sqMeanDiffTot += meanDiff * meanDiff;
                    }
                }
                sumMdnDiffs[d] = sumMdnDiff;
                sumMdnDiffTot += sumMdnDiff;
                double sum2MdnDiff = sumMdnDiff * sumMdnDiff / tnx[d];
                sum2MdnDiffs[d] = sum2MdnDiff;
                sum2MdnDiffTot += sum2MdnDiff;
                variances[d] = sqMeanDiffTot / (tnx[d] - 1.0);
            }
            //  Bartlett's test from the variances about the group means: a sum of squares less the square of the sum
            //  loses figures when the values are large compared with their spread
            for (int d = 0; d < frame.VariableCount; d++)
            {
                double df = tnx[d] - 1;
                sbar += variances[d] * df;
                lns += df * Math.Log(variances[d]);
            }
            sbar /= svi;
            double M = svi * Math.Log(sbar) - lns;
            long bdf = frame.VariableCount - 1;
            double C = 1.0 + 1.0 / (3.0 * bdf) * (svii - 1.0 / svi);
            double x2 = M / C;
            double[] ws = new double[frame.VariableCount]; //  Force to zeroes
            double wTot = 0;
            double wMeanTot = 0;
            for (int d = 0; d < frame.VariableCount; d++)
            {
                double w = tnx[d] / variances[d];
                ws[d] = w;
                wTot += w;
                double wMean = means[d] * w;
                wMeanTot += wMean;
            }
            double xBar = wMeanTot / wTot;
            double faTotal = 0;
            double fcTotal = 0;
            for (int d = 0; d < frame.VariableCount; d++)
            {
                double fa = ws[d] * (means[d] - xBar) * (means[d] - xBar);
                double something = 1.0 - tnx[d] / variances[d] / wTot;
                double fc = something * something / (tnx[d] - 1.0);
                faTotal += fa;
                fcTotal += fc;
            }
            double cc = sumMdnDiffTot * sumMdnDiffTot / ntot;
            double sstot = sqMdnDiffTot - cc;
            double ssgroup = sum2MdnDiffTot - cc;
            long dfGroup = frame.VariableCount - 1;
            double sserror = sstot - ssgroup;
            int dferr = ntot - frame.VariableCount;
            double msgroup = ssgroup / dfGroup;
            double mserr = sserror / dferr;
            ParameterBag outputParameters = new();

            // Levene
            outputParameters.AddOutput("f", msgroup / mserr);
            outputParameters.AddOutput("df1", dfGroup);
            outputParameters.AddOutput("df2", dferr);
            double P = PDF.fvalp(msgroup / mserr, dfGroup, dferr);
            outputParameters.AddOutput("pLevene", P);

            // Bartlett
            outputParameters.AddOutput("x2", x2);
            outputParameters.AddOutput("df", bdf);
            outputParameters.AddOutput("pBartlett", PDF.chivalp(x2, bdf));

            // Welch
            double groups = frame.VariableCount;
            double fb = 2 * (groups - 2.0) / (groups * groups - 1.0);
            double fWelch = faTotal / (groups - 1.0) / (1.0 + fb * fcTotal);
            double dfdWelch = (groups * groups - 1) / (3.0 * fcTotal);
            double pWelch = PDF.fvalp(fWelch, dfGroup, dfdWelch);
            outputParameters.AddOutput("fWelch", fWelch);
            outputParameters.AddOutput("dfnWelch", dfGroup);
            outputParameters.AddOutput("dfdWelch", dfdWelch);
            outputParameters.AddOutput("pWelch", pWelch);
            return new StepOutput(outputParameters);
        }

        public static StepOutput RptNestMeans(ParameterBag parameters)
        {
            if (parameters.ContainsKey("data2d") && parameters.ContainsKey("ctr") && parameters.ContainsKey("ngp") && parameters.ContainsKey("gbar") && parameters.ContainsKey("sgbar") && parameters.ContainsKey("gm") && parameters.ContainsKey("ctr"))
            {
                DataFrame2D frame = parameters["data2d"].AsDataFrame2D;
                int ctr = parameters["ctr"].AsInt32;
                int[] ngp = (int[])parameters["ngp"].AsObject;
                double[] gbar = (double[])parameters["gbar"].AsObject;
                double[] sgbar = (double[])parameters["sgbar"].AsObject;
                double gm = parameters["gm"].AsDouble;

                ParameterBag outputParameters = new();

                IList<ParameterBag> groupList = new List<ParameterBag>();
                outputParameters.AddOutput("*group", groupList);
                for (int j = 1; j <= frame.VariableCount; j++)
                {
                    ParameterBag groupParameters = new();
                    groupParameters.AddOutput("ggrp", j);
                    groupParameters.AddOutput("gmean", gbar[j]);
                    groupParameters.AddOutput("gn", ngp[j]);
                    groupList.Add(groupParameters);
                }
                outputParameters.AddOutput("g_mean", gm);
                outputParameters.AddOutput("g_n", ctr);

                IList<ParameterBag> subGroupList = new List<ParameterBag>();
                outputParameters.AddOutput("*subgroup", subGroupList);
                int ii = 0;
                for (int j = 0; j < frame.VariableCount; j++)
                {
                    for (int i = 0; i < frame.Variables[j].Count; i++)
                    {
                        ParameterBag subGroupParameters = new();
                        ii += 1;
                        subGroupParameters.AddOutput("sggrp", j + 1);
                        subGroupParameters.AddOutput("sgsub_grp", i + 1);
                        subGroupParameters.AddOutput("sgtitle", frame.Variables[j][i].Title);
                        subGroupParameters.AddOutput("sgmean", sgbar[ii]);
                        subGroupList.Add(subGroupParameters);
                    }
                }
                return new StepOutput(outputParameters);
            }

            throw new Exception("Trying to call rptNestMeans without the prerequisites set");
        }

        public static StepOutput RptLatin(ParameterBag parameters)
        {
            //  Get observations into a temporary vector v - precondition: the number of observations is a square
            DataFrame observationFrame = parameters["observations"].AsDataFrame;
            DoubleVariable observationVariable = observationFrame.Variables[0] as DoubleVariable ?? throw new TemplateOperationCancelledException("The observations and the three factor codes must be numeric.", "Latin Square");
            int nn = observationVariable.Length;
            double[] v = new double[nn + 1];
            double[] vcx = new double[nn + 1];
            double[] vrx = new double[nn + 1];
            double[] vlx = new double[nn + 1];
            int n = Convert.ToInt32(Math.Sqrt(nn));
            for (int i = 1; i <= nn; i++)
            {
                v[i] = observationVariable.Data[i - 1];
            }

            //  Get column classes
            DataFrame columnFrame = parameters["column"].AsDataFrame;
            DoubleVariable columnVariable = columnFrame.Variables[0] as DoubleVariable ?? throw new TemplateOperationCancelledException("The observations and the three factor codes must be numeric.", "Latin Square");
            for (int i = 1; i <= nn; i++)
            {
                vcx[i] = columnVariable.Data[i - 1];
            }
            string tlist = columnVariable.Title;

            // get row classes
            DataFrame rowFrame = parameters["row"].AsDataFrame;
            DoubleVariable rowVariable = rowFrame.Variables[0] as DoubleVariable ?? throw new TemplateOperationCancelledException("The observations and the three factor codes must be numeric.", "Latin Square");
            for (int i = 1; i <= nn; i++)
            {
                vrx[i] = rowVariable.Data[i - 1];
            }
            tlist += ", " + rowVariable.Title;

            // get treatment/Latin/random classes
            DataFrame treatmentFrame = parameters["treatment"].AsDataFrame;
            DoubleVariable treatmentVariable = treatmentFrame.Variables[0] as DoubleVariable ?? throw new TemplateOperationCancelledException("The observations and the three factor codes must be numeric.", "Latin Square");
            for (int i = 1; i <= nn; i++)
            {
                vlx[i] = treatmentVariable.Data[i - 1];
            }
            tlist += ", " + treatmentVariable.Title + ".";

            // set up calculation variables
            double[,] x = new double[n + 1, n + 1];
            double[] tx = new double[n + 1];
            double[] sr = new double[n + 1];
            double[] sc = new double[n + 1];

            if (n * n != nn)
                throw new TemplateOperationCancelledException("A Latin square needs n by n observations.", "Latin Square");
            if (n < 3)
                throw new TemplateOperationCancelledException("A Latin square needs at least three rows and columns to leave a residual degree of freedom.", "Latin Square");

            // each factor's codes may be any n distinct values, in any order and any rows: they are ranked to 1..n
            int[] ri = LatinSquareIndexes(vrx, nn, n, "row");
            int[] ci = LatinSquareIndexes(vcx, nn, n, "column");
            int[] ti = LatinSquareIndexes(vlx, nn, n, "treatment");

            // collapse observation vector v into row by col matrix x, get Latin factor totals tx, and check the design
            int[,] cellCount = new int[n + 1, n + 1];
            int[,] rowTreatment = new int[n + 1, n + 1];
            int[,] columnTreatment = new int[n + 1, n + 1];
            for (int i = 1; i <= nn; i++)
            {
                x[ri[i], ci[i]] = v[i];
                cellCount[ri[i], ci[i]]++;
                rowTreatment[ri[i], ti[i]]++;
                columnTreatment[ci[i], ti[i]]++;
                tx[ti[i]] += v[i];
            }
            for (int i = 1; i <= n; i++)
                for (int j = 1; j <= n; j++)
                    if (cellCount[i, j] != 1 || rowTreatment[i, j] != 1 || columnTreatment[i, j] != 1)
                        throw new TemplateOperationCancelledException("The design is not a Latin square: each row and column combination must be observed once, and each treatment must occur once in every row and once in every column.", "Latin Square");

            double grand = 0;
            for (int i = 1; i <= n; i++)
            {
                for (int j = 1; j <= n; j++)
                {
                    sr[i] += x[i, j];
                    sc[j] += x[i, j];
                    grand += x[i, j];
                }
            }
            double an = n;
            double es = grand / an;
            double ex = grand / (an * an);
            double ssqtot = 0;
            double bb = 0;
            double cc = 0;
            double dd = 0;
            for (int i = 1; i <= n; i++)
            {
                bb += (sr[i] - es) * (sr[i] - es);
                cc += (sc[i] - es) * (sc[i] - es);
                dd += (tx[i] - es) * (tx[i] - es);
                for (int j = 1; j <= n; j++)
                {
                    ssqtot += (x[i, j] - ex) * (x[i, j] - ex);
                }
            }
            double ssqr = bb / an;
            double ssqc = cc / an;
            double ssqtr = dd / an;
            double ssqres = ssqtot - ssqr - ssqc - ssqtr;
            int ndf = n - 1;
            int ndftot = n * n - 1;
            int ndfres = (n - 1) * (n - 2);
            double df = ndf;
            double dfres = ndfres;
            double vr = ssqr / df;
            double vc = ssqc / df;
            double vtr = ssqtr / df;
            double vres = ssqres / dfres;
            double fr = vr / vres;
            double fc = vc / vres;
            double ftr = vtr / vres;
            ParameterBag outputParameters = new();
            outputParameters.AddOutput("tlist", tlist);
            outputParameters.AddOutput("row_sum", ssqr);
            outputParameters.AddOutput("row_f", ndf);
            outputParameters.AddOutput("row_mean", vr);
            outputParameters.AddOutput("col_sum", ssqc);
            outputParameters.AddOutput("col_f", ndf);
            outputParameters.AddOutput("col_mean", vc);
            outputParameters.AddOutput("treat_sum", ssqtr);
            outputParameters.AddOutput("treat_f", ndf);
            outputParameters.AddOutput("treat_mean", vtr);
            outputParameters.AddOutput("res_sum", ssqres);
            outputParameters.AddOutput("res_f", ndfres);
            outputParameters.AddOutput("res_mean", vres);
            outputParameters.AddOutput("tot_sum", ssqtot);
            outputParameters.AddOutput("tot_f", ndftot);
            outputParameters.AddOutput("f_row", fr);
            outputParameters.AddOutput("p_row", PDF.fvalp(fr, df, dfres));
            outputParameters.AddOutput("f_col", fc);
            outputParameters.AddOutput("p_col", PDF.fvalp(fc, df, dfres));
            outputParameters.AddOutput("f_treat", ftr);
            outputParameters.AddOutput("p_treat", PDF.fvalp(ftr, df, dfres));
            return new StepOutput(outputParameters);
        }

        public static StepOutput RptCrossover(ParameterBag parameters)
        {
            double dif; double difss1 = 0; double sumsum1 = 0; double dsum = 0; double psum = 0;
            double sumss2 = 0; double difss2 = 0;
            double corrector; double difsum1 = 0; double sumss1 = 0;
            double difsum2 = 0; double sumsum2 = 0;

            double GAMMA = parameters["gamma"].AsDouble;
            if (GAMMA <= 0)
                throw new Exception("GAMMA must be greater than zero");

            // Group 1
            DataFrame group1DrugFrame = parameters["group1drug"].AsDataFrame;
            double[] group1DrugData = (group1DrugFrame.Variables[0] as DoubleVariable).Data;
            int rows = group1DrugData.Length;

            DataFrame group1PlaceboFrame = parameters["group1placebo"].AsDataFrame;
            double[] group1PlaceboData = (group1PlaceboFrame.Variables[0] as DoubleVariable).Data;

            bool g1bl = parameters.ContainsKey("group1baseline") && parameters["group1baseline"] != null;
            double[] group1BaselineData;
            if (g1bl)
            {
                DataFrame group1BaselineFrame = parameters["group1baseline"].AsDataFrame;
                group1BaselineData = (group1BaselineFrame.Variables[0] as DoubleVariable).Data;
            }
            else
            {
                group1BaselineData = null;
            }
            double[] x1d = new double[rows + 1];
            double[] x1p = new double[rows + 1];
            int ng1 = 0;
            for (int j = 0; j < rows; j++)
            {
                if (group1DrugData[j] != Constant.MISSING && group1PlaceboData[j] != Constant.MISSING && (!g1bl || group1BaselineData[j] != Constant.MISSING))
                {
                    ng1 += 1;
                    corrector = g1bl ? group1BaselineData[j] : 0;
                    x1d[ng1] = group1DrugData[j] - corrector;
                    x1p[ng1] = group1PlaceboData[j] - corrector;
                }
            }

            // Group 2
            DataFrame group2DrugFrame = parameters["group2drug"].AsDataFrame;
            double[] group2DrugData = (group2DrugFrame.Variables[0] as DoubleVariable).Data;
            rows = group2DrugData.Length;

            DataFrame group2PlaceboFrame = parameters["group2placebo"].AsDataFrame;
            double[] group2PlaceboData = (group2PlaceboFrame.Variables[0] as DoubleVariable).Data;

            bool g2bl = parameters.ContainsKey("group2baseline") && parameters["group2baseline"] != null;
            double[] group2BaselineData;
            if (g2bl)
            {
                DataFrame group2BaselineFrame = parameters["group2baseline"].AsDataFrame;
                group2BaselineData = (group2BaselineFrame.Variables[0] as DoubleVariable).Data;
            }
            else
            {
                group2BaselineData = null;
            }
            double[] x2d = new double[rows + 1];
            double[] x2p = new double[rows + 1];
            int ng2 = 0;
            for (int j = 0; j < rows; j++)
            {
                if (group2DrugData[j] != Constant.MISSING && group2PlaceboData[j] != Constant.MISSING && (!g2bl || group2BaselineData[j] != Constant.MISSING))
                {
                    ng2 += 1;
                    corrector = g2bl ? group2BaselineData[j] : 0;
                    x2p[ng2] = group2DrugData[j] - corrector;
                    x2d[ng2] = group2PlaceboData[j] - corrector;
                }
            }

            for (int j = 1; j <= ng1; j++)
            {
                dif = x1d[j] - x1p[j];
                difsum1 += dif;
                difss1 += dif * dif;
                sumsum1 = sumsum1 + x1d[j] + x1p[j];
                sumss1 += (x1d[j] + x1p[j]) * (x1d[j] + x1p[j]);
                dsum += x1d[j];
                psum += x1p[j];
            }
            double difbar1 = difsum1 / ng1;
            double sumbar1 = sumsum1 / ng1;
            double dbar1 = dsum / ng1;
            double pbar1 = psum / ng1;
            double tdsum = difsum1;
            double tdsum2 = difss1;
            dsum = 0.0;
            psum = 0.0;
            for (int j = 1; j <= ng2; j++)
            {
                dif = x2d[j] - x2p[j];
                difsum2 += dif;
                difss2 += dif * dif;
                tdsum -= dif;
                tdsum2 += dif * dif;
                sumsum2 = sumsum2 + x2d[j] + x2p[j];
                sumss2 += (x2d[j] + x2p[j]) * (x2d[j] + x2p[j]);
                dsum += x2d[j];
                psum += x2p[j];
            }
            double totdifbar = tdsum / (ng1 + ng2);
            double totdifvar = (tdsum2 - tdsum * tdsum / (ng1 + ng2)) / Convert.ToDouble(ng1 + ng2 - 1);
            double difbar2 = difsum2 / ng2;
            double sumbar2 = sumsum2 / ng2;
            double dbar2 = dsum / ng2;
            double pbar2 = psum / ng2;
            ParameterBag outputParameters = new();
            int skipped = (group1DrugData.Length - ng1) + (group2DrugData.Length - ng2);
            if (skipped > 0)
            {
                IList<ParameterBag> warnList = new List<ParameterBag>();
                ParameterBag warnParameters = new();
                warnParameters.AddOutput("warn", "WARNING - " + skipped.ToString() + " subject(s) with a missing value left out");
                warnList.Add(warnParameters);
                outputParameters.AddOutput("*warn", warnList);
            }
            else
            {
                outputParameters.AddOutput("*warn", null);
            }
            outputParameters.AddOutput("grp1_p1", dbar1);
            outputParameters.AddOutput("grp1_p2", pbar1);
            outputParameters.AddOutput("grp1_diff", difbar1);
            outputParameters.AddOutput("grp2_p1", dbar2);
            outputParameters.AddOutput("grp2_p2", pbar2);
            outputParameters.AddOutput("grp2_diff", difbar2);
            double se = Math.Sqrt(totdifvar / (ng1 + ng2));
            outputParameters.AddOutput("relative_diff", totdifbar);
            outputParameters.AddOutput("relative_se", se);
            double df = Convert.ToDouble(ng1 + ng2 - 1L);
            double t = totdifbar / se;
            outputParameters.AddOutput("relative_t", t);
            outputParameters.AddOutput("relative_df", df);
            double p = PDF.tvalp(Math.Abs(t), df);
            if (p > 1.0 - p)
                p = 1.0 - p;
            outputParameters.AddOutput("relative_p", p * 2.0);
            double var1 = difss1 - difsum1 * difsum1 / ng1;
            double var2 = difss2 - difsum2 * difsum2 / ng2;
            double var = (var1 + var2) / (ng1 + ng2 - 2L);
            se = Math.Sqrt(var * (1.0 / ng2 + 1.0 / ng1));
            df = ng1 + ng2 - 2L;
            t = (difbar1 - difbar2) / se;
            double mag = (difbar1 - difbar2) / 2.0;
            double pot = 1.0 - GAMMA;
            double crit = PDF.tfromp(pot / 2.0, df);
            outputParameters.AddOutput("treatment_diff", difbar1 - difbar2);
            outputParameters.AddOutput("treatment_se", se);
            outputParameters.AddOutput("treatment_mag", mag);
            outputParameters.AddOutput("treatment_pc", 100 * GAMMA);
            outputParameters.AddOutput("treatment_from", mag - crit * se / 2.0);
            outputParameters.AddOutput("treatment_to", mag + crit * se / 2.0);
            outputParameters.AddOutput("treatment_t", t);
            outputParameters.AddOutput("treatment_df", df);
            p = PDF.tvalp(Math.Abs(t), df);
            if (p > 1.0 - p)
                p = 1.0 - p;
            outputParameters.AddOutput("treatment_p", p * 2.0);
            t = (difbar1 + difbar2) / se;
            outputParameters.AddOutput("period_diff", difbar1 + difbar2);
            outputParameters.AddOutput("period_se", se);
            outputParameters.AddOutput("period_t", t);
            outputParameters.AddOutput("period_df", df);
            p = PDF.tvalp(Math.Abs(t), df);
            if (p > 1.0 - p)
                p = 1.0 - p;
            outputParameters.AddOutput("period_p", p * 2.0);
            var1 = sumss1 - sumsum1 * sumsum1 / ng1;
            var2 = sumss2 - sumsum2 * sumsum2 / ng2;
            var = (var1 + var2) / (ng1 + ng2 - 2L);
            se = Math.Sqrt(var * (1.0 / ng2 + 1.0 / ng1));
            t = (sumbar1 - sumbar2) / se;
            outputParameters.AddOutput("tpi_sum", sumbar1 - sumbar2);
            outputParameters.AddOutput("tpi_se", se);
            outputParameters.AddOutput("tpi_t", t);
            outputParameters.AddOutput("tpi_df", df);
            p = PDF.tvalp(Math.Abs(t), df);
            if (p > 1.0 - p)
                p = 1.0 - p;
            outputParameters.AddOutput("tpi_p", p * 2.0);
            return new StepOutput(outputParameters);
        }

        private static ParameterCarrier FindOrCalculateParameters(ParameterBag parameters)
        {
            ParameterCarrier carrier = new();
            if (parameters.ContainsKey("dfres") && parameters.ContainsKey("msres") && parameters.ContainsKey("mean") && parameters.ContainsKey("tnx"))
            {
                carrier.Dferr = parameters["dfres"].AsInt32;
                carrier.Mean = (double[])parameters["mean"].AsObject;
                carrier.Msx = parameters["msres"].AsDouble;
                carrier.Tnx = parameters["tnx"].AsObject is int[] counts ? Array.ConvertAll(counts, n => (double)n) : (double[])parameters["tnx"].AsObject;
                carrier.EquivalentSizes = parameters.ContainsKey("equivalent_sizes") && parameters["equivalent_sizes"].AsBoolean;
            }
            else
            {
                DataFrame frame = parameters["data"].AsDataFrame;

                int[] tnx = new int[frame.VariableCount];
                double[] mean = new double[frame.VariableCount];
                double sumtot = 0.0;
                int ntot = 0;
                for (int d = 0; d < frame.VariableCount; d++)
                {
                    DoubleVariable v = frame.Variables[d]as DoubleVariable;
                    int nx = 0;
                    double sum = 0;
                    foreach (double val in v.Data)
                    {
                        if (val != Constant.MISSING)
                        {
                            nx++;
                            sum += val;
                        }
                    }
                    tnx[d] = nx;
                    ntot += nx;
                    mean[d] = sum / nx;
                    sumtot += sum;
                }

                double sserror = 0;   // within groups, accumulated directly from the deviations about the group means
                for (int d = 0; d < frame.VariableCount; d++)
                {
                    DoubleVariable v = frame.Variables[d] as DoubleVariable;
                    foreach (double val in v.Data)
                        if (val != Constant.MISSING)
                            sserror += (val - mean[d]) * (val - mean[d]);
                }
                int dferr = ntot - frame.VariableCount;
                // double msgroup = ssgroup / dfgroup; Never used.  PJC 2012/04/09.
                double mserr = sserror / Convert.ToDouble(dferr);

                carrier.Dferr = dferr;
                carrier.Mean = mean;
                carrier.Msx = mserr;
                carrier.Tnx = Array.ConvertAll(tnx, n => (double)n);
            }
            return carrier;
        }

        /// <summary>
        /// Whether two group sizes are the same: whole numbers compare exactly, equivalent sizes to within rounding.
        /// </summary>
        private static bool SameSize(double a, double b) => Math.Abs(a - b) <= 1e-9 * Math.Max(Math.Abs(a), Math.Abs(b));

        /// <summary>
        /// A group size for a report: a whole number as an integer, which prints as it always did, an equivalent size as a double, which the template rounds.
        /// </summary>
        private static object WholeOrEquivalentSize(double size) => size == Math.Floor(size) && size <= int.MaxValue ? (object)(int)size : size;

        /// <summary>
        /// Rank the codes of one Latin square factor to 1..n, whatever values they are and whatever order they come in.
        /// </summary>
        private static int[] LatinSquareIndexes(double[] codes, int nn, int n, string factor)
        {
            double[] sorted = new double[nn];
            Array.Copy(codes, 1, sorted, 0, nn);
            Array.Sort(sorted);
            List<double> levels = new();
            foreach (double code in sorted)
                if (levels.Count == 0 || levels[levels.Count - 1] != code)
                    levels.Add(code);
            if (levels.Count != n)
                throw new TemplateOperationCancelledException("The " + factor + " factor must have exactly " + n.ToString() + " distinct codes for a " + n.ToString() + " by " + n.ToString() + " Latin square (it has " + levels.Count.ToString() + ").", "Latin Square");
            int[] index = new int[nn + 1];
            for (int i = 1; i <= nn; i++)
                index[i] = levels.BinarySearch(codes[i]) + 1;
            return index;
        }

        private class Contraster : IComparable<Contraster>
        {
            public double Absdelta;
            public double Delta;
            public double Mean1;
            public double Mean2;
            public double Ll;
            public double Ul;
            public double P;
            public double Q;
            public long Gps;
            public double N;           //  Dunnett: the size of the group (its equivalent size after a replicated two way analysis with missing repeats)
            public bool Significant;   //  declared different at the chosen level (for Newman-Keuls, after the step-down rule)
            public bool NotTested;     //  Newman-Keuls: inside a wider range of ordered means that is not significant
            public int Lo;             //  Newman-Keuls: the first and last positions, among the ordered means, that the contrast spans
            public int Hi;
            public string Lab1;
            public string Lab2;

            private int CompareTo(Contraster other)
            {
                //  Deliberately sorts by *descending* order of ABSDELTA. CompareTo, unlike Math.Sign of the difference,
                //  orders infinite and not-a-number statistics (a zero residual mean square) without throwing.
                return other.Absdelta.CompareTo(Absdelta);
            }
            // interface methods implemented by CompareTo
            int IComparable<Contraster>.CompareTo(Contraster other)
            {
                return CompareTo(other);
            }

        }

        private class ParameterCarrier
        {
            public double[] Tnx;   //  group sizes: whole numbers, except the equivalent sizes after a replicated two way analysis with missing repeats
            public bool EquivalentSizes;   //  the sizes are those equivalent sizes
            public double Msx;
            public double[] Mean;
            public int Dferr;
        }

        private class SignificantContrasts
        {
            public readonly List<string> Significant;
            public double Mean;

            public SignificantContrasts()
            {
                Significant = new List<string>();
            }
        }
    }
}
