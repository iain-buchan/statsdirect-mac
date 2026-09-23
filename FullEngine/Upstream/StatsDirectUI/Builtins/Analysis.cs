using System;
using System.Collections.Generic;

using StatsDirect.Data;
using StatsDirect.Numerics;
using StatsDirect.Templates;
using StatsDirect.Utilities;
using static StatsDirect.Builtins.ExactBB;

namespace StatsDirect.Builtins
{
    public static class Analysis
    {
        public static StepOutput RptRateDirectStd(ParameterBag parameters)
        {
            DataFrame datFrame = parameters["data"].AsDataFrame;
            DoubleVariable datV0 = (DoubleVariable) datFrame.Variables[0];
            DoubleVariable datV1 = (DoubleVariable) datFrame.Variables[1];
            DoubleVariable datV2 = (DoubleVariable) datFrame.Variables[2];
            int rows = datFrame.MaxRows;
            double[] idxy = new double[rows + 1];
            double[] idxn = new double[rows + 1];
            double[] idxr = new double[rows + 1];
            double[] refn = new double[rows + 1];
            double[] refw = new double[rows + 1];

            double cco = parameters["cco"].AsDouble;
            if (cco > 1.0 || cco < 0.0)
                cco = 0.95;
            double alpha = 1.0 - cco;

            double nunit = Parsing.Cdbl_Txt(parameters["nunit"].AsString);
            if (nunit <= 0.0)
                nunit = 1.0;

            double refntot = 0.0;
            double revents = 0.0;
            double ntot = 0.0;
            for (int j = 1; j <= rows; j++)
            {
                double xy = datV0.Data[j - 1];
                idxy[j] = xy;
                revents += xy;
                double xn = datV1.Data[j - 1];
                if (xn <= 0.0)
                    throw new InvalidDataException();
                idxn[j] = xn;
                ntot += xn;
                double rf = datV2.Data[j - 1];
                refn[j] = rf;
                refntot += rf;
                if (xy > xn)
                    throw new InvalidDataException("Number of events must be greater then person-time, do not scale person-time");
            }

            if (refntot <= 0.0)
                throw new InvalidDataException("Total reference group size must be greater than zero");

            for (int j = 1; j <= rows; j++)
                refw[j] = refn[j] / refntot;

            double stdr = 0.0;
            double poisVar = 0.0;
            double binoVar = 0.0;
            for (int j = 1; j <= rows; j++)
            {
                idxr[j] = idxy[j] / idxn[j];
                stdr += idxr[j] * refn[j];
                poisVar += refn[j] * refn[j] * idxr[j] / idxn[j];
                binoVar += refn[j] * refn[j] * idxr[j] * (1.0 - idxr[j]) / idxn[j];
            }
            stdr /= refntot;
            poisVar /= (refntot * refntot);
            binoVar /= (refntot * refntot);

            ParameterBag outputParameters = new();
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

            // CIs for the single Poisson parameter (stratum specific rate)
            outputParameters.AddOutput("pc", cco * 100);
            List<ParameterBag> cisList = new();
            outputParameters.AddOutput("*cis", cisList);
            double xu;
            double xl;
            for (int j = 1; j <= rows; j++)
            {
                ParameterBag cisParameters = new();
                cisList.Add(cisParameters);
                cisParameters.AddOutput("idxr", idxr[j] * nunit);
                Rates.poisson_ci(alpha, idxy[j], idxn[j], out xl, out xu);
                cisParameters.AddOutput("from", xl * nunit);
                cisParameters.AddOutput("to", xu * nunit);
                cisParameters.AddOutput("label", string.Empty);
            }

            // pooled
            outputParameters.AddOutput("events", revents);
            outputParameters.AddOutput("stde", stdr * ntot);

            outputParameters.AddOutput("crude", revents * nunit / ntot);
            outputParameters.AddOutput("stdr", stdr * nunit);
            double cit = PDF.gauinv(cco + (1.0 - cco) / 2.0, out int fault);

            // Binomial approx CI - see Armitage
            double ser = binoVar > 0.0 ? Math.Sqrt(binoVar) : Constant.MISSING;
            outputParameters.AddOutput("ser_any", ser * nunit);

            if (fault != 0)
            {
                xl = Constant.MISSING;
                xu = Constant.MISSING;
            }
            else
            {
                xl = stdr - cit * ser;
                xu = stdr + cit * ser;
            }
            outputParameters.AddOutput("from_any", xl * nunit);
            outputParameters.AddOutput("to_any", xu * nunit);

            // Poisson approx CI
            ser = poisVar > 0.0 ? Math.Sqrt(poisVar) : Constant.MISSING;
            outputParameters.AddOutput("ser_small", ser * nunit);
            if (fault != 0)
            {
                xl = Constant.MISSING;
                xu = Constant.MISSING;
            }
            else
            {
                xl = stdr - cit * ser;
                xu = stdr + cit * ser;
            }
            outputParameters.AddOutput("from_small", xl * nunit);
            outputParameters.AddOutput("to_small", xu * nunit);

            // Dobson improved approx Poisson CI - Stats in Medicine 1991 (10) 457-
            Rates.poisson_ci(alpha, revents, 1.0, out xl, out xu);
            if (xl != Constant.MISSING & poisVar >= 0.0 & revents > 0.0)
                xl = stdr + Math.Sqrt(poisVar / revents) * (xl - revents);
            else
                xl = Constant.MISSING;
            if (xu != Constant.MISSING & poisVar >= 0.0 & revents > 0.0)
                xu = stdr + Math.Sqrt(poisVar / revents) * (xu - revents);
            else
                xu = Constant.MISSING;
            outputParameters.AddOutput("from_dobson", xl * nunit);
            outputParameters.AddOutput("to_dobson", xu * nunit);
            return new StepOutput(outputParameters);
        }

        public static StepOutput RptRateCompareTwo(ITemplateHost host, ParameterBag parameters)
        {
            double a = parameters["a"].AsDouble;
            double b = parameters["b"].AsDouble;
            double pt1 = parameters["pt1"].AsDouble;
            double pt2 = parameters["pt2"].AsDouble;
            bool doCml = parameters["do_cml"].AsBoolean;
            double pt = pt1 + pt2;
            double m = a + b;
            double gamma = parameters["gamma"].AsDouble;
            if (gamma <= 0.0 || gamma >= 1.0)
                gamma = 0.95;

            if (a + b <= 0.0 || pt1 <= 0.0 || pt2 <= 0.0)
                throw new InvalidDataException();

            double ir1 = a / pt1;
            double ir2 = b / pt2;
            double ird = ir1 - ir2;
            double xmh = (a - m * pt1 / pt) * (a - m * pt1 / pt) / (m * pt1 * pt2 / (pt * pt));
            double pxmh = PDF.chivalp(xmh, 1.0);

            double p = 1.0 - (1.0 - gamma) / 2.0;
            double z = PDF.gauinv(p, out int fault);

            double ird1, ird2;
            if (xmh == 0)
            {
                ird1 = Constant.MISSING;
                ird2 = Constant.MISSING;
            }
            else
            {
                ird1 = ird - z * Math.Sqrt(ird * ird / xmh);
                ird2 = ird + z * Math.Sqrt(ird * ird / xmh);
            }

            double irr0, irr1, irr2;
            if (a == 0.0)
            {
                irr1 = 0.0;
            }
            else
            {
                double f = PDF.ffromp(2.0 * a, 2.0 * (b + 1), 1.0 - p);
                irr1 = pt2 / pt1 * (a / (b + 1.0)) * (1.0 / f);
            }
            if (b == 0.0)
            {
                irr0 = Constant.MISSING;
                irr2 = Constant.MISSING;
            }
            else
            {
                irr0 = a / pt1 / (b / pt2);
                double f = PDF.ffromp(2.0 * b, 2.0 * (a + 1), 1.0 - p);
                irr2 = pt2 / pt1 * ((a + 1.0) / b) * f;
            }

            if (fault != 0)
            {
                // TODO: Error
                return null;
            }

            ParameterBag outputParameters = new();

            outputParameters.AddOutput("a_out", a);
            outputParameters.AddOutput("b_out", b);
            outputParameters.AddOutput("m", m);
            outputParameters.AddOutput("pt1_out", pt1);
            outputParameters.AddOutput("pt2_out", pt2);
            outputParameters.AddOutput("pt", pt);

            outputParameters.AddOutput("ir1", ir1);
            outputParameters.AddOutput("ir2", ir2);

            outputParameters.AddOutput("ird", ird);
            outputParameters.AddOutput("pc", gamma * 100);
            outputParameters.AddOutput("ird_from", ird1);
            outputParameters.AddOutput("ird_to", ird2);

            outputParameters.AddOutput("xmh", xmh);
            outputParameters.AddOutput("p", pxmh);

            outputParameters.AddOutput("irr", irr0 == Constant.MISSING ? double.PositiveInfinity : irr0);
            outputParameters.AddOutput("irr_from", irr1 == Constant.MISSING ? double.NegativeInfinity : irr1);
            outputParameters.AddOutput("irr_to", irr2 == Constant.MISSING ? double.PositiveInfinity : irr2);

            if (doCml)
            {
                Rec2X2[] tabl = new Rec2X2[1];
                tabl[0].Freq = 1;
                tabl[0].A = a;
                tabl[0].M1 = b + a;
                tabl[0].N1 = pt1;
                tabl[0].N0 = pt2;
                tabl[0].IsInformative = a * pt1 != 0 || b * pt2 != 0;
                bool useLogScale = false;
                new ExactBB().Exact22K(host, 0, 1, Exact22KDataType.Type3, tabl, gamma, out double eor, out double ulf, out double llf, out double ulm, out double llm, out double p1F, out double p2F, out double p1M, out double p2M, ref useLogScale, out int ierr);
                if (ierr != 0)
                    host.Error(Formatting.ERRCOLON + "Error in calculation", "StatsDirect");

                List<ParameterBag> exactList = new();
                outputParameters.AddOutput("*exact", exactList);
                ParameterBag exactParameters = new();
                exactList.Add(exactParameters);
                exactParameters.AddOutput("eor", eor);
                exactParameters.AddOutput("llf", llf);
                exactParameters.AddOutput("ulf", ulf);
                exactParameters.AddOutput("p1f", p1F);
                exactParameters.AddOutput("p2f", p2F);
                exactParameters.AddOutput("llm", llm);
                exactParameters.AddOutput("ulm", ulm);
                exactParameters.AddOutput("p1m", p1M);
                exactParameters.AddOutput("p2m", p2M);
            }

            return new StepOutput(outputParameters);
        }

        private static double PropMidPFisher2(int a, int b, int c, int d)
        {
            int fault = 0;

            if (a > d)
            {
                int t = a;
                a = d;
                d = t;
            }
            if (b > c)
            {
                int t = b;
                b = c;
                c = t;
            }

            int p = a + b;
            int q = c + d;
            int r = a + c;
            int s = b + d;
            int n = p + q;

            if (p > 0 && q > 0 && r > 0 && s > 0)
            {

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

                double e1 = p * r / (double)n;

                if (fault != 0)
                    return Constant.MISSING;
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
                // g = 1.0; 
                g1[1] = 1.0;

                int a2;
                do
                {
                    a1 += 1;
                    q1 += 1;
                    h = h * p1 / a1 * r1 / q1;
                    f += h;
                    a2 = a1 + 1;
                    f1[a2] = f;
                    h1[a2] = h;
                    p1 -= 1;
                    r1 -= 1;
                }
                while (p1 > 0);

                //   UPPER TAIL PROBABILITIES WOULD BE SUBJECT TO SUBTRACTION ERRORS
                //   IF CALCULATED BY 1 - F. THEREFORE ......

                double g = 0.0;
                int j;
                for (j = a2; j >= 2; j--)
                {
                    g += h1[j];
                    g1[j] = g;
                }

                a1 = a + 1;
                h = 1.00000000000001 * h1[a1];
                if (a > e1)
                {

                    g = g1[a1] - h1[a1] / 2.0;
                    f = 0.0;
                    for (j = 1; j <= a2; j++)
                    {
                        if (h1[j] > h)
                            break;
                        f = f1[j] - h1[j] / 2.0;
                    }

                    /* g2 is never used.  PJC 2012/04/09.
                    double g2 = 2.0 * g; 
                    if ( g2 > 1.0 )
                        g2 = 1.0; 
                     */
                }
                else
                {

                    f = f1[a1] - h1[a1] / 2.0;
                    g = 0.0;
                    for (j = a2; j >= 1; j--)
                    {
                        if (h1[j] > h)
                            break;
                        g = g1[j] - h1[j] / 2.0;
                    }
                    /* f2 is never used.  PJC 2012/04/09.
                    double f2 = 2.0 * f; 
                    if ( f2 > 1.0 )
                        f2 = 1.0; 
                     */
                }

                double z = f + g;
                if (z > 1.0)
                    z = 1.0;
                return z;
            }
            return Constant.MISSING;
        }

        public static StepOutput RptMiscRetroRisk(IProgressBarHost host, ParameterBag parameters)
        {
            double pe = Constant.MISSING;
            bool peFromControls = false;

            double a = parameters["a"].AsDouble;
            double b = parameters["b"].AsDouble;
            double c = parameters["c"].AsDouble;
            double d = parameters["d"].AsDouble;
            double m1 = a + b;
            double m2 = c + d;
            double n1 = a + c;
            double n2 = b + d;
            double n = m1 + m2;

            double gamma = parameters["cco"].AsDouble;
            if (gamma <= 0.0 | gamma >= 1.0)
                gamma = 0.95;

            double odr = OddsRatio(a, b, c, d);

            double p = 1.0 - (1.0 - gamma) / 2.0;
            double zp = PDF.gauinv(p, out int fault);
            if (fault != 0)
                return null;

            //  only calculate PAR for ODR > 1 because -ve PAR is meaningless
            double parUl;
            double parLl;
            double par;
            if (odr > 1.0 && !double.IsInfinity(odr))
            {
                if (parameters.ContainsKey("pe") && null != parameters["pe"] && parameters["pe"].HasData)
                    pe = parameters["pe"].AsDouble;
                // Without a population figure, exposure is estimated from the controls, who stand for the population when the
                // outcome is rare. The pooled sample (a + c) / n, used before version 5, moves with the number of controls the
                // investigator chose to sample. With this default PAR = 1 - (b / m1) / (d / m2), the estimator whose
                // variance (Walter) is used below.
                if (pe == Constant.MISSING || pe < 0.0 || pe > 1.0)
                {
                    pe = c / m2;
                    peFromControls = true;
                }
                par = pe * (odr - 1.0) / (1.0 + pe * (odr - 1.0));
                if (peFromControls)
                {
                    double varPar = b * m2 / (d * m1) * (b * m2 / (d * m1)) * (a / (b * m1) + c / (d * m2));
                    parLl = par - zp * Math.Sqrt(varPar);
                    parUl = par + zp * Math.Sqrt(varPar);
                }
                else
                {
                    // An entered exposure is a fixed number, so the only sampling error is the odds ratio's. PAR rises with the
                    // odds ratio, so its limits are those of the (Woolf, logit) interval for the odds ratio carried through the
                    // same formula. Walter's variance belongs to the controls-based estimator above and was wrong here.
                    double seLogOdr = Math.Sqrt(1.0 / a + 1.0 / b + 1.0 / c + 1.0 / d);
                    double odrL = Math.Exp(Math.Log(odr) - zp * seLogOdr);
                    double odrU = Math.Exp(Math.Log(odr) + zp * seLogOdr);
                    parLl = pe * (odrL - 1.0) / (1.0 + pe * (odrL - 1.0));
                    parUl = pe * (odrU - 1.0) / (1.0 + pe * (odrU - 1.0));
                }
            }
            else
            {
                par = Constant.MISSING;
                parLl = Constant.MISSING;
                parUl = Constant.MISSING;
            }

            ParameterBag outputParameters = new();
            outputParameters.AddOutput("aa", a);
            outputParameters.AddOutput("bb", b);
            outputParameters.AddOutput("cc", c);
            outputParameters.AddOutput("dd", d);

            //odr = b * c > 0 ? (a * d) / (b * c) : Constant.MISSING;
            outputParameters.AddOutput("odds", odr);
            bool dofish = true;
            double power = Power.fishpower(1.0 - gamma, a, b, n1, n2, ref dofish);
            outputParameters.AddOutput("pwr", Formatting.pwr(power, 1.0 - gamma));

            List<ParameterBag> powerList = new();
            outputParameters.AddOutput("*power", powerList);
            if (b * c > 0 && a * d > 0)
            {
                ParameterBag powerParameters = new();
                powerList.Add(powerParameters);
                double seodr = Math.Sqrt(1 / a + 1 / b + 1 / c + 1 / d);
                double yodr = Math.Log(odr) - zp * seodr;
                double xodr = Math.Log(odr) + zp * seodr;
                powerParameters.AddOutput("ci", gamma * 100);
                powerParameters.AddOutput("ci_1", Math.Exp(yodr));
                powerParameters.AddOutput("ci_2", Math.Exp(xodr));
            }

            //if ((a * d != 0) || (b * c != 0))
            //{
            //    ExactBB.Rec2X2[] tabl = new ExactBB.Rec2X2[1 + 1 /* VB to C# conversion */];
            //    tabl[1].Freq = 1;
            //    tabl[1].A = a;
            //    tabl[1].M1 = a + b;
            //    tabl[1].N1 = a + c;
            //    tabl[1].N0 = b + d;
            //    tabl[1].Informative = (a * d != 0) | (b * c != 0);
            //    bool useLogScale = false;
            //    int ierr;
            //    new ExactBB().Exact22K(host, 1, 1, tabl, gamma, ref eor, out ulf, out llf, out ulm, out llm, out p1F, out p2F, out p1M, out p2M, ref useLogScale, out ierr);
            //}
            //else
            //{
            //    eor = Constant.MISSING;
            //    llf = Constant.MISSING;
            //    ulf = Constant.MISSING;
            //    p1F = Constant.MISSING;
            //    p2F = Constant.MISSING;
            //    p1M = Constant.MISSING;
            //    p2M = Constant.MISSING;
            //}
            OddsRatioCMLE(host, gamma, a, b, c, d, out double eor, out double llf, out double ulf, out double llm, out double ulm, out double p1f, out double p2f, out double p1m, out double p2m, out _);
            outputParameters.AddOutput("eor", eor);
            outputParameters.AddOutput("pc", gamma * 100.0);
            outputParameters.AddOutput("llf", llf);
            outputParameters.AddOutput("ulf", ulf);
            outputParameters.AddOutput("p1f", p1f);
            outputParameters.AddOutput("p2f", p2f);
            outputParameters.AddOutput("llm", llm);
            outputParameters.AddOutput("ulm", ulm);
            outputParameters.AddOutput("p1m", p1m);
            outputParameters.AddOutput("p2m", p2m);

            List<ParameterBag> riskList = new();
            outputParameters.AddOutput("*risk", riskList);
            if (par != Constant.MISSING)
            {
                ParameterBag riskParameters = new();
                riskList.Add(riskParameters);
                riskParameters.AddOutput("pe", pe * 100.0);
                riskParameters.AddOutput("pe_note", peFromControls ? " (exposure among the controls)" : " (as entered)");
                riskParameters.AddOutput("par", par * 100.0);
                riskParameters.AddOutput("from", parLl * 100.0);
                riskParameters.AddOutput("to", parUl * 100.0);
            }
            return new StepOutput(outputParameters);
        }

        private static string XBenHarm(IFormatting host, double x, bool roundup)
        {
            return (roundup ? Formatting.RoundUp(Math.Abs(x)) : host.RoundU(Math.Abs(x))) + (x < 0 ? "_harm" : "_benefit");
        }

        private static void XNnSwap(ref double nnl, ref double nnu)
        {
            if (nnl < 0.0 && nnu < 0.0)
            {
                if (nnl < nnu)
                {
                    double tmp = nnl;
                    nnl = nnu;
                    nnu = tmp;
                }
            }
            else
            {
                if (nnl > nnu)
                {
                    double tmp = nnl;
                    nnl = nnu;
                    nnu = tmp;
                }
            }
        }

        public static StepOutput RptMiscDiagnostic(IProgressBarHost host, ParameterBag parameters)
        {
            double a = parameters["a"].AsDouble;
            double b = parameters["b"].AsDouble;
            double c = parameters["c"].AsDouble;
            double d = parameters["d"].AsDouble;
            double n = a + b + c + d;
            double cco = parameters["cco"].AsDouble;
            if (cco <= 0.0 || cco >= 1.0)
                cco = 0.95;

            if (n <= 0.0)
                throw new InvalidDataException();

            ParameterBag outputParameters = new();
            outputParameters.AddOutput("aa", a);
            outputParameters.AddOutput("bb", b);
            outputParameters.AddOutput("ab", a + b);

            outputParameters.AddOutput("cc", c);
            outputParameters.AddOutput("dd", d);
            outputParameters.AddOutput("cd", c + d);

            outputParameters.AddOutput("ac", a + c);
            outputParameters.AddOutput("bd", b + d);
            outputParameters.AddOutput("tot", n);

            // CI level
            outputParameters.AddOutput("pc", cco * 100.0);

            // prevalence
            double prevel = (a + c) / n;
            outputParameters.AddOutput("prevalence", prevel);

            // Clopper-Pearson CI
            MathDbl.binci(a + c, n, out double pil, out double piu, cco, out string warn);
            outputParameters.AddOutput("prevalence_from", pil);
            outputParameters.AddOutput("prevalence_to", piu);
            outputParameters.AddOutput("prevalence_warn", warn);
            // as percentage
            outputParameters.AddOutput("prevalence_pc", prevel * 100.0);
            outputParameters.AddOutput("prevalence_from_pc", pil != Constant.MISSING ? 100.0 * pil : Constant.MISSING);
            outputParameters.AddOutput("prevalence_to_pc", piu != Constant.MISSING ? 100.0 * piu : Constant.MISSING);

            // ppv
            double ptld;
            double temp2;
            double temp1;
            if (a + b > 0.0)
            {
                ptld = a / (a + b);
                temp1 = ptld * 100.0;
                temp2 = Convert.ToInt64(ptld * 100.0) - Convert.ToInt64(prevel * 100.0);
            }
            else
            {
                ptld = Constant.MISSING;
                temp1 = Constant.MISSING;
                temp2 = Constant.MISSING;
            }
            outputParameters.AddOutput("likely", ptld);

            // Clopper-Pearson CI
            MathDbl.binci(a, a + b, out pil, out piu, cco, out warn);
            outputParameters.AddOutput("likely_from", pil);
            outputParameters.AddOutput("likely_to", piu);
            outputParameters.AddOutput("likely_warn", warn);
            // as percentage
            outputParameters.AddOutput("likely_pc", temp1);
            outputParameters.AddOutput("likely_from_pc", pil != Constant.MISSING ? 100.0 * pil : Constant.MISSING);
            outputParameters.AddOutput("likely_to_pc", piu != Constant.MISSING ? 100.0 * piu : Constant.MISSING);
            // change
            outputParameters.AddOutput("likely_change", temp2);

            // npv
            double ptlng;
            if (d + c > 0.0)
            {
                ptlng = d / (d + c);
                temp1 = ptlng * 100.0;
                temp2 = Convert.ToInt64(ptlng * 100.0) - Convert.ToInt64((b + d) / n * 100.0);
            }
            else
            {
                ptlng = Constant.MISSING;
                temp1 = Constant.MISSING;
                temp2 = Constant.MISSING;
            }
            outputParameters.AddOutput("likely_negative", ptlng);
            // Clopper-Pearson CI
            MathDbl.binci(d, d + c, out pil, out piu, cco, out warn);
            outputParameters.AddOutput("likely_negative_from", pil);
            outputParameters.AddOutput("likely_negative_to", piu);
            outputParameters.AddOutput("likely_negative_warn", warn);
            // as percentage
            outputParameters.AddOutput("likely_negative_pc", temp1);
            outputParameters.AddOutput("likely_negative_from_pc", pil != Constant.MISSING ? 100.0 * pil : Constant.MISSING);
            outputParameters.AddOutput("likely_negative_to_pc", piu != Constant.MISSING ? 100.0 * piu : Constant.MISSING);
            // change
            outputParameters.AddOutput("likely_negative_change", temp2);

            // p[dx] despite -ve test
            double ptlnd;
            if (d + c > 0.0)
            {
                ptlnd = 1.0 - d / (d + c);
                temp1 = ptlnd * 100.0;
                temp2 = Convert.ToInt64(ptlnd * 100.0) - Convert.ToInt64(prevel * 100.0);
            }
            else
            {
                ptlnd = Constant.MISSING;
                temp1 = Constant.MISSING;
                temp2 = Constant.MISSING;
            }
            outputParameters.AddOutput("likely_despite", ptlnd);
            // Clopper-Pearson CI
            MathDbl.binci(d, d + c, out pil, out piu, cco, out warn);
            outputParameters.AddOutput("likely_despite_from", Math.Min(1.0 - pil, 1.0 - piu));
            outputParameters.AddOutput("likely_despite_to", Math.Max(1.0 - pil, 1.0 - piu));
            outputParameters.AddOutput("likely_despite_warn", warn);
            // as percentage
            outputParameters.AddOutput("likely_despite_pc", temp1);
            pil = pil != Constant.MISSING ? 100.0 * (1.0 - pil) : Constant.MISSING;
            piu = piu != Constant.MISSING ? 100.0 * (1.0 - piu) : Constant.MISSING;
            outputParameters.AddOutput("likely_despite_from_pc", Math.Min(pil, piu));
            outputParameters.AddOutput("likely_despite_to_pc", Math.Max(pil, piu));
            // change
            outputParameters.AddOutput("likely_despite_change", temp2);

            // sensitivity
            double sensi;
            if (a + c > 0.0)
            {
                sensi = a / (a + c);
                temp1 = 100.0 * sensi;
            }
            else
            {
                sensi = Constant.MISSING;
                temp1 = Constant.MISSING;
            }
            // Clopper-Pearson CI for sensitivity
            outputParameters.AddOutput("sensitive", sensi);
            MathDbl.binci(a, a + c, out pil, out piu, cco, out warn);
            outputParameters.AddOutput("sensitive_from", pil);
            outputParameters.AddOutput("sensitive_to", piu);
            outputParameters.AddOutput("sensitive_warn", warn);
            // as percentage
            outputParameters.AddOutput("sensitive_pc", temp1);
            outputParameters.AddOutput("sensitive_from_pc", pil != Constant.MISSING ? 100.0 * pil : Constant.MISSING);
            outputParameters.AddOutput("sensitive_to_pc", piu != Constant.MISSING ? 100.0 * piu : Constant.MISSING);

            // specificity
            double speci;
            if (d + b > 0.0)
            {
                speci = d / (d + b);
                temp1 = 100.0 * speci;
            }
            else
            {
                speci = Constant.MISSING;
                temp1 = Constant.MISSING;
            }
            outputParameters.AddOutput("specific", speci);
            // Clopper-Pearson CI for specificity
            MathDbl.binci(d, d + b, out pil, out piu, cco, out warn);
            outputParameters.AddOutput("specific_from", pil);
            outputParameters.AddOutput("specific_to", piu);
            outputParameters.AddOutput("specific_warn", warn);
            // as percentage
            outputParameters.AddOutput("specific_pc", temp1);
            outputParameters.AddOutput("specific_from_pc", pil != Constant.MISSING ? 100.0 * pil : Constant.MISSING);
            outputParameters.AddOutput("specific_to_pc", piu != Constant.MISSING ? 100.0 * piu : Constant.MISSING);

            // + likelihood ratio with CI
            double lrpos;
            double zc = 1.0 - (1.0 - cco) / 2.0;
            // fault = 0; 
            zc = PDF.gauinv(zc);
            if (b + d > 0.0 && a + c > 0.0 && b > 0.0 && ptld > 0.0)
            {
                double abpos = b / (b + d);
                lrpos = sensi / abpos;
            }
            else
            {
                lrpos = Constant.MISSING;
            }
            MathDbl.lr_ci(b, a, b + d, a + c, zc, out double thetal, out double thetau);
            outputParameters.AddOutput("lr_pos", lrpos);
            outputParameters.AddOutput("lr_pos_from", thetal);
            outputParameters.AddOutput("lr_pos_to", thetau);

            // - likelihood ratio with CI
            double lrneg;
            if (b + d > 0.0 && a + c > 0.0 && speci > 0.0 && ptlnd > 0.0)
            {
                double presneg = c / (a + c);
                lrneg = presneg / speci;
            }
            else
            {
                lrneg = Constant.MISSING;
            }
            MathDbl.lr_ci(d, c, b + d, a + c, zc, out thetal, out thetau);
            outputParameters.AddOutput("lr_neg", lrneg);
            outputParameters.AddOutput("lr_neg_from", thetal);
            outputParameters.AddOutput("lr_neg_to", thetau);

            // diagnostic odds ratio
            double odr = b * c > 0.0 && a * d > 0.0 ? a * d / (b * c) : Constant.MISSING;
            outputParameters.AddOutput("odr", odr);

            OddsRatioCMLE(host, cco, a, b, c, d, out double eor, out double llf, out double ulf, out double _, out double _, out double _, out double _, out double _, out double _, out int _);
            outputParameters.AddOutput("cmle", eor);
            outputParameters.AddOutput("cmle_from", llf);
            outputParameters.AddOutput("cmle_to", ulf);

            return new StepOutput(outputParameters);
        }

        public static StepOutput RptMiscFalseResult(ParameterBag parameters)
        {
            double pt = parameters["pt"].AsDouble;
            if (Math.Abs(pt - 0.5) >= 0.5)
                throw new InvalidDataException();
            double pf = parameters["pf"].AsDouble;
            if (Math.Abs(pf - 0.5) >= 0.5)
                throw new InvalidDataException();

            double pd = 1.0 / parameters["pd"].AsDouble;

            ParameterBag outputParameters = new();

            outputParameters.AddOutput("population", pd * 10000);

            double pp = pf * (1 - pd) / (pf + pd * (pt - pf));
            double pn = (1.0 - pt) * pd / (1.0 - pf - pd * (pt - pf));

            outputParameters.AddOutput("sensitive", pt * 100);
            outputParameters.AddOutput("positive", pp);

            outputParameters.AddOutput("specific", (1 - pf) * 100);
            outputParameters.AddOutput("negative", pn);

            return new StepOutput(outputParameters);
        }

        public static StepOutput RptKappaScreen(IPreferences host, ParameterBag parameters)
        {
            double cco = parameters["ci"].AsDouble;
            if (cco <= 0.0 || cco >= 1.0)
                cco = 0.95;

            int wtype = Parsing.Cint_Txt(parameters["method"].AsString);
            double cit = PDF.gauinv(cco + (1.0 - cco) / 2.0, out int fault);
            if (fault != 0)
                return null;
            DataFrame datFrame = parameters["responsesCrosstab"].AsDataFrame;
            int rows = datFrame.MaxRows;
            int cols = datFrame.VariableCount;
            int g = Math.Max(rows, cols);
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

            for (int i = 0; i < rows; i++)
                for (int j = 0; j < cols; j++)
                    o[i, j] = ((DoubleVariable) datFrame.Variables[j]).Data[i];

            switch (wtype)
            {
                case 3:
                    DataFrame weights = parameters["weights"].AsDataFrame;
                    for (int i = 0; i < weights.VariableCount; i++)
                    {
                        DoubleVariable v = (DoubleVariable) weights.Variables[i];
                        for (int j = 0; j < v.Length; j++)
                        {
                            w[i, j] = v.Data[j];
                            if (w[i, j] == Constant.MISSING)
                                w[i, j] = 0.0;
                        }
                    }
                    break;
                case 2:
                    for (int i = 0; i < g; i++)
                        for (int j = 0; j < g; j++)
                            w[i, j] = 1 - Math.Pow(Convert.ToDouble(i - j) / Convert.ToDouble(g - 1), 2.0);
                    break;
                case 1:
                    for (int i = 0; i < g; i++)
                        for (int j = 0; j < g; j++)
                            w[i, j] = 1 - Convert.ToDouble(Math.Abs(i - j)) / Convert.ToDouble(g - 1);
                    break;
                default:
                    throw new Exception("Unknown weight type");
            }

            Tables.Kappa(o, w, g, out double k, out double sek, out double sekci, out double kcil, out double kciu, out double kw, out double sekw, out double sekwci, out double kwcil, out double kwciu, out double po, out double pe, out double pow, out double pew, cit, out double spe, out double spi, out double gama, out double segama, out double gamacil, out double gamaciu, out double pegama, out bool ierror);
            if (ierror)
                return null;

            ParameterBag outputParameters = new();
            outputParameters.AddOutput("po", po * 100);
            outputParameters.AddOutput("pe", pe * 100);
            outputParameters.AddOutput("kappa", k);
            outputParameters.AddInput("kDouble", k);
            outputParameters.AddOutput("se", sek);
            outputParameters.AddOutput("seci", sekci);
            outputParameters.AddOutput("pc", cco * 100);
            outputParameters.AddOutput("from", kcil);
            outputParameters.AddOutput("to", kciu);
            double z = sek != 0.0 ? k / sek : Constant.MISSING;
            outputParameters.AddOutput("z", z);
            outputParameters.AddOutput("p", z != Constant.MISSING ? 1.0 - PDF.alnorm(z) : Constant.MISSING);
            switch (wtype)
            {
                case 3:
                    outputParameters.AddOutput("methodName", "user defined");
                    break;
                case 2:
                    outputParameters.AddOutput("methodName", "1-[(i-j)/(1-k)]²");
                    break;
                case 1:
                    outputParameters.AddOutput("methodName", "1-abs(i-j)/(1-k)");
                    break;
            }

            List<ParameterBag> weightsList = new();
            outputParameters.AddOutput("*weights", weightsList);
            for (int i = 1; i <= g; i++)
            {
                ParameterBag weightsParameters = new();
                weightsList.Add(weightsParameters);
                List<ParameterBag> totList = new();
                weightsParameters.AddOutput("*tot", totList);
                for (int j = 1; j <= g; j++)
                {
                    ParameterBag totParameters = new();
                    totList.Add(totParameters);
                    totParameters.AddOutput("tot", Formatting.XRound(w[i - 1, j - 1], host.Preferences.PDecimalPlaces));
                }
            }
            outputParameters.AddOutput("pow", pow * 100);
            outputParameters.AddOutput("pew", pew * 100);
            outputParameters.AddOutput("kappaw", kw);
            outputParameters.AddInput("kwDouble", kw);
            outputParameters.AddOutput("sekw", sekw);
            outputParameters.AddOutput("sekwci", sekwci);
            outputParameters.AddOutput("pcw", cco * 100);
            outputParameters.AddOutput("fromw", kwcil);
            outputParameters.AddOutput("tow", kwciu);
            double zw = sekw != 0.0 ? kw / sekw : Constant.MISSING;
            outputParameters.AddOutput("zw", zw);
            outputParameters.AddOutput("pw", zw != Constant.MISSING ? 1.0 - PDF.alnorm(zw) : Constant.MISSING);

            outputParameters.AddOutput("spe", spe * 100);
            outputParameters.AddOutput("spi", spi);
            List<ParameterBag> deciList = new();
            outputParameters.AddOutput("*deci", deciList);
            if (g == 2)
            {
                Tables.XKappaCI22(Convert.ToInt32(o[0, 0]), Convert.ToInt32(o[0, 1] + o[1, 0]), Convert.ToInt32(o[1, 1]), cit, out double _, out double lwr, out double upr, out fault);
                if (fault == 0)
                {
                    ParameterBag deciParameters = new();
                    deciList.Add(deciParameters);
                    deciParameters.AddOutput("pc", cco * 100);
                    deciParameters.AddOutput("lwr", lwr);
                    deciParameters.AddOutput("upr", upr);
                }
            }

            // Maxwell's test
            Tables.Maxwell(o, g, out double x2, out double x2M, out int dfm);
            if (x2 == Constant.MISSING)
            {
                outputParameters.AddOutput("x2", Constant.MISSING);
                outputParameters.AddOutput("df", Constant.MISSING);
                outputParameters.AddOutput("pmaxwell", Constant.MISSING);
            }
            else
            {
                outputParameters.AddOutput("x2", x2);
                outputParameters.AddOutput("df", g - 1.0);
                outputParameters.AddOutput("pmaxwell", PDF.chivalp(x2, g - 1.0));
            }
            // general McNemar
            if (x2M == Constant.MISSING)
            {
                outputParameters.AddOutput("x2m", Constant.MISSING);
                outputParameters.AddOutput("dfmcnemar", Constant.MISSING);
                outputParameters.AddOutput("pmcnemar", Constant.MISSING);
            }
            else
            {
                outputParameters.AddOutput("x2m", x2M);
                outputParameters.AddOutput("dfmcnemar", dfm);
                outputParameters.AddOutput("pmcnemar", PDF.chivalp(x2M, dfm));
            }

            // Gwet's AC1
            outputParameters.AddOutput("gama", gama);
            outputParameters.AddOutput("gamapc", Math.Round(gama * 100.0, 2));
            outputParameters.AddOutput("segama", segama);
            outputParameters.AddOutput("gamacil", gamacil);
            outputParameters.AddOutput("gamaciu", gamaciu);
            outputParameters.AddOutput("pegama", pegama);
            outputParameters.AddOutput("pegamapc", Math.Round(pegama * 100.0, 2));

            return new StepOutput(outputParameters);
        }

        public static StepOutput RptMiscLikely(ParameterBag parameters)
        {
            DataFrame datFrame = parameters["data"].AsDataFrame;
            DoubleVariable datV0 = (DoubleVariable) datFrame.Variables[0];
            DoubleVariable datV1 = (DoubleVariable) datFrame.Variables[1];
            int rows = datFrame.MaxRows;

            double[] c1 = new double[rows + 1];
            double[] c2 = new double[rows + 1];

            double c1Tot = 0;
            double c2Tot = 0;
            for (int i = 1; i <= rows; i++)
            {
                if (c1[i] < 0 || c2[i] < 0 || c1[i] == Constant.MISSING || c2[i] == Constant.MISSING)
                    throw new InvalidDataException("All values must be >= 0");

                c1[i] = datV0.Data[i - 1];
                c2[i] = datV1.Data[i - 1];
                c1Tot += c1[i];
                c2Tot += c2[i];
            }

            if (c1Tot <= 0 || c2Tot <= 0)
                throw new InvalidDataException("Total of -feature and total of +feature must both be > 0");

            double zl = parameters["z1"].AsDouble;
            if (zl <= 0.0 || zl >= 1.0)
                zl = 0.95;
            double zc = 1.0 - (1.0 - zl) / 2.0;
            zc = PDF.gauinv(zc);

            ParameterBag outputParameters = new();
            outputParameters.AddOutput("pc", 100 * zl);

            List<ParameterBag> rowList = new();
            outputParameters.AddOutput("*row", rowList);
            for (int i = 1; i <= rows; i++)
            {
                ParameterBag rowParameters = new();
                rowList.Add(rowParameters);
                rowParameters.AddOutput("result", i);
                rowParameters.AddOutput("plusfeature", c1[i]);
                rowParameters.AddOutput("minusfeature", c2[i]);

                double li;
                if (c2[i] <= 0.0)
                    li = Constant.MISSING;
                else
                    li = c1[i] / c1Tot / (c2[i] / c2Tot);

                rowParameters.AddOutput("likely", li);

                MathDbl.lr_ci(c2[i], c1[i], c2Tot, c1Tot, zc, out double thetal, out double thetau);
                rowParameters.AddOutput("from", thetal);
                rowParameters.AddOutput("to", thetau);
            }
            return new StepOutput(outputParameters);
        }

        public static StepOutput RptMiscNumberNeededToTreat(IPreferencesAndProgressBar host, ParameterBag parameters)
        {
            double tmp;
            double nt = parameters["nt"].AsDouble;
            double xt = parameters["xt"].AsDouble;
            double nc = parameters["nc"].AsDouble;
            double xc = parameters["xc"].AsDouble;

            if (nt < xt)
            {
                tmp = xt;
                xt = nt;
                nt = tmp;
            }
            if (nc < xc)
            {
                tmp = xc;
                xc = nc;
                nc = tmp;
            }

            double t1 = xt;
            double t2 = nt - xt;
            double t3 = xc;
            double t4 = nc - xc;

            if (nc < 1.0 || nt < 1.0)
                throw new InvalidDataException();

            double zl = parameters["cco"].AsDouble;
            if (zl <= 0.0 || zl >= 1.0)
                zl = 0.95;

            double zc = 1.0 - (1.0 - zl) / 2.0;
            zc = PDF.gauinv(zc);
            if (xc > nc)
            {
                tmp = xc;
                xc = nc;
                nc = tmp;
                parameters["nc"] = FilledParameterFactory.Input(nc);
                parameters["xc"] = FilledParameterFactory.Input(xc);
            }
            double pc = xc / nc;
            if (xt > nt)
            {
                tmp = xt;
                xt = nt;
                nt = tmp;
                parameters["nt"] = FilledParameterFactory.Input(nt);
                parameters["xt"] = FilledParameterFactory.Input(xt);
            }
            double pt = xt / nt;

            ParameterBag outputParameters = new();
            outputParameters.AddOutput("pc", 100.0 * zl);

            outputParameters.AddOutput("ce", xc.ToString() + "/" + nc.ToString() + " = " + host.RoundU(pc));
            MathDbl.binci(xc, nc, out double cl, out double cu, zl, out string warn);
            outputParameters.AddOutput("ce_from", cl);
            outputParameters.AddOutput("ce_to", host.RoundU(cu) + warn);
            outputParameters.AddOutput("te", xt.ToString() + "/" + nt.ToString() + " = " + host.RoundU(pt));
            MathDbl.binci(xt, nt, out cl, out cu, zl, out warn);
            outputParameters.AddOutput("te_from", cl);
            outputParameters.AddOutput("te_to", host.RoundU(cu) + warn);
            MathDbl.lr_ci(xc, xt, nc, nt, zc, out double rrel, out double rreu);
            if (rrel > rreu)
            {
                tmp = rrel;
                rrel = rreu;
                rreu = tmp;
            }
            double rre = pc != 0 ? pt / pc : double.PositiveInfinity;
            outputParameters.AddOutput("rre", rre);
            outputParameters.AddOutput("rre_from", rrel);
            outputParameters.AddOutput("rre_to", rreu);

            outputParameters.AddOutput("cne", (nc - xc).ToString() + "/" + nc.ToString() + " = " + host.RoundU(1.0 - pc));
            MathDbl.binci(nc - xc, nc, out cl, out cu, zl, out warn);
            outputParameters.AddOutput("cne_from", cl);
            outputParameters.AddOutput("cne_to", host.RoundU(cu) + warn);
            outputParameters.AddOutput("tne", (nt - xt).ToString() + "/" + nt.ToString() + " = " + host.RoundU(1.0 - pt));
            MathDbl.binci(nt - xt, nt, out cl, out cu, zl, out warn);
            outputParameters.AddOutput("tne_from", cl);
            outputParameters.AddOutput("tne_to", host.RoundU(cu) + warn);
            MathDbl.lr_ci(nc - xc, nt - xt, nc, nt, zc, out double rrnel, out double rrneu);
            if (rrnel > rrneu)
            {
                tmp = rrnel;
                rrnel = rrneu;
                rrneu = tmp;
            }
            double rrne = pc != 1.0 ? (1.0 - pt) / (1.0 - pc) : double.PositiveInfinity;
            outputParameters.AddOutput("rrne", rrne);
            outputParameters.AddOutput("rrne_from", rrnel);
            outputParameters.AddOutput("rrne_to", rrneu);

            //ExactBB.Rec2X2[] tabl = new ExactBB.Rec2X2[2];
            //tabl[1].Freq = 1;
            //tabl[1].A = t1;
            //tabl[1].M1 = t1 + t2;
            //tabl[1].N1 = t1 + t3;
            //tabl[1].N0 = t2 + t4;
            //tabl[1].Informative = (t1 * t4 != 0) || (t2 * t3 != 0);
            //bool useLogScale = false;
            //new ExactBB().Exact22K(host,1, 1, tabl, zl, ref eor, out ulf, out llf, out ulm, out llm, out p1F, out p2F, out p1M, out p2M, ref useLogScale, out ierr);
            double oor = OddsRatio(t1, t2, t3, t4);
            OddsRatioCMLE(host, zl, t1, t2, t3, t4, out double _, out double llf, out double ulf, out double _, out double _, out double _, out double _, out double _, out double _, out int _);
            //if (ierr != 0)
            //    eor = Constant.MISSING;
            //double oor = t2 * t3 == 0.0 ? Constant.MISSING : (t1 * t4) / (t2 * t3);
            outputParameters.AddOutput("oor", oor);
            outputParameters.AddOutput("oor_from", llf);
            outputParameters.AddOutput("oor_to", ulf);

            double rrr = pc != 0.0 ? (pc - pt) / pc : 0.0;
            double rrrl = rrel != Constant.MISSING ? 1.0 - rrel : Constant.MISSING;
            double rrru = rreu != Constant.MISSING ? 1.0 - rreu : Constant.MISSING;
            if (rrrl > rrru)
            {
                tmp = rrrl;
                rrrl = rrru;
                rrru = tmp;
            }
            outputParameters.AddOutput("rrr", rrr);
            outputParameters.AddOutput("rrr_from", rrrl);
            outputParameters.AddOutput("rrr_to", rrru);

            double rd = pc - pt;
            MathDbl.uppci(Convert.ToInt32(xc), Convert.ToInt32(nc), Convert.ToInt32(xt), Convert.ToInt32(nt), out cl, out cu, zc, 100.0 * zl);
            double rdl = cl;
            double rdu = cu;
            if (rdl > rdu)
            {
                tmp = rdl;
                rdl = rdu;
                rdu = tmp;
            }
            outputParameters.AddOutput("rd", rd);
            outputParameters.AddOutput("rd_from", rdl);
            outputParameters.AddOutput("rd_to", rdu);

            // NNT_risk difference
            double nnt = rd != 0.0 ? 1.0 / rd : double.PositiveInfinity;
            double nnl = rdl != 0.0 ? 1.0 / rdl : double.PositiveInfinity;
            double nnu = rdu != 0.0 ? 1.0 / rdu : double.PositiveInfinity;

            // Jan 02 change to benefit/harm notation
            // Altman DG. Confidence intervals for the number needed to treat. BMJ 1998;317:1309-12
            XNnSwap(ref nnl, ref nnu);
            outputParameters.AddOutput("treat", XBenHarm(host, nnt, false));
            outputParameters.AddOutput("treat_from", XBenHarm(host, nnl, false));
            outputParameters.AddOutput("treat_to", XBenHarm(host, nnu, false));
            outputParameters.AddOutput("treat_round", XBenHarm(host, nnt, true));
            outputParameters.AddOutput("treat_round_from", XBenHarm(host, nnl, true));
            outputParameters.AddOutput("treat_round_to", XBenHarm(host, nnu, true));
            // <--

            // **************************************************************************************
            // substitute external baseline event rate (brr) for control event rate (pc) if brr given
            bool hasBrr = parameters.ContainsKey("brr") && parameters["brr"] != null;
            List<ParameterBag> adjustedList = new();
            outputParameters.AddOutput("*adjusted", adjustedList);
            if (hasBrr)
            {
                ParameterBag adjustedParameters = new();
                adjustedList.Add(adjustedParameters);
                double brr = parameters["brr"].AsDouble;
                string brt;
                if (brr < 0.0 | brr > 1.0)
                {
                    if (brr > 1.0 & brr < 100.0)
                    {
                        brr /= 100.0;
                        brt = "(from percentage) ";
                    }
                    else
                    {
                        brt = "(reset to control event rate) ";
                        brr = pc;
                    }
                }
                else
                {
                    brt = string.Empty;
                }
                adjustedParameters.AddOutput("type", brt);
                adjustedParameters.AddOutput("brr", 100.0 * brr);

                adjustedParameters.AddOutput("pc", 100.0 * zl);

                // NNT_risk difference
                nnt = rd != 0.0 ? 1.0 / rd : double.PositiveInfinity;
                nnl = rdl != 0.0 ? 1.0 / rdl : double.PositiveInfinity;
                nnu = rdu != 0.0 ? 1.0 / rdu : double.PositiveInfinity;
                // Jan 02 change to benefit/harm notation
                // Altman DG. Confidence intervals for the number needed to treat. BMJ 1998;317:1309-12
                XNnSwap(ref nnl, ref nnu);
                adjustedParameters.AddOutput("rd_treat", XBenHarm(host, nnt, false));
                adjustedParameters.AddOutput("rd_treat_from", XBenHarm(host, nnl, false));
                adjustedParameters.AddOutput("rd_treat_to", XBenHarm(host, nnu, false));
                adjustedParameters.AddOutput("rd_treat_round", XBenHarm(host, nnt, true));
                adjustedParameters.AddOutput("rd_treat_round_from", XBenHarm(host, nnl, true));
                adjustedParameters.AddOutput("rd_treat_round_to", XBenHarm(host, nnu, true));
                // <--

                // NNT_risk ratio of event
                double d = brr * rrr;
                nnt = d != 0.0 ? 1.0 / d : double.PositiveInfinity;
                d = brr * rrrl;
                nnl = d != 0.0 ? 1.0 / d : double.PositiveInfinity;
                d = brr * rrru;
                nnu = d != 0.0 ? 1.0 / d : double.PositiveInfinity;
                // Jan 02 change to benefit/harm notation
                // Altman DG. Confidence intervals for the number needed to treat. BMJ 1998;317:1309-12
                XNnSwap(ref nnl, ref nnu);
                adjustedParameters.AddOutput("rr_treat", XBenHarm(host, nnt, false));
                adjustedParameters.AddOutput("rr_treat_from", XBenHarm(host, nnl, false));
                adjustedParameters.AddOutput("rr_treat_to", XBenHarm(host, nnu, false));
                adjustedParameters.AddOutput("rr_treat_round", XBenHarm(host, nnt, true));
                adjustedParameters.AddOutput("rr_treat_round_from", XBenHarm(host, nnl, true));
                adjustedParameters.AddOutput("rr_treat_round_to", XBenHarm(host, nnu, true));
                // <--

                // NNT_risk ratio of no event
                // Sally Hollis pointed out not (1-brr) * (1-rrr) as given by Jon Deeks
                d = (1.0 - brr) * (rrne - 1.0);
                nnt = d != 0.0
                    ? 1.0 / d
                    : double.PositiveInfinity;
                d = (1.0 - brr) * (rrnel - 1.0);
                nnl = d != 0.0
                    ? 1.0 / d
                    : double.PositiveInfinity;
                d = (1.0 - brr) * (rrneu - 1.0);
                nnu = d != 0.0
                    ? 1.0 / d
                    : double.PositiveInfinity;
                // Jan 02 change to benefit/harm notation
                // Altman DG. Confidence intervals for the number needed to treat. BMJ 1998;317:1309-12
                XNnSwap(ref nnl, ref nnu);
                adjustedParameters.AddOutput("rrn_treat", XBenHarm(host, nnt, false));
                adjustedParameters.AddOutput("rrn_treat_from", XBenHarm(host, nnl, false));
                adjustedParameters.AddOutput("rrn_treat_to", XBenHarm(host, nnu, false));
                adjustedParameters.AddOutput("rrn_treat_round", XBenHarm(host, nnt, true));
                adjustedParameters.AddOutput("rrn_treat_round_from", XBenHarm(host, nnl, true));
                adjustedParameters.AddOutput("rrn_treat_round_to", XBenHarm(host, nnu, true));
                // <--

                // NNT_odds ratio
                d = (1.0 - brr) * brr * (1.0 - oor);
                nnt = d != 0.0 
                    ? (1.0 - brr * (1.0 - oor)) / d
                    : double.PositiveInfinity;
                d = (1.0 - brr) * brr * (1.0 - llf);
                nnl = d != 0.0
                    ? (1.0 - brr * (1.0 - llf)) / d
                    : double.PositiveInfinity;
                d = (1.0 - brr) * brr * (1.0 - ulf);
                nnu = d != 0.0
                    ? (1.0 - brr * (1.0 - ulf)) / d
                    : double.PositiveInfinity;
                // Jan 02 change to benefit/harm notation
                // Altman DG. Confidence intervals for the number needed to treat. BMJ 1998;317:1309-12
                XNnSwap(ref nnl, ref nnu);
                adjustedParameters.AddOutput("or_treat", XBenHarm(host, nnt, false));
                adjustedParameters.AddOutput("or_treat_from", XBenHarm(host, nnl, false));
                adjustedParameters.AddOutput("or_treat_to", XBenHarm(host, nnu, false));
                adjustedParameters.AddOutput("or_treat_round", XBenHarm(host, nnt, true));
                adjustedParameters.AddOutput("or_treat_round_from", XBenHarm(host, nnl, true));
                adjustedParameters.AddOutput("or_treat_round_to", XBenHarm(host, nnu, true));
                // <--
            }

            return new StepOutput(outputParameters);
        }

        public static StepOutput RptMiscRelRisk(ParameterBag parameters)
        {
            double pe = Constant.MISSING;

            double a = parameters["a"].AsDouble;
            double b = parameters["b"].AsDouble;
            double c = parameters["c"].AsDouble;
            double d = parameters["d"].AsDouble;
            double m1 = a + b;
            double m2 = c + d;
            double n1 = a + c;
            double n2 = b + d;
            double n = m1 + m2;

            double gamma = parameters["cco"].AsDouble;
            if (gamma <= 0.0 || gamma >= 1.0)
                gamma = 0.95;

            if (a + c <= 0 || b + d <= 0 || b <= 0)
                throw new InvalidDataException("Relative risk can not be calculated for these data.");

            double rr = a / (a + c) / (b / (b + d));
            double p = 1.0 - (1.0 - gamma) / 2.0;
            double zp = PDF.gauinv(p, out int fault);

            double p1 = a / n1;
            double p2 = b / n2;
            double dif = p1 - p2;
            MathDbl.uppci(Convert.ToInt32(a), Convert.ToInt32(n1), Convert.ToInt32(b), Convert.ToInt32(n2), out double difLl, out double difUl, zp, 100.0 * (1.0 - gamma));

            bool dofish = true;
            double power = Power.fishpower(1.0 - gamma, a, b, n1, n2, ref dofish);

            //  only calculate PAR for RR > 1 because -ve PAR is meaningless
            double parUl;
            double parLl;
            double par;
            if (rr > 1.0)
            {
                if (parameters.ContainsKey("pe") && null != parameters["pe"] && parameters["pe"].HasData)
                    pe = parameters["pe"].AsDouble;
                if (pe == Constant.MISSING || pe < 0.0 || pe > 1.0)
                    pe = (a + c) / n;
                par = pe * (rr - 1.0) / (1.0 + pe * (rr - 1.0));
                double varPar = b * n / (Math.Pow(m1, 3.0) * Math.Pow(n2, 3.0)) * (a * d * (n - b) + b * b * c);
                parLl = par - zp * Math.Sqrt(varPar);
                parUl = par + zp * Math.Sqrt(varPar);
            }
            else
            {
                par = Constant.MISSING;
                parLl = Constant.MISSING;
                parUl = Constant.MISSING;
            }

            if (fault == 0)
            {
                ParameterBag outputParameters = new();
                MathDbl.lr_ci(b, a, b + d, a + c, zp, out double ll, out double ul);
                outputParameters.AddOutput("a_out", a);
                outputParameters.AddOutput("b_out", b);
                outputParameters.AddOutput("c_out", c);
                outputParameters.AddOutput("d_out", d);

                outputParameters.AddOutput("ratio", rr);
                outputParameters.AddOutput("pc", gamma * 100);
                outputParameters.AddOutput("koopman_from", ll);
                outputParameters.AddOutput("koopman_to", ul);
                outputParameters.AddOutput("pwr", Formatting.pwr(power, 1.0 - gamma));

                outputParameters.AddOutput("dif", dif);
                outputParameters.AddOutput("miettinen_from", difLl);
                outputParameters.AddOutput("miettinen_to", difUl);

                List<ParameterBag> exposureList = new();
                outputParameters.AddOutput("*exposure", exposureList);
                if (par != Constant.MISSING)
                {
                    ParameterBag exposureParameters = new();
                    exposureList.Add(exposureParameters);
                    exposureParameters.AddOutput("pe", pe * 100.0);
                    exposureParameters.AddOutput("par", par * 100.0);
                    exposureParameters.AddOutput("walter_from", parLl * 100.0);
                    exposureParameters.AddOutput("walter_to", parUl * 100.0);
                }

                return new StepOutput(outputParameters);
            }
            return null;
        }

        public static StepOutput RptPropPairs(ParameterBag parameters)
        {
            double n = parameters["n"].AsDouble;

            if (n <= 0)
                throw new InvalidDataException("Total number in study must be at least 1");
            double r = parameters["r"].AsDouble;
            double s = parameters["s"].AsDouble;
            double t = parameters["t"].AsDouble;

            if (n < r + s + t)
                throw new InvalidDataException("Total number in study must be at least the sum of the number responding in both categories + first category only + second category only");

            double cco = parameters["cco"].AsDouble;
            if (cco <= 0.0 || cco >= 1.0)
                cco = 0.95;
            double pt = (1.0 - cco) / 2.0;

            double cit = PDF.gauinv(cco + pt, out int ifault);
            if (ifault != 0)
                return null;

            double p1 = (r + s) / n;
            double p2 = (r + t) / n;
            double p3 = (s - t) / n;

            ParameterBag outputParameters = new();
            outputParameters.AddOutput("prop_1", p1);
            outputParameters.AddOutput("prop_2", p2);
            outputParameters.AddOutput("prop_diff", p3);

            double nx = s + t;
            double rx = s;
            if (rx < 0 && rx >= nx)
                return null;
            if (rx > nx / 2)
                rx = nx - rx;
            double fl = Math.Pow(0.5, nx);

            List<ParameterBag> exactList = new();
            outputParameters.AddOutput("*exact", exactList);
            List<ParameterBag> approxList = new();
            outputParameters.AddOutput("*approx", approxList);
            if (fl > 0)
            {
                ParameterBag exactParameters = new();
                exactList.Add(exactParameters);
                double pl = fl;
                if (rx != 0)
                {
                    double i;
                    for (i = 1; i <= rx; i++)
                    {
                        fl = fl * (nx - i + 1) / i;
                        pl += fl;
                    }
                }

                double p2L = 2.0 * pl;
                double p = pl;
                if (p2L > 1.0)
                {
                    p2L = 1.0;
                }
                p2 = p2L;
                exactParameters.AddOutput("cum_2", p2);
                exactParameters.AddOutput("cum_1", p);

                pl -= fl / 2.0;
                p2L = 2.0 * pl;
                p = pl;
                if (p2L > 1.0)
                    p2L = 1.0;
                p2 = p2L;
                exactParameters.AddOutput("cum_2_mid", p2);
                exactParameters.AddOutput("cum_1_mid", p);
            }
            else
            {
                ParameterBag approxParameters = new();
                approxList.Add(approxParameters);

                double d = Math.Abs(nx / 2 - rx) - 0.5;
                double z;
                if (d < 0)
                    z = 0;
                else
                    z = d / Math.Sqrt(nx / 4);
                approxParameters.AddOutput("z", z);
            }

            // Following snippet is only used if calculating qcl according to commented-out code below.  PJC 2012/04/09.
            // double qcl = ( 1.0 - cco ) / 2.0; 
            // qcl = cco + qcl; 

            // Following code was commented out in original.  PJC 2012/04/09.
            // If n < 200 Then
            //  ia = CLng(n - s - T)
            //  ib = CLng(s)
            //  ic = CLng(T)
            //  Call cipair(ia, ib, ic, CL, cu, qcl, cit, ierr)
            //  q = "Exact (unconditional)"
            // Else
            int ial = Convert.ToInt32(r);
            int ibl = Convert.ToInt32(s);
            int icl = Convert.ToInt32(t);
            int idl = Convert.ToInt32(n - r - s - t);
            MathDbl.Wilson(ial, ibl, icl, idl, out double cl, out double cu, cit, out bool fault);
            const string q = "Score based (Newcombe)";
            // End If
            double piu;
            double pil;
            if (fault == false)
            {
                pil = cl;
                piu = cu;
            }
            else
            {
                pil = Constant.MISSING;
                piu = Constant.MISSING;
            }

            outputParameters.AddOutput("qcl", q);
            outputParameters.AddOutput("pc", cco * 100);
            outputParameters.AddOutput("lower", pil);
            outputParameters.AddOutput("upper", piu);

            return new StepOutput(outputParameters);
        }

        public static StepOutput RptPropSingle(ParameterBag parameters)
        {
            double n = parameters["n"].AsDouble;
            double r = parameters["r"].AsDouble;
            if (r > n)
            {
                double tmp = r;
                r = n;
                n = tmp;
            }

            if (n <= 0)
                throw new InvalidDataException();
            double qpi = parameters["qpi"].AsDouble;
            if (qpi <= 0)
                qpi = 1.0E-28;
            if (qpi >= 1)
                qpi = 0.9999999;
            if (r != Math.Floor(r) && n <= r)
                return null;
            double cco = parameters["cco"].AsDouble;
            if (cco <= 0.0 || cco >= 1.0)
                cco = 0.95;
            double cit = PDF.gauinv(cco + (1 - cco) / 2, out int fault);
            double p = r / n;
            ParameterBag outputParameters = new();
            outputParameters.AddOutput("prop", p);

            // Clopper Pearson by F distribution
            outputParameters.AddOutput("ci_exact", cco * 100);
            MathDbl.binci(r, n, out double pil, out double piu, cco, out string warn);
            outputParameters.AddOutput("lower_exact", pil);
            outputParameters.AddOutput("upper_exact", piu);
            outputParameters.AddOutput("warn_exact", warn);

            // binomial exact P
            string aprx = "Binomial";
            double qpix = qpi == 1.0E-28 ? 0 : qpi;
            outputParameters.AddOutput("null", qpix);
            double p2;
            double dp2;
            double dp1;
            if (n > 1000000)
            {
                aprx = "Normal";
                p = 1.0 - PDF.alnorm((Math.Abs(r - n * qpi) - 0.5) / Math.Sqrt(n * qpi * (1.0 - qpi)));
                if (p > 1.0 - p)
                    p = 1.0 - p;
                p2 = 2.0 * p;
            }
            else
            {
                PDF.bino2(Convert.ToInt32(n), qpi, Convert.ToInt32(r), out dp1, out dp2, out fault);
                p = dp1;
                p2 = dp2;
            }
            if (fault != 0)
            {
                p = Constant.MISSING;
                p2 = Constant.MISSING;
            }
            outputParameters.AddOutput("ap_1_exact", aprx);
            outputParameters.AddOutput("p_1_exact", p);
            outputParameters.AddOutput("ap_2_exact", aprx);
            outputParameters.AddOutput("p_2_exact", p2);

            // Wilson approximate mid-P
            double t1 = 2.0 * r + cit * cit;
            double t2 = cit * Math.Sqrt(cit * cit + 4.0 * r * (1.0 - r / n));
            double t3 = 2.0 * (n + cit * cit);
            pil = (t1 - t2) / t3;
            piu = (t1 + t2) / t3;
            outputParameters.AddOutput("ci_approx", cco * 100);
            outputParameters.AddOutput("lower_approx", pil);
            outputParameters.AddOutput("upper_approx", piu);

            // binomial mid P
            if (n > 1000000)
            {
                p = 1.0 - PDF.alnorm((Math.Abs(r - n * qpi) - 0.5) / Math.Sqrt(n * qpi * (1.0 - qpi)));
                if (p > 1.0 - p)
                    p = 1.0 - p;
                p2 = 2.0 * p;
            }
            else
            {
                PDF.binomid(Convert.ToInt32(n), qpi, Convert.ToInt32(r), out dp1, out dp2, out fault);
                p = dp1;
                p2 = dp2;
            }
            if (fault != 0)
            {
                p = Constant.MISSING;
                p2 = Constant.MISSING;
            }
            outputParameters.AddOutput("ap_1_approx", aprx);
            outputParameters.AddOutput("p_1_approx", p);
            outputParameters.AddOutput("ap_2_approx", aprx);
            outputParameters.AddOutput("p_2_approx", p2);

            return new StepOutput(outputParameters);
        }

        public static StepOutput RptPropUnPaired(ParameterBag parameters)
        {
            double n1 = parameters["n1"].AsDouble;
            double r1 = parameters["r1"].AsDouble;

            if (r1 > n1)
            {
                double rTmp = r1;
                r1 = n1;
                n1 = rTmp;
            }
            if (n1 <= 0)
                throw new InvalidDataException();

            double n2 = parameters["n2"].AsDouble;
            double r2 = parameters["r2"].AsDouble;
            if (r2 > n2)
            {
                double rTmp = r2;
                r2 = n2;
                n2 = rTmp;
            }

            if (n2 <= 0)
                throw new InvalidDataException();

            double cco = parameters["cco"].AsDouble;
            if (cco <= 0.0 | cco >= 1.0)
                cco = 0.95;
            double cit = PDF.gauinv(cco + (1 - cco) / 2, out int fault);
            if (fault != 0)
                return null;

            double p1 = r1 / n1;
            double p2 = r2 / n2;
            double p = (r1 + r2) / (n1 + n2);

            ParameterBag outputParameters = new();
            outputParameters.AddOutput("n_1", n1);
            outputParameters.AddOutput("r_1", r1);
            outputParameters.AddOutput("prop_1", p1);
            outputParameters.AddOutput("n_2", n2);
            outputParameters.AddOutput("r_2", r2);
            outputParameters.AddOutput("prop_2", p2);
            outputParameters.AddOutput("prop_diff", p1 - p2);

            MathDbl.uppci(Convert.ToInt32(r1), Convert.ToInt32(n1), Convert.ToInt32(r2), Convert.ToInt32(n2), out double cl, out double cu, cit, 100.0 * cco);

            outputParameters.AddOutput("ci", 100 * cco);
            outputParameters.AddOutput("from", cl);
            outputParameters.AddOutput("to", cu);

            double mp = PropMidPFisher2(Convert.ToInt32(r1), Convert.ToInt32(n1 - r1), Convert.ToInt32(r2), Convert.ToInt32(n2 - r2));
            List<ParameterBag> exact2List = new();
            outputParameters.AddOutput("*exact2", exact2List);
            if (mp != Constant.MISSING)
            {
                ParameterBag exact2Parameters = new();
                exact2List.Add(exact2Parameters);
                exact2Parameters.AddOutput("mp", mp);
            }

            double sepest = Math.Sqrt(p * (1 - p) * (1 / n1 + 1 / n2));
            double z;
            if (sepest == 0)
            {
                sepest = Constant.MISSING;
                z = Constant.MISSING;
            }
            else
            {
                z = (p1 - p2) / sepest;
            }

            outputParameters.AddOutput("se", sepest);
            outputParameters.AddOutput("z", z);

            List<ParameterBag> approx2List = new();
            outputParameters.AddOutput("*approx2", approx2List);
            if (z != Constant.MISSING)
            {
                ParameterBag approx2Parameters = new();
                approx2List.Add(approx2Parameters);
                // Duplicate - we could use the outside version, but that would leave this bag puzzlingly empty for anyone who doesn't read it along with the report and realise that it's solely there to trigger display of a section.
                approx2Parameters.AddOutput("z", z);
            }
            return new StepOutput(outputParameters);
        }
    }
}
