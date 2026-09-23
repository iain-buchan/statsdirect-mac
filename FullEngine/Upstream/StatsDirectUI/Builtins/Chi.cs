using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using StatsDirect.Charting;
using StatsDirect.Data;
using StatsDirect.Numerics;
using StatsDirect.Templates;
using StatsDirect.Utilities;
using static StatsDirect.Builtins.ExactBB;

namespace StatsDirect.Builtins
{
    public static class Chi
    {
        public static StepOutput RptChi2By2(IProgressBarHost host, ParameterBag parameters)
        {
            double cco = parameters["cco"].AsDouble;
            string studyType = parameters["study_type"].AsString;
            bool isCaseControl = "casecontrol".Equals(studyType);
            bool isCohort = "cohort".Equals(studyType);
            bool doFisher = parameters.ContainsKey("doFisher") && parameters["doFisher"].AsBoolean;

            if (cco <= 0.0 || cco >= 1.0)
                cco = 0.95;
            double cit = PDF.gauinv(cco + (1.0 - cco) / 2.0, out int fault);

            double a = parameters["a"].AsDouble;
            double b = parameters["b"].AsDouble;
            double c = parameters["c"].AsDouble;
            double d = parameters["d"].AsDouble;
            double p = a + b;
            double q = c + d;
            double r = a + c;
            double s = b + d;
            double n = p + q;
            ParameterBag outputParameters = new();
            if (!(fault == 0 && (p > 0 || q > 0 || r > 0 || s > 0) && p * q * r * s > 0))
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

            double e1 = p * r / n;
            double e2 = p * s / n;
            double e3 = q * r / n;
            double e4 = q * s / n;

            outputParameters.AddOutput("tab_a1", e1);
            outputParameters.AddOutput("tab_b1", e2);
            outputParameters.AddOutput("tab_a2", e3);
            outputParameters.AddOutput("tab_b2", e4);

            double f = a * d - b * c;
            double x2 = f * f * n / (p * q * r * s);
            outputParameters.AddOutput("chi", x2);
            outputParameters.AddOutput("chi_p", PDF.chivalp(x2, 1.0));

            f = Math.Abs(f) - n / 2;
            if (f < 0)
                f = 0;

            double x2C = f * f * n / (p * q * r * s);
            outputParameters.AddOutput("yates_chi", x2C);
            outputParameters.AddOutput("yates_chi_p", PDF.chivalp(x2C, 1.0));

            // coefficients (see Agresti p 23-4)
            double p1 = Math.Sqrt(x2 / (x2 + n));
            double c1 = (a * d - b * c) / Math.Sqrt(p * q * r * s);
            outputParameters.AddOutput("pearson", p1);
            outputParameters.AddOutput("vs", c1);

            List<ParameterBag> warnList = new();
            outputParameters.AddOutput("*warn", warnList);
            if (e1 < 5 || e2 < 5 || e3 < 5 || e4 < 5 || n < 20)
            {
                ParameterBag warnParameters = new();
                warnList.Add(warnParameters);
                string wrn = n < 20 ? "Number of observations" : "Expected frequencies";
                warnParameters.AddOutput("wrn", wrn);
            }

            bool doneExact = false;

            List<ParameterBag> oddsList = new();
            outputParameters.AddOutput("*odds", oddsList);
            List<ParameterBag> relRiskList = new();
            outputParameters.AddOutput("*relrisk", relRiskList);
            if (isCaseControl)
            {
                ParameterBag oddsParameters = new();
                oddsList.Add(oddsParameters);
                // Woolf/logit CI
                double odr = OddsRatio(a, b, c, d);
                double yodr;
                double xodr;
                if (b * c > 0 && a * d > 0)
                {
                    double seodr = Math.Sqrt(1.0 / a + 1.0 / b + 1.0 / c + 1.0 / d);
                    yodr = Math.Exp(Math.Log(odr) - cit * seodr);
                    xodr = Math.Exp(Math.Log(odr) + cit * seodr);
                }
                else
                {
                    yodr = Constant.MISSING;
                    xodr = Constant.MISSING;
                    if (a == 0 || d == 0)
                        yodr = 0;
                    else if (b == 0 || c == 0)
                        xodr = double.PositiveInfinity;
                }
                oddsParameters.AddOutput("odds", odr);
                oddsParameters.AddOutput("woolf_ci", cco * 100.0);
                oddsParameters.AddOutput("woolf_ci_1", yodr);
                oddsParameters.AddOutput("woolf_ci_2", xodr);
                // CMLE
                //ExactBB.Rec2X2[] tabl = new ExactBB.Rec2X2[1 + 1];
                //tabl[1].Freq = 1;
                //tabl[1].A = a;
                //tabl[1].M1 = a + b;
                //tabl[1].N1 = a + c;
                //tabl[1].N0 = b + d;
                //tabl[1].Informative = (a * d != 0) | (b * c != 0);
                //bool useLogScale = false;
                //new ExactBB().Exact22K(host, 1, 1, tabl, cco, ref eor, out ulf, out llf, out ulm, out llm, out p1F, out p2F, out p1M, out p2M, ref useLogScale, out ierr);
                OddsRatioCMLE(host, cco, a, b, c, d, out double _, out double llf, out double ulf, out double llm, out double ulm, out double p1f, out double p2f, out double p1m, out double p2m, out int ierr);
                if (ierr != 0)
                //{
                // eor = Constant.MISSING; 
                //    ulf = Constant.MISSING;
                //    llf = Constant.MISSING;
                //    ulm = Constant.MISSING;
                //    llm = Constant.MISSING;
                //    p1F = Constant.MISSING;
                //    p2F = Constant.MISSING;
                //    p1M = Constant.MISSING;
                //    p2M = Constant.MISSING;
                // }
                //else
                {
                    doneExact = true;
                }
                oddsParameters.AddOutput("ci", cco * 100.0);
                oddsParameters.AddOutput("llf", llf);
                oddsParameters.AddOutput("ulf", ulf);
                oddsParameters.AddOutput("p1f", p1f);
                oddsParameters.AddOutput("p2f", p2f);
                oddsParameters.AddOutput("llm", llm);
                oddsParameters.AddOutput("ulm", ulm);
                oddsParameters.AddOutput("p1m", p1m);
                oddsParameters.AddOutput("p2m", p2m);
            }
            else if (isCohort)
                relRiskList.Add(Analysis.RptMiscRelRisk(parameters).ParameterBag);

            List<ParameterBag> fisherList = new();
            outputParameters.AddOutput("*fisher", fisherList);
            if (!doneExact)
            {
                if (e1 < 5 || e2 < 5 || e3 < 5 || e4 < 5 || n < 20)
                {
                    fisherList.Add(Exact.RptExactFisher(parameters).ParameterBag);
                }
                else
                {
                    if (doFisher)
                        fisherList.Add(Exact.RptExactFisher(parameters).ParameterBag);
                }
            }
            return new StepOutput(outputParameters);
        }

        private enum Chi2ByNTrend
        {
            WithoutTrend = 0,
            LinearTrend = 1,
            WithTrend = 2
        }

        public static StepOutput RptChi2ByNWithoutTrend(ParameterBag parameters) => RptChi2ByN(parameters, Chi2ByNTrend.WithoutTrend);
        public static StepOutput RptChi2ByNLinearTrend(ParameterBag parameters) => RptChi2ByN(parameters, Chi2ByNTrend.LinearTrend);
        public static StepOutput RptChi2ByNWithTrend(ParameterBag parameters) => RptChi2ByN(parameters, Chi2ByNTrend.WithTrend);

        private static StepOutput RptChi2ByN(ParameterBag parameters, Chi2ByNTrend z)
        {
            DataFrame datFrame = parameters["data"].AsDataFrame;
            if (datFrame.VariableCount < (z == Chi2ByNTrend.WithTrend ? 3 : 2))
                throw new InvalidDataException("Invalid data: Please fill in the same number of rows in each column without gaps");
            DoubleVariable datV0 = (DoubleVariable)datFrame.Variables[0];
            DoubleVariable datV1 = (DoubleVariable)datFrame.Variables[1];
            DoubleVariable datV2 = null;
            if (z == Chi2ByNTrend.WithTrend)
                datV2 = (DoubleVariable)datFrame.Variables[2];
            int rows = datFrame.MaxRows;
            double[] f = new double[rows + 1];
            double[] g = new double[rows + 1];
            double[] h = new double[rows + 1];
            double[] s = new double[rows + 1];

            ParameterBag outputParameters = new();
            double k4 = 0;
            double k2 = 0;
            double k1 = 0;
            double c = 0;
            double t = 0;
            double b = 0;
            double a = 0;
            for (int r = 1; r <= rows; r++)
            {
                double a1 = datV0.Data[r - 1];
                double b1 = datV1.Data[r - 1];
                double t1 = a1 + b1;
                if (t1 <= 0.0)
                    throw new InvalidDataException("Invalid data: row " + r.ToString() + " total is not greater than zero, which it must be for this calculation");
                Debug.Assert(z != Chi2ByNTrend.WithTrend || datV2 != null);
                double s1 = z == Chi2ByNTrend.WithTrend ? datV2.Data[r - 1] : r;
                f[r] = a1;
                g[r] = b1;
                h[r] = t1;
                s[r] = s1;
                a += a1;
                b += b1;
                t += t1;
                c += a1 * a1 / t1;
                k1 += s1 * a1;
                k2 += s1 * b1;
                k4 += s1 * s1 * (a1 + b1);
            }
            double n1 = 0;
            List<ParameterBag> rowList = new();
            outputParameters.AddOutput("*row", rowList);
            for (int r = 1; r <= rows; r++)
            {
                double a1 = f[r];
                double b1 = g[r];
                double t1 = h[r];
                double s1 = s[r];
                double e1 = a * t1 / t;
                if (e1 < 5)
                    n1++;
                double e2 = b * t1 / t;
                if (e2 < 5)
                    n1++;
                ParameterBag rowParameters = new();
                rowList.Add(rowParameters);
                rowParameters.AddOutput("obs_succ", a1);
                rowParameters.AddOutput("obs_fail", b1);
                rowParameters.AddOutput("obs_tot", t1);
                rowParameters.AddOutput("obs_pc", 100 * a1 / t1);
                rowParameters.AddOutput("score", s1);

                rowParameters.AddOutput("exp_succ", e1);
                rowParameters.AddOutput("exp_fail", e2);
            }

            outputParameters.AddOutput("tot_succ", a);
            outputParameters.AddOutput("tot_fail", b);
            outputParameters.AddOutput("tot_tot", t);
            outputParameters.AddOutput("tot_pc", 100 * a / t);

            List<ParameterBag> warnList = new();
            outputParameters.AddOutput("*warn", warnList);
            if (n1 != 0)
            {
                ParameterBag warnParameters = new();
                warnList.Add(warnParameters);
                warnParameters.AddOutput("num", n1);
                warnParameters.AddOutput("den", 2 * rows);
            }

            double n2 = rows - 1;
            double x2 = (t * c - a * a) * t / (a * b);

            outputParameters.AddOutput("chi", x2);
            outputParameters.AddInput("x2", x2); //  For use with follow-on functions
            outputParameters.AddOutput("chi_abs", Math.Sqrt(x2));
            outputParameters.AddOutput("totdf", n2);
            outputParameters.AddOutput("chi_p", PDF.chivalp(x2, n2));

            List<ParameterBag> zList = new();
            outputParameters.AddOutput("*z", zList);
            if (z != Chi2ByNTrend.WithoutTrend)
            {
                c = x2;
                double k8 = b / a;
                double d = (k4 - Math.Pow(k1 + k2, 2.0) / t) / k8;
                if (d < 0)
                    d = 0;
                d = Math.Sqrt(d);
                double x1 = (k1 - k2 / k8) / d;
                x2 = x1 * x1;
                n2 = 1;
                ParameterBag zParameters = new();
                zList.Add(zParameters);

                zParameters.AddOutput("chi_lin", x2);
                outputParameters.AddInput("x2_lin", x2); //  For use with follow-on functions
                zParameters.AddOutput("chi_1df", x1);
                zParameters.AddOutput("chi_lin_p", PDF.chivalp(x2, n2));

                x2 = c - x2;
                n2 = rows - 2;
                zParameters.AddOutput("chi_non", x2);
                zParameters.AddOutput("df", n2);
                zParameters.AddOutput("chi_non_p", PDF.chivalp(x2, n2));
            }

            return new StepOutput(outputParameters);
        }

        public static StepOutput RptChiMantel(IPreferencesAndProgressBar host, ParameterBag parameters)
        {
            double p2M = 0;
            double p1M = 0;
            double p2F = 0;
            double p1F = 0;
            double llm = 0;
            double ulm = 0;
            double llf = 0;
            double ulf = 0;
            double eor = 0;
            DataFrame datFrame = parameters["data"].AsDataFrame;
            DoubleVariable datV0 = (DoubleVariable)datFrame.Variables[0];
            DoubleVariable datV1 = (DoubleVariable)datFrame.Variables[1];
            int rows = datFrame.MaxRows;

            if (rows <= 0)
                throw new InvalidDataException();

            int k = rows / 2;
            double[,] o = new double[k + 1, 4 + 1];
            string[] title = new string[k + 1];
            double[] axll = new double[k + 1];
            double[] axul = new double[k + 1];
            for (int r = 1; r <= rows; r += 2)
            {
                int strat = 1 + r / 2;
                title[strat] = "stratum " + strat.ToString();
                double rtd = datV0.Data[r - 1];
                o[strat, 1] = rtd;
                rtd = datV1.Data[r - 1];
                o[strat, 3] = rtd;
                rtd = datV0.Data[r];
                o[strat, 2] = rtd;
                rtd = datV1.Data[r];
                o[strat, 4] = rtd;
            }

            double cco = parameters["cco"].AsDouble;
            if (cco <= 0.0 || cco >= 1.0)
                cco = 0.95;

            bool plotForest = parameters["plot_forest"].AsBoolean;
            double cit = PDF.gauinv(cco + (1.0 - cco) / 2.0);

            Meta.Mantel(host, 1, k, out int realk, o, out double rmh, out double ll, out double ul, out double x2, out double sk, cit, cco, out double[] odr, out double[] odw, out double[] dswt, out double[] odrl, out double[] odru, out double[] odx, out bool[] lerr, out bool[] uerr, out double qc, out double bd, out double dsor, out double dsx2, out double dsll, out double dsul, out bool[] cced, out double tausq, out bool[] included, out int ierr);
            if (ierr != 0)
                return null;

            // Try exact Mantel
            bool tryExact = parameters["try_exact"].AsBoolean;
            if (tryExact)
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
            List<ParameterBag> inputsList = new();
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
                inputsParameters.AddOutput("lb", string.Empty);
            }
            outputParameters.AddOutput("pc", cco * 100);
            outputParameters.AddOutput("method", host.Preferences.MetaExact ? "CML" : "logit");
            List<ParameterBag> orList = new();
            outputParameters.AddOutput("*or", orList);
            for (int i = 1; i <= k; i++)
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
                //orParameters.AddOutput("lb", Meta.GetMetaLabel(host, o, i, false, cced, title));
                string tmp = Meta.GetMetaLabel(host, o, i, false, cced, title);
                if (host.Preferences.DelayContinuityCorrection)
                {
                    tmp = tmp.Replace("[CC", "[late CC");
                }
                orParameters.AddOutput("lb", tmp);
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

            List<ParameterBag> eggerList = new();
            outputParameters.AddOutput("*egger", eggerList);
            ParameterBag eggerParameters = new();
            eggerList.Add(eggerParameters);
            Meta.Metabias(host, eggerParameters, odr, axll, axul, k, ref cco, Transformation.Log);

            List<ParameterBag> harbordList = new();
            outputParameters.AddOutput("*harbord", harbordList);
            ParameterBag harbordParameters = new();
            harbordList.Add(harbordParameters);
            Meta.ModMetabias(host, harbordParameters, o, k, cco, 1);

            IList<ParameterBag> chartList = new List<ParameterBag>();
            outputParameters.AddOutput("*chart", chartList);

            if (plotForest)
            {
                ParameterBag chartParameters = new();
                chartList.Add(chartParameters);
                chartParameters.AddOutput("chart", ChartRendererFactory.PrepForLater(ChartType.MH, new MHOptions(1, k, odw, title, rmh, ll, ul, cco, odr, odrl, odru, lerr, uerr, included, "Odds ratio meta-analysis plot [fixed effects]", 1, "odds ratio")));

                chartParameters = new ParameterBag();
                chartList.Add(chartParameters);
                chartParameters.AddOutput("chart", ChartRendererFactory.PrepForLater(ChartType.MH, new MHOptions(1, k, dswt, title, dsor, dsll, dsul, cco, odr, odrl, odru, lerr, uerr, included, "Odds ratio meta-analysis plot [random effects]", 1, "odds ratio")));
            }
            return new StepOutput(outputParameters);
        }

        public static StepOutput RptChiRbyC(ITemplateHost host, ParameterBag parameters)
        {
            double cco = parameters["cco"].AsDouble;
            DataFrame dataFrame = parameters["data"].AsDataFrame;
            int rows = dataFrame.MaxRows;
            int cols = dataFrame.VariableCount;
            double[,] a = new double[rows + 1, cols + 1];
            double t = 0;
            for (int r = 1; r <= rows; r++)
            {
                for (int c = 1; c <= cols; c++)
                {
                    double a1 = ((DoubleVariable)dataFrame.Variables[c - 1]).Data[r - 1];
                    a[r, c] = a1;
                    t += a1;
                }
            }
            if (t <= 0.0)
                throw new InvalidDataException();

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

            return new StepOutput(Tables.SChi(host, ref cco, a, rows, cols, doExact, doMonteCarlo, pc, xp, cs, xs, specifyScores, mcci, iterations, seed));
        }

        public static StepOutput RptChiWoolf(ParameterBag parameters)
        {
            int rc;

            DataFrame datFrame = parameters["data"].AsDataFrame;
            DoubleVariable datV0 = (DoubleVariable)datFrame.Variables[0];
            DoubleVariable datV1 = (DoubleVariable)datFrame.Variables[1];
            int rows = datFrame.MaxRows;
            if (rows <= 0)
                throw new InvalidDataException();

            double cco = parameters["cco"].AsDouble;
            if (cco <= 0.0 || cco >= 1.0)
                cco = 0.95;

            double cit = PDF.gauinv(cco + (1.0 - cco) / 2.0);

            bool showIntermediates = parameters["show_intermediates"].AsBoolean;

            int k = rows / 2;
            double[,] o = new double[k + 1, 5];
            int cnt = 0;
            for (rc = 1; rc <= rows; rc += 2)
            {
                cnt += 1;
                double rtd = datV0.Data[rc - 1];
                o[cnt, 1] = rtd;
                rtd = datV1.Data[rc - 1];
                o[cnt, 2] = rtd;
                rtd = datV0.Data[rc];
                o[cnt, 3] = rtd;
                rtd = datV1.Data[rc];
                o[cnt, 4] = rtd;
            }

            return new StepOutput(Tables.Woolf(o, k, showIntermediates, cit, cco, out bool _));
        }

        public static StepOutput RptChi2ByNWithTrendSimulateExactP(IProgressBarHost host, ParameterBag parameters)
        {
            int iterations = parameters["iterations"].AsInt32;
            double ci = parameters["ci"].AsDouble;
            int seed = parameters["seed"].AsInt32;
            double x2 = parameters["x2_lin"].AsDouble;

            DataFrame datFrame = parameters["data"].AsDataFrame;
            bool hasSpecifiedTrend = datFrame.VariableCount == 3;
            DoubleVariable datV0 = (DoubleVariable)datFrame.Variables[0];
            DoubleVariable datV1 = (DoubleVariable)datFrame.Variables[1];
            DoubleVariable datV2 = null;
            if (hasSpecifiedTrend)
                datV2 = (DoubleVariable)datFrame.Variables[2];
            int rows = datFrame.MaxRows;
            const int cols = 2;

            int[,] x = new int[rows + 1, 3];
            double[] wt = new double[rows + 1];
            for (int row = 1; row <= rows; row++)
            {
                x[row, 1] = Convert.ToInt32(datV0.Data[row - 1]);
                x[row, 2] = Convert.ToInt32(datV1.Data[row - 1]);
                wt[row] = hasSpecifiedTrend ? datV2.Data[row - 1] : row;
            }

            int ierror = 0;
            Chi2TrendResample(host, x, wt, rows, cols, x2, iterations, out int r, out int actualIterations, seed, ref ierror);

            ParameterBag outputParameters = new();
            if (ierror == 0 || ierror == -1 /* interrupted but partial results returned */ )
            {
                double p = r / (double)actualIterations;
                outputParameters.AddOutput("p", p);
                //  CI
                MathDbl.binci(r, actualIterations, out double ll, out double ul, ci, out string warn);
                outputParameters.AddOutput("pc", 100.0 * ci);
                outputParameters.AddOutput("ll", ll);
                outputParameters.AddOutput("ul", ul);
                outputParameters.AddOutput("warn", warn);
                outputParameters.AddOutput("k", actualIterations.ToString("N0"));
                outputParameters.AddOutput("seed_fmt", seed.ToString());
            }
            else
            {
                outputParameters.AddOutput("p", "P = * (cancelled)");
            }
            return new StepOutput(outputParameters);
        }

        ///  <summary>
        ///  Simulated exact P for Cochran-Armitage trend test
        ///  </summary>
        /// <param name="host"></param>
        /// <param name="x">(1..nrow,1..ncol) input 2 by k table</param>
        ///  <param name="wt">(1..nrow) input weights</param>
        ///  <param name="nrow">rows</param>
        ///  <param name="ncol">columns (could modify this for r by c)</param>
        ///  <param name="x2">chi-square for trend (could add independence chi-square too)</param>
        ///  <param name="iter">Monte Carlo iterations</param>
        ///  <param name="r">Monte Carlo P numerator</param>
        /// <param name="actualIterations">The number of Monte Carlo iterations actually performed</param>
        /// <param name="iseed">RNG seed (0 for automatic)</param>
        ///  <param name="ierror">return non-zero if fault (-1 if interrupted)</param>
        ///  <remarks></remarks>
        private static void Chi2TrendResample(IProgressBarHost host, int[,] x, double[] wt, int nrow, int ncol, double x2, int iter, out int r, out int actualIterations, int iseed, ref int ierror)
        {
            int[] ncolt = new int[ncol + 1];
            int[] nrowt = new int[nrow + 1];
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

            for (j = 1; j <= nrow; j++)
            {
                for (i = 1; i <= ncol; i++)
                {
                    nrowt[j] += x[j, i];
                    ncolt[i] += x[j, i];
                }
            }

            int maxtot = 5000000;
            bool primed = false;

            double[] fact = new double[ncol + 1];
            int[] jwork = new int[ncol + 1];

            const double tol = Constant.EPSILON * 100.0;

            r = 0;
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
                Rcont2(1, nrow, ncol, nrowt, ncolt, ref primed, ref x, ref fact, ref ntotal, ref maxtot, ref jwork, out ierror, ref rng);
                if (ierror != 0)
                    throw new InvalidDataException("Monte Carlo simulation not possible: all row and column totals must be be greater than zero");
                double x2Rep = Chi2Trend(x, wt, nrow);
                if (x2Rep > x2 || Math.Abs(x2Rep - x2) < tol)
                    r += 1;
            }
            actualIterations = i - 1;
        }

        private static double Chi2Trend(int[,] x, double[] wt, int rows)
        {
            double a = 0, b = 0, t = 0, k1 = 0, k2 = 0, k4 = 0;
            for (int r = 1; r <= rows; r++)
            {
                double a1 = x[r, 1];
                double b1 = x[r, 2];
                double s1 = wt[r];
                a += a1;
                b += b1;
                double t1 = a1 + b1;
                if (t1 <= 0.0)
                {
                    return 0.0;
                }
                t += t1;
                k1 += s1 * a1;
                k2 += s1 * b1;
                k4 += s1 * s1 * (a1 + b1);
            }

            double k8 = b / a;
            double d = (k4 - Math.Pow(k1 + k2, 2.0) / t) / k8;
            if (d < 0)
            {
                d = 0;
            }
            d = Math.Sqrt(d);
            double x1 = (k1 - k2 / k8) / d;

            return x1 * x1;
        }

        ///  <summary>
        ///  Simulated exact P for R by C chi-square for independent, for trend, for equality and g-square
        ///  </summary>
        ///  <param name="host"></param>
        ///  <param name="o">(1..nrow,1..ncol) input 2 by k table</param>
        ///  <param name="rowScore">(1..nrow) row scores for trend test</param>
        ///  <param name="colScore">(1..nrow) column scores for trend test</param>
        ///  <param name="nrow">rows</param>
        ///  <param name="ncol">columns</param>
        ///  <param name="iter">Monte Carlo iterations</param>
        ///  <param name="x2">chi-square for independence</param>
        ///  <param name="rx2">Monte Carlo P numerator for independece chi-square</param>
        ///  <param name="x2Eq">chi-square for equality</param>
        ///  <param name="rx2Eq">Monte Carlo P numerator for equality chi-square</param>
        ///  <param name="x2Trend">chi-square for trend</param>
        ///  <param name="rx2Trend">Monte Carlo P numerator for trend chi-square</param>
        ///  <param name="g2">chi-square for g-square</param>
        ///  <param name="rg2">Monte Carlo P numerator for g-square</param>
        ///  <param name="actualIterations">The number of Monte Carlo iterations actually performed</param>
        ///  <param name="iseed">RNG seed (0 for automatic)</param>
        ///  <param name="ierror">return non-zero if fault (-1 if interrupted)</param>
        public static void ChiRCResample(IProgressBarHost host, double[,] o, double[] rowScore, double[] colScore, int nrow, int ncol, int iter, double x2, out int rx2, double x2Eq, out int rx2Eq, double x2Trend, out int rx2Trend, double g2, out int rg2, out int actualIterations, int iseed, ref int ierror)
        {
            int[] ncolt = new int[ncol + 1];
            int[] nrowt = new int[nrow + 1];
            int[,] x = new int[nrow + 1, ncol + 1];
            int ntotal = 0;
            int i;
            int j;
            MersenneTwister rng = new();

            int bootsDivisor = Math.Max(1, iter / 1000);

            using IProgressBar progress = host.StartProgress("Simulating exact P", true);

            if (iseed != 0)
            {
                rng.Seed(iseed);
            }
            else { rng.Seed(); }

            for (j = 1; j <= nrow; j++)
            {
                for (i = 1; i <= ncol; i++)
                {
                    x[j, i] = Convert.ToInt32(o[j, i]);
                    nrowt[j] += x[j, i];
                    ncolt[i] += x[j, i];
                }
            }

            int maxtot = 5000000;
            bool primed = false;

            double[] fact = new double[ncol + 1];
            int[] jwork = new int[ncol + 1];

            rx2 = 0;
            rg2 = 0;
            rx2Eq = 0;
            rx2Trend = 0;
            const double tol = Constant.EPSILON * 100.0;
            actualIterations = 0;

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
                Rcont2(1, nrow, ncol, nrowt, ncolt, ref primed, ref x, ref fact, ref ntotal, ref maxtot, ref jwork, out ierror, ref rng);
                if (ierror != 0)
                    throw new InvalidDataException("Monte Carlo simulation not possible: all row and column totals must be be greater than zero");
                ChiRC(x, nrow, ncol, rowScore, colScore, out double x2rep, out double x2Trendrep, out double x2Eqrep, out double g2rep, out bool faultrep);
                if (!faultrep)
                {
                    actualIterations++;
                    if (x2rep > x2 || Math.Abs(x2rep - x2) < tol)
                        rx2++;
                    if (g2rep > g2 || Math.Abs(g2rep - g2) < tol)
                        rg2++;
                    if (x2Eqrep > x2Eq || Math.Abs(x2Eqrep - x2Eq) < tol)
                        rx2Eq++;
                    if (x2Trendrep >= x2Trend || Math.Abs(x2Trendrep - x2Trend) < tol)
                        rx2Trend++;
                }
            }
        }

        public static ParameterBag MCResults(int ierror, int r, int its, int seed, double cco)
        {
            if (ierror == 0 || ierror == -1 /* interrupted but partial results returned */ )
            {
                ParameterBag outputParameters = new();
                double p = r / (double)its;
                MathDbl.binci(r, its, out double ll, out double ul, cco, out string warn);
                outputParameters.AddOutput(new Dictionary<string, object>
                {
                    { "p", p },
                    { "pc", 100.0 * cco },
                    { "ll", ll },
                    { "ul", ul },
                    { "warn", warn },
                    { "its", its },
                    { "seed", seed }
                });
                return outputParameters;
            }
            else
                return null;
        }

        private static void ChiRC(int[,] x, int rows, int cols, double[] rowscore, double[] colscore, out double x2, out double x2trend, out double x2eq, out double g2, out bool fault)
        {
            double gtot = 0;
            double sumWeighted = 0;
            double[] rtot = new double[rows + 1];
            double[] ctot = new double[cols + 1];
            for (int r = 1; r <= rows; r++)
            {
                for (int c = 1; c <= cols; c++)
                {
                    rtot[r] += x[r, c];
                    ctot[c] += x[r, c];
                    gtot += x[r, c];
                    sumWeighted += x[r, c] * rowscore[r] * colscore[c];
                }
            }

            fault = false;
            x2 = 0.0;
            g2 = 0.0;
            x2trend = 0.0;
            x2eq = 0.0;
            if (gtot < 1)
            {
                fault = true;
                return;
            }

            double sumWtCol = 0.0;
            double sumWtSqCol = 0.0;
            int nzCols = 0;
            for (int c = 1; c <= cols; c++)
            {
                sumWtCol += ctot[c] * colscore[c];
                sumWtSqCol += ctot[c] * colscore[c] * colscore[c];
                if (ctot[c] > 0.0)
                    nzCols++;
            }

            double sumWtRow = 0.0;
            double sumWtSqRow = 0.0;
            int nzRows = 0;
            for (int r = 1; r <= rows; r++)
            {
                sumWtRow += rtot[r] * rowscore[r];
                sumWtSqRow += rtot[r] * rowscore[r] * rowscore[r];
                if (rtot[r] > 0.0)
                    nzRows++;
            }

            double dsrs = 0.0;
            for (int c = 1; c <= cols; c++)
            {
                double xi = 0.0;
                for (int r = 1; r <= rows; r++)
                {
                    xi += rowscore[r] * x[r, c];
                    double ef = rtot[r] * ctot[c] / gtot;
                    if (ef != 0.0)
                    {
                        x2 += Math.Pow(x[r, c] - ef, 2.0) / ef;
                        if (x[r, c] != 0)
                            g2 += x[r, c] * Math.Log(x[r, c] / ef);
                    }
                }
                if (ctot[c] != 0.0)
                    dsrs += xi * xi / ctot[c];
            }

            //  ANOVA style equality of variance test
            double sxx = sumWtSqRow - sumWtRow * sumWtRow / gtot;
            x2eq = (gtot - 1.0) / sxx * (dsrs - sumWtRow * sumWtRow / gtot);

            //  Chi-square for linear trend
            double syy = sumWtSqCol - sumWtCol * sumWtCol / gtot;
            double sxy = sumWeighted - sumWtCol * sumWtRow / gtot;
            x2trend = (gtot - 1.0) * (sxy * sxy) / (sxx * syy);

            // Chi-square and G-square for independence
            g2 = 2.0 * g2;
        }

        ///  <remarks>
        ///     WM Patefield,
        ///     Algorithm AS 159:
        ///     An Efficient Method of Generating RXC Tables with Given Row and Column Totals,
        ///     Applied Statistics, Volume 30, Number 1, 1981, pages 91-97.
        ///  </remarks>
        ///  <param name="lowerBound">0 for 0-based arrays (indices 0..nrow-1, 0..ncol-1); 1 for 1-based arrays (indices 1..nrow, 1..ncol).</param>
        /// <param name="matrix"></param>
        /// <param name="fact">1..(nrow+ncol) to store log-factorials</param>
        /// <param name="nrow"></param>
        /// <param name="ncol"></param>
        /// <param name="nrowt"></param>
        /// <param name="ncolt"></param>
        /// <param name="primed"></param>
        /// <param name="ntotal"></param>
        /// <param name="maxtot"></param>
        /// <param name="jwork"></param>
        /// <param name="ierror"></param>
        /// <param name="rng"></param>
        public static void Rcont2(int lowerBound, int nrow, int ncol, int[] nrowt, int[] ncolt, ref bool primed, ref int[,] matrix, ref double[] fact, ref int ntotal, ref int maxtot, ref int[] jwork, out int ierror, ref MersenneTwister rng)
        {
            ierror = 0;

            //   On user's signal, set up the factorial table.
            if (primed == false)
            {
                primed = true;
                if (nrow <= 1)
                {
                    ierror = 1;
                    return;
                }
                if (ncol <= 1)
                {
                    ierror = 2;
                    return;
                }
                for (int i = lowerBound; i < nrow + lowerBound; i++)
                {
                    if (nrowt[i] <= 0)
                    {
                        ierror = 3;
                        return;
                    }
                }
                for (int j = lowerBound; j < ncol + lowerBound; j++)
                {
                    if (ncolt[j] <= 0)
                    {
                        ierror = 4;
                        return;
                    }
                }
                int ncolsum = 0;
                int nrowsum = 0;
                for (int i = lowerBound; i < nrow + lowerBound; i++)
                    nrowsum += nrowt[i];
                for (int j = lowerBound; j < ncol + lowerBound; j++)
                    ncolsum += ncolt[j];
                if (ncolsum != nrowsum)
                {
                    ierror = 6;
                    return;
                }
                ntotal = nrowsum;
                if (maxtot < ntotal)
                {
                    ierror = 5;
                    return;
                }
                fact = new double[ntotal + 2];
                //   Calculate log-factorials.
                double x = 0.0;
                fact[1] = 0.0;
                for (int i = 1; i <= ntotal; i++)
                {
                    x += Math.Log(i);
                    fact[i + 1] = x;
                }
            }

            //   Construct a random matrix.

            for (int j = lowerBound; j <= ncol - 2 + lowerBound; j++)
                jwork[j] = ncolt[j];

            int jc = ntotal;
            int ib = 0;

            for (int l = lowerBound; l <= nrow - 2 + lowerBound; l++)
            {

                int nrowtl = nrowt[l];
                int ia = nrowtl;
                int ic = jc;
                jc -= nrowtl;

                for (int m = lowerBound; m <= ncol - 2 + lowerBound; m++)
                {

                    int id = jwork[m];
                    int ie = ic;
                    ic -= id;
                    ib = ie - ia;
                    int ii = ib - id;

                    //   Test for zero entries in matrix.

                    if (ie == 0)
                    {
                        ia = 0;
                        for (int j = lowerBound; j < ncol + lowerBound; j++)
                            matrix[l, j] = 0;
                        break;
                    }

                    //   Generate a pseudo-random number.
                    double r = rng.NextDouble();

                    //   Compute the conditional expected value of MATRIX(L,M).

                    bool done1 = false;
                    bool done2 = false;

                    int nlm;
                    do
                    {
                        nlm = (int)Math.Floor(Convert.ToDouble(ia * id) / Convert.ToDouble(ie) + 0.5);

                        int iap = ia + 1;
                        int idp = id + 1;
                        int igp = idp - nlm;
                        int ihp = iap - nlm;
                        int nlmp = nlm + 1;
                        int iip = ii + nlmp;
                        double x = Math.Exp(fact[iap] + fact[ib + 1] + fact[ic + 1] + fact[idp] - fact[ie + 1] - fact[nlmp] - fact[igp] - fact[ihp] - fact[iip]);

                        if (r <= x)
                            break;

                        double sumprb = x;
                        double y = x;
                        int nll = nlm;
                        bool lsp = false;
                        bool lsm = false;

                        //   Increment entry in row L, column M.

                        while (lsp == false)
                        {

                            int j = (id - nlm) * (ia - nlm);

                            if (j == 0)
                                lsp = true;
                            else
                            {

                                nlm += 1;
                                x *= Convert.ToDouble(j) / Convert.ToDouble(nlm * (ii + nlm));
                                sumprb += x;

                                if (r <= sumprb)
                                {
                                    done1 = true;
                                    break;
                                }

                            }

                            done2 = false;

                            while (lsm == false)
                            {

                                //   Decrement the entry in row L, column M.

                                j = nll * (ii + nll);

                                if (j == 0)
                                {
                                    lsm = true;
                                    break;
                                }

                                nll -= 1;
                                y *= Convert.ToDouble(j) / Convert.ToDouble((id - nll) * (ia - nll));
                                sumprb += y;

                                if (r <= sumprb)
                                {
                                    nlm = nll;
                                    done2 = true;
                                    break;
                                }

                                if (lsp == false)
                                    break;
                            }

                            if (done2)
                                break;
                        }

                        if (done1 || done2)
                            break;

                        r = rng.NextDouble();
                        r = sumprb * r;

                    }
                    while (true);

                    matrix[l, m] = nlm;
                    ia -= nlm;
                    jwork[m] -= nlm;

                }

                matrix[l, ncol - 1 + lowerBound] = ia;
            }

            //   Compute the last row.
            for (int m = lowerBound; m <= ncol - 2 + lowerBound; m++)
                matrix[nrow - 1 + lowerBound, m] = jwork[m];
            matrix[nrow - 1 + lowerBound, ncol - 1 + lowerBound] = ib - matrix[nrow - 1 + lowerBound, ncol - 2 + lowerBound];
        }
    }
}
