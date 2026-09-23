using System;
using System.Collections.Generic;

using StatsDirect.Data;
using StatsDirect.Numerics;
using StatsDirect.Templates;
using StatsDirect.Utilities;

namespace StatsDirect.Builtins
{
    public static class Exact
    {
        public static StepOutput RptExactSign(ParameterBag parameters)
        {
            double n = parameters["n"].AsDouble;
            double r = parameters["r"].AsDouble;
            if (r > n)
            {
                double temp = r;
                r = n;
                n = temp;
            }
            ParameterBag outputParameters = new();
            if (n <= 0.0)
                throw new InvalidDataException();

            double acr = r;
            double cco = parameters["cco"].AsDouble;
            if (cco <= 0.0 || cco >= 1.0)
                cco = 0.95;

            if (r > n / 2.0)
                r = n - r;

            double f = Math.Pow(0.5, n);
            outputParameters.AddOutput("sample", n);
            outputParameters.AddOutput("sample_1", acr);
            if (f > 0.0)
            {
                double p = f;
                if (r != 0.0)
                {
                    for (long i = 1; i <= Convert.ToInt64(r); i++)
                    {
                        f *= (n - i + 1.0) / Convert.ToDouble(i);
                        p += f;
                    }
                }
                double p2 = 2.0 * p;
                if (p2 > 1.0)
                    p2 = 1.0;

                List<ParameterBag> exactList = new();
                outputParameters.AddOutput("*exact", exactList);
                ParameterBag exactParameters = new();
                exactList.Add(exactParameters);
                exactParameters.AddOutput("prob_2", p2);
                exactParameters.AddOutput("prob_1", p);
                outputParameters.AddOutput("*large", null);
            }
            else
            {
                outputParameters.AddOutput("*exact", null);
                List<ParameterBag> largeList = new();
                outputParameters.AddOutput("*large", largeList);
                largeList.Add(new ParameterBag());
            }

            double d = Math.Abs(n / 2.0 - r) - 0.5;
            double x9;
            if (d < 0.0)
                x9 = 0.0;
            else
                x9 = d / Math.Sqrt(n / 4.0);

            outputParameters.AddOutput("z", x9);

            r = acr;
            outputParameters.AddOutput("ci", cco * 100);

            MathDbl.binci(r, n, out double pil, out double piu, cco, out string warn);

            outputParameters.AddOutput("lower", pil);
            outputParameters.AddOutput("prop", r / n);
            outputParameters.AddOutput("upper", piu);
            outputParameters.AddOutput("warn", warn);

            return new StepOutput(outputParameters);
        }

        public static StepOutput RptExactFisher(ParameterBag parameters)
        {
            int fault = 0;
            int a = Convert.ToInt32(parameters["a"].AsDouble);
            int b = Convert.ToInt32(parameters["b"].AsDouble);
            int c = Convert.ToInt32(parameters["c"].AsDouble);
            int d = Convert.ToInt32(parameters["d"].AsDouble);
            ParameterBag outputParameters = Tables.SFisher(ref a, ref b, ref c, ref d, ref fault);
            if (fault != 0)
                throw new TemplateOperationCancelledException();
            return new StepOutput(outputParameters);
        }

        public static StepOutput RptExactFisherX(ParameterBag parameters)
        {
            int fault = 0;

            int a = Convert.ToInt32(parameters["a"].AsDouble);
            int b = Convert.ToInt32(parameters["b"].AsDouble);
            int c = Convert.ToInt32(parameters["c"].AsDouble);
            int d = Convert.ToInt32(parameters["d"].AsDouble);

            ParameterBag outputParameters = new();
            outputParameters.AddOutput("tab_a1", a);
            outputParameters.AddOutput("tab_b1", b);
            outputParameters.AddOutput("tab_a2", c);
            outputParameters.AddOutput("tab_b2", d);

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

            if (p <= 0 || q <= 0 || r <= 0 || s <= 0)
            {
                throw new InvalidDataException();
            }

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
                if (b0 > 1.0E+300 | s1 <= 0.0)
                {
                    fault = 1;
                    break;
                }
                b0 = b0 * n1 / s1;
                s1 -= 1.0;
                n1 -= 1.0;
            }
            while (n1 > Convert.ToDouble(q));

            double e1 = Convert.ToDouble(p) * Convert.ToDouble(r) / Convert.ToDouble(n);

            outputParameters.AddOutput("exp_a", e1);

            List<ParameterBag> headerList = new();
            outputParameters.AddOutput("*header", headerList);
            List<ParameterBag> rowList = new();
            outputParameters.AddOutput("*row", rowList);
            if (fault != 0)
            {
                Tables.Fisherp(a, b, c, d, out double zP1, out double ptwo, out fault);
                outputParameters.AddOutput("tail_1", string.Empty);
                if (fault != 0)
                {
                    outputParameters.AddOutput("p_1", "err");
                    outputParameters.AddOutput("p_1d", "err");
                    outputParameters.AddOutput("p_2", "err");
                }
                else
                {
                    outputParameters.AddOutput("p_1", zP1);
                    outputParameters.AddOutput("p_1d", zP1 * 2.0);
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
                double g = 1.0;
                g1[1] = 1.0;

                headerList.Add(new ParameterBag());
                ParameterBag rowParameters = new();
                rowList.Add(rowParameters);
                rowParameters.AddOutput("a", a1);
                rowParameters.AddOutput("lower", Formatting.pr15(g));
                rowParameters.AddOutput("ind_p", Formatting.pr15(h));
                rowParameters.AddOutput("upper", Formatting.pr15(f));
                int a2;
                do
                {
                    a1++;
                    q1++;
                    h *= Convert.ToDouble(p1) / Convert.ToDouble(a1) * Convert.ToDouble(r1) / Convert.ToDouble(q1);
                    f += h;
                    a2 = a1 + 1;
                    f1[a2] = f;
                    h1[a2] = h;
                    --p1;
                    --r1;
                }
                while (p1 > 0L);

                //   UPPER TAIL PROBABILITIES WOULD BE SUBJECT TO SUBTRACTION ERRORS
                //   IF CALCULATED BY 1 - F. THEREFORE ......

                g = 0.0;
                for (int j = a2; j >= 2; j--)
                {
                    g += h1[j];
                    g1[j] = g;
                }
                // int Start = 1; 
                for (int j = 2; j <= a2; j++)
                {
                    rowParameters = new ParameterBag();
                    rowList.Add(rowParameters);
                    rowParameters.AddOutput("a", j - 1);
                    rowParameters.AddOutput("lower", Formatting.pr15(f1[j]));
                    rowParameters.AddOutput("ind_p", Formatting.pr15(h1[j]));
                    rowParameters.AddOutput("upper", Formatting.pr15(g1[j]));
                }

                a1 = a + 1;
                h = 1.00000000000001 * h1[a1];
                double midP;
                if (a > e1)
                {

                    g = g1[a1];
                    f = 0.0;
                    for (int j = 1; j <= a2; j++)
                    {
                        if (h1[j] > h)
                            break;
                        f = f1[j];
                    }

                    double g2 = 2.0 * g;
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
                    for (int j = a2; j >= 1; j--)
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

                outputParameters.AddOutput("p_2", z);
                outputParameters.AddOutput("mid_p", midP);
                outputParameters.AddOutput("mid_p_2", Math.Min(midP * 2.0, 1.0));

            }
            return new StepOutput(outputParameters);
        }

        public static StepOutput RptChiWoolf(ParameterBag parameters)
        {
            int rc;

            DataFrame datFrame = parameters["dat"].AsDataFrame;
            DoubleVariable datV0 = datFrame.Variables[0]as DoubleVariable;
            DoubleVariable datV1 = datFrame.Variables[1]as DoubleVariable;
            int rows = datFrame.MaxRows;
            if (rows <= 0)
                throw new InvalidDataException();

            double cco = parameters["cco"].AsDouble;
            if (cco <= 0.0 || cco >= 1.0)
                cco = 0.95;
            double cit = PDF.gauinv(cco + (1.0 - cco) / 2.0);

            bool showIntermediates = parameters["show_intermediates"].AsBoolean;

            int k = rows / 3;
            double[,] o = new double[k + 1, 5];
            int cnt = 0;
            for (rc = 1; rc <= rows; rc += 2)
            {
                cnt++;
                double rtd = datV0.Data[rc - 1];
                o[cnt, 1] = rtd;
                rtd = datV1.Data[rc - 1];
                o[cnt, 2] = rtd;
                rtd = datV0.Data[rc];
                o[cnt, 3] = rtd;
                rtd = datV1.Data[rc];
                o[cnt, 4] = rtd;
            }

            return new StepOutput(Tables.Woolf(o, k, showIntermediates, cit, cco, out bool ierr));
        }


        public static StepOutput RptExactMcNamar(ParameterBag parameters)
        {
            double ba = parameters["a"].AsDouble;
            double bb = parameters["b"].AsDouble;
            double bc = parameters["c"].AsDouble;
            double bd = parameters["d"].AsDouble;
            double gamma = parameters["gamma"].AsDouble;
            if (gamma <= 0.0 || gamma >= 1.0)
                gamma = 0.95;

            ParameterBag outputParameters = new();
            outputParameters.AddOutput("tab_a1", ba);
            outputParameters.AddOutput("tab_b1", bb);
            outputParameters.AddOutput("tab_a2", bc);
            outputParameters.AddOutput("tab_b2", bd);

            if (bb + bc <= 0.0)
                throw new InvalidDataException();

            double x2 = Math.Abs(bb - bc) * Math.Abs(bb - bc) / (bb + bc);
            outputParameters.AddOutput("chi", x2);
            outputParameters.AddOutput("chi_p", PDF.chivalp(x2, 1.0));

            x2 = Math.Abs(bb - bc) - 1.0;
            double n = bb + bc;
            x2 = x2 * x2 / n;
            outputParameters.AddOutput("yates_chi", x2);
            outputParameters.AddOutput("yates_chi_p", PDF.chivalp(x2, 1.0));

            double rr = bc > 0.0
                ? bb / bc
                : double.PositiveInfinity;
            outputParameters.AddOutput("risk", rr);

            double r = bb;
            double s = bc;

            if (r < s)
                Utilities.Utilities.Swap(ref r, ref s);
            double p = (1 - gamma) / 2.0;
            double dfn = 2.0 * (s + 1.0);
            double dfd = 2.0 * r;
            double llf = PDF.ffromp(dfd, dfn, p);
            dfn = 2.0 * (r + 1.0);
            dfd = 2.0 * s;
            double ulf = PDF.ffromp(dfd, dfn, p);
            double ll = llf > 0.0
                ? r / ((s + 1.0) * llf)
                : Constant.MISSING;
            double ul = s > 0.0
                ? (r + 1.0) * ulf / s
                : Constant.MISSING;

            if (bc > bb)
            {
                if (ll != Constant.MISSING)
                    ll = 1.0 / ll;
                if (ul != Constant.MISSING)
                    ul = 1.0 / ul;
            }
            if (ll != Constant.MISSING && ul != Constant.MISSING)
            {
                if (ul < ll)
                    Utilities.Utilities.Swap(ref ll, ref ul);
            }
            outputParameters.AddOutput("pc", gamma * 100);
            if (ll == Constant.MISSING)
                ll = double.NegativeInfinity;
            outputParameters.AddOutput("from", ll);
            if (ul == Constant.MISSING)
                ul = double.PositiveInfinity;
            outputParameters.AddOutput("to", ul);

            double f = r / (s + 1.0);
            p = PDF.fvalp(f, 2.0 * (s + 1.0), 2.0 * r) * 2.0;
            if (p > 1.0)
                p = 1.0;

            outputParameters.AddOutput("f", f);
            outputParameters.AddOutput("tail_2", p);
            List<ParameterBag> rPrimeList = new();
            outputParameters.AddOutput("*r_prime", rPrimeList);
            if (p < 0.05)
                rPrimeList.Add(new ParameterBag());

            return new StepOutput(outputParameters);
        }


        public static StepOutput RptExactORCML(IProgressBarHost host, ParameterBag parameters)
        {
            // Gart replaced by CML in May 2001

            double cco = parameters["gamma"].AsDouble;
            if (cco <= 0.0 || cco >= 1.0)
                cco = 0.95;

            double a = parameters["a"].AsDouble;
            double b = parameters["b"].AsDouble;
            double c = parameters["c"].AsDouble;
            double d = parameters["d"].AsDouble;

            ParameterBag outputParameters = new();
            outputParameters.AddOutput("tab_a1", a);
            outputParameters.AddOutput("tab_b1", b);
            outputParameters.AddOutput("tab_a2", c);
            outputParameters.AddOutput("tab_b2", d);

            ExactBB.OddsRatioCMLE(host, cco, a, b, c, d, out double eor, out double llf, out double ulf, out double llm, out double ulm, out double p1f, out double p2f, out double p1m, out double p2m, out int ierr);
            double odr = ExactBB.OddsRatio(a, b, c, d);
            outputParameters.AddOutput("odds", odr);

            outputParameters.AddOutput("eor", eor);
            outputParameters.AddOutput("pc", cco * 100);
            outputParameters.AddOutput("llf", llf);
            outputParameters.AddOutput("ulf", ulf);
            outputParameters.AddOutput("p1f", p1f);
            outputParameters.AddOutput("p2f", p2f);
            outputParameters.AddOutput("llm", llm);
            outputParameters.AddOutput("ulm", ulm);
            outputParameters.AddOutput("p1m", p1m);
            outputParameters.AddOutput("p2m", p2m);
            return new StepOutput(outputParameters);
        }

        public static StepOutput RptRatePoissonCI(ParameterBag parameters)
        {
            double cco = parameters["cco"].AsDouble;
            double alpha = 1.0 - cco;
            if (alpha <= 0.0 || alpha >= 1.0)
                alpha = 0.05;

            double revents = parameters["revents"].AsDouble;
            double tar = parameters["tar"].AsDouble;
            if (tar <= 0.0)
            {
                tar = 1.0;
                parameters["tar"] = FilledParameterFactory.Input(1.0);
            }

            ParameterBag outputParameters = new();
            outputParameters.AddOutput("events", revents);
            outputParameters.AddOutput("time", tar);
            outputParameters.AddOutput("rate", revents / tar);

            outputParameters.AddOutput("pc", cco * 100);

            Rates.poisson_ci(alpha, revents, tar, out double xl, out double xu);
            outputParameters.AddOutput("from", xl);
            outputParameters.AddOutput("to", xu);
            return new StepOutput(outputParameters);
        }
    }
}
