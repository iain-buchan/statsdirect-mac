using StatsDirect.Charting;
using StatsDirect.Data;
using StatsDirect.Numerics;
using StatsDirect.Templates;
using StatsDirect.Utilities;

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using static StatsDirect.Builtins.ExactBB;

namespace StatsDirect.Builtins
{
    public static class Meta
    {
        public static StepOutput RptPetoMeta(IPreferencesAndProgressBar host, ParameterBag parameters)
        {
            double rmh = 0;

            double cco = parameters["gamma"].AsDouble;
            if (cco <= 0)
                cco = 0.95;
            double cit = PDF.gauinv(1.0 - (1.0 - cco) / 2.0);

            DataFrame snFrame = parameters["sn"].AsDataFrame;
            DoubleVariable snVariable = (DoubleVariable)snFrame.Variables[0];
            DataFrame srFrame = parameters["sr"].AsDataFrame;
            DoubleVariable srVariable = (DoubleVariable)srFrame.Variables[0];
            DataFrame xnFrame = parameters["xn"].AsDataFrame;
            DoubleVariable xnVariable = (DoubleVariable)xnFrame.Variables[0];
            DataFrame xrFrame = parameters["xr"].AsDataFrame;
            DoubleVariable xrVariable = (DoubleVariable)xrFrame.Variables[0];
            int rawRows = snVariable.Length;

            DoubleArraysAndBooleans copiesRemovingMissingRows = Numerics.Utilities.RemoveMissingRows(new[] { snVariable.Data, srVariable.Data, xnVariable.Data, xrVariable.Data }, 0, rawRows, 1);
            double[] sn = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[0];
            double[] sr = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[1];
            double[] xn = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[2];
            double[] xr = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[3];

            string[] title = MakeTitles(parameters, "strata", "stratum {0}", rawRows, out bool hasUserSuppliedLabels);

            int k = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[0].Length - 1; /* 1-based */
            title = Numerics.Utilities.CopyValidRows(title, copiesRemovingMissingRows.ValidRowsInOriginal, 0, rawRows, 1, k);

            double[,] o = new double[k + 1, 4 + 1];
            double[] oe = new double[k + 1];
            double[] odr = new double[k + 1];
            double[] odrv = new double[k + 1];
            double[] odrl = new double[k + 1];
            double[] odru = new double[k + 1];
            double[] odw = new double[k + 1];
            double[] odz = new double[k + 1];
            double[] odx = new double[k + 1];
            bool[] allFalse = new bool[k + 1];
            bool[] included = new bool[k + 1];
            for (int i = 1; i <= k; i++)
            {
                o[i, 1] = Math.Abs(sr[i]);
                o[i, 3] = Math.Abs(sn[i] - sr[i]);
                if (sr[i] < 0 || sn[i] < 0 || sn[i] < sr[i])
                    throw new InvalidDataException();
                o[i, 2] = Math.Abs(xr[i]);
                o[i, 4] = Math.Abs(xn[i] - xr[i]);
                if (xr[i] < 0 || xn[i] < 0 || xn[i] < xr[i])
                    throw new InvalidDataException();
                included[i] = IncludeTable(o, i);
            }

            // see Fleiss paper
            double sumoe = 0.0;
            double sumv = 0.0;
            for (int i = 1; i <= k; i++)
            {
                double a = o[i, 1];
                double b = o[i, 2];
                double c = o[i, 3];
                double d = o[i, 4];
                double n = a + b + c + d;
                if (n > 0)
                {
                    double e = (a + b) * (a + c) / n;
                    oe[i] = a - e;
                    sumoe += oe[i];
                    double v = (a + b) * (c + d) * (a + c) * (b + d) / (n * n * (n - 1));
                    sumv += v;
                    odw[i] = v;
                    odx[i] = n;
                    if (v > 0)
                    {
                        odr[i] = Math.Exp(oe[i] / v);
                        odz[i] = oe[i] / Math.Sqrt(v);
                        odrv[i] = v;
                        odrl[i] = Math.Exp((oe[i] - cit * Math.Sqrt(v)) / v);
                        odru[i] = Math.Exp((oe[i] + cit * Math.Sqrt(v)) / v);
                    }
                    else
                    {
                        odr[i] = Constant.MISSING;
                        odrl[i] = Constant.MISSING;
                        odru[i] = Constant.MISSING;
                        odz[i] = Constant.MISSING;
                    }
                }
                else
                {
                    odr[i] = Constant.MISSING;
                    odw[i] = Constant.MISSING;
                    odrl[i] = Constant.MISSING;
                    odru[i] = Constant.MISSING;
                    odz[i] = Constant.MISSING;
                }
            }

            // pooled peto odds ratio
            double poru; double porl; double por; double z;
            if (sumv > 0.0)
            {
                por = Math.Exp(sumoe / sumv);
                porl = Math.Exp((sumoe - cit * Math.Sqrt(sumv)) / sumv);
                poru = Math.Exp((sumoe + cit * Math.Sqrt(sumv)) / sumv);
                z = sumoe / Math.Sqrt(sumv);
            }
            else
            {
                throw new InvalidDataException();
            }

            // combinability
            double qc = 0.0;
            int realk = 0;
            for (int i = 1; i <= k; i++)
            {
                if (IncludeTable(o, i))
                {
                    realk++;
                    double lori = oe[i] / odw[i];
                    qc += Math.Pow(lori - Math.Log(por), 2.0) * odw[i];
                }
            }

            ParameterBag outputParameters = new();
            IList<ParameterBag> inputsList = new List<ParameterBag>();
            outputParameters.AddOutput("*inputs", inputsList);
            for (int i = 1; i <= k; i++)
            {
                ParameterBag inputsParameters = new();
                inputsList.Add(inputsParameters);
                inputsParameters.AddOutput("st", i);
                inputsParameters.AddOutput("a", o[i, 1]);
                inputsParameters.AddOutput("b", o[i, 2]);
                inputsParameters.AddOutput("c", o[i, 3]);
                inputsParameters.AddOutput("d", o[i, 4]);
                inputsParameters.AddOutput("lb", GetMetaLabel(host, o, i, hasUserSuppliedLabels, allFalse, title));
            }

            outputParameters.AddOutput("pc", cco * 100);

            IList<ParameterBag> oddsList = new List<ParameterBag>();
            outputParameters.AddOutput("*odds", oddsList);
            for (int i = 1; i <= k; i++)
            {
                ParameterBag oddsParameters = new();
                oddsList.Add(oddsParameters);
                oddsParameters.AddOutput("st", i);
                oddsParameters.AddOutput("oe", oe[i]);
                oddsParameters.AddOutput("or", odr[i]);
                oddsParameters.AddOutput("yi", odr[i] > 0 ? Math.Log(odr[i]) : 0);
                oddsParameters.AddOutput("vi", odrv[i]);
                oddsParameters.AddOutput("lci", odrl[i]);
                oddsParameters.AddOutput("uci", odru[i]);
                oddsParameters.AddOutput("wt", 100 * odw[i] / Formatting.dsum(odw, 1));
                oddsParameters.AddOutput("lb", GetMetaLabel(host, o, i, hasUserSuppliedLabels, allFalse, title));
            }

            IList<ParameterBag> zList = new List<ParameterBag>();
            outputParameters.AddOutput("*z", zList);
            for (int i = 1; i <= k; i++)
            {
                ParameterBag zParameters = new();
                zList.Add(zParameters);
                zParameters.AddOutput("st", i);
                zParameters.AddOutput("v", odw[i]);
                zParameters.AddOutput("z", odz[i]);
                if (odz[i] != Constant.MISSING)
                {
                    double p = 1.0 - PDF.alnorm(odz[i]);
                    if (p > 1.0 - p)
                        p = 1.0 - p;
                    zParameters.AddOutput("p", 2.0 * p);
                }
                else
                {
                    zParameters.AddOutput("p", Formatting.ASTERISK);
                }
                zParameters.AddOutput("lb", GetMetaLabel(host, o, i, hasUserSuppliedLabels, allFalse, title));
            }

            outputParameters.AddOutput("por", por);
            outputParameters.AddOutput("from", porl);
            outputParameters.AddOutput("to", poru);

            outputParameters.AddOutput("z", z);
            double pz = 1.0 - PDF.alnorm(z);
            if (pz > 1.0 - pz)
                pz = 1.0 - pz;
            outputParameters.AddOutput("p_z", 2.0 * pz);

            outputParameters.AddOutput("qc", qc);
            outputParameters.AddOutput("df", realk - 1);
            outputParameters.AddOutput("xp", PDF.chivalp(qc, realk - 1));
            IsquareNcc(host, qc, realk, cco, cit, out double isq, out double llisq, out double ulisq);
            outputParameters.AddOutput("isq", isq);
            outputParameters.AddOutput("pc1", cco * 100);
            outputParameters.AddOutput("llisq", llisq);
            outputParameters.AddOutput("ulisq", ulisq);

            IList<ParameterBag> eggerList = new List<ParameterBag>();
            outputParameters.AddOutput("*egger", eggerList);
            ParameterBag eggerParameters = new();
            eggerList.Add(eggerParameters);
            Metabias(host, eggerParameters, odr, odrl, odru, k, ref cco, Transformation.Log);

            IList<ParameterBag> harbordList = new List<ParameterBag>();
            outputParameters.AddOutput("*harbord", harbordList);
            ParameterBag harbordParameters = new();
            harbordList.Add(harbordParameters);
            ModMetabias(host, harbordParameters, o, k, cco, 1);

            IList<ParameterBag> chartList = new List<ParameterBag>();
            outputParameters.AddOutput("*chart", chartList);
            ParameterBag chartParameters;

            if (k > 3)
            {
                chartParameters = new ParameterBag();
                chartList.Add(chartParameters);
                chartParameters.AddOutput("chart", ChartRendererFactory.PrepForLater(ChartType.BiasMA, new BiasMAOptions(odr, odx, odw, k, "Peto odds ratio", odrl, odru, cco, cit, por, Transformation.Log, false)));
            }

            chartParameters = new ParameterBag();
            chartList.Add(chartParameters);
            chartParameters.AddOutput("chart", ChartRendererFactory.PrepForLater(ChartType.LAbbe, new LAbbeOptions(k, o, rmh)));

            chartParameters = new ParameterBag();
            chartList.Add(chartParameters);
            chartParameters.AddOutput("chart", ChartRendererFactory.PrepForLater(ChartType.MH, new MHOptions(1, k, odw, title, por, porl, poru, cco, odr, odrl, odru, allFalse, allFalse, included, "Peto odds ratio plot", 1, "Peto odds ratio" /* , "Pooled Peto odds ratio" */)));

            if (k > 2)
            {
                chartParameters = new ParameterBag();
                chartList.Add(chartParameters);
                chartParameters.AddOutput("chart", ChartRendererFactory.PrepForLater(ChartType.BiasMA, new BiasMAOptions(odw, oe, oe, k, "Peto weights", odrl, odru, cco, cit, por, Transformation.None, true)));
            }

            return new StepOutput(outputParameters);
        }

        /// <summary>
        /// Confidence level for the intervals of the bias (small study effect) tests of Egger and Harbord: twice the alpha of the analysis, so 90% where the analysis uses 95%.
        /// </summary>
        /// <remarks>These tests have low power, so they are conventionally judged at P &lt; 0.1 and reported with the matching 90% interval (Egger et al. 1997; Harbord et al. 2006).</remarks>
        /// <param name="cco">Confidence level of the analysis, as a proportion</param>
        private static double BiasTestConfidenceLevel(double cco)
        {
            double level = 1.0 - 2.0 * (1.0 - cco);
            return level > 0.0 && level < 1.0 ? level : 0.9;
        }

        public static void Metabias(IProgressBarHost host, ParameterBag outputParameters, double[] t, double[] tl, double[] tu, int n, ref double cco, Transformation xform)
        {
            double cit;
            if (cco > 0)
            {
                cit = PDF.gauinv(1.0 - (1.0 - cco) / 2.0);
            }
            else
            {
                cco = 0.95;
                cit = PDF.gauinv(0.975);
            }

            // setup basic variables
            // bool DoC = true; 
            int P = 2;
            int nx = 0;
            for (int i = 1; i <= n; i++)
                if (t[i] != Constant.MISSING && tl[i] != Constant.MISSING && tu[i] != Constant.MISSING && !double.IsInfinity(tl[i]) && !double.IsInfinity(tu[i]))
                    nx++;

            double tau = Constant.MISSING; double p2 = Constant.MISSING;
            double[] seb = null; double[] bd = null;
            double rdf = 0; double rss = 0;

            bool tooFewStrata = nx < 4;
            if (!tooFewStrata)
            {
                double[] y = new double[nx + 1];
                double[,] x = new double[nx + 1, P + 1];
                double[] wt = new double[nx + 1];
                double[] var = new double[nx + 1];
                double[] tt = new double[nx + 1];
                double[] ts = new double[nx + 1];
                nx = 0;
                double se;
                switch (xform)
                {
                    case Transformation.Log:
                        for (int i = 1; i <= n; i++)
                        {
                            if (t[i] != Constant.MISSING && tl[i] != Constant.MISSING && tu[i] != Constant.MISSING && !double.IsInfinity(tl[i]) && !double.IsInfinity(tu[i]) && tu[i] - tl[i] != 0.0 && t[i] > 0.0 && tl[i] > 0.0 && tu[i] > 0.0)
                            {
                                se = (Math.Log(tu[i]) - Math.Log(tl[i])) / 2 / cit;
                                if (se != 0.0)
                                {
                                    nx += 1;
                                    tt[nx] = Math.Log(t[i]);
                                    y[nx] = tt[nx] / se;
                                    x[nx, 2] = 1.0 / se;
                                    x[nx, 1] = 1.0;
                                    var[nx] = se * se;
                                    wt[nx] = 1.0;
                                }
                            }
                        }
                        break;
                    case Transformation.Z:
                        for (int i = 1; i <= n; i++)
                        {
                            //  Fisher's z is defined for any correlation strictly between -1 and 1. This test used to require the correlation and both limits to be positive, as the log transformation above does, which silently left out every study with a correlation or lower limit at or below zero.
                            if (t[i] != Constant.MISSING & tl[i] != Constant.MISSING & tu[i] != Constant.MISSING & !double.IsInfinity(tl[i]) & !double.IsInfinity(tu[i]) & tu[i] - tl[i] != 0.0 & Math.Abs(t[i]) < 1.0 & Math.Abs(tl[i]) < 1.0 & Math.Abs(tu[i]) < 1.0)
                            {
                                se = (MathDbl.rtoz(tu[i]) - MathDbl.rtoz(tl[i])) / 2 / cit;
                                if (se != 0.0)
                                {
                                    nx += 1;
                                    tt[nx] = MathDbl.rtoz(t[i]);
                                    y[nx] = tt[nx] / se;
                                    x[nx, 2] = 1.0 / se;
                                    x[nx, 1] = 1.0;
                                    var[nx] = se * se;
                                    wt[nx] = 1.0;
                                }
                            }
                        }
                        break;
                    case Transformation.None:
                        for (int i = 1; i <= n; i++)
                        {
                            if (t[i] != Constant.MISSING & tl[i] != Constant.MISSING & tu[i] != Constant.MISSING & !double.IsInfinity(tl[i]) & !double.IsInfinity(tu[i]))
                            {
                                se = (tu[i] - tl[i]) / 2 / cit;
                                if (se != 0)
                                {
                                    nx += 1;
                                    tt[nx] = t[i];
                                    y[nx] = tt[nx] / se;
                                    x[nx, 2] = 1.0 / se;
                                    x[nx, 1] = 1.0;
                                    var[nx] = se * se;
                                    wt[nx] = 1.0;
                                }
                            }
                        }
                        break;
                }

                // Begg's method
                double sumwt = 0.0;
                double sumwtt = 0.0;
                for (int i = 1; i <= nx; i++)
                {
                    double wx = 1.0 / var[i];
                    sumwt += wx;
                    sumwtt += tt[i] * wx;
                }
                for (int i = 1; i <= nx; i++)
                {
                    double vt = var[i] - 1.0 / sumwt;
                    ts[i] = (tt[i] - sumwtt / sumwt) / Math.Sqrt(vt);
                }
                Anova.XAgreeKendall(host, ts, var, 1, ref nx, out tau, out p2, out bool isLowPower, out bool isTauB);

                // setup regression call
                seb = new double[P + 1];
                bd = new double[P * P + 1];
                int incep = 1;
                int indep = 1;
                int iwt = 1;
                double[,] xx = new double[nx + 1, indep + 1 + iwt + 1];
                double[,] r = new double[P + 1, P + 1];
                double[] D = new double[P + 1];
                double[] xMin = new double[P + 1];
                double[] xMax = new double[P + 1];
                double[] wk = new double[2 * (P + 1) + 1];
                int[] idum = new int[1 + 1];
                for (int i = 1; i <= nx; i++)
                {
                    int j;
                    for (j = 1 + incep; j <= indep + incep; j++)
                        xx[i, j - incep] = x[i, j];
                    xx[i, indep + 1] = wt[i];
                    xx[i, indep + 2] = y[i];
                }
                int iwtcol = indep + 1;
                int irank = 0; int nrmiss = 0; int ifault = 0;
                Regress1.glsqr(0, incep, 0, nx, indep + iwt + 1, xx, -indep, idum, -1, idum, 0, iwtcol, bd, r, D, ref irank, ref rdf, ref rss, ref nrmiss, xMin, xMax, wk, ref ifault);
                if (ifault == 0)
                {
                    double[,] covb = new double[P + 1, P + 1];
                    Regress1.rcovarb(P, r, 1.0, covb, ref ifault);
                    double rms = rss / rdf;
                    Regress1.rcovarb(P, r, rms, covb, ref ifault);
                    for (int i = 1; i <= P; i++)
                        seb[i] = Math.Sqrt(covb[i, i]);
                }
            }

            //  cco and cit above recover each study's standard error from its limits, so they stay at the level of the analysis; only Egger's own interval uses the bias test level
            double biasCco = BiasTestConfidenceLevel(cco);
            double a, prob, cla, cua;
            if (!tooFewStrata)
            {
                MathDbl.civ(nx - P, out double citt, biasCco, out double _);
                Debug.Assert(null != seb);
                double tz = Math.Abs(bd[1] / seb[1]);
                prob = PDF.tvalp(tz, Convert.ToDouble(nx - P));
                if (prob > 1.0 - prob)
                    prob = 1.0 - prob;
                prob = 2.0 * prob;
                a = bd[1];
                cla = a - seb[1] * citt;
                cua = a + seb[1] * citt;
            }
            else
            {
                a = Constant.MISSING;
                cla = Constant.MISSING;
                cua = Constant.MISSING;
                prob = Constant.MISSING;
            }

            if (tooFewStrata)
            {
                outputParameters.AddOutput("warnTooFewStrata", "<too few strata>");
                p2 = Constant.MISSING;
            }
            else
            {
                outputParameters.AddOutput("tau", tau);
            }
            outputParameters.AddOutput("p2", p2);

            if (tooFewStrata)
            {
                outputParameters.AddOutput("a", tau);
                cla = Constant.MISSING;
                cua = Constant.MISSING;
                prob = Constant.MISSING;
            }
            else
            {
                outputParameters.AddOutput("a", a);
            }

            outputParameters.AddOutput("pc_egger", 100.0 * biasCco);
            outputParameters.AddOutput("cl", cla);
            outputParameters.AddOutput("cu", cua);
            outputParameters.AddOutput("p", prob);
        }

        public static StepOutput RptRiskDifferenceMeta(IPreferencesAndProgressBar host, ParameterBag parameters)
        {
            double cco = parameters["gamma"].AsDouble;
            if (cco <= 0)
                cco = 0.95;
            double cit = PDF.gauinv(1.0 - (1.0 - cco) / 2.0);

            DataFrame snFrame = parameters["sn"].AsDataFrame;
            DoubleVariable snVariable = (DoubleVariable)snFrame.Variables[0];
            DataFrame srFrame = parameters["sr"].AsDataFrame;
            DoubleVariable srVariable = (DoubleVariable)srFrame.Variables[0];
            DataFrame xnFrame = parameters["xn"].AsDataFrame;
            DoubleVariable xnVariable = (DoubleVariable)xnFrame.Variables[0];
            DataFrame xrFrame = parameters["xr"].AsDataFrame;
            DoubleVariable xrVariable = (DoubleVariable)xrFrame.Variables[0];
            int rawRows = snVariable.Length;

            DoubleArraysAndBooleans copiesRemovingMissingRows = Numerics.Utilities.RemoveMissingRows(new[] { snVariable.Data, srVariable.Data, xnVariable.Data, xrVariable.Data }, 0, rawRows, 1);
            double[] sn = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[0];
            double[] sr = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[1];
            double[] xn = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[2];
            double[] xr = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[3];

            string[] title = MakeTitles(parameters, "strata", "stratum {0}", rawRows, out bool hasUserSuppliedLabels);

            int k = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[0].Length - 1; /* 1-based */
            title = Numerics.Utilities.CopyValidRows(title, copiesRemovingMissingRows.ValidRowsInOriginal, 0, rawRows, 1, k);

            double[,] o = new double[k + 1, 4 + 1];
            double[] rkr = new double[k + 1];
            double[] rkw = new double[k + 1];
            double[] dsw = new double[k + 1];
            double[] rkrl = new double[k + 1];
            double[] rkru = new double[k + 1];
            double[] rkx = new double[k + 1];
            bool[] lerr = new bool[k + 1];
            bool[] uerr = new bool[k + 1];
            bool[] cced = new bool[k + 1];
            for (int i = 1; i <= k; i++)
            {
                o[i, 1] = Math.Abs(sr[i]);
                o[i, 3] = Math.Abs(sn[i] - sr[i]);
                if (sr[i] < 0 || sn[i] < 0 || sn[i] < sr[i])
                    throw new InvalidDataException();
                o[i, 2] = Math.Abs(xr[i]);
                o[i, 4] = Math.Abs(xn[i] - xr[i]);
                if (xr[i] < 0 || xn[i] < 0 || xn[i] < xr[i])
                    throw new InvalidDataException();
            }

            Riskdifma(host, k, o, out double rmh, out double ll, out double ul, out double x2Rmh, cit, cco, rkr, rkw, dsw, rkrl, rkru, rkx, lerr, uerr, out double qc, out double dsrd, out double dsx2, out double dsll, out double dsul, out double tausq, cced, out int ierr);
            if (ierr == -1)
                throw new InvalidDataException();

            ParameterBag outputParameters = new();

            IList<ParameterBag> inputsList = new List<ParameterBag>();
            outputParameters.AddOutput("*inputs", inputsList);
            for (int i = 1; i <= k; i++)
            {
                ParameterBag inputsParameters = new();
                inputsList.Add(inputsParameters);
                inputsParameters.AddOutput("st", i);
                inputsParameters.AddOutput("a", o[i, 1]);
                inputsParameters.AddOutput("b", o[i, 2]);
                inputsParameters.AddOutput("c", o[i, 3]);
                inputsParameters.AddOutput("d", o[i, 4]);
                string tmp = hasUserSuppliedLabels ? title[i] : string.Empty;
                if (cced[i])
                {
                    tmp += " [CC = ";
                    tmp += host.Preferences.MetaCC == -9.0
                              ? "treatment arm"
                              : host.Preferences.MetaCC.ToString();
                    tmp += "]";
                }
                inputsParameters.AddOutput("lb", tmp);
            }

            outputParameters.AddOutput("pc", cco * 100);
            outputParameters.AddOutput("method", host.Preferences.MetaExact ? "Miettinen" : "approximate");
            IList<ParameterBag> differencesList = new List<ParameterBag>();
            outputParameters.AddOutput("*differences", differencesList);
            for (int i = 1; i <= k; i++)
            {
                ParameterBag differencesParameters = new();
                differencesList.Add(differencesParameters);
                differencesParameters.AddOutput("st", i);
                differencesParameters.AddOutput("rd", rkr[i]);
                differencesParameters.AddOutput("lci", rkrl[i]);
                differencesParameters.AddOutput("uci", rkru[i]);
                differencesParameters.AddOutput("wt", 100 * rkw[i] / Formatting.dsum(rkw, 1));
                differencesParameters.AddOutput("dwt", 100 * dsw[i] / Formatting.dsum(dsw, 1));
                differencesParameters.AddOutput("lb", hasUserSuppliedLabels ? title[i] : string.Empty);
                differencesParameters.AddOutput("yi", rkr[i]);
                differencesParameters.AddOutput("vi", VarianceFromCI(rkrl[i], rkru[i], cit, false));
                // double a = o[ i, 1 ]; 
                // double b = o[ i, 2 ]; 
                // double C = o[ i, 3 ]; 
                // double D = o[ i, 4 ]; 
                // double N = a + b + C + D; 
            }

            outputParameters.AddOutput("rmh", rmh);
            outputParameters.AddOutput("from", ll);
            outputParameters.AddOutput("to", ul);

            outputParameters.AddOutput("x2", x2Rmh);
            outputParameters.AddOutput("df", 1);
            outputParameters.AddOutput("xp", PDF.chivalp(x2Rmh, 1.0));

            outputParameters.AddOutput("qc", qc);
            outputParameters.AddOutput("df_cochran", k - 1);
            outputParameters.AddOutput("xp_cochran", PDF.chivalp(qc, k - 1));
            outputParameters.AddOutput("tausq", tausq);
            IsquareNcc(host, qc, k, cco, cit, out double isq, out double llisq, out double ulisq);
            outputParameters.AddOutput("isq", isq);
            outputParameters.AddOutput("pc1", cco * 100);
            outputParameters.AddOutput("llisq", llisq);
            outputParameters.AddOutput("ulisq", ulisq);

            outputParameters.AddOutput("dsrd", dsrd);
            outputParameters.AddOutput("dsll", dsll);
            outputParameters.AddOutput("dsul", dsul);
            outputParameters.AddOutput("dsx2", dsx2);
            outputParameters.AddOutput("df_ds", 1);
            outputParameters.AddOutput("xp_ds", PDF.chivalp(dsx2, 1.0));

            IList<ParameterBag> eggerList = new List<ParameterBag>();
            outputParameters.AddOutput("*egger", eggerList);
            ParameterBag eggerParameters = new();
            eggerList.Add(eggerParameters);
            Metabias(host, eggerParameters, rkr, rkrl, rkru, k, ref cco, Transformation.None);

            IList<ParameterBag> chartList = new List<ParameterBag>();
            outputParameters.AddOutput("*chart", chartList);
            ParameterBag chartParameters;

            //  Ensure no accidental (0,0) plots
            rkr[0] = Constant.MISSING;
            rkx[0] = Constant.MISSING;
            rkw[0] = Constant.MISSING;

            if (k > 3)
            {
                chartParameters = new ParameterBag();
                chartList.Add(chartParameters);
                chartParameters.AddOutput("chart", ChartRendererFactory.PrepForLater(ChartType.BiasMA, new BiasMAOptions(rkr, rkx, rkw, k, "Risk difference", rkrl, rkru, cco, cit, rmh, Transformation.None, false)));
            }

            chartParameters = new ParameterBag();
            chartList.Add(chartParameters);
            chartParameters.AddOutput("chart", ChartRendererFactory.PrepForLater(ChartType.MHRD, new MHOptions(1, k, rkw, title, rmh, ll, ul, cco, rkr, rkrl, rkru, lerr, uerr, null, "Risk difference meta-analysis plot [fixed effects]", 1, "risk difference")));

            chartParameters = new ParameterBag();
            chartList.Add(chartParameters);
            chartParameters.AddOutput("chart", ChartRendererFactory.PrepForLater(ChartType.MHRD, new MHOptions(1, k, dsw, title, dsrd, dsll, dsul, cco, rkr, rkrl, rkru, lerr, uerr, null, "Risk difference meta-analysis plot [random effects]", 1, "risk difference")));

            return new StepOutput(outputParameters);
        }

        public static StepOutput RptRelativeRiskMeta(IPreferencesAndProgressBar host, ParameterBag parameters)
        {
            const int lowerBound = 1;

            double cco = parameters["gamma"].AsDouble;
            if (cco <= 0)
                cco = 0.95;
            double cit = PDF.gauinv(1.0 - (1.0 - cco) / 2.0);

            DataFrame snFrame = parameters["sn"].AsDataFrame;
            DoubleVariable snVariable = (DoubleVariable)snFrame.Variables[0];
            DataFrame srFrame = parameters["sr"].AsDataFrame;
            DoubleVariable srVariable = (DoubleVariable)srFrame.Variables[0];
            DataFrame xnFrame = parameters["xn"].AsDataFrame;
            DoubleVariable xnVariable = (DoubleVariable)xnFrame.Variables[0];
            DataFrame xrFrame = parameters["xr"].AsDataFrame;
            DoubleVariable xrVariable = (DoubleVariable)xrFrame.Variables[0];
            int rawRows = snVariable.Length;

            DoubleArraysAndBooleans copiesRemovingMissingRows = Numerics.Utilities.RemoveMissingRows(new[] { snVariable.Data, srVariable.Data, xnVariable.Data, xrVariable.Data }, 0, rawRows, 1);
            double[] sn = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[0];
            double[] sr = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[1];
            double[] xn = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[2];
            double[] xr = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[3];

            string[] title = MakeTitles(parameters, "strata", "stratum {0}", rawRows, out bool hasUserSuppliedLabels);

            int k = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[0].Length - 1; /* 1-based */
            title = Numerics.Utilities.CopyValidRows(title, copiesRemovingMissingRows.ValidRowsInOriginal, 0, rawRows, 1, k);

            double[,] o = new double[k + lowerBound, 4 + 1];
            double[] axll = new double[k + lowerBound];
            double[] axul = new double[k + lowerBound];
            for (int i = 1; i <= k; i++)
            {
                o[i, 1] = Math.Abs(sr[i]);
                o[i, 3] = Math.Abs(sn[i] - sr[i]);
                if (sr[i] < 0 || sn[i] < 0 || sn[i] < sr[i])
                    throw new InvalidDataException("All data values must be >= 0, and the number responding must be less than the sample size");

                o[i, 2] = Math.Abs(xr[i]);
                o[i, 4] = Math.Abs(xn[i] - xr[i]);
                if (xr[i] < 0 || xn[i] < 0 || xn[i] < xr[i])
                    throw new InvalidDataException("All data values must be >= 0, and the number responding must be less than the sample size");
            }

            RelativeRiskMA(host, lowerBound, k, out int realk, o, out double rmh, out double ll, out double ul, out double x2Rmh, cit, out double[] rkr, out double[] rkw, out double[] dsw, out double[] rkrl, out double[] rkru, out double[] rkx, out bool[] lerr, out bool[] uerr, out double qc, out double dsrr, out double dsx2, out double dsll, out double dsul, out double tausq, out bool[] cced, out bool[] included, out int ierr);
            if (ierr == -1)
                throw new InvalidDataException("relriskma() returned an error");

            ParameterBag outputParameters = new();

            IList<ParameterBag> inputsList = new List<ParameterBag>();
            outputParameters.AddOutput("*inputs", inputsList);
            for (int i = 1; i <= k; i++)
            {
                ParameterBag inputsParameters = new();
                inputsList.Add(inputsParameters);
                inputsParameters.AddOutput("st", i);
                inputsParameters.AddOutput("a", o[i, 1]);
                inputsParameters.AddOutput("b", o[i, 2]);
                inputsParameters.AddOutput("c", o[i, 3]);
                inputsParameters.AddOutput("d", o[i, 4]);
                inputsParameters.AddOutput("lb", hasUserSuppliedLabels ? title[i] : string.Empty);
            }

            outputParameters.AddOutput("pc", cco * 100);
            outputParameters.AddOutput("method", host.Preferences.MetaExact ? "Koopman" : "approximate");

            IList<ParameterBag> risksList = new List<ParameterBag>();
            outputParameters.AddOutput("*risks", risksList);
            for (int i = 1; i <= k; i++)
            {
                ParameterBag risksParameters = new();
                risksList.Add(risksParameters);
                risksParameters.AddOutput("st", i);
                risksParameters.AddOutput("rr", rkr[i]);
                risksParameters.AddOutput("yi", rkr[i] > 0 ? Math.Log(rkr[i]) : 0);
                risksParameters.AddOutput("vi", VarianceFromCI(rkrl[i], rkru[i], cit, true));
                risksParameters.AddOutput("lci", rkrl[i]);
                risksParameters.AddOutput("uci", rkru[i]);
                risksParameters.AddOutput("wt", 100 * rkw[i] / Formatting.dsum(rkw, 1));
                risksParameters.AddOutput("dwt", 100 * dsw[i] / Formatting.dsum(dsw, 1));
                risksParameters.AddOutput("lb", GetMetaLabel(host, o, i, hasUserSuppliedLabels, cced, title));
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
            IsquareNcc(host, qc, realk, cco, cit, out double isq, out double llisq, out double ulisq);
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

            GetAproxrrCI(host, o, k, cit, axll, axul);

            IList<ParameterBag> eggerList = new List<ParameterBag>();
            outputParameters.AddOutput("*egger", eggerList);
            ParameterBag eggerParameters = new();
            eggerList.Add(eggerParameters);
            Metabias(host, eggerParameters, rkr, axll, axul, k, ref cco, Transformation.Log);

            IList<ParameterBag> harbordList = new List<ParameterBag>();
            outputParameters.AddOutput("*harbord", harbordList);
            ParameterBag harbordParameters = new();
            harbordList.Add(harbordParameters);
            ModMetabias(host, harbordParameters, o, k, cco, 2);

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

            return new StepOutput(outputParameters);
        }

        // TODO: Move this somewhere more sensible now that it's used by functions outside meta.
        internal static string[] MakeTitles(ParameterBag parameters, string parameterName, string missingTitleFormat, int expectedRows, out bool hasUserSuppliedLabels, int extraElementsAtEnd = 0)
        {
            string[] title;
            hasUserSuppliedLabels = parameters.ContainsKey(parameterName) && parameters[parameterName].HasData;
            if (hasUserSuppliedLabels)
            {
                DataFrame strataFrame = parameters[parameterName].AsDataFrame;
                StringVariable strataVariable = (StringVariable)strataFrame.Variables[0];
                if (extraElementsAtEnd > 0)
                {
                    // Allocate a new array to hold the extra rows
                    title = new string[expectedRows + extraElementsAtEnd];
                    Array.Copy(strataVariable.Data, title, strataVariable.Data.Length);
                }
                else
                {
                    // No extra rows, just nick the data from the variable
                    title = strataVariable.Data;
                }
                for (int i = 0; i < expectedRows; i++)
                {
                    string buf = strataVariable.Data[i].Trim();
                    if (buf.Length > 0)
                    {
                        if (buf.Length > 50)
                            buf = buf.Substring(0, 50);
                        title[i] = buf;
                    }
                    else
                        title[i] = string.Format(missingTitleFormat, i + 1);
                }
            }
            else
            {
                title = new string[expectedRows + extraElementsAtEnd];
                for (int i = 0; i < expectedRows; i++)
                    title[i] = string.Format(missingTitleFormat, i + 1);
            }
            return title;
        }

        public static StepOutput RptEffect(IPreferencesAndProgressBar host, ParameterBag parameters)
        {
            double cco = parameters["gamma"].AsDouble;
            if (cco <= 0)
                cco = 0.95;
            double cit = PDF.gauinv(1.0 - (1.0 - cco) / 2.0);

            string type = parameters["type"].AsString.ToLower(CultureInfo.InvariantCulture);
            int proc;
            switch (type)
            {
                case "g":
                    proc = 2;
                    break;
                case "m":
                    proc = 3;
                    break;
                default:
                    proc = 1;
                    break;
            }

            DataFrame enFrame = parameters["en"].AsDataFrame;
            DoubleVariable enVariable = (DoubleVariable)enFrame.Variables[0];
            int rawRows = enVariable.Length;

            DoubleVariable emVariable = null;
            DoubleVariable esVariable = null;
            if (proc != 2)
            {
                DataFrame emFrame = parameters["em"].AsDataFrame;
                emVariable = (DoubleVariable)emFrame.Variables[0];

                DataFrame esFrame = parameters["es"].AsDataFrame;
                esVariable = (DoubleVariable)esFrame.Variables[0];
            }

            DataFrame cnFrame = parameters["cn"].AsDataFrame;
            DoubleVariable cnVariable = (DoubleVariable)cnFrame.Variables[0];

            DoubleVariable gVariable = null;
            DoubleVariable cmVariable = null;
            DoubleVariable csVariable = null;
            bool gotg = proc == 2;
            if (gotg)
            {
                DataFrame gFrame = parameters["g"].AsDataFrame;
                gVariable = (DoubleVariable)gFrame.Variables[0];
            }
            else
            {
                DataFrame cmFrame = parameters["cm"].AsDataFrame;
                cmVariable = (DoubleVariable)cmFrame.Variables[0];

                DataFrame csFrame = parameters["cs"].AsDataFrame;
                csVariable = (DoubleVariable)csFrame.Variables[0];
            }

            DoubleArraysAndBooleans copiesRemovingMissingRows = Numerics.Utilities.RemoveMissingRows(new[] { enVariable.Data, emVariable?.Data, esVariable?.Data, gVariable?.Data, cnVariable.Data, cmVariable?.Data, csVariable?.Data }, 0, rawRows, 1);
            double[] en = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[0];
            double[] em = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[1];
            double[] es = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[2];
            double[] g = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[3];
            double[] cn = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[4];
            double[] cm = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[5];
            double[] cs = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[6];

            string[] title = MakeTitles(parameters, "strata", "stratum {0}", rawRows, out bool hasUserSuppliedLabels);

            int k = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[0].Length - 1; /* 1-based */
            title = Numerics.Utilities.CopyValidRows(title, copiesRemovingMissingRows.ValidRowsInOriginal, 0, rawRows, 1, k);

            if (proc != 3)
            {
                // single effect analysis
                double[] d = new double[k + 1];
                double[] gj = new double[k + 1];
                double[] lcid = new double[k + 1];
                double[] ucid = new double[k + 1];
                double[] lcig = new double[k + 1];
                double[] ucig = new double[k + 1];
                double[] rkw = new double[k + 1];
                double[] rkx = new double[k + 1];
                Debug.Assert(null != es);
                bool poolok = k > 1;
                if (!gotg)
                {
                    g = new double[k + 1];
                    for (int i = 1; i <= k; i++)
                    {
                        double n = cn[i] + en[i];
                        if (((en[i] - 1.0) * Math.Pow(es[i], 2.0) + (cn[i] - 1.0) * Math.Pow(cs[i], 2.0)) / (n - 2.0) > 0)
                        {
                            double s = Math.Sqrt(((en[i] - 1.0) * Math.Pow(es[i], 2.0) + (cn[i] - 1.0) * Math.Pow(cs[i], 2.0)) / (n - 2.0));
                            g[i] = (em[i] - cm[i]) / s;
                        }
                        else
                        {
                            g[i] = Constant.MISSING;
                        }
                    }
                }

                double vard;
                for (int i = 1; i <= k; i++)
                {
                    double n = cn[i] + en[i];
                    rkx[i] = n;
                    if (g[i] != Constant.MISSING)
                    {
                        double m = n - 2;
                        if (m < 200)
                            gj[i] = Math.Exp(PDF.alogam(m / 2.0)) / (Math.Sqrt(m / 2.0) * Math.Exp(PDF.alogam((m - 1.0) / 2.0)));
                        else
                            gj[i] = 1.0 - 3.0 / (4.0 * m - 1.0);
                        d[i] = gj[i] * g[i];
                        vard = n / (cn[i] * en[i]) + Math.Pow(d[i], 2.0) / (2.0 * n);
                        lcid[i] = d[i] - cit * Math.Sqrt(vard);
                        ucid[i] = d[i] + cit * Math.Sqrt(vard);
                        double z = Math.Sqrt(cn[i] * en[i] / n);
                        Ginterval(g[i], Convert.ToInt32(n - 2), z, (1.0 - cco) / 2.0, lcid[i], ucid[i], out lcig[i], out ucig[i]);
                    }
                    else
                    {
                        poolok = false;
                        g[i] = Constant.MISSING;
                        gj[i] = Constant.MISSING;
                        d[i] = Constant.MISSING;
                        lcid[i] = Constant.MISSING;
                        ucid[i] = Constant.MISSING;
                        lcig[i] = Constant.MISSING;
                        ucig[i] = Constant.MISSING;
                    }
                }

                ParameterBag outputParameters = new();
                outputParameters.AddOutput("pc", cco * 100);

                IList<ParameterBag> exactList = new List<ParameterBag>();
                outputParameters.AddOutput("*exact", exactList);
                for (int i = 1; i <= k; i++)
                {
                    ParameterBag exactParameters = new();
                    exactList.Add(exactParameters);
                    exactParameters.AddOutput("st", i);
                    exactParameters.AddOutput("gj", gj[i]);
                    exactParameters.AddOutput("g", g[i]);
                    exactParameters.AddOutput("lci", lcig[i]);
                    exactParameters.AddOutput("uci", ucig[i]);
                    exactParameters.AddOutput("lb", hasUserSuppliedLabels ? title[i] : string.Empty);
                }

                IList<ParameterBag> approximateList = new List<ParameterBag>();
                outputParameters.AddOutput("*approximate", approximateList);
                for (int i = 1; i <= k; i++)
                {
                    ParameterBag approximateParameters = new();
                    approximateList.Add(approximateParameters);
                    approximateParameters.AddOutput("st", i);
                    approximateParameters.AddOutput("ne", en[i]);
                    approximateParameters.AddOutput("nc", cn[i]);
                    approximateParameters.AddOutput("d", d[i]);
                    approximateParameters.AddOutput("lci", lcid[i]);
                    approximateParameters.AddOutput("uci", ucid[i]);
                    approximateParameters.AddOutput("lb", hasUserSuppliedLabels ? title[i] : string.Empty);
                }

                IList<ParameterBag> poolOkList = new List<ParameterBag>();
                outputParameters.AddOutput("*poolok", poolOkList);
                // pooled analysis
                double dsd = 0; double dsll = 0; double dsul = 0;
                double dplus = 0; double dplusll = 0; double dplusul = 0;
                double sumwt = 0; double sumdwt = 0;
                double[] hedgesOlkinWeights = new double[k + 1];
                double[] derSimonianLairdWeights = new double[k + 1];

                if (poolok)
                {
                    for (int i = 1; i <= k; i++)
                    {
                        double n = cn[i] + en[i];
                        vard = n / (cn[i] * en[i]) + Math.Pow(d[i], 2.0) / (2.0 * n);
                        double wt = 1.0 / vard;
                        rkw[i] = wt;
                        sumwt += wt;
                        sumdwt += d[i] * wt;
                    }
                    dplus = sumdwt / sumwt;
                    double vardplus = 1 / sumwt;
                    double dplusz = dplus / Math.Sqrt(vardplus);
                    dplusll = dplus - cit * Math.Sqrt(vardplus);
                    dplusul = dplus + cit * Math.Sqrt(vardplus);
                    double qc = 0;
                    sumwt = 0;
                    double sumsqwt = 0;
                    for (int i = 1; i <= k; i++)
                    {
                        double n = cn[i] + en[i];
                        vard = n / (cn[i] * en[i]) + d[i] * d[i] / (2.0 * n);
                        double wt = 1.0 / vard;
                        qc += wt * Math.Pow(d[i] - dplus, 2.0);
                        sumwt += wt;
                        sumsqwt += wt * wt;
                        hedgesOlkinWeights[i] = wt;
                    }
                    double sumHedgesOlkinWeights = sumwt;

                    // DerSimonian-Laird treatment
                    double tausq;
                    if (sumwt - sumsqwt / sumwt == 0.0)
                        tausq = 0.0;
                    else
                        tausq = (qc - Convert.ToDouble(k - 1)) / (sumwt - sumsqwt / sumwt);
                    if (tausq < 0)
                        tausq = 0;
                    sumwt = 0;
                    sumdwt = 0;
                    for (int i = 1; i <= k; i++)
                    {
                        double n = cn[i] + en[i];
                        vard = n / (cn[i] * en[i]) + d[i] * d[i] / (2.0 * n);
                        double wt = 1.0 / vard;
                        wt = 1.0 / (tausq + 1.0 / wt);
                        sumwt += wt;
                        sumdwt += d[i] * wt;
                        derSimonianLairdWeights[i] = wt;
                    }
                    double sumDerSimonianLairdWeights = sumwt;

                    dsd = sumdwt / sumwt;
                    double dsz = sumdwt / Math.Sqrt(sumwt);
                    dsll = dsd - cit / Math.Sqrt(sumwt);
                    dsul = dsd + cit / Math.Sqrt(sumwt);

                    ParameterBag poolOkParameters = new();
                    poolOkList.Add(poolOkParameters);
                    poolOkParameters.AddOutput("dplus", dplus);
                    poolOkParameters.AddOutput("from", dplusll);
                    poolOkParameters.AddOutput("to", dplusul);
                    poolOkParameters.AddOutput("z", dplusz);
                    poolOkParameters.AddOutput("p", MathDbl.zvalp2(dplusz));
                    poolOkParameters.AddOutput("qc", qc);
                    poolOkParameters.AddOutput("df", k - 1);
                    poolOkParameters.AddOutput("xp", PDF.chivalp(qc, k - 1));
                    poolOkParameters.AddOutput("tausq", tausq);
                    IsquareNcc(host, qc, k, cco, cit, out double isq, out double llisq, out double ulisq);
                    poolOkParameters.AddOutput("isq", isq);
                    poolOkParameters.AddOutput("pc1", cco * 100);
                    poolOkParameters.AddOutput("llisq", llisq);
                    poolOkParameters.AddOutput("ulisq", ulisq);
                    poolOkParameters.AddOutput("dsrd", dsd);
                    poolOkParameters.AddOutput("dsll", dsll);
                    poolOkParameters.AddOutput("dsul", dsul);
                    poolOkParameters.AddOutput("dz", dsz);
                    poolOkParameters.AddOutput("dp", MathDbl.zvalp2(dsz));

                    IList<ParameterBag> weightsList = new List<ParameterBag>();
                    outputParameters.AddOutput("*weights", weightsList);
                    for (int i = 1; i <= k; i++)
                    {
                        ParameterBag weightsParameters = new();
                        weightsList.Add(weightsParameters);
                        weightsParameters.AddOutput("st", i);
                        weightsParameters.AddOutput("howt", 100.0 * hedgesOlkinWeights[i] / sumHedgesOlkinWeights);
                        weightsParameters.AddOutput("dswt", 100.0 * derSimonianLairdWeights[i] / sumDerSimonianLairdWeights);
                        weightsParameters.AddOutput("lb", hasUserSuppliedLabels ? title[i] : string.Empty);
                    }
                }

                IList<ParameterBag> eggerList = new List<ParameterBag>();
                outputParameters.AddOutput("*egger", eggerList);
                ParameterBag eggerParameters = new();
                eggerList.Add(eggerParameters);
                Metabias(host, eggerParameters, d, lcid, ucid, k, ref cco, Transformation.None);

                IList<ParameterBag> chartList = new List<ParameterBag>();
                outputParameters.AddOutput("*chart", chartList);
                ParameterBag chartParameters;

                if (k > 3)
                {
                    chartParameters = new ParameterBag();
                    chartList.Add(chartParameters);
                    chartParameters.AddOutput("chart", ChartRendererFactory.PrepForLater(ChartType.BiasMA, new BiasMAOptions(d, rkx, rkw, k, "Effect size", lcid, ucid, cco, cit, dplus, Transformation.None, false)));
                }

                chartParameters = new ParameterBag();
                chartList.Add(chartParameters);
                chartParameters.AddOutput("chart", ChartRendererFactory.PrepForLater(ChartType.Effect, new EffectOptions(k, cn, en, title, dplus, dplusll, dplusul, cco, d, lcid, ucid, "Effect size meta-analysis plot [fixed effects]", 1, "effect size")));

                chartParameters = new ParameterBag();
                chartList.Add(chartParameters);
                chartParameters.AddOutput("chart", ChartRendererFactory.PrepForLater(ChartType.Effect, new EffectOptions(k, cn, en, title, dsd, dsll, dsul, cco, d, lcid, ucid, "Effect size meta-analysis plot [random effects]", 1, "effect size")));

                return new StepOutput(outputParameters);
            }
            else
            {
                // single wmd analysis
                double[] d = new double[k + 1];
                double[] lcid = new double[k + 1];
                double[] ucid = new double[k + 1];
                double[] rkw = new double[k + 1];
                double[] rkx = new double[k + 1];
                bool poolok = k > 1;
                for (int i = 1; i <= k; i++)
                {
                    double n = cn[i] + en[i];
                    rkx[i] = n;
                    if (en[i] > 0 & cn[i] > 0 & cs[i] > 0)
                    {
                        double spool = ((en[i] - 1.0) * Math.Pow(es[i], 2.0) + (cn[i] - 1.0) * Math.Pow(cs[i], 2.0)) / (en[i] + cn[i] - 2.0);
                        double sed = Math.Sqrt(spool * (1.0 / en[i] + 1.0 / cn[i]));
                        d[i] = em[i] - cm[i];
                        lcid[i] = d[i] - cit * sed;
                        ucid[i] = d[i] + cit * sed;
                    }
                    else
                    {
                        d[i] = Constant.MISSING;
                        lcid[i] = Constant.MISSING;
                        ucid[i] = Constant.MISSING;
                        poolok = false;
                    }
                }

                ParameterBag outputParameters = new();
                outputParameters.AddOutput("pc", cco * 100);
                IList<ParameterBag> approximateList = new List<ParameterBag>();
                outputParameters.AddOutput("*approximate", approximateList);
                for (int i = 1; i <= k; i++)
                {
                    ParameterBag approximateParameters = new();
                    approximateList.Add(approximateParameters);
                    approximateParameters.AddOutput("st", i);
                    approximateParameters.AddOutput("ne", en[i]);
                    approximateParameters.AddOutput("nc", cn[i]);
                    approximateParameters.AddOutput("d", d[i]);
                    approximateParameters.AddOutput("lci", lcid[i]);
                    approximateParameters.AddOutput("uci", ucid[i]);
                    approximateParameters.AddOutput("lb", hasUserSuppliedLabels ? title[i] : string.Empty);
                }


                IList<ParameterBag> poolOkList = new List<ParameterBag>();
                outputParameters.AddOutput("*poolok", poolOkList);
                // pooled wmd analysis
                double dsd = 0; double dsll = 0; double dsul = 0;
                double dplus = 0; double dplusll = 0; double dplusul = 0;
                if (poolok)
                {
                    double sumwt = 0;
                    double sumdwt = 0;
                    for (int i = 1; i <= k; i++)
                    {
                        double wt = 1.0 / (Math.Pow(es[i], 2.0) / en[i] + Math.Pow(cs[i], 2.0) / cn[i]);
                        rkw[i] = wt;
                        sumwt += wt;
                        sumdwt += d[i] * wt;
                    }
                    dplus = sumdwt / sumwt;
                    double vardplus = 1.0 / sumwt;
                    double dplusz = dplus / Math.Sqrt(vardplus);
                    dplusll = dplus - cit * Math.Sqrt(vardplus);
                    dplusul = dplus + cit * Math.Sqrt(vardplus);
                    double qc = 0;
                    sumwt = 0;
                    double sumsqwt = 0;
                    for (int i = 1; i <= k; i++)
                    {
                        double wt = 1.0 / (Math.Pow(es[i], 2.0) / en[i] + Math.Pow(cs[i], 2.0) / cn[i]);
                        qc += wt * Math.Pow(d[i] - dplus, 2.0);
                        sumwt += wt;
                        sumsqwt += wt * wt;
                    }

                    // DerSimonian-Laird treatment
                    double tausq;
                    if (sumwt - sumsqwt / sumwt == 0.0)
                        tausq = 0.0;
                    else
                        tausq = (qc - Convert.ToDouble(k - 1)) / (sumwt - sumsqwt / sumwt);
                    if (tausq < 0)
                        tausq = 0;
                    sumwt = 0;
                    sumdwt = 0;
                    for (int i = 1; i <= k; i++)
                    {
                        double wt = 1.0 / (Math.Pow(es[i], 2.0) / en[i] + Math.Pow(cs[i], 2.0) / cn[i]);
                        wt = 1.0 / (tausq + 1.0 / wt);
                        sumwt += wt;
                        sumdwt += d[i] * wt;
                    }
                    dsd = sumdwt / sumwt;
                    double dsz = sumdwt / Math.Sqrt(sumwt);
                    dsll = dsd - cit / Math.Sqrt(sumwt);
                    dsul = dsd + cit / Math.Sqrt(sumwt);

                    ParameterBag poolOkParameters = new();
                    poolOkList.Add(poolOkParameters);
                    poolOkParameters.AddOutput("dplus", dplus);
                    poolOkParameters.AddOutput("from", dplusll);
                    poolOkParameters.AddOutput("to", dplusul);
                    poolOkParameters.AddOutput("z", dplusz);
                    poolOkParameters.AddOutput("p", MathDbl.zvalp2(dplusz));
                    poolOkParameters.AddOutput("qc", qc);
                    poolOkParameters.AddOutput("df", k - 1);
                    poolOkParameters.AddOutput("xp", PDF.chivalp(qc, k - 1));
                    poolOkParameters.AddOutput("tausq", tausq);
                    IsquareNcc(host, qc, k, cco, cit, out double isq, out double llisq, out double ulisq);
                    poolOkParameters.AddOutput("isq", isq);
                    poolOkParameters.AddOutput("pc1", cco * 100);
                    poolOkParameters.AddOutput("llisq", llisq);
                    poolOkParameters.AddOutput("ulisq", ulisq);
                    poolOkParameters.AddOutput("dsrd", dsd);
                    poolOkParameters.AddOutput("dsll", dsll);
                    poolOkParameters.AddOutput("dsul", dsul);
                    poolOkParameters.AddOutput("dz", dsz);
                    poolOkParameters.AddOutput("zp", MathDbl.zvalp2(dsz));
                }

                IList<ParameterBag> eggerList = new List<ParameterBag>();
                outputParameters.AddOutput("*egger", eggerList);
                ParameterBag eggerParameters = new();
                eggerList.Add(eggerParameters);
                Metabias(host, eggerParameters, d, lcid, ucid, k, ref cco, Transformation.None);

                IList<ParameterBag> chartList = new List<ParameterBag>();
                outputParameters.AddOutput("*chart", chartList);
                ParameterBag chartParameters;

                if (k > 3)
                {
                    chartParameters = new ParameterBag();
                    chartList.Add(chartParameters);
                    chartParameters.AddOutput("chart", ChartRendererFactory.PrepForLater(ChartType.BiasMA, new BiasMAOptions(d, rkx, rkw, k, "Effect size", lcid, ucid, cco, cit, dplus, Transformation.None, false)));
                }

                // bool bfault = false; 
                chartParameters = new ParameterBag();
                chartList.Add(chartParameters);
                chartParameters.AddOutput("chart", ChartRendererFactory.PrepForLater(ChartType.Effect, new EffectOptions(k, cn, en, title, dplus, dplusll, dplusul, cco, d, lcid, ucid, "Effect size meta-analysis plot [fixed effects]", 1, "weighted mean difference")));

                chartParameters = new ParameterBag();
                chartList.Add(chartParameters);
                chartParameters.AddOutput("chart", ChartRendererFactory.PrepForLater(ChartType.Effect, new EffectOptions(k, cn, en, title, dsd, dsll, dsul, cco, d, lcid, ucid, "Effect size meta-analysis plot [random effects]", 1, "weighted mean difference")));

                return new StepOutput(outputParameters);
            }
        }

        private static void Ginterval(double g, int df, double z, double alpha, double lcid, double ucid, out double lcig, out double ucig)
        {

            double t = g * z;
            double al = 1.0 - alpha;
            double au = alpha;
            const double acc = 0.000000001;
            double x = t; // lcid * z; 
            double na = ExFortran.pnct(t, df, x, out _);
            double delta = Math.Abs(na - al);
            double last = delta;
            double gstep = x;
            int cnt = 0;
            double gtry;

            // lcig = Constant.MISSING;
            do
            {
                cnt++;
                if (cnt > 100)
                    break;
                gstep /= 10.0;
                gtry = x + gstep;
                na = ExFortran.pnct(t, df, gtry, out _);
            }
            while (!(na > 0 && na < 1));

            if (Math.Abs(na - al) > delta)
                gstep = -gstep;
            cnt = 0;
            gtry = x;
            do
            {
                cnt++;
                if (cnt > 5000)
                {
                    lcig = Constant.MISSING;
                    break;
                }
                gtry += gstep;
                na = ExFortran.pnct(t, df, gtry, out _);
                delta = Math.Abs(na - al);
                if (delta < acc)
                {
                    lcig = gtry / z;
                    break;
                }
                if (delta > last)
                    gstep = -gstep / 10.0;
                last = delta;
            }
            while (true);

            x = ucid * z;
            na = ExFortran.pnct(t, df, x, out _);
            delta = Math.Abs(na - au);
            last = delta;
            gstep = x;
            cnt = 0;
            do
            {
                cnt++;
                if (cnt > 100)
                    break;
                gstep /= 10.0;
                gtry = x + gstep;
                na = ExFortran.pnct(t, df, gtry, out _);
            }
            while (!(na > 0 & na < 1));

            if (Math.Abs(na - au) > delta)
                gstep = -gstep;

            cnt = 0;
            gtry = x;
            ucig = Constant.MISSING;
            do
            {
                cnt++;
                if (cnt > 5000)
                {
                    lcig = Constant.MISSING;
                    break;
                }
                gtry += gstep;
                na = ExFortran.pnct(t, df, gtry, out _);
                delta = Math.Abs(na - au);
                if (delta < acc)
                {
                    ucig = gtry / z;
                    break;
                }
                if (delta > last)
                    gstep = -gstep / 10.0;
                last = delta;
            }
            while (true);
        }

        public static void RelativeRiskMA(IPreferences host, int lowerBound, int k, out int realk, double[,] o, out double rmh, out double ll, out double ul, out double x2Rmh, double cit, out double[] rkr, out double[] rkw, out double[] dsw, out double[] rkrl, out double[] rkru, out double[] rkx, out bool[] lerr, out bool[] uerr, out double qc, out double dsrr, out double dsx2, out double dsll, out double dsul, out double tausq, out bool[] cced, out bool[] included, out int ierr)
        {
            ierr = -1;
            double siga = 0.0;
            double sumwt = 0.0;
            double svd1 = 0.0;
            double svd2 = 0.0;
            double svd3 = 0.0;
            realk = 0;

            rkr = new double[k + lowerBound];
            rkw = new double[k + lowerBound];
            dsw = new double[k + lowerBound];
            rkrl = new double[k + lowerBound];
            rkru = new double[k + lowerBound];
            rkx = new double[k + lowerBound];
            lerr = new bool[k + lowerBound];
            uerr = new bool[k + lowerBound];
            cced = new bool[k + lowerBound];
            included = new bool[k + lowerBound];

            for (int i = lowerBound; i < lowerBound + k; i++)
            {
                double a = o[i, 1];
                double b = o[i, 2];
                double c = o[i, 3];
                double d = o[i, 4];
                double n = a + b + c + d;
                rkx[i] = n;
                if (n <= 0)
                    throw new InvalidDataException();

                included[i] = IncludeTable(o, i);
                if (included[i])
                {
                    realk++;

                    if (host.Preferences.MetaExact)
                    {
                        // try Koopman rr and ci for stratum before continuity correction
                        MathDbl.lr_ci(b, a, b + d, a + c, cit, out rkrl[i], out rkru[i]);
                        lerr[i] = rkrl[i] == Constant.MISSING;
                        uerr[i] = rkru[i] == Constant.MISSING;
                    }

                    // get rr continuity corrected if neccessary
                    if (a <= 0.0 || b <= 0.0 || c <= 0.0 || d <= 0.0)
                    {
                        cced[i] = true;
                        ContinuityCorrect(host, a, b, c, d, out a, out b, out c, out d);
                    }
                    else
                    {
                        cced[i] = false;
                    }
                    rkr[i] = a / (a + c) / (b / (b + d));
                    if (!host.Preferences.MetaExact)
                    {
                        // approximate se of log rr
                        double selogrr = Math.Sqrt(1.0 / a + 1.0 / b - 1.0 / (a + c) - 1.0 / (b + d));
                        rkrl[i] = Math.Exp(Math.Log(rkr[i]) - selogrr * cit);
                        rkru[i] = Math.Exp(Math.Log(rkr[i]) + selogrr * cit);
                        lerr[i] = false;
                        uerr[i] = false;
                    }

                    //  Rothman-Boice combined risk ratio
                    double weight = b * (a + c) / n;
                    rkw[i] = weight;
                    sumwt += weight;
                    siga += a * (b + d) / n;
                    // Greenland-Robins variance
                    svd1 += ((a + b) * (a + c) * (b + d) - a * b * n) / Math.Pow(n, 2.0);
                    svd2 += a * (b + d) / n;
                    svd3 += b * (a + c) / n;

                }
                else
                {
                    rkr[i] = Constant.MISSING;
                    rkrl[i] = 0.0;
                    rkru[i] = double.PositiveInfinity;
                    lerr[i] = false;
                    uerr[i] = false;
                }

            }

            rmh = siga / sumwt;
            double serr = svd1 / (svd2 * svd3);
            ll = Math.Exp(Math.Log(rmh) - Math.Sqrt(serr * cit * cit));
            ul = Math.Exp(Math.Log(rmh) + Math.Sqrt(serr * cit * cit));
            if (ll > ul)
                Utilities.Utilities.Swap(ref ll, ref ul);
            x2Rmh = Math.Pow(Math.Log(rmh) / Math.Sqrt(serr), 2.0);

            // Q (combinability)
            qc = 0.0;
            sumwt = 0.0;
            double sumsqwt = 0.0;
            for (int i = lowerBound; i < lowerBound + k; i++)
            {
                if (IncludeTable(o, i))
                {
                    double a = o[i, 1];
                    double b = o[i, 2];
                    double c = o[i, 3];
                    double d = o[i, 4];
                    if (a <= 0.0 || b <= 0.0 || c <= 0.0 || d <= 0.0)
                        ContinuityCorrect(host, a, b, c, d, out a, out b, out c, out d);

                    double n = a + b + c + d;
                    // Weight = b * ( a + C ) / N; - unused
                    // using weight as 1/variance
                    svd1 = ((a + b) * (a + c) * (b + d) - a * b * n) / Math.Pow(n, 2.0);
                    svd2 = a * (b + d) / n;
                    svd3 = b * (a + c) / n;
                    double wt = 1.0 / (svd1 / (svd2 * svd3));
                    double lrri = Math.Log(a / (a + c) / (b / (b + d)));
                    qc += wt * Math.Pow(lrri - Math.Log(rmh), 2.0);
                    sumwt += wt;
                    sumsqwt += wt * wt;
                }
            }

            // DerSimonian-Laird random effects
            if (sumwt - sumsqwt / sumwt == 0.0)
                tausq = 0.0;
            else
                tausq = (qc - Convert.ToDouble(realk - 1)) / (sumwt - sumsqwt / sumwt);
            if (tausq < 0.0)
                tausq = 0.0;
            double wlrr = 0.0;
            sumwt = 0.0;
            // sumsqwt = 0.0; 
            for (int i = lowerBound; i < lowerBound + k; i++)
            {
                if (IncludeTable(o, i))
                {
                    double a = o[i, 1];
                    double b = o[i, 2];
                    double c = o[i, 3];
                    double d = o[i, 4];
                    if (a <= 0.0 || b <= 0.0 || c <= 0.0 || d <= 0.0)
                        ContinuityCorrect(host, a, b, c, d, out a, out b, out c, out d);
                    double n = a + b + c + d;
                    // using weight as 1/var
                    svd1 = ((a + b) * (a + c) * (b + d) - a * b * n) / Math.Pow(n, 2.0);
                    svd2 = a * (b + d) / n;
                    svd3 = b * (a + c) / n;
                    double wt = 1.0 / (svd1 / (svd2 * svd3));
                    double weight = 1.0 / (tausq + 1.0 / wt);
                    dsw[i] = weight;
                    double lrri = Math.Log(a / (a + c) / (b / (b + d)));
                    wlrr += lrri * weight;
                    sumwt += weight;
                }
            }
            dsrr = Math.Exp(wlrr / sumwt);
            dsx2 = Math.Pow(wlrr, 2.0) / sumwt;
            dsll = Math.Exp(wlrr / sumwt - cit / Math.Sqrt(sumwt));
            dsul = Math.Exp(wlrr / sumwt + cit / Math.Sqrt(sumwt));
            if (dsll > dsul)
                Utilities.Utilities.Swap(ref dsll, ref dsul);
            ierr = 0;
        }

        private static void Riskdifma(IPreferences host, int k, double[,] o, out double rmh, out double ll, out double ul, out double x2Rmh, double cit, double cco, double[] rkr, double[] rkw, double[] dsw, double[] rkrl, double[] rkru, double[] rkx, bool[] lerr, bool[] uerr, out double qc, out double dsrd, out double dsx2, out double dsll, out double dsul, out double tausq, bool[] cced, out int ierr)
        {
            ierr = -1;
            double sumlk = 0.0;
            double mhn = 0.0;
            double mhd = 0.0;
            for (int i = 1; i <= k; i++)
            {
                double a = o[i, 1];
                double b = o[i, 2];
                double c = o[i, 3];
                double d = o[i, 4];
                double n = a + b + c + d;
                rkx[i] = n;
                // rd and ci for stratum
                if (b + d <= 0.0 || a + c <= 0.0)
                {
                    rkr[i] = Constant.MISSING;
                    rkrl[i] = Constant.MISSING;
                    rkru[i] = Constant.MISSING;
                    lerr[i] = true;
                    uerr[i] = true;
                }
                else
                {
                    rkr[i] = a / (a + c) - b / (b + d);
                    if (host.Preferences.MetaExact)
                    {
                        double r1 = a;
                        double n1 = a + c;
                        double r2 = b;
                        double n2 = b + d;
                        MathDbl.uppci(Convert.ToInt32(r1), Convert.ToInt32(n1), Convert.ToInt32(r2), Convert.ToInt32(n2), out rkrl[i], out rkru[i], cit, 100.0 * cco);
                    }
                }
                //  rd across strata
                if (n <= 0)
                    throw new InvalidDataException();

                // standard weights - do this before continuity correction
                double nmn = (a + c) * (b + d) / n;
                rkw[i] = nmn;
                mhn += (a * (b + d) / n - b * (a + c) / n);
                mhd += nmn;
                if (a <= 0.0 || b <= 0.0 || c <= 0.0 || d <= 0.0)
                {
                    ContinuityCorrect(host, a, b, c, d, out a, out b, out c, out d);
                    n = a + b + c + d;
                    cced[i] = true;
                }
                else
                {
                    cced[i] = false;
                }
                //  Greenland-Robins pooled risk difference
                double lk = (a * c * Math.Pow(b + d, 3.0) + b * d * Math.Pow(a + c, 3.0)) / ((a + c) * (b + d) * Math.Pow(n, 2.0));
                sumlk += lk;
                // inverse variance weights
                // rkw(i) = 1# / vark
                if (!host.Preferences.MetaExact)
                {
                    double vark = a * c / Math.Pow(a + c, 3.0) + b * d / Math.Pow(b + d, 3.0);
                    double se = Math.Sqrt(vark);
                    rkrl[i] = rkr[i] - cit * se;
                    rkru[i] = rkr[i] + cit * se;
                }
                lerr[i] = rkrl[i] == Constant.MISSING;
                uerr[i] = rkru[i] == Constant.MISSING;
            }
            rmh = mhn / mhd;
            double serd = Math.Sqrt(sumlk / Math.Pow(mhd, 2.0));
            ll = rmh - serd * cit;
            ul = rmh + serd * cit;
            if (ll > ul)
                Utilities.Utilities.Swap(ref ll, ref ul);
            x2Rmh = Math.Pow(rmh / serd, 2.0);
            // Q (combinability)
            qc = 0.0;
            double sumwt = 0.0;
            double sumsqwt = 0.0;
            for (int i = 1; i <= k; i++)
            {
                double a = o[i, 1];
                double b = o[i, 2];
                double c = o[i, 3];
                double d = o[i, 4];
                // nmn = ( a + C ) * ( b + D ) / N; 
                double rkrs = a / (a + c) - b / (b + d);
                if (a <= 0.0 || b <= 0.0 || c <= 0.0 || d <= 0.0)
                    ContinuityCorrect(host, a, b, c, d, out a, out b, out c, out d);
                double vark = a * c / Math.Pow(a + c, 3.0) + b * d / Math.Pow(b + d, 3.0);
                double wt = 1.0 / vark;
                qc += wt * Math.Pow(rkrs - rmh, 2.0);
                sumwt += wt;
                sumsqwt += wt * wt;
            }
            // DerSimonian-Laird random effects
            if (sumwt - sumsqwt / sumwt == 0.0)
            {
                tausq = 0.0;
            }
            else
            {
                tausq = (qc - (k - 1.0)) / (sumwt - sumsqwt / sumwt);
            }
            if (tausq < 0.0)
            {
                tausq = 0.0;
            }
            double wrd = 0.0;
            sumwt = 0.0;
            // sumsqwt = 0.0; 
            for (int i = 1; i <= k; i++)
            {
                double a = o[i, 1];
                double b = o[i, 2];
                double c = o[i, 3];
                double d = o[i, 4];
                // nmn = ( ( a + C ) * ( b + D ) ) / N; 
                double rkrs = a / (a + c) - b / (b + d);
                if (a <= 0.0 || b <= 0.0 || c <= 0.0 || d <= 0.0)
                    ContinuityCorrect(host, a, b, c, d, out a, out b, out c, out d);
                double vark = a * c / Math.Pow(a + c, 3) + b * d / Math.Pow(b + d, 3);
                double wt = 1.0 / vark;
                double weight = 1.0 / (tausq + 1.0 / wt);
                dsw[i] = weight;
                wrd += rkrs * weight;
                sumwt += weight;
            }
            dsrd = wrd / sumwt;
            dsx2 = Math.Pow(wrd, 2.0) / sumwt;
            dsll = wrd / sumwt - cit / Math.Sqrt(sumwt);
            dsul = wrd / sumwt + cit / Math.Sqrt(sumwt);
            if (dsll > dsul)
                Utilities.Utilities.Swap(ref dsll, ref dsul);
            ierr = 0;
        }

        private enum MetaIncidenceRateMode
        {
            Difference = 1,
            Ratio = 2
        }

        public static StepOutput RptMetaIncidenceRateRatio(IPreferencesAndProgressBar host, ParameterBag parameters) => RptMetaIncidenceRate(host, parameters, MetaIncidenceRateMode.Ratio);

        public static StepOutput RptMetaIncidenceRateDifference(IPreferencesAndProgressBar host, ParameterBag parameters) => RptMetaIncidenceRate(host, parameters, MetaIncidenceRateMode.Difference);

        private static StepOutput RptMetaIncidenceRate(IPreferencesAndProgressBar host, ParameterBag parameters, MetaIncidenceRateMode mode)
        {
            double cco = parameters["gamma"].AsDouble;
            if (cco <= 0)
                cco = 0.95;
            double cit = PDF.gauinv(1.0 - (1.0 - cco) / 2.0);

            DataFrame aFrame = parameters["a"].AsDataFrame;
            DoubleVariable aVariable = (DoubleVariable)aFrame.Variables[0];
            DataFrame pt1Frame = parameters["pt1"].AsDataFrame;
            DoubleVariable pt1Variable = (DoubleVariable)pt1Frame.Variables[0];
            DataFrame bFrame = parameters["b"].AsDataFrame;
            DoubleVariable bVariable = (DoubleVariable)bFrame.Variables[0];
            DataFrame pt2Frame = parameters["pt2"].AsDataFrame;
            DoubleVariable pt2Variable = (DoubleVariable)pt2Frame.Variables[0];
            int rawRows = aVariable.Length;

            DoubleArraysAndBooleans copiesRemovingMissingRows = Numerics.Utilities.RemoveMissingRows(new[] { aVariable.Data, pt1Variable.Data, bVariable.Data, pt2Variable.Data }, 0, rawRows, 1);
            double[] a = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[0];
            double[] pt1 = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[1];
            double[] b = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[2];
            double[] pt2 = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[3];

            string[] title = MakeTitles(parameters, "strata", "stratum {0}", rawRows, out bool hasUserSuppliedLabels);

            int k = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[0].Length - 1; /* 1-based */
            title = Numerics.Utilities.CopyValidRows(title, copiesRemovingMissingRows.ValidRowsInOriginal, 0, rawRows, 1, k);

            double[,] o = new double[k + 1, 4 + 1];
            double[] rkr = new double[k + 1];
            double[] rkw = new double[k + 1];
            double[] dsw = new double[k + 1];
            double[] rkrl = new double[k + 1];
            double[] rkru = new double[k + 1];
            bool[] lerr = new bool[k + 1];
            bool[] uerr = new bool[k + 1];
            bool[] included = new bool[k + 1];
            double zrmh; double ul; double ll; double rmh;
            double dz; double dsird = 0; double dsirr = 0; double qc;
            double dsul; double dsll; double tausq;
            int ierr; double realk;

            if (mode == MetaIncidenceRateMode.Difference)
                IrdMeta(k, a, b, pt1, pt2, out rmh, out ll, out ul, out zrmh, ref cit, ref cco, rkr, rkw, dsw, rkrl, rkru, lerr, uerr, out qc, out dsird, out dz, out dsll, out dsul, out realk, out tausq, out ierr);
            else
                IrrMeta(k, a, b, pt1, pt2, out rmh, out ll, out ul, out zrmh, ref cit, ref cco, rkr, rkw, dsw, rkrl, rkru, lerr, uerr, out qc, out dsirr, out dz, out dsll, out dsul, out realk, out tausq, out ierr);
            if (ierr == -1)
                throw new InvalidDataException();

            double p2M = 0; double p1M = 0; double p2F = 0; double p1F = 0; double llm = 0; double ulm = 0; double llf = 0; double ulf = 0; double eor = 0;
            if (mode == MetaIncidenceRateMode.Ratio)
            {
                // Try exact IRR
                if (host.Preferences.MetaExact)
                {
                    Rec2X2[] tbl = new Rec2X2[k + 1];
                    for (int i = 1; i <= k; i++)
                    {
                        tbl[i].Freq = 1;
                        tbl[i].A = a[i];
                        tbl[i].M1 = b[i] + a[i];
                        tbl[i].N1 = pt1[i];
                        tbl[i].N0 = pt2[i];
                        tbl[i].IsInformative = (a[i] * pt1[i] != 0.0) | (b[i] * pt2[i] != 0.0);
                    }
                    bool useLogScale = false;
                    new ExactBB().Exact22K(host, 1, k, Exact22KDataType.Type1, tbl, cco, out eor, out ulf, out llf, out ulm, out llm, out p1F, out p2F, out p1M, out p2M, ref useLogScale, out ierr);
                }
                else
                {
                    ierr = -9;
                }
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
            }

            ParameterBag outputParameters = new();
            outputParameters.AddOutput("pc", cco * 100);

            IList<ParameterBag> inputsList = new List<ParameterBag>();
            outputParameters.AddOutput("*inputs", inputsList);
            for (int i = 1; i <= k; i++)
            {
                ParameterBag inputsParameters = new();
                inputsList.Add(inputsParameters);
                inputsParameters.AddOutput("st", i);
                inputsParameters.AddOutput("a", a[i]);
                inputsParameters.AddOutput("pt1", pt1[i]);
                inputsParameters.AddOutput("b", b[i]);
                inputsParameters.AddOutput("pt2", pt2[i]);
                inputsParameters.AddOutput("lb", hasUserSuppliedLabels ? title[i] : string.Empty);
            }

            IList<ParameterBag> irList = new List<ParameterBag>();
            outputParameters.AddOutput("*ir", irList);
            for (int i = 1; i <= k; i++)
            {
                ParameterBag irParameters = new();
                irList.Add(irParameters);
                irParameters.AddOutput("st", i);
                irParameters.AddOutput(mode == MetaIncidenceRateMode.Difference ? "ird" : "irr", rkr[i]);
                irParameters.AddOutput("lci", rkrl[i]);
                irParameters.AddOutput("uci", rkru[i]);
                irParameters.AddOutput("wt",
                    rkw[i] != Constant.MISSING
                        ? 100 * rkw[i] / Formatting.dsum(rkw, 1)
                        : Constant.MISSING);
                irParameters.AddOutput("dwt",
                    dsw[i] != Constant.MISSING
                        ? 100 * dsw[i] / Formatting.dsum(dsw, 1)
                        : Constant.MISSING);
                irParameters.AddOutput("lb", hasUserSuppliedLabels ? title[i] : string.Empty);
                if (mode == MetaIncidenceRateMode.Difference)
                {
                    irParameters.AddOutput("yi", rkr[i]);
                    irParameters.AddOutput("vi", VarianceFromCI(rkrl[i], rkru[i], cit, false));
                }
                else
                {
                    irParameters.AddOutput("yi", rkr[i] > 0 ? Math.Log(rkr[i]) : 0);
                    irParameters.AddOutput("vi", VarianceFromCI(rkrl[i], rkru[i], cit, true));
                }

            }
            outputParameters.AddOutput("rmh", rmh);
            outputParameters.AddOutput("from", ll);
            outputParameters.AddOutput("to", ul);
            outputParameters.AddOutput("z", zrmh);
            outputParameters.AddOutput("p_z", MathDbl.zvalp2(zrmh));
            if (mode == MetaIncidenceRateMode.Ratio)
            {
                if (ierr == -9)
                {
                    outputParameters.AddOutput("*poolok", null);
                }
                else
                {
                    IList<ParameterBag> poolokList = new List<ParameterBag>();
                    outputParameters.AddOutput("*poolok", poolokList);
                    ParameterBag poolokParameters = new();
                    poolokList.Add(poolokParameters);
                    poolokParameters.AddOutput("eor", eor);
                    poolokParameters.AddOutput("llf", llf);
                    poolokParameters.AddOutput("ulf", ulf);
                    poolokParameters.AddOutput("p1f", p1F);
                    poolokParameters.AddOutput("p2f", p2F);
                    poolokParameters.AddOutput("llm", llm);
                    poolokParameters.AddOutput("ulm", ulm);
                    poolokParameters.AddOutput("p1m", p1M);
                    poolokParameters.AddOutput("p2m", p2M);
                }
            }

            outputParameters.AddOutput("qc", qc);
            outputParameters.AddOutput("df", realk - 1);
            outputParameters.AddOutput("xp", PDF.chivalp(qc, realk - 1));
            outputParameters.AddOutput("tausq", tausq);
            // Call isquare(qc, k, cit, isq, llisq, ulisq)
            IsquareNcc(host, qc, k, cco, cit, out double isq, out double llisq, out double ulisq);
            outputParameters.AddOutput("isq", isq);
            outputParameters.AddOutput("pc1", cco * 100);
            outputParameters.AddOutput("llisq", llisq);
            outputParameters.AddOutput("ulisq", ulisq);

            if (mode == MetaIncidenceRateMode.Difference)
                outputParameters.AddOutput("dsird", dsird);
            else
                outputParameters.AddOutput("dsirr", dsirr);
            outputParameters.AddOutput("dsll", dsll);
            outputParameters.AddOutput("dsul", dsul);
            outputParameters.AddOutput("dz", dz);
            outputParameters.AddOutput("dp", MathDbl.zvalp2(dz));


            IList<ParameterBag> eggerList = new List<ParameterBag>();
            outputParameters.AddOutput("*egger", eggerList);
            ParameterBag eggerParameters = new();
            eggerList.Add(eggerParameters);
            Transformation xform = Transformation.None;
            if (mode != MetaIncidenceRateMode.Difference)
                xform = Transformation.Log;
            Metabias(host, eggerParameters, rkr, rkrl, rkru, k, ref cco, xform);

            double[] ptt = new double[k + 1];
            for (int i = 1; i <= k; i++)
            {
                o[i, 1] = pt1[i];
                o[i, 2] = pt2[i];
                o[i, 3] = pt1[i];
                o[i, 4] = pt2[i];
                included[i] = IncludeTable(o, i);
                if (pt2[i] == Constant.MISSING || pt1[i] == Constant.MISSING)
                    ptt[i] = Constant.MISSING;
                else
                    ptt[i] = pt1[i] + pt2[i];
            }

            IList<ParameterBag> chartList = new List<ParameterBag>();
            outputParameters.AddOutput("*chart", chartList);
            ParameterBag chartParameters;

            if (mode == MetaIncidenceRateMode.Difference)
            {
                if (k > 3)
                {
                    chartParameters = new ParameterBag();
                    chartList.Add(chartParameters);
                    chartParameters.AddOutput("chart", ChartRendererFactory.PrepForLater(ChartType.BiasMA, new BiasMAOptions(rkr, ptt, rkw, k, "Incidence rate difference", rkrl, rkru, cco, cit, rmh, Transformation.None, false)));
                }

                chartParameters = new ParameterBag();
                chartList.Add(chartParameters);
                chartParameters.AddOutput("chart", ChartRendererFactory.PrepForLater(ChartType.MHRD, new MHOptions(1, k, rkw, title, rmh, ll, ul, cco, rkr, rkrl, rkru, lerr, uerr, null, "Incidence rate difference meta-analysis plot [fixed effects]", 1, "incidence rate difference")));

                chartParameters = new ParameterBag();
                chartList.Add(chartParameters);
                chartParameters.AddOutput("chart", ChartRendererFactory.PrepForLater(ChartType.MHRD, new MHOptions(1, k, dsw, title, dsird, dsll, dsul, cco, rkr, rkrl, rkru, lerr, uerr, null, "Incidence rate difference meta-analysis plot [random effects]", 1, "incidence rate difference")));
            }
            else
            {
                if (k > 3)
                {
                    chartParameters = new ParameterBag();
                    chartList.Add(chartParameters);
                    chartParameters.AddOutput("chart", ChartRendererFactory.PrepForLater(ChartType.BiasMA, new BiasMAOptions(rkr, ptt, rkw, k, "Incidence rate ratio", rkrl, rkru, cco, cit, rmh, Transformation.Log, false)));
                }

                chartParameters = new ParameterBag();
                chartList.Add(chartParameters);
                chartParameters.AddOutput("chart", ChartRendererFactory.PrepForLater(ChartType.MH, new MHOptions(1, k, rkw, title, rmh, ll, ul, cco, rkr, rkrl, rkru, lerr, uerr, included, "Incidence rate ratio meta-analysis plot [fixed effects]", 1, "incidence rate ratio")));

                chartParameters = new ParameterBag();
                chartList.Add(chartParameters);
                chartParameters.AddOutput("chart", ChartRendererFactory.PrepForLater(ChartType.MH, new MHOptions(1, k, dsw, title, dsirr, dsll, dsul, cco, rkr, rkrl, rkru, lerr, uerr, included, "Incidence rate ratio meta-analysis plot [random effects]", 1, "incidence rate ratio")));
            }
            return new StepOutput(outputParameters);
        }
        public static StepOutput RptMantel(IPreferencesAndProgressBar host, ParameterBag parameters)
        {
            double p2M = 0; double p1M = 0;
            double p2F = 0; double p1F = 0; double llm = 0; double ulm = 0; double llf = 0; double ulf = 0; double eor = 0;

            double cco = parameters["gamma"].AsDouble;
            if (cco <= 0)
                cco = 0.95;
            double cit = PDF.gauinv(1.0 - (1.0 - cco) / 2.0);

            DataFrame snFrame = parameters["sn"].AsDataFrame;
            DoubleVariable snVariable = (DoubleVariable)snFrame.Variables[0];
            DataFrame srFrame = parameters["sr"].AsDataFrame;
            DoubleVariable srVariable = (DoubleVariable)srFrame.Variables[0];
            DataFrame xnFrame = parameters["xn"].AsDataFrame;
            DoubleVariable xnVariable = (DoubleVariable)xnFrame.Variables[0];
            DataFrame xrFrame = parameters["xr"].AsDataFrame;
            DoubleVariable xrVariable = (DoubleVariable)xrFrame.Variables[0];
            int rawRows = snVariable.Length;

            DoubleArraysAndBooleans copiesRemovingMissingRows = Numerics.Utilities.RemoveMissingRows(new[] { snVariable.Data, srVariable.Data, xnVariable.Data, xrVariable.Data }, 0, rawRows, 1);
            double[] sn = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[0];
            double[] sr = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[1];
            double[] xn = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[2];
            double[] xr = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[3];

            string[] title = MakeTitles(parameters, "strata", "stratum {0}", rawRows, out bool hasUserSuppliedLabels);

            int k = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[0].Length - 1; /* 1-based */
            title = Numerics.Utilities.CopyValidRows(title, copiesRemovingMissingRows.ValidRowsInOriginal, 0, rawRows, 1, k);

            double[,] o = new double[k + 1, 4 + 1];
            double[] axll = new double[k + 1];
            double[] axul = new double[k + 1];
            for (int i = 1; i <= k; i++)
            {
                o[i, 1] = Math.Abs(sr[i]);
                o[i, 3] = Math.Abs(sn[i] - sr[i]);
                if (sr[i] < 0 | sn[i] < 0 | sn[i] < sr[i])
                    throw new InvalidDataException();
                o[i, 2] = Math.Abs(xr[i]);
                o[i, 4] = Math.Abs(xn[i] - xr[i]);
                if (xr[i] < 0.0 | xn[i] < 0.0 | xn[i] < xr[i])
                    throw new InvalidDataException();
            }

            Mantel(host, 1, k, out int realk, o, out double rmh, out double ll, out double ul, out double x2, out double sk, cit, cco, out double[] odr, out double[] odw, out double[] dswt, out double[] odrl, out double[] odru, out double[] odx, out bool[] lerr, out bool[] uerr, out double qc, out double bd, out double dsor, out double dsx2, out double dsll, out double dsul, out bool[] cced, out double tausq, out bool[] included, out int ierr);
            if (ierr != 0)
            {
                if (ierr != 99)
                    throw new InvalidDataException();
                throw new TemplateOperationCancelledException();
            }

            // Try exact Mantel
            if (host.Preferences.MetaExact)
            {
                Rec2X2[] tbl = new Rec2X2[k + 1];
                for (int i = 1; i <= k; i++)
                {
                    tbl[i].Freq = 1;
                    tbl[i].A = o[i, 1];
                    tbl[i].M1 = o[i, 1] + o[i, 2];
                    tbl[i].N1 = o[i, 1] + o[i, 3];
                    tbl[i].N0 = o[i, 2] + o[i, 4];
                    tbl[i].IsInformative = (o[i, 1] * o[i, 4] != 0.0) | (o[i, 2] * o[i, 3] != 0.0);
                }
                bool useLogScale = false;
                new ExactBB().Exact22K(host, 1, k, Exact22KDataType.Type1, tbl, cco, out eor, out ulf, out llf, out ulm, out llm, out p1F, out p2F, out p1M, out p2M, ref useLogScale, out ierr);
            }
            else
            {
                ierr = -9;
            }
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
            outputParameters.AddOutput("pc", cco * 100);

            IList<ParameterBag> inputsList = new List<ParameterBag>();
            outputParameters.AddOutput("*inputs", inputsList);
            for (int i = 1; i <= k; i++)
            {
                ParameterBag inputsParameters = new();
                inputsList.Add(inputsParameters);
                inputsParameters.AddOutput("st", i);
                inputsParameters.AddOutput("a", o[i, 1]);
                inputsParameters.AddOutput("b", o[i, 2]);
                inputsParameters.AddOutput("c", o[i, 3]);
                inputsParameters.AddOutput("d", o[i, 4]);
                inputsParameters.AddOutput("lb", hasUserSuppliedLabels ? title[i] : string.Empty);
            }

            outputParameters.AddOutput("method", host.Preferences.MetaExact ? "CML" : "logit");

            IList<ParameterBag> orList = new List<ParameterBag>();
            outputParameters.AddOutput("*or", orList);
            for (int i = 1; i <= k; i++)
            {
                ParameterBag orParameters = new();
                orList.Add(orParameters);
                orParameters.AddOutput("st", i);
                orParameters.AddOutput("or", odr[i]);
                orParameters.AddOutput("yi", odr[i] > 0 ? Math.Log(odr[i]) : 0);
                orParameters.AddOutput("vi", VarianceFromCI(odrl[i], odru[i], cit, true));
                orParameters.AddOutput("lci", odrl[i]);
                orParameters.AddOutput("uci", odru[i]);
                orParameters.AddOutput("wt", 100 * odw[i] / Formatting.dsum(odw, 1));
                orParameters.AddOutput("dwt", 100 * dswt[i] / Formatting.dsum(dswt, 1));
                string tmp = GetMetaLabel(host, o, i, hasUserSuppliedLabels, cced, title);
                if (host.Preferences.DelayContinuityCorrection)
                    tmp = tmp.Replace("[CC", "[late CC");
                orParameters.AddOutput("lb", tmp);
                //if (host.Preferences.MetaExact & ((i) == Constant.MISSING || odru[i] == Constant.MISSING))
                //{
                //    OrciCorn(host, ref cco, ref o[i, 1], ref o[i, 2], ref o[i, 3], ref o[i, 4], out odr[i], out odrl[i], out odru[i]);
                //    orParameters = new ParameterBag();
                //    orList.Add(orParameters);
                //    orParameters.AddOutput("st", "* " + i.ToString());
                //    orParameters.AddOutput("or", string.Empty);
                //    orParameters.AddOutput("standardized_effect", string.Empty);
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

            IList<ParameterBag> cmlList = new List<ParameterBag>();
            outputParameters.AddOutput("*cml", cmlList);
            if (ierr != -9)
            {
                ParameterBag cmlParameters = new();
                cmlList.Add(cmlParameters);
                cmlParameters.AddOutput("eor", eor);
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

            IsquareNcc(host, qc, realk, cco, cit, out double isq, out double llisq, out double ulisq);
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

            GetLogitCi(host, o, k, cit, axll, axul);

            IList<ParameterBag> eggerList = new List<ParameterBag>();
            outputParameters.AddOutput("*egger", eggerList);
            ParameterBag eggerParameters = new();
            eggerList.Add(eggerParameters);
            Metabias(host, eggerParameters, odr, axll, axul, k, ref cco, Transformation.Log);

            IList<ParameterBag> harbordList = new List<ParameterBag>();
            outputParameters.AddOutput("*harbord", harbordList);
            ParameterBag harbordParameters = new();
            harbordList.Add(harbordParameters);
            ModMetabias(host, harbordParameters, o, k, cco, 1);

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
            return new StepOutput(outputParameters);
        }

        public static void Mantel(IPreferencesAndProgressBar host, int lowerBound, int k, out int realk, double[,] o, out double rmh, out double ll, out double ul, out double x2, out double sk, double cit, double cco, out double[] odr, out double[] odw, out double[] dswt, out double[] odrl, out double[] odru, out double[] odx, out bool[] lerr, out bool[] uerr, out double qc, out double bd, out double dsor, out double dsx2, out double dsll, out double dsul, out bool[] cced, out double tausq, out bool[] included, out int ierr)
        {
            odr = new double[k + lowerBound];
            odrl = new double[k + lowerBound];
            odru = new double[k + lowerBound];
            odw = new double[k + lowerBound];
            dswt = new double[k + lowerBound];
            odx = new double[k + lowerBound];
            lerr = new bool[k + lowerBound];
            uerr = new bool[k + lowerBound];
            cced = new bool[k + lowerBound];
            included = new bool[k + lowerBound];

            ierr = -1;
            double eai = 0.0;
            double vari = 0.0;
            double rk = 0.0;
            sk = 0.0;
            double w = 0.0;
            double svd1 = 0.0;
            double svd2 = 0.0;
            double svd3 = 0.0;
            double sumwt = 0.0;
            realk = 0;

            bool rkok = false;
            for (int i = lowerBound; i < k + lowerBound; i++)
                if (o[i, 1] * o[i, 4] != 0.0)
                    rkok = true;

            for (int i = lowerBound; i < k + lowerBound; i++)
            {
                double a = o[i, 1];
                double b = o[i, 2];
                double c = o[i, 3];
                double d = o[i, 4];
                double n = a + b + c + d;
                odx[i] = n;
                if (n <= 0)
                    throw new InvalidDataException();

                if (!host.Preferences.DelayContinuityCorrection)
                    rkok = false;

                // MH across strata
                included[i] = IncludeTable(o, i);
                if (included[i])
                {
                    // only do cc at this stage if absolutely necessary (all a or all d cells zero)
                    if (!rkok)
                    {
                        if (a <= 0 || b <= 0 || c <= 0 || d <= 0)
                        {
                            ContinuityCorrect(host, a, b, c, d, out a, out b, out c, out d);
                            n = a + b + c + d;
                            cced[i] = true;
                        }
                        else
                        {
                            cced[i] = false;
                        }
                    }
                    realk += 1;
                    eai = eai + a - (a + c) * (a + b) / n;
                    vari += (a + c) * (b + d) * (a + b) * (c + d) / (Math.Pow(n, 2.0) * (n - 1.0));
                    double rr = a * d / n;
                    double ss = b * c / n;
                    double pp = (a + d) / n;
                    double qq = (b + c) / n;
                    w = w + (qq + 1.0 / n) * rr + (pp + 1.0 / n) * ss;
                    rk += rr;
                    sk += ss;
                    svd1 += pp * rr;
                    svd2 += (qq * rr + pp * ss);
                    svd3 += qq * ss;
                    double weight = b * c / n;
                    odw[i] = weight;
                    sumwt += weight;
                }

                if (!included[i])
                {
                    odr[i] = 0;
                    odrl[i] = 0;
                    odru[i] = double.PositiveInfinity;
                    lerr[i] = false;
                    uerr[i] = false;
                }
                else
                {
                    if (rkok)
                    {
                        // do cc if not done earlier
                        if (a <= 0 || b <= 0 || c <= 0 || d <= 0)
                        {
                            ContinuityCorrect(host, a, b, c, d, out a, out b, out c, out d);
                            // N = a + b + C + D; 
                            cced[i] = true;
                        }
                        else
                        {
                            cced[i] = false;
                        }
                    }
                    odr[i] = a * d / (b * c);
                    if (host.Preferences.MetaExact)
                    {
                        OddsRatioCI(host, cco, a, b, c, d, out double _, out odrl[i], out odru[i], out lerr[i], out uerr[i]);
                    }
                    else
                    {
                        // go for horrid logit se if you must
                        double se = Math.Sqrt(1.0 / a + 1.0 / b + 1.0 / c + 1.0 / d);
                        odrl[i] = Math.Exp(Math.Log(odr[i]) - cit * se);
                        odru[i] = Math.Exp(Math.Log(odr[i]) + cit * se);
                        lerr[i] = false;
                        uerr[i] = false;
                    }
                }
            }

            if (sk == 0)
            {
                // SATO T. BIOMETRICS 46 71-80
                rmh = Constant.MISSING;
                double sq = Math.Sqrt((4.0 * rk * sk + cit * cit * w) * cit * cit * w);
                // ll = ( 2.0 * rk * sk + cit * cit * w - sq ) / 2.0 / rk / rk; 
                ul = (2.0 * rk * sk + cit * cit * w + sq) / 2.0 / rk / rk;
                ll = Math.Exp(1.0 / ul);
                ul = Constant.MISSING;
            }
            else
            {
                rmh = rk / sk;
                //  RBG
                double vrbg = svd1 / 2.0 / rk / rk + svd2 / 2.0 / rk / sk + svd3 / 2.0 / sk / sk;
                ll = Math.Exp(Math.Log(rk / sk) - Math.Sqrt(cit * cit * vrbg));
                ul = Math.Exp(Math.Log(rk / sk) + Math.Sqrt(cit * cit * vrbg));
            }
            if (ll > ul)
                Utilities.Utilities.Swap(ref ll, ref ul);
            x2 = Math.Pow(Math.Abs(eai) - 0.5, 2.0) / vari;

            // Q (combinability)
            qc = 0.0;
            bd = 0.0;
            double wlor = 0.0;
            sumwt = 0.0;
            double sumsqwt = 0.0;
            for (int i = lowerBound; i < k + lowerBound; i++)
            {
                double a = o[i, 1];
                double b = o[i, 2];
                double c = o[i, 3];
                double d = o[i, 4];
                // Breslow-Day - must do it before continuity correction -->
                double n1 = a + b;
                double n0 = c + d;
                double m1 = a + c;
                double m2 = b + d;
                if (n1 != 0 && n0 != 0 && m1 != 0 && m2 != 0)
                {
                    // quadratic coefficients ax² + bx + c = 0
                    double qda = 1.0 - rmh;
                    double qdb = m2 - n1 + (m1 + n1) * rmh;
                    double qdc = -m1 * n1 * rmh;
                    double ea = (-qdb + Math.Sqrt(Math.Pow(qdb, 2.0) - 4.0 * qda * qdc)) / (2.0 * qda);
                    // give the rest of the expected table e.g. Breslow & Day P 144
                    double varea = 1.0 / (1.0 / ea + 1.0 / (n1 - ea) + 1.0 / (m1 - ea) + 1.0 / (n0 - m1 + ea));
                    bd += (a - ea) * (a - ea) / varea;
                }
                // <--
                if (included[i])
                {
                    if (a <= 0 || b <= 0 || c <= 0 || d <= 0)
                        ContinuityCorrect(host, a, b, c, d, out a, out b, out c, out d);
                    double n = a + b + c + d;
                    double rr = a * d / n;
                    double ss = b * c / n;
                    double pp = (a + d) / n;
                    double qq = (b + c) / n;
                    svd1 = pp * rr;
                    svd2 = qq * rr + pp * ss;
                    svd3 = qq * ss;
                    double vrbgi = svd1 / 2.0 / rr / rr + svd2 / 2.0 / rr / ss + svd3 / 2.0 / ss / ss;
                    double weight = 1.0 / vrbgi;
                    double lori = Math.Log(a * d / (b * c));
                    qc += weight * Math.Pow(lori - Math.Log(rmh), 2.0);
                    wlor += lori * weight;
                    sumwt += weight;
                    sumsqwt += weight * weight;
                }
            }
            // DerSimonian-Laird
            if (sumwt * sumwt - sumsqwt == 0.0)
                tausq = 0.0;
            else
                tausq = (qc - (realk - 1)) * sumwt / (sumwt * sumwt - sumsqwt);
            if (tausq < 0.0)
                tausq = 0.0;
            wlor = 0.0;
            sumwt = 0.0;
            for (int i = lowerBound; i < k + lowerBound; i++)
            {
                double a = o[i, 1];
                double b = o[i, 2];
                double c = o[i, 3];
                double d = o[i, 4];
                if (included[i])
                {
                    if (a <= 0.0 || b <= 0.0 || c <= 0.0 || d <= 0.0)
                        ContinuityCorrect(host, a, b, c, d, out a, out b, out c, out d);
                    double n = a + b + c + d;
                    double rr = a * d / n;
                    double ss = b * c / n;
                    double pp = (a + d) / n;
                    double qq = (b + c) / n;
                    svd1 = pp * rr;
                    svd2 = qq * rr + pp * ss;
                    svd3 = qq * ss;
                    double vrbgi = svd1 / 2.0 / rr / rr + svd2 / 2.0 / rr / ss + svd3 / 2.0 / ss / ss;
                    double weight = 1.0 / (tausq + vrbgi);
                    dswt[i] = weight;
                    double lori = Math.Log(a * d / (b * c));
                    wlor += lori * weight;
                    sumwt += weight;
                }
            }
            dsor = Math.Exp(wlor / sumwt);
            dsx2 = Math.Pow(wlor, 2.0) / sumwt;
            dsll = Math.Exp(wlor / sumwt - cit / Math.Sqrt(sumwt));
            dsul = Math.Exp(wlor / sumwt + cit / Math.Sqrt(sumwt));
            if (dsll > dsul)
                Utilities.Utilities.Swap(ref dsll, ref dsul);
            ierr = 0;
        }

        public static void GetLogitCi(IPreferences host, double[,] o, int k, double cit, double[] axll, double[] axul)
        {
            for (int i = 1; i <= k; i++)
            {
                double a = o[i, 1];
                double b = o[i, 2];
                double c = o[i, 3];
                double d = o[i, 4];
                // double N = a + b + C + D; 
                if (IncludeTable(o, i) == false)
                {
                    axll[i] = 0;
                    axul[i] = double.PositiveInfinity;
                }
                else
                {
                    if (a <= 0.0 || b <= 0.0 || c <= 0.0 || d <= 0.0)
                    {
                        ContinuityCorrect(host, a, b, c, d, out a, out b, out c, out d);
                        // N = a + b + C + D; 
                    }
                    double odr = a * d / (b * c);
                    double se = Math.Sqrt(1.0 / a + 1.0 / b + 1.0 / c + 1.0 / d);
                    axll[i] = Math.Exp(Math.Log(odr) - cit * se);
                    axul[i] = Math.Exp(Math.Log(odr) + cit * se);
                }
            }
        }

        public static void GetAproxrrCI(IPreferences host, double[,] o, int k, double cit, double[] axll, double[] axul)
        {
            for (int i = 1; i <= k; i++)
            {
                double a = o[i, 1];
                double b = o[i, 2];
                double c = o[i, 3];
                double d = o[i, 4];
                if (IncludeTable(o, i))
                {
                    if (a <= 0.0 || b <= 0.0 || c <= 0.0 || d <= 0.0)
                        ContinuityCorrect(host, a, b, c, d, out a, out b, out c, out d);
                    double rkr = a / (a + c) / (b / (b + d));
                    // approximate se of log rr
                    double se = Math.Sqrt(1.0 / a + 1.0 / b - 1.0 / (a + c) - 1.0 / (b + d));
                    axll[i] = Math.Exp(Math.Log(rkr) - se * cit);
                    axul[i] = Math.Exp(Math.Log(rkr) + se * cit);
                }
            }
        }

        private static void IrdMeta(int k, double[] a, double[] b, double[] pt1, double[] pt2, out double rmh, out double ll, out double ul, out double zrmh, ref double cit, ref double cco, double[] rkr, double[] rkw, double[] dsw, double[] rkrl, double[] rkru, bool[] lerr, bool[] uerr, out double qc, out double dsrd, out double dz, out double dsll, out double dsul, out double realk, out double tausq, out int ierr)
        {
            double sumwt = 0.0;
            double sumwi = 0.0;
            realk = 0.0;
            for (int i = 1; i <= k; i++)
            {
                // ird and ci for stratum
                double pt = pt1[i] + pt2[i];
                double m = a[i] + b[i];
                if (a[i] + b[i] <= 0.0 || pt1[i] <= 0.0 || pt2[i] <= 0.0)
                {
                    rkr[i] = Constant.MISSING;
                    rkw[i] = Constant.MISSING;
                    rkrl[i] = Constant.MISSING;
                    rkru[i] = Constant.MISSING;
                    lerr[i] = true;
                    uerr[i] = true;
                }
                else
                {
                    realk += 1.0;
                    double ir1 = a[i] / pt1[i];
                    double ir2 = b[i] / pt2[i];
                    double ird = ir1 - ir2;
                    double xmh = (a[i] - m * pt1[i] / pt) * (a[i] - m * pt1[i] / pt) / (m * pt1[i] * pt2[i] / (pt * pt));
                    if (xmh == 0)
                    {
                        rkrl[i] = Constant.MISSING;
                        lerr[i] = true;
                    }
                    else
                    {
                        rkrl[i] = ird - cit * Math.Sqrt(ird * ird / xmh);
                    }
                    if (xmh == 0)
                    {
                        rkru[i] = Constant.MISSING;
                        uerr[i] = true;
                    }
                    else
                    {
                        rkru[i] = ird + cit * Math.Sqrt(ird * ird / xmh);
                    }
                    rkr[i] = ird;
                    //  pooled incidence risk difference
                    double vark = a[i] / (pt1[i] * pt1[i]) + b[i] / (pt2[i] * pt2[i]);
                    rkw[i] = 1.0 / vark;
                    sumwt += rkw[i];
                    sumwi += rkw[i] * ird;
                }
            }
            rmh = sumwi / sumwt;
            double se = Math.Sqrt(1.0 / sumwt);
            ll = rmh - se * cit;
            ul = rmh + se * cit;
            if (ll > ul)
            {
                double t = ll;
                ll = ul;
                ul = t;
            }
            zrmh = rmh / se;

            // Q (combinability)
            qc = 0.0;
            sumwt = 0.0;
            double sumsqwt = 0.0;
            for (int i = 1; i <= k; i++)
            {
                if (rkw[i] != Constant.MISSING)
                {
                    qc += rkw[i] * Math.Pow(rkr[i] - rmh, 2.0);
                    sumwt += rkw[i];
                    sumsqwt += rkw[i] * rkw[i];
                }
            }

            // DerSimonian-Laird random effects
            if (sumwt - sumsqwt / sumwt == 0.0)
                tausq = 0.0;
            else
                tausq = (qc - (realk - 1.0)) / (sumwt - sumsqwt / sumwt);
            if (tausq < 0.0)
                tausq = 0.0;
            double wrd = 0.0;
            sumwt = 0.0;
            // sumsqwt = 0.0; - unused
            for (int i = 1; i <= k; i++)
            {
                if (rkw[i] != Constant.MISSING)
                {
                    double weight = 1.0 / (tausq + 1.0 / rkw[i]);
                    dsw[i] = weight;
                    wrd += rkr[i] * weight;
                    sumwt += weight;
                }
                else
                {
                    dsw[i] = Constant.MISSING;
                }
            }
            dsrd = wrd / sumwt;
            dz = wrd / Math.Sqrt(sumwt);
            dsll = wrd / sumwt - cit / Math.Sqrt(sumwt);
            dsul = wrd / sumwt + cit / Math.Sqrt(sumwt);
            if (dsll > dsul)
            {
                double t = dsll;
                dsll = dsul;
                dsul = t;
            }
            ierr = 0;
        }

        private static void IrrMeta(int k, double[] a, double[] b, double[] pt1, double[] pt2, out double rmh, out double ll, out double ul, out double zrmh, ref double cit, ref double cco, double[] rkr, double[] rkw, double[] dsw, double[] rkrl, double[] rkru, bool[] lerr, bool[] uerr, out double qc, out double dsirr, out double dz, out double dsll, out double dsul, out double realk, out double tausq, out int ierr)
        {
            double sumwt = 0.0;
            double sumwi = 0.0;
            realk = 0.0;
            for (int i = 1; i <= k; i++)
            {
                // irr and ci for stratum
                if (a[i] + b[i] <= 0.0 || b[i] <= 0.0 || pt1[i] <= 0.0 || pt2[i] <= 0.0)
                {
                    rkr[i] = Constant.MISSING;
                    rkw[i] = Constant.MISSING;
                    rkrl[i] = Constant.MISSING;
                    rkru[i] = Constant.MISSING;
                    lerr[i] = true;
                    uerr[i] = true;
                }
                else
                {
                    realk += 1.0;
                    double ir1 = a[i] / pt1[i];
                    double ir2 = b[i] / pt2[i];
                    double p = cco + (1.0 - cco) / 2.0;
                    double f;
                    if (a[i] == 0.0)
                    {
                        rkrl[i] = 0.0;
                    }
                    else
                    {
                        f = PDF.ffromp(2.0 * a[i], 2.0 * (b[i] + 1.0), 1.0 - p);
                        rkrl[i] = pt2[i] / pt1[i] * (a[i] / (b[i] + 1.0)) * (1.0 / f);
                    }
                    if (b[i] == 0.0)
                    {
                        rkru[i] = Constant.MISSING;
                        rkr[i] = Constant.MISSING;
                    }
                    else
                    {
                        f = PDF.ffromp(2.0 * b[i], 2.0 * (a[i] + 1.0), 1.0 - p);
                        rkru[i] = pt2[i] / pt1[i] * ((a[i] + 1.0) / b[i]) * f;
                        rkr[i] = ir1 / ir2;
                    }
                    // pooled incidence rate ratio
                    // vark = 1# / a(i) + 1# / b(i) - as expressed in Lau paper on AZT
                    rkw[i] = a[i] * b[i] / (a[i] + b[i]);
                    sumwt += rkw[i];
                    if (rkr[i] > 0)
                        sumwi += rkw[i] * Math.Log(rkr[i]);
                }
            }
            rmh = Math.Exp(sumwi / sumwt);
            double se = Math.Sqrt(1.0 / sumwt);
            ll = Math.Exp(Math.Log(rmh) - se * cit);
            ul = Math.Exp(Math.Log(rmh) + se * cit);
            if (ll > ul)
            {
                double t = ll;
                ll = ul;
                ul = t;
            }
            zrmh = Math.Log(rmh) / se;
            // Q (combinability)
            qc = 0.0;
            sumwt = 0.0;
            double sumsqwt = 0.0;
            for (int i = 1; i <= k; i++)
            {
                if (rkw[i] != Constant.MISSING)
                {
                    if (rkr[i] > 0)
                        qc += rkw[i] * Math.Pow(Math.Log(rkr[i]) - Math.Log(rmh), 2.0);
                    sumwt += rkw[i];
                    sumsqwt += rkw[i] * rkw[i];
                }
            }
            // DerSimonian-Laird random effects
            if (sumwt - sumsqwt / sumwt == 0.0)
                tausq = 0.0;
            else
                tausq = (qc - (realk - 1.0)) / (sumwt - sumsqwt / sumwt);
            if (tausq < 0.0)
                tausq = 0.0;
            double wrd = 0.0;
            sumwt = 0.0;
            // sumsqwt = 0.0; - unused
            for (int i = 1; i <= k; i++)
            {
                if (rkw[i] != Constant.MISSING)
                {
                    double weight = 1.0 / (tausq + 1.0 / rkw[i]);
                    dsw[i] = weight;
                    if (rkr[i] > 0)
                        wrd += Math.Log(rkr[i]) * weight;
                    sumwt += weight;
                }
                else
                {
                    dsw[i] = Constant.MISSING;
                }
            }
            dsirr = Math.Exp(wrd / sumwt);
            dz = wrd / Math.Sqrt(sumwt);
            dsll = Math.Exp(wrd / sumwt - cit / Math.Sqrt(sumwt));
            dsul = Math.Exp(wrd / sumwt + cit / Math.Sqrt(sumwt));
            if (dsll > dsul)
            {
                double t = dsll;
                dsll = dsul;
                dsul = t;
            }
            ierr = 0;
        }

        public static StepOutput RptMetaSummary(IPreferencesAndProgressBar host, ParameterBag parameters)
        {
            double dsul; double dsll; double dsrr;
            double tausq;
            double zrmh; double ulrmh; double llrmh;
            double[] odx = null;

            double cco = parameters["gamma"].AsDouble;
            if (cco <= 0)
                cco = 0.95;
            double cit = PDF.gauinv(1.0 - (1.0 - cco) / 2.0);

            string statx = parameters["statx"].AsString;
            bool useRatio = parameters["use_ratio"].AsBoolean;
            string stat = parameters["stat_in"].AsString;
            bool useCI = "true".Equals(parameters["use_ci"].AsString.ToLower(CultureInfo.InvariantCulture));

            DataFrame yFrame = parameters["y"].AsDataFrame;
            DoubleVariable yVariable = (DoubleVariable)yFrame.Variables[0];
            double[] y = yVariable.Data;

            int rawRows = y.Length;

            double[] llY;
            double[] ulY;
            double[] seY;
            if (useCI)
            {
                DataFrame llYFrame = parameters["ll_y"].AsDataFrame;
                DoubleVariable llYVariable = (DoubleVariable)llYFrame.Variables[0];
                llY = llYVariable.Data;

                DataFrame ulYFrame = parameters["ul_y"].AsDataFrame;
                DoubleVariable ulYVariable = (DoubleVariable)ulYFrame.Variables[0];
                ulY = ulYVariable.Data;

                seY = new double[rawRows];

                for (int i = 0; i < rawRows; i++)
                {
                    if (llY[i] == Constant.MISSING)
                        llY[i] = 0.0;
                    if (ulY[i] == Constant.MISSING && useRatio)
                        ulY[i] = 1.0;
                    if (llY[i] > ulY[i])
                        Utilities.Utilities.Swap(ref llY[i], ref ulY[i]);
                    if (useRatio)
                        seY[i] = (Math.Log(ulY[i]) - Math.Log(llY[i])) / 2.0 / cit;
                    else
                        seY[i] = (ulY[i] - llY[i]) / 2.0 / cit;
                }
            }
            else
            {
                DataFrame seYFrame = parameters["se_y"].AsDataFrame;
                DoubleVariable seYVariable = (DoubleVariable)seYFrame.Variables[0];
                seY = seYVariable.Data;

                llY = new double[rawRows];
                ulY = new double[rawRows];

                for (int i = 0; i < rawRows; i++)
                {
                    if (useRatio)
                    {
                        llY[i] = Math.Exp(Math.Log(y[i]) - cit * seY[i]);
                        ulY[i] = Math.Exp(Math.Log(y[i]) + cit * seY[i]);
                    }
                    else
                    {
                        llY[i] = y[i] - cit * seY[i];
                        ulY[i] = y[i] + cit * seY[i];
                    }
                }
            }

            DoubleArraysAndBooleans copiesRemovingMissingRows = Numerics.Utilities.RemoveMissingRows(new[] { y, llY, ulY, seY }, 0, rawRows, 1, 1);
            y = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[0];
            llY = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[1];
            ulY = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[2];
            seY = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[3];
            int k = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[0].Length - 2; /* 1-based, spare at end */

            // Pooling
            CorrelationRowType[] pg = new CorrelationRowType[k + 2];
            for (int i = 1; i <= k; i++)
                pg[i] = CorrelationRowType.Study;
            // pooled indicator for last element - needed by plot_cp
            pg[k + 1] = CorrelationRowType.Pooled;

            string[] title = MakeTitles(parameters, "studies", "study {0}", rawRows, out bool hasUserSuppliedLabels);
            title = Numerics.Utilities.CopyValidRows(title, copiesRemovingMissingRows.ValidRowsInOriginal, 0, rawRows, 1, k, 1);
            title[k + 1] = Charting.Renderer.AbstractForestishChartRenderer.ComboTi(string.Empty);

            // Pool
            double sumwt = 0.0;
            double sumsqwt = 0.0;
            double sumywt = 0.0;
            double[] wt = new double[k + 2];
            double[] dswt = new double[k + 2];
            for (int i = 1; i <= k; i++)
            {
                if (seY[i] == 0.0)
                    throw new InvalidDataException();
                wt[i] = 1.0 / (seY[i] * seY[i]);
                sumwt += wt[i];
                sumsqwt += wt[i] * wt[i];
                if (useRatio)
                    sumywt += Math.Log(y[i]) * wt[i];
                else
                    sumywt += y[i] * wt[i];
            }
            wt[k + 1] = Constant.MISSING;
            dswt[k + 1] = Constant.MISSING;
            double rmh = useRatio ? Math.Exp(sumywt / sumwt) : sumywt / sumwt;
            double sermh = Math.Pow(sumwt, -0.5);
            if (useRatio)
            {
                llrmh = Math.Exp(Math.Log(rmh) - sermh * cit);
                ulrmh = Math.Exp(Math.Log(rmh) + sermh * cit);
                if (llrmh > ulrmh)
                    Utilities.Utilities.Swap(ref llrmh, ref ulrmh);
                zrmh = Math.Log(rmh) / sermh;
            }
            else
            {
                llrmh = rmh - sermh * cit;
                ulrmh = rmh + sermh * cit;
                zrmh = rmh / sermh;
            }

            // Q (combinability)
            double qc = 0.0;
            for (int i = 1; i <= k; i++)
            {
                if (useRatio)
                    qc += wt[i] * Math.Pow(Math.Log(y[i]) - Math.Log(rmh), 2.0);
                else
                    qc += wt[i] * Math.Pow(y[i] - rmh, 2.0);
            }

            // DerSimonian-Laird random effects
            if (sumwt - sumsqwt / sumwt == 0.0)
                tausq = 0.0;
            else
                tausq = (qc - Convert.ToDouble(k - 1)) / (sumwt - sumsqwt / sumwt);
            if (tausq < 0.0)
                tausq = 0.0;
            double wlrr = 0.0;
            sumwt = 0.0;
            // sumsqwt = 0.0; - unused
            for (int i = 1; i <= k; i++)
            {
                double weight = 1.0 / (tausq + 1.0 / wt[i]);
                dswt[i] = weight;
                sumwt += weight;
                if (useRatio)
                    wlrr += Math.Log(y[i]) * weight;
                else
                    wlrr += y[i] * weight;
            }
            if (useRatio)
            {
                dsrr = Math.Exp(wlrr / sumwt);
                dsll = Math.Exp(wlrr / sumwt - cit / Math.Sqrt(sumwt));
                dsul = Math.Exp(wlrr / sumwt + cit / Math.Sqrt(sumwt));
            }
            else
            {
                dsrr = wlrr / sumwt;
                dsll = wlrr / sumwt - cit / Math.Sqrt(sumwt);
                dsul = wlrr / sumwt + cit / Math.Sqrt(sumwt);
            }
            double dsz = wlrr / Math.Sqrt(sumwt);
            if (dsll > dsul)
            {
                Utilities.Utilities.Swap(ref dsll, ref dsul);
            }

            ParameterBag outputParameters = new();
            outputParameters.AddOutput("stat", stat);
            outputParameters.AddOutput("pc", cco * 100);

            IList<ParameterBag> studiesList = new List<ParameterBag>();
            outputParameters.AddOutput("*studies", studiesList);
            for (int i = 1; i <= k; i++)
            {
                ParameterBag studiesParameters = new();
                studiesList.Add(studiesParameters);
                studiesParameters.AddOutput("st", i);
                studiesParameters.AddOutput("y", y[i]);
                studiesParameters.AddOutput("se", seY[i]);
                studiesParameters.AddOutput("from", llY[i]);
                studiesParameters.AddOutput("to", ulY[i]);
                studiesParameters.AddOutput("wt", 100 * wt[i] / Formatting.dsum(wt, 1));
                studiesParameters.AddOutput("dwt", 100 * dswt[i] / Formatting.dsum(dswt, 1));
                studiesParameters.AddOutput("standardized_effect", y[i]); // TODO: Correct?  Is re-using se correct?
                studiesParameters.AddOutput("lb", hasUserSuppliedLabels ? title[i] : string.Empty);
            }

            outputParameters.AddOutput("stat_fixed", stat.ToLower(CultureInfo.CurrentCulture));
            outputParameters.AddOutput("rmh", rmh);
            outputParameters.AddOutput("from_fixed", llrmh);
            outputParameters.AddOutput("to_fixed", ulrmh);

            outputParameters.AddOutput("task", "test " + stat + " " + statx.ToLower(CultureInfo.CurrentCulture));
            outputParameters.AddOutput("z", zrmh);
            outputParameters.AddOutput("p_fixed", MathDbl.zvalp2(zrmh));

            outputParameters.AddOutput("qc", qc);
            outputParameters.AddOutput("df", k - 1);
            outputParameters.AddOutput("xp", PDF.chivalp(qc, k - 1));
            outputParameters.AddOutput("tausq", tausq);
            IsquareNcc(host, qc, k, cco, cit, out double isq, out double llisq, out double ulisq);
            outputParameters.AddOutput("isq", isq);
            outputParameters.AddOutput("pc1", cco * 100);
            outputParameters.AddOutput("llisq", llisq);
            outputParameters.AddOutput("ulisq", ulisq);

            outputParameters.AddOutput("dsstat", stat.ToLower(CultureInfo.CurrentCulture));
            outputParameters.AddOutput("dsrr", dsrr);
            outputParameters.AddOutput("dsll", dsll);
            outputParameters.AddOutput("dsul", dsul);

            outputParameters.AddOutput("zstat", "test " + stat + statx.ToLower(CultureInfo.CurrentCulture));
            outputParameters.AddOutput("dz", dsz);
            outputParameters.AddOutput("dp", MathDbl.zvalp2(dsz));

            IList<ParameterBag> biasList = new List<ParameterBag>();
            outputParameters.AddOutput("*bias", biasList);
            ParameterBag biasParameters = new();
            biasList.Add(biasParameters);
            Transformation xform = Transformation.None;
            if (useRatio)
                xform = Transformation.Log;
            Metabias(host, biasParameters, y, llY, ulY, k, ref cco, xform);

            IList<ParameterBag> chartList = new List<ParameterBag>();
            outputParameters.AddOutput("*chart", chartList);
            ParameterBag chartParameters;

            if (k > 3)
            {
                chartParameters = new ParameterBag();
                chartList.Add(chartParameters);
                chartParameters.AddOutput("chart", ChartRendererFactory.PrepForLater(ChartType.BiasMA, new BiasMAOptions(ShallowCopy(y), odx, wt, k, stat.ToLower(CultureInfo.CurrentCulture), ShallowCopy(llY), ShallowCopy(ulY), cco, cit, rmh, xform, false)));
            }

            y[k + 1] = rmh;
            llY[k + 1] = llrmh;
            ulY[k + 1] = ulrmh;
            chartParameters = new ParameterBag();
            chartList.Add(chartParameters);
            chartParameters.AddOutput("chart", ChartRendererFactory.PrepForLater(ChartType.Correlation, new CorrelationOptions(k + 1, title, ShallowCopy(y), ShallowCopy(llY), ShallowCopy(ulY), wt, pg, "Summary meta-analysis plot [fixed effects]", stat.ToLower(CultureInfo.CurrentCulture) + " (" + Formatting.XRound(cco * 100, 1) + "% confidence interval" + ")", xform, !useRatio)));

            y[k + 1] = dsrr;
            llY[k + 1] = dsll;
            ulY[k + 1] = dsul;
            chartParameters = new ParameterBag();
            chartList.Add(chartParameters);
            chartParameters.AddOutput("chart", ChartRendererFactory.PrepForLater(ChartType.Correlation, new CorrelationOptions(k + 1, title, ShallowCopy(y), ShallowCopy(llY), ShallowCopy(ulY), dswt, pg, "Summary meta-analysis plot [random effects]", stat.ToLower(CultureInfo.CurrentCulture) + " (" + Formatting.XRound(cco * 100, 1) + "% confidence interval" + ")", xform, !useRatio)));

            return new StepOutput(outputParameters);
        }

        public static StepOutput RptMetaCorrelation(IPreferencesAndProgressBar host, ParameterBag parameters)
        {
            double tausq;
            double cit;
            int i;
            bool stratlab;
            double[] odx = null;

            double cco = parameters["gamma"].AsDouble;
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

            DataFrame rFrame = parameters["r"].AsDataFrame;
            DoubleVariable rVariable = (DoubleVariable) rFrame.Variables[0]; //  Ends up in y
            int k = rVariable.Length;
            double[] y = new double[k + 2];
            // double[] n = new double[k + 2 ]; - unused
            string[] title = new string[k + 2];
            CorrelationRowType[] pg = new CorrelationRowType[k + 2];
            for (i = 1; i <= k; i++)
            {
                y[i] = rVariable.Data[i - 1];
                pg[i] = CorrelationRowType.Study;
                if (y[i] < -1.0 || y[i] > 1.0)
                    throw new Exception($"r({i}) must be between -1 and 1");
            }
            // pooled indicator for last element - needed by plot_cp
            pg[k + 1] = CorrelationRowType.Pooled;

            DataFrame nFrame = parameters["n"].AsDataFrame;
            DoubleVariable nVariable = (DoubleVariable)nFrame.Variables[0];
            double[] seY = new double[k + 2];
            double[] llY = new double[k + 2];
            double[] ulY = new double[k + 2];
            double[] ss = new double[k + 2];
            for (i = 1; i <= k; i++)
            {
                double sampleSize = nVariable.Data[i - 1];
                if (sampleSize < 3)
                    throw new Exception($"All values of n must be at least 3. n({i}) is less than 3");

                ss[i] = sampleSize;
                seY[i] = Math.Sqrt(1 / (sampleSize - 3));
                llY[i] = MathDbl.ztor(MathDbl.rtoz(y[i]) - cit * seY[i]);
                ulY[i] = MathDbl.ztor(MathDbl.rtoz(y[i]) + cit * seY[i]);
            }

            if (parameters.ContainsKey("studies") && parameters["studies"].HasData)
            {
                stratlab = true;
                DataFrame strataFrame = parameters["studies"].AsDataFrame;
                StringVariable strataVariable = (StringVariable)strataFrame.Variables[0];
                for (i = 1; i <= k; i++)
                {
                    string buf = strataVariable.Data[i - 1].Trim();
                    if (buf.Length > 0)
                    {
                        if (buf.Length > 50)
                            buf = buf.Substring(0, 50);
                        title[i] = buf;
                    }
                    else
                    {
                        title[i] = "study " + i;
                    }
                }
            }
            else
            {
                stratlab = false;
                for (i = 1; i <= k; i++)
                    title[i] = "study " + i;
            }
            title[k + 1] = Charting.Renderer.AbstractForestishChartRenderer.ComboTi(string.Empty);

            // Pool
            double sumwt = 0.0;
            double sumsqwt = 0.0;
            double sumywt = 0.0;
            double[] wt = new double[k + 2];
            double[] dswt = new double[k + 2];
            for (i = 1; i <= k; i++)
            {
                if (seY[i] == 0.0)
                    throw new InvalidDataException();
                wt[i] = ss[i] - 3;
                sumwt += wt[i];
                sumsqwt += wt[i] * wt[i];
                sumywt += MathDbl.rtoz(y[i]) * wt[i];
            }
            wt[k + 1] = Constant.MISSING;
            dswt[k + 1] = Constant.MISSING;
            double rmh = MathDbl.ztor(sumywt / sumwt);
            double sermh = Math.Pow(sumwt, -0.5);
            double llrmh = MathDbl.ztor(MathDbl.rtoz(rmh) - sermh * cit);
            double ulrmh = MathDbl.ztor(MathDbl.rtoz(rmh) + sermh * cit);
            if (llrmh > ulrmh)
                Utilities.Utilities.Swap(ref llrmh, ref ulrmh);
            double zrmh = MathDbl.rtoz(rmh) / sermh;

            // Q (combinability)
            double qc = 0.0;
            for (i = 1; i <= k; i++)
                qc += wt[i] * Math.Pow(MathDbl.rtoz(y[i]) - MathDbl.rtoz(rmh), 2.0);

            // DerSimonian-Laird random effects
            if (sumwt - sumsqwt / sumwt == 0.0)
                tausq = 0.0;
            else
                tausq = (qc - Convert.ToDouble(k - 1)) / (sumwt - sumsqwt / sumwt);
            if (tausq < 0.0)
                tausq = 0.0;
            double wlrr = 0.0;
            sumwt = 0.0;
            // sumsqwt = 0.0; - unused
            for (i = 1; i <= k; i++)
            {
                double weight = 1.0 / (tausq + 1.0 / wt[i]);
                dswt[i] = weight;
                sumwt += weight;
                wlrr += MathDbl.rtoz(y[i]) * weight;
            }
            double dsrr = MathDbl.ztor(wlrr / sumwt);
            double dsll = MathDbl.ztor(wlrr / sumwt - cit / Math.Sqrt(sumwt));
            double dsul = MathDbl.ztor(wlrr / sumwt + cit / Math.Sqrt(sumwt));
            double dsz = wlrr / Math.Sqrt(sumwt);
            if (dsll > dsul)
                Utilities.Utilities.Swap(ref dsll, ref dsul);

            // Schmidt-Hunter
            double varR = 0, wmrCrll, wmrCrul;
            double wmr = 0.0;
            double tot = 0.0;
            for (i = 1; i <= k; i++)
                tot += ss[i];
            for (i = 1; i <= k; i++)
                wmr += y[i] * ss[i];
            wmr /= tot;
            for (i = 1; i <= k; i++)
                varR += ss[i] * Math.Pow(y[i] - wmr, 2.0);
            varR /= tot;
            double varE = Math.Pow(1.0 - Math.Pow(wmr, 2.0), 2.0) / (tot / Convert.ToDouble(k) - 1.0);
            double percvar = 100.0 * varE / varR;
            double varP = varR - varE;
            if (varP < 0.0)
            {
                varP = 0.0;
                percvar = 100.0;
            }
            double wmrZ = wmr / Math.Sqrt(varR / Convert.ToDouble(k));
            double wmrP = MathDbl.zvalp2(wmrZ);
            double wmrLcl = wmr - cit * Math.Sqrt(varR / Convert.ToDouble(k));
            double wmrUcl = wmr + cit * Math.Sqrt(varR / Convert.ToDouble(k));
            double sres = Math.Sqrt(varP);
            if (varP > 0.0)
            {
                wmrCrll = wmr - cit * sres;
                wmrCrul = wmr + cit * sres;
            }
            else
            {
                wmrCrll = Constant.MISSING;
                wmrCrul = Constant.MISSING;
            }
            double hetX2 = Convert.ToDouble(k) * varR / varE;
            double hetP = PDF.chivalp(hetX2, Convert.ToDouble(k - 1));

            const string stat = "Correlation";
            ParameterBag outputParameters = new();
            outputParameters.AddOutput("stat", stat);
            outputParameters.AddOutput("pc", cco * 100);

            IList<ParameterBag> studiesList = new List<ParameterBag>();
            outputParameters.AddOutput("*studies", studiesList);
            for (i = 1; i <= k; i++)
            {
                ParameterBag studiesParameters = new();
                studiesList.Add(studiesParameters);
                studiesParameters.AddOutput("st", i);
                studiesParameters.AddOutput("n", ss[i]);
                studiesParameters.AddOutput("y", y[i]);
                studiesParameters.AddOutput("from", llY[i]);
                studiesParameters.AddOutput("to", ulY[i]);
                studiesParameters.AddOutput("wt", 100 * wt[i] / Formatting.dsum(wt, 1));
                studiesParameters.AddOutput("dwt", 100 * dswt[i] / Formatting.dsum(dswt, 1));
                studiesParameters.AddOutput("nwt", 100 * ss[i] / Formatting.dsum(ss, 1));
                studiesParameters.AddOutput("yi", MathDbl.rtoz(y[i]));
                studiesParameters.AddOutput("vi", seY[i] * seY[i]);
                studiesParameters.AddOutput("lb", stratlab ? title[i] : string.Empty);
            }

            outputParameters.AddOutput("stat_fixed", stat.ToLower(CultureInfo.CurrentCulture));
            outputParameters.AddOutput("rmh", rmh);
            outputParameters.AddOutput("from_fixed", llrmh);
            outputParameters.AddOutput("to_fixed", ulrmh);

            outputParameters.AddOutput("z", zrmh);
            outputParameters.AddOutput("p_fixed", MathDbl.zvalp2(zrmh));

            outputParameters.AddOutput("qc", qc);
            outputParameters.AddOutput("df", k - 1);
            outputParameters.AddOutput("xp", PDF.chivalp(qc, k - 1));
            outputParameters.AddOutput("tausq", tausq);

            IsquareNcc(host, qc, k, cco, cit, out double isq, out double llisq, out double ulisq);
            outputParameters.AddOutput("isq", isq);
            outputParameters.AddOutput("pc1", cco * 100);
            outputParameters.AddOutput("llisq", llisq);
            outputParameters.AddOutput("ulisq", ulisq);

            outputParameters.AddOutput("dsstat", stat.ToLower(CultureInfo.CurrentCulture));
            outputParameters.AddOutput("dsrr", dsrr);
            outputParameters.AddOutput("dsll", dsll);
            outputParameters.AddOutput("dsul", dsul);

            outputParameters.AddOutput("dz", dsz);
            outputParameters.AddOutput("dp", MathDbl.zvalp2(dsz));

            outputParameters.AddOutput("wmr", wmr);
            outputParameters.AddOutput("wmr_lcl", wmrLcl);
            outputParameters.AddOutput("wmr_ucl", wmrUcl);
            outputParameters.AddOutput("wmr_z", wmrZ);
            outputParameters.AddOutput("wmr_p", wmrP);
            outputParameters.AddOutput("var_r", varR);
            outputParameters.AddOutput("var_e", varE);
            outputParameters.AddOutput("var_p", varP);
            outputParameters.AddOutput("wmr_crll", wmrCrll);
            outputParameters.AddOutput("wmr_crul", wmrCrul);
            outputParameters.AddOutput("wmr4", wmr / 4.0);
            outputParameters.AddOutput("sres", sres);
            outputParameters.AddOutput("percvar", percvar);
            outputParameters.AddOutput("het_x2", hetX2);
            outputParameters.AddOutput("het_p", hetP);

            IList<ParameterBag> biasList = new List<ParameterBag>();
            outputParameters.AddOutput("*bias", biasList);
            ParameterBag biasParameters = new();
            biasList.Add(biasParameters);
            Metabias(host, biasParameters, y, llY, ulY, k, ref cco, Transformation.Z);

            IList<ParameterBag> chartList = new List<ParameterBag>();
            outputParameters.AddOutput("*chart", chartList);
            ParameterBag chartParameters;

            if (k > 3)
            {
                chartParameters = new ParameterBag();
                chartList.Add(chartParameters);
                chartParameters.AddOutput("chart", ChartRendererFactory.PrepForLater(ChartType.BiasMA, new BiasMAOptions(ShallowCopy(y), odx, wt, k, "Correlation", ShallowCopy(llY), ShallowCopy(ulY), cco, cit, wmr, Transformation.Z, false)));
            }

            y[k + 1] = rmh;
            llY[k + 1] = llrmh;
            ulY[k + 1] = ulrmh;
            chartParameters = new ParameterBag();
            chartList.Add(chartParameters);
            chartParameters.AddOutput("chart", ChartRendererFactory.PrepForLater(ChartType.Correlation, new CorrelationOptions(k + 1, title, ShallowCopy(y), ShallowCopy(llY), ShallowCopy(ulY), wt, pg, "Correlation (Hedges-Olkin fixed effects) meta-analysis plot", stat + " (" + Formatting.XRound(cco * 100, 1) + "% confidence interval" + ")", Transformation.None, false)));

            y[k + 1] = dsrr;
            llY[k + 1] = dsll;
            ulY[k + 1] = dsul;
            chartParameters = new ParameterBag();
            chartList.Add(chartParameters);
            chartParameters.AddOutput("chart", ChartRendererFactory.PrepForLater(ChartType.Correlation, new CorrelationOptions(k + 1, title, ShallowCopy(y), ShallowCopy(llY), ShallowCopy(ulY), wt, pg, "Correlation (Hedges-Olkin random effects) meta-analysis plot", stat + " (" + Formatting.XRound(cco * 100, 1) + "% confidence interval" + ")", Transformation.None, false)));

            y[k + 1] = wmr;
            llY[k + 1] = wmrLcl;
            ulY[k + 1] = wmrUcl;
            chartParameters = new ParameterBag();
            chartList.Add(chartParameters);
            chartParameters.AddOutput("chart", ChartRendererFactory.PrepForLater(ChartType.Correlation, new CorrelationOptions(k + 1, title, y, llY, ulY, wt, pg, "Correlation (Schmidt-Hunter) meta-analysis plot", stat + " (" + Formatting.XRound(cco * 100, 1) + "% confidence interval" + ")", Transformation.None, false)));

            return new StepOutput(outputParameters);
        }

        public static void OrciCorn(IPreferences host, ref double conflev, ref double a, ref double b, ref double c, ref double d, out double odr, out double ll, out double ul)
        {
            //  ref Alan Agresti R script http://web.stat.ufl.edu/~aa/cda/R/two_sample/R2/
            double aa;
            double bb;
            double cc;
            double dd;
            if (b * c == 0.0)
            {
                ContinuityCorrect(host, a, b, c, d, out aa, out bb, out cc, out dd);
                odr = aa * dd / (bb * cc);
            }
            else
            {
                odr = a * d / (b * c);
                aa = a;
                bb = b;
                cc = c;
                dd = d;
            }
            double x1 = aa;
            double n1 = aa + cc;
            double x2 = bb;
            double n2 = bb + dd;
            double px = x1 / n1;
            double py = x2 / n2;
            double theta;
            if (((aa == 0.0) & (bb == 0.0)) | ((aa == aa + cc) & (bb == bb + dd)))
            {
                ul = double.PositiveInfinity;
                ll = 0.0;
            }
            else if ((aa == 0.0) | (bb == n2))
            {
                ll = 0.0;
                theta = 0.01 / n2;
                ul = CornfieldLimit(x1, n1, x2, n2, conflev, ref theta, 1.0);
            }
            else if ((aa == n1) | (bb == 0.0))
            {
                ul = double.PositiveInfinity;
                theta = 100.0 * n1;
                ll = CornfieldLimit(x1, n1, x2, n2, conflev, ref theta, 0.0);
            }
            else
            {
                theta = px / (1 - px) / (py / (1 - py)) / 1.1;
                ll = CornfieldLimit(x1, n1, x2, n2, conflev, ref theta, 0.0);
                theta = px / (1 - px) / (py / (1 - py)) * 1.1;
                ul = CornfieldLimit(x1, n1, x2, n2, conflev, ref theta, 1.0);
            }
        }

        private static double CornfieldLimit(double x, double nx, double y, double ny, double conflev, ref double lim, double t)
        {
            double ci = 0;

            double z = PDF.ppchi2(conflev, 1.0, out int fault);
            if (fault != 0)
            {
                lim = Constant.MISSING;
            }
            else
            {
                double px = x / nx;
                double score = 0.0;
                int iter = 0;
                while (score < z)
                {
                    double a = ny * (lim - 1.0);
                    double b = nx * lim + ny - (x + y) * (lim - 1.0);
                    double c = -(x + y);
                    double p2D = (-b + Math.Sqrt(Math.Pow(b, 2.0) - 4.0 * a * c)) / (2.0 * a);
                    double p1D = p2D * lim / (1.0 + p2D * (lim - 1.0));
                    score = Math.Pow(nx * (px - p1D), 2.0) * (1.0 / (nx * p1D * (1.0 - p1D)) + 1.0 / (ny * p2D * (1.0 - p2D)));
                    ci = lim;
                    if (t == 0.0)
                    {
                        lim = ci / 1.001;
                    }
                    else
                    {
                        lim = ci * 1.001;
                    }
                    iter += 1;
                    if (iter > 1000000)
                    {
                        ci = Constant.MISSING;
                        break;
                    }
                }
                return ci;
            }
            return 0;
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="q"></param>
        /// <param name="k"></param>
        /// <param name="cit"></param>
        /// <param name="isq"></param>
        /// <param name="ll"></param>
        /// <param name="ul"></param>
        /// <remarks>Higgins P, Thompson S. Quantifying heterogeneity in meta-analysis. Stats in Medicine 2002; 21: 1539-1558</remarks>
        public static void Isquare(double q, int k, double cit, out double isq, out double ll, out double ul)
        {
            double df = Convert.ToDouble(k - 1);
            double hsq = q / df;
            isq = 100.0 * Math.Max(0, (hsq - 1.0) / hsq);
            if (k < 3)
            {
                ll = Constant.MISSING;
                ul = Constant.MISSING;
            }
            else
            {
                double selh;
                if (q > Convert.ToDouble(k))
                {
                    selh = 0.5 * (Math.Log(q) - Math.Log(df)) / (Math.Sqrt(2.0 * q) - Math.Sqrt(2.0 * Convert.ToDouble(k) - 3.0));
                }
                else
                {
                    selh = Math.Sqrt(1.0 / (2.0 * Convert.ToDouble(k - 2)) * (1.0 - 1.0 / (3.0 * Math.Pow(Convert.ToDouble(k - 2), 2.0))));
                }
                double llh = Math.Exp(Math.Log(Math.Sqrt(hsq)) - cit * selh);
                double ulh = Math.Exp(Math.Log(Math.Sqrt(hsq)) + cit * selh);
                ll = 100.0 * Math.Max(0, (Math.Pow(llh, 2.0) - 1.0) / Math.Pow(llh, 2.0));
                ul = 100.0 * Math.Max(0, (Math.Pow(ulh, 2.0) - 1.0) / Math.Pow(ulh, 2.0));
            }
        }

        private static void ContinuityCorrect(IPreferences host, double a, double b, double c, double d, out double ax, out double bx, out double cx, out double dx)
        {
            double x = host.Preferences.MetaCC == 0.0 ? 0.5 : host.Preferences.MetaCC;
            if (x > 0.0 && x < 1.0)
            {
                ax = a + x;
                bx = b + x;
                cx = c + x;
                dx = d + x;
            }
            else if (x == -9.0)
            {
                double nt = a + c;
                double nc = b + d;
                if (nt > 0.0 && b * c > 0.0)  // IEB 18 Jul 18: force Cochran correction if odds ratio would cause divide by zero - needs reporting properly not just labelled as preference method
                {
                    double r = nc / nt;
                    bx = b + r / (r + 1.0);
                    dx = d + r / (r + 1.0);
                    ax = a + 1.0 / (r + 1.0);
                    cx = c + 1.0 / (r + 1.0);
                }
                else
                {
                    x = 0.5;
                    ax = a + x;
                    bx = b + x;
                    cx = c + x;
                    dx = d + x;
                }
            }
            else
            {
                x = 0.5;
                ax = a + x;
                bx = b + x;
                cx = c + x;
                dx = d + x;
            }
        }

        public static StepOutput RptProportionMeta(IPreferencesAndProgressBar host, ParameterBag parameters)
        {
            double cco = parameters["gamma"].AsDouble;
            VarianceStabilisationMethod method = "doubleArcsine".Equals(parameters["method"].AsString) ? VarianceStabilisationMethod.DoubleArcsine : VarianceStabilisationMethod.ArcsineSquareRoot;
            if (cco < 0)
                cco = 0.95;
            double cit = PDF.gauinv(1.0 - (1.0 - cco) / 2.0);

            double fudge = 0.5;

            DataFrame snFrame = parameters["sn"].AsDataFrame;
            DoubleVariable snVariable = (DoubleVariable)snFrame.Variables[0];
            DataFrame srFrame = parameters["sr"].AsDataFrame;
            DoubleVariable srVariable = (DoubleVariable)srFrame.Variables[0];
            int rawRows = snVariable.Length;

            DoubleArraysAndBooleans copiesRemovingMissingRows = Numerics.Utilities.RemoveMissingRows(new[] { snVariable.Data, srVariable.Data }, 0, rawRows, 1, 1);
            double[] sn = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[0];
            double[] sr = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[1];

            string[] title = MakeTitles(parameters, "strata", "stratum {0}", rawRows, out bool hasUserSuppliedLabels);

            int k = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[0].Length - 2; /* 1-based, 1 extra for pooling */
            title = Numerics.Utilities.CopyValidRows(title, copiesRemovingMissingRows.ValidRowsInOriginal, 0, rawRows, 1, k, 1);
            title[k + 1] = Charting.Renderer.AbstractForestishChartRenderer.ComboTi(string.Empty);

            bool allRZero = true;
            bool allREqualN = true;
            for (int i = 1; i <= k; i++)
            {
                if (sr[i] > 0)
                    allRZero = false;
                if (sr[i] < sn[i])
                    allREqualN = false;
                if (sr[i] < 0.0 || sn[i] < sr[i])
                    throw new InvalidDataException("Each value of r must be between 0 and its corresponding n");
            }

            double[] y = new double[k + 2];
            double[] seY = new double[k + 2];
            double[] llY = new double[k + 2];
            double[] ulY = new double[k + 2];
            CorrelationRowType[] pg = new CorrelationRowType[k + 2];
            for (int i = 1; i <= k; i++)
                pg[i] = CorrelationRowType.Study;
            pg[k + 1] = CorrelationRowType.Pooled;

            // Pool
            double sumwt = 0.0;
            double sumsqwt = 0.0;
            double sumywt = 0.0;
            double[] wt = new double[k + 2];
            double[] dswt = new double[k + 2];
            for (int i = 1; i <= k; i++)
            {
                // arcsine transformation to stabilize the variance of the proportion
                y[i] = ArcsineP(sr[i], sn[i]);
                seY[i] = ArcsineSe(sn[i], fudge);
                if (seY[i] == 0.0)
                    throw new InvalidDataException();
                wt[i] = 1.0 / (seY[i] * seY[i]);
                sumwt += wt[i];
                sumsqwt += wt[i] * wt[i];
                sumywt += y[i] * wt[i];
            }
            wt[k + 1] = Constant.MISSING;
            dswt[k + 1] = Constant.MISSING;
            double rmh = sumywt / sumwt;
            double sermh = Math.Pow(sumwt, -0.5);
            double llrmh = rmh - sermh * cit;
            double ulrmh = rmh + sermh * cit;
            // double x2rmh = Math.Pow( ( rmh / sermh ), 2.0 ); - never used

            // Q (combinability)
            double qc = 0.0;
            for (int i = 1; i <= k; i++)
                qc += wt[i] * Math.Pow(y[i] - rmh, 2.0);

            // DerSimonian-Laird random effects
            double tausq;
            if (sumwt - sumsqwt / sumwt == 0.0)
                tausq = 0.0;
            else
                tausq = (qc - (k - 1)) / (sumwt - sumsqwt / sumwt);
            if (tausq < 0.0)
                tausq = 0.0;
            double wlrr = 0.0;
            sumwt = 0.0;
            // sumsqwt = 0.0; unused
            for (int i = 1; i <= k; i++)
            {
                double weight = 1.0 / (tausq + 1.0 / wt[i]);
                dswt[i] = weight;
                sumwt += weight;
                wlrr += y[i] * weight;
            }
            double dspr = wlrr / sumwt;
            double dsll = wlrr / sumwt - cit / Math.Sqrt(sumwt);
            double dsul = wlrr / sumwt + cit / Math.Sqrt(sumwt);
            // double dsx2 = Math.Pow( wlrr, 2.0 ) / sumwt; - unused
            if (dsll > dsul)
                Utilities.Utilities.Swap(ref dsll, ref dsul);

            // convert back to proportion scale
            double[,] o = new double[k + 1, 4 + 1];
            rmh = ArcsineInv(rmh, sn, method);
            llrmh = ArcsineInv(llrmh, sn, method);
            ulrmh = ArcsineInv(ulrmh, sn, method);
            dspr = ArcsineInv(dspr, sn, method);
            dsll = ArcsineInv(dsll, sn, method);
            dsul = ArcsineInv(dsul, sn, method);

            // Set limits (ticket #495, 2012-05-08)
            if (allRZero)
            {
                rmh = 0;
                llrmh = 0;
            }
            else if (allREqualN)
            {
                rmh = 1;
                ulrmh = 1;
            }

            for (int i = 1; i <= k; i++)
            {
                y[i] = sr[i] / sn[i];
                o[i, 1] = sr[i];
                o[i, 2] = sn[i];
                o[i, 3] = rmh;
            }

            ParameterBag outputParameters = new();

            IList<ParameterBag> inputsList = new List<ParameterBag>();
            outputParameters.AddOutput("*inputs", inputsList);
            for (int i = 1; i <= k; i++)
            {
                ParameterBag inputsParameters = new();
                inputsList.Add(inputsParameters);
                inputsParameters.AddOutput("st", i);
                inputsParameters.AddOutput("r", sr[i]);
                inputsParameters.AddOutput("n", sn[i]);
                inputsParameters.AddOutput("lb", hasUserSuppliedLabels ? title[i] : string.Empty);
            }

            outputParameters.AddOutput("pc", cco * 100);

            IList<ParameterBag> proportionsList = new List<ParameterBag>();
            outputParameters.AddOutput("*proportions", proportionsList);
            for (int i = 1; i <= k; i++)
            {
                ParameterBag proportionsParameters = new();
                proportionsList.Add(proportionsParameters);
                proportionsParameters.AddOutput("st", i);
                proportionsParameters.AddOutput("p", sr[i] / sn[i]);
                MathDbl.binci(sr[i], sn[i], out llY[i], out ulY[i], cco, out string tmp);
                proportionsParameters.AddOutput("from_y", llY[i]);
                proportionsParameters.AddOutput("to_y", ulY[i]);
                proportionsParameters.AddOutput("wt", 100 * wt[i] / Formatting.dsum(wt, 1));
                proportionsParameters.AddOutput("dwt", 100 * dswt[i] / Formatting.dsum(dswt, 1));
                proportionsParameters.AddOutput("yi", y[i]);
                proportionsParameters.AddOutput("vi", seY[i] * seY[i]);
                if (hasUserSuppliedLabels)
                    tmp = title[i] + tmp;
                proportionsParameters.AddOutput("lb", tmp);
            }

            outputParameters.AddOutput("methodLabel", method == VarianceStabilisationMethod.ArcsineSquareRoot ? "Stuart-Ord (inverse double arcsine square root)" : "Miller (exact inverse Freeman-Tukey double arcsine)");

            outputParameters.AddOutput("rmh", rmh);
            outputParameters.AddOutput("from", llrmh);
            outputParameters.AddOutput("to", ulrmh);

            outputParameters.AddOutput("qc", qc);
            outputParameters.AddOutput("df", k - 1);
            outputParameters.AddOutput("xp", PDF.chivalp(qc, k - 1));
            outputParameters.AddOutput("tausq", tausq);
            IsquareNcc(host, qc, k, cco, cit, out double isq, out double llisq, out double ulisq);
            outputParameters.AddOutput("isq", isq);
            outputParameters.AddOutput("pc1", cco * 100);
            outputParameters.AddOutput("llisq", llisq);
            outputParameters.AddOutput("ulisq", ulisq);

            outputParameters.AddOutput("dspr", dspr);
            outputParameters.AddOutput("from_ds", dsll);
            outputParameters.AddOutput("to_ds", dsul);

            IList<ParameterBag> eggerList = new List<ParameterBag>();
            outputParameters.AddOutput("*egger", eggerList);
            ParameterBag eggerParameters = new();
            eggerList.Add(eggerParameters);
            Metabias(host, eggerParameters, y, llY, ulY, k, ref cco, Transformation.None);

            IList<ParameterBag> harbordList = new List<ParameterBag>();
            outputParameters.AddOutput("*harbord", harbordList);
            ParameterBag harbordParameters = new();
            harbordList.Add(harbordParameters);
            ModMetabias(host, harbordParameters, o, k, cco, 3);

            IList<ParameterBag> chartList = new List<ParameterBag>();
            outputParameters.AddOutput("*chart", chartList);
            ParameterBag chartParameters;

            if (k > 3)
            {
                chartParameters = new ParameterBag();
                chartList.Add(chartParameters);
                chartParameters.AddOutput("chart", ChartRendererFactory.PrepForLater(ChartType.BiasMA, new BiasMAOptions(ShallowCopy(y), sn, wt, k, "Proportion", ShallowCopy(llY), ShallowCopy(ulY), cco, cit, rmh, Transformation.None, false)));
            }

            y[k + 1] = rmh;
            llY[k + 1] = llrmh;
            ulY[k + 1] = ulrmh;

            chartParameters = new ParameterBag();
            chartList.Add(chartParameters);
            chartParameters.AddOutput("chart", ChartRendererFactory.PrepForLater(ChartType.Correlation, new CorrelationOptions(k + 1, title, ShallowCopy(y), ShallowCopy(llY), ShallowCopy(ulY), wt, pg, "Proportion meta-analysis plot [fixed effects]", "proportion" + " (" + Formatting.XRound(cco * 100, 1) + "% confidence interval" + ")", Transformation.None, false)));

            y[k + 1] = dspr;
            llY[k + 1] = dsll;
            ulY[k + 1] = dsul;
            chartParameters = new ParameterBag();
            chartList.Add(chartParameters);
            chartParameters.AddOutput("chart", ChartRendererFactory.PrepForLater(ChartType.Correlation, new CorrelationOptions(k + 1, title, ShallowCopy(y), ShallowCopy(llY), ShallowCopy(ulY), dswt, pg, "Proportion meta-analysis plot [random effects]", "proportion" + " (" + Formatting.XRound(cco * 100, 1) + "% confidence interval" + ")", Transformation.None, false)));

            return new StepOutput(outputParameters);
        }

        private static double ArcsineP(double r, double n)
        {
            // Anscombe (1948)
            // arcsine_p = ASin(Math.Sqrt((r + 3# / 8#) / (N + 3# / 4#)))
            // 
            // Freeman-Tukey
            return Math.Asin(Math.Sqrt(r / (n + 1.0))) + Math.Asin(Math.Sqrt((r + 1.0) / (n + 1.0)));
        }

        private static double ArcsineSe(double n, double fudge)
        {
            // Anscombe (1948)
            // arcsine_se = (N ^ (-0.5)) / 2#
            // 
            // Freeman-Tukey
            //  or N + 0.5
            return Math.Sqrt(1.0 / (n + fudge));
        }

        private static double ArcsineInv(double t, double[] n, VarianceStabilisationMethod method)
        {
            // Anscombe (1948)
            // arcsine_inv = Sin(P) ^ 2#
            switch (method)
            {
                case VarianceStabilisationMethod.ArcsineSquareRoot:
                    return Math.Pow(Math.Sin(t / 2.0), 2);
                case VarianceStabilisationMethod.DoubleArcsine:
                    double hmn = 0;
                    //  n(0) is empty, n(n.Length - 1) is empty
                    for (int i = 1; i <= n.Length - 2; i++)
                    {
                        hmn += 1.0 / n[i];
                    }
                    hmn = (n.Length - 2) / hmn;

                    if (t > ArcsineP(hmn, hmn))
                        return 1.0;
                    if (t < ArcsineP(0, hmn))
                        return 0;
                    return 0.5 * (1.0 - Math.Sign(Math.Cos(t)) * Math.Sqrt(1.0 - Math.Pow(Math.Sin(t) + (Math.Sin(t) - 1.0 / Math.Sin(t)) / hmn, 2.0)));
                default:
                    throw new ArgumentOutOfRangeException(nameof(method), method, "Only Arcsine and DoubleArcsine are known");
            }
        }

        private static bool IncludeTable(double[,] o, int i)
        {
            return !(o[i, 1] == 0.0 && o[i, 2] == 0.0 || o[i, 3] == 0.0 && o[i, 4] == 0.0);
        }

        public static string GetMetaLabel(IPreferences host, double[,] o, int i, bool stratlab, bool[] cced, string[] title)
        {
            if (IncludeTable(o, i))
                return (stratlab ? title[i] : string.Empty)
                    + (cced[i]
                        ? " [CC = " + (host.Preferences.MetaCC == -9.0 ? "treatment arm" : host.Preferences.MetaCC.ToString()) + "]"
                        : string.Empty);
            else
                return "* (excluded)";
        }

        public static void ModMetabias(IPreferences host, ParameterBag outputParameters, double[,] o, int k, double cco, int method)
        {
            //  Horbord et al 2006
            // get linear regression of z on sqr(v)
            //  This was cco - (1 - cco) / 2, which gave a 92.5% interval at 95%; the help has always described, and earlier versions printed, a 90% interval
            double ncco = BiasTestConfidenceLevel(cco > 0.0 ? cco : 0.95);
            double sumx = 0.0;
            double sumy = 0.0;
            double sumxy = 0.0;
            double sxs = 0.0;
            double sys = 0;
            int realk = 0;
            for (int i = 1; i <= k; i++)
            {
                if (IncludeTable(o, i))
                {
                    realk += 1;
                    double a = o[i, 1];
                    double b = o[i, 2];
                    double c = o[i, 3];
                    double d = o[i, 4];
                    double n = a + b + c + d;
                    if (n > 0)
                    {
                        double v;
                        double z;
                        if (method == 3)
                        {
                            if (b <= 0 || c <= 0)
                            {
                                a += 0.5;
                                b += 0.5;
                                c += 0.5;
                            }
                            // relative risk parameters from Whitehead
                            z = a - b * c;
                            v = b * c * (1.0 - c);
                        }
                        else if (method == 2)
                        {
                            if (a <= 0 || b <= 0 || c <= 0 || d <= 0)
                            {
                                ContinuityCorrect(host, a, b, c, d, out a, out b, out c, out d);
                                n = a + b + c + d;
                            }
                            // relative risk parameters from Whitehead
                            z = (a * n - (a + b) * (a + c)) / (c + d);
                            v = (b + d) * (a + c) * (a + b) / (n * (c + d));
                        }
                        else
                        {
                            if (a <= 0 || b <= 0 || c <= 0 || d <= 0)
                            {
                                ContinuityCorrect(host, a, b, c, d, out a, out b, out c, out d);
                                n = a + b + c + d;
                            }
                            // efficient score
                            z = a - (a + b) * (a + c) / n;
                            // hypergeometric variance of the score (Harbord, Egger and Sterne 2006)
                            v = (a + b) * (c + d) * (a + c) * (b + d) / (n * n * (n - 1.0));
                        }
                        double x = Math.Sqrt(v);
                        double y = z / Math.Sqrt(v);
                        sumx += x;
                        sxs += x * x;
                        sys += y * y;
                        sumy += y;
                        sumxy += x * y;
                    }
                }
            }
            double ssx = sxs - sumx * sumx / realk;
            double ssy = sys - sumy * sumy / realk;
            double xy = sumxy - sumx * sumy / realk;
            double slope = xy / ssx;
            double yInt = sumy / realk - slope * (sumx / realk);
            double ssreg = xy * xy / ssx;
            double ssres = ssy - ssreg;
            double bias = yInt;
            double ll; double ul;
            double se = 0;
            if (realk > 2 & ssres >= 0.0)
            {
                double mnsqr = ssres / (realk - 2);
                se = Math.Sqrt(mnsqr * (1.0 / realk + Math.Pow(sumx / realk, 2.0) / ssx));
                MathDbl.civ(realk - 2, out double cit, ncco, out double _);
                ll = bias - se * cit;
                ul = bias + se * cit;
            }
            else
            {
                ll = Constant.MISSING;
                ul = Constant.MISSING;
            }
            double t = bias / se;
            double p2 = PDF.tvalp(Math.Abs(t), realk - 2);
            if (p2 > 1.0 - p2)
                p2 = 1.0 - p2;
            p2 = 2.0 * p2;
            outputParameters.AddOutput("a", bias);
            outputParameters.AddOutput("pc_harbord", 100.0 * ncco);
            outputParameters.AddOutput("cl", ll);
            outputParameters.AddOutput("cu", ul);
            outputParameters.AddOutput("p", p2);
        }

        public static void IsquareNcc(IPreferences host, double q, int k, double cco, double cit, out double i2, out double ll, out double ul)
        {
            double SElnH;
            double minLbNc;
            int ierr = 0;
            double lbI2H; double ubI2H;

            double df = Convert.ToDouble(k - 1);
            double dk = Convert.ToDouble(k);

            i2 = Constant.MISSING;
            ll = Constant.MISSING;
            ul = Constant.MISSING;

            if (q < 0)
                return;

            // Calculate I-squared even with only one degree of freedom.
            if (df < 1)
                return;
            i2 = Math.Max(0.0, 100.0 * (q - df) / q);
            if (df < 2)
                return;
            if (cco < 0.1 || cco > 0.99)
                return;

            double level = 100.0 * cco;
            double levelci = level * 0.005 + 0.5;
            double clevelci = 1.0 - levelci;

            double h2 = q / df;
            double i22 = Math.Max(0.0, (h2 - 1.0) / h2);
            if (Math.Sqrt(h2) < 1.0)
            {
                h2 = 1.0;
            }

            //  CI for H (Higgins & Thompson, 2002 Stat in Med)
            if (q > k)
                SElnH = 0.5 * ((Math.Log(q) - Math.Log(df)) / (Math.Sqrt(2.0 * q) - Math.Sqrt(2.0 * dk - 3.0)));
            else
                SElnH = Math.Sqrt(1.0 / (2.0 * (dk - 2.0)) * (1.0 - 1.0 / (3.0 * Math.Pow(dk - 2.0, 2.0))));
            // double LB_H_III = Math.Exp( Math.Log( Math.Sqrt( H2 ) ) - cit * SElnH ); 
            // double UB_H_III = Math.Exp( Math.Log( Math.Sqrt( H2 ) ) + cit * SElnH ); 
            // if ( LB_H_III < 1.0 )
            // { 
            // LB_H_III = 1.0; 
            // } 
            //  CI for H (P 1550 Higgins & Thompson)
            // double LB_I2_HT = Math.Max( 0.0, ( Math.Pow( LB_H_III, 2.0 ) - 1.0 ) / Math.Pow( LB_H_III, 2.0 ) ); 
            // double UB_I2_HT = ( Math.Pow( UB_H_III, 2.0 ) - 1.0 ) / Math.Pow( UB_H_III, 2.0 ); 

            //  CI interval for I2 based var(logH), formula not indicated in (Higgins & Thompson, 2002 Stat in Med)
            double varI2 = 4.0 * Math.Pow(SElnH, 2.0) / Math.Exp(4.0 * Math.Log(Math.Sqrt(h2)));
            double lbI2 = i22 - cit * Math.Sqrt(varI2);
            double ubI2 = i22 + cit * Math.Sqrt(varI2);
            if (lbI2 < 0.0)
                lbI2 = 0.0;
            if (ubI2 > 1.0)
                ubI2 = 1.0;
            ll = 100.0 * lbI2;
            ul = 100.0 * ubI2;

            if (!host.Preferences.MetaExact)
                return;

            //  Iterative solution to seek CI for non-centrality parameter (and then for H and I2)
            //  non-centrality (nc) parameter = (Q-df)
            double nc = Math.Max(0.0, q - df);
            double endp = nc + 1000.0;

            //  check if Q < df , in this case no need to seek the lower bound
            if (q < df)
            {
                minLbNc = 0.0;
            }
            else
            {
                minLbNc = IsquareBrentRoot(0, endp, nc, df, clevelci, ref ierr);
                if (ierr != 0)
                    minLbNc = Constant.MISSING;
            }

            double minUbNc = IsquareBrentRoot(0, endp, nc, df, levelci, ref ierr);
            if (ierr != 0)
                minUbNc = Constant.MISSING;

            //  transform lower bound for non-centrality parameter (Q-df) in lower bound for H and I2
            if (minLbNc != Constant.MISSING)
            {
                double lbHH = Math.Max(1.0, Math.Sqrt(minLbNc / df));
                lbI2H = Math.Max(0.0, (Math.Pow(lbHH, 2.0) - 1.0) / Math.Pow(lbHH, 2.0));
            }
            else
            {
                // LB_H_H = Constant.MISSING; 
                lbI2H = Constant.MISSING;
            }

            if (minUbNc != Constant.MISSING)
            {
                double ubHH = Math.Sqrt(minUbNc / df);
                ubI2H = (Math.Pow(ubHH, 2.0) - 1.0) / Math.Pow(ubHH, 2.0);
            }
            else
            {
                // UB_H_H = Constant.MISSING; 
                ubI2H = Constant.MISSING;
            }

            // if all goes well - assign the Higgins non-central chi-square interval as the result
            if (lbI2H == Constant.MISSING)
                ll = Constant.MISSING;
            else
                ll = 100.0 * lbI2H;
            if (ubI2H == Constant.MISSING)
                ul = Constant.MISSING;
            else
                ul = 100.0 * ubI2H;
        }

        /// <summary>
        /// Brent alternative to Pegasus method for root finding - can be faster when high precision demanded
        /// </summary>
        /// <param name="xl">lower bound of search interval</param>
        /// <param name="xu">upper bound of search interval</param>
        /// <param name="nc"></param>
        /// <param name="df"></param>
        /// <param name="clev"></param>
        /// <param name="ierr"></param>
        /// <returns></returns>
        private static double IsquareBrentRoot(double xl, double xu, double nc, double df, double clev, ref int ierr)
        {
            double d = 0;
            const double tolerance = 0.000001;
            const int maxIter = 300;

            double e = 0.0;
            double a = xl;
            double b = xu;

            double fa = ExFortran.nchi2(df, nc, a) - clev;
            if (fa == Constant.MISSING)
            {
                return 0;
            }
            double fb = ExFortran.nchi2(df, nc, b) - clev;
            if (fb == Constant.MISSING)
            {
                return 0;
            }

            double c = b;
            double fc = fb;

            ierr = 0;
            int nIter = 0;

            do
            {
                nIter++;
                if (nIter > maxIter)
                {
                    ierr = 1;
                    break;
                }

                if (fb > 0.0 && fc > 0.0 || fb < 0.0 && fc < 0.0)
                {
                    c = a;
                    fc = fa;
                    d = b - a;
                    e = d;
                }

                if (Math.Abs(fc) < Math.Abs(fb))
                {
                    a = b;
                    b = c;
                    c = a;
                    fa = fb;
                    fb = fc;
                    fc = fa;
                }

                double tol1 = 2.0 * Constant.EPSILON * Math.Abs(b) + 0.5 * tolerance;

                double xm = 0.5 * (c - b);

                if (Math.Abs(xm) <= tol1 | fb == 0.0)
                    break;

                if (Math.Abs(e) >= tol1 & Math.Abs(fa) > Math.Abs(fb))
                {
                    double s = fb / fa;
                    double p;
                    double q;
                    if (a == c)
                    {
                        p = 2.0 * xm * s;
                        q = 1.0 - s;
                    }
                    else
                    {
                        q = fa / fc;
                        double r = fb / fc;
                        p = s * (2.0 * xm * q * (q - r) - (b - a) * (r - 1.0));
                        q = (q - 1.0) * (r - 1.0) * (s - 1.0);
                    }

                    if (p > 0.0)
                    {
                        q = -q;
                    }

                    p = Math.Abs(p);
                    double xmin = Math.Abs(e * q);
                    double tmp = 3.0 * xm * q - Math.Abs(tol1 * q);

                    if (xmin < tmp)
                    {
                        xmin = tmp;
                    }

                    if (2.0 * p < xmin)
                    {
                        e = d;
                        d = p / q;
                    }
                    else
                    {
                        d = xm;
                        e = d;
                    }
                }
                else
                {
                    d = xm;
                    e = d;
                }

                a = b;
                fa = fb;

                if (Math.Abs(d) > tol1)
                {
                    b += d;
                }
                else
                {
                    if (xm < 0.0)
                    {
                        b -= Math.Abs(tol1);
                    }
                    else
                    {
                        b += Math.Abs(tol1);
                    }
                }

                fb = ExFortran.nchi2(df, nc, b) - clev;
                if (fb == Constant.MISSING)
                {
                    return 0;
                }
            }
            while (true);

            return b;
        }

        public static double VarianceFromCI(double ll, double ul, double cit, bool logtransform)
        {
            if (cit <= 0)
                return Constant.MISSING;
            return logtransform
                ? Math.Pow((Math.Log(ul) - Math.Log(ll)) / 2 / cit, 2)
                : Math.Pow((ul - ll) / 2 / cit, 2);
        }

        private static T[] ShallowCopy<T>(T[] original)
        {
            T[] copy = new T[original.Length];
            Array.Copy(original, copy, original.Length);
            return copy;
        }
    }
}
