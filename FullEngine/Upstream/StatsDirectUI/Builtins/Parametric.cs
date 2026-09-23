using System;
using System.Collections.Generic;
using StatsDirect.Utilities;
using StatsDirect.Templates;
using StatsDirect.Numerics;
using StatsDirect.Data;
using StatsDirect.Charting;

namespace StatsDirect.Builtins
{
    public static class Parametric
    {
        private static void Univariate(double[] arr1, int nx, out double sum, out double mean, out double var)
        {
            sum = 0;
            double sumsqdev = 0;
            for (int N = 1; N <= nx; N++)
                sum += arr1[N];
            mean = sum / nx;
            for (int N = 1; N <= nx; N++)
            {
                if (Math.Abs(sumsqdev) > 1.0E+300)
                {
                    sumsqdev = Constant.MISSING;
                    break;
                }
                sumsqdev += (arr1[N] - mean) * (arr1[N] - mean);
            }
            if (sumsqdev == Constant.MISSING)
                var = Constant.MISSING;
            else
                var = sumsqdev / (nx - 1);
        }

        private static void Para(DataFrame frame, double[] mean, double[] ss, double[] var, double[] sd, double[] sem, int[] tnx)
        {
            for (int d = 0; d < frame.VariableCount; d++)
            {
                int nx = 0;
                double sum = 0.0;
                foreach (double v in (frame.Variables[d] as DoubleVariable).Data)
                {
                    if (v != Constant.MISSING)
                    {
                        nx++;
                        sum += v;
                    }
                }
                tnx[d] = nx;
                mean[d] = sum / Convert.ToDouble(tnx[d]);
                // The sum of squares about the mean is taken from the two-pass loop below. It was formed from the raw sums
                // (sum of squares less the square of the sum over n), which loses digits when the mean is large compared with
                // the spread: the unpaired t test on values near 1e8 was wrong and near 1e9 gave t = infinity.
                double sumsqdev = 0.0;
                foreach (double v in (frame.Variables[d] as DoubleVariable).Data)
                {
                    if (v != Constant.MISSING)
                    {
                        if (Math.Abs(sumsqdev) > 1.0E+300)
                        {
                            sumsqdev = Constant.MISSING;
                            break;
                        }
                        sumsqdev += (v - mean[d]) * (v - mean[d]);
                    }
                }
                ss[d] = sumsqdev;
                if (sumsqdev == Constant.MISSING)
                    var[d] = Constant.MISSING;
                else
                    var[d] = sumsqdev / (tnx[d] - 1);
                sd[d] = Math.Sqrt(var[d]);
                sem[d] = sd[d] / Math.Sqrt(tnx[d]);
            }
        }

        public static StepOutput RptVarianceRatio(ParameterBag parameters)
        {
            int bot; int top;

            double[] mean = new double[1 + 1 /* VB to C# conversion */ ];
            double[] ss = new double[1 + 1 /* VB to C# conversion */ ];
            double[] var = new double[1 + 1 /* VB to C# conversion */ ];
            double[] sd = new double[1 + 1 /* VB to C# conversion */ ];
            double[] sem = new double[1 + 1 /* VB to C# conversion */ ];
            int[] tnx = new int[1 + 1 /* VB to C# conversion */ ];
            DataFrame data = parameters["data"].AsDataFrame;
            Para(data, mean, ss, var, sd, sem, tnx);
            if (Math.Abs(var[0]) > Math.Abs(var[1]))
            {
                top = 0;
                bot = 1;
            }
            else
            {
                top = 1;
                bot = 0;
            }
            double f = var[top] / var[bot];
            ParameterBag outputParameters = new();
            outputParameters.AddOutput("title_0", data.Variables[top].Title);
            outputParameters.AddOutput("df_0", tnx[top] - 1);
            outputParameters.AddOutput("var_0", var[top]);
            outputParameters.AddOutput("title_1", data.Variables[bot].Title);
            outputParameters.AddOutput("df_1", tnx[bot] - 1);
            outputParameters.AddOutput("var_1", var[bot]);
            outputParameters.AddOutput("f", f);
            double P = PDF.fvalp(f, tnx[top] - 1, tnx[bot] - 1);
            outputParameters.AddOutput("p_1", P);
            //  Two sided: twice the smaller tail. With the larger variance on top the upper tail is usually the smaller, but not
            //  always when the degrees of freedom differ, and capping it at 0.5 printed P = 1 then.
            outputParameters.AddOutput("p_2", 2.0 * Math.Min(P, 1.0 - P));
            return new StepOutput(outputParameters);
        }

        public static StepOutput RptReferenceRange(ParameterBag parameters)
        {
            double xq = 0;
            double o = 0;
            int k = 0;

            double[] mean = new double[2];
            double[] ss = new double[2];
            double[] var = new double[2];
            double[] sd = new double[2];
            double[] sem = new double[2];
            int[] tnx = new int[2];

            DataFrame data = parameters["data"].AsDataFrame;
            DoubleVariable variable = data.Variables[0]as DoubleVariable;
            int present = 0;
            foreach (double v in variable.Data)
                if (v != Constant.MISSING)
                    present++;
            if (present < 8)
                throw new TemplateOperationCancelledException("Too few data for this method (minimum 8)", "Reference Range");

            bool do_conservative = parameters["do_conservative"].AsBoolean;
            double GAMMA = parameters["gamma"].AsDouble;
            if (GAMMA <= 0.0 || GAMMA >= 1.0)
            {
                GAMMA = 0.95;
            }
            double qrr = parameters["reference-interval"].AsDouble;
            double qrz = Math.Abs(PDF.gauinv((1.0 - qrr) / 2.0, out int fault));
            if (fault != 0 || qrr < 0.0 || qrr > 1.0)
                throw new TemplateOperationCancelledException("Coverage not possible.", "Reference Range");

            MathDbl.civ(0, out double z, GAMMA, out _);
            Para(data, mean, ss, var, sd, sem, tnx);
            double xbar = mean[0];
            double s = sd[(int)Math.Floor(o)];
            int N = tnx[0];
            ParameterBag outputParameters = new();
            outputParameters.AddOutput("name", variable.Title);
            outputParameters.AddOutput("mean", xbar);
            outputParameters.AddOutput("size", N);
            outputParameters.AddOutput("sd", s);
            // normal version
            outputParameters.AddOutput("qrr", 100.0 * qrr);
            double lrr = xbar - qrz * s;
            double urr = xbar + qrz * s;
            outputParameters.AddOutput("lrr", lrr);
            outputParameters.AddOutput("urr", urr);
            double serr = Math.Sqrt(s * s / N + qrz * qrz * s * s / (2.0 * N));
            double lx = lrr - serr * z;
            double ux = lrr + serr * z;
            outputParameters.AddOutput("pc", 100.0 * GAMMA);
            outputParameters.AddOutput("lx_l", lx);
            outputParameters.AddOutput("ux_l", ux);
            lx = urr - serr * z;
            ux = urr + serr * z;
            outputParameters.AddOutput("lx_u", lx);
            outputParameters.AddOutput("ux_u", ux);

            // log-normal version
            double[] r = new double[variable.Length + 1];
            double sum = 0;
            double sumsq = 0;
            N = 0;
            bool ok = true;
            for (int j = 0; j < data.Variables[k].Length; j++)
            {
                double v = (data.Variables[k] as DoubleVariable).Data[j];
                if (v != Constant.MISSING)
                {
                    // strictly positive: the logarithm of zero is minus infinity, which made the log-normal lines meaningless
                    if (v > 0.0)
                    {
                        N++;
                        r[N] = Math.Log(variable.Data[j]);
                        sum += r[N];
                        sumsq += r[N] * r[N];
                    }
                    else
                    {
                        ok = false;
                        break;
                    }
                }
            }
            if (!ok)
            {
                outputParameters.AddOutput("*lognormal", null);
            }
            else
            {
                IList<ParameterBag> lognormalList = new List<ParameterBag>();
                outputParameters.AddOutput("*lognormal", lognormalList);
                ParameterBag lognormalParameters = new();
                lognormalList.Add(lognormalParameters);
                xbar = sum / Convert.ToDouble(N);
                double sumsqdev = 0.0;
                for (int j = 1; j <= N; j++)
                {
                    if (Math.Abs(sumsqdev) > 1.0E+300)
                    {
                        sumsqdev = Constant.MISSING;
                        break;
                    }
                    sumsqdev += (r[j] - xbar) * (r[j] - xbar);
                }
                s = sumsqdev == Constant.MISSING ? Constant.MISSING : Math.Sqrt(sumsqdev / Convert.ToDouble(N - 1));
                lrr = xbar - qrz * s;
                urr = xbar + qrz * s;
                lognormalParameters.AddOutput("lrr_lognormal", Math.Exp(lrr));
                lognormalParameters.AddOutput("urr_lognormal", Math.Exp(urr));
                serr = Math.Sqrt(s * s / Convert.ToDouble(N) + qrz * qrz * s * s / (2.0 * Convert.ToDouble(N)));
                lx = Math.Exp(lrr - serr * z);
                ux = Math.Exp(lrr + serr * z);
                lognormalParameters.AddOutput("lx_l_lognormal", lx);
                lognormalParameters.AddOutput("ux_l_lognormal", ux);
                lx = Math.Exp(urr - serr * z);
                ux = Math.Exp(urr + serr * z);
                lognormalParameters.AddOutput("lx_u_lognormal", lx);
                lognormalParameters.AddOutput("ux_u_lognormal", ux);
            }
            // percentile version
            r = new double[variable.Length + 1];
            int rx = 0;
            for (int j = 0; j < data.Variables[k].Length; j++)
            {
                if ((data.Variables[k] as DoubleVariable).Data[j] != Constant.MISSING)
                {
                    rx++;
                    r[rx] = (data.Variables[k] as DoubleVariable).Data[j];
                }
            }
            Array.Sort(r, 1, rx);
            double qc = (1.0 - qrr) / 2.0;
            Nonparametric.XQci(qc, rx, r, ref xq, GAMMA, out double ll, out double ul, out double cover, do_conservative, out bool capUpper, out bool capLower, out _);
            outputParameters.AddOutput("qx_any", qc);
            outputParameters.AddOutput("qxv_any", xq);
            outputParameters.AddOutput("type", do_conservative ? "(conservative)" : "(non-conservative)");
            if (capLower)
                outputParameters.AddOutput("cap_from_any", "* ");
            outputParameters.AddOutput("from_any", ll);
            if (capUpper)
                outputParameters.AddOutput("cap_to_any", "* ");
            outputParameters.AddOutput("to_any", ul);
            outputParameters.AddOutput("co_any", cover);
            if (capLower || capUpper)
                outputParameters.AddOutput("cap_co_any", "  (* limit capped at min/max)");
            qc = 1.0 - (1.0 - qrr) / 2.0;
            Nonparametric.XQci(qc, rx, r, ref xq, GAMMA, out ll, out ul, out cover, do_conservative, out capUpper, out capLower, out _);
            outputParameters.AddOutput("qx", qc);
            outputParameters.AddOutput("qxv", xq);
            if (capLower)
                outputParameters.AddOutput("cap_from", "* ");
            outputParameters.AddOutput("from", ll);
            if (capUpper)
                outputParameters.AddOutput("cap_to", "* ");
            outputParameters.AddOutput("to", ul);
            outputParameters.AddOutput("co", cover);
            if (capLower || capUpper)
                outputParameters.AddOutput("cap_co", "  (* limit capped at min/max)");

            return new StepOutput(outputParameters);
        }

        private static void x_poisson(double[] x, int nobs, double percent, out double mean, out double tlower, out double tupper, ref int fault)
        {
            mean = Constant.MISSING;
            tlower = Constant.MISSING;
            tupper = Constant.MISSING;
            if (nobs < 1)
            {
                fault = 1;
                return;
            }
            double sum = 0.0;
            for (int i = 1; i <= nobs; i++)
            {
                if (x[i] < 0)
                {
                    fault = 2;
                    return;
                }
                sum += x[i];
            }
            double dn = nobs;
            mean = sum / dn;
            if (percent <= 0.0 | percent >= 100.0)
            {
                fault = 3;
                return;
            }
            double al1 = 0.005 * (100.0 - percent);
            double al2 = 1.0 - al1;
            if (sum <= 0.0)
            {
                tupper = -Math.Log(al1) / dn;
                tlower = 0.0;
            }
            else
            {
                double df1 = 2.0 * sum;
                double chi2;
                if (sum == 1.0)
                {
                    tlower = -Math.Log(al2) / dn;
                }
                else
                {
                    chi2 = PDF.ppchi2(al1, df1, out fault);
                    if (fault != 0)
                        return;
                    tlower = chi2 * 0.5 / dn;
                }
                double df2 = df1 + 2.0;
                chi2 = PDF.ppchi2(al2, df2, out fault);
                if (fault != 0)
                    return;
                tupper = chi2 * 0.5 / dn;
            }
        }

        public static StepOutput RptPoissonConfidenceInterval(ParameterBag parameters)
        {
            DataFrame data = parameters["data"].AsDataFrame;
            double percent2 = parameters["gamma"].AsDouble * 100.0;
            if (percent2 <= 0.0 || percent2 >= 100.0)
                percent2 = 95.0;
            double percent1 = 100.0 - 2.0 * (100.0 - percent2);

            ParameterBag outputParameters = new();
            IList<ParameterBag> sampleList = new List<ParameterBag>();
            outputParameters.AddOutput("*sample", sampleList);
            foreach (IVariable varbl in data.Variables)
            {
                DoubleVariable variable = varbl as DoubleVariable;
                double[] x = new double[variable.Length + 1 ];
                int nobs = 0;
                bool not_int = false;
                bool non_neg = false;
                foreach (double v in variable.Data)
                {
                    if (v != Constant.MISSING)
                    {
                        nobs++;
                        x[nobs] = v;
                        if (x[nobs] != Math.Floor(v))
                            not_int = true;
                        if (x[nobs] < 0)
                            non_neg = true;
                    }
                }
                ParameterBag sampleParameters = new();
                sampleList.Add(sampleParameters);
                sampleParameters.AddOutput("ti", variable.Title);
                string wrn = non_neg
                    ? "(error - negative values used)"
                    : (not_int
                        ? "(warning - source data not integers)"
                        : string.Empty);
                sampleParameters.AddOutput("warn", wrn);
                sampleParameters.AddOutput("n", nobs);

                int fault = 0;
                x_poisson(x, nobs, percent2, out double that, out double tlower2, out double tupper2, ref fault);
                if (fault != 0)
                {
                    tlower2 = Constant.MISSING;
                    tupper2 = Constant.MISSING;
                }
                x_poisson(x, nobs, percent1, out double _, out double tlower1, out double tupper1, ref fault);
                if (fault != 0)
                {
                    // a confidence level of 50% or less gives no one sided interval; the mean was also blanked here
                    tlower1 = Constant.MISSING;
                    tupper1 = Constant.MISSING;
                }
                sampleParameters.AddOutput("mean", that);
                sampleParameters.AddOutput("pc2", Math.Round(percent2, 1));
                sampleParameters.AddOutput("pc1", Math.Round(percent1, 1));
                sampleParameters.AddOutput("lower2", tlower2);
                sampleParameters.AddOutput("upper2", tupper2);
                sampleParameters.AddOutput("lower1", tlower1);
                sampleParameters.AddOutput("upper1", tupper1);
            }
            return new StepOutput(outputParameters);
        }

        public static StepOutput RptZSingle(ParameterBag parameters) => RptNormalZ(parameters, 1);

        public static StepOutput RptZUnpaired(ParameterBag parameters) => RptNormalZ(parameters, 2);

        private static StepOutput RptNormalZ(ParameterBag parameters, int mode)
        {
            double[] mean = new double[1 + 1];
            double[] ss = new double[1 + 1];
            double[] var = new double[1 + 1];
            double[] sd = new double[1 + 1];
            double[] sem = new double[1 + 1];
            int[] tnx = new int[1 + 1];

            double GAMMA = parameters["gamma"].AsDouble;
            if (mode == 2)
            {
                DataFrame Data = parameters["data"].AsDataFrame;
                MathDbl.civ(0, out double cit, GAMMA, out double P0);
                Para(Data, mean, ss, var, sd, sem, tnx);
                ParameterBag outputParameters = new();
                IList<ParameterBag> sampleList = new List<ParameterBag>();
                outputParameters.AddOutput("*sample", sampleList);
                for (int d = 0; d <= 1; d++)
                {
                    ParameterBag sampleParameters = new();
                    sampleList.Add(sampleParameters);
                    sampleParameters.AddOutput("name", Data.Variables[d].Title);
                    sampleParameters.AddOutput("mean", mean[d]);
                    sampleParameters.AddOutput("var", var[d]);
                    sampleParameters.AddOutput("size", tnx[d]);
                }
                double cse = Math.Sqrt(var[0] / tnx[0] + var[1] / tnx[1]);
                outputParameters.AddOutput("error", cse);
                outputParameters.AddOutput("pc", 100 * (1 - P0));
                outputParameters.AddOutput("from", mean[0] - mean[1] - cse * cit);
                outputParameters.AddOutput("to", mean[0] - mean[1] + cse * cit);
                double statz = (mean[0] - mean[1]) / cse;
                outputParameters.AddOutput("z", statz);
                double P = 1.0 - PDF.alnorm(Math.Abs(statz));
                if (P > 1 - P)
                    P = 1 - P;
                outputParameters.AddOutput("p_1", P);
                outputParameters.AddOutput("p_2", P * 2);
                if (tnx[0] < 30 || tnx[1] < 30)
                    outputParameters.AddOutput("*warn", new List<ParameterBag> { new ParameterBag() });
                else
                    outputParameters.AddOutput("*warn", null);
                return new StepOutput(outputParameters);
            }
            else
            {
                DataFrame Data = parameters["data"].AsDataFrame;
                DoubleVariable v0 = Data.Variables[0]as DoubleVariable;
                double pm = parameters["popmean"].AsDouble;
                double psd = parameters.ContainsKey("popsd") && parameters["popsd"] != null
                    ? parameters["popsd"].AsDouble
                    : Constant.MISSING;
                if (psd != Constant.MISSING && psd < 0.0)
                    throw new TemplateOperationCancelledException("The population standard deviation must be positive; leave it blank if it is not known.", "Single Sample z Test");
                MathDbl.civ(0, out double cit, GAMMA, out double P0);
                Para(Data, mean, ss, var, sd, sem, tnx);
                ParameterBag outputParameters = new();
                outputParameters.AddOutput("name", v0.Title);
                outputParameters.AddOutput("mean", mean[0]);
                outputParameters.AddOutput("pop_mean", pm);
                outputParameters.AddOutput("size", tnx[0]);
                outputParameters.AddOutput("sd", sd[0]);
                //  The standard error of the mean from the population standard deviation when it is given, else from the sample's;
                //  the statistic and the confidence interval use the same one (the interval had always used the sample's)
                double se;
                if (psd == Constant.MISSING || psd == 0.0)
                {
                    outputParameters.AddOutput("psd", "not known");
                    se = sd[0] / Math.Sqrt(tnx[0]);
                }
                else
                {
                    outputParameters.AddOutput("psd", psd);
                    se = psd / Math.Sqrt(tnx[0]);
                }
                double statz = (mean[0] - pm) / se;
                outputParameters.AddOutput("pc", 100 * (1 - P0));
                outputParameters.AddOutput("for", pm == 0 ? "for the mean" : "for mean difference");
                outputParameters.AddOutput("from", mean[0] - pm - cit * se);
                outputParameters.AddOutput("to", mean[0] - pm + cit * se);
                outputParameters.AddOutput("z", statz);
                double P = 1.0 - PDF.alnorm(Math.Abs(statz));
                if (P > 1 - P)
                    P = 1 - P;

                outputParameters.AddOutput("p_1", P);
                outputParameters.AddOutput("p_2", P * 2);
                int nx = 0;
                double gsum = 0;
                double gsumsq = 0;
                foreach (double val in v0.Data)
                {
                    if (val != Constant.MISSING & val > 0)
                    {
                        nx++;
                        double logVal = Math.Log(val);
                        gsum += logVal;
                        gsumsq += logVal * logVal;
                    }
                }
                double urr;
                double lrr;
                double gmean;
                if (nx > 1)
                {
                    gmean = gsum / Convert.ToDouble(nx);
                    double gss = gsumsq - gsum * gsum / nx;
                    double gvar = gss / (nx - 1);
                    double gsd = Math.Sqrt(gvar);
                    lrr = gmean - gsd * cit;
                    urr = gmean + gsd * cit;
                    gmean = Math.Exp(gmean);
                    lrr = Math.Exp(lrr);
                    urr = Math.Exp(urr);
                }
                else
                {
                    gmean = Constant.MISSING;
                    lrr = Constant.MISSING;
                    urr = Constant.MISSING;
                }
                outputParameters.AddOutput("gmean", gmean);
                outputParameters.AddOutput("pc2", 100 * (1 - P0));
                outputParameters.AddOutput("lrr", lrr);
                outputParameters.AddOutput("urr", urr);
                if (tnx[0] < 30)
                {
                    IList<ParameterBag> warnList = new List<ParameterBag>
                    {
                        new ParameterBag()
                    };
                    outputParameters.AddOutput("*warn", warnList);
                }
                return new StepOutput(outputParameters);
            }
        }

        public static StepOutput RptNormality(IFormatting host, ParameterBag parameters)
        {
            // ASSUME: Data passed in was acquired with NumericSkipMissing and has no missing values.
            DataFrame frame = parameters["data"].AsDataFrame;

            ParameterBag outputParameters = new();
            List<ParameterBag> outputList = new();
            outputParameters.AddOutput("*variable", outputList);

            foreach (IVariable v in frame.Variables)
            {
                DoubleVariable v0 = v as DoubleVariable;
                double[] data = v0.Data;
                int n = data.Length;

                // variable
                ParameterBag variableParameters = new();
                outputList.Add(variableParameters);
                variableParameters.AddOutput("sample", v0.Title);
                variableParameters.AddOutput("n", n);
                normality_sk(data, 0, n, out double mean, out double sd, out double skewness, out double kurtosis, out double _, out double b1P, out double _, out double b2P, out double k2, out double k2P);
                variableParameters.AddOutput("mean", mean);
                variableParameters.AddOutput("sd", sd);
                if (sd == Constant.MISSING)
                {
                    // the fourth moment overflowed (values of size above about 1e75)
                    variableParameters.AddOutput("skewness", Constant.MISSING);
                    variableParameters.AddOutput("kurtosis", Constant.MISSING);
                    variableParameters.AddOutput("k2", "Not calculated: the values are too large");
                    variableParameters.AddOutput("sw_w", "Not calculated: the values are too large");
                    variableParameters.AddOutput("sf_w", "Not calculated: the values are too large");
                    variableParameters.AddOutput("result", "The values are too large for these calculations");
                    continue;
                }
                if (!(sd > 0.0))
                {
                    // Every value is the same (or there is only one): no test can be calculated, and the normal plot has no
                    // scale to draw, which stopped the report with an exception from the chart.
                    variableParameters.AddOutput("skewness", Constant.MISSING);
                    variableParameters.AddOutput("kurtosis", Constant.MISSING);
                    variableParameters.AddOutput("k2", "Not calculated: there is no variation in the sample");
                    variableParameters.AddOutput("sw_w", "Not calculated: there is no variation in the sample");
                    variableParameters.AddOutput("sf_w", "Not calculated: there is no variation in the sample");
                    variableParameters.AddOutput("result", n < 2 ? "Normality cannot be tested: there is only one value" : "Normality cannot be tested: all the values are the same");
                    continue;
                }
                if (n < 8)
                {
                    variableParameters.AddOutput("skewness", skewness);
                    variableParameters.AddOutput("kurtosis", kurtosis);
                    variableParameters.AddOutput("k2", "Not calculated if sample size < 8");
                }
                else
                {
                    // a comma before each P, as the omnibus test line has
                    variableParameters.AddOutput("skewness", host.RoundU(skewness) + ",");
                    variableParameters.AddOutput("kurtosis", host.RoundU(kurtosis) + ",");
                    variableParameters.AddOutput("b1_p", b1P);
                    variableParameters.AddOutput("b2_p", b2P);
                    variableParameters.AddOutput("k2", host.RoundU(k2) + ",");
                    variableParameters.AddOutput("k2_p", k2P);
                }

                // Shapiro-Wilk
                normality_sw(data, 0, n, out double sw_w, out double sw_p, out double _, out double sw_v);
                if (n < 3)
                {
                    variableParameters.AddOutput("sw_w", "Not calculated if sample size < 3");
                }
                else
                {
                    variableParameters.AddOutput("sw_w", host.RoundU(sw_w) + ",");
                    variableParameters.AddOutput("sw_v", "V = " + host.RoundU(sw_v) + ",");
                    variableParameters.AddOutput("sw_p", sw_p);
                    if (n > 2000)
                        variableParameters.AddOutput("sw_p_warn", ": Test unreliable with more than 2000 observations.");
                }

                normality_sf(data, 0, n, out double sf_w, out double sf_v, out double _, out double sf_p);
                if (n < 5)
                {
                    variableParameters.AddOutput("sf_w", "Not calculated if sample size < 5");
                }
                else
                {
                    variableParameters.AddOutput("sf_w", host.RoundU(sf_w) + ",");
                    variableParameters.AddOutput("sf_v", "V' = " + host.RoundU(sf_v) + ",");
                    variableParameters.AddOutput("sf_p", sf_p);
                    if (n > 5000)
                        variableParameters.AddOutput("sf_p_warn", ": Test unreliable with more than 5000 observations.");
                }

                double pmin = Constant.MISSING;
                if (sw_p != Constant.MISSING)
                    pmin = sw_p;
                if (sf_p != Constant.MISSING && sf_p < pmin)
                    pmin = sf_p;
                if (pmin != Constant.MISSING)
                {
                    if (pmin < 0.05)
                        variableParameters.AddOutput("result", "Sample unlikely to be from a normal distribution");
                    else if (pmin < 0.1)
                        variableParameters.AddOutput("result", "Tests not quite significant but do not assume normality");
                    else
                        variableParameters.AddOutput("result", "No non-normality detected by tests: examine plot");
                }
                else
                {
                    variableParameters.AddOutput("result", n < 3 ? "Too few observations for the tests (at least 3 are needed)" : "Error in calculation");
                }

                NormalOptions nOptions = new() { ShouldScaleZ = true, Method = NormalOptions.ScoreMethod.Blom };
                ChartDefinition cd = new() { ChartOptions = nOptions, ChartType = ChartType.Normal };
                cd.XSeries.Add(new DoubleSeries(data, v0.Title));
                variableParameters.AddOutput("chart", cd);
            }
            return new StepOutput(outputParameters);
        }

        ///  <summary>
        ///  Royston's adjusted D'Agnostio ombibus test of skewness and kurtosis
        ///  </summary>
        ///  <param name="x">Vector of observations with zero lower bound</param>
        /// <param name="sd"></param>
        /// <param name="skewness">Fisher G1 coefficient of skewness</param>
        ///  <param name="lowerBound">Lower bound of observation vector</param>
        ///  <param name="n">Number of observations</param>
        ///  <param name="kurtosis">Fisher G2 coefficient of kurtosis</param>
        ///  <param name="sqrtb1">sqrt(B1)</param>
        ///  <param name="p_b1">Significance of sqrt(B1)</param>
        ///  <param name="b2">B2</param>
        ///  <param name="p_b2">Significance of B2</param>
        ///  <param name="k2">Royston adjusted omnibus test statistic K2</param>
        ///  <param name="p_k2">Significance of K2</param>
        /// <param name="mean"></param>
        /// <remarks>
        ///  D'Agostino RB, Belanger A, D'Agostino RB Jr. A suggestion for using powerful and informative tests of normality. American Statistician 1990;44(4):316-321.
        ///  Royston JP. Comment on sg3.4 and an improved D'Agostino test. sg3.5. Stata Technical Bulletin 1991;3:23-24.
        ///  </remarks>
        public static void normality_sk(double[] x, int lowerBound, int n, out double mean, out double sd, out double skewness, out double kurtosis, out double sqrtb1, out double p_b1, out double b2, out double p_b2, out double k2, out double p_k2)
        {
            // set on error exit values first
            sd = Constant.MISSING;
            skewness = Constant.MISSING;
            kurtosis = Constant.MISSING;
            sqrtb1 = Constant.MISSING;
            b2 = Constant.MISSING;
            p_b1 = Constant.MISSING;
            p_b2 = Constant.MISSING;
            k2 = Constant.MISSING;
            p_k2 = Constant.MISSING;

            // basic sums
            double nx = 0.0;
            double sum = 0.0;
            int i;
            for (i = lowerBound; i < n + lowerBound; i++)
            {
                if (x[i] != Constant.MISSING)
                {
                    nx += 1.0;
                    sum += x[i];
                }
            }
            mean = sum / nx;

            // moments of deviation from the mean - agrees with R moments package whereas Stata seems to have a rounding error at 7 or so significant digits
            double m1 = 0.0;
            double m2 = 0.0;
            double m3 = 0.0;
            double m4 = 0.0;
            // bool toobig = false; 
            for (i = lowerBound; i < n + lowerBound; i++)
            {
                double s = x[i] - mean;
                m2 += Math.Pow(s, 2.0);
                m3 += Math.Pow(s, 3.0);
                m4 += Math.Pow(s, 4.0);
                if (m4 > 1.0E+300)
                    return;
            }
            double var = (m2 - m1 * 2.0 / nx) / (nx - 1.0);
            sd = Math.Sqrt(var);
            if (var == 0.0)
                return;
            m2 /= nx;
            m3 /= nx;
            m4 /= nx;
            skewness = m3 * Math.Pow(m2, -1.5);
            kurtosis = m4 * Math.Pow(m2, -2.0);
            if (n < 8)
                return;

            // tests of skewness, kurtosis and omnibus k2
            sqrtb1 = (nx - 2.0) / Math.Sqrt(nx * (nx - 1.0)) * skewness;
            double y = skewness * Math.Sqrt((nx + 1.0) * (nx + 3.0) / (6.0 * (nx - 2.0)));
            double beta2 = 3.0 * (nx * nx + 27.0 * nx - 70.0) * (nx + 1.0) * (nx + 3.0) / ((nx - 2.0) * (nx + 5.0) * (nx + 7.0) * (nx + 9.0));
            double w2 = -1 + Math.Sqrt(2.0 * (beta2 - 1.0));
            double delta = 1.0 / Math.Sqrt(Math.Log(Math.Sqrt(w2)));
            double alpha = Math.Sqrt(2.0 / (w2 - 1.0));
            double z_b1 = Math.Abs(delta * Math.Log(y / alpha + Math.Sqrt(Math.Pow(y / alpha, 2.0) + 1.0)));
            p_b1 = 2.0 - 2.0 * PDF.alnorm(z_b1);

            b2 = 3.0 * (nx - 1.0) / (nx + 1.0) + (nx - 2.0) * (nx - 3.0) / ((nx + 1.0) * (nx - 1.0)) * kurtosis;
            double meanb2 = 3.0 * (nx - 1.0) / (nx + 1.0);
            double varb2 = 24.0 * nx * (nx - 2.0) * (nx - 3.0) / (Math.Pow(nx + 1.0, 2.0) * (nx + 3.0) * (nx + 5.0));
            double xx = (kurtosis - meanb2) / Math.Sqrt(varb2);
            double moment = 6.0 * (nx * nx - 5.0 * nx + 2.0) / ((nx + 7.0) * (nx + 9.0)) * Math.Sqrt(6.0 * (nx + 3.0) * (nx + 5.0) / (nx * (nx - 2.0) * (nx - 3.0)));
            double a = 6.0 + 8.0 / moment * (2.0 / moment + Math.Sqrt(1.0 + 4.0 / Math.Pow(moment, 2.0)));
            // The denominator of the base of the cube root reaches 0 when the sample is much flatter than the approximation
            // allows for (two point data with n above about 35): z tends to minus infinity as it does, and beyond that the base
            // is negative and the approximation no longer applies, so P is taken as 0 rather than left undefined.
            double wh = (1.0 - 2.0 / a) / (1.0 + xx * Math.Sqrt(2.0 / (a - 4.0)));
            double z_b2 = wh > 0.0
                ? Math.Abs((1.0 - 2.0 / (9.0 * a) - Math.Pow(wh, 1.0 / 3.0)) / Math.Sqrt(2.0 / (9.0 * a)))
                : double.PositiveInfinity;
            p_b2 = wh > 0.0 ? 2.0 - 2.0 * PDF.alnorm(z_b2) : 0.0;

            k2 = z_b1 * z_b1 + z_b2 * z_b2;
            p_k2 = double.IsPositiveInfinity(k2) ? 0.0 : PDF.chivalp(k2, 2.0);
            // Royston adjustment. The P of the raw K2 is exp(-k2 / 2); its normal deviate is found in log space when that would
            // underflow (k2 above about 1400), from the asymptotic upper tail Q(z) ~ exp(-z^2 / 2) / (z sqrt(2 pi)), that is
            // z^2 = k2 - 2 ln z - ln(2 pi); the underflow had left K2 unadjusted (1,780 printed for 17 zeros and 17 ones where
            // the adjusted value is 1,047). An infinite K2 (from the kurtosis guard above) is left as it is.
            double zc2 = 0.0;
            int ifault = double.IsPositiveInfinity(k2) ? 1 : 0;
            if (ifault == 0 && k2 < 1400.0)
            {
                zc2 = -PDF.gauinv(Math.Exp(-0.5 * k2), out ifault);
            }
            else if (ifault == 0)
            {
                zc2 = Math.Sqrt(k2);
                for (int it = 0; it < 8; it++)
                    zc2 = Math.Sqrt(k2 - 2.0 * Math.Log(zc2) - Math.Log(2.0 * Math.PI));
            }
            if (ifault == 0)
            {
                double logn = Math.Log(nx);
                double cut = 0.55 * Math.Pow(nx, 0.2) - 0.21;
                double a1 = (-5.0 + 3.46 * logn) * Math.Exp(-1.37 * logn);
                double b1 = 1.0 + (0.854 - 0.148 * logn) * Math.Exp(-0.55 * logn);
                double b2mb1 = 2.13 / (1.0 - 2.37 * logn);
                double a2 = a1 - b2mb1 * cut;
                double b2x = b2mb1 + b1;
                double z;
                if (zc2 < -1.0)
                {
                    z = zc2;
                }
                else if (zc2 < cut)
                {
                    z = a1 + b1 * zc2;
                }
                else
                {
                    z = a2 + b2x * zc2;
                }
                // ln P of the adjusted deviate, the upper tail asked for directly (1 - alnorm(z) was 0 for z above about 8) and in
                // log space beyond z = 30, so that the adjusted K2 = -2 ln P is printed even when P is below the smallest double
                double logP = z < 30.0
                    ? Math.Log(PDF.alnorm(-z))
                    : -0.5 * z * z - Math.Log(z) - 0.5 * Math.Log(2.0 * Math.PI) + Math.Log(1.0 - 1.0 / (z * z) + 3.0 / (z * z * z * z));
                if (!double.IsNaN(logP) && !double.IsPositiveInfinity(logP))
                {
                    k2 = -2.0 * logP;
                    p_k2 = Math.Exp(logP);
                }
            }

        }

        ///  <summary> Shapiro-Francia test for normality</summary>
        ///  <param name="x">Vector of observations</param>
        ///  <param name="lowerBound">Lower bound of observation vector</param>
        ///  <param name="n">Number of observations</param>
        ///  <param name="w">W test statistic</param>
        ///  <param name="p">Significance of W</param>
        ///  <param name="z">Normalised test statistic for W</param>
        ///  <param name="v">(1-W)/(median of 1-W)</param>
        ///  <remarks></remarks>
        private static void normality_sw(double[] x, int lowerBound, int n, out double w, out double p, out double z, out double v)
        {
            // set on error exit values first
            w = Constant.MISSING;
            p = Constant.MISSING;
            z = Constant.MISSING;
            v = Constant.MISSING;

            // clean observations
            double[] q = new double[n + 1];
            int i;
            int k = 0;
            for (i = lowerBound; i < n + lowerBound; i++)
            {
                if (x[i] != Constant.MISSING)
                {
                    k += 1;
                    q[k] = x[i];
                }
            }
            if (n < 3.0)
                return;

            // Blom scores for each position in the ordered sample, as in the published algorithm (Royston 1995) and in R.
            // Tied values had been given the same score, from their mid-rank, which moved W a little for tied data.
            double[] r = new double[n + 1];
            Array.Sort(q, 1, k);

            // normalised coefficients
            double nx = Convert.ToDouble(k);
            if (k == 3)
            {
                for (i = 1; i <= k; i++)
                    r[i] = Math.Sqrt(0.5) * Convert.ToDouble(i - 2);
            }
            else
            {
                for (i = 1; i <= k; i++)
                {
                    r[i] = PDF.gauinv((i - 0.375) / (nx + 0.25), out int ifault);
                    if (ifault != 0)
                        return;
                }
                double mean = 0.0;
                for (i = 1; i <= k; i++)
                    mean += r[i];
                mean /= nx;
                double m1 = 0.0;
                double m2 = 0.0;
                // bool toobig = false; 
                for (i = 1; i <= k; i++)
                {
                    double sx = r[i] - mean;
                    m2 += Math.Pow(sx, 2.0);
                    if (m2 > 1.0E+300)
                        return;
                }
                double var = (m2 - m1 * 2.0 / n) / (nx - 1.0);
                if (var == 0.0)
                    return;
                double summ2 = var * (nx - 1.0);
                double xx = 1.0 / Math.Sqrt(nx);
                double a1 = r[k] / Math.Sqrt(summ2) + xx * (0.221157 + xx * (-0.147981 + xx * (-2.07119 + xx * (4.434685 - xx * 2.706056))));
                int i1;
                double fac;
                if (k > 5)
                {
                    i1 = 3;
                    double a2 = r[k - 1] / Math.Sqrt(summ2) + xx * (0.042981 + xx * (-0.293762 + xx * (-1.752461 + xx * (5.682633 - xx * 3.582633))));
                    fac = Math.Sqrt((summ2 - 2.0 * Math.Pow(r[k], 2.0) - 2.0 * Math.Pow(r[k - 1], 2.0)) / (1.0 - 2.0 * Math.Pow(a1, 2.0) - 2.0 * Math.Pow(a2, 2.0)));
                    r[k] = a1;
                    r[k - 1] = a2;
                    r[1] = -a1;
                    r[2] = -a2;
                }
                else
                {
                    i1 = 2;
                    fac = Math.Sqrt((summ2 - 2.0 * Math.Pow(r[k], 2.0)) / (1.0 - 2.0 * Math.Pow(a1, 2.0)));
                    r[k] = a1;
                    r[1] = -a1;
                }
                int i2 = k - i1 + 1;
                for (i = i1; i <= i2; i++)
                    r[i] = r[i] / fac;
            }

            double rho = MathDbl.corr(q, r, 1, k, true);
            w = rho * rho;

            //  Evaluate P, Z and V [(1-W)/(median of 1-W)]
            double y = Math.Log(1.0 - w);
            double xq = Math.Log(nx);
            double m = 0.0;
            double s = 1.0;
            if (k == 3)
            {
                // the exact arcsine: a polynomial approximation to it moved P by up to 5e-5 and could make it slightly negative
                double stqr = Math.Asin(Math.Sqrt(0.75));
                p = Math.Max(0.0, 6.0 / Constant.PI * (Math.Asin(Math.Sqrt(w)) - stqr));
                z = -PDF.gauinv(p, out int ifault);
                v = (1.0 - w) / (1 - Math.Pow(Math.Sin(Constant.PI / 12.0 + stqr), 2.0));
            }
            else
            {
                if (k <= 11)
                {
                    double gamma = nx * 0.459 - 2.273;
                    if (y >= gamma)
                    {
                        y = 9.9999;
                        v = Constant.MISSING;
                    }
                    else
                    {
                        y = -Math.Log(-y + gamma);
                        m = 0.544 + nx * (-0.39978 + nx * (0.025054 - nx * 0.0006714));
                        s = Math.Exp(1.3822 + nx * (-0.77857 + nx * (0.062767 - nx * 0.0020322)));
                        v = (1.0 - w) / Math.Exp(gamma - Math.Exp(-m));
                    }
                }
                else
                {
                    m = -1.5861 + xq * (-0.31082 + xq * (-0.083751 + xq * 0.0038915));
                    s = Math.Exp(-0.4803 + xq * (-0.082676 + xq * 0.0030302));
                    v = (1.0 - w) / Math.Exp(m);
                }
                z = (y - m) / s;
                p = PDF.alnorm(-z);
            }

        }

        ///  <summary>
        ///  Shapiro-Francia test for normality
        ///  </summary>
        ///  <param name="x">Vector of observations with zero lower bound</param>
        /// <param name="n"> </param>
        /// <param name="w">W'</param>
        ///  <param name="v">V'</param>
        ///  <param name="z">Normalised statistic</param>
        ///  <param name="p">Significance</param>
        /// <param name="lowerBound"> </param>
        /// <remarks></remarks>
        private static void normality_sf(double[] x, int lowerBound, int n, out double w, out double v, out double z, out double p)
        {
            // set on error exit values first
            w = Constant.MISSING;
            v = Constant.MISSING;
            z = Constant.MISSING;
            p = Constant.MISSING;

            // clean observations
            double[] q = new double[n + 1 ];
            int i;
            int k = 0;
            for (i = lowerBound; i < n + lowerBound; i++)
            {
                if (x[i] != Constant.MISSING)
                {
                    k += 1;
                    q[k] = x[i];
                }
            }
            if (n < 5.0)
            {
                return;
            }

            // Blom scores for each position in the ordered sample, as published (Royston 1983); ties were mid-ranked before.
            double[] r = new double[n + 1 ];
            Array.Sort(q, 1, k);

            // Shapiro-Francia by Patrick Royston
            double nx = Convert.ToDouble(k);
            for (i = 1; i <= k; i++)
            {
                r[i] = PDF.gauinv((i - 0.375) / (nx + 0.25), out int ifault);
                if (ifault != 0)
                    return;
            }

            double h = Math.Log(nx) - 5.0;
            double l = -0.0480157 + h * (0.01971964 - 0.0119065 * h * h);
            double m = -Math.Exp(1.6930674 + h * (0.1441647 + h * (-0.01849276 + h * (0.031074485 + h * 0.0055717663))));
            double f = Math.Exp(-0.510725 + h * (-0.1160364 + h * (-0.006702098 + h * (0.054465944 + h * 0.0087397329))));
            double rho = MathDbl.corr(q, r, 1, k, true);
            w = rho * rho;
            double y = (Math.Pow(1.0 - w, l) - 1.0) / l;
            z = (y - m) / f;
            v = (1.0 - w) / Math.Pow(l * m + 1.0, 1.0 / l);
            p = PDF.alnorm(-z);
        }

        public static StepOutput RptTUnpairedSummary(ParameterBag parameters)
        {
            double GAMMA = parameters["gamma"].AsDouble;
            int nx1 = parameters["nx1"].AsInt32;
            double um1 = parameters["um1"].AsDouble;
            double sd1 = parameters["sd1"].AsDouble;
            int nx2 = parameters["nx2"].AsInt32;
            double um2 = parameters["um2"].AsDouble;
            double sd2 = parameters["sd2"].AsDouble;
            int degf = nx1 + nx2 - 2;
            if (nx1 < 2 || sd1 == 0 || nx2 < 2 || sd2 == 0)
                throw new Exception("Insufficient data (must be at least two members in each sample with non-zero standard deviations)");
            double var1 = sd1 * sd1;
            double var2 = sd2 * sd2;
            MathDbl.civ(degf, out double cit, GAMMA, out double P0);
            double xm1 = um1;
            double xm2 = um2;
            // t carries the sign of the difference (sample 1 less sample 2), as the confidence interval does.

            ParameterBag outputParameters = new();
            outputParameters.AddOutput("title_0", "* sample 1 from summary");
            outputParameters.AddOutput("mean_0", xm1);
            outputParameters.AddOutput("n0", nx1);
            outputParameters.AddOutput("title_1", "* sample 2 from summary");
            outputParameters.AddOutput("mean_1", xm2);
            outputParameters.AddOutput("n1", nx2);
            double xn1 = Convert.ToDouble(nx1);
            double xn2 = Convert.ToDouble(nx2);
            // equal variances
            double cv = (var1 * (nx1 - 1) + var2 * (nx2 - 1)) / (nx1 + nx2 - 2);
            double cn = 1.0 / nx1 + 1.0 / nx2;
            double cset = Math.Sqrt(cv) * Math.Sqrt(cn);
            double tstat = (um1 - um2) / cset;
            double power = Power.tstpower(1.0 - GAMMA, Math.Abs(um1 - um2), Math.Sqrt(cv), nx1, xn2 / xn1);
            outputParameters.AddOutput("error", cset);
            outputParameters.AddOutput("df", degf);
            outputParameters.AddOutput("t", tstat);
            double P = PDF.tvalp(Math.Abs(tstat), degf);
            if (P > 1.0 - P)
                P = 1.0 - P;
            outputParameters.AddOutput("p_1", P);
            outputParameters.AddOutput("p_2", P * 2.0);
            outputParameters.AddOutput("pc", 100 * (1 - P0));
            outputParameters.AddOutput("from", xm1 - xm2 - cit * cset);
            outputParameters.AddOutput("to", xm1 - xm2 + cit * cset);
            outputParameters.AddOutput("pwr", Formatting.pwr(power, 1.0 - GAMMA));
            // unequal variances
            cset = Math.Sqrt(var1 / xn1 + var2 / xn2);
            tstat = (um1 - um2) / cset;
            double xdegf = Math.Pow(var1 / xn1 + var2 / xn2, 2.0) / (Math.Pow(var1 / xn1, 2.0) / (xn1 - 1.0) + Math.Pow(var2 / xn2, 2.0) / (xn2 - 1.0));
            double citw = PDF.tfromp((1.0 - GAMMA) / 2.0, xdegf);
            outputParameters.AddOutput("error_unequal", cset);
            outputParameters.AddOutput("df_unequal", xdegf);
            outputParameters.AddOutput("t_unequal", tstat);
            P = PDF.tvalp(Math.Abs(tstat), xdegf);
            if (P > 1.0 - P)
                P = 1.0 - P;
            outputParameters.AddOutput("p_1_unequal", P);
            outputParameters.AddOutput("p_2_unequal", P * 2.0);
            outputParameters.AddOutput("pc_unequal", 100 * (1 - P0));
            outputParameters.AddOutput("from_unequal", xm1 - xm2 - citw * cset);
            outputParameters.AddOutput("to_unequal", xm1 - xm2 + citw * cset);
            power = Power.uvttpower(1.0 - GAMMA, Math.Abs(um1 - um2), xn1, xn2, sd1, sd2);
            outputParameters.AddOutput("pwr_unequal", Formatting.pwr(power, 1.0 - GAMMA));
            double f;
            if (Math.Abs(var1) > Math.Abs(var2))
            {
                f = var1 / var2;
                P = PDF.fvalp(f, nx1 - 1, nx2 - 1);
            }
            else
            {
                f = var2 / var1;
                P = PDF.fvalp(f, nx2 - 1, nx1 - 1);
            }
            if (P < 0.025)
            {
                outputParameters.AddOutput("say1", "TWO SIDED F TEST IS SIGNIFICANT");
                outputParameters.AddOutput("say2", "USE APPROXIMATE t (UNEQUAL VARIANCES) RESULT or ALTERNATIVELY MANN-WHITNEY");
            }
            else
            {
                outputParameters.AddOutput("say1", "Two sided F test is not significant");
                outputParameters.AddOutput("say2", "No need to assume unequal variances");
            }
            return new StepOutput(outputParameters);
        }

        public static StepOutput RptTSingleSummary(ParameterBag parameters)
        {

            double GAMMA = parameters["gamma"].AsDouble;
            int nx = parameters["nx"].AsInt32;
            double mu = parameters["mu"].AsDouble;
            double sd = parameters["sd1"].AsDouble;
            double mu0 = parameters["mu0"].AsDouble;

            int degf = nx - 1;
            if (nx < 2 || sd == 0)
                throw new Exception("Insufficient data (must be at least two members in the sample with non-zero standard deviation)");

            double se = sd / Math.Sqrt(nx);
            MathDbl.civ(degf, out double cit, GAMMA, out double P0);
            ParameterBag outputParameters = new();
            outputParameters.AddOutput("name", "* from summary data");
            outputParameters.AddOutput("sam_mean", mu);
            outputParameters.AddOutput("pop_mean", mu0);
            outputParameters.AddOutput("size", nx);
            outputParameters.AddOutput("sd", sd);
            outputParameters.AddOutput("pc", 100 * (1 - P0));
            outputParameters.AddOutput("for", mu0 == 0 ? "for the mean" : "for mean difference");
            outputParameters.AddOutput("from", mu - mu0 - cit * se);
            outputParameters.AddOutput("to", mu - mu0 + cit * se);
            double t = (mu - mu0) / se;
            degf = nx - 1;
            double P = PDF.tvalp(Math.Abs(t), Convert.ToDouble(degf));
            if (P > 1.0 - P)
                P = 1.0 - P;
            double power = Power.ptpower(1.0 - GAMMA, mu - mu0, sd, Convert.ToDouble(nx));
            outputParameters.AddOutput("df", degf);
            outputParameters.AddOutput("t", t);
            outputParameters.AddOutput("p_1", P);
            outputParameters.AddOutput("p_2", P * 2.0);
            outputParameters.AddOutput("pwr", Formatting.pwr(power, 1.0 - GAMMA));
            return new StepOutput(outputParameters);
        }

        public static StepOutput RptTUnpaired(ParameterBag parameters)
        {
            int bot; int top;

            double[] mean = new double[1 + 1 /* VB to C# conversion */ ];
            double[] ss = new double[1 + 1 /* VB to C# conversion */ ];
            double[] var = new double[1 + 1 /* VB to C# conversion */ ];
            double[] sd = new double[1 + 1 /* VB to C# conversion */ ];
            double[] sem = new double[1 + 1 /* VB to C# conversion */ ];
            int[] tnx = new int[1 + 1 /* VB to C# conversion */];
            double GAMMA = parameters["gamma"].AsDouble;
            DataFrame data = parameters["data"].AsDataFrame;
            Para(data, mean, ss, var, sd, sem, tnx);
            int degf = tnx[0] + tnx[1] - 2;
            MathDbl.civ(degf, out double cit, GAMMA, out double P0);
            // t carries the sign of the difference (first sample less second), as the confidence interval does; the one sided P is
            // the tail beyond the observed difference either way. Both t values were made positive by swapping the means here.
            double um1 = mean[0];
            double um2 = mean[1];
            ParameterBag outputParameters = new();
            outputParameters.AddOutput("title_0", data.Variables[0].Title);
            outputParameters.AddOutput("mean_0", mean[0]);
            outputParameters.AddOutput("n0", tnx[0]);
            outputParameters.AddOutput("title_1", data.Variables[1].Title);
            outputParameters.AddOutput("mean_1", mean[1]);
            outputParameters.AddOutput("n1", tnx[1]);
            // equal variances
            double cv = (ss[0] + ss[1]) / (tnx[0] + tnx[1] - 2);
            double cn = 1.0 / tnx[0] + 1.0 / tnx[1];
            double cset = Math.Sqrt(cv * cn);
            double tstat = (um1 - um2) / cset;
            double power = Power.tstpower(1.0 - GAMMA, Math.Abs(um1 - um2), Math.Sqrt(cv), tnx[0], Convert.ToDouble(tnx[1]) / tnx[0]);
            outputParameters.AddOutput("error", cset);
            outputParameters.AddOutput("df", degf);
            outputParameters.AddOutput("t", tstat);
            double P = PDF.tvalp(Math.Abs(tstat), degf);
            if (P > 1.0 - P)
                P = 1.0 - P;
            outputParameters.AddOutput("p_1", P);
            outputParameters.AddOutput("p_2", P * 2.0);
            outputParameters.AddOutput("pc", 100 * (1 - P0));
            outputParameters.AddOutput("from", mean[0] - mean[1] - cit * cset);
            outputParameters.AddOutput("to", mean[0] - mean[1] + cit * cset);
            outputParameters.AddOutput("pwr", Formatting.pwr(power, 1.0 - GAMMA));
            // unequal variances
            double xs1 = ss[0] / (tnx[0] - 1);
            double xs2 = ss[1] / (tnx[1] - 1);
            double xn1 = tnx[0];
            double xn2 = tnx[1];
            cset = Math.Sqrt(xs1 / xn1 + xs2 / xn2);
            tstat = (um1 - um2) / cset;
            double xdegf = Math.Pow(xs1 / xn1 + xs2 / xn2, 2.0) / (Math.Pow(xs1 / xn1, 2.0) / (xn1 - 1.0) + Math.Pow(xs2 / xn2, 2.0) / (xn2 - 1.0));
            double citw = PDF.tfromp((1.0 - GAMMA) / 2.0, xdegf);
            outputParameters.AddOutput("error_unequal", cset);
            outputParameters.AddOutput("df_unequal", xdegf);
            outputParameters.AddOutput("t_unequal", tstat);
            P = PDF.tvalp(Math.Abs(tstat), xdegf);
            if (P > 1.0 - P)
                P = 1.0 - P;
            outputParameters.AddOutput("p_1_unequal", P);
            outputParameters.AddOutput("p_2_unequal", P * 2.0);
            outputParameters.AddOutput("pc_unequal", 100 * (1 - P0));
            outputParameters.AddOutput("from_unequal", mean[0] - mean[1] - citw * cset);
            outputParameters.AddOutput("to_unequal", mean[0] - mean[1] + citw * cset);
            power = Power.uvttpower(1.0 - GAMMA, Math.Abs(um1 - um2), tnx[0], tnx[1], sd[0], sd[1]);
            outputParameters.AddOutput("pwr_unequal", Formatting.pwr(power, 1.0 - GAMMA));
            if (Math.Abs(var[0]) > Math.Abs(var[1]))
            {
                top = 0;
                bot = 1;
            }
            else
            {
                top = 1;
                bot = 0;
            }
            double f = var[top] / var[bot];
            P = PDF.fvalp(f, tnx[top] - 1, tnx[bot] - 1);
            if (double.IsNaN(f) || double.IsInfinity(f) || double.IsNaN(P))
            {
                outputParameters.AddOutput("say1", "F test not calculated: a variance is zero or a sample has fewer than two values");
                outputParameters.AddOutput("say2", string.Empty);
            }
            else if (P < 0.025)
            {
                outputParameters.AddOutput("say1", "TWO SIDED F TEST IS SIGNIFICANT");
                outputParameters.AddOutput("say2", "USE APPROXIMATE t (UNEQUAL VARIANCES) RESULT or ALTERNATIVELY MANN-WHITNEY");
            }
            else
            {
                outputParameters.AddOutput("say1", "Two sided F test is not significant");
                outputParameters.AddOutput("say2", "No need to assume unequal variances");
            }
            return new StepOutput(outputParameters);
        }

        public static StepOutput RptTSingle(ParameterBag parameters)
        {
            double[] mean = new double[1];
            double[] ss = new double[1];
            double[] var = new double[1];
            double[] sd = new double[1];
            double[] sem = new double[1];
            int[] tnx = new int[1];

            DataFrame Data = parameters["data"].AsDataFrame;
            double mu0 = parameters["population-mean"].AsDouble;
            double GAMMA = parameters["gamma"].AsDouble;

            Para(Data, mean, ss, var, sd, sem, tnx);
            int degf = tnx[0] - 1;
            MathDbl.civ(degf, out double cit, GAMMA, out double P0);
            ParameterBag outputParameters = new();
            outputParameters.AddOutput("name", Data.Variables[0].Title);
            outputParameters.AddOutput("sam_mean", mean[0]);
            outputParameters.AddOutput("pop_mean", mu0);
            outputParameters.AddOutput("size", tnx[0]);
            outputParameters.AddOutput("sd", sd[0]);
            outputParameters.AddOutput("pc", 100 * (1 - P0));
            outputParameters.AddOutput("for", mu0 == 0 ? "for the mean" : "for mean difference");
            outputParameters.AddOutput("from", mean[0] - mu0 - cit * sem[0]);
            outputParameters.AddOutput("to", mean[0] - mu0 + cit * sem[0]);
            double t = (mean[0] - mu0) / sem[0];
            degf = tnx[0] - 1;
            double P = PDF.tvalp(Math.Abs(t), degf);
            if (P > 1.0 - P)
                P = 1.0 - P;
            double power = Power.ptpower(1.0 - GAMMA, mean[0] - mu0, sd[0], tnx[0]);
            outputParameters.AddOutput("df", degf);
            outputParameters.AddOutput("t", t);
            outputParameters.AddOutput("p_1", P);
            outputParameters.AddOutput("p_2", P * 2.0);
            outputParameters.AddOutput("pwr", Formatting.pwr(power, 1.0 - GAMMA));
            return new StepOutput(outputParameters);
        }

        public static StepOutput RptTPaired(ParameterBag parameters)
        {
            DataFrame Data = parameters["data"].AsDataFrame;
            double GAMMA = parameters["gamma"].AsDouble;
            bool DoAgree = Data.VariableCount > 1 && parameters.ContainsKey("doAgreement") && parameters["doAgreement"].AsBoolean;

            double[] arr1 = new double[Data.MaxRows + 1 ]; // New array to replace Arr2(0,n)
            DoubleVariable v0 = Data.Variables[0]as DoubleVariable;
            int nx = 0;
            string txc;
            if (Data.VariableCount == 1)
            {
                for (int n = 0; n < v0.Length; n++)
                {
                    if (v0.Data[n] != Constant.MISSING)
                    {
                        nx++;
                        arr1[nx] = v0.Data[n];
                    }
                }
                txc = "differences listed in " + v0.Title;
            }
            else
            {
                DoubleVariable v1 = Data.Variables[1]as DoubleVariable;
                for (int n = 0; n < v0.Length; n++)
                {
                    if (v0.Data[n] != Constant.MISSING && v1.Data[n] != Constant.MISSING)
                    {
                        nx++;
                        arr1[nx] = v0.Data[n] - v1.Data[n];
                    }
                }
                txc = "differences between " + v0.Title + " and " + v1.Title;
            }

            Univariate(arr1, nx, out double sum, out double mean, out double var);
            double sd = Math.Sqrt(var);
            double sem = sd / Math.Sqrt(nx);
            int degf = nx - 1;
            MathDbl.civ(degf, out double cit, GAMMA, out double P0);
            ParameterBag outputParameters = new();
            outputParameters.AddOutput("label", txc);
            outputParameters.AddOutput("mean", mean);
            outputParameters.AddOutput("n", nx);
            outputParameters.AddOutput("sd", sd);
            outputParameters.AddOutput("sem", sem);
            double z = PDF.gauinv(1.0 - P0 / 2.0);
            double lla = mean - z * sd;
            double ula = mean + z * sd;
            outputParameters.AddOutput("pc", 100 * (1.0 - P0));
            outputParameters.AddOutput("from", mean - cit * sem);
            outputParameters.AddOutput("to", mean + cit * sem);
            // With no variation in the differences t is infinite (mean not 0) or undefined (mean 0), and P follows: it was
            // printed as P < 0.0001 for a mean difference of 0 because t had been set to the missing value code instead.
            double t = mean / sem;
            double power = Power.ptpower(1.0 - GAMMA, mean, sd, nx);
            outputParameters.AddOutput("df", nx - 1);
            outputParameters.AddOutput("t", t);
            double tstat = t;
            double P = PDF.tvalp(Math.Abs(tstat), degf);
            if (P > 1.0 - P)
                P = 1.0 - P;
            outputParameters.AddOutput("tail_1", P);
            outputParameters.AddOutput("tail_2", P * 2.0);
            outputParameters.AddOutput("pwr", Formatting.pwr(power, 1.0 - GAMMA));
            if (DoAgree)
            {
                IList<ParameterBag> twosampleList = new List<ParameterBag>();
                outputParameters.AddOutput("*twosample", twosampleList);
                ParameterBag twosampleParameters = new();
                twosampleList.Add(twosampleParameters);
                twosampleParameters.AddOutput("from2", lla);
                twosampleParameters.AddOutput("to2", ula);
                if (!(sd > 0.0) || nx < 2)
                {
                    // With no spread in the differences the agreement plot has no scale to draw, and it stopped the whole
                    // report with an exception from the chart.
                    twosampleParameters.AddOutput("note", "(no plot: the differences do not vary)");
                    outputParameters.AddOutput("*chart", null);
                }
                else
                {
                IList<ParameterBag> chartList = new List<ParameterBag>();
                outputParameters.AddOutput("*chart", chartList);

                DoubleVariable v1 = Data.Variables[1]as DoubleVariable;
                double[] x = new double[v0.Length + 1 ];
                double[] y = new double[v1.Length + 1 ];
                x[0] = Constant.MISSING;
                y[0] = Constant.MISSING;
                nx = 0;
                for (int j = 0; j < v0.Length; j++)
                {
                    if (v0.Data[j] != Constant.MISSING && v1.Data[j] != Constant.MISSING)
                    {
                        nx += 1;
                        y[nx] = v0.Data[j] - v1.Data[j];
                        x[nx] = (v0.Data[j] + v1.Data[j]) / 2;
                    }
                }

                ParameterBag chartParameters = new();
                chartList.Add(chartParameters);
                chartParameters.AddOutput("chart", ChartRendererFactory.PrepForLater(ChartType.Ties, new TiesOptions(x, y, nx, lla, ula, GAMMA, v0.Title, v1.Title, mean)));
                }
            }
            else
            {
                outputParameters.AddOutput("*twosample", null);
                outputParameters.AddOutput("*chart", null);
            }
            return new StepOutput(outputParameters);
        }
    }
}
