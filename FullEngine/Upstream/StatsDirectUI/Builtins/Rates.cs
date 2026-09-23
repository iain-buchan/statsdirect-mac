using System;
using System.Collections.Generic;
using StatsDirect.Charting;
using StatsDirect.Data;
using StatsDirect.Numerics;
using StatsDirect.Templates;
using StatsDirect.Utilities;

namespace StatsDirect.Builtins
{
    public static class Rates
    {

        ///  <summary>
        ///  relates chi-sq to Poisson
        ///  </summary>
        ///  <param name="alpha"></param>
        ///  <param name="events"></param>
        ///  <param name="tar"></param>
        ///  <param name="xl"></param>
        ///  <param name="xu"></param>
        ///  <remarks>Johnson &amp; Kotz 1969, Ulm in Am J Epidemiol 1990 (131) 373-
        ///  comments by Dobson Stats in Med 1991 (10) 457-</remarks>
        public static void poisson_ci(double alpha, double events, double tar, out double xl, out double xu)
        {
            int fault;
            if (events < 0.0)
            {
                xl = Constant.MISSING;
                xu = Constant.MISSING;
            }
            else if (events == 0.0)
            {
                xl = 0.0;
                xu = PDF.ppchi2(1.0 - alpha / 2.0, 2.0, out fault) / 2.0;
                if (fault != 0)
                    xu = Constant.MISSING;
                else
                    xu /= tar;
            }
            else
            {
                xl = PDF.ppchi2(alpha / 2.0, 2.0 * events, out fault) / 2.0;
                if (fault != 0)
                    xl = Constant.MISSING;
                else
                    xl /= tar;
                xu = PDF.ppchi2(1.0 - alpha / 2.0, 2.0 * (events + 1.0), out fault) / 2.0;
                if (fault != 0)
                    xu = Constant.MISSING;
                else
                    xu /= tar;
            }
        }

        public static StepOutput RptRateSmr(ParameterBag parameters)
        {
            double cco = parameters["cco"].AsDouble;
            if (cco > 1.0 || cco < 0.0)
                cco = 0.95;

            DataFrame ratesFrame = parameters["rates"].AsDataFrame;
            DoubleVariable ratesVariable = (DoubleVariable) ratesFrame.Variables[0];
            DataFrame timesFrame = parameters["times"].AsDataFrame;
            DoubleVariable timesVariable = (DoubleVariable) timesFrame.Variables[0];
            int rawRows = ratesVariable.Length;

            DoubleArraysAndBooleans copiesRemovingMissingRows = Numerics.Utilities.RemoveMissingRows(new[] { ratesVariable.Data, timesVariable.Data }, 0, rawRows, 1);
            double[] asm = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[0];
            double[] spop = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[1];

            double nunit = Parsing.Cdbl_Txt(parameters["nunit"].AsString);
            if (nunit <= 0.0)
                nunit = 1.0;
            int rows = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[0].Length - 1; /* 1-based */
            for (int i = 1; i <= rows; i++)
                asm[i] /= nunit;

            double etot = 0.0;
            for (int i = 1; i <= rows; i++)
                etot += asm[i] * spop[i];
            if (etot <= 0)
                throw new InvalidDataException();

            string[] title = Meta.MakeTitles(parameters, "strata", "stratum {0}", rawRows, out bool hasUserSuppliedLabels);

            title = Numerics.Utilities.CopyValidRows(title, copiesRemovingMissingRows.ValidRowsInOriginal, 0, rawRows, 1, rows);

            double dead = parameters["dead"].AsDouble;

            ParameterBag outputParameters = new();
            List<ParameterBag> groupsList = new();
            outputParameters.AddOutput("*groups", groupsList);
            for (int j = 1; j <= rows; j++)
            {
                ParameterBag groupsParameters = new();
                groupsList.Add(groupsParameters);
                groupsParameters.AddOutput("group", asm[j]);
                groupsParameters.AddOutput("observed", spop[j]);
                groupsParameters.AddOutput("expected", spop[j] * asm[j]);
                groupsParameters.AddOutput("lb", hasUserSuppliedLabels ? title[j] : string.Empty);
            }
            outputParameters.AddOutput("total", etot);

            PDF.gauinv(cco + (1.0 - cco) / 2.0, out int fault);
            if (fault == 0)
            {
                outputParameters.AddOutput("ratio", dead / etot);
                outputParameters.AddOutput("smr", dead / etot * 100);

                poisson_ci(1.0 - cco, dead, 1.0, out double xl, out double xu);

                if (xl != Constant.MISSING)
                    xl /= etot;
                if (xu != Constant.MISSING)
                    xu /= etot;
                outputParameters.AddOutput("pc", 100 * cco);
                outputParameters.AddOutput("from", xl);
                outputParameters.AddOutput("to", xu);
                outputParameters.AddOutput("from100", Convert.ToInt32(100 * xl));
                outputParameters.AddOutput("to100", Convert.ToInt32(100 * xu));

                ExFortran.poisson(etot, Convert.ToInt32(dead), out double phi, out double plo, out double _, out fault);
                if (fault != 0)
                    phi = Constant.MISSING;

                outputParameters.AddOutput("qty", Convert.ToInt64(dead));
                outputParameters.AddOutput("p_hi", phi);
                outputParameters.AddOutput("p_lo", plo);
            }
            return new StepOutput(outputParameters);
        }


        public static StepOutput RptRateDirect(ParameterBag parameters)
        {
            double cco = parameters["cco"].AsDouble;
            if (cco > 1.0 || cco < 0.0)
                cco = 0.95;
            double alpha = 1.0 - cco;

            DataFrame idxnFrame = parameters["idxn"].AsDataFrame;
            DoubleVariable idxnVariable = (DoubleVariable) idxnFrame.Variables[0];
            DataFrame timesFrame = parameters["times"].AsDataFrame;
            DoubleVariable timesVariable = (DoubleVariable) timesFrame.Variables[0];
            DataFrame refnFrame = parameters["refn"].AsDataFrame;
            DoubleVariable refnVariable = (DoubleVariable) refnFrame.Variables[0];
            int rawRows = idxnVariable.Length;


            DoubleArraysAndBooleans copiesRemovingMissingRows = Numerics.Utilities.RemoveMissingRows(new[] { idxnVariable.Data, timesVariable.Data, refnVariable.Data }, 0, rawRows, 1);
            double[] idxy = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[0];
            double[] idxn = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[1];
            double[] refn = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[2];

            int rows = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[0].Length - 1; /* 1-based */

            double events = 0.0;
            for (int i = 1; i <= rows; i++)
                events += idxy[i];
            double ntot = 0.0;
            for (int i = 1; i <= rows; i++)
            {
                ntot += idxn[i];
                if (idxy[i] > idxn[i])
                    throw new InvalidDataException("Number of events must be greater then person-time, do not scale person-time");
            }
            double refntot = 0.0;
            for (int i = 1; i <= rows; i++)
                refntot += refn[i];

            string[] title = Meta.MakeTitles(parameters, "strata", "stratum {0}", rawRows, out bool _);
            title = Numerics.Utilities.CopyValidRows(title, copiesRemovingMissingRows.ValidRowsInOriginal, 0, rawRows, 1, rows);

            double nunit = Parsing.Cdbl_Txt(parameters["nunit"].AsString);
            if (refntot <= 0.0 || ntot <= 0.0)
                throw new InvalidDataException();

            ParameterBag outputParameters = new();
            double[] refw = new double[rows + 1];
            for (int j = 1; j <= rows; j++)
                refw[j] = refn[j] / refntot;
            double stdr = 0.0;
            double pois_var = 0.0;
            double bino_var = 0.0;
            double[] idxr = new double[rows + 1];
            for (int j = 1; j <= rows; j++)
            {
                idxr[j] = idxy[j] / idxn[j];
                stdr += idxr[j] * refn[j];
                pois_var += refn[j] * refn[j] * idxr[j] / idxn[j];
                bino_var += refn[j] * refn[j] * idxr[j] * (1.0 - idxr[j]) / idxn[j];
            }
            stdr /= refntot;
            pois_var /= (refntot * refntot);
            bino_var /= (refntot * refntot);
            if (nunit == 1.0)
                outputParameters.AddOutput("units", "1 unit");
            else
                outputParameters.AddOutput("units", nunit.ToString("#,##0") + " units");
            List<ParameterBag> inputsList = new();
            outputParameters.AddOutput("*inputs", inputsList);
            for (int j = 1; j <= rows; j++)
            {
                ParameterBag inputsParameters = new();
                inputsList.Add(inputsParameters);
                inputsParameters.AddOutput("idxy", idxy[j]);
                inputsParameters.AddOutput("idxn", idxn[j]);
                inputsParameters.AddOutput("idxr", idxr[j] * nunit);
                inputsParameters.AddOutput("refn", refn[j]);
                inputsParameters.AddOutput("refw", refw[j]);
            }
            double xu; double xl;
            // CIs for the single Poisson parameter (stratum specific rate)
            outputParameters.AddOutput("pc", cco * 100.0);
            List<ParameterBag> cisList = new();
            outputParameters.AddOutput("*cis", cisList);
            for (int j = 1; j <= rows; j++)
            {
                ParameterBag cisParameters = new();
                cisList.Add(cisParameters);
                cisParameters.AddOutput("idxr", idxr[j] * nunit);
                poisson_ci(alpha, idxy[j], idxn[j], out xl, out xu);
                cisParameters.AddOutput("from", xl * nunit);
                cisParameters.AddOutput("to", xu * nunit);
                cisParameters.AddOutput("label", title[j]);
            }

            // pooled
            outputParameters.AddOutput("events", events);
            outputParameters.AddOutput("stde", stdr * ntot);

            outputParameters.AddOutput("crude", nunit * events / ntot);
            outputParameters.AddOutput("stdr", nunit * stdr);
            double cit = PDF.gauinv(cco + (1.0 - cco) / 2.0);

            // Binomial approx CI - see Armitage
            double ser = bino_var > 0.0 ? Math.Sqrt(bino_var) : Constant.MISSING;
            outputParameters.AddOutput("ser_any", nunit * ser);
            xl = stdr - cit * ser;
            xu = stdr + cit * ser;
            outputParameters.AddOutput("from_any", nunit * xl);
            outputParameters.AddOutput("to_any", nunit * xu);

            // Poisson approx CI
            ser = pois_var > 0.0 ? Math.Sqrt(pois_var) : Constant.MISSING;
            outputParameters.AddOutput("ser_small", nunit * ser);

            xl = stdr - cit * ser;
            xu = stdr + cit * ser;
            outputParameters.AddOutput("from_small", nunit * xl);
            outputParameters.AddOutput("to_small", nunit * xu);

            // Dobson et al. improved approx Poisson CI - Stats in Medicine 1991 (10)457
            poisson_ci(alpha, events, 1.0, out xl, out xu);
            if (xl != Constant.MISSING && pois_var >= 0.0 && events > 0.0)
                xl = stdr + Math.Sqrt(pois_var / events) * (xl - events);
            else
                xl = Constant.MISSING;
            if (xu != Constant.MISSING && pois_var >= 0.0 && events > 0.0)
                xu = stdr + Math.Sqrt(pois_var / events) * (xu - events);
            else
                xu = Constant.MISSING;
            outputParameters.AddOutput("from_dobson", nunit * xl);
            outputParameters.AddOutput("to_dobson", nunit * xu);

            return new StepOutput(outputParameters);
        }

        public static StepOutput RptStdrr(ParameterBag parameters)
        {
            double cco = parameters["cco"].AsDouble;
            if (cco <= 0)
                cco = 0.95;
            double cit = PDF.gauinv(1.0 - (1.0 - cco) / 2.0);

            DataFrame aFrame = parameters["a"].AsDataFrame;
            DoubleVariable aVariable = (DoubleVariable) aFrame.Variables[0];
            int rawRows = aVariable.Length;
            DataFrame pt1Frame = parameters["pt1"].AsDataFrame;
            DoubleVariable pt1Variable = (DoubleVariable) pt1Frame.Variables[0];
            DataFrame bFrame = parameters["b"].AsDataFrame;
            DoubleVariable bVariable = (DoubleVariable) bFrame.Variables[0];
            DataFrame pt2Frame = parameters["pt2"].AsDataFrame;
            DoubleVariable pt2Variable = (DoubleVariable) pt2Frame.Variables[0];
            DataFrame refFrame = parameters["ref"].AsDataFrame;
            DoubleVariable refVariable = (DoubleVariable) refFrame.Variables[0];

            DoubleArraysAndBooleans copiesRemovingMissingRows = Numerics.Utilities.RemoveMissingRows(new[] { aVariable.Data, pt1Variable.Data, bVariable.Data, pt2Variable.Data, refVariable.Data }, 0, rawRows, 1);
            double[] a = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[0];
            double[] pt1 = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[1];
            double[] b = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[2];
            double[] pt2 = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[3];
            double[] refIdent = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[4];

            string[] title = Meta.MakeTitles(parameters, "strata", "stratum {0}", rawRows, out bool hasUserSuppliedLabels);

            int k = copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[0].Length - 1; /* 1-based */
            title = Numerics.Utilities.CopyValidRows(title, copiesRemovingMissingRows.ValidRowsInOriginal, 0, rawRows, 1, k, 2);

            string modelString = parameters["model"].AsString;
            int model = "poisson".Equals(modelString) ? 1 : 2;

            double nunit = Parsing.Cdbl_Txt(parameters["nunit"].AsString);
            if (nunit <= 0.0)
                nunit = 1.0;

            double[] rkr = new double[k + 3];
            double[] rkw = new double[k + 3];
            double[] rkrl = new double[k + 3];
            double[] rkru = new double[k + 3];
            bool[] lerr = new bool[k + 3];
            bool[] uerr = new bool[k + 3];
            // ierr = -1; 

            double refsum = 0.0;
            double asum = 0.0;
            double bsum = 0.0;
            double pt1Sum = 0.0;
            double pt2Sum = 0.0;
            for (int i = 1; i <= k; i++)
            {
                refsum += refIdent[i];
                asum += a[i];
                bsum += b[i];
                pt1Sum += pt1[i];
                pt2Sum += pt2[i];
            }

            double alpha = 1.0 - cco;
            if (alpha <= 0.0 || alpha >= 1.0)
                alpha = 0.05;
            double p = cco + (1.0 - cco) / 2.0;

            double cre = asum / pt1Sum;
            double crne = bsum / pt2Sum;
            string warn1;
            string warn2;
            double crneu; double crnel; double creu; double crel;

            if (model == 1)
            {
                // Poisson rate CI
                poisson_ci(alpha, asum, pt1Sum, out crel, out creu);
                poisson_ci(alpha, bsum, pt2Sum, out crnel, out crneu);
                warn1 = string.Empty;
                warn2 = string.Empty;
            }
            else
            {
                // Binomial like single proportion
                MathDbl.binci(asum, pt1Sum, out crel, out creu, cco, out warn1);
                MathDbl.binci(bsum, pt2Sum, out crnel, out crneu, cco, out warn2);
            }

            double crr;
            if (crne != 0.0)
                crr = cre / crne;
            else
                crr = Constant.MISSING;
            double crru; double f; double crrl;
            if (model == 1)
            {
                // Poisson
                if (asum == 0.0)
                {
                    crrl = 0.0;
                }
                else
                {
                    f = PDF.ffromp(2.0 * asum, 2.0 * (bsum + 1.0), 1.0 - p);
                    crrl = pt2Sum / pt1Sum * (asum / (bsum + 1.0)) * (1.0 / f);
                }
                if (bsum == 0.0)
                {
                    crru = Constant.MISSING;
                    crr = Constant.MISSING;
                }
                else
                {
                    f = PDF.ffromp(2.0 * bsum, 2.0 * (asum + 1.0), 1.0 - p);
                    crru = pt2Sum / pt1Sum * ((asum + 1.0) / bsum) * f;
                }
            }
            else
            {
                // Binomial like relative risk
                MathDbl.lr_ci(bsum, asum, pt2Sum, pt1Sum, cit, out crrl, out crru);
            }

            rkr[k + 1] = crr;
            rkrl[k + 1] = crrl;
            rkru[k + 1] = crru;
            rkw[k + 1] = 1.0;
            title[k + 1] = "All (crude)";

            double sre = 0.0;
            double srne = 0.0;
            double vsre = 0.0;
            double vsrne = 0.0;
            double vsre_bino = 0.0;
            double vsrne_bino = 0.0;
            int realk = 0;

            for (int i = 1; i <= k; i++)
            {
                // rr and ci for stratum
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
                    realk += 1;
                    double ir1 = a[i] / pt1[i];
                    double ir2 = b[i] / pt2[i];
                    if (ir2 != 0.0)
                        rkr[i] = ir1 / ir2;
                    else
                        rkr[i] = Constant.MISSING;
                    if (model == 1)
                    {
                        // Poisson
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
                        }
                    }
                    else
                    {
                        // Binomial like relative risk
                        MathDbl.lr_ci(b[i], a[i], pt2[i], pt1[i], cit, out rkrl[i], out rkru[i]);
                    }
                }
                // pooled
                if (refIdent[i] != 0.0)
                {
                    rkw[i] = refIdent[i] / refsum;
                    double pa = a[i] / pt1[i];
                    double qa = 1.0 - pa;
                    sre += refIdent[i] * pa;
                    vsre += rkw[i] * rkw[i] * (a[i] / (pt1[i] * pt1[i]));
                    vsre_bino += rkw[i] * rkw[i] * pa * qa / pt1[i];
                    double pb = b[i] / pt2[i];
                    double qb = 1.0 - pb;
                    srne += refIdent[i] * pb;
                    vsrne += rkw[i] * rkw[i] * (b[i] / (pt2[i] * pt2[i]));
                    vsrne_bino += rkw[i] * rkw[i] * pb * qb / pt2[i];
                }
            }
            sre /= refsum;
            srne /= refsum;

            double sreu_bino; double srel_bino; double sreu; double srel;
            if (vsre < 0.0)
            {
                srel = Constant.MISSING;
                sreu = Constant.MISSING;
            }
            else
            {
                srel = sre - cit * Math.Sqrt(vsre);
                sreu = sre + cit * Math.Sqrt(vsre);
            }

            if (vsre_bino < 0.0)
            {
                srel_bino = Constant.MISSING;
                sreu_bino = Constant.MISSING;
            }
            else
            {
                srel_bino = sre - cit * Math.Sqrt(vsre_bino);
                sreu_bino = sre + cit * Math.Sqrt(vsre_bino);
            }

            double srneu_bino; double srnel_bino; double srneu; double srnel;
            if (vsrne < 0.0)
            {
                srnel = Constant.MISSING;
                srneu = Constant.MISSING;
            }
            else
            {
                srnel = srne - cit * Math.Sqrt(vsrne);
                srneu = srne + cit * Math.Sqrt(vsrne);
            }

            if (vsrne_bino < 0.0)
            {
                srnel_bino = Constant.MISSING;
                srneu_bino = Constant.MISSING;
            }
            else
            {
                srnel_bino = srne - cit * Math.Sqrt(vsrne_bino);
                srneu_bino = srne + cit * Math.Sqrt(vsrne_bino);
            }

            double srru_bino; double srrl_bino;
            double srru; double srrl;
            double srr;
            if (srne != 0.0)
            {
                srr = sre / srne;
                double vsrr = vsre / (sre * sre) + vsrne / (srne * srne);
                double vsrr_bino = vsre_bino / (sre * sre) + vsrne_bino / (srne * srne);
                srrl = Math.Exp(Math.Log(srr) - cit * Math.Sqrt(vsrr));
                srru = Math.Exp(Math.Log(srr) + cit * Math.Sqrt(vsrr));
                double dtmp;
                if (srrl > srru)
                {
                    dtmp = srrl;
                    srrl = srru;
                    srru = dtmp;
                }
                srrl_bino = Math.Exp(Math.Log(srr) - cit * Math.Sqrt(vsrr_bino));
                srru_bino = Math.Exp(Math.Log(srr) + cit * Math.Sqrt(vsrr_bino));
                if (srrl_bino > srru_bino)
                {
                    dtmp = srrl_bino;
                    srrl_bino = srru_bino;
                    srru_bino = dtmp;
                }
            }
            else
            {
                srr = Constant.MISSING;
                srrl = Constant.MISSING;
                srru = Constant.MISSING;
                srrl_bino = Constant.MISSING;
                srru_bino = Constant.MISSING;
            }

            ParameterBag outputParameters = new();
            List<ParameterBag> strataList = new();
            outputParameters.AddOutput("*strata", strataList);
            for (int i = 1; i <= k; i++)
            {
                ParameterBag strataParameters = new();
                strataList.Add(strataParameters);
                strataParameters.AddOutput("st", i);
                strataParameters.AddOutput("a", a[i]);
                strataParameters.AddOutput("pt1", pt1[i]);
                strataParameters.AddOutput("b", b[i]);
                strataParameters.AddOutput("pt2", pt2[i]);
                strataParameters.AddOutput("lb", hasUserSuppliedLabels ? title[i] : string.Empty);
            }
            outputParameters.AddOutput("pc", cco * 100.0);
            string meth = model == 1 ? "exact Poisson" : "Koopman";
            outputParameters.AddOutput("method", meth);
            List<ParameterBag> ratesList = new();
            outputParameters.AddOutput("*rates", ratesList);
            for (int i = 1; i <= k + 1; i++)
            {
                ParameterBag ratesParameters = new();
                ratesList.Add(ratesParameters);
                ratesParameters.AddOutput("st", i <= k ? i.ToString() : "All");
                ratesParameters.AddOutput("rr", rkr[i]);
                ratesParameters.AddOutput("lci", rkrl[i]);
                ratesParameters.AddOutput("uci", rkru[i]);
                ratesParameters.AddOutput("wt", rkw[i]);
                ratesParameters.AddOutput("lb", hasUserSuppliedLabels ? title[i] : string.Empty);
            }

            outputParameters.AddOutput("model_out", model == 1 ? "Poisson (small rates)" : "Binomial");
            if (nunit == 1.0)
                outputParameters.AddOutput("units", "1 unit");
            else
                outputParameters.AddOutput("units", nunit.ToString("#,##0") + " units");

            outputParameters.AddOutput("cre", cre * nunit);
            outputParameters.AddOutput("cre_from", crel * nunit);
            outputParameters.AddOutput("cre_to", creu * nunit);
            outputParameters.AddOutput("cre_warn", warn1);

            outputParameters.AddOutput("crne", crne * nunit);
            outputParameters.AddOutput("crne_from", crnel * nunit);
            outputParameters.AddOutput("crne_to", crneu * nunit);
            outputParameters.AddOutput("crne_warn", warn2);

            outputParameters.AddOutput("sre", sre * nunit);
            if (model == 1)
            {
                outputParameters.AddOutput("sre_from", srel * nunit);
                outputParameters.AddOutput("sre_to", sreu * nunit);
            }
            else
            {
                outputParameters.AddOutput("sre_from", srel_bino * nunit);
                outputParameters.AddOutput("sre_to", sreu_bino * nunit);
            }

            outputParameters.AddOutput("srne", srne * nunit);
            if (model == 1)
            {
                outputParameters.AddOutput("srne_from", srnel * nunit);
                outputParameters.AddOutput("srne_to", srneu * nunit);
            }
            else
            {
                outputParameters.AddOutput("srne_from", srnel_bino * nunit);
                outputParameters.AddOutput("srne_to", srneu_bino * nunit);
            }

            outputParameters.AddOutput("srr", srr);
            if (model == 1)
            {
                outputParameters.AddOutput("srr_from", srrl);
                outputParameters.AddOutput("srr_to", srru);
            }
            else
            {
                outputParameters.AddOutput("srr_from", srrl_bino);
                outputParameters.AddOutput("srr_to", srru_bino);
            }

            CorrelationRowType[] pg = new CorrelationRowType[k + 2 + 1 /* VB to C# conversion */ ];
            pg[k + 1] = CorrelationRowType.Subgroup;
            pg[k + 2] = CorrelationRowType.Pooled;

            rkr[k + 2] = srr;
            rkrl[k + 2] = srrl;
            rkru[k + 2] = srru;
            rkw[k + 2] = Constant.MISSING;
            rkw[k + 1] = Constant.MISSING;
            title[k + 2] = "Standardized";

            IList<ParameterBag> chartList = new List<ParameterBag>();
            outputParameters.AddOutput("*chart", chartList);

            ParameterBag chartParameters = new();
            chartList.Add(chartParameters);
            chartParameters.AddOutput("chart", ChartRendererFactory.PrepForLater(ChartType.Correlation, new CorrelationOptions(k + 2, title, rkr, rkrl, rkru, rkw, pg, "Stratified rate ratio plot (direct standardization)", "rate ratio (" + Formatting.XRound(cco * 100, 1) + "% confidence interval)", Transformation.Log, false)));

            return new StepOutput(outputParameters);
        }
    }
}
