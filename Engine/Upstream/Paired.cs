using System;
using System.Collections.Generic;
using StatsDirect.Utilities;
using StatsDirect.Templates;
using StatsDirect.Numerics;
using StatsDirect.Data;
using StatsDirect.Charting;
namespace StatsDirect.Builtins { public static class Parametric {
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
}}
