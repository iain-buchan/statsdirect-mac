using StatsDirect.Charting;
using StatsDirect.Data;
using StatsDirect.Numerics;
using StatsDirect.Templates;
using StatsDirect.Utilities;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;

namespace StatsDirect.Builtins
{
    public static class Regress
    {
        ///  <summary>
        ///  The equivalent of the PASS_* variables in SD2, so PASS_X is X in this class
        ///  </summary>
        ///  <remarks></remarks>
        [Serializable]
        private class MultipleLinearRegressionContext
        {
            public double[] Arg { get; set; }
            public double[] B { get; set; }
            public double[] Covariance { get; set; }
            public double DEV { get; set; }
            public double DEVX { get; set; }
            public int DF { get; set; }
            public int DFX { get; set; }
            public bool DoC { get; set; }
            public double[] DV { get; set; }
            public int M { get; set; }
            public double[] FV { get; set; }
            public double[] H1 { get; set; }
            public double[,] H { get; set; }
            public string[] Labels { get; set; }
            public double LLX { get; set; }
            public int N { get; set; }
            public string OutcomeTitle { get; set; }
            public int P { get; set; }
            public double[] R { get; set; }
            public double[,] R2 { get; set; }
            public int RANK { get; set; }
            public double[] RV { get; set; }
            public int[] RXI { get; set; }

            ///  <summary>
            ///  Weights
            ///  </summary>
            public double[] S { get; set; }

            public double[] Se { get; set; }
            public double SSREG { get; set; }
            public double SSY { get; set; }
            public double[] SV { get; set; }
            /// <summary>
            /// Trials
            /// </summary>
            public double[] T { get; set; }

            /// <remarks>1-based when used as predictor titles, 0-based when used for polynomial regression.  Sorry!</remarks>
            public string[] Titles { get; set; }

            public double TOL { get; set; }
            //public double[] V1;
            public double[,] V { get; set; }
            public double[] VIF { get; set; }
            public string warn { get; set; }
            public bool WEIGHT { get; set; }
            public string weightTitle { get; set; }
            public double[] WT { get; set; }
            public double[,] X { get; set; }
            public double[] X1 { get; set; }
            /// <summary>
            /// Events
            /// </summary>
            public double[] Y { get; set; }

            internal MultipleLinearRegressionContext StripForOutput()
            {
                // No space saving required
                return this;
            }
        }

        /// <summary>
        /// Remove missing rows from assumed parameters y and x, and return the missings in the order Y, X.
        /// </summary>
        private static DoubleArraysAndBooleans GetSimpleLinearRegressionYX(ParameterBag parameters, out string yTitle, out string xTitle)
        {
            DataFrame fy = parameters["y"].AsDataFrame;
            DoubleVariable vy = (DoubleVariable)fy.Variables[0];
            DataFrame fx = parameters["x"].AsDataFrame;
            DoubleVariable vx = (DoubleVariable)fx.Variables[0];
            yTitle = vy.Title;
            xTitle = vx.Title;
            return Numerics.Utilities.RemoveMissingRows(new[] { vy.Data, vx.Data }, 0, vy.Length, 0);
        }

        private static SimpleLinearRegressionContext GetSimpleLinearRegressionContext(ParameterBag parameters)
        {
            // If there's already a cached context, assume it is from a previous operation with the same values and use it.
            if (parameters.ContainsKey("context"))
                return (SimpleLinearRegressionContext)parameters["context"].AsObject;

            // Create a new context holding these X and Y variables
            return GetSimpleLinearRegressionContextWithData(parameters);
        }

        private static SimpleLinearRegressionContext GetSimpleLinearRegressionContextWithData(ParameterBag parameters)
        {
            DoubleArraysAndBooleans copiesRemovingMissingRows = GetSimpleLinearRegressionYX(parameters, out string yTitle, out string xTitle);
            return new SimpleLinearRegressionContext(copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[1], copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[0], xTitle, yTitle);
        }

        private static MultipleLinearRegressionContext GetMultipleLinearRegressionContext(ParameterBag parameters)
        {
            if (parameters.ContainsKey("context"))
                return (MultipleLinearRegressionContext)parameters["context"].AsObject;
            throw new Exception("Expected to find a context parameter and didn't");
        }

        public static StepOutput RptInterpolateXY(ParameterBag parameters)
        {
            SimpleLinearRegressionContext context = GetSimpleLinearRegressionContext(parameters);
            double newx = parameters["newx"].AsDouble;
            double newy = newx * context.Slope + context.YIntercept;
            ParameterBag outputParameters = new();
            outputParameters.AddOutput("t1", context.XTitle);
            outputParameters.AddOutput("v1", newx);
            outputParameters.AddOutput("t2", context.YTitle);
            outputParameters.AddOutput("v2", newy);
            return new StepOutput(outputParameters);
        }

        public static StepOutput RptInterpolateYX(ParameterBag parameters)
        {
            SimpleLinearRegressionContext context = GetSimpleLinearRegressionContext(parameters);
            double newy = parameters["newy"].AsDouble;
            double newx = (newy - context.YIntercept) / context.Slope;
            ParameterBag outputParameters = new();
            outputParameters.AddOutput("t1", context.YTitle);
            outputParameters.AddOutput("v1", newy);
            outputParameters.AddOutput("t2", context.XTitle);
            outputParameters.AddOutput("v2", newx);
            return new StepOutput(outputParameters);
        }

        public static StepOutput RptRanv(ParameterBag parameters)
        {
            SimpleLinearRegressionContext context = GetSimpleLinearRegressionContext(parameters);
            ParameterBag outputParameters = new();
            outputParameters.AddOutput("reg_sum", context.SSREG);
            outputParameters.AddOutput("reg_df", "1");
            outputParameters.AddOutput("reg_mean", context.SSREG);
            outputParameters.AddOutput("res_sum", context.SSY - context.SSREG);
            double resDf = context.NX - 2;
            outputParameters.AddOutput("res_df", resDf);
            outputParameters.AddOutput("res_mean", (context.SSY - context.SSREG) / resDf);
            outputParameters.AddOutput("tot_sum", context.SSY);
            double totDf = context.NX - 1;
            outputParameters.AddOutput("tot_df", totDf);
            double vr = context.SSREG / ((context.SSY - context.SSREG) / resDf);
            outputParameters.AddOutput("f", vr);
            double prob = PDF.fvalp(vr, 1.0, resDf);
            outputParameters.AddOutput("p", prob);
            outputParameters.AddOutput("r", context.SSREG / context.SSY);
            outputParameters.AddOutput("mse", Math.Sqrt((context.SSY - context.SSREG) / resDf));
            return new StepOutput(outputParameters);
        }

        public static StepOutput RptSimpleLinearRegression(ParameterBag parameters)
        {
            SimpleLinearRegressionContext context = GetSimpleLinearRegressionContext(parameters);

            double reggamma = parameters["gamma"].AsDouble;
            if (reggamma <= 0.0)
                throw new Exception("GAMMA must be greater than zero");

            context.CalculateLeastSquaresMethod();
            context.CalcRcia(reggamma);
            ParameterBag outputParameters = new();
            outputParameters.AddOutput("ytitle", context.YTitle);
            outputParameters.AddOutput("slope", context.Slope);
            outputParameters.AddOutput("xtitle", context.XTitle);
            outputParameters.AddOutput("lnk", context.YIntercept < 0.0 ? "-" : "+");
            outputParameters.AddOutput("abs_yintercept", Math.Abs(context.YIntercept));
            if (!context.IsPerfectCorrelation)
            {
                IList<ParameterBag> seList = new List<ParameterBag>();
                outputParameters.AddOutput("*se", seList);
                ParameterBag seParameters = new();
                seList.Add(seParameters);
                double seb = context.SeEst / (context.SDX * Math.Sqrt(context.NX - 1));
                seParameters.AddOutput("slope_err", seb);
                seParameters.AddOutput("se_pc", 100 * (1.0 - context.P0));
                seParameters.AddOutput("se_from", context.Slope - context.CIT * seb);
                seParameters.AddOutput("se_to", context.Slope + context.CIT * seb);
                seParameters.AddOutput("se_r", context.R);
                seParameters.AddOutput("se_r2", context.R * context.R);
                if (context.NX > 3)
                {
                    IList<ParameterBag> ciList = new List<ParameterBag>();
                    seParameters.AddOutput("*ci", ciList);
                    ParameterBag ciParameters = new();
                    ciList.Add(ciParameters);
                    double GAMMA = 1.0 - context.P0 / 2.0;
                    double rcit = PDF.gauinv(GAMMA);
                    double fz = 0.5 * Math.Log((1.0 + context.R) / (1.0 - context.R));
                    double fz1 = fz - rcit / Math.Sqrt(context.NX - 3);
                    double fz2 = fz + rcit / Math.Sqrt(context.NX - 3);
                    double con1 = (Math.Exp(2.0 * fz1) - 1.0) / (Math.Exp(2.0 * fz1) + 1.0);
                    double con2 = (Math.Exp(2.0 * fz2) - 1.0) / (Math.Exp(2.0 * fz2) + 1.0);
                    ciParameters.AddOutput("ci_pc", 100 * (1.0 - context.P0));
                    ciParameters.AddOutput("ci_from", con1);
                    ciParameters.AddOutput("ci_to", con2);
                    // double af = 1; 
                    int df = context.NX - 2;
                    double r = context.R;
                    double st = r * Math.Sqrt(Math.Abs(df / (1.0 - r * r)));
                    ciParameters.AddOutput("df", df);
                    ciParameters.AddOutput("tdf", st);
                    double P = PDF.tvalp(Math.Abs(st), df);
                    if (P > 1.0 - P)
                        P = 1.0 - P;
                    P = 2.0 * P;
                    ciParameters.AddOutput("p", P);
                    ciParameters.AddOutput("pwr", Formatting.pwr(Power.rpower(0.0, r, context.NX, context.P0), context.P0));
                    string x = "Correlation coefficient is ";
                    if (P > 0.05)
                        x += "not ";
                    ciParameters.AddOutput("sig", x + "significantly different from zero");
                }
                else
                {
                    seParameters.AddOutput("*ci", null);
                }
                outputParameters.AddOutput("*notcalc", null);
            }
            else
            {
                // Perfect correlation
                outputParameters.AddOutput("*se", null);
                IList<ParameterBag> notcalcList = new List<ParameterBag>();
                outputParameters.AddOutput("*notcalc", notcalcList);
                ParameterBag notcalcParameters = new();
                notcalcList.Add(notcalcParameters);
                notcalcParameters.AddOutput("r", context.R);
            }

            outputParameters.AddInput("context", context.StripForOutput());
            return new StepOutput(outputParameters);
        }

        public static StepOutput PlotSimpleLinearRegression(ParameterBag parameters)
        {
            SimpleLinearRegressionContext context = GetSimpleLinearRegressionContext(parameters);
            ParameterBag outputParameters = new();
            outputParameters.AddOutput("mdnValue", context.Slope);
            outputParameters.AddOutput("interceptValue", context.YIntercept);
            outputParameters.AddOutput("xtitle", context.XTitle);
            outputParameters.AddOutput("ytitle", context.YTitle);
            outputParameters.AddOutput("chartIsFullWidth", true);
            return new StepOutput(outputParameters);
        }

        public static StepOutput PlotResidualsSimple(ParameterBag parameters)
        {
            SimpleLinearRegressionContext context = GetSimpleLinearRegressionContextWithData(parameters);
            context.CalculateLeastSquaresMethod();

            int nx = context.NX;
            ParameterBag outputParameters = new();
            double[] predicted = new double[nx];
            double[] residual = new double[nx];
            for (int j = 0; j < nx; j++)
            {
                predicted[j] = context.X[j] * context.Slope + context.YIntercept;
                residual[j] = context.Y[j] - predicted[j];
            }
            outputParameters.AddOutput("residualsVsY", ChartRendererFactory.PrepForLater(ChartType.Xy, new XyOptions(predicted, residual, "Fitted " + context.YTitle, "Residuals (Y - y fit)", "Residuals vs. Fitted Y [linear regression]", true, DataMinMax.XCalc_YCalc)));
            outputParameters.AddOutput("residualsVsPredictor", ChartRendererFactory.PrepForLater(ChartType.Xy, new XyOptions(context.X, residual, "Predictor: " + context.XTitle, "Residuals (Y - y fit)", "Residuals vs. Predictor [linear regression]", true, DataMinMax.XCalc_YCalc)));

            double[] ranked = new double[nx];
            Array.Copy(residual, ranked, nx);
            double[] ranks = new double[nx];
            ExFortran.Rank(ranked, ranks, 0, nx, 0, out double _);
            for (int j = 0; j < nx; j++)
            {
                //  van der Waerden normal scores, Conover P 396
                ranks[j] = PDF.gauinv(ranks[j] / (nx + 1.0), out int ifault);
                if (ifault != 0)
                    predicted[j] = Constant.MISSING;
            }
            outputParameters.AddOutput("residualsNormalPlot", ChartRendererFactory.PrepForLater(ChartType.Xy, new XyOptions(ranked, ranks, "Residual (Y - y fit)", "van der Waerden normal score", "Normal Plot for Residuals [linear regression]", false, DataMinMax.XCalc_YCalc)));
            return new StepOutput(outputParameters);
        }

        /// <summary>
        /// Plot Standard Error and 95% confidence interval for simple linear regression
        /// </summary>
        /// <param name="host"></param>
        /// <param name="parameters"></param>
        /// <returns></returns>
        public static StepOutput PlotSeCi(ParameterBag parameters)
        {
            SimpleLinearRegressionContext context = GetSimpleLinearRegressionContextWithData(parameters);
            context.CalculateLeastSquaresMethod();
            double REGGAMMA = parameters["reggamma"].AsDouble;
            context.CalcRcia(REGGAMMA);

            ParameterBag outputParameters = new();
            outputParameters.AddOutput("chart", ChartRendererFactory.PrepForLater(ChartType.LinearRegressionAndMaybeSeCiOrPredictionInterval, new LinearRegressionAndMaybeSeCiOrPredictionIntervalOptions("SE and " + Formatting.XRound((1.0 - context.P0) * 100, 1) + "% CI for regression estimate", context.Slope, context.YIntercept, true, context.XTitle, context.YTitle, context.PERT, context.NX, context.MS, context.SumX, context.SSX, false), new DoubleSeries(context.X, context.XTitle), new DoubleSeries(context.Y, context.YTitle)));
            return new StepOutput(outputParameters);
        }

        public static StepOutput PlotPredictionInterval(ParameterBag parameters)
        {
            SimpleLinearRegressionContext context = GetSimpleLinearRegressionContextWithData(parameters);
            context.CalculateLeastSquaresMethod();
            double REGGAMMA = parameters["gamma"].AsDouble;
            context.CalcRcia(REGGAMMA);

            ParameterBag outputParameters = new();
            outputParameters.AddOutput("chart", ChartRendererFactory.PrepForLater(ChartType.LinearRegressionAndMaybeSeCiOrPredictionInterval, new LinearRegressionAndMaybeSeCiOrPredictionIntervalOptions(Formatting.XRound((1.0 - context.P0) * 100, 1) + "% Prediction Interval", context.Slope, context.YIntercept, true, context.XTitle, context.YTitle, context.PERT, context.NX, context.MS, context.SumX, context.SSX, true), new DoubleSeries(context.X, context.XTitle), new DoubleSeries(context.Y, context.YTitle)));
            return new StepOutput(outputParameters);
        }

        public static StepOutput RptCiMeanY(ParameterBag parameters)
        {
            SimpleLinearRegressionContext context = GetSimpleLinearRegressionContext(parameters);
            int nx = context.NX;
            double reggamma = parameters["reggamma"].AsDouble;
            context.CalcRcia(reggamma);
            double xa = parameters["xa"].AsDouble;
            double sey = Math.Sqrt(context.MS * (1.0 / nx + Math.Pow(xa - context.SumX / nx, 2.0) / context.SSX));
            double ya = context.Slope * xa + context.YIntercept;
            double pcon = ya + sey * context.PERT;
            double ncon = ya - sey * context.PERT;
            ParameterBag outputParameters = new();
            outputParameters.AddOutput("xtitle", context.XTitle);
            outputParameters.AddOutput("ytitle", context.YTitle);
            outputParameters.AddOutput("var_x", xa);
            outputParameters.AddOutput("var_y", ya);
            outputParameters.AddOutput("ci_y", sey);
            outputParameters.AddOutput("pci", 100 * (1.0 - context.P0));
            outputParameters.AddOutput("fromi", ncon);
            outputParameters.AddOutput("toi", pcon);
            double spred = Math.Sqrt(context.MS * (1.0 + (1.0 / nx + Math.Pow(xa - context.SumX / nx, 2.0) / context.SSX)));
            pcon = ya + spred * context.PERT;
            ncon = ya - spred * context.PERT;
            outputParameters.AddOutput("s_pred", spred);
            outputParameters.AddOutput("pcp", 100 * (1.0 - context.P0));
            outputParameters.AddOutput("fromp", ncon);
            outputParameters.AddOutput("top", pcon);
            return new StepOutput(outputParameters);
        }

        public static StepOutput CalcSimpleLinearRegressionCi(ParameterBag parameters)
        {
            SimpleLinearRegressionContext context = GetSimpleLinearRegressionContextWithData(parameters);
            double REGGAMMA = parameters["gamma"].AsDouble;
            int nx = context.NX;
            context.CalcRcia(REGGAMMA);

            DataFrame outputFrame = new();
            DoubleVariable reg = new(nx, "Reg~" + context.YTitle);
            outputFrame.Variables.Add(reg);

            DoubleVariable uci = new(nx, "UCI~" + context.YTitle);
            outputFrame.Variables.Add(uci);

            DoubleVariable lci = new(nx, "LCI~" + context.YTitle);
            outputFrame.Variables.Add(lci);

            for (int j = 0; j < nx; j++)
            {
                double sey = Math.Sqrt(context.MS * (1.0 / nx + Math.Pow(context.Y[j] - context.SumX / nx, 2.0) / context.SSX));
                double ya = context.Slope * context.X[j] + context.YIntercept;
                double pcon = ya + sey * context.PERT;
                double ncon = ya - sey * context.PERT;
                reg.Data[j] = ya;
                uci.Data[j] = pcon;
                lci.Data[j] = ncon;
            }
            ParameterBag outputParameters = new();
            outputParameters.AddOutput("data", outputFrame);
            return new StepOutput(outputParameters);
        }

        public static StepOutput RptPrincipalComponentsRegressionCorrelation(ParameterBag parameters)
        {
            DataFrame frame = parameters["data"].AsDataFrame;
            bool correctForReversal = parameters["correctForReversal"].AsBoolean;
            return CalcPrincipal(frame, out double[,] _, out double[,] _, out double[,] _, out double[,] _, 1, out int _, out int _, correctForReversal);
        }

        public static StepOutput RptPrincipalComponentsRegressionCovariance(ParameterBag parameters)
        {
            DataFrame frame = parameters["data"].AsDataFrame;
            bool correctForReversal = parameters["correctForReversal"].AsBoolean;
            return CalcPrincipal(frame, out double[,] _, out double[,] _, out double[,] _, out double[,] _, 2, out int _, out int _, correctForReversal);
        }

        ///  <summary>
        ///  
        ///  </summary>
        /// <param name="frame"></param>
        /// <param name="x">Set to...</param>
        ///  <param name="xc">Set to...</param>
        ///  <param name="xr">Set to...</param>
        ///  <param name="v">Set to...</param>
        ///  <param name="irv">Passed in as 1 for correlation ("corral"), 2 for covariance ("covar")</param>
        ///  <param name="n">Set to the number of columns in the input</param>
        ///  <param name="nx">Set to the number of rows in the input</param>
        /// <param name="host"></param>
        /// <param name="correctForReversal"></param>
        /// <remarks></remarks>
        private static StepOutput CalcPrincipal(DataFrame frame, out double[,] x, out double[,] xc, out double[,] xr, out double[,] v, int irv, out int n, out int nx, bool correctForReversal)
        {
            int ifault = 0;
            double cum = 0; double dsum = 0;

            n = frame.VariableCount;
            nx = frame.Variables[0].Length;
            x = new double[n + 1, nx + 1];
            bool[] revx = new bool[n + 1];
            int inx = 0;
            for (int j = 1; j <= nx; j++)
            {
                bool iskip = false;
                for (int i = 1; i <= n; i++)
                {
                    if (((DoubleVariable)frame.Variables[i - 1]).Data[j - 1] == Constant.MISSING)
                        iskip = true;
                }
                if (!iskip)
                {
                    inx++;
                    for (int i = 1; i <= n; i++)
                        x[i, inx] = ((DoubleVariable)frame.Variables[i - 1]).Data[j - 1];
                }
            }
            nx = inx;

            // first do the pca to check for scale reversal like Stata alpha command without the asis subcommand
            XPrincipal(n, nx, x, out xc, out xr, out double[,] u, out double[] w, out v, irv, ref ifault);
            bool signrev = false;
            string revlab = string.Empty;
            XPscore1Corr(n, nx, x, v, irv, revx);
            for (int i = 1; i <= n; i++)
            {
                if (!revx[i])
                {
                    signrev = true;
                    break;
                }
            }
            if (signrev)
            {
                if (correctForReversal)
                {
                    for (int i = 1; i <= n; i++)
                    {
                        if (!revx[i])
                        {
                            for (int j = 1; j <= nx; j++)
                                x[i, j] = -x[i, j];
                            revlab += frame.Variables[i - 1].Title + "; ";
                        }
                    }
                    if (revlab.Length > 0)
                    {
                        revlab = revlab.Substring(0, revlab.Length - 2);
                        revlab = "Sign was reversed for: " + revlab;
                    }
                }
            }

            // do the pca with the selected covariance or correlation approach
            XPrincipal(n, nx, x, out xc, out xr, out u, out w, out v, irv, ref ifault);

            ParameterBag outputParameters = new();
            if (ifault == 0)
            {
                for (int j = 1; j <= n; j++)
                    dsum += w[j];
                outputParameters.AddOutput("type", irv == 1 ? "correlation" : "covariance");
                IList<ParameterBag> warnList = null;
                if (revlab.Length > 0)
                {
                    warnList = new List<ParameterBag>();
                    ParameterBag warnParameters = new();
                    warnParameters.AddOutput("warn", revlab);
                    warnList.Add(warnParameters);
                }
                outputParameters.AddOutput("*warn", warnList);
                IList<ParameterBag> tableList = new List<ParameterBag>();
                for (int j = 1; j <= n; j++)
                {
                    ParameterBag tableParameters = new();
                    double prop = w[j] / dsum;
                    cum += prop;
                    tableParameters.AddOutput("comp", j);
                    tableParameters.AddOutput("eigen", w[j]);
                    tableParameters.AddOutput("prop", prop * 100.0);
                    tableParameters.AddOutput("cum", cum * 100.0);
                    tableList.Add(tableParameters);
                }
                outputParameters.AddOutput("*table", tableList);
            }
            MultipleLinearRegressionContext context = new() { X = x, H = xc, R2 = xr, V = v, M = irv, P = n, N = nx };
            outputParameters.AddInput("context", context.StripForOutput());
            return new StepOutput(outputParameters);
        }

        ///  <summary>
        ///  
        ///  </summary>
        ///  <param name="n"></param>
        ///  <param name="nx"></param>
        ///  <param name="x"></param>
        ///  <param name="xc">Set to...</param>
        ///  <param name="xr">Set to...</param>
        ///  <param name="u">Set to...</param>
        ///  <param name="w">Set to...</param>
        ///  <param name="v">Set to...</param>
        ///  <param name="irv"></param>
        ///  <param name="ifault"></param>
        ///  <remarks></remarks>
        private static void XPrincipal(int n, int nx, double[,] x, out double[,] xc, out double[,] xr, out double[,] u, out double[] w, out double[,] v, int irv, ref int ifault)
        {
            xc = new double[n + 1, n + 1];
            xr = new double[n + 1, n + 1];
            u = new double[n + 1, n + 1];
            if (irv == 1)
            {
                for (int j = 1; j <= n; j++)
                {
                    for (int i = 1; i <= n; i++)
                    {
                        Regress1.X_Comat(out xc[j, i], out xr[j, i], x, nx, j, i);
                        u[j, i] = xr[j, i];
                    }
                }
            }
            else
            {
                for (int j = 1; j <= n; j++)
                {
                    for (int i = 1; i <= n; i++)
                    {
                        Regress1.X_Comat(out xc[j, i], out xr[j, i], x, nx, j, i);
                        u[j, i] = xc[j, i];
                    }
                }
            }
            w = new double[n + 1];
            v = new double[n + 1, n + 1];
            for (int i = 1; i <= n; i++)
                w[i] = 1.0;
            Regress1.X_SVDCP(u, n, n, w, v, ref ifault);
            double wmax = w[1];
            for (int j = 1; j <= n; j++)
                if (wmax < w[j])
                    wmax = w[j];
            double tol = wmax * Constant.EPSNEG;
            for (int j = 1; j <= n; j++)
                if (w[j] < tol)
                    w[j] = 0.0;
            Regress1.X_Eigsrt(w, v, n);
        }

        private static void XPscore1Corr(int n, int nx, double[,] x, double[,] v, int irv, bool[] negcorr)
        {
            double[] av = null; double[] sd = null;

            double[] ps = new double[nx + 1];
            double[] xx = new double[nx + 1];
            if (irv == 1)
            {
                av = new double[n + 1];
                sd = new double[n + 1];
                for (int j = 1; j <= n; j++)
                    Regress1.x_avsd(x, nx, j, out av[j], out sd[j]);
            }
            for (int j = 1; j <= nx; j++)
            {
                for (int i = 1; i <= 1; i++)
                {
                    ps[j] = 0.0;
                    for (int k = 1; k <= n; k++)
                    {
                        if (irv == 1)
                        {
                            //  References to av and sd in the following line are OK, because they are only referenced if irv=1 and are always set in this case.
                            Debug.Assert(null != av && null != sd);
                            ps[j] = ps[j] + v[k, i] * ((x[k, j] - av[k]) / sd[k]);
                        }
                        else
                        {
                            ps[j] = ps[j] + v[k, i] * x[k, j];
                        }
                    }
                }
            }
            for (int i = 1; i <= n; i++)
            {
                for (int j = 1; j <= nx; j++)
                    xx[j] = x[i, j];
                negcorr[i] = MathDbl.corr(xx, ps, 1, nx, true) < 0.0;
            }
        }

        public static StepOutput RptMultipleLinearRegression(ParameterBag parameters)
        {
            DataFrame outcomeFrame = parameters["outcome"].AsDataFrame;
            DoubleVariable outcomeVariable = (DoubleVariable)outcomeFrame.Variables[0];
            bool weighted = parameters.ContainsKey("weights") && parameters["weights"] != null;
            DoubleVariable weightsVariable;
            if (weighted)
            {
                DataFrame weightsFrame = parameters["weights"].AsDataFrame;
                weightsVariable = (DoubleVariable)weightsFrame.Variables[0];
            }
            else
            {
                //  Weights aren't in use, use all 1s
                double[] allOnes = new double[outcomeVariable.Length];
                for (int i = 0; i < allOnes.Length; i++)
                    allOnes[i] = 1;
                weightsVariable = new DoubleVariable(allOnes);
            }
            bool calculateIntercept = parameters["calculateIntercept"].AsBoolean;
            DataFrame predictorsFrame = parameters["predictors"].AsDataFrame;

            //  ReDim PASSX(1, 1) - note 1 for calculate intercept, 0 for not
            //  y() is outcome data, cd(0) is its title
            //  wy() is weights, cd(1) is its title
            //  x(,) is predictors, xd() is titles of predictors
            //  Then in SD2 was transferred to ARR2(0) = y, arr2(1)=wy, arr2(2...) = predictors

            //  calc_multi
            MultipleLinearRegressionContext context = new();
            int iq;
            // Arr2(0,n)=y data
            // Arr2(1,n)=weight data
            context.N = outcomeVariable.Length;
            int ip = predictorsFrame.VariableCount;
            context.P = ip;
            context.Y = new double[context.N + 1];
            context.S = new double[context.N + 1];
            context.OutcomeTitle = outcomeVariable.Title;
            context.weightTitle = weighted ? weightsVariable.Title : string.Empty;
            if (calculateIntercept)
            {
                // intercept
                context.DoC = true;
                context.P += 1;
                context.X = new double[context.N + 1, context.P + 1];
                iq = 1;
                for (int j = 1; j <= context.N; j++)
                    context.X[j, 1] = 1;
            }
            else
            {
                // no intercept
                context.DoC = false;
                context.X = new double[context.N + 1, context.P + 1];
                iq = 0;
            }
            context.Titles = new string[predictorsFrame.VariableCount + iq + 1];
            for (int i = 0; i < predictorsFrame.VariableCount; i++)
                context.Titles[i + 1 + iq] = predictorsFrame.Variables[i].Title;
            int cnt = 0;
            for (int j = 0; j < context.N; j++)
            {
                bool ok = outcomeVariable.Data[j] != Constant.MISSING;
                if (weightsVariable.Data[j] == Constant.MISSING)
                    ok = false;
                for (int k = 1; k <= ip; k++)
                    if (((DoubleVariable)predictorsFrame.Variables[k - 1]).Data[j] == Constant.MISSING)
                        ok = false;
                if (ok)
                {
                    cnt += 1;
                    context.Y[cnt] = outcomeVariable.Data[j];
                    context.S[cnt] = weightsVariable.Data[j];
                    for (int k = 1; k <= ip; k++)
                        context.X[cnt, k + iq] = ((DoubleVariable)predictorsFrame.Variables[k - 1]).Data[j];
                }
            }
            string dropWarning = null;
            if (context.N != cnt)
            {
                dropWarning = (context.N - cnt).ToString() + " observations dropped due to missing data. Make sure that observations with missing data are not a subgroup";
                context.N = cnt;
            }
            (context.P, context.M) = x_glin(context, context.P, context.M);
            // context.DoC, not a literal true: a model fitted without an intercept had its first slope labelled "Intercept"
            return new StepOutput(MakeMultipleRegressionOutput(context, context.Se, context.B, context.DoC, context.N, context.P, false, context.M, dropWarning));
        }


        private static (int P, int ifault) x_glin(MultipleLinearRegressionContext context, int P, int ifault)
        {
            int incep; int indep; int irank = 0;
            int nrmiss = 0;
            double rdf = 0; double rss = 0;
            double s;
            context.warn = string.Empty;
            int original_p = P;
            context.Se = new double[P + 1];
            context.B = new double[P * P + 1];
            context.H = new double[P + 1, P + 1];
            context.R = new double[context.N + 1];
            context.FV = new double[context.N + 1];
            if (context.DoC)
            {
                incep = 1;
                indep = P - 1;
            }
            else
            {
                incep = 0;
                indep = P;
            }
            int iwt = 0;
            for (int i = 1; i <= context.N; i++)
                if (context.S[i] != 1.0)
                    iwt = 1;
            double[,] xx = new double[context.N + 1, indep + 1 + iwt + 1];
            double[,] r = new double[P + 1, P + 1];
            double[] D = new double[P + 1];
            double[] xMin = new double[P + 1];
            double[] xMax = new double[P + 1];
            double[] wk = new double[2 * (P + 1) + 1];
            int[] idum = new int[1 + 1];
            for (int i = 1; i <= context.N; i++)
            {
                for (int j = 1 + incep; j <= indep + incep; j++)
                    xx[i, j - incep] = context.X[i, j];
                if (iwt == 1)
                {
                    xx[i, indep + 1] = context.S[i];
                    xx[i, indep + 2] = context.Y[i];
                }
                else
                {
                    xx[i, indep + 1] = context.Y[i];
                }
            }
            int iwtcol = iwt == 0 ? 0 : indep + 1;
            Regress1.glsqr(0, incep, 0, context.N, indep + iwt + 1, xx, -indep, idum, -1, idum, 0, iwtcol, context.B, r, D, ref irank, ref rdf, ref rss, ref nrmiss, xMin, xMax, wk, ref ifault);
            if (irank != P & indep > 1)
            {
                int ctr = incep;
                for (int j = 1 + incep; j <= P; j++)
                {
                    if (r[j, j] == 0)
                    {
                        context.warn += context.Titles[j] + ", ";
                    }
                    else
                    {
                        ctr += 1;
                        for (int i = 1; i <= context.N; i++)
                            context.X[i, ctr] = xx[i, j - incep];

                        //  Swap the titles
                        string temp = context.Titles[ctr];
                        context.Titles[ctr] = context.Titles[j];
                        context.Titles[j] = temp;
                    }
                }
                if (context.warn.Length > 0)
                    context.warn = context.warn.Substring(0, context.warn.Length - 2) + " dropped from the model due to very high correlation with other variable(s) included.";
                P = irank;
                context.Se = new double[P + 1];
                context.B = new double[P * P + 1];
                context.H = new double[P + 1, P + 1];
                context.R = new double[context.N + 1];
                context.FV = new double[context.N + 1];
                if (context.DoC)
                {
                    incep = 1;
                    indep = P - 1;
                }
                else
                {
                    incep = 0;
                    indep = P;
                }
                r = new double[P + 1, P + 1];
                D = new double[P + 1];
                xMin = new double[P + 1];
                xMax = new double[P + 1];
                wk = new double[2 * (P + 1) + 1];
                idum = new int[1 + 1];
                for (int i = 1; i <= context.N; i++)
                {
                    for (int j = 1 + incep; j <= indep + incep; j++)
                        xx[i, j - incep] = context.X[i, j];
                    if (iwt == 1)
                    {
                        xx[i, indep + 1] = context.S[i];
                        xx[i, indep + 2] = context.Y[i];
                    }
                    else
                    {
                        xx[i, indep + 1] = context.Y[i];
                    }
                }
                Regress1.glsqr(0, incep, 0, context.N, indep + iwt + 1, xx, -indep, idum, -1, idum, 0, iwtcol, context.B, r, D, ref irank, ref rdf, ref rss, ref nrmiss, xMin, xMax, wk, ref ifault);
            }
            if (ifault != 0)
            {
                context.warn = "QR solution failed and SVD used, extreme results may be invalid.";
                P = original_p;
                context.VIF = new double[P + 1];
                context.Se = new double[P + 1];
                context.B = new double[P + 1];
                context.H = new double[P + 1, P + 1];
                context.R = new double[context.N + 1];
                double[] sig = new double[context.N + 1];
                for (int i = 1; i <= P; i++)
                    context.VIF[i] = Constant.MISSING;
                for (int i = 1; i <= context.N; i++)
                    sig[i] = Math.Sqrt(1.0 / context.S[i]);
                (context.SSREG, context.SSY, context.FV, ifault) = x_glin_svd(context.Y, sig, context.X, context.Se, context.B, context.H, context.R, context.DoC, context.N, P);
                return (P, ifault);
            }
            double[,] covb = new double[P + 1, P + 1];
            context.VIF = new double[P + 1];
            // variance inflation
            if (incep == 1 && r[1, 1] > 0.0)
                context.VIF[1] = Math.Pow(r[1, 1], 2.0);
            for (int j = incep + 1; j <= P; j++)
                if (r[j, j] > 0.0)
                    for (int i = incep + 1; i <= j; i++)
                        if (r[i, i] > 0.0)
                            context.VIF[j] += Math.Pow(r[i, j], 2.0);
            for (int j = 1; j <= P; j++)
                if (r[j, j] <= 0.0)
                    context.VIF[j] = Constant.MISSING;
            Regress1.rcovarb(P, r, 1.0, covb, ref ifault);
            for (int j = 1; j <= P; j++)
                if (context.VIF[j] != Constant.MISSING)
                    context.VIF[j] *= covb[j, j];
            double rms = rss / rdf;
            Regress1.rcovarb(P, r, rms, covb, ref ifault);
            for (int i = 1; i <= P; i++)
                context.Se[i] = Math.Sqrt(covb[i, i]);
            for (int i = 1; i <= P; i++)
                for (int j = 1; j <= P; j++)
                    context.H[i, j] = covb[i, j] / rms;
            for (int i = 1; i <= context.N; i++)
            {
                s = 0.0;
                for (int j = 1; j <= P; j++)
                    s += context.X[i, j] * context.B[j];
                context.FV[i] = s;
                context.R[i] = context.Y[i] - s;
            }
            context.SSREG = 0.0;
            for (int i = 1; i <= P - incep; i++)
            {
                s = 0.0;
                int j = incep + i;
                if (r[j, j] > 0.0)
                    for (int k = 0; k <= P - j; k++)
                        s += r[j, j + k] * context.B[j + k];
                context.SSREG += s * s;
            }
            context.SSY = context.SSREG + rss;
            return (P, ifault);
        }

        private static ParameterBag MakeMultipleRegressionOutput(MultipleLinearRegressionContext context, double[] seb, double[] bd, bool DoC, int nx, int p, bool pol, int errcode, string dropWarning)
        {
            double rdf = nx - p;
            ParameterBag outputParameters = new();
            IList<ParameterBag> warnList = new List<ParameterBag>();
            outputParameters.AddOutput("*warn", warnList);
            if (context.warn.Length > 0 || errcode != 0)
                warnList.Add(new ParameterBag("warn", new FilledStringParameter(FilledParameterDirection.Output, context.warn)));
            if (null != dropWarning)
                warnList.Add(new ParameterBag("warn", new FilledStringParameter(FilledParameterDirection.Output, dropWarning)));
            outputParameters.AddOutput("isPoly", pol);
            if (errcode == 0)
            {
                IList<ParameterBag> rowList = new List<ParameterBag>();
                outputParameters.AddOutput("*row", rowList);
                ParameterBag rowParameters = new();
                rowList.Add(rowParameters);
                IList<ParameterBag> colList = new List<ParameterBag>();
                rowParameters.AddOutput("*col", colList);
                for (int i = 1; i <= p; i++)
                {
                    ParameterBag colParameters = new();
                    colList.Add(colParameters);
                    double prob = PDF.tvalp(Math.Abs(bd[i] / seb[i]), Convert.ToDouble(nx - p));
                    if (prob > 1.0 - prob)
                        prob = 1.0 - prob;
                    prob = 2.0 * prob;
                    if (DoC)
                    {
                        if (i == 1)
                        {
                            colParameters.AddOutput("label", "Intercept");
                            colParameters.AddOutput("b", "0");
                        }
                        else
                        {
                            colParameters.AddOutput("label", context.Titles[i]);
                            colParameters.AddOutput("b", i - 1);
                        }
                    }
                    else
                    {
                        colParameters.AddOutput("label", context.Titles[i]);
                        colParameters.AddOutput("b", i);
                    }
                    colParameters.AddOutput("val_b", bd[i]);
                    double t;
                    double rp;
                    if (seb[i] != 0.0)
                    {
                        t = bd[i] / seb[i];
                        rp = t / Math.Sqrt(t * t + rdf);
                    }
                    else
                    {
                        t = Constant.MISSING;
                        rp = Constant.MISSING;
                    }
                    if (DoC == false || i > 1)
                        colParameters.AddOutput("*r", new List<ParameterBag> { new ParameterBag("rp", new FilledDoubleParameter(FilledParameterDirection.Output, rp)) });

                    colParameters.AddOutput("t", t);
                    colParameters.AddOutput("p", prob);
                }
                if (!string.IsNullOrEmpty(context.weightTitle))
                    rowParameters.AddOutput("y", context.OutcomeTitle + " (weighted by " + context.weightTitle + ")");
                else
                    rowParameters.AddOutput("y", context.OutcomeTitle);
                IList<ParameterBag> zList = new List<ParameterBag>();
                rowParameters.AddOutput("*z", zList);
                for (int j = 1; j <= p; j++)
                {
                    ParameterBag zParameters = new();
                    if (j > 1 && bd[j] >= 0.0)
                        zParameters.AddOutput("extraSign", "+");
                    zParameters.AddOutput("z", bd[j]);
                    if (j > 1 || !DoC)
                        zParameters.AddOutput("title", " " + context.Titles[j]);
                    zList.Add(zParameters);
                }
            }
            outputParameters.AddInput("context", context.StripForOutput());
            //  For best subset code
            // the predictors are parameters 1 + iq to p: 2 to p after a constant, 1 to p without one (the first was left out)
            int firstPredictor = DoC ? 2 : 1;
            string[] predictorTitles = new string[p - firstPredictor + 1];
            for (int i = firstPredictor; i <= p; i++)
                predictorTitles[i - firstPredictor] = context.Titles[i];
            outputParameters["predictorTitles"] = FilledParameterFactory.Input(new DataFrame(new StringVariable(predictorTitles)));
            outputParameters["candidatePredictors"] = FilledParameterFactory.Input(x_prep_intermr(context));
            return outputParameters;
        }

        private static (double bss, double ctss, double[] yfit, int ifault) x_glin_svd(double[] yd, double[] sig, double[,] xd, double[] SEB, double[] bd, double[,] xtxi, double[] er, bool DoC, int nx, int P)
        {
            double[] yfit = new double[nx + 1];
            double[,] ud = new double[nx + 1, P + 1];
            double[,] vd = new double[P + 1, P + 1];
            double[] wd = new double[P + 1];
            double[] cn = new double[P + 1];
            double[] hi = new double[nx + 1];
            int ifault = Regress1.X_SVGO(xd, yd, sig, nx, P, bd, ud, vd, wd, yfit, er);
            Regress1.X_SVDVRD(xd, vd, wd, nx, P, xtxi, cn, hi);
            double sy = 0.0;
            double sn = 0.0;
            for (int i = 1; i <= nx; i++)
            {
                double wt = 1.0 / (sig[i] * sig[i]);
                sn += wt;
                sy += yd[i] * wt;
            }
            double ym = sy / sn;
            double ctss = 0.0;
            double bss = 0.0;
            if (DoC)
            {
                for (int i = 1; i <= nx; i++)
                {
                    double wt = 1.0 / (sig[i] * sig[i]);
                    ctss += (yd[i] * wt - ym) * (yd[i] * wt - ym);
                    bss += (yfit[i] - ym) * (yfit[i] - ym);
                }
            }
            else
            {
                for (int i = 1; i <= nx; i++)
                {
                    double wt = 1.0 / (sig[i] * sig[i]);
                    ctss += yd[i] * wt * (yd[i] * wt);
                    bss += yfit[i] * yfit[i];
                }
            }
            double rss = ctss - bss;
            double rdf = nx - 1 - (P - 1);
            double rms = rss / rdf;
            for (int i = 1; i <= P; i++)
                SEB[i] = Math.Sqrt(xtxi[i, i] * rms);
            return (bss, ctss, yfit, ifault);
        }

        public static StepOutput RptMultipleLinearRegressionAnova(IFormatting host, ParameterBag parameters)
        {
            MultipleLinearRegressionContext context = GetMultipleLinearRegressionContext(parameters);
            double ci = parameters["ci"].AsDouble;

            double rdf = context.N - context.P;
            double bdf = context.P == 1 || context.DoC == false ? context.P : context.P - 1;
            double bms = context.SSREG / bdf;
            double rss = context.SSY - context.SSREG;
            double rms = rss / rdf;
            double vr = bms / rms;
            int tdf = context.DoC ? context.N - 1 : context.N;
            ParameterBag outputParameters = new();
            outputParameters.AddOutput("reg_sum", context.SSREG);
            outputParameters.AddOutput("reg_df", Math.Floor(bdf));
            outputParameters.AddOutput("reg_mean", bms);
            outputParameters.AddOutput("res_sum", context.SSY - context.SSREG);
            outputParameters.AddOutput("res_df", Math.Floor(rdf));
            outputParameters.AddOutput("res_mean", rms);
            outputParameters.AddOutput("tot_sum", context.SSY);
            outputParameters.AddOutput("tot_df", tdf);
            outputParameters.AddOutput("mse", Math.Sqrt(rms));
            outputParameters.AddOutput("f", vr);
            double prob = PDF.fvalp(vr, bdf, rdf);
            outputParameters.AddOutput("p", prob);
            double r2 = context.SSREG / context.SSY;
            double r = Math.Sqrt(r2);
            if (Math.Floor(bdf) == 1 && context.N > 3)
            {
                if (!context.DoC)
                {
                    if (context.B[1] < 0)
                        r = -r;
                }
                else
                {
                    if (context.B[2] < 0)
                        r = -r;
                }
                double p0 = 1 - ci;
                double gamma = 1.0 - p0 / 2.0;
                double rcit = PDF.gauinv(gamma);
                double fz = 0.5 * Math.Log((1.0 + r) / (1.0 - r));
                double fz1 = fz - rcit / Math.Sqrt(Convert.ToDouble(context.N - 3));
                double fz2 = fz + rcit / Math.Sqrt(Convert.ToDouble(context.N - 3));
                double con1 = (Math.Exp(2.0 * fz1) - 1.0) / (Math.Exp(2.0 * fz1) + 1.0);
                double con2 = (Math.Exp(2.0 * fz2) - 1.0) / (Math.Exp(2.0 * fz2) + 1.0);
                outputParameters.AddOutput("r_extra", "  [" + Formatting.XRound(100 * (1.0 - p0), 1) + "%CI = " + host.RoundU(con1) + " to " + host.RoundU(con2) + "]");
            }
            outputParameters.AddOutput("r", r);
            outputParameters.AddOutput("r2", r2 * 100);
            // adjusted R squared can be negative, when the model explains less than its number of parameters would by chance; it is
            // reported as it is, where earlier versions showed zero. The total sum of squares has N - 1
            // degrees of freedom with an intercept and N without one (tdf), where it is not corrected for the mean.
            r2 = 1.0 - rss / Convert.ToDouble(context.N - context.P) / (context.SSY / Convert.ToDouble(tdf));
            outputParameters.AddOutput("ra2", r2 * 100);
            Regress1.x_dwsd(context.R, context.N, out double dw);
            outputParameters.AddOutput("dw", dw);
            return new StepOutput(outputParameters);
        }

        public static StepOutput RptMultipleLinearRegressionPrediction(ParameterBag parameters)
        {
            MultipleLinearRegressionContext context = GetMultipleLinearRegressionContext(parameters);
            double gamma = parameters["ci"].AsDouble;
            DataFrame candidatePredictors = parameters["candidatePredictors"].AsDataFrame;

            int iq;

            double[] newx = new double[context.P + 1];
            bool lsqmean = true;
            if (context.DoC)
            {
                iq = 1;
                newx[1] = 1.0;
            }
            else
            {
                iq = 0;
            }
            StringVariable valueVariable = (StringVariable)candidatePredictors.Variables[1];
            DoubleVariable oldValueVariable = (DoubleVariable)candidatePredictors.Variables[2];
            // A blank or non-numeric predictor arrives as MISSING (a huge negative number). Multiplied by a slope it is no longer
            // recognisable as missing, and the prediction was printed as a number like -9E+307 with infinite limits; the
            // prediction and its intervals are now missing too, as in the logistic prediction.
            bool missingPredictor = false;
            for (int i = 1 + iq; i <= context.P; i++)
            {
                newx[i] = Parsing.Cdbl_Txt(valueVariable.Data[i - 1 - iq]);
                if (newx[i] == Constant.MISSING || double.IsNaN(newx[i]) || double.IsInfinity(newx[i]))
                    missingPredictor = true;
                if (newx[i] != oldValueVariable.Data[i - 1 - iq])
                    lsqmean = false;
            }
            double newy = 0.0;
            for (int i = 1; i <= context.P; i++)
                newy += newx[i] * context.B[i];

            MathDbl.civ(context.N - context.P, out double cit, gamma, out double p0);
            ParameterBag outputParameters = new();
            IList<ParameterBag> xList = new List<ParameterBag>();
            outputParameters.AddOutput("*x", xList);
            for (int i = 1 + iq; i <= context.P; i++)
            {
                ParameterBag xParameters = new();
                xList.Add(xParameters);
                // parameter i has title i, with or without a constant (Titles[i - iq + 1] ran off the end without one)
                xParameters.AddOutput("xtitle", context.Titles[i]);
                xParameters.AddOutput("x", newx[i]);
            }
            string msg = lsqmean ? "  (least squares mean)" : string.Empty;
            outputParameters.AddOutput("ytitle", context.OutcomeTitle);
            outputParameters.AddOutput("y", missingPredictor ? Constant.MISSING : newy);
            outputParameters.AddOutput("msg", msg);
            double rdf = Convert.ToDouble(context.N - 1 - (context.P - 1));
            double rss = context.SSY - context.SSREG;
            double rms = rss / rdf;
            Regress1.x_ciyp(newx, context.H, context.P, rms, cit, out double cl, out double pl);
            outputParameters.AddOutput("ci_pc", 100 * (1.0 - p0));
            outputParameters.AddOutput("ci_from", missingPredictor ? Constant.MISSING : newy - cl);
            outputParameters.AddOutput("ci_to", missingPredictor ? Constant.MISSING : newy + cl);
            outputParameters.AddOutput("pred_pc", 100 * (1.0 - p0));
            outputParameters.AddOutput("pred_from", missingPredictor ? Constant.MISSING : newy - pl);
            outputParameters.AddOutput("pred_to", missingPredictor ? Constant.MISSING : newy + pl);
            return new StepOutput(outputParameters);
        }

        public static StepOutput PlotMultipleLinearRegressionResiduals(ParameterBag parameters)
        {
            MultipleLinearRegressionContext context = GetMultipleLinearRegressionContext(parameters);
            double[] r;

            ParameterBag outputParameters = new();
            IList<ParameterBag> chartList = new List<ParameterBag>();
            outputParameters.AddOutput("*chart", chartList);

            context.R[0] = Constant.MISSING;
            chartList.Add(new ParameterBag("chart", FilledParameterFactory.Output(ChartRendererFactory.PrepForLater(ChartType.Xy, new XyOptions(context.FV, context.R, "Fitted Y (y fit)", "Residual (Y - y fit)", "Residuals vs. Fitted Y [linear regression]", true, DataMinMax.XCalc_YCalc)))));

            for (int i = 1; i <= context.P; i++)
            {
                if (i > 1 || !context.DoC)
                {
                    int k = context.DoC ? i - 1 : i;
                    r = new double[context.N + 1];
                    r[0] = Constant.MISSING;
                    for (int j = 1; j <= context.N; j++)
                        r[j] = context.X[j, i];
                    chartList.Add(new ParameterBag("chart", FilledParameterFactory.Output(ChartRendererFactory.PrepForLater(ChartType.Xy, new XyOptions(r, context.R, "Predictor: " + context.Titles[i], "Residual (Y - y fit)", "Residuals vs. Predictor " + k.ToString() + " [linear regression]", true, DataMinMax.XCalc_YCalc)))));
                }
            }
            r = new double[context.N + 1];
            ExFortran.Rank(context.R, r, 1, context.N, 0, out double _);
            for (int j = 1; j <= context.N; j++)
            {
                // van der Waerden normal scores, Conover P 396
                r[j] = PDF.gauinv(r[j] / (Convert.ToDouble(context.N) + 1.0), out int ifault);
                if (ifault != 0)
                    r[j] = Constant.MISSING;
            }
            chartList.Add(new ParameterBag("chart", FilledParameterFactory.Output(ChartRendererFactory.PrepForLater(ChartType.Xy, new XyOptions(context.R, r, "Residual (Y - y fit)", "van der Waerden normal score", "Normal Plot for Residuals (linear regression)", true, DataMinMax.XCalc_YCalc)))));
            return new StepOutput(outputParameters);
        }

        public static StepOutput RptMultipleLinearRegressionParameterDetail(ParameterBag parameters)
        {
            MultipleLinearRegressionContext context = GetMultipleLinearRegressionContext(parameters);

            double gamma = parameters["ci"].AsDouble;
            int df = context.N - context.P;
            MathDbl.civ(df, out double cit, gamma, out double p0);
            ParameterBag outputParameters = new();
            outputParameters.AddOutput("pc", 100 * (1.0 - p0));
            IList<ParameterBag> vList = new List<ParameterBag>();
            outputParameters.AddOutput("*v", vList);
            for (int i = 1; i <= context.P; i++)
            {
                // parameter i has title i, with or without a constant (Titles[i - iq + 1] ran off the end without one)
                string q = i == 1 && context.DoC ? "constant" : context.Titles[i];
                ParameterBag vParameters = new();
                vList.Add(vParameters);
                vParameters.AddOutput("label", q);
                vParameters.AddOutput("coef", context.B[i]);
                vParameters.AddOutput("err", context.Se[i]);
                vParameters.AddOutput("from", context.B[i] - cit * context.Se[i]);
                vParameters.AddOutput("to", context.B[i] + cit * context.Se[i]);
            }
            bool usedSvd = true;
            for (int i = 1; i <= context.P; i++)
            {
                if (context.VIF[i] != Constant.MISSING)
                {
                    usedSvd = false;
                    break;
                }
            }
            if (!usedSvd)
            {
                double[] vif2 = new double[context.P + 1];
                string[] ti = new string[context.P + 1];
                double sumv = 0.0;
                for (int i = 1; i <= context.P; i++)
                {
                    if (i == 1 && context.DoC)
                    {
                        ti[i] = "_*_";
                    }
                    else
                    {
                        ti[i] = context.Titles[i];
                        sumv += context.VIF[i];
                    }
                    vif2[i] = context.VIF[i];
                }
                int iv = context.DoC ? context.P - 1 : context.P;
                double meanv = sumv / iv;
                // TODO: bubble sort - use something else!
                bool bsorted = false;
                while (!bsorted)
                {
                    bsorted = true;
                    for (int i = context.P - 1; i >= 1; i--)
                    {
                        if (vif2[i + 1] > vif2[i])
                        {
                            bsorted = false;
                            double temp = vif2[i];
                            string tempx = ti[i];
                            vif2[i] = vif2[i + 1];
                            ti[i] = ti[i + 1];
                            vif2[i + 1] = temp;
                            ti[i + 1] = tempx;
                        }
                    }
                }
                // print for independent variables
                IList<ParameterBag> vifList = new List<ParameterBag>();
                outputParameters.AddOutput("*vif", vifList);
                for (int i = 1; i <= context.P; i++)
                {
                    if (ti[i] != "_*_")
                    {
                        ParameterBag vifParameters = new();
                        vifList.Add(vifParameters);
                        vifParameters.AddOutput("label", ti[i]);
                        vifParameters.AddOutput("vif", vif2[i]);
                        vifParameters.AddOutput("x", vif2[i] > 20.0 ? Formatting.ASTERISK : string.Empty);
                        vifParameters.AddOutput("rvif", 1.0 / vif2[i]);
                    }
                }
                outputParameters.AddOutput("meanv", meanv);
            }
            else
            {
                // not calc if SVD used cos no r matrix
                outputParameters.AddOutput("meanv", "not calculated");
            }
            return new StepOutput(outputParameters);
        }

        /// <summary>
        /// Renders a 2D array ary[dim1, dim2] into a FilledParameter of list of bags of lists of bags as required by the report renderer.  In the output, dim1 varies faster (inner dimension) and dim2 more slowly (outer dimension).
        /// </summary>
        /// <typeparam name="ArrayType">The type of the array to be rendered</typeparam>
        /// <typeparam name="RenderedType">The type returned by the renderer - allows use of many different renderers</typeparam>
        /// <param name="ary"></param>
        /// <param name="outerLowerBound"></param>
        /// <param name="outerLength"></param>
        /// <param name="innerLowerBound"></param>
        /// <param name="innerLength"></param>
        /// <param name="innerName"></param>
        /// <param name="valueName"></param>
        /// <param name="renderer"></param>
        /// <returns></returns>
        public static List<ParameterBag> ToOutputParameter<ArrayType, RenderedType>(ArrayType[,] ary, int outerLowerBound, int outerLength, int innerLowerBound, int innerLength, string innerName, string valueName, Func<ArrayType, RenderedType> renderer)
        {
            List<ParameterBag> outerList = new();
            for (int i = outerLowerBound; i < outerLowerBound + outerLength; i++)
            {
                ParameterBag outerParameters = new();
                outerList.Add(outerParameters);
                List<ParameterBag> innerList = new();
                outerParameters.AddOutput(innerName, innerList);
                for (int j = innerLowerBound; j < innerLowerBound + innerLength; j++)
                {
                    ParameterBag innerParameters = new();
                    innerList.Add(innerParameters);
                    innerParameters.AddOutput(valueName, renderer(ary[j, i]));
                }
            }
            return outerList;
        }

        public static StepOutput RptXxi(ParameterBag parameters)
        {
            MultipleLinearRegressionContext context = GetMultipleLinearRegressionContext(parameters);

            double rdf = Convert.ToDouble(context.N - context.P);
            double rss = context.SSY - context.SSREG;
            double rms = rss / rdf;

            DataFrame frame = new();
            IList<IVariable> pendedVariables = new List<IVariable>();
            for (int i = 1; i <= context.P; i++)
            {
                DoubleVariable vxxi = new();
                frame.Variables.Add(vxxi);
                DoubleVariable vcv = new();
                pendedVariables.Add(vcv);
                vxxi.Title = "XXi " + i.ToString();
                vxxi.EnsureLength(context.P);
                vcv.Title = "Var-CoVar " + i.ToString();
                vcv.EnsureLength(context.P);
                for (int j = 1; j <= context.P; j++)
                {
                    vxxi.SetData(j - 1, context.H[i, j]);
                    vcv.SetData(j - 1, context.H[i, j] * rms);
                }
            }
            //  Spacer
            frame.Variables.Add(new DoubleVariable());
            //  Add all the cv variables
            foreach (IVariable v in pendedVariables)
                frame.Variables.Add(v);

            ParameterBag outputParameters = new();
            outputParameters.AddOutput("data", frame);

            outputParameters.AddOutput("*xxi", ToOutputParameter(context.H, 1, context.P, 1, context.P, "*col", "x", v => v));
            outputParameters.AddOutput("*covar", ToOutputParameter(context.H, 1, context.P, 1, context.P, "*col", "x", v => rms * v));

            return new StepOutput(outputParameters);
        }

        public static StepOutput RptMultipleLinearRegressionResiduals(ParameterBag parameters)
        {
            MultipleLinearRegressionContext context = GetMultipleLinearRegressionContext(parameters);
            double ci = parameters["ci"].AsDouble;
            bool shouldSaveFittedY = parameters["saveFittedY"].AsBoolean;
            bool shouldSaveStudentisedResidual = parameters["saveStudentised"].AsBoolean;
            bool shouldSaveJackknifeResidual = parameters["saveJackknife"].AsBoolean;

            // Check if we need to save the data
            double alpha = 1.0 - ci;
            double hicrit = Math.Min(3.0 * (double)context.P / context.N, 0.99);
            double srcrit = PDF.tfromp(alpha / 2.0, context.N - context.P);
            double jackcrit = PDF.tfromp(alpha / 2.0, context.N - context.P - 1);
            double cdcrit = PDF.ffromp(context.N - context.P, context.P, alpha);
            double dfcrit = 2.0 * Math.Sqrt(context.P / (double)context.N);
            double[] hi = new double[context.N + 1];
            double[] sey = new double[context.N + 1];
            double[] rstd = new double[context.N + 1];
            double[] rstudent = new double[context.N + 1];
            double[] cd = new double[context.N + 1];
            double[] dff = new double[context.N + 1];
            double rdf = Convert.ToDouble(context.N - context.P);
            //  root mean square is estimate of population variance
            double rms = (context.SSY - context.SSREG) / rdf;
            // double Con = ( rdf - 1.0 ) / rdf; - unused
            for (int i = 1; i <= context.N; i++)
            {
                double wt = context.S[i];
                double xcx = 0.0;
                int j;
                for (j = 1; j <= context.P; j++)
                {
                    double s = 0.0;
                    for (int k = 1; k <= context.P; k++)
                        s += context.H[j, k] * context.X[i, k];
                    xcx += s * context.X[i, j];
                }
                sey[i] = Math.Sqrt(rms * xcx);
                hi[i] = wt * xcx;
                if (wt == 0.0 || hi[i] == 0.0)
                {
                    rstudent[i] = Constant.MISSING;
                    rstd[i] = Constant.MISSING;
                    cd[i] = Constant.MISSING;
                    dff[i] = Constant.MISSING;
                }
                else
                {
                    double varer = (1.0 - hi[i]) / wt;
                    double SI = Math.Sqrt((wt * (context.N - context.P) * rms - Math.Pow(wt * context.R[i], 2.0) / (1.0 - hi[i])) / (rdf - 1.0));
                    //  jackknife (SAS calls it rstudent) - see Kleinbaum
                    rstudent[i] = wt * context.R[i] / (SI * Math.Sqrt(1.0 - hi[i]));
                    //  studentised residual, standardised residual is er(i)/sqr(rms)
                    rstd[i] = context.R[i] / Math.Sqrt(rms * varer);
                    cd[i] = rstd[i] * rstd[i] * (hi[i] / (1.0 - hi[i])) / context.P;
                    dff[i] = Math.Sqrt(hi[i] / (1.0 - hi[i])) * rstudent[i];
                }
            }
            ParameterBag outputParameters = new();
            IList<ParameterBag> yfitList = new List<ParameterBag>();
            outputParameters.AddOutput("*yfit", yfitList);
            for (int i = 1; i <= context.N; i++)
            {
                ParameterBag yfitParameters = new();
                yfitList.Add(yfitParameters);
                yfitParameters.AddOutput("index", i);
                yfitParameters.AddOutput("y", context.Y[i]);
                yfitParameters.AddOutput("fit_y", context.FV[i]);
                yfitParameters.AddOutput("std_err", sey[i]);
                yfitParameters.AddOutput("res", context.R[i]);
            }
            if (shouldSaveFittedY)
            {
                DataFrame yfitFrame = new();
                DoubleVariable vYFit = new(context.N, "Y Fit");
                yfitFrame.Variables.Add(vYFit);
                DoubleVariable vSdYFit = new(context.N, "SD Y Fit");
                yfitFrame.Variables.Add(vSdYFit);
                DoubleVariable vResidual = new(context.N, "Residual");
                yfitFrame.Variables.Add(vResidual);
                for (int i = 1; i <= context.N; i++)
                {
                    vYFit.SetData(i - 1, context.FV[i]);
                    vSdYFit.SetData(i - 1, sey[i]);
                    vResidual.SetData(i - 1, context.R[i]);
                }
                outputParameters.AddOutput("yfit", yfitFrame);
            }
            IList<ParameterBag> studentisedList = new List<ParameterBag>();
            outputParameters.AddOutput("*studentised", studentisedList);
            for (int i = 1; i <= context.N; i++)
            {
                ParameterBag studentisedParameters = new();
                studentisedList.Add(studentisedParameters);
                studentisedParameters.AddOutput("index", i);
                studentisedParameters.AddOutput("index_star", Math.Abs(rstd[i]) > srcrit ? Formatting.ASTERISK : string.Empty);
                studentisedParameters.AddOutput("stu", rstd[i]);
                studentisedParameters.AddOutput("stu_star", Math.Abs(hi[i]) > hicrit ? Formatting.ASTERISK : string.Empty);
                studentisedParameters.AddOutput("hi", hi[i]);
                studentisedParameters.AddOutput("hi_star", Math.Abs(cd[i]) > cdcrit ? Formatting.ASTERISK : string.Empty);
                studentisedParameters.AddOutput("cook", cd[i]);
            }
            if (shouldSaveStudentisedResidual)
            {
                DataFrame studentisedFrame = new();
                DoubleVariable vResidual = new(context.N, "Studentised Residual");
                studentisedFrame.Variables.Add(vResidual);
                DoubleVariable vLeverage = new(context.N, "Leverage");
                studentisedFrame.Variables.Add(vLeverage);
                DoubleVariable vCook = new(context.N, "Cook's Distance");
                studentisedFrame.Variables.Add(vCook);
                for (int i = 1; i <= context.N; i++)
                {
                    vResidual.SetData(i - 1, rstd[i]);
                    vLeverage.SetData(i - 1, hi[i]);
                    vCook.SetData(i - 1, cd[i]);
                }
                outputParameters.AddOutput("studentised", studentisedFrame);
            }
            IList<ParameterBag> jackknifeList = new List<ParameterBag>();
            outputParameters.AddOutput("*jackknife", jackknifeList);
            for (int i = 1; i <= context.N; i++)
            {
                ParameterBag jackknifeParameters = new();
                jackknifeList.Add(jackknifeParameters);
                jackknifeParameters.AddOutput("index", i);
                jackknifeParameters.AddOutput("index_star", Math.Abs(rstudent[i]) > jackcrit ? Formatting.ASTERISK : string.Empty);
                jackknifeParameters.AddOutput("jack", rstudent[i]);
                jackknifeParameters.AddOutput("jack_star", Math.Abs(dff[i]) > dfcrit ? Formatting.ASTERISK : string.Empty);
                jackknifeParameters.AddOutput("dfit", dff[i]);
            }
            if (shouldSaveJackknifeResidual)
            {
                DataFrame jackknifeFrame = new();
                DoubleVariable vResidual = new(context.N, "Jackknife Residual");
                jackknifeFrame.Variables.Add(vResidual);
                DoubleVariable vDFIT = new(context.N, "DFIT");
                jackknifeFrame.Variables.Add(vDFIT);
                for (int i = 1; i <= context.N; i++)
                {
                    vResidual.SetData(i - 1, rstudent[i]);
                    vDFIT.SetData(i - 1, dff[i]);
                }
                outputParameters.AddOutput("jackknife", jackknifeFrame);
            }
            outputParameters.AddOutput("zhi", hicrit);
            outputParameters.AddOutput("zcook", cdcrit);
            outputParameters.AddOutput("zstu", srcrit);
            outputParameters.AddOutput("zjack", jackcrit);
            outputParameters.AddOutput("zdfit", dfcrit);
            return new StepOutput(outputParameters);
        }


        public static StepOutput RptMultipleLinearRegressionBestSubset(ParameterBag parameters)
        {
            MultipleLinearRegressionContext context = GetMultipleLinearRegressionContext(parameters);
            bool[] selectedPredictors = (bool[])parameters["selectedPredictors"].AsObject;
            bool shouldUseMaximumF = "maximumF".Equals(parameters["selector"].AsString);
            int errcode = 0;

            int forced = 0; int kept = 0; int[] keep = null;
            double maxf = 0; double maxr2 = 0;

            double rmsorig = (context.SSY - context.SSREG) / Convert.ToDouble(context.N - 1 - (context.P - 1));
            double mincp = (context.SSY - context.SSREG) / rmsorig - Convert.ToDouble(context.N - 2 * (context.P + 1));
            int iq = 0;
            if (context.DoC)
                iq = 1;
            int[] force = new int[context.P + 1];
            for (int c = 0; c < selectedPredictors.Length; c++)
            {
                if (selectedPredictors[c])
                {
                    forced += 1;
                    force[forced] = c + 1 + iq;
                }
            }
            if (context.DoC)
            {
                forced += 1;
                // create temp variable for copying values 
                int[] transTemp12 = new int[forced + 1];
                Array.Copy(force, transTemp12, Math.Min(force.Length, transTemp12.Length));
                force = transTemp12;
                force[forced] = 1;
            }
            for (int j = 1; j <= context.P; j++)
            {
                int[] preds = new int[j + 1];
                for (int i = 1; i <= j; i++)
                    preds[i] = i;
                int at = j;
                do
                {
                    bool oktry = x_forceinc(forced, force, j, preds);
                    if (context.DoC)
                    {
                        if (j == 1)
                        {
                            oktry = false;
                        }
                        else
                        {
                            for (int k = 1; k <= j; k++)
                            {
                                if (preds[k] == 1 & k != 1)
                                {
                                    int temp = preds[k];
                                    preds[k] = preds[1];
                                    preds[1] = temp;
                                }
                            }
                        }
                    }
                    if (oktry)
                    {
                        double[,] tryx = new double[context.N + 1, j + 1];
                        for (int i = 1; i <= context.N; i++)
                            for (int k = 1; k <= j; k++)
                                tryx[i, k] = context.X[i, preds[k]];
                        double[,] cached = context.X;
                        context.X = tryx;
                        (j, errcode) = x_glin(context, j, errcode);
                        context.X = cached;
                        if (errcode == 0)
                        {
                            double rdf = context.N - 1 - (j - 1);
                            double bdf = j > 1 ? j - 1 : j;
                            double bms = context.SSREG / bdf;
                            double rms = (context.SSY - context.SSREG) / rdf;
                            double f = bms / rms;
                            double r2 = context.SSREG / context.SSY;
                            double cp = (context.SSY - context.SSREG) / rmsorig - (context.N - 2 * (j + 1));
                            bool isBetter = shouldUseMaximumF ? f > maxf : cp <= mincp;
                            if (isBetter)
                            {
                                maxf = f;
                                mincp = cp;
                                maxr2 = r2;
                                kept = j;
                                keep = new int[kept + 1];
                                for (int k = 1; k <= j; k++)
                                    keep[k] = preds[k];
                            }
                        }
                        else
                        {
                            throw new TemplateOperationCancelledException();
                        }
                    }
                    for (int l = j; l >= 0; l--)
                    {
                        if (preds[l] < context.P - (j - l))
                        {
                            at = l;
                            break;
                        }
                    }
                    if (at == 0 || j == context.P)
                        break;
                    preds[at] = preds[at] + 1;
                    if (at != j)
                    {
                        for (int Q = at + 1; Q <= j; Q++)
                            preds[Q] = preds[at] + (Q - at);
                        at = j;
                    }
                }
                while (true);
            }

            ParameterBag outputParameters = new();
            IList<ParameterBag> selectedList = new List<ParameterBag>();
            outputParameters.AddOutput("*selected", selectedList);
            for (int j = 1 + iq; j <= kept; j++)
            {
                ParameterBag selectedParameters = new();
                selectedList.Add(selectedParameters);
                selectedParameters.AddOutput("label", context.Titles[keep[j]]);
            }
            outputParameters.AddOutput("f", maxf);
            outputParameters.AddOutput("r2", maxr2);
            outputParameters.AddOutput("cp", mincp);

            //  Hack the data in the analysis to drop some of the predictors
            context.P = kept;
            double[,] newX = new double[context.N + 1, context.P + 1];
            for (int j = 1; j <= context.N; j++)
                for (int k = 1; k <= context.P; k++)
                    newX[j, k] = context.X[j, keep[k]];
            context.X = newX;
            for (int j = 1 + iq; j <= kept; j++)
            {
                int ix1 = j;
                int ix2 = keep[j];
                string temp = context.Titles[ix1];
                context.Titles[ix1] = context.Titles[ix2];
                context.Titles[ix2] = temp;
            }
            // create temp variable for copying values 
            string[] transTemp13 = new string[context.P + 1];
            Array.Copy(context.Titles, transTemp13, Math.Min(context.Titles.Length, transTemp13.Length));
            context.Titles = transTemp13;
            (context.P, errcode) = x_glin(context, context.P, errcode);

            ParameterBag otherParameters = MakeMultipleRegressionOutput(context, context.Se, context.B, context.DoC, context.N, context.P, false, errcode, null);
            foreach (KeyValuePair<string, FilledParameter> pair in otherParameters.Pairs)
                outputParameters[pair.Key] = pair.Value;
            outputParameters.AddOutput("subsetApplied", true);
            return new StepOutput(outputParameters);
        }

        private static bool x_forceinc(int forced, int[] force, int j, int[] preds)
        {
            if (forced > 0)
            {
                int cnt = 0;
                for (int i = 1; i <= forced; i++)
                    for (int k = 1; k <= j; k++)
                        if (force[i] == preds[k])
                            cnt++;
                return cnt == forced;
            }
            return true;
        }


        private static DataFrame x_prep_intermr(MultipleLinearRegressionContext context)
        {
            int iq = context.DoC ? 1 : 0;

            DataFrame frame = new();
            StringVariable keyVariable = new() { Title = "Name" };
            frame.Variables.Add(keyVariable);
            StringVariable valueVariable = new() { Title = "Value" };
            frame.Variables.Add(valueVariable);
            DoubleVariable oldValueVariable = new() { Title = "Old value" };
            frame.Variables.Add(oldValueVariable);

            for (int j = 1 + iq; j <= context.P; j++)
            {
                double mu = 0.0;
                double a = context.X[1, j];
                double b = Constant.MISSING;
                bool bin = true;
                int i;
                for (i = 1; i <= context.N; i++)
                {
                    double z = context.X[i, j];
                    if (z != Constant.MISSING)
                    {
                        mu += z;
                        if (z != a)
                        {
                            if (z != b)
                            {
                                if (b == Constant.MISSING)
                                    b = z;
                                else
                                    bin = false;
                            }
                        }
                    }
                }
                if (bin)
                    mu = 0.5;
                else
                    mu /= context.N;
                keyVariable.SetData(j - 1 - iq, context.Titles[j]);
                valueVariable.SetData(j - 1 - iq, mu.ToString(CultureInfo.InvariantCulture));
                oldValueVariable.SetData(j - 1 - iq, Parsing.Cdbl_Txt(mu.ToString(CultureInfo.InvariantCulture)));
            }
            return frame;
        }

        public static StepOutput RptPrincipalComponentsRegressionCoefficients(ParameterBag parameters)
        {
            MultipleLinearRegressionContext context = GetMultipleLinearRegressionContext(parameters);
            DataFrame frame = parameters["data"].AsDataFrame;
            ParameterBag outputParameters = new();
            IList<ParameterBag> pcList = new List<ParameterBag>();
            outputParameters.AddOutput("*pc", pcList);
            for (int j = 1; j <= context.P; j++)
            {
                ParameterBag pcParameters = new();
                pcList.Add(pcParameters);
                pcParameters.AddOutput("pc", j);
            }
            IList<ParameterBag> varList = new List<ParameterBag>();
            outputParameters.AddOutput("*var", varList);
            for (int j = 1; j <= context.P; j++)
            {
                ParameterBag varParameters = new();
                varList.Add(varParameters);
                varParameters.AddOutput("lab", frame.Variables[j - 1].Title);
                IList<ParameterBag> resList = new List<ParameterBag>();
                varParameters.AddOutput("*res", resList);
                for (int i = 1; i <= context.P; i++)
                {
                    ParameterBag resParameters = new();
                    resList.Add(resParameters);
                    resParameters.AddOutput("res", context.V[j, i]);
                }
            }
            return new StepOutput(outputParameters);
        }

        public static StepOutput RptCronbach(ParameterBag parameters)
        {
            MultipleLinearRegressionContext context = GetMultipleLinearRegressionContext(parameters);
            DataFrame frame = parameters["data"].AsDataFrame;
            int k = context.P;
            int N = context.N;
            double[,] x = context.X;
            double[,] r = context.R2;
            double totvar = 0; double alpha; double cl;
            double cco = parameters["ci"].AsDouble;
            if (cco <= 0.0 || cco >= 1.0)
                cco = 0.95;

            double[] qv = new double[k + 1];
            for (int i = 1; i <= N; i++)
            {
                x[0, i] = 0.0;
                for (int j = 1; j <= k; j++)
                    x[0, i] = x[0, i] + x[j, i];
            }
            for (int j = 0; j <= k; j++)
            {
                Regress1.x_avsd(x, N, j, out double _, out qv[j]);
                qv[j] = qv[j] * qv[j];
                if (j > 0)
                    totvar += qv[j];
            }
            double talpha = Convert.ToDouble(k) / Convert.ToDouble(k - 1) * (1.0 - totvar / qv[0]);
            // Stata technical bulletin 56: SG 144
            double f = PDF.ffromp(Convert.ToDouble(k - 1) * Convert.ToDouble(N - 1), Convert.ToDouble(N - 1), 1.0 - cco);
            if (f == Constant.MISSING)
            {
                cl = Constant.MISSING;
            }
            else
            {
                cl = 1.0 - (1.0 - talpha) * f;
                if (cl < 0.0 || cl > talpha)
                    cl = 0.0;
            }
            ParameterBag outputParameters = new();
            outputParameters.AddOutput("raw_t", talpha);
            outputParameters.AddOutput("pc", cco * 100.0);
            outputParameters.AddOutput("raw_cl", cl);
            IList<ParameterBag> rawList = new List<ParameterBag>();
            outputParameters.AddOutput("*raw", rawList);
            for (int l = 1; l <= k; l++)
            {
                totvar = 0.0;
                for (int i = 1; i <= N; i++)
                {
                    x[0, i] = 0.0;
                    for (int j = 1; j <= k; j++)
                        if (j != l)
                            x[0, i] = x[0, i] + x[j, i];
                }
                for (int j = 0; j <= k; j++)
                {
                    if (j != l)
                    {
                        qv[j] = 0.0;
                        Regress1.x_avsd(x, N, j, out double _, out qv[j]);
                        qv[j] = qv[j] * qv[j];
                        if (j > 0)
                            totvar += qv[j];
                    }
                }
                alpha = k > 2
                    ? (k - 1) / (double)(k - 2) * (1.0 - totvar / qv[0])
                    : Constant.MISSING;
                ParameterBag rawParameters = new();
                rawList.Add(rawParameters);
                rawParameters.AddOutput("lab", frame.Variables[l - 1].Title);
                rawParameters.AddOutput("a", alpha);
                if (alpha != Constant.MISSING && alpha - talpha > 0.1)
                    rawParameters.AddOutput("x", Formatting.ASTERISK);
                rawParameters.AddOutput("a-t", alpha - talpha);
            }
            // FOR STANDARDIZED DATA (see SAS & SPSS)
            double rtot = 0.0;
            int ctr = 0;
            for (int i = 2; i <= k; i++)
            {
                for (int j = 1; j < i; j++)
                {
                    rtot += r[j, i];
                    ctr += 1;
                }
            }
            double rbar = rtot / ctr;
            talpha = Convert.ToDouble(k) * rbar / (1.0 + (k - 1) * rbar);
            // Stata technical bulletin 56: SG 144
            f = PDF.ffromp((k - 1) * (N - 1), N - 1, 1.0 - cco);
            if (f == Constant.MISSING)
            {
                cl = Constant.MISSING;
            }
            else
            {
                cl = 1.0 - (1.0 - talpha) * f;
                if (cl < 0.0 || cl > talpha)
                    cl = 0.0;
            }
            outputParameters.AddOutput("standard_t", talpha);
            outputParameters.AddOutput("standard_cl", cl);
            IList<ParameterBag> standardList = new List<ParameterBag>();
            outputParameters.AddOutput("*standard", standardList);
            for (int L = 1; L <= k; L++)
            {
                rtot = 0.0;
                ctr = 0;
                for (int i = 2; i <= k; i++)
                {
                    for (int j = 1; j < i; j++)
                    {
                        if (j != L & i != L)
                        {
                            rtot += r[j, i];
                            ctr += 1;
                        }
                    }
                }
                rbar = rtot / ctr;
                alpha = k < 2
                    ? Constant.MISSING
                    : (k - 1) * rbar / (1.0 + (k - 2) * rbar);
                ParameterBag standardParameters = new();
                standardList.Add(standardParameters);
                standardParameters.AddOutput("lab", frame.Variables[L - 1].Title);
                standardParameters.AddOutput("a", alpha);
                if (alpha != Constant.MISSING && alpha - talpha > 0.1)
                    standardParameters.AddOutput("x", Formatting.ASTERISK);
                standardParameters.AddOutput("a-t", alpha - talpha);
            }
            return new StepOutput(outputParameters);
        }

        public static StepOutput RptPrincipalComponentsRegressionScores(ParameterBag parameters)
        {
            MultipleLinearRegressionContext context = GetMultipleLinearRegressionContext(parameters);
            int n = context.P;
            int nx = context.N;
            double[,] x = context.X;
            double[,] v = context.V;
            double[] av = null; double[] sd = null;

            ParameterBag outputParameters = new();
            IList<ParameterBag> pcList = new List<ParameterBag>();
            outputParameters.AddOutput("*pc", pcList);
            for (int j = 1; j <= n; j++)
            {
                ParameterBag pcParameters = new();
                pcList.Add(pcParameters);
                pcParameters.AddOutput("pc", j);
            }
            if (context.M == 1)
            {
                av = new double[n + 1];
                sd = new double[n + 1];
                for (int j = 1; j <= n; j++)
                    Regress1.x_avsd(x, nx, j, out av[j], out sd[j]);
            }
            IList<ParameterBag> rowList = new List<ParameterBag>();
            outputParameters.AddOutput("*row", rowList);
            for (int j = 1; j <= nx; j++)
            {
                ParameterBag rowParameters = new();
                rowList.Add(rowParameters);
                rowParameters.AddOutput("row", j);
                IList<ParameterBag> resList = new List<ParameterBag>();
                rowParameters.AddOutput("*res", resList);
                for (int i = 1; i <= n; i++)
                {
                    double ps = 0.0;
                    for (int k = 1; k <= n; k++)
                    {
                        if (context.M == 1)
                        {
                            Debug.Assert(null != av && null != sd);
                            ps += v[k, i] * ((x[k, j] - av[k]) / sd[k]);
                        }
                        else
                        {
                            ps += v[k, i] * x[k, j];
                        }
                    }
                    ParameterBag resParameters = new();
                    resList.Add(resParameters);
                    resParameters.AddOutput("res", ps);
                }
            }
            return new StepOutput(outputParameters);
        }

        public static StepOutput RptPrincipalComponentsRegressionMatrix(ParameterBag parameters)
        {
            MultipleLinearRegressionContext context = GetMultipleLinearRegressionContext(parameters);
            DataFrame frame = parameters["data"].AsDataFrame;
            int n = context.P;
            double[,] xc = context.H;
            double[,] xr = context.R2;
            ParameterBag outputParameters = new();
            outputParameters.AddOutput("type", context.M == 1 ? "Correlation" : "Variance-Covariance");
            IList<ParameterBag> lab1List = new List<ParameterBag>();
            outputParameters.AddOutput("*lab1", lab1List);
            for (int j = 1; j <= n; j++)
            {
                ParameterBag lab1Parameters = new();
                lab1List.Add(lab1Parameters);
                lab1Parameters.AddOutput("lab", frame.Variables[j - 1].Title);
            }
            IList<ParameterBag> lab2List = new List<ParameterBag>();
            outputParameters.AddOutput("*lab2", lab2List);
            for (int j = 1; j <= n; j++)
            {
                ParameterBag lab2Parameters = new();
                lab2List.Add(lab2Parameters);
                lab2Parameters.AddOutput("lab", frame.Variables[j - 1].Title);
                IList<ParameterBag> resList = new List<ParameterBag>();
                lab2Parameters.AddOutput("*res", resList);
                for (int i = 1; i <= n; i++)
                {
                    ParameterBag resParameters = new();
                    resList.Add(resParameters);
                    resParameters.AddOutput("res", context.M == 1 ? xr[j, i] : xc[j, i]);
                }
            }
            return new StepOutput(outputParameters);
        }

        public static StepOutput RptLinearizedEstimates(ParameterBag parameters)
        {
            SimpleLinearRegressionContext context = GetSimpleLinearRegressionContext(parameters);
            int model = 0;
            if (parameters.ContainsKey("model"))
                model = Parsing.Cint_Txt(parameters["model"].AsString);

            int nx = context.NX;
            ParameterBag outputParameters = new();
            switch (model)
            {
                case 0:
                    context.ApplyToY(Math.Log);
                    outputParameters.AddOutput("modelDescription", "(Exponential)  Y = a * exp(b * x)");
                    context.CalculateLeastSquaresMethod();
                    context.A = Math.Exp(context.YIntercept);
                    context.G = context.Slope;
                    break;
                case 1:
                    context.ApplyToY(Math.Log);
                    context.ApplyToX(Math.Log);
                    outputParameters.AddOutput("modelDescription", "(Geometric / Power)  Y = a * x^b");
                    context.CalculateLeastSquaresMethod();
                    context.A = Math.Exp(context.YIntercept);
                    context.G = context.Slope;
                    break;
                case 2:
                    context.ApplyToY(a => 1.0 / a);
                    context.ApplyToX(a => 1.0 / a);
                    outputParameters.AddOutput("modelDescription", "(Hyperbolic)  Y = x / (a + b * x)");
                    context.CalculateLeastSquaresMethod();
                    context.A = context.Slope;
                    context.G = context.YIntercept;
                    break;
                default:
                    throw new Exception("Unknown model");
            }

            outputParameters.AddOutput("lab_y", context.YTitle);
            outputParameters.AddOutput("lab_x", context.XTitle);
            outputParameters.AddOutput("a", context.A);
            outputParameters.AddOutput("b", context.G);
            outputParameters.AddOutput("r", context.R);
            outputParameters.AddOutput("r2", context.R * context.R);
            outputParameters.AddOutput("ste", context.SeEst);
            outputParameters.AddInput("context", context.StripForOutput());
            return new StepOutput(outputParameters);
        }

        public static StepOutput RptLinearizedEstimateInterpolation(ParameterBag parameters)
        {
            SimpleLinearRegressionContext context = GetSimpleLinearRegressionContext(parameters);
            int model = 0;
            if (parameters.ContainsKey("model"))
                model = Parsing.Cint_Txt(parameters["model"].AsString);
            double newx = parameters["newx"].AsDouble;
            double newy = 0;
            switch (model)
            {
                case 0:
                    newy = Math.Exp(context.YIntercept) * Math.Exp(context.Slope * newx);
                    break;
                case 1:
                    newy = Math.Exp(context.YIntercept) * Math.Pow(newx, context.Slope);
                    break;
                case 2:
                    double denom = context.Slope + newx * context.YIntercept;
                    if (denom == 0.0)
                        denom = 0.0000001;
                    newy = newx / denom;
                    break;
            }

            ParameterBag outputParameters = new();
            outputParameters.AddOutput("lab_x", context.XTitle);
            outputParameters.AddOutput("res_x", newx);
            outputParameters.AddOutput("lab_y", context.YTitle);
            outputParameters.AddOutput("res_y", newy);
            return new StepOutput(outputParameters);
        }

        public static StepOutput RptLinearizedEstimatePlot(ParameterBag parameters)
        {
            DataFrame fY = parameters["y"].AsDataFrame;
            DoubleVariable vY = (DoubleVariable)fY.Variables[0];
            DataFrame fX = parameters["x"].AsDataFrame;
            DoubleVariable vX = (DoubleVariable)fX.Variables[0];
            SimpleLinearRegressionContext context = GetSimpleLinearRegressionContext(parameters);
            int model = 0;
            if (parameters.ContainsKey("model"))
                model = Parsing.Cint_Txt(parameters["model"].AsString);

            ParameterBag outputParameters = new();
            outputParameters.AddOutput("chart", ChartRendererFactory.PrepForLater(ChartType.LinearizedEstimation, new LinearizedEstimationOptions(string.Empty, model, context.A, context.G, vX.Title, vY.Title), new DoubleSeries(vX.Data, vX.Title), new DoubleSeries(vY.Data, vY.Title)));
            return new StepOutput(outputParameters);
        }

        public static StepOutput RptPolynomialRegression(ParameterBag parameters)
        {
            DataFrame fY = parameters["y"].AsDataFrame;
            DoubleVariable vY = (DoubleVariable)fY.Variables[0];
            int P = Parsing.Cint_Txt(parameters["degree"].AsString) + 1;
            MultipleLinearRegressionContext context = new() { N = vY.Length, P = P, DoC = true };
            CalcPoly(parameters, context);
            (context.P, context.M) = x_glin(context, context.P, context.M);
            return new StepOutput(MakeMultipleRegressionOutput(context, context.Se, context.B, true, context.N, context.P, true, context.M, null));
        }

        ///  <summary>
        ///  Fill in py, weight, px and titles given X and Y data, P and N.
        ///  </summary>
        /// <param name="parameters"></param>
        ///  <param name="context"></param>
        ///  <remarks></remarks>
        private static void CalcPoly(ParameterBag parameters, MultipleLinearRegressionContext context)
        {
            DataFrame fY = parameters["y"].AsDataFrame;
            DoubleVariable vY = (DoubleVariable)fY.Variables[0];
            DataFrame fX = parameters["x"].AsDataFrame;
            DoubleVariable vX = (DoubleVariable)fX.Variables[0];
            //  Sort X and Y in increasing order of X
            Array.Sort(vX.Data, vY.Data);
            int deg = context.P - 1;
            context.Y = new double[context.N + 1];
            context.S = new double[context.N + 1];
            context.X = new double[context.N + 1, context.P + 1];
            context.Titles = new string[context.N + 1];
            context.Titles[0] = vY.Title;
            context.Titles[1] = vX.Title;
            for (int j = 1; j <= context.N; j++)
                context.X[j, 1] = 1.0;
            for (int j = 1; j <= deg; j++)
                for (int i = 1; i <= context.N; i++)
                    context.X[i, j + 1] = Math.Pow(vX.Data[i - 1], Convert.ToDouble(j));
            if (context.P > deg)
            {
                context.Titles[2] = context.Titles[1];
                context.Titles[1] = context.Titles[0];
                for (int j = 3; j <= context.P; j++)
                    context.Titles[j] = context.Titles[2] + "^" + (j - 1).ToString();
            }
            else
            {
                for (int j = 2; j <= deg; j++)
                    context.Titles[j] = context.Titles[1] + "^" + j.ToString();
            }
            for (int j = 1; j <= context.N; j++)
            {
                context.Y[j] = vY.Data[j - 1];
                context.S[j] = 1.0;
            }
        }

        public static StepOutput RptPolynomialRegressionInterpolation(ParameterBag parameters)
        {
            MultipleLinearRegressionContext context = (MultipleLinearRegressionContext)parameters["context"].AsObject;
            double[,] xtxi = context.H;
            double[] bd = context.B;
            double rss = context.SSY - context.SSREG;
            int nx = context.N;
            int p = context.P;
            double[] newx = new double[p + 1];
            newx[1] = 1.0;
            double nwx = parameters["newx"].AsDouble;
            if (p > 1)
            {
                for (int n = 2; n <= p; n++)
                    newx[n] = Math.Pow(nwx, n - 1);
            }
            double newy = 0;
            for (int n = 1; n <= p; n++)
                newy += newx[n] * bd[n];
            double gamma = parameters["gamma"].AsDouble;
            MathDbl.civ(nx - p, out double cit, gamma, out double P0);
            ParameterBag outputParameters = new();
            IList<ParameterBag> tableList = new List<ParameterBag>();
            outputParameters.AddOutput("*table", tableList);
            for (int n = 1; n <= p; n++)
            {
                ParameterBag tableParameters = new();
                tableList.Add(tableParameters);
                tableParameters.AddOutput("lab", n == 1 ? "Intercept" : context.Titles[n - 1]);
                tableParameters.AddOutput("res", newx[n]);
            }
            outputParameters.AddOutput("y_lab", context.Titles[0]);
            outputParameters.AddOutput("y_res", newy);
            double rdf = nx - 1 - (p - 1);
            double rms = rss / rdf;
            Regress1.x_ciyp(newx, xtxi, p, rms, cit, out double cl, out double pl);
            outputParameters.AddOutput("pc", 100 * (1.0 - P0));
            outputParameters.AddOutput("from_conf", newy - cl);
            outputParameters.AddOutput("to_conf", newy + cl);
            outputParameters.AddOutput("from_pred", newy - pl);
            outputParameters.AddOutput("to_pred", newy + pl);
            return new StepOutput(outputParameters);
        }

        public static StepOutput RptPolynomialRegressionPlot(ParameterBag parameters)
        {
            MultipleLinearRegressionContext context = (MultipleLinearRegressionContext)parameters["context"].AsObject;
            ParameterBag outputParameters = new();
            IList<ParameterBag> chartList = new List<ParameterBag>();
            outputParameters.AddOutput("*chart", chartList);
            for (int mode = 0; mode <= 2; mode++)
            {
                ParameterBag chartParameters = new();
                chartList.Add(chartParameters);
                chartParameters.AddOutput("chart", PlotPoly(parameters, mode, context.H, context.B, context.SSREG - context.SSY, context.N, context.P));
            }
            return new StepOutput(outputParameters);
        }

        private static IRenderable PlotPoly(ParameterBag parameters, int mode, double[,] xtxi, double[] bd, double rss, int nx, int P)
        {
            DataFrame fY = parameters["y"].AsDataFrame;
            DoubleVariable vY = (DoubleVariable)fY.Variables[0];
            DataFrame fX = parameters["x"].AsDataFrame;
            DoubleVariable vX = (DoubleVariable)fX.Variables[0];
            double gamma = parameters["gamma"].AsDouble;
            MathDbl.civ(nx - P, out double _, gamma, out double p0);
            string title = string.Empty;
            // Select the title
            switch (mode)
            {
                case 0:
                    title = string.Empty;
                    break;
                case 1:
                    title = Formatting.XRound((1.0 - p0) * 100, 1) + "% CI for the regression estimate";
                    break;
                case 2:
                    title = Formatting.XRound((1.0 - p0) * 100, 1) + "% Prediction Interval";
                    break;
            }

            return ChartRendererFactory.PrepForLater(ChartType.PolynomialRegression, new PolynomialRegressionOptions(title, mode, xtxi, bd, rss, nx, P, gamma, vX.Title, vY.Title), new DoubleSeries(vX.Data, vX.Title), new DoubleSeries(vY.Data, vY.Title));
        }

        public static StepOutput RptAreaUnderCurve(IFormatting host, ParameterBag parameters)
        {
            MultipleLinearRegressionContext context = (MultipleLinearRegressionContext)parameters["context"].AsObject;
            double[] bd = context.B;
            int nx = context.N;
            int p = context.P;
            DataFrame fY = parameters["y"].AsDataFrame;
            DoubleVariable vY = (DoubleVariable)fY.Variables[0];
            DataFrame fX = parameters["x"].AsDataFrame;
            DoubleVariable vX = (DoubleVariable)fX.Variables[0];

            ParameterBag outputParameters = new();
            double auc = 0;
            outputParameters.AddOutput("poly_auc",
                x_qromb(vX.Data[0], vX.Data[vX.Length - 1], ref auc, bd, p)
                    ? host.RoundU(auc)
                    : Formatting.ERRR);
            double aucg = x_giabaldi(nx, vY.Data, vX.Data);
            outputParameters.AddOutput("trap_auc", aucg);
            return new StepOutput(outputParameters);
        }

        private static bool x_qromb(double a, double b, ref double ss, double[] bd, int p)
        {
            double ds = 0;
            const double eps = 100.0 * Constant.EPSNEG;
            const int jmax = 16;
            const int jmaxp = jmax + 1;
            const int k = 5;
            const int km = k - 1;
            double[] h = new double[jmaxp + 1];
            double[] s = new double[jmaxp + 1];
            h[1] = 1.0;
            int j;
            for (j = 1; j <= jmax; j++)
            {
                s[j] = Regress1.trapzd(a, b, s[j], j, bd, p);
                if (j >= k)
                {
                    int ifault = 0;
                    Regress1.polint(h, s, j - km, k, 0.0, out ss, ref ds, ref ifault);
                    if (ifault != 0)
                        return false;
                    if (Math.Abs(ds) <= eps * Math.Abs(ss))
                        return true;
                }
                s[j + 1] = s[j];
                h[j + 1] = 0.25 * h[j];
            }
            return j < jmax;
        }

        private static double x_giabaldi(int nx, double[] y, double[] x)
        {
            double ss = 0.0;
            for (int i = 1; i < nx; i++)
                ss += (y[i] + y[i - 1]) / 2.0 * Math.Abs(x[i] - x[i - 1]);
            return ss;
        }

        public static StepOutput RptPolynomialRegressionConfidence(ParameterBag parameters)
        {
            MultipleLinearRegressionContext context = (MultipleLinearRegressionContext)parameters["context"].AsObject;
            int nx = context.N;
            int p = context.P;
            double[,] xtxi = context.H;
            double[] yfit = context.FV;
            double[,] x = context.X;
            double rss = context.SSY - context.SSREG;
            double rdf = Convert.ToDouble(nx - 1 - (p - 1));
            double rms = rss / rdf;
            double GAMMA = parameters["gamma"].AsDouble;
            MathDbl.civ(nx - p, out double cit, GAMMA, out double P0);
            DoubleVariable vYFit = new(nx, "Fitted Y");
            DoubleVariable vsey = new(nx, "SE of Y fit");
            DoubleVariable vcl = new(nx, Formatting.XRound(100.0 * (1.0 - P0), 1) + "% Conf Limit");
            DoubleVariable vpl = new(nx, Formatting.XRound(100.0 * (1.0 - P0), 1) + "% Pred Limit");
            for (int k = 1; k <= nx; k++)
            {
                double xcx = 0;
                double s;
                for (int i = 1; i <= p; i++)
                {
                    s = 0;
                    for (int j = 1; j <= p; j++)
                        s += xtxi[i, j] * x[k, j];
                    xcx += s * x[k, i];
                }
                double sey = Math.Sqrt(rms * xcx);
                double cl = cit * sey;
                s = Math.Sqrt(rms * (1.0 + xcx));
                double pl = cit * s;
                vYFit.SetData(k - 1, yfit[k]);
                vsey.SetData(k - 1, sey);
                vcl.SetData(k - 1, cl);
                vpl.SetData(k - 1, pl);
            }
            DataFrame outputFrame = new();
            outputFrame.Variables.Add(vYFit);
            outputFrame.Variables.Add(vsey);
            outputFrame.Variables.Add(vcl);
            outputFrame.Variables.Add(vpl);
            ParameterBag outputParameters = new();
            outputParameters.AddOutput("results", outputFrame);
            return new StepOutput(outputParameters);
        }

        public static StepOutput RptPolynomialRegressionBackInterpolation(IFormatting host, ParameterBag parameters)
        {
            MultipleLinearRegressionContext context = (MultipleLinearRegressionContext)parameters["context"].AsObject;
            double[] bd = context.B;
            int nx = context.N;
            int p = context.P;
            double[] yfit = context.FV;
            DataFrame fX = parameters["x"].AsDataFrame;
            DoubleVariable vX = (DoubleVariable)fX.Variables[0];
            long cnt = 0; bool fault = false;
            double lastdif = 0;
            double y = parameters["newy"].AsDouble;
            double yMax = yfit[1];
            double yMin = yfit[1];
            double xMax = vX.Data[0];
            double xMin = xMax;
            for (int j = 1; j <= nx; j++)
            {
                if (yfit[j] > yMax)
                    yMax = yfit[j];
                if (yfit[j] < yMin)
                    yMin = yfit[j];
                double x = vX.Data[j - 1];
                if (x > xMax)
                    xMax = x;
                if (x < xMin)
                    xMax = x;
            }
            if (y > yMax || y < yMin)
                throw new TemplateOperationCancelledException("Y must lie within the fitted curve (" + host.RoundU(yMin) + " to " + host.RoundU(yMax) + ")", "Polynomial Interpolation");

            double inc = (xMax - xMin) / 10.0;
            double yinc = (yMax - yMin) / 10.0;
            double gotx = xMin - inc;
            while (true)
            {
                while (true)
                {
                    cnt += 1;
                    if (cnt > 10000)
                    {
                        fault = true;
                        break;
                    }
                    gotx += inc;
                    double goty = Regress1.polyfunc(gotx, bd, p);
                    double dif = Math.Abs(goty - y);
                    if (dif == lastdif)
                        break;
                    lastdif = dif;
                    if (dif < Math.Abs(yinc * 10))
                    {
                        yinc /= 10.0;
                        gotx -= inc;
                        break;
                    }
                }
                inc /= 10.0;
                if (inc < Constant.EPSNEG * 10.0)
                    break;
                if (fault)
                    break;
            }
            ParameterBag outputParameters = new();
            outputParameters.AddOutput("y", Regress1.polyfunc(gotx, bd, p));
            outputParameters.AddOutput("x", gotx);
            if (fault)
                outputParameters.AddOutput("*error", new List<ParameterBag>() { new ParameterBag() });
            return new StepOutput(outputParameters);
        }

        public static StepOutput RptLogisticRegression(IFormatting host, ParameterBag parameters)
        {
            int rows;
            int totObs;
            double[] tt; double[] tr; double[] tw;

            double accuracy = Parsing.Cdbl_Txt(parameters["accuracy"].AsString);
            if (accuracy > 0.01)
                accuracy = 0.01;
            bool grouped = "grouped".Equals(parameters["grouping"].AsString);
            bool shouldCalculateIntercept = parameters["intercept"].AsBoolean;
            bool hasWeights = parameters["weights"].AsBoolean;

            DoubleVariable responseVariable;
            if (grouped)
            {
                DataFrame totalFrame = parameters["total"].AsDataFrame;
                DoubleVariable totalVariable = (DoubleVariable)totalFrame.Variables[0];
                // Store the total Data
                rows = totalVariable.Length;
                tt = new double[rows + 1];
                tr = new double[rows + 1];
                tw = new double[rows + 1];
                totObs = 0;
                for (int c = 1; c <= rows; c++)
                {
                    tt[c] = totalVariable.Data[c - 1];
                    if (tt[c] != Constant.MISSING) totObs += Convert.ToInt32(tt[c]);
                }
                DataFrame responseFrame = parameters["response"].AsDataFrame;
                responseVariable = (DoubleVariable)responseFrame.Variables[0];
                // Store the response data
                for (int c = 1; c <= rows; c++)
                    tr[c] = responseVariable.Data[c - 1];
            }
            else
            {
                DataFrame responseFrame = parameters["response"].AsDataFrame;
                responseVariable = (DoubleVariable)responseFrame.Variables[0];
                rows = responseVariable.Length;
                tt = new double[rows + 1];
                tr = new double[rows + 1];
                tw = new double[rows + 1];
                // Store the response data
                for (int c = 1; c <= rows; c++)
                {
                    tr[c] = responseVariable.Data[c - 1];
                    if (tr[c] > 1.0 && tr[c] != Constant.MISSING)
                        throw new TemplateOperationCancelledException("Response data must be either 0 (not responded) or 1 (responded), if you want to use grouped response data then please select this option at the start", "Logistic Regression");
                }
                // Total observations = rows
                totObs = rows;
                // set denominator/total as 1
                for (int c = 1; c <= rows; c++)
                    tt[c] = 1.0;
            }
            if (hasWeights)
            {
                DataFrame weightsFrame = parameters["weights"].AsDataFrame;
                DoubleVariable weightsVariable = (DoubleVariable)weightsFrame.Variables[0];
                // Store the weight Data
                for (int c = 1; c <= rows; c++)
                    tw[c] = weightsVariable.Data[c - 1];
            }
            else
            {
                for (int c = 1; c <= rows; c++)
                    tw[c] = 1.0;
            }
            DataFrame predictorsFrame = parameters["predictors"].AsDataFrame;
            // Store the predictors
            int prd = predictorsFrame.VariableCount;
            double[,] pt = new double[prd, rows + 1];
            for (int c = 0; c < prd; c++)
            {
                DoubleVariable v = (DoubleVariable)predictorsFrame.Variables[c];
                double[] data = v.Data;
                int r;
                for (r = 1; r <= rows; r++)
                    pt[c, r] = data[r - 1];
            }
            // check predictors for categorical data not yet dummied
            if (prd + 1 >= totObs)
                throw new TemplateOperationCancelledException("You must have more observations than parameters", "Logistic Regression");

            // stack entries with duplicate covariate patterns
            // IEB July 2009: don't stack missing observations in the response as the subsequent dropper won't work
            int cutrows = 0;
            for (int i = 1; i < rows; i++)
            {
                for (int j = i + 1; j <= rows; j++)
                {
                    if (tw[j] == 1.0 && tr[j] != Constant.MISSING)
                    {
                        bool snap = true;
                        for (int k = 0; k < prd; k++)
                        {
                            if (pt[k, j] != pt[k, i])
                            {
                                snap = false;
                                break;
                            }
                        }
                        if (snap)
                        {
                            tt[i] += tt[j];
                            tr[i] += tr[j];
                            tw[j] = Constant.MISSING;
                            cutrows += 1;
                        }
                    }
                }
            }
            //  At this point we have merged rows where there are duplicate covariate patterns, and all other rows have MISSING in the weights.  There are rows - cutrows valid rows in the arrays, but they could be anywhere!
            int newrows = rows - cutrows;
            //  Copy down the remaining observations
            //  0 = tt = total observations
            //  1 = tr = responses
            //  2 = tw = weights
            //  3+ = pt = predictors
            int targetRow = 1;
            for (int sourceRow = 1; sourceRow <= rows; sourceRow++)
            {
                if (tw[sourceRow] != Constant.MISSING)
                {
                    //  This row is valid; if necessary, copy it down to our current target row
                    if (sourceRow != targetRow)
                    {
                        tt[targetRow] = tt[sourceRow];
                        tr[targetRow] = tr[sourceRow];
                        tw[targetRow] = tw[sourceRow];
                        for (int pred = 0; pred < prd; pred++)
                            pt[pred, targetRow] = pt[pred, sourceRow];
                    }
                    targetRow += 1;
                }
            }
            Debug.Assert(targetRow == newrows + 1);
            //  At this point, tt, tr, tw and pt contain valid data from row 1 to row newrows inclusive

            bool useWeights = false; int rank = 0; int df = 0;
            double devx; double llx;
            const int maxit = 200;
            int records = newrows;
            int[] rxi = new int[1 + 1];
            int predictors = predictorsFrame.VariableCount;
            int p = predictors;
            bool mean = shouldCalculateIntercept;
            if (mean)
                p++;

            double tol = accuracy;
            string[] labels = new string[p + 1];
            labels[0] = responseVariable.Title.Trim();
            for (int j = 1; j <= predictors; j++)
                labels[j] = predictorsFrame.Variables[j - 1].Title.Trim();

            // Copy tt to t, tr yo y, tw to wt, pt to x.  Check for missing data; if any is present for a row, do not copy the row.
            int cnt = 0;
            double[] t = new double[records + 1];
            double[] y = new double[records + 1];
            double[] wt = new double[records + 1];
            double[,] x = new double[records + 1, p + 1];
            for (int j = 1; j <= records; j++)
            {
                bool ok = tt[j] != Constant.MISSING && tr[j] != Constant.MISSING;
                if (useWeights && tw[j] == Constant.MISSING)
                    ok = false;
                for (int k = 0; k < predictors; k++)
                {
                    if (pt[k, j] == Constant.MISSING)
                    {
                        ok = false;
                        break;
                    }
                }
                if (ok)
                {
                    cnt++;
                    t[cnt] = tt[j];
                    y[cnt] = tr[j];
                    if (y[cnt] == 0.0)
                        y[cnt] = Constant.EPSNEG;
                    if (y[cnt] == t[cnt])
                        y[cnt] = y[cnt] - Constant.EPSNEG;
                    if (useWeights)
                        wt[cnt] = tw[j];
                    else
                        wt[cnt] = 1.0;
                    for (int k = 1; k <= predictors; k++)
                        x[cnt, k] = pt[k - 1, j];
                }
            }
            ParameterBag outputParameters = new();
            IList<ParameterBag> warnList = new List<ParameterBag>();
            outputParameters.AddOutput("*warn", warnList);
            if (records != cnt)
            {
                AddDropWarning(warnList, records - cnt);
                records = cnt;
            }
            //  get intercept deviance - drop predictors
            double[,] x2 = new double[records + 1, 1 + 1];
            for (int j = 1; j <= records; j++)
            {
                x2[j, 0] = 1;
                x2[j, 1] = 1;
            }
            bool[] selectX = new bool[1 + 1];
            selectX[1] = true;
            double[] beta = new double[1 + 1];
            double[] seBeta = new double[records + 1];
            double[] covariance = new double[1 + 1];
            double[] fit = new double[records + 1];
            double[] residual = new double[records + 1];
            double[] leverage = new double[records + 1];
            double[] offset = new double[records + 1];
            string dropped = string.Empty;
            string errMsg = string.Empty;
            Regress1.X_Logistic_Regression(false, false, ref useWeights, records, x2, 1, selectX, 1, y, t, wt, out double deviance, ref df, beta, ref rank, seBeta, covariance, tol, maxit, fit, residual, leverage, offset, out int fault, ref dropped, ref errMsg);
            int idfx = df;
            if (mean == false)
            {
                llx = Constant.MISSING;
                devx = Constant.MISSING;
            }
            else
            {
                llx = x_loglik_l(useWeights, records, wt, y, t, fit);
                devx = deviance;
            }

            //  calculate full model
            selectX = new bool[p + 1];
            for (int j = 1; j <= p; j++)
                selectX[j] = true;

            beta = new double[p + 1];
            seBeta = new double[records + 1];
            covariance = new double[(int)Math.Floor((double)p * (p + 1) / 2) + 1];
            fit = new double[records + 1];
            residual = new double[records + 1];
            leverage = new double[records + 1];
            offset = new double[records + 1];
            dropped = string.Empty;
            errMsg = string.Empty;
            Regress1.X_Logistic_Regression(mean, false, ref useWeights, records, x, predictors, selectX, p, y, t, wt, out deviance, ref df, beta, ref rank, seBeta, covariance, tol, maxit, fit, residual, leverage, offset, out fault, ref dropped, ref errMsg);
            if (fault != 0 && fault != 3)
                throw new TemplateOperationCancelledException(errMsg, "Logistic Regression");

            if (fault == 3 && errMsg.Length > 0)
                warnList.Add(new ParameterBag("warn", new FilledStringParameter(FilledParameterDirection.Output, Formatting.WRNCOLON + errMsg)));
            if (rank != p)
                warnList.Add(new ParameterBag("warn", new FilledStringParameter(FilledParameterDirection.Output, Formatting.WRNCOLON + "result not of full rank, there is more than one solution for the model. Look for correlated predictor variables that you might drop: the mutliple linear regression function does this automatically.")));
            if (df <= 0)
                warnList.Add(new ParameterBag("warn", new FilledStringParameter(FilledParameterDirection.Output, Formatting.WRNCOLON + "saturated model (all degrees of freedom used, can't assess goodness of fit)")));
            if (dropped.Length > 0)
                warnList.Add(new ParameterBag("warn", new FilledStringParameter(FilledParameterDirection.Output, dropped)));
            outputParameters.AddOutput("dev", deviance);
            outputParameters.AddOutput("df", df);
            double prob = PDF.chivalp(deviance, df);
            outputParameters.AddOutput("p", prob);
            outputParameters.AddOutput("w", prob < 0.05 ? Formatting.ASTERISK : string.Empty);
            double x2Dev = devx - deviance;
            if (x2Dev < 0.0)
                x2Dev = Constant.MISSING;

            outputParameters.AddOutput("x2", x2Dev);
            outputParameters.AddOutput("df_lr", idfx - df);
            outputParameters.AddOutput("p_lr",
                idfx > 0
                    ? PDF.chivalp(x2Dev, idfx - df)
                    : Constant.MISSING);

            // IEB Dec 14 change from reporting coefficients to reporting odds ratios
            double gamma = parameters["gamma"].AsDouble;
            MathDbl.civ(0, out double cit, gamma, out double p0);
            outputParameters.AddOutput("pc", 100 * (1.0 - p0));
            int iq = 0;
            if (mean)
                iq = 1;
            IList<ParameterBag> varList = new List<ParameterBag>();
            outputParameters.AddOutput("*var", varList);
            for (int i = 1; i <= p; i++)
            {
                prob = seBeta[i] == 0
                    ? Constant.MISSING
                    : 2.0 * (1.0 - PDF.alnorm(Math.Abs(beta[i] / seBeta[i])));
                ParameterBag varParameters = new();
                varList.Add(varParameters);
                string q = i == 1 && mean ? "(intercept)" : labels[i - iq];
                varParameters.AddOutput("par", q);
                if (i > 1 || !mean)
                {
                    double odr = Formatting.SafeExp(beta[i]);
                    double lci = Formatting.SafeExp(beta[i] - seBeta[i] * cit);
                    double uci = Formatting.SafeExp(beta[i] + seBeta[i] * cit);
                    varParameters.AddOutput("or", odr);
                    varParameters.AddOutput("*ci",
                        new List<ParameterBag>()
                        {
                            new ParameterBag()
                                .AddOutput("lci", lci)
                                .AddOutput("uci", uci)
                        });
                }
                else
                {
                    varParameters.AddOutput("or", "n/a");
                }
                if (seBeta[i] == 0.0)
                {
                    double z = Constant.MISSING;
                    varParameters.AddOutput("z", z);
                    varParameters.AddOutput("p_var", "* error: drop this variable *");
                }
                else
                {
                    double z = beta[i] / seBeta[i];
                    varParameters.AddOutput("z", z);
                    varParameters.AddOutput("p_var", prob);
                }
            }

            /*
            IList<ParameterBag> varList = new List<ParameterBag>();
            outputParameters.AddOutput("*var", varList);
            for (int i = 1; i <= p; i++)
            {
                if (se_beta[i] == 0)
                    prob = Constant.MISSING;
                else
                    prob = 2.0 * (1.0 - PDF.alnorm(Math.Abs(beta[i] / se_beta[i])));
                ParameterBag varParameters = new ParameterBag();
                varList.Add(varParameters);
                if (mean)
                {
                    varParameters.AddOutput("lab", i == 1 ? "Intercept" : label[i - 1]);
                    varParameters.AddOutput("idx", (i - 1).ToString());
                }
                else
                {
                    varParameters.AddOutput("lab", label[i]);
                    varParameters.AddOutput("idx", i.ToString());
                }
                varParameters.AddOutput("res", host.RoundU(beta[i]));
                double z;
                if (se_beta[i] == 0.0)
                {
                    z = Constant.MISSING;
                    varParameters.AddOutput("z", host.RoundU(z));
                    varParameters.AddOutput("p_var", "* error: drop this variable *");
                }
                else
                {
                    z = beta[i] / se_beta[i];
                    varParameters.AddOutput("z", host.RoundU(z));
                    varParameters.AddOutput("p_var", host.pval(prob));
                }
            }
            */

            string tx = "logit ";
            if (labels[0].Length > 0)
                tx += labels[0];
            else
                tx += "Y";
            tx += " = ";
            for (int j = 1; j <= p; j++)
            {
                if (j > 1 && beta[j] >= 0.0)
                    tx += "+";
                tx += host.RoundU(beta[j]);
                string Q = mean
                    ? (j > 1 ? labels[j - 1] : " ")
                    : labels[j];
                if (Q.Length == 0)
                    tx += " X" + j.ToString();
                else
                    tx += " " + Q + " ";
            }
            outputParameters.AddOutput("logit", tx);
            MultipleLinearRegressionContext context = new();
            outputParameters.AddInput("context", context.StripForOutput());
            context.Se = seBeta;
            context.B = beta;
            context.T = t;
            context.X = x;
            context.Y = y;
            context.FV = fit;
            context.R = residual;
            context.H1 = leverage;
            context.N = records;
            context.DoC = mean;
            context.Labels = labels;
            context.P = p;
            context.Covariance = covariance;
            context.WT = wt;
            context.RXI = rxi;
            context.WEIGHT = useWeights;
            context.RANK = rank;
            context.DF = df;
            context.TOL = tol;
            context.M = predictors;
            context.DEV = deviance;
            context.DEVX = devx;
            context.LLX = llx;
            context.DFX = idfx;
            outputParameters["candidatePredictors"] = FilledParameterFactory.Input(x_prep_interlr(context));
            return new StepOutput(outputParameters);
        }

        private static double x_loglik_p(bool useWeights, int n, double[] wt, double[] y, double[] fvl)
        {
            double ll = 0;
            int i;

            for (i = 1; i <= n; i++)
            {
                double ww = useWeights ? wt[i] : 1.0;
                ll += ww * y[i] * Math.Log(fvl[i]) - ww * fvl[i] - ww * PDF.alogam(y[i] + 1.0);
            }
            return ll;
        }

        private static double x_loglik_l(bool useWeights, int n, double[] wt, double[] y, double[] t, double[] fvl)
        {
            double ll = 0;
            for (int i = 1; i <= n; i++)
            {
                double pp = fvl[i] / t[i];
                double ww = useWeights ? wt[i] : 1.0;
                if (pp != 0.0)
                    ll = ww * ll + y[i] * Math.Log(pp) + ww * (t[i] - y[i]) * Math.Log(1.0 - pp);
            }
            return ll;
        }

        private static void AddDropWarning(IList<ParameterBag> warnList, int q)
        {
            warnList.Add(new ParameterBag("warn", new FilledStringParameter(FilledParameterDirection.Output, q.ToString() + " observations dropped due to missing data. Make sure that observations with missing data are not a subgroup.")));
        }

        public static StepOutput RptLogisticRegressionFit(ParameterBag parameters)
        {
            MultipleLinearRegressionContext context = (MultipleLinearRegressionContext)parameters["context"].AsObject;

            double[] t = context.T;
            double[] y = context.Y;
            double[] fvl = context.FV;
            double[] dr = context.R;
            double[] hi = context.H1;
            // double[] var = context.V1; 
            int nx = context.N;
            bool DoC = context.DoC;
            string[] labels = context.Labels;
            int P = context.P;
            double[] covariance = context.Covariance;
            double[] wt = context.WT;
            bool weight = context.WEIGHT;
            double[,] x = context.X;

            double[] ry = new double[nx + 1];
            double[] fit = new double[nx + 1];
            double[] PP = new double[nx + 1];
            double[] ww = new double[nx + 1];
            double[] pxi = new double[nx + 1];
            double[] xis = new double[nx + 1];
            double[] cbar = new double[nx + 1];
            double[] c = new double[nx + 1];
            double[] d = new double[nx + 1];
            double[] dc = new double[nx + 1];
            for (int i = 1; i <= nx; i++)
            {
                // Deviance
                ry[i] = y[i] <= Constant.EPSNEG ? 0.0 : y[i];
                fit[i] = t[i] != 0.0 ? fvl[i] / t[i] : Constant.MISSING;

                // Pearson
                PP[i] = fvl[i] / t[i];
                ww[i] = weight
                    ? wt[i]
                    : 1.0;
                pxi[i] = PP[i] != 0.0
                    ? (y[i] - t[i] * PP[i]) * Math.Sqrt(ww[i]) / Math.Sqrt(t[i] * PP[i] * (1.0 - PP[i]))
                    : Constant.MISSING;
                xis[i] = 1.0 - hi[i] > 0.0 && pxi[i] != Constant.MISSING
                    ? pxi[i] / Math.Sqrt(1.0 - hi[i])
                    : Constant.MISSING;

                // Delta beta et al.  IEB July 2009
                if (PP[i] * (1.0 - PP[i]) != 0.0)
                {
                    double xi = (y[i] - t[i] * PP[i]) * Math.Sqrt(ww[i]) / Math.Sqrt(t[i] * PP[i] * (1.0 - PP[i]));
                    c[i] = Math.Pow(xi, 2.0) * hi[i] / Math.Pow(1.0 - hi[i], 2.0);
                    cbar[i] = Math.Pow(xi, 2.0) * hi[i] / (1.0 - hi[i]);
                    d[i] = Math.Pow(dr[i], 2.0) + cbar[i];
                    dc[i] = cbar[i] / hi[i];
                }
                else
                {
                    c[i] = Constant.MISSING;
                    cbar[i] = Constant.MISSING;
                    d[i] = Constant.MISSING;
                    dc[i] = Constant.MISSING;
                }
            }

            ParameterBag outputParameters = new();

            // Output is individual if the user selected individual rows in the original regression *and* chose to preserve them in this call
            bool isGrouped = !("individual".Equals(parameters["grouping"].AsString) && "individual".Equals(parameters["row_type"].AsString));

            // Make up all variables for a possible future output of a frame containing all or part of these.
            // DO NOT change this order without looking at MakeLogisticRegressionFitRow and GridLogisticRegressionFit, which assume these indices.
            int variableLength = isGrouped ? nx : parameters["predictors"].AsDataFrame.MaxRows;
            DataFrame outputFrame = new();
            outputFrame.Variables.Add(new DoubleVariable(variableLength, "Trials"));
            outputFrame.Variables.Add(new DoubleVariable(variableLength, "Events"));
            outputFrame.Variables.Add(new DoubleVariable(variableLength, "Event Probability"));
            outputFrame.Variables.Add(new DoubleVariable(variableLength, "Deviance Residual"));
            outputFrame.Variables.Add(new DoubleVariable(variableLength, "Pearson Residual"));
            outputFrame.Variables.Add(new DoubleVariable(variableLength, "Leverage"));
            outputFrame.Variables.Add(new DoubleVariable(variableLength, "Std Pearson Residual"));
            outputFrame.Variables.Add(new DoubleVariable(variableLength, "Delta Beta"));
            outputFrame.Variables.Add(new DoubleVariable(variableLength, "Std Delta Beta"));
            outputFrame.Variables.Add(new DoubleVariable(variableLength, "Delta Deviance"));
            outputFrame.Variables.Add(new DoubleVariable(variableLength, "Delta Chi-Square"));
            outputParameters.AddOutput("fitsDump", outputFrame);

            if (isGrouped)
            {
                List<ParameterBag> groupedList = new();
                outputParameters.AddOutput("*grouped", groupedList);
                ParameterBag groupedParameters = new();
                groupedList.Add(groupedParameters);

                List<ParameterBag> predictorsList = new();
                groupedParameters.AddOutput("*predictors", predictorsList);
                for (int i = 1; i <= labels.Length - 2; i++)
                {
                    ParameterBag predictorsParameters = new();
                    predictorsList.Add(predictorsParameters);
                    predictorsParameters.AddOutput("lab", labels[i]);
                }
                List<ParameterBag> predictorValuesList = new();
                groupedParameters.AddOutput("*predictorValues", predictorValuesList);
                for (int i = 1; i <= nx; i++)
                {
                    ParameterBag bag = MakeLogisticRegressionFitRow(t, y, dr, hi, labels, x, ry, fit, pxi, xis, cbar, c, d, dc, i, true, outputFrame, i - 1);
                    predictorValuesList.Add(bag);
                }
            }
            else
            {
                List<ParameterBag> individualList = new();
                outputParameters.AddOutput("*individual", individualList);
                ParameterBag individualParameters = new();
                individualList.Add(individualParameters);

                List<ParameterBag> predictorValuesList = new();
                individualParameters.AddOutput("*predictorValues", predictorValuesList);

                double[] responses = ((DoubleVariable)parameters["response"].AsDataFrame.Variables[0]).Data;
                DataFrame predictorsFrame = parameters["predictors"].AsDataFrame;
                // Process each (known individual) predictor
                int vars = predictorsFrame.VariableCount;
                int rows = predictorsFrame.MaxRows;
                for (int predictorRow = 0; predictorRow < rows; predictorRow++)
                {
                    // Gather the predictor values for this row
                    double[] thisRow = new double[vars];
                    bool atLeastOneMissing = false;
                    for (int v = 0; v < vars; v++)
                    {
                        double value = ((DoubleVariable)predictorsFrame.Variables[v]).Data[predictorRow];
                        if (value == Constant.MISSING)
                        {
                            atLeastOneMissing = true;
                            break;
                        }
                        thisRow[v] = value;
                    }
                    // If we have missing data, this row will never have a group so there's no point looking
                    ParameterBag bag = null;
                    if (atLeastOneMissing)
                    {
                        bag = MakeLogisticRegressionFitRow(null, null, null, null, null, null, null, null, null, null, null, null, null, null, 0, false, outputFrame, predictorRow);
                    }
                    else
                    {
                        // Find that predictor pattern in our grouped data; once found, emit the matching values
                        bool snapped = false;
                        for (int i = 1; i <= nx; i++)
                        {
                            for (int xindex = 0; xindex <= nx; xindex++)
                            {
                                bool snap = true;
                                for (int predIndex = 0; predIndex < vars; predIndex++)
                                {
                                    if (x[i, predIndex + 1] != thisRow[predIndex])
                                    {
                                        snap = false;
                                        break;
                                    }
                                }
                                if (snap)
                                {
                                    bag = MakeLogisticRegressionFitRow(t, y, dr, hi, labels, x, ry, fit, pxi, xis, cbar, c, d, dc, i, false, outputFrame, predictorRow);
                                    snapped = true;
                                    break;
                                }
                            }
                        }
                        if (!snapped)
                            throw new Exception("Should never happen: Couldn't find an individual predictor pattern in the processed groups.");
                    }
                    bag.AddOutput("resbool", responses[predictorRow]);
                    bag.AddOutput("resnum", predictorRow + 1);
                    predictorValuesList.Add(bag);
                }
            }

            // Covariance
            IList<ParameterBag> covarList = new List<ParameterBag>();
            outputParameters.AddOutput("*covar", covarList);
            for (int i = 1; i <= P; i++)
            {
                for (int j = i; j <= P; j++)
                {
                    ParameterBag covarParameters = new();
                    covarList.Add(covarParameters);
                    string x1 = qlbli(labels, i, DoC);
                    string x2 = qlbli(labels, j, DoC);
                    covarParameters.AddOutput("lab", x1 + " vs. " + x2);
                    covarParameters.AddOutput("cov", covariance[(int)Math.Floor((double)j * (j - 1) / 2 + i)]);
                }
            }
            return new StepOutput(outputParameters);
        }

        private static ParameterBag MakeLogisticRegressionFitRow(double[] t, double[] y, double[] dr, double[] hi, string[] label, double[,] x, double[] ry, double[] fit, double[] pxi, double[] xis, double[] cbar, double[] c, double[] d, double[] dc, int arrayOffset, bool includePredictors, DataFrame outputFrame, int outputRow)
        {
            ParameterBag predictorValuesParameters = new();
            predictorValuesParameters.AddOutput("idx", arrayOffset);
            predictorValuesParameters.AddOutput("sub", t?[arrayOffset] ?? Constant.MISSING);
            predictorValuesParameters.AddOutput("res", ry?[arrayOffset] ?? Constant.MISSING);
            predictorValuesParameters.AddOutput("fit", fit?[arrayOffset] ?? Constant.MISSING);
            predictorValuesParameters.AddOutput("dev", dr?[arrayOffset] ?? Constant.MISSING);

            predictorValuesParameters.AddOutput("pres", pxi?[arrayOffset] ?? Constant.MISSING);
            predictorValuesParameters.AddOutput("lev", hi?[arrayOffset] ?? Constant.MISSING);
            predictorValuesParameters.AddOutput("spres", xis?[arrayOffset] ?? Constant.MISSING);

            predictorValuesParameters.AddOutput("deltac", cbar?[arrayOffset] ?? Constant.MISSING);
            predictorValuesParameters.AddOutput("deltabar", c?[arrayOffset] ?? Constant.MISSING);
            predictorValuesParameters.AddOutput("deltadev", d?[arrayOffset] ?? Constant.MISSING);
            predictorValuesParameters.AddOutput("deltachi", dc?[arrayOffset] ?? Constant.MISSING);

            ((DoubleVariable)outputFrame.Variables[0]).Data[outputRow] = t?[arrayOffset] ?? Constant.MISSING; // Trials
            ((DoubleVariable)outputFrame.Variables[1]).Data[outputRow] = y?[arrayOffset] ?? Constant.MISSING; // Events
            ((DoubleVariable)outputFrame.Variables[2]).Data[outputRow] = fit?[arrayOffset] ?? Constant.MISSING; // Event Probability
            ((DoubleVariable)outputFrame.Variables[3]).Data[outputRow] = dr?[arrayOffset] ?? Constant.MISSING; // Deviance Residual
            ((DoubleVariable)outputFrame.Variables[4]).Data[outputRow] = pxi?[arrayOffset] ?? Constant.MISSING; // Pearson Residual
            ((DoubleVariable)outputFrame.Variables[5]).Data[outputRow] = hi?[arrayOffset] ?? Constant.MISSING; // Leverage
            ((DoubleVariable)outputFrame.Variables[6]).Data[outputRow] = xis?[arrayOffset] ?? Constant.MISSING; // Std Pearson Residual
            ((DoubleVariable)outputFrame.Variables[7]).Data[outputRow] = cbar?[arrayOffset] ?? Constant.MISSING; // Delta Beta
            ((DoubleVariable)outputFrame.Variables[8]).Data[outputRow] = c?[arrayOffset] ?? Constant.MISSING; // Std Delta Beta
            ((DoubleVariable)outputFrame.Variables[9]).Data[outputRow] = d?[arrayOffset] ?? Constant.MISSING; // Delta Deviance
            ((DoubleVariable)outputFrame.Variables[10]).Data[outputRow] = dc?[arrayOffset] ?? Constant.MISSING; // Delta Chi-Square

            if (includePredictors)
            {
                List<ParameterBag> predictorsList2 = new();
                predictorValuesParameters.AddOutput("*pred", predictorsList2);
                for (int j = 1; j < label.Length - 1; j++)
                {
                    ParameterBag predictorsParameters = new();
                    predictorsList2.Add(predictorsParameters);
                    predictorsParameters.AddOutput("val", x[arrayOffset, j]);
                }
            }

            return predictorValuesParameters;
        }

        public static StepOutput GridLogisticRegressionFit(ParameterBag parameters)
        {
            bool doTrials = parameters["trials"].AsBoolean;
            bool doEvents = parameters["events"].AsBoolean;
            bool doEventProbability = parameters["eventProbability"].AsBoolean;
            bool doDevianceResidual = parameters["devianceResidual"].AsBoolean;
            bool doPearsonResidual = parameters["pearsonResidual"].AsBoolean;
            bool doLeverage = parameters["leverage"].AsBoolean;
            bool doStdPearsonResidual = parameters["stdPearsonResidual"].AsBoolean;
            bool doDeltaBeta = parameters["deltaBeta"].AsBoolean;
            bool doStdDeltaBeta = parameters["stdDeltaBeta"].AsBoolean;
            bool doDeltaDeviance = parameters["deltaDeviance"].AsBoolean;
            bool doDeltaChiSquare = parameters["deltaChiSquare"].AsBoolean;
            DataFrame fitsDump = parameters["fitsDump"].AsDataFrame;
            ParameterBag outputParameters = new();
            if (doTrials || doEvents || doEventProbability || doDevianceResidual || doPearsonResidual || doLeverage || doStdPearsonResidual || doDeltaBeta || doStdDeltaBeta || doDeltaDeviance || doDeltaChiSquare)
            {
                // Retrieve all the variables (it's fast!) then only include the ones we need
                DoubleVariable trialsVariable = fitsDump.Variables[0] as DoubleVariable;
                DoubleVariable eventsVariable = fitsDump.Variables[1] as DoubleVariable;
                DoubleVariable eventProbabilityVariable = fitsDump.Variables[2] as DoubleVariable;
                DoubleVariable devianceResidualVariable = fitsDump.Variables[3] as DoubleVariable;
                DoubleVariable pearsonResidualVariable = fitsDump.Variables[4] as DoubleVariable;
                DoubleVariable leverageVariable = fitsDump.Variables[5] as DoubleVariable;
                DoubleVariable stdPearsonResidualVariable = fitsDump.Variables[6] as DoubleVariable;
                DoubleVariable deltaBetaVariable = fitsDump.Variables[7] as DoubleVariable;
                DoubleVariable stdDeltaBetaVariable = fitsDump.Variables[8] as DoubleVariable;
                DoubleVariable deltaDevianceVariable = fitsDump.Variables[9] as DoubleVariable;
                DoubleVariable deltaChiSquareVariable = fitsDump.Variables[10] as DoubleVariable;

                DataFrame resultsFrame = new();
                if (doTrials)
                    resultsFrame.Variables.Add(trialsVariable);
                if (doEvents)
                    resultsFrame.Variables.Add(eventsVariable);
                if (doEventProbability)
                    resultsFrame.Variables.Add(eventProbabilityVariable);
                if (doDevianceResidual)
                    resultsFrame.Variables.Add(devianceResidualVariable);
                if (doPearsonResidual)
                    resultsFrame.Variables.Add(pearsonResidualVariable);
                if (doLeverage)
                    resultsFrame.Variables.Add(leverageVariable);
                if (doStdPearsonResidual)
                    resultsFrame.Variables.Add(stdPearsonResidualVariable);
                if (doDeltaBeta)
                    resultsFrame.Variables.Add(deltaBetaVariable);
                if (doStdDeltaBeta)
                    resultsFrame.Variables.Add(stdDeltaBetaVariable);
                if (doDeltaDeviance)
                    resultsFrame.Variables.Add(deltaDevianceVariable);
                if (doDeltaChiSquare)
                    resultsFrame.Variables.Add(deltaChiSquareVariable);
                outputParameters.AddOutput("results", resultsFrame);
            }
            return new StepOutput(outputParameters);
        }

        private static string qlbli(string[] label, int i, bool DoC)
        {
            string x = DoC
                ? i == 1
                    ? "Intercept"
                    : label[i - 1]
                : label[i];
            if (x.Length == 0)
                x = "b" + i.ToString();
            return x;
        }


        public static StepOutput PlotLogisticRegressionDiagnostics(ParameterBag parameters)
        {
            MultipleLinearRegressionContext context = (MultipleLinearRegressionContext)parameters["context"].AsObject;
            double[] t = context.T;
            double[] y = context.Y;
            double[] fv = context.FV;
            double[] dr = context.R;
            double[] hi = context.H1;
            int nx = context.N;
            double[] wt = context.WT;
            bool weight = context.WEIGHT;

            if (context.DF <= 0)
                throw new TemplateOperationCancelledException("Plots are not relevant for a saturated model.", "Logistic Regression");

            double[] yy1 = new double[nx + 1];
            double[] yy2 = new double[nx + 1];
            double[] yy3 = new double[nx + 1];
            double[] yy4 = new double[nx + 1];
            double[] xx = new double[nx + 1];
            // diagnostic plots
            const string ep = "Event Probability (pi)";
            const string lv = "Leverage (Hi)";
            const string db = "Delta Beta";
            const string dbs = "Delta Beta Std";
            const string dd = "Delta Deviance";
            const string dx = "Delta Chi-square";
            for (int i = 1; i <= nx; i++)
            {
                double PP = fv[i] / t[i];
                double ww = weight ? wt[i] : 1.0;
                // IEB July 2009
                double c;
                double cbar;
                double d;
                double dc;
                if (PP * (1.0 - PP) != 0.0)
                {
                    double xi = (y[i] - t[i] * PP) * Math.Sqrt(ww) / Math.Sqrt(t[i] * PP * (1.0 - PP));
                    c = Math.Pow(xi, 2.0) * hi[i] / Math.Pow(1.0 - hi[i], 2.0);
                    cbar = Math.Pow(xi, 2.0) * hi[i] / (1.0 - hi[i]);
                    d = Math.Pow(dr[i], 2.0) + cbar;
                    dc = cbar / hi[i];
                }
                else
                {
                    c = Constant.MISSING;
                    cbar = Constant.MISSING;
                    d = Constant.MISSING;
                    dc = Constant.MISSING;
                }
                yy1[i] = c;
                yy2[i] = cbar;
                yy3[i] = d;
                yy4[i] = dc;
                xx[i] = PP;
            }
            ParameterBag outputParameters = new();
            List<ParameterBag> chartsList = new();
            outputParameters.AddOutput("*chart", chartsList);
            //  Ensure the zeroth element isn't plotted
            xx[0] = Constant.MISSING;
            hi[0] = Constant.MISSING;

            //  delta beta vs. proportion
            chartsList.Add(new ParameterBag("chart", FilledParameterFactory.Output(ChartRendererFactory.PrepForLater(ChartType.Xy, new XyOptions(xx, yy1, ep, db, db + " vs. " + ep, false, DataMinMax.XCalc_YCalc)))));
            //  std delta beta vs. proportion
            chartsList.Add(new ParameterBag("chart", FilledParameterFactory.Output(ChartRendererFactory.PrepForLater(ChartType.Xy, new XyOptions(xx, yy2, ep, dbs, dbs + " vs. " + ep, false, DataMinMax.XCalc_YCalc)))));
            //  delta deviance vs. proportion
            chartsList.Add(new ParameterBag("chart", FilledParameterFactory.Output(ChartRendererFactory.PrepForLater(ChartType.Xy, new XyOptions(xx, yy3, ep, dd, dd + " vs. " + ep, false, DataMinMax.XCalc_YCalc)))));
            //  delta x2 vs. proportion
            chartsList.Add(new ParameterBag("chart", FilledParameterFactory.Output(ChartRendererFactory.PrepForLater(ChartType.Xyz, new XyzOptions(xx, yy4, yy1, ep, dx, dx + " (delta beta as marker size) vs. " + ep, false, DataMinMax.XCalc_YCalc)))));
            //  delta beta vs. hi
            chartsList.Add(new ParameterBag("chart", FilledParameterFactory.Output(ChartRendererFactory.PrepForLater(ChartType.Xy, new XyOptions(hi, yy1, lv, db, db + " vs. " + lv, false, DataMinMax.XCalc_YCalc)))));
            //  delta beta std vs. hi
            chartsList.Add(new ParameterBag("chart", FilledParameterFactory.Output(ChartRendererFactory.PrepForLater(ChartType.Xy, new XyOptions(hi, yy2, lv, dbs, dbs + " vs. " + lv, false, DataMinMax.XCalc_YCalc)))));
            //  delta deviance vs. hi
            chartsList.Add(new ParameterBag("chart", FilledParameterFactory.Output(ChartRendererFactory.PrepForLater(ChartType.Xy, new XyOptions(hi, yy3, lv, dd, dd + " vs. " + lv, false, DataMinMax.XCalc_YCalc)))));
            //  delta x2 vs. hi
            chartsList.Add(new ParameterBag("chart", FilledParameterFactory.Output(ChartRendererFactory.PrepForLater(ChartType.Xy, new XyOptions(hi, yy4, lv, dx, dx + " vs. " + lv, false, DataMinMax.XCalc_YCalc)))));
            return new StepOutput(outputParameters);
        }


        private struct Tri
        {
            public double D;
            public double R;
            public double S;
        }


        private class TriByDAscending : IComparer<Tri>
        {
            private static int Compare(Tri x, Tri y)
            {
                if (x.D > y.D)
                    return 1;
                if (x.D == y.D)
                    return 0;
                return -1;
            }

            // interface methods implemented by Compare
            int IComparer<Tri>.Compare(Tri x, Tri y)
            {
                return Compare(x, y);
            }
        }

        public static StepOutput RptPoissonRegressionModel(ParameterBag parameters)
        {
            MultipleLinearRegressionContext context = (MultipleLinearRegressionContext)parameters["context"].AsObject;
            double[] b = context.B;
            double[] se = context.Se;
            int p = context.P;
            string[] labels = context.Labels;
            bool DoC = context.DoC;
            double dev = context.DEV;
            int irank = context.RANK;
            int idf = context.DF;
            double tol = context.TOL;
            int m = context.M;
            int n = context.N;
            double[] fvl = context.FV;
            double[] y = context.Y;
            bool weight = context.WEIGHT;
            double[] wt = context.WT;
            double devx = context.DEVX;
            double llx = context.LLX;
            int idfx = context.DFX;
            int i; int iq = 0;
            double ll = 0; double x2 = 0;
            double r2; double r2I; double sp;
            double sX2Dev; double sX2; double sDev;
            double prob = 0;
            string q;

            if (idf > 0)
            {
                x2 = 0.0;
                for (i = 1; i <= n; i++)
                {
                    double ww = weight ? wt[i] : 1.0;
                    x2 += Math.Pow((y[i] - fvl[i]) * Math.Sqrt(ww), 2.0) / Math.Max(fvl[i], Constant.EPSNEG);
                }
                ll = x_loglik_p(weight, n, wt, y, fvl);
            }

            ParameterBag outputParameters = new();
            if (DoC)
                iq = 1;
            outputParameters.AddOutput("acc", tol);
            outputParameters.AddOutput("ll", ll);
            outputParameters.AddOutput("dev", dev);
            outputParameters.AddOutput("df", idf);
            outputParameters.AddOutput("rank", irank);
            outputParameters.AddOutput("aka", dev + 2 * p); // p parameters: the predictors, and the intercept only when one was fitted
            outputParameters.AddOutput("sch", dev + p * Math.Log(n)); // the same p parameters as the Akaike criterion; it used to count one more
            outputParameters.AddOutput("devx", devx);
            double x2Dev = devx - dev;
            if (x2Dev < 0.0)
            {
                x2Dev = Constant.MISSING;
                r2 = Constant.MISSING;
            }
            else
            {
                r2 = x2Dev / devx;
            }
            r2I = llx == Constant.MISSING
                ? Constant.MISSING
                : 1.0 - ll / llx;
            if (idf > 0 && x2 != 0.0)
            {
                sp = x2 / (n - p);
                sX2Dev = x2Dev / sp;
                sX2 = x2 / sp;
                sDev = dev / sp;
            }
            else
            {
                sp = Constant.MISSING;
                sX2Dev = Constant.MISSING;
                sX2 = Constant.MISSING;
                sDev = Constant.MISSING;
            }
            outputParameters.AddOutput("x2dev", x2Dev);
            outputParameters.AddOutput("x2df", idfx - idf);
            if (idf > 0)
            {
                outputParameters.AddOutput("x2p", PDF.chivalp(x2Dev, idfx - idf));
            }
            else
            {
                outputParameters.AddOutput("x2p", "* saturated model: goodness of fit not valid");
                x2Dev = Constant.MISSING;
                x2 = Constant.MISSING;
                dev = Constant.MISSING;
            }
            outputParameters.AddOutput("r2", r2);
            outputParameters.AddOutput("r2i", r2I);
            outputParameters.AddOutput("x2_pearson", x2);
            outputParameters.AddOutput("idf", idf);
            outputParameters.AddOutput("p_pearson", PDF.chivalp(x2, idf));
            outputParameters.AddOutput("dev_gf", dev);
            outputParameters.AddOutput("p_dev", PDF.chivalp(dev, idf));
            // scaled for overdispersion
            outputParameters.AddOutput("sp", sp);
            outputParameters.AddOutput("x2dev_scaled", sX2Dev);
            outputParameters.AddOutput("x2p_scaled", PDF.chivalp(sX2Dev, idfx - idf));
            outputParameters.AddOutput("x2_scaled", sX2);
            outputParameters.AddOutput("p_p_scaled", PDF.chivalp(sX2, idf));
            outputParameters.AddOutput("dev_scaled", sDev);
            outputParameters.AddOutput("p_dev_scaled", PDF.chivalp(sDev, idf));

            IList<ParameterBag> unscaledList = new List<ParameterBag>();
            outputParameters.AddOutput("*unscaled", unscaledList);
            for (i = 1; i <= p; i++)
            {
                ParameterBag unscaledParameters = new();
                unscaledList.Add(unscaledParameters);
                q = i == 1 && DoC
                    ? "Constant"
                    : labels[i - iq];
                unscaledParameters.AddOutput("par", q);
                unscaledParameters.AddOutput("coef", b[i]);
                unscaledParameters.AddOutput("err", se[i]);
            }

            IList<ParameterBag> scaledList = new List<ParameterBag>();
            outputParameters.AddOutput("*scaled", scaledList);
            for (i = 1; i <= p; i++)
            {
                ParameterBag scaledParameters = new();
                scaledList.Add(scaledParameters);
                if (i == 1 && DoC)
                {
                    q = "Constant";
                }
                else { q = labels[i - iq]; }
                double sse = sp == Constant.MISSING
                    ? Constant.MISSING
                    : Math.Sqrt(se[i] * se[i] * sp);
                double z;
                if (sse == 0.0 || sse == Constant.MISSING)
                {
                    z = Constant.MISSING;
                }
                else
                {
                    z = b[i] / sse;
                    prob = 2.0 * (1.0 - PDF.alnorm(Math.Abs(b[i]) / sse));
                }
                scaledParameters.AddOutput("par", q);
                scaledParameters.AddOutput("err", sse);
                scaledParameters.AddOutput("z", z);
                scaledParameters.AddOutput("p", prob);
            }
            return new StepOutput(outputParameters);
        }

        public static StepOutput RptLogisticRegressionModel(ParameterBag parameters)
        {
            MultipleLinearRegressionContext context = (MultipleLinearRegressionContext)parameters["context"].AsObject;
            double[] b = context.B;
            double[] se = context.Se;
            int p = context.P;
            string[] labels = context.Labels;
            bool DoC = context.DoC;
            double dev = context.DEV;
            int irank = context.RANK;
            int idf = context.DF;
            double tol = context.TOL;
            int m = context.M;
            int n = context.N;
            double[] fvl = context.FV;
            double[] t = context.T;
            double[] y = context.Y;
            bool weight = context.WEIGHT;
            double[] wt = context.WT;
            double devx = context.DEVX;
            double llx = context.LLX;
            int idfx = context.DFX;

            int hldf = 0; int i;
            int iq = 0;
            double x2 = 0; double ll = 0;
            double chat = 0;
            double r2; double r2I;
            if (idf > 0)
            {
                x2 = 0.0;
                int ntot = 0;
                double pp;
                for (i = 1; i <= n; i++)
                {
                    pp = fvl[i] / t[i];
                    double ww = weight ? wt[i] : 1;
                    if (pp != 0.0)
                        x2 += Math.Pow((y[i] - t[i] * pp) * Math.Sqrt(ww), 2.0) / (t[i] * pp * (1.0 - pp));
                    ntot += Convert.ToInt32(t[i]);
                }
                ll = x_loglik_l(weight, n, wt, y, t, fvl);
                double[] obs = new double[10 + 1];
                double[] tot = new double[10 + 1];
                double[] mpi = new double[10 + 1];
                Tri[] z = new Tri[n + 1];
                for (i = 1; i <= n; i++)
                {
                    pp = fvl[i] / t[i];
                    z[i].D = pp;
                    z[i].R = y[i];
                    z[i].S = t[i];
                }
                Array.Sort(z, 1, n, new TriByDAscending());
                int ctr = 1;
                double ndiv = Convert.ToDouble(ntot) / 10.0;
                double ncut = Math.Floor(ndiv);
                double ncum = 0;
                for (i = 1; i <= n; i++)
                {
                    if (ncum >= ncut & ctr <= 10)
                    {
                        ctr++;
                        ncut = Math.Floor(Math.Max(ncum + ndiv, ctr * ndiv));
                    }
                    tot[ctr] = tot[ctr] + z[i].S;
                    ncum += z[i].S;
                    obs[ctr] = obs[ctr] + z[i].R;
                    mpi[ctr] = mpi[ctr] + z[i].D * z[i].S;
                    if (ncum >= ntot)
                        break;
                }
                hldf = ctr - 2;
                chat = 0.0;
                for (i = 1; i <= ctr; i++)
                {
                    if (tot[i] > 0.0 & mpi[i] > 0.0)
                    {
                        double numer = (obs[i] - mpi[i]) * (obs[i] - mpi[i]);
                        mpi[i] = mpi[i] / tot[i];
                        chat += numer / (tot[i] * mpi[i] * (1.0 - mpi[i]));
                    }
                }
            }
            if (DoC)
                iq = 1;
            ParameterBag outputParameters = new();
            outputParameters.AddOutput("acc", tol);
            outputParameters.AddOutput("ll", ll);
            outputParameters.AddOutput("dev", dev);
            outputParameters.AddOutput("idf", idf);
            outputParameters.AddOutput("rank", irank);
            outputParameters.AddOutput("aka", dev + 2 * p); // p parameters: the predictors, and the intercept only when one was fitted
            outputParameters.AddOutput("sch", dev + p * Math.Log(n)); // the same p parameters as the Akaike criterion; it used to count one more
            outputParameters.AddOutput("devx", devx);
            double x2Dev = devx - dev;
            if (devx == Constant.MISSING)
            {
                x2Dev = Constant.MISSING;
                r2 = Constant.MISSING;
            }
            else
            {
                r2 = x2Dev / devx;
            }
            r2I = llx == Constant.MISSING
                ? Constant.MISSING 
                : 1.0 - ll / llx;
            outputParameters.AddOutput("x2dev", x2Dev);
            outputParameters.AddOutput("x2df", idfx - idf);
            outputParameters.AddOutput("x2p",
                idfx > 0
                    ? PDF.chivalp(x2Dev, idfx - idf)
                    : Constant.MISSING);
            outputParameters.AddOutput("r2", r2);
            outputParameters.AddOutput("r2i", r2I);
            outputParameters.AddOutput("x2", x2);
            if (idf <= 0)
            {
                x2 = Constant.MISSING;
                dev = Constant.MISSING;
                chat = Constant.MISSING;
                outputParameters.AddOutput("p", "* saturated model: can't assess goodness of fit");
            }
            else
            {
                outputParameters.AddOutput("p", PDF.chivalp(x2, idf));
            }
            outputParameters.AddOutput("dev_good", dev);
            outputParameters.AddOutput("df_good", idf);
            outputParameters.AddOutput("p_good", PDF.chivalp(dev, idf));
            outputParameters.AddOutput("hl", chat);
            outputParameters.AddOutput("df_hl", hldf);
            double hlp = hldf < 1
                ? Constant.MISSING
                : PDF.chivalp(chat, hldf);
            outputParameters.AddOutput("p_hl", hlp);
            List<ParameterBag> parametersList = new();
            outputParameters.AddOutput("*parameters", parametersList);
            for (i = 1; i <= p; i++)
            {
                double prob;
                if (se[i] == 0)
                    prob = Constant.MISSING;
                else
                    prob = 2.0 * (1.0 - PDF.alnorm(Math.Abs(b[i] / se[i])));
                ParameterBag parametersParameters = new();
                parametersList.Add(parametersParameters);
                string q = i == 1 && DoC
                    ? "(intercept)"
                    : labels[i - iq];
                parametersParameters.AddOutput("par", q);
                parametersParameters.AddOutput("coef", b[i]);
                parametersParameters.AddOutput("err", se[i]);
                if (se[i] == 0.0)
                {
                    double z = Constant.MISSING;
                    parametersParameters.AddOutput("z", z);
                    parametersParameters.AddOutput("p_var", "* error: drop this variable *");
                }
                else
                {
                    double z = b[i] / se[i];
                    parametersParameters.AddOutput("z", z);
                    parametersParameters.AddOutput("p_var", prob);
                }
            }
            return new StepOutput(outputParameters);
        }


        public static StepOutput RptPoissonRegressionIrr(ParameterBag parameters)
        {
            MultipleLinearRegressionContext context = (MultipleLinearRegressionContext)parameters["context"].AsObject;
            double[] b = context.B;
            double[] se = context.Se;
            int p = context.P;
            string[] labels = context.Labels;
            bool DoC = context.DoC;
            double gamma = parameters["gamma"].AsDouble;
            MathDbl.civ(0, out double cit, gamma, out double P0);
            ParameterBag outputParameters = new();

            //  Whole study
            IList<ParameterBag> popList = new List<ParameterBag>();
            outputParameters.AddOutput("*pop", popList);
            ParameterBag popParameters = new();
            popList.Add(popParameters);
            popParameters.AddOutput("pop", "whole study (baseline relative risk)");
            popParameters.AddOutput("pc", 100 * (1.0 - P0));
            IList<ParameterBag> parList = new List<ParameterBag>();
            popParameters.AddOutput("*par", parList);
            int iq = DoC ? 1 : 0;
            for (int i = 1; i <= p; i++)
            {
                if (i != 1 || !DoC)
                {
                    ParameterBag parParameters = new();
                    parList.Add(parParameters);
                    parParameters.AddOutput("par", labels[i - iq]);
                    parParameters.AddOutput("est", b[i]);
                    double rr = Formatting.SafeExp(b[i]);
                    double lci;
                    double uci;
                    if (rr != Constant.MISSING)
                    {
                        lci = Formatting.SafeExp(b[i] - se[i] * cit);
                        uci = Formatting.SafeExp(b[i] + se[i] * cit);
                    }
                    else
                    {
                        lci = Constant.MISSING;
                        uci = Constant.MISSING;
                    }
                    parParameters.AddOutput("irr", rr);
                    parParameters.AddOutput("lci", lci);
                    parParameters.AddOutput("uci", uci);
                }
            }

            // relative to dichotomous covariates
            if (parameters["hasDichotomousCovariates"].AsBoolean)
            {
                double[] nsel = ((DoubleVariable)parameters["dichotomousCovariates"].AsDataFrame.Variables[1]).Data;
                bool[] cov = (bool[])parameters["cov"].AsObject;
                int selectedIndex = 0;
                for (int i = 0; i <= cov.GetUpperBound(0); i++)
                {
                    if (cov[i])
                    {
                        selectedIndex = i;
                        break;
                    }
                }
                int l = (int)nsel[selectedIndex];
                for (int j = 2; j >= 1; j--)
                {
                    double bx = Formatting.SafeExp(b[l]);
                    if (bx != Constant.MISSING)
                    {
                        popParameters = new ParameterBag();
                        popList.Add(popParameters);
                        popParameters.AddOutput("pop", labels[l - iq] + " = " + (j - 1).ToString());
                        popParameters.AddOutput("pc", 100 * (1.0 - P0));
                        parList = new List<ParameterBag>();
                        popParameters.AddOutput("*par", parList);
                        if (j == 1)
                            bx = 1.0 / bx;

                        for (int i = 1; i <= p; i++)
                        {
                            if ((i != 1 || !DoC) && i != l)
                            {
                                ParameterBag parParameters = new();
                                parList.Add(parParameters);
                                parParameters.AddOutput("par", labels[i - iq]);
                                parParameters.AddOutput("est", b[i]);
                                double rr = Formatting.SafeExp(b[i]) * bx;
                                double lci;
                                double uci;
                                if (rr != Constant.MISSING)
                                {
                                    lci = Formatting.SafeExp(b[i] * bx - se[i] * cit * bx);
                                    uci = Formatting.SafeExp(b[i] * bx + se[i] * cit * bx);
                                }
                                else
                                {
                                    lci = Constant.MISSING;
                                    uci = Constant.MISSING;
                                }
                                parParameters.AddOutput("irr", rr);
                                parParameters.AddOutput("lci", lci);
                                parParameters.AddOutput("uci", uci);
                            }
                        }
                    }
                }
            }
            return new StepOutput(outputParameters);
        }

        public static StepOutput OpPoissonRegressionIrrMakeDichotomousCovariates(ParameterBag parameters)
        {
            MultipleLinearRegressionContext context = (MultipleLinearRegressionContext)parameters["context"].AsObject;
            double[,] x = context.X;
            int p = context.P;
            int nx = context.N;

            ParameterBag outputParameters = new();

            int iq = context.DoC ? 1 : 0;

            // Locate dichotomous covariates so that the user can be asked which one they want
            List<double> nsel = new();
            List<string> okLabels = new();
            for (int l = 1; l <= p; l++)
            {
                if (l > 1 || !context.DoC)
                {
                    bool ok = true;
                    int k = context.DoC ? l - 1 : l;
                    for (int j = 1; j <= nx; j++)
                    {
                        if (x[j, k] != 0.0 && x[j, k] != 1.0)
                        {
                            ok = false;
                            break;
                        }
                    }
                    if (ok)
                    {
                        okLabels.Add(context.Labels[l - iq]);
                        nsel.Add(l);
                    }
                }
            }

            // We need to ask if there's at least one dichotomous covariate and at least two coefficients other than the intercept
            outputParameters.AddOutput("hasDichotomousCovariates", okLabels.Count >= 1 && p - iq > 1);
            StringVariable names = new(okLabels.ToArray(), "labels");
            DoubleVariable offsets = new(nsel.ToArray(), "offsets");
            DataFrame dcFrame = new();
            dcFrame.Variables.Add(names);
            dcFrame.Variables.Add(offsets);
            outputParameters.AddOutput("dichotomousCovariates", dcFrame);
            return new StepOutput(outputParameters);
        }

        public static StepOutput RptLogisticRegressionModelSelection(IPreferencesAndProgressBar host, ParameterBag parameters)
        {
            MultipleLinearRegressionContext context = (MultipleLinearRegressionContext)parameters["context"].AsObject;
            bool mean = context.DoC;
            int n = context.N;
            string[] labels = context.Labels;
            double[] y = context.Y;
            double[] t = context.T;
            double[] wt = context.WT;
            double[,] x = context.X;
            int p = context.P;
            int m = context.M;
            double tol = context.TOL;
            //intercept deviance and degrees of freedom can be used from original fit
            int dfx = context.DFX;
            double devx = context.DEVX;

            ParameterBag outputParameters = new();
            List<ParameterBag> parametersList = new();
            outputParameters.AddOutput("*parameters", parametersList);

            //first show the full model
            bool[] selectX = new bool[p + 1];
            for (int j = 1; j <= p; j++)
                selectX[j] = true;

            double[] b = new double[p + 1];
            double[] se = new double[n + 1];
            double[] cov = new double[(int)Math.Floor((double)p * (p + 1) / 2) + 1];
            double[] fv = new double[n + 1];
            double[] dr = new double[n + 1];
            double[] h = new double[n + 1];
            double[] offst = new double[n + 1];
            int df = 0;
            int rank = 0;
            bool iweight = true;
            var dropped = string.Empty;
            var errMsg = string.Empty;
            using (IProgressBar progress = host.StartProgress("Checking significance with all predictors", false))
            {
                Regress1.X_Logistic_Regression(mean, false, ref iweight, n, x, m, selectX, p, y, t, wt, out double dev, ref df, b, ref rank, se, cov, tol, 50, fv, dr, h, offst, out int fault, ref dropped, ref errMsg);
                LR_ModelSelectionOutput(host, parametersList, fault, labels, b, se, mean, dev, devx, p, m, df, dfx, errMsg, selectX);
            }

            // Now add predictors one at time: select the predictor that gives max Akaike information to the model on each addition, building up to the full model again
            using (IProgressBar progress = host.StartProgress("Selecting most informative predictors. Small models are tested first. Cancel will give interim results.", true))
            {
                bool[] previousSelection = new bool[p + 1]; // All blank initially; no previous selections.
                int parms = mean ? 2 : 1;
                double estimatedRegressionsToRun = m * (m + 1) / 2.0 + m;
                int regressionsRun = 0;
                while (true)
                {
                    selectX = new bool[p + 1];
                    Array.Copy(previousSelection, selectX, p + 1);
                    int bestPredictorIndexSoFar = 0;
                    double minAkaikeInformationSoFar = double.MaxValue;
                    bool abandon = false;
                    double dev;
                    int fault;
                    for (int candidate = 1; candidate <= m; candidate++)
                    {
                        // If we've already processed this one, don't do so again
                        if (previousSelection[candidate])
                            continue;

                        // Check whether it's better than our best so far this run; if so, note the fact.
                        // Lower AIC values are better - the value represents the information *lost* if this model is chosen.
                        selectX[candidate] = true;
                        Regress1.X_Logistic_Regression(mean, false, ref iweight, n, x, m, selectX, parms, y, t, wt, out dev, ref df, b, ref rank, se, cov, tol, 50, fv, dr, h, offst, out fault, ref dropped, ref errMsg);
                        if (progress.Update(++regressionsRun / estimatedRegressionsToRun))
                        {
                            abandon = true;
                            break;
                        }
                        double aic = dev + 2 * (1 + m);
                        if (aic < minAkaikeInformationSoFar)
                        {
                            bestPredictorIndexSoFar = candidate;
                            minAkaikeInformationSoFar = aic;
                        }
                        selectX[candidate] = false;
                    }

                    // Have we added all predictors (or has the user given up)?
                    if (bestPredictorIndexSoFar <= 0 || abandon)
                        break;

                    // Re-do the regression with that predictor selected along with any others we may have from previous iterations
                    selectX[bestPredictorIndexSoFar] = true;
                    Regress1.X_Logistic_Regression(mean, false, ref iweight, n, x, m, selectX, parms, y, t, wt, out dev, ref df, b, ref rank, se, cov, tol, 50, fv, dr, h, offst, out fault, ref dropped, ref errMsg);
                    LR_ModelSelectionOutput(host, parametersList, fault, labels, b, se, mean, dev, devx, p, m, df, dfx, errMsg, selectX);
                    if (progress.Update(++regressionsRun / estimatedRegressionsToRun))
                        break;

                    // Go round again, remembering the predictor we've chosen this time
                    previousSelection = selectX;
                    parms++;
                }
            }

            return new StepOutput(outputParameters);
        }

        private static void LR_ModelSelectionOutput(IFormatting host, List<ParameterBag> parametersList, int fault, string[] label, double[] b, double[] se, bool mean, double dev, double devx, int p, int m, int df, int dfx, string err_msg, bool[] selectX)
        {
            ParameterBag parametersParameters = new();
            parametersList.Add(parametersParameters);
            if (fault != 0)
            {
                parametersParameters.AddOutput("model", err_msg);
                return;
            }

            string tx = "logit ";
            tx += label[0].Length > 0 ? label[0] : "Y";
            tx += " = ";
            int significantCoefficients = 0;
            int totalCoefficients = 0;
            for (int j = 1; j <= p; j++)
            {
                bool isIntercept = mean && j == 1;
                // Only process this part of the model if it is selected
                if (!isIntercept)
                {
                    int selectXIndex = mean ? j - 1 : j;
                    if (!selectX[selectXIndex])
                        continue;
                }

                if (!isIntercept && b[j] >= 0.0)
                    tx += "+";
                tx += host.RoundU(b[j]);
                tx += SignificanceString(b, se, out bool isSignificant, j);
                if (isSignificant)
                    significantCoefficients++;
                totalCoefficients++;
                string q = mean ? (j > 1 ? label[j - 1] : " ") : label[j];
                if (q.Length == 0)
                    tx += " X" + j.ToString();
                else
                    tx += " " + q + " ";
            }

            parametersParameters.AddOutput("model", tx);
            parametersParameters.AddOutput("aic", dev + 2 * totalCoefficients); // the parameters of THIS model; the full model's count made every sub-model look worse than it is
            double x2dev = devx - dev;
            double r2;
            if (devx == Constant.MISSING)
            {
                x2dev = Constant.MISSING;
                r2 = Constant.MISSING;
            }
            else
            {
                r2 = x2dev / devx;
            }
            parametersParameters.AddOutput("r2", r2);
            parametersParameters.AddOutput("scoef", significantCoefficients);
            parametersParameters.AddOutput("ncoef", totalCoefficients);
            parametersParameters.AddOutput("x2dev", x2dev);
            parametersParameters.AddOutput("p_dev",
                dfx > 0
                    ? PDF.chivalp(x2dev, dfx - df)
                    : Constant.MISSING);
        }

        private static string SignificanceString(double[] b, double[] se, out bool isSignificant, int j)
        {
            isSignificant = false;
            if (se[j] == 0.0)
                return "~N/A";
            double prob = 2.0 * (1.0 - PDF.alnorm(Math.Abs(b[j] / se[j])));
            if (prob < 0.05)
            {
                isSignificant = true;
                return string.Empty;
            }
            if (prob >= 0.05 && prob < 0.2)
                return "~?NS";
            return "~NS";
        }


        public static StepOutput RptLogisticRegressionClassification(ParameterBag parameters)
        {
            MultipleLinearRegressionContext context = (MultipleLinearRegressionContext)parameters["context"].AsObject;
            int n = context.N;
            double[] fvl = context.FV;
            double[] t = context.T;
            double[] y = context.Y;

            ParameterBag outputParameters = new();
            double co = parameters["cutoff"].AsDouble;
            if (co <= 0.0 || co >= 1.0)
                co = 0.5;

            double gamma = parameters["gamma"].AsDouble;
            MathDbl.civ(0, out double zc, gamma, out double zl);
            x_lclass(t, fvl, y, n, out int tp, out int fp, out int fn, out int tn, co);
            outputParameters.AddOutput("tp", tp);
            outputParameters.AddOutput("fp", fp);
            outputParameters.AddOutput("totc", tp + fp);
            outputParameters.AddOutput("fn", fn);
            outputParameters.AddOutput("tn", tn);
            outputParameters.AddOutput("totnoc", tn + fn);
            outputParameters.AddOutput("tote", tp + fn);
            outputParameters.AddOutput("totnoe", fp + tn);
            outputParameters.AddOutput("co", co);
            double a = tp;
            double b = fp;
            double c = fn;
            double d = tn;

            double sns = tp + fn > 0
                ? 100.0 * a / (a + c)
                : Constant.MISSING;
            outputParameters.AddOutput("sens", sns);
            double spe = tn + fp > 0
                ? 100.0 * d / (b + d)
                : Constant.MISSING;
            outputParameters.AddOutput("spec", spe);
            double ppv = tp + fp > 0
                ? 100.0 * a / (a + b)
                : Constant.MISSING;
            outputParameters.AddOutput("positive", ppv);
            double nnv = tn + fn > 0
                ? 100.0 * (1.0 - d / (d + c))
                : Constant.MISSING;
            outputParameters.AddOutput("npv", 100.0 - nnv);
            outputParameters.AddOutput("negative", nnv);
            outputParameters.AddOutput("cc", 100.0 * (a + d) / (a + b + c + d));
            outputParameters.AddOutput("pc", 100.0 * (1.0 - zl));
            double lrpos; double thetal; double thetau;
            if (tp + fn > 0 && fp + tn > 0 && fp > 0 && tp > 0)
            {
                lrpos = a / (a + c) / (b / (b + d));
                x_lrci(b, a, b + d, a + c, zc, out thetal, out thetau);
            }
            else
            {
                lrpos = Constant.MISSING;
                thetal = Constant.MISSING;
                thetau = Constant.MISSING;
            }
            outputParameters.AddOutput("lr_positive", lrpos);
            outputParameters.AddOutput("from_positive", thetal);
            outputParameters.AddOutput("to_positive", thetau);
            double lrneg;
            if (tp + fn > 0 && fp + tn > 0 && tn > 0 && fn > 0)
            {
                lrneg = c / (a + c) / (d / (d + b));
                x_lrci(d, c, b + d, a + c, zc, out thetal, out thetau);
            }
            else
            {
                lrneg = Constant.MISSING;
                thetal = Constant.MISSING;
                thetau = Constant.MISSING;
            }
            outputParameters.AddOutput("lr_negative", lrneg);
            outputParameters.AddOutput("from_negative", thetal);
            outputParameters.AddOutput("to_negative", thetau);
            double xMax = 0.0;
            co = 0.0;
            double cmax = co;
            const int stps = 100;
            double[] ry = new double[stps + 1];
            double[] rx = new double[stps + 1];
            for (int i = 1; i <= stps; i++)
            {
                co += 0.01;
                x_lclass(t, fvl, y, n, out tp, out fp, out fn, out tn, co);
                if (tp + fn > 0 && tn + fp > 0)
                {
                    double sens = tp / (double)(tp + fn);
                    double sec = tn / (double)(tn + fp);
                    ry[i] = sens;
                    rx[i] = 1.0 - sec;
                    if (sens + sec > xMax)
                    {
                        xMax = sens + sec;
                        cmax = co;
                    }
                }
            }
            double auc = MathDbl.trapezoid_xy_roc(rx, ry, 1, stps);
            outputParameters.AddOutput("cmax", cmax);
            outputParameters.AddOutput("area", auc);
            // Don't plot the zeroth element
            rx[0] = Constant.MISSING;
            ry[0] = Constant.MISSING;
            outputParameters.AddOutput("chart", ChartRendererFactory.PrepForLater(ChartType.Xy0To1, new XyOptions(rx, ry, "1-specificity", "sensitivity", string.Empty, false, DataMinMax.XPreset_YPreset)));
            return new StepOutput(outputParameters);
        }

        public static StepOutput RptLogisticRegressionBootstrap(IProgressBarHost host, ParameterBag parameters)
        {
            MultipleLinearRegressionContext context = (MultipleLinearRegressionContext)parameters["context"].AsObject;
            double[] se;
            double[] b = context.B;
            double[] t = context.T;
            double[,] x = context.X;
            double[] y = context.Y;
            double[] fv;
            double[] dr;
            double[] h;
            int n = context.N;
            bool mean = context.DoC;
            string[] labels = context.Labels;
            int p = context.P;
            double[] cov;
            double[] wt = context.WT;
            bool useWeights = context.WEIGHT;
            int rank = context.RANK;
            int df = context.DF;
            double tol = context.TOL;
            int predictors = context.M;
            double dev;

            int j; int i;
            int iq = 0;
            double[] offst;
            string dropped;
            string errMsg;

            double gamma = parameters["gamma"].AsDouble;
            MathDbl.civ(0, out double cit, gamma, out double p0);
            bool[] isx = new bool[p + 1];
            double[] ob = new double[p + 1];
            for (j = 1; j <= p; j++)
            {
                isx[j] = true;
                ob[j] = Formatting.SafeExp(b[j]);
            }
            int gtot = 0;
            for (j = 1; j <= n; j++)
            {
                gtot += Convert.ToInt32(t[j]);
            }
            int boots = parameters["boots"].AsInt32;
            using IProgressBar progress = host.StartProgress("Bootstrapping " + boots.ToString() + " iterations", true);
            double[,] qo = new double[p + 1, boots + 1];
            double[] theta = new double[p + 1];
            double[] ql = new double[p + 1];
            double[] qu = new double[p + 1];
            int booted = 0;
            MersenneTwister rng = new();
            for (i = 1; i <= boots; i++)
            {
                if (progress.Update(i / (double)boots))
                    break;

                double[] rndy = new double[n + 1];
                double[] rndt = new double[n + 1];
                double[] rndwt = new double[n + 1];
                for (j = 1; j <= gtot; j++)
                {
                    int pick = Math.Min(gtot, (int)Math.Floor(gtot * rng.NextDouble()) + 1);
                    int pivot = 0;
                    int k;
                    for (k = 1; k <= n; k++)
                    {
                        pivot += Convert.ToInt32(t[k]);
                        if (pick <= pivot)
                        {
                            rndt[k]++;
                            if (rng.NextDouble() <= Convert.ToInt64(y[k]) / (double)Convert.ToInt64(t[k]))
                                rndy[k]++;
                            break;
                        }
                    }
                }
                for (j = 1; j <= n; j++)
                {
                    if (rndy[j] == 0.0)
                        rndy[j] = Constant.EPSNEG;
                    if (rndy[j] == rndt[j])
                        rndy[j] = rndy[j] - Constant.EPSNEG;
                    if (rndt[j] == 0.0)
                        rndwt[j] = 0.0;
                    else
                        rndwt[j] = wt[j];
                }
                b = new double[p + 1];
                se = new double[n + 1];
                cov = new double[(int)Math.Floor((double)p * (p + 1) / 2) + 1];
                fv = new double[n + 1];
                dr = new double[n + 1];
                h = new double[n + 1];
                offst = new double[n + 1];
                bool iweight = true;
                dropped = string.Empty;
                errMsg = string.Empty;
                Regress1.X_Logistic_Regression(mean, false, ref iweight, n, x, predictors, isx, p, rndy, rndt, rndwt, out dev, ref df, b, ref rank, se, cov, tol, 50, fv, dr, h, offst, out int fault, ref dropped, ref errMsg);
                if (fault == 0)
                {
                    booted++;
                    for (j = 1; j <= p; j++)
                    {
                        qo[j, booted] = Formatting.SafeExp(b[j]);
                        if (qo[j, booted] < 1000.0 * ob[j])
                            theta[j] += qo[j, booted];
                    }
                }
            }

            // In the case of the bootstrap not running to its full iterations because the user cancelled, present results as far as it's got (#669)
            boots = i - 1;

            ParameterBag outputParameters = new();

            for (j = 1; j <= p; j++)
                theta[j] /= booted;
            for (j = 1; j <= p; j++)
            {
                double[] qq = new double[booted + 1];
                int ctr = 0;
                for (i = 1; i <= booted; i++)
                {
                    qq[i] = qo[j, i];
                    if (qq[i] <= ob[j])
                        ctr += 1;
                }
                Array.Sort(qq, 1, booted);
                double z0 = ctr / (double)booted;
                z0 = PDF.gauinv(z0);
                double p1 = PDF.alnorm(2.0 * z0 - cit);
                double p2 = PDF.alnorm(2.0 * z0 + cit);
                ql[j] = qq[Convert.ToInt32((booted - 1) * p1) + 1];
                qu[j] = qq[Convert.ToInt32((booted - 1) * p2) + 1];
            }
            outputParameters.AddOutput("boots", booted);
            if (boots != booted)
                outputParameters.AddOutput("warn", ", warning: " + (boots - booted).ToString() + " re-samples were dropped because they caused error in the regression");
            outputParameters.AddOutput("pc", 100 * (1.0 - p0));
            if (mean)
                iq = 1;
            List<ParameterBag> parametersList = new();
            outputParameters.AddOutput("*parameters", parametersList);
            for (i = 1; i <= p; i++)
            {
                ParameterBag parametersParameters = new();
                parametersList.Add(parametersParameters);
                string q = i == 1 && mean
                    ? "Constant"
                    : labels[i - iq];
                parametersParameters.AddOutput("par", q);
                parametersParameters.AddOutput("obs", ob[i]);
                if (i > 1 || !mean)
                {
                    parametersParameters.AddOutput("bias", theta[i] - ob[i]);
                    parametersParameters.AddOutput("lci", ql[i]);
                    parametersParameters.AddOutput("uci", qu[i]);
                }
            }
            //  recalculate full model
            b = new double[p + 1];
            se = new double[n + 1];
            cov = new double[(int)Math.Floor((double)p * (p + 1) / 2) + 1];
            fv = new double[n + 1];
            dr = new double[n + 1];
            h = new double[n + 1];
            offst = new double[n + 1];
            dropped = string.Empty;
            errMsg = string.Empty;
            Regress1.X_Logistic_Regression(mean, false, ref useWeights, n, x, predictors, isx, p, y, t, wt, out dev, ref df, b, ref rank, se, cov, tol, 50, fv, dr, h, offst, out int _, ref dropped, ref errMsg);
            return new StepOutput(outputParameters);
        }

        public static StepOutput RptLogisticRegressionPrediction(ParameterBag parameters)
        {
            MultipleLinearRegressionContext context = (MultipleLinearRegressionContext)parameters["context"].AsObject;
            double[] b = context.B;
            int p = context.P;
            string[] labels = context.Labels;
            double[] covariance = context.Covariance;
            bool DoC = context.DoC;

            int iq;

            ParameterBag outputParameters = new();
            double[] newx = new double[p + 1];
            bool lsqmean = true;
            if (DoC)
            {
                iq = 1;
                newx[1] = 1.0;
            }
            else
            {
                iq = 0;
            }
            DataFrame candidatePredictors = parameters["candidatePredictors"].AsDataFrame;
            //  Predictors are guaranteed to be in the same order as the labels
            StringVariable valueVariable = (StringVariable)candidatePredictors.Variables[1];
            DoubleVariable oldValueVariable = (DoubleVariable)candidatePredictors.Variables[2];
            // A blank or non-numeric predictor arrives as MISSING (a huge negative number). The prediction is then missing too:
            // PFromLogit would otherwise turn the resulting logit into a confident 0 or 1.
            bool missingPredictor = false;
            // The ith predictor sits at i + iq: after the constant when there is one, first when there is not. It was written
            // to i + 1 whatever the model, so a model without an intercept ran off the end of newx and the prediction stopped
            // with an error.
            for (int i = 1; i <= p - iq; i++)
            {
                newx[i + iq] = Parsing.Cdbl_Txt(valueVariable.Data[i - 1]);
                if (newx[i + iq] == Constant.MISSING || double.IsNaN(newx[i + iq]) || double.IsInfinity(newx[i + iq]))
                    missingPredictor = true;
                if (newx[i + iq] != oldValueVariable.Data[i - 1])
                    lsqmean = false;
            }
            double newy = 0.0;
            for (int i = 1; i <= p; i++)
                newy += newx[i] * b[i];
            double gamma = parameters["gamma"].AsDouble;
            MathDbl.civ(0, out double cit, gamma, out double P0);
            List<ParameterBag> predictorsList = new();
            outputParameters.AddOutput("*predictors", predictorsList);
            for (int i = 1; i <= p - iq; i++)
            {
                ParameterBag predictorsParameters = new();
                predictorsList.Add(predictorsParameters);
                predictorsParameters.AddOutput("xtitle", labels[i]);
                predictorsParameters.AddOutput("x", newx[i + iq]);
            }
            //  sd of Y from covariance matrix as sqr(xVx')
            double sey = 0.0;
            for (int j = 1; j <= p; j++)
            {
                double s = 0.0;
                for (int i = 1; i <= p; i++)
                {
                    // unpack the upper triangular packed form of the covariance matrix
                    int ii;
                    int jj;
                    if (j >= i)
                    {
                        jj = j;
                        ii = i;
                    }
                    else
                    {
                        jj = i;
                        ii = j;
                    }
                    s += covariance[(int)Math.Floor((double)jj * (jj - 1) / 2 + ii)] * newx[i];
                }
                sey += s * newx[j];
            }
            double lcl, ucl;
            if (sey >= 0.0)
            {
                sey = Math.Sqrt(sey);
                double cl = cit * sey;
                lcl = newy - cl;
                ucl = newy + cl;
                //  transform to outcome probability scale
                newy = PFromLogit(newy);
                lcl = PFromLogit(lcl);
                ucl = PFromLogit(ucl);
            }
            else
            {
                newy = PFromLogit(newy);
                lcl = Constant.MISSING;
                ucl = Constant.MISSING;
            }
            if (missingPredictor)
            {
                newy = Constant.MISSING;
                lcl = Constant.MISSING;
                ucl = Constant.MISSING;
            }
            outputParameters.AddOutput("y", newy);
            if (lsqmean)
                outputParameters.AddOutput("msg", "  (regression mean)");
            outputParameters.AddOutput("pc", 100 * (1.0 - P0));
            outputParameters.AddOutput("from", lcl);
            outputParameters.AddOutput("to", ucl);
            return new StepOutput(outputParameters);
        }

        private static void x_lrci(double fp, double tp, double column2total, double column1total, double zc, out double thetal, out double thetau)
        {
            double lastz = 0;

            double x0 = fp;
            double x1 = tp;
            double n0 = column2total;
            if (n0 == x0)
                n0 += 0.5;
            double n1 = column1total;
            if (n1 == x1)
                n1 += 0.5;
            double uhat = 1.0 / (x1 + 0.5) + 1.0 / (x0 + 0.5) - 1.0 / (n0 + 0.5) - 1.0 / (n1 + 0.5);
            double n = n0 + n1;
            double logthetahat = Math.Log((x1 + 0.5) / (n1 + 0.5)) - Math.Log((x0 + 0.5) / (n0 + 0.5));
            thetau = Math.Exp(logthetahat) * Math.Exp(zc * Math.Sqrt(uhat));
            thetal = Math.Exp(logthetahat) * Math.Exp(-zc * Math.Sqrt(uhat));
            for (int i = 1; i <= 2; i++)
            {
                double za2 = zc;
                double temptheta1 = i == 1 ? thetau : thetal;
                double temptheta2 = 0.9 * temptheta1;
                double ztemp1 = x_lrz(temptheta1, out _, out _, out _, n, n0, n1, x0, x1);
                double diff1 = Math.Abs(za2 - Math.Abs(ztemp1));
                double ztemp2 = x_lrz(temptheta2, out _, out _, out _, n, n0, n1, x0, x1);
                double diff2 = Math.Abs(za2 - Math.Abs(ztemp2));
                x_lrdiff(diff1, diff2, out double theta1, out double theta0, temptheta1, temptheta2, out double z1, out double z0, ztemp1, ztemp2, out double zcritical);
                int cnt = 0;
                double theta2;
                do
                {
                    if (i == 1)
                        za2 = -zc;
                    theta2 = Math.Exp(Math.Log(theta0) + (za2 - z0) / (z1 - z0) * Math.Log(theta1 / theta0));
                    temptheta1 = theta1;
                    temptheta2 = theta2;
                    ztemp2 = x_lrz(temptheta2, out _, out _, out _, n, n0, n1, x0, x1);
                    ztemp1 = z1;
                    diff1 = Math.Abs(za2 - ztemp1);
                    diff2 = Math.Abs(za2 - ztemp2);
                    x_lrdiff(diff1, diff2, out theta1, out theta0, temptheta1, temptheta2, out z1, out z0, ztemp1, ztemp2, out zcritical);
                    cnt += 1;
                    if (cnt > 5000)
                        break;
                    if (zcritical == lastz && zcritical < 0.001)
                        break;
                    lastz = zcritical;
                }
                while (!(zcritical < 0.00000001));
                if (i == 1)
                    thetau = theta2;
                else
                    thetal = theta2;
            }
        }

        private static double x_lrptilde(double theta, double a, double b, double C)
        {
            double pest1 = (-b + Math.Sqrt(b * b - 4.0 * a * C)) / 2.0 / a;
            double pest2 = (-b - Math.Sqrt(b * b - 4.0 * a * C)) / 2.0 / a;
            if (pest1 > 1.0 || pest1 < 0.0)
                return pest2;
            if (pest2 > 1.0 || pest2 < 0.0)
                return pest1;
            if (pest1 * theta > 1.0 || pest1 * theta < 0.0)
                return pest2;
            return pest1;
        }

        private static double x_lrz(double thetaHat, out double a, out double b, out double c, double n, double n0, double n1, double x0, double x1)
        {

            a = n * thetaHat;
            b = -((x0 + n1) * thetaHat + x1 + n0);
            c = x0 + x1;
            double p0tilde = x_lrptilde(thetaHat, a, b, c);
            double p1tilde = p0tilde * thetaHat;
            double q0tilde = 1.0 - p0tilde;
            double q1tilde = 1.0 - p1tilde;
            double utilde = q0tilde / (n0 * p0tilde) + q1tilde / (n1 * p1tilde);
            double vtilde = 1.0 / utilde;
            return (x1 - n1 * p1tilde) / q1tilde / Math.Sqrt(vtilde);
        }

        private static double PFromLogit(double x)
        {
            if (x == Constant.MISSING || double.IsNaN(x))
                return Constant.MISSING;
            // Each branch exponentiates a non-positive number, so neither tail overflows; a logit of exactly zero is a
            // probability of one half, which this function used to return as missing.
            if (x >= 0.0)
                return 1.0 / (1.0 + Math.Exp(-x));
            double y = Math.Exp(x);
            return y / (1.0 + y);
        }

        private static void x_lclass(double[] t, double[] fvl, double[] y, int N, out int tp, out int fp, out int fn, out int tn, double co)
        {
            // updated 15 Aug 2001
            tp = 0;
            fn = 0;
            fp = 0;
            tn = 0;
            //  a=true positives TP, b=false positives FP, c=false negatives FN, d=true negatives TN
            //  sens = a/(a+c), spec = d/(b+d)
            for (int j = 1; j <= N; j++)
            {
                double P = fvl[j] / t[j];
                int obsTot = Convert.ToInt32(t[j]);
                int obsPos = Convert.ToInt32(y[j]);
                int obsNeg = obsTot - obsPos;
                if (P >= co)
                {
                    tp += obsPos;
                    fp += obsNeg;
                }
                else
                {
                    tn += obsNeg;
                    fn += obsPos;
                }
            }
        }

        private static void x_lrdiff(double diff1, double diff2, out double theta1, out double theta0, double temptheta1, double temptheta2, out double z1, out double z0, double ztemp1, double ztemp2, out double zcritical)
        {
            if (diff1 < diff2)
            {
                theta1 = temptheta1;
                theta0 = temptheta2;
                z1 = ztemp1;
                z0 = ztemp2;
                zcritical = diff1;
            }
            else
            {
                theta0 = temptheta1;
                theta1 = temptheta2;
                z0 = ztemp1;
                z1 = ztemp2;
                zcritical = diff2;
            }
        }

        private static DataFrame x_prep_interlr(MultipleLinearRegressionContext context)
        {
            int iq = context.DoC ? 1 : 0;

            DataFrame frame = new();
            StringVariable keyVariable = new() { Title = "Name" };
            frame.Variables.Add(keyVariable);
            StringVariable valueVariable = new() { Title = "Value" };
            frame.Variables.Add(valueVariable);
            DoubleVariable oldValueVariable = new() { Title = "Old value" };
            frame.Variables.Add(oldValueVariable);

            for (int j = 1; j <= context.P - iq; j++)
            {
                double mu = 0.0;
                double a = context.X[1, j];
                double b = Constant.MISSING;
                bool bin = true;
                for (int i = 1; i <= context.N; i++)
                {
                    double z = context.X[i, j];
                    if (z != Constant.MISSING)
                    {
                        mu += z;
                        if (z != a)
                        {
                            if (z != b)
                            {
                                if (b == Constant.MISSING)
                                    b = z;
                                else
                                    bin = false;
                            }
                        }
                    }
                }
                if (bin)
                {
                    string t = context.Labels[j];
                    int px = t.IndexOf("(", StringComparison.Ordinal) + 1;
                    if (px == 0)
                    {
                        mu = 0.5;
                    }
                    else
                    {
                        //  Deal with multiple predictors with the same name - stored as name(...
                        int k = 1;
                        t = t.Substring(0, px - 1);
                        for (int i = 1; i < context.Labels.Length; i++)
                            if (null != context.Labels[i] && context.Labels[i].Contains(t))
                                k++;
                        mu = 1.0 / k;
                    }
                }
                else
                {
                    mu /= context.N;
                }
                keyVariable.SetData(j - 1, context.Labels[j]);
                valueVariable.SetData(j - 1, mu.ToString());
                oldValueVariable.SetData(j - 1, Parsing.Cdbl_Txt(mu.ToString()));
            }
            return frame;
        }

        public static StepOutput RptPoissonRegression(IFormatting host, ParameterBag parameters)
        {
            //  Dim PASSX(4, 1) As Double ' (1, 1) = calc intercept (1 = yes); (2, 1) = accuracy; (3, 1) = weights (1 = yes); (4, 1) = ptime (1 = yes)
            double tol = Parsing.Cdbl_Txt(parameters["accuracy"].AsString);
            if (tol > 0.01)
                tol = 0.01;

            bool ptime = "true".Equals(parameters["has-exposure"].AsString);
            bool weighted = parameters["weights"].AsBoolean;
            bool intercept = parameters["intercept"].AsBoolean;

            DataFrame responseFrame = parameters["response"].AsDataFrame;
            DoubleVariable responseVariable = (DoubleVariable)responseFrame.Variables[0];
            int rows = responseVariable.Length;
            double[] y = new double[rows + 1];
            double[] t = new double[rows + 1];
            double[] weight = new double[rows + 1];
            for (int c = 1; c <= rows; c++)
                y[c] = responseVariable.Data[c - 1];

            if (ptime)
            {
                DataFrame exposureFrame = parameters["exposure"].AsDataFrame;
                DoubleVariable exposureVariable = (DoubleVariable)exposureFrame.Variables[0];
                for (int c = 1; c <= rows; c++)
                    t[c] = exposureVariable.Data[c - 1];
            }

            if (weighted)
            {
                DataFrame weightFrame = parameters["weight"].AsDataFrame;
                DoubleVariable weightVariable = (DoubleVariable)weightFrame.Variables[0];
                for (int c = 1; c <= rows; c++)
                    weight[c] = weightVariable.Data[c - 1];
            }

            DataFrame predictorsFrame = parameters["predictors"].AsDataFrame;
            // Store the predictors
            int prd = predictorsFrame.VariableCount;
            double[,] x = new double[rows + 1, prd + 1];
            for (int c = 1; c <= prd; c++)
            {
                DoubleVariable v = (DoubleVariable)predictorsFrame.Variables[c - 1];
                for (int r = 1; r <= rows; r++)
                {
                    x[r, c] = v.Data[r - 1];
                    if (x[r, c] == Constant.MISSING)
                        weight[r] = Constant.MISSING;
                }
            }

            // is n<p
            if (prd + 1 >= rows)
                throw new TemplateOperationCancelledException("You must have more observations than parameters", "Poisson regression");

            //  Copy down the remaining observations
            int targetRow = 1;
            for (int sourceRow = 1; sourceRow <= rows; sourceRow++)
            {
                bool OK = y[sourceRow] != Constant.MISSING;
                if (t[sourceRow] == Constant.MISSING)
                    OK = false;
                if (weighted && weight[sourceRow] == Constant.MISSING)
                    OK = false;
                if (ptime && t[sourceRow] <= 0.0)
                    OK = false;
                for (int pred = 1; pred <= prd; pred++)
                {
                    if (x[sourceRow, pred] == Constant.MISSING)
                        OK = false;
                }
                if (OK)
                {
                    //  This row is valid; if necessary, copy it down to our current target row
                    if (sourceRow != targetRow)
                    {
                        y[targetRow] = y[sourceRow];
                        if (ptime)
                            t[targetRow] = t[sourceRow];
                        else
                            t[targetRow] = 1.0;
                        if (weighted)
                            weight[targetRow] = weight[sourceRow];
                        for (int pred = 1; pred <= prd; pred++)
                            x[targetRow, pred] = x[sourceRow, pred];
                    }
                    targetRow++;
                }
            }
            //  At this point, y, pt, wt and x contain valid data from row 1 to row targetrow - 1 inclusive
            // int ctr = 0; 
            string warn;
            const int maxit = 200;
            int rank = 0; int df = 0;
            double deviance = 0; double devx; double llx;
            int records = rows;
            int[] rxi = new int[1 + 1];
            int predictors = prd;
            int p = predictors;
            bool mean = intercept;
            if (mean)
                p++;
            string[] labels = new string[p + 1];
            labels[0] = responseVariable.Title;
            for (int j = 1; j <= prd; j++)
                labels[j] = predictorsFrame.Variables[j - 1].Title;
            ParameterBag outputParameters = new();
            IList<ParameterBag> warnList = new List<ParameterBag>();
            outputParameters.AddOutput("*warn", warnList);
            if (records != targetRow - 1)
            {
                AddDropWarning(warnList, records - (targetRow - 1));
                records = targetRow - 1;
            }
            bool use_offset = ptime;
            //  get intercept deviance - drop predictors
            double[,] x2 = new double[records + 1, 1 + 1];
            for (int j = 1; j <= records; j++)
            {
                x2[j, 0] = 1;
                x2[j, 1] = 1;
            }
            bool[] selectX = new bool[1 + 1];
            selectX[1] = true;
            double[] beta = new double[1 + 1];
            double[] se_beta = new double[records + 1];
            double[] covariance = new double[1 + 1];
            double[] fit = new double[records + 1];
            double[] residual = new double[records + 1];
            double[] leverage = new double[records + 1];
            double[] offset = new double[records + 1];
            //  use offset of log(exposure) if exposure specified
            if (use_offset)
            {
                for (int j = 1; j <= records; j++)
                    offset[j] = Math.Log(t[j]);
            }
            string dropped = string.Empty;
            string err_msg = string.Empty;
            Regress1.X_Poisson_Regression(false, use_offset, ref weighted, records, x2, 1, selectX, 1, y, t, weight, ref deviance, ref df, beta, ref rank, se_beta, covariance, tol, maxit, fit, residual, leverage, offset, out int fault, ref dropped, ref err_msg);
            int idfx = df;
            if (!mean)
            {
                llx = Constant.MISSING;
                devx = Constant.MISSING;
            }
            else
            {
                llx = x_loglik_p(weighted, records, weight, y, fit);
                devx = deviance;
            }
            //  calculate full model
            selectX = new bool[p + 1];
            for (int j = 1; j <= p; j++)
                selectX[j] = true;
            beta = new double[p + 1];
            se_beta = new double[records + 1];
            covariance = new double[(int)Math.Floor((double)p * (p + 1) / 2) + 1];
            fit = new double[records + 1];
            residual = new double[records + 1];
            leverage = new double[records + 1];
            Regress1.X_Poisson_Regression(mean, use_offset, ref weighted, records, x, predictors, selectX, p, y, t, weight, ref deviance, ref df, beta, ref rank, se_beta, covariance, tol, maxit, fit, residual, leverage, offset, out fault, ref dropped, ref err_msg);
            if (fault != 0 && fault != 3)
                throw new TemplateOperationCancelledException(err_msg, "Poisson regression");

            if (fault == 3 && err_msg.Length > 0)
                warnList.Add(new ParameterBag("warn", new FilledStringParameter(FilledParameterDirection.Output, Formatting.WRNCOLON + err_msg)));
            if (rank != p)
                warnList.Add(new ParameterBag("warn", new FilledStringParameter(FilledParameterDirection.Output, Formatting.WRNCOLON + "result not of full rank, there is more than one solution for the model. Look for correlated predictor variables that you might drop: the mutliple linear regression function does this automatically.")));
            if (df <= 0)
                warnList.Add(new ParameterBag("warn", new FilledStringParameter(FilledParameterDirection.Output, Formatting.WRNCOLON + "saturated model (all degrees of freedom used, can't assess goodness of fit)")));
            if (dropped.Length > 0)
                warnList.Add(new ParameterBag("warn", new FilledStringParameter(FilledParameterDirection.Output, dropped)));

            double GAMMA = parameters["gamma"].AsDouble;
            MathDbl.civ(0, out double cit, GAMMA, out double P0);
            outputParameters.AddOutput("pc", 100 * (1.0 - P0));

            outputParameters.AddOutput("dev", deviance);
            outputParameters.AddOutput("df_dev", df);
            double prob = PDF.chivalp(deviance, df);
            outputParameters.AddOutput("p_dev", prob);
            warn = prob < 0.05 ? Formatting.ASTERISK : string.Empty;
            outputParameters.AddOutput("w", warn);
            double x2dev = devx - deviance;
            if (x2dev < 0.0)
                x2dev = Constant.MISSING;
            outputParameters.AddOutput("x2", x2dev);
            outputParameters.AddOutput("df_x2", idfx - df);
            outputParameters.AddOutput("p_x2",
                df > 0
                    ? PDF.chivalp(x2dev, idfx - df)
                    : Constant.MISSING);
            IList<ParameterBag> predList = new List<ParameterBag>();
            outputParameters.AddOutput("*pred", predList);
            for (int i = 1; i <= p; i++)
            {
                if (se_beta[i] == 0)
                    prob = Constant.MISSING;
                else
                    prob = 2.0 * (1.0 - PDF.alnorm(Math.Abs(beta[i] / se_beta[i])));
                ParameterBag predParameters = new();
                predList.Add(predParameters);
                if (mean)
                {
                    predParameters.AddOutput("lab", i == 1 ? "Intercept" : labels[i - 1]);
                    predParameters.AddOutput("idx", i - 1);
                }
                else
                {
                    predParameters.AddOutput("lab", labels[i]);
                    predParameters.AddOutput("idx", i);
                }
                predParameters.AddOutput("res", beta[i]);
                double z;
                if (se_beta[i] == 0.0)
                {
                    z = Constant.MISSING;
                    predParameters.AddOutput("z", z);
                    predParameters.AddOutput("p", "* error: drop this variable *");
                }
                else
                {
                    z = beta[i] / se_beta[i];
                    predParameters.AddOutput("z", z);
                    predParameters.AddOutput("p", prob);
                }

                double rr = Formatting.SafeExp(beta[i]);
                double lci;
                double uci;
                if (rr != Constant.MISSING)
                {
                    lci = Formatting.SafeExp(beta[i] - se_beta[i] * cit);
                    uci = Formatting.SafeExp(beta[i] + se_beta[i] * cit);
                }
                else
                {
                    lci = Constant.MISSING;
                    uci = Constant.MISSING;
                }
                predParameters.AddOutput("irr", rr);
                predParameters.AddOutput("lci", lci);
                predParameters.AddOutput("uci", uci);
            }
            string tx = "log ";
            tx += labels[0].Length > 0
                ? labels[0]
                : "Y";
            if (use_offset)
            {
                tx += " [offset log(";
                tx += labels[1].Length > 0
                    ? labels[1]
                    : "exposure";
                tx += ")]";
            }
            tx += " = ";
            for (int j = 1; j <= p; j++)
            {
                if (j > 1 && beta[j] >= 0.0)
                    tx += "+";
                tx += host.RoundU(beta[j]);
                string Q = mean
                    ? (j > 1 ? labels[j - 1] : " ")
                    : labels[j];
                tx += Q.Length == 0
                    ? " X" + j.ToString()
                    : " " + Q + " ";
            }
            outputParameters.AddOutput("logit", tx);

            MultipleLinearRegressionContext context = new()
            {
                B = beta,
                Covariance = covariance,
                DEV = deviance,
                DEVX = devx,
                DF = df,
                DFX = idfx,
                DoC = mean,
                M = predictors,
                FV = fit,
                H1 = leverage,
                Labels = labels,
                LLX = llx,
                N = records,
                P = p,
                R = residual,
                RANK = rank,
                RXI = rxi,
                Se = se_beta,
                T = t,
                TOL = tol,
                WEIGHT = weighted,
                WT = weight,
                X = x,
                Y = y
            };
            outputParameters.AddInput("context", context.StripForOutput());
            return new StepOutput(outputParameters);
        }

        public static StepOutput RptPoissonRegressionFit(ParameterBag parameters)
        {
            MultipleLinearRegressionContext context = (MultipleLinearRegressionContext)parameters["context"].AsObject;
            double[] t = context.T;
            double[] y = context.Y;
            double[] fvl = context.FV;
            double[] dr = context.R;
            double[] hi = context.H1;
            int nx = context.N;
            bool DoC = context.DoC;
            string[] labels = context.Labels;
            int P = context.P;
            double[] covariance = context.Covariance;
            double[] wt = context.WT;
            bool Weight = context.WEIGHT;
            double[,] x = context.X;

            double ww;

            ParameterBag outputParameters = new();
            List<ParameterBag> predictorsList = new();
            outputParameters.AddOutput("*predictors", predictorsList);
            for (int i = 1; i <= labels.Length - 2; i++)
            {
                ParameterBag predictorsParameters = new();
                predictorsList.Add(predictorsParameters);
                predictorsParameters.AddOutput("lab", labels[i]);
            }
            List<ParameterBag> predictorValuesList = new();
            outputParameters.AddOutput("*predictorValues", predictorValuesList);
            for (int j = 1; j <= nx; j++)
            {
                ParameterBag predictorValuesParameters = new();
                predictorValuesList.Add(predictorValuesParameters);
                predictorValuesParameters.AddOutput("idx", j);
                List<ParameterBag> predictorsList2 = new();
                predictorValuesParameters.AddOutput("*pred", predictorsList2);
                for (int i = 1; i <= labels.Length - 2; i++)
                {
                    ParameterBag predictorsParameters = new();
                    predictorsList2.Add(predictorsParameters);
                    predictorsParameters.AddOutput("val", x[j, i]);
                }
            }

            IList<ParameterBag> eventsList = new List<ParameterBag>();
            outputParameters.AddOutput("*events", eventsList);
            for (int i = 1; i <= nx; i++)
            {
                ParameterBag eventsParameters = new();
                eventsList.Add(eventsParameters);
                eventsParameters.AddOutput("idx", i);
                eventsParameters.AddOutput("obs", y[i]);
                eventsParameters.AddOutput("fit", fvl[i]);
                eventsParameters.AddOutput("iro", t[i] != 0.0 ? y[i] / t[i] : Constant.MISSING);
                eventsParameters.AddOutput("ire", t[i] != 0.0 ? fvl[i] / t[i] : Constant.MISSING);
            }

            IList<ParameterBag> residualsList = new List<ParameterBag>();
            outputParameters.AddOutput("*residuals", residualsList);
            for (int i = 1; i <= nx; i++)
            {
                ParameterBag residualsParameters = new();
                residualsList.Add(residualsParameters);
                residualsParameters.AddOutput("idx", i);
                residualsParameters.AddOutput("yr", y[i] - fvl[i]);
                ww = Weight ? wt[i] : 1.0;
                double ftr = fvl[i] <= 0.0
                    ? Constant.MISSING
                    : Math.Sqrt(y[i]) * Math.Sqrt(ww) + Math.Sqrt(y[i] + 1.0) * Math.Sqrt(ww) - Math.Sqrt(4.0 * fvl[i] + 1.0) * Math.Sqrt(ww);
                residualsParameters.AddOutput("ftr", ftr);
                residualsParameters.AddOutput("dev", dr[i]);
            }

            IList<ParameterBag> pearsonList = new List<ParameterBag>();
            outputParameters.AddOutput("*pearson", pearsonList);
            for (int i = 1; i <= nx; i++)
            {
                ParameterBag pearsonParameters = new();
                pearsonList.Add(pearsonParameters);
                pearsonParameters.AddOutput("idx", i);
                ww = Weight ? wt[i] : 1;
                double xi = fvl[i] == 0.0 ? Constant.MISSING : Math.Pow(y[i] - fvl[i], 2.0) / fvl[i];
                pearsonParameters.AddOutput("res", xi);
                pearsonParameters.AddOutput("lev", hi[i]);
                // IEB July 2009
                double xis;
                if (fvl[i] == 0.0)
                {
                    // xi = Constant.MISSING; never used
                    xis = Constant.MISSING;
                }
                else
                {
                    xi = (y[i] - fvl[i]) * Math.Sqrt(ww) / Math.Sqrt(fvl[i]);
                    xis = 1.0 - hi[i] > 0.0 ? xi / Math.Sqrt(1.0 - hi[i]) : Constant.MISSING;
                }
                pearsonParameters.AddOutput("sres", xis);
            }

            IList<ParameterBag> covarList = new List<ParameterBag>();
            outputParameters.AddOutput("*covar", covarList);
            for (int i = 1; i <= P; i++)
            {
                for (int j = i; j <= P; j++)
                {
                    ParameterBag covarParameters = new();
                    covarList.Add(covarParameters);
                    covarParameters.AddOutput("labi", qlbli(labels, i, DoC));
                    covarParameters.AddOutput("labj", qlbli(labels, j, DoC));
                    covarParameters.AddOutput("cov", covariance[(int)Math.Floor((double)j * (j - 1) / 2 + i)]);
                }
            }
            return new StepOutput(outputParameters);
        }


        public static StepOutput GridPoissonRegressionFit(ParameterBag parameters)
        {
            MultipleLinearRegressionContext context = (MultipleLinearRegressionContext)parameters["context"].AsObject;
            double[] t = context.T;
            double[] y = context.Y;
            double[] fvl = context.FV;
            double[] dr = context.R;
            double[] hi = context.H1;
            int nx = context.N;
            double[] wt = context.WT;
            bool Weight = context.WEIGHT;
            bool expectedEvents = parameters["expectedEvents"].AsBoolean;
            bool expectedIncidence = parameters["expectedIncidence"].AsBoolean;
            bool residualEvents = parameters["residualEvents"].AsBoolean;
            bool freemanTukeyResidual = parameters["freemanTukeyResidual"].AsBoolean;
            bool devianceResidual = parameters["devianceResidual"].AsBoolean;
            bool pearsonResidual = parameters["pearsonResidual"].AsBoolean;
            bool leverage = parameters["leverage"].AsBoolean;
            bool stdPearsonResidual = parameters["stdPearsonResidual"].AsBoolean;
            ParameterBag outputParameters = new();
            DataFrame resultsFrame = new();
            if (expectedEvents || expectedIncidence || residualEvents || freemanTukeyResidual || devianceResidual || pearsonResidual || leverage || stdPearsonResidual)
            {
                //  Make up all the variables (it's fast!) then only include the ones we need
                DoubleVariable expectedEventsVariable = new(nx, "Expected events");
                DoubleVariable expectedIncidenceVariable = new(nx, "Expected incidence");
                DoubleVariable residualEventsVariable = new(nx, "Residual events");
                DoubleVariable freemanTukeyResidualVariable = new(nx, "Freeman-Tukey residual");
                DoubleVariable devianceResidualVariable = new(nx, "Deviance Residual");
                DoubleVariable pearsonResidualVariable = new(nx, "Pearson Residual");
                DoubleVariable leverageVariable = new(nx, "Leverage");
                DoubleVariable stdPearsonResidualVariable = new(nx, "Std Pearson Residual");
                for (int i = 1; i <= nx; i++)
                {
                    // Check for each save option
                    if (expectedEvents)
                    { // Events

                        expectedEventsVariable.SetData(i - 1, fvl[i]);
                    }
                    if (expectedIncidence)
                    {
                        // Incidence

                        double ry = t[i] != 0.0 ? fvl[i] / t[i] : Constant.MISSING;
                        expectedIncidenceVariable.SetData(i - 1, ry);
                    }
                    if (residualEvents)
                    { // Residual

                        residualEventsVariable.SetData(i - 1, y[i] - fvl[i]);
                    }
                    double ww;
                    if (freemanTukeyResidual)
                    { // Freeman-Tukey

                        ww = Weight ? wt[i] : 1.0;
                        double ftr = fvl[i] <= 0.0
                                         ? Constant.MISSING
                                         : Math.Sqrt(y[i]) * Math.Sqrt(ww) + Math.Sqrt(y[i] + 1.0) * Math.Sqrt(ww) -
                                           Math.Sqrt(4.0 * fvl[i] + 1.0) * Math.Sqrt(ww);
                        freemanTukeyResidualVariable.SetData(i - 1, ftr);
                    }
                    if (devianceResidual)
                    { // Deviance residuals

                        devianceResidualVariable.SetData(i - 1, dr[i]);
                    }
                    ww = Weight ? wt[i] : 1.0;
                    double xi = fvl[i] == 0.0 ? Constant.MISSING : Math.Pow(y[i] - fvl[i], 2.0) / fvl[i];
                    if (pearsonResidual)
                    { // Pearson chi-square residuals

                        pearsonResidualVariable.SetData(i - 1, xi);
                    }
                    if (leverage)
                    { // Leverage HI

                        leverageVariable.SetData(i - 1, hi[i]);
                    }
                    if (stdPearsonResidual)
                    { // Standardised Pearson residual

                        xi = (y[i] - fvl[i]) * Math.Sqrt(ww) / Math.Sqrt(fvl[i]);
                        double xis = 1.0 - hi[i] > 0.0 ? xi / Math.Sqrt(1.0 - hi[i]) : Constant.MISSING;
                        stdPearsonResidualVariable.SetData(i - 1, xis);
                    }
                }
                if (expectedEvents)
                    resultsFrame.Variables.Add(expectedEventsVariable);
                if (expectedIncidence)
                    resultsFrame.Variables.Add(expectedIncidenceVariable);
                if (residualEvents)
                    resultsFrame.Variables.Add(residualEventsVariable);
                if (freemanTukeyResidual)
                    resultsFrame.Variables.Add(freemanTukeyResidualVariable);
                if (devianceResidual)
                    resultsFrame.Variables.Add(devianceResidualVariable);
                if (pearsonResidual)
                    resultsFrame.Variables.Add(pearsonResidualVariable);
                if (leverage)
                {
                    // Leverage HI
                    resultsFrame.Variables.Add(leverageVariable);
                }
                if (stdPearsonResidual)
                {
                    // Standardised Pearson residual
                    resultsFrame.Variables.Add(stdPearsonResidualVariable);
                }
            }
            outputParameters.AddOutput("results", resultsFrame);
            return new StepOutput(outputParameters);
        }


        public static StepOutput RptPoissonRegressionResiduals(ParameterBag parameters)
        {
            MultipleLinearRegressionContext context = (MultipleLinearRegressionContext)parameters["context"].AsObject;
            int nx = context.N;
            double[] yfit = context.FV;
            double[] dr = context.R;
            double[,] xd = context.X;
            string[] labels = context.Labels;
            int P = context.P;
            bool Intercept = context.DoC;

            ParameterBag outputParameters = new();
            IList<ParameterBag> chartList = new List<ParameterBag>();
            outputParameters.AddOutput("*chart", chartList);

            double[] r = new double[nx + 1];
            r[0] = Constant.MISSING; //  Avoid drawing a point at (0,0)
            for (int j = 1; j <= nx; j++)
                r[j] = Math.Abs(dr[j]);

            ParameterBag chartParameters = new();
            chartList.Add(chartParameters);
            chartParameters.AddOutput("chart", ChartRendererFactory.PrepForLater(ChartType.Xy, new XyOptions(yfit, r, "Fitted Y", "Abs(Deviance residual)", "Absolute Residuals vs. Fitted Y [Poisson regression]", false, DataMinMax.XCalc_YCalc)));
            for (int i = 1; i <= P; i++)
            {
                if (i > 1 || !Intercept)
                {
                    bool ok = false;
                    int k = Intercept ? i - 1 : i;
                    r = new double[nx + 1];
                    for (int j = 1; j <= nx; j++)
                    {
                        r[j] = xd[j, k];
                        if (!ok)
                            ok = r[j] != 1.0 && r[j] != 0.0 && r[j] != -1.0;
                    }
                    if (ok)
                    {
                        chartParameters = new ParameterBag();
                        chartList.Add(chartParameters);
                        chartParameters.AddOutput("chart", ChartRendererFactory.PrepForLater(ChartType.Xy, new XyOptions(r, dr, "Predictor: " + labels[k], "Deviance residual", "Residuals vs. Predictor " + k.ToString() + " [Poisson regression]", true, DataMinMax.XCalc_YCalc)));
                    }
                }
            }
            return new StepOutput(outputParameters);
        }

        public enum ProbitModel
        {
            Probit = 1,
            Logit = 2,
        }

        public static StepOutput RptProbit(ParameterBag parameters)
        {
            return RptProbitOrLogit(parameters, ProbitModel.Probit);
        }

        public static StepOutput RptLogit(ParameterBag parameters)
        {
            return RptProbitOrLogit(parameters, ProbitModel.Logit);
        }

        public static StepOutput ProbitOrLogitDataHasControls(ParameterBag parameters)
        {
            DataFrame doseFrame = parameters["dose"].AsDataFrame;
            DoubleVariable doseVariable = (DoubleVariable)doseFrame.Variables[0];

            DataFrame subjectsFrame = parameters["subjects"].AsDataFrame;
            DoubleVariable subjectsVariable = (DoubleVariable)subjectsFrame.Variables[0];

            DataFrame respondersFrame = parameters["responders"].AsDataFrame;
            DoubleVariable respondersVariable = (DoubleVariable)respondersFrame.Variables[0];

            ParameterBag outputParameters = new();
            for (int n = 0; n < doseVariable.Length; n++)
            {
                if (doseVariable.Data[n] == 0.0 && subjectsVariable.Data[n] != Constant.MISSING && respondersVariable.Data[n] != Constant.MISSING)
                {
                    outputParameters.AddInput("dataHasControls", true);
                    outputParameters.AddInput("nc", Convert.ToInt32(subjectsVariable.Data[n]));
                    outputParameters.AddInput("nrc", Convert.ToInt32(respondersVariable.Data[n]));
                    break;
                }
            }
            return new StepOutput(outputParameters);
        }

        private static StepOutput RptProbitOrLogit(ParameterBag parameters, ProbitModel model)
        {
            DataFrame doseFrame = parameters["dose"].AsDataFrame;
            DoubleVariable doseVariable = (DoubleVariable)doseFrame.Variables[0];
            ColumnData[] cd = new ColumnData[3];
            cd[0] = new ColumnData { Title = doseVariable.Title };

            int rows = doseVariable.Length;
            double[] dv = new double[rows + 1];
            for (int row = 1; row <= rows; row++)
                dv[row] = doseVariable.Data[row - 1];

            DataFrame subjectsFrame = parameters["subjects"].AsDataFrame;
            DoubleVariable subjectsVariable = (DoubleVariable)subjectsFrame.Variables[0];
            cd[1] = new ColumnData { Title = subjectsVariable.Title };
            double[] sv = new double[rows + 1];
            for (int row = 1; row <= rows; row++)
                sv[row] = subjectsVariable.Data[row - 1];

            DataFrame respondersFrame = parameters["responders"].AsDataFrame;
            DoubleVariable respondersVariable = (DoubleVariable)respondersFrame.Variables[0];
            cd[2] = new ColumnData { Title = respondersVariable.Title };
            // Store the Responders Data
            double[] rv = new double[rows + 1];
            for (int row = 1; row <= rows; row++)
                rv[row] = respondersVariable.Data[row - 1];

            double ici = parameters["conf"].AsDouble;
            bool clog = parameters["calc-log10-doses"].AsBoolean;

            int ifa = 0;
            int laps = 0;
            int nc = 0; int nrc = 0; int icount = 0; int ifault2 = 0;
            double t; double seh = 0; double se = 0;
            double a = 0; double b = 0; double varb = 0; double sw = 0; double S1 = 0; double S2 = 0; double s3 = 0; double cse = 0; double cseh = 0;
            double I1 = 0; double XM = 0;
            double C2 = 0;
            double dose50 = 0; double doseq = 0; double nohetllm = 0;
            double nohetulm = 0; double hetllm = 0; double hetulm = 0; double nohetllq = 0; double nohetulq = 0; double hetllq = 0; double hetulq = 0; double TM = 0; double ym = 0; double del = 0; double s4 = 0; double s6 = 0;

            ParameterBag outputParameters = new();
            int nx = 0;

            int k = rows;
            double C1 = 0.0;
            double[] d = new double[k + 1];
            double[] s = new double[k + 1];
            double[] r = new double[k + 1];
            for (int n = 1; n <= k; n++)
            {
                if (dv[n] != Constant.MISSING && sv[n] != Constant.MISSING && rv[n] != Constant.MISSING)
                {
                    if (dv[n] == 0 && C1 == 0.0)
                    {
                        nc = Convert.ToInt32(sv[n]);
                        nrc = Convert.ToInt32(rv[n]);
                        C1 = -1.0;
                    }
                    else
                    {
                        nx++;
                        d[nx] = dv[n];
                        s[nx] = sv[n];
                        r[nx] = rv[n];
                    }
                }
            }
            k = nx;
            // create temp variable for copying values 
            double[] transTemp14 = new double[k + 1];
            Array.Copy(d, transTemp14, Math.Min(d.Length, transTemp14.Length));
            d = transTemp14;
            // create temp variable for copying values 
            double[] transTemp15 = new double[k + 1];
            Array.Copy(s, transTemp15, Math.Min(s.Length, transTemp15.Length));
            s = transTemp15;
            // create temp variable for copying values 
            double[] transTemp16 = new double[k + 1];
            Array.Copy(r, transTemp16, Math.Min(r.Length, transTemp16.Length));
            r = transTemp16;
            if (C1 == 0.0)
            {
                nc = parameters["nc"].AsInt32;
                if (nc > 0)
                {
                    nrc = parameters["nrc"].AsInt32;
                    C1 = -1.0;
                }
            }
            double qld = parameters["qld"].AsDouble;
            if (qld >= 100.0 || qld <= 0.0)
                qld = 90.0;

            double[] P = new double[k + 1];
            double[] w = new double[k + 1];
            double[] y = new double[k + 1];
            double[] pob = new double[k + 1];
            double[] x = new double[k + 1];
            x_sortbydose(d, s, r, k);
            double c = 0;
            x_probits(model, k, ref C1, ref c, ref nc, nrc, clog, qld, d, s, r, P, w, y, pob, x, ref a, ref b, ref laps, ref S1, ref S2, ref s3, ref s4, ref s6, ref del, ref TM, ref XM, ref ym, ref sw, ref icount, out int ifault);
            if (ifault != 0)
                throw new TemplateOperationCancelledException(ProbitFaultToString(ifault), "Fault in Probit Analysis");

            x_qdcl(model, k, out C2, ici, clog, qld, ref dose50, ref doseq, a, b, ref nohetllm, ref nohetulm, ref hetllm, ref hetulm, ref nohetllq, ref nohetulq, ref hetllq, ref hetulq, ref c, out se, ref cse, out seh, ref cseh, ref I1, ref S1, ref S2, ref s3, s4, s6, del, TM, XM, sw, out varb, icount, out ifault2);
            if (ifault2 != 0)
                throw new TemplateOperationCancelledException(ProbitFaultToString(ifault2), "Fault in Probit Analysis");

            outputParameters.AddOutput("title", model == ProbitModel.Probit ? "probit sigmoid curve" : "logit sigmoid curve");
            outputParameters.AddOutput("a", a);
            outputParameters.AddOutput("b", b);

            double hetp = PDF.chivalp(c, I1);
            outputParameters.AddOutput("mxd", dose50);
            if (hetp < 0.05)
            {
                outputParameters.AddOutput("het", "(Heterogeneity)");
                outputParameters.AddOutput("from", hetllm);
                outputParameters.AddOutput("to", hetulm);
            }
            else
            {
                outputParameters.AddOutput("het", "(No Heterogeneity)");
                outputParameters.AddOutput("from", nohetllm);
                outputParameters.AddOutput("to", nohetulm);
            }
            outputParameters.AddOutput("centile", qld);
            outputParameters.AddOutput("doseq", doseq);
            if (hetp < 0.05)
            {
                outputParameters.AddOutput("het_cent", "(Heterogeneity)");
                outputParameters.AddOutput("from_cent", hetllq);
                outputParameters.AddOutput("to_cent", hetulq);
            }
            else
            {
                outputParameters.AddOutput("het_cent", "(No Heterogeneity)");
                outputParameters.AddOutput("from_cent", nohetllq);
                outputParameters.AddOutput("to_cent", nohetulq);
            }
            outputParameters.AddOutput("dev", c);
            outputParameters.AddOutput("df", I1);
            outputParameters.AddOutput("p", hetp);
            if (hetp < 0.05)
                t = b / seh;
            else
                t = b / se;
            outputParameters.AddOutput("t_slope", t);
            outputParameters.AddOutput("df_slope", I1);
            double tp = PDF.tvalp(t, I1);
            if (tp > 1.0 - tp)
                tp = 1.0 - tp;
            tp = 2.0 * tp;
            outputParameters.AddOutput("p_slope", tp);
            if (tp > 0.05)
                outputParameters.AddOutput("*warn", new List<ParameterBag>() { new ParameterBag() });

            MultipleLinearRegressionContext context = new() { Arg = new double[18 + 1] };

            context.Arg[1] = a;
            context.Arg[2] = b;
            context.Arg[3] = t;
            context.Arg[4] = varb;
            context.Arg[5] = sw;
            context.Arg[6] = S1;
            context.Arg[7] = S2;
            context.Arg[8] = s3;
            context.Arg[9] = seh;
            context.Arg[10] = se;
            context.Arg[11] = cse;
            context.Arg[12] = cseh;
            context.Arg[13] = hetp;
            context.Arg[14] = I1;
            context.Arg[15] = XM;
            context.Arg[16] = ici;
            context.Arg[17] = C1;
            context.Arg[18] = C2;
            context.M = (int)model;
            context.X1 = d;
            context.Y = s;
            context.R = r;
            context.H1 = P;
            context.N = ifa;
            context.DoC = clog;
            context.P = laps;
            context.DF = k;
            context.DV = dv;
            context.SV = sv;
            context.RV = rv;
            context.Labels = new string[3];
            context.Labels[0] = doseVariable.Title;
            context.Labels[1] = subjectsVariable.Title;
            context.Labels[2] = respondersVariable.Title;
            outputParameters.AddInput("context", context.StripForOutput());
            return new StepOutput(outputParameters);
        }


        private static void x_sortbydose(double[] d, double[] s, double[] r, int k)
        {
            Tri[] swp = new Tri[k + 1];
            for (int i = 1; i <= k; i++)
            {
                swp[i].D = d[i];
                swp[i].S = s[i];
                swp[i].R = r[i];
            }
            Array.Sort(swp, 1, k, new TriByDAscending());
            for (int i = 1; i <= k; i++)
            {
                d[i] = swp[i].D;
                s[i] = swp[i].S;
                r[i] = swp[i].R;
            }
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="model"></param>
        /// <param name="k"></param>
        /// <param name="c1">Experimental value of natural mortality</param>
        /// <param name="c"></param>
        /// <param name="nc"></param>
        /// <param name="nrc"></param>
        /// <param name="clog"></param>
        /// <param name="qld"></param>
        /// <param name="d"></param>
        /// <param name="s"></param>
        /// <param name="r"></param>
        /// <param name="p"></param>
        /// <param name="w"></param>
        /// <param name="y"></param>
        /// <param name="pob"></param>
        /// <param name="x"></param>
        /// <param name="a"></param>
        /// <param name="b"></param>
        /// <param name="laps"></param>
        /// <param name="s1"></param>
        /// <param name="s2"></param>
        /// <param name="s3"></param>
        /// <param name="s4"></param>
        /// <param name="s6"></param>
        /// <param name="del"></param>
        /// <param name="tm"></param>
        /// <param name="xm"></param>
        /// <param name="ym"></param>
        /// <param name="sw"></param>
        /// <param name="icount"></param>
        /// <param name="ifault"></param>
        public static void x_probits(ProbitModel model, int k, ref double c1, ref double c, ref int nc, int nrc, bool clog, double qld, double[] d, double[] s, double[] r, double[] p, double[] w, double[] y, double[] pob, double[] x, ref double a, ref double b, ref int laps, ref double s1, ref double s2, ref double s3, ref double s4, ref double s6, ref double del, ref double tm, ref double xm, ref double ym, ref double sw, ref int icount, out int ifault)
        {
            int i;
            double pp;
            double s1L; double s2L; double s3L; double s4L = 0; double s6L = 0; double dell = 0;
            double s5 = 0;
            double swl;
            double dsq;

            double[] y2 = new double[k + 1];
            double[] t2 = new double[k + 1];
            //  ***  CALCULATE EXPERIMENTAL VALUE OF NATURAL MORTALITY (C1) AND RESET CPOOL
            double rc = nrc;
            double cpool = -1.0;
            if (c1 < 0.0)
            {
                c1 = rc / Convert.ToDouble(nc);
                cpool = c1;
            }
            if (c1 < 0.0)
            {
                ifault = 1;
                return;
            }
            double dc = 0.0;
            c = c1;
            for (i = 1; i <= k; i++)
            {
                x[i] = d[i];
            }
            //  ***  CHECK THAT NUMBER OF DOSE LEVELS >2
            ifault = 2;
            if (k <= 2)
            {
                return;
            }
            //  ***  CHECK DOSE LEVELS ARE ALL POSITIVE
            ifault = 3;
            for (i = 1; i <= k; i++)
            {
                if (x[i] < 0.0)
                {
                    return;
                }
            }
            //  ***  IF LOG CONVERSION REQUIRED , CHECK DOSE LEVELS > 0 THEN CONVERT TO
            //  ***  COMMON LOGS
            if (clog)
            {
                for (i = 1; i <= k; i++)
                {
                    if (x[i] > 0.0)
                    {
                        x[i] = Math.Log(x[i]) / Math.Log(10.0);
                    }
                    else
                    {
                        ifault = 4;
                        return;
                    }
                }
            }
            //  ***  CHECK FOR RESPONDERS > SUBJECTS, AND SUBJECTS < 1,  AND CALCULATE
            //  ***  PROPORTIONS RESPONDING
            for (i = 1; i <= k; i++)
            {
                if (s[i] > 0.0)
                {
                    if (s[i] - r[i] < 0.0)
                    {
                        ifault = 1;
                        return;
                    }
                    p[i] = r[i] / s[i];
                }
            }
            //  ***  CHECK THAT NO PROPORTIONS RESPONDING (P) ARE LOWER THAN OR EQUAL
            //  ***  TO THE EXPERIMENTAL VALUE OF NATURAL MORTALITY (CPOOL) (IF THERE
            //  ***  IS NO CONTROL DATA CPOOL WILL BE -1)
            int j = 0;
            for (i = 1; i <= k; i++)
            {
                if (p[i] - cpool <= 0.0)
                {
                    j = i;
                }
            }
            if (j > 0)
            {
                for (i = 1; i <= j; i++)
                {
                    nc += Convert.ToInt32(s[i]);
                    rc += r[i];
                }
                c1 = rc / Convert.ToDouble(nc);
                c = c1;
                ifault = 6;
                if (k - j <= 2)
                {
                    return;
                }
            }
            //  ***  CALCULATE INITIAL ESTIMATE OF A AND B FOR THE PROBIT EQUTION
            //  ***  CALCULATE OBSERVED PROBITS (POB), USING P ADJUSTED BY THE
            //  ***  EXPERIMENTAL VALUE OF NATURAL MORTALITY AND ADDING OR SUBTRACTING
            //  ***  -.5 IF PROPORTION RESPONDING IS 0.0 OR 1.0
            //  ***  CALCULATE EXPECTED PROBITS (Y) USING THESE INITIAL ESTIMATES
            double sm = 0.0;
            double sumxz = 0.0;
            double sumx = 0.0;
            double sumz = 0.0;
            double sumxx = 0.0;
            for (i = j + 1; i <= k; i++)
            {
                sm += 1.0;
                pp = (p[i] - c) / (1.0 - c);
                if (pp <= 0.0)
                {
                    pp = (0.5 / s[i] - c) / (1.0 - c);
                }
                else
                {
                    if (pp >= 1.0)
                    {
                        pp = ((r[i] - 0.5) / s[i] - c) / (1.0 - c);
                    }
                }
                double z = model == ProbitModel.Probit ? PDF.gauinv(pp) : 0.5 * Math.Log(pp / (1.0 - pp));
                pob[i] = z;
                sumxz += z * x[i];
                sumx += x[i];
                sumz += z;
                sumxx += x[i] * x[i];
            }
            xm = sumx / sm;
            double zm = sumz / sm;
            b = (sumxz - xm * sumz) / (sumxx - xm * sumx);
            a = zm - b * xm;
            for (i = 1; i <= k; i++)
            {
                y[i] = a + b * x[i];
            }
            //  ***  CALCULATE THE EXPECTED PROBITS ITERATIVELY  *******************
            //  ***  CALCULATE WEIGHTS(W) AND AUXILIARY VARIATE(T)
            do
            {
                icount = 0;
                for (i = 1; i <= k; i++)
                {
                    double v = y[i];
                    double dd;
                    double q;
                    if (model == ProbitModel.Probit)
                    {
                        pp = PDF.alnorm(v);
                        q = 1.0 - pp;
                        dd = 0.398942280401433 * Math.Exp(-v * v / 2.0);
                    }
                    else
                    {
                        pp = Math.Exp(v * 2.0) / (1.0 + Math.Exp(v * 2.0));
                        q = 1.0 - pp;
                        dd = 2.0 * q * pp;
                    }
                    if (q <= 0.0 | q >= 1.0)
                    {
                        icount += 1;
                        w[i] = 0.0;
                        t2[i] = 0.0;
                    }
                    else
                    {
                        w[i] = dd * dd / (q * (pp + c / (1.0 - c)));
                        t2[i] = q / dd;
                    }
                    //  ***  CALCULATE WORKING PROBITS (Y2)
                    double ap = (p[i] - c) / (1.0 - c);
                    if (y[i] <= 0.0)
                    {
                        if (dd == 0.0)
                        {
                            y2[i] = y[i] - pp + ap;
                        }
                        else
                        {
                            y2[i] = y[i] - pp / dd + ap / dd;
                        }
                    }
                    else
                    {
                        if (dd == 0.0)
                        {
                            y2[i] = y[i] + q - (1.0 - ap);
                        }
                        else
                        {
                            y2[i] = y[i] + q / dd - (1.0 - ap) / dd;
                        }
                    }
                }
                //  ***  CHECK THAT THER ARE NOT TOO MANY DOSE LEVELS WITH 0 WEIGHTS
                ifault = 7;
                if (k - icount < 2)
                {
                    return;
                }
                //  ***  CALCULATE VALUES OF COEFFICIENTS in EQUATIONS (S1 TO S7)
                //  ***  FINNEY, PROBIT ANALYSIS (1971) PAGE 130
                double swxx = 0.0;
                double swx = 0.0;
                swl = 0.0;
                double swxy = 0.0;
                double swy = 0.0;
                double swyy = 0.0;
                double swxt = 0.0;
                double swtt = 0.0;
                double swt = 0.0;
                double swty = 0.0;
                for (i = 1; i <= k; i++)
                {
                    swxt += s[i] * w[i] * x[i] * t2[i];
                    swt += s[i] * w[i] * t2[i];
                    swtt += s[i] * w[i] * t2[i] * t2[i];
                    swty += s[i] * w[i] * t2[i] * y2[i];
                    swxx += s[i] * w[i] * x[i] * x[i];
                    swx += s[i] * w[i] * x[i];
                    swl += s[i] * w[i];
                    swxy += s[i] * w[i] * x[i] * y2[i];
                    swy += s[i] * w[i] * y2[i];
                    swyy += s[i] * w[i] * y2[i] * y2[i];
                }
                s1L = swxx - swx * swx / swl;
                s2L = swxy - swx * swy / swl;
                s3L = swyy - swy * swy / swl;
                if (c > 0)
                {
                    s4L = swtt - swt * swt / swl + Convert.ToDouble(nc) * (1.0 - c) / c;
                    s5 = swty - swt * swy / swl + Convert.ToDouble(nc) * (c1 - c) / c;
                    s6L = swxt - swx * swt / swl;
                    double s7 = s6L * s6L;
                    dell = s1L * s4L - s7;
                }
                ym = swy / swl;
                xm = swx / swl;
                tm = swt / swl;
                //  ***  CALCULATE NEW A, B AND DC USING COEFFICIENTS
                ifault = 7;
                if (s1L == 0)
                {
                    return;
                }
                b = s2L / s1L;
                if (c > 0.0)
                {
                    b = (s4L * s2L - s6L * s5) / dell;
                    dc = (1.0 - c) * (s5 * s1L - s6L * s2L) / dell;
                }
                a = ym - b * xm - dc * tm / (1.0 - c);
                //  ***  CALCULATE NEW EXPECTED PROBITS (STORE in T TEMPORARILY) AND
                //  ***  ADD CHANGE in NATURAL MORTALITY TO ESTIMATE. COMPARE NEW EXPECTED
                //  ***  PROBITS WITH OLD AND IF CHANGE > 1D-9 RETURN TO BEGINING OF
                //  ***  ITERATIVE CYCLE
                dsq = 0.0;
                for (i = 1; i <= k; i++)
                {
                    double t = a + b * x[i];
                    dsq += (y[i] - t) * (y[i] - t);
                    y[i] = t;
                }
                c += dc;
                laps += 1;
                if (laps > 300)
                {
                    ifault = 10;
                    return;
                }
            }
            while (!(dsq < Constant.EPSILON));
            //  ***  CHECK THAT THERE ARE NOT TOO MANY DOSE LEVELS WITH 0 WEIGHTS
            ifault = 7;
            if (k - icount <= 2)
            {
                return;
            }
            //  ***  ADJUST P BY THE FINAL ESTIMATE OF NATURAL MORTALITY
            for (i = 1; i <= k; i++)
            {
                p[i] = (p[i] - c) / (1.0 - c);
            }
            //  ***  FINAL ESTIMATE OF NATURAL MORTALITY
            if (c > 0.0)
            {
            }
            s1 = s1L;
            s2 = s2L;
            s3 = s3L;
            s4 = s4L;
            s6 = s6L;
            sw = swl;
            del = dell;
            ifault = 0;
        }

        private static string ProbitFaultToString(int ifault)
        {
            if (ifault == 0)
                return null;
            switch (ifault)
            {
                case 1:
                    return "Responders > Subjects";
                case 2:
                    return "Dose levels < 2";
                case 3:
                    return "Negative dose level";
                case 4:
                    return "> 1 Dose level <= 0";
                case 6:
                    return "Too few dose levels after adjusting for controls";
                case 7:
                    return "Too many dose levels with zero weights";
                case 8:
                case 9:
                    return "Slope insignificant, can not calculate confidence limits";
                case 10:
                    return "Convergent solution not reached within 300 cycles";
                default:
                    return "Unknown error";
            }
        }


        private static void x_qdcl(ProbitModel model, int k, out double c2, double ici, bool clog, double qld, ref double dose50, ref double doseq, double a, double b, ref double nohetllm, ref double nohetulm, ref double hetllm, ref double hetulm, ref double nohetllq, ref double nohetulq, ref double hetllq, ref double hetulq, ref double c, out double se, ref double cse, out double seh, ref double cseh, ref double i1, ref double s1, ref double s2, ref double s3, double s4, double s6, double del, double tm, double xm, double sw, out double varb, int icount, out int ifault)
        {
            double covar = 0;
            double vardcb = 0;
            double g = 0;

            int ibit = 0;
            //  ***  PUT C2 = C, NATURAL MORTALITY. (C BECOMES THE CHI-SQUARED VALUE)
            c2 = c;
            c = s3 - b * s2;
            //  ***  CALCULATE THE VARIANCE OF B (VARB),(THE FORMULA IS DIFFERENT IF
            //  ***  THERE IS CONTROL DATA). CALCULATE THE DEGREES OF FREEDOM (I).
            varb = c2 <= 0.0
                ? 1.0 / s1
                : s4 / del;
            int i = k - 2 - icount;
            //  ***  WRITE CHI-SQUARE VALUE, AND STANDARD ERROR OF B FOR HETEROGENEITY
            //  ***  AND NO HETEROGENEITY
            se = Math.Sqrt(varb);
            seh = se * Math.Sqrt(c / Convert.ToDouble(i));
            //  ***  IF THERE ARE CONTROL DATA CALCULATE AND PRINT THE STANDARD ERROR
            //  ***  OF C FOR NO HETEROGENEITY AND HETEROGENEITY
            if (c2 > 0.0)
            {
                cse = (1.0 - c2) * Math.Sqrt(s1 / del);
                cseh = cse * Math.Sqrt(c / Convert.ToDouble(i));
            }
            //  ***  CALCULATE  AND PRINT THE VALUES FOR LETHAL DOSES 50 OR 90 (Z).
            //  ***  CONVERT IT IF LOGS HAVE BEEN USED. (IBIT RECORDS WHETHER LETHAL
            //  ***  DOSE 50 OR LETHAL DOSE Q IS BEING CALCULATED)
            do
            {
                int ifa;
                double qldz;
                if (ibit == 1)
                {
                    if (model == ProbitModel.Probit)
                    {
                        qldz = PDF.gauinv(qld / 100.0, out ifa);
                    }
                    else
                    {
                        qldz = qld / 100.0;
                        qldz = 0.5 * Math.Log(qldz / (1.0 - qldz));
                    }
                }
                else
                {
                    qldz = 0.0;
                }
                double pdose = (qldz - a) / b;
                double dose = clog ? Math.Exp(pdose * Math.Log(10.0)) : pdose;
                //  ***  FOR BOTH LETHAL DOSES CALCULATE THE CONFIDENCE LIMITS FOR
                //  ***  NO HETEROGENEITY AND HETEROGENEITY (HET RECORDS WHETHER NO
                //  ***  HETEROGENEITY OR HETEROGENEITY BEING PERFORMED) ***************
                //  ***  RECORD in ICL AND PRINT WHICH CONFIDENCE LIMITS ARE BEING
                //  ***  CALCULATED AND PUT THE NORMAL DEVIATE FOR THOSE LIMITS in T.
                double t = PDF.gauinv(ici + (1.0 - ici) / 2.0, out ifa);
                int het = 1;
                double vx = pdose - xm;
                varb = 1.0 / s1;
                //  ***  IF THERE IS CONTROL DATA THE FORMULA FOR CONFIDENCE LIMITS IS
                //  ***  MORE COMPLICATED, CALCULATE SOME EXTRA TERMS HERE
                if (c2 > 0.0)
                {
                    varb = s4 / del;
                    vardcb = s1 / del;
                    covar = -s6 / del;
                }
                //  ***  IF HETEROGENEITY CONFIDENCE LIMITS BEING CALCULATED, MULTIPLY
                //  ***  VALUES in EQUATION BY THE CHI-SQUARE VALUE DIVIDED BY THE DEGREES
                //  ***  OF FREEDOM AND PUT T VALUE FOR CONFIDENCE LIMITS INT.
                do
                {
                    if (het == 2)
                    {
                        varb = varb * c / Convert.ToDouble(i);
                        i1 = Convert.ToDouble(i);
                        t = PDF.tfromp((1.0 - ici) / 2.0, i1);
                    }
                    else
                    {
                        g = t * t * varb / (b * b);
                    }
                    //  ***  TEST FOR INSIGNIFICANCE OF SLOPE, IF IT IS PRESENT PRINT MESSAGE
                    //  ***  AND DISCONTINUE CALCULATIONS FOR THIS LETHAL DOSE
                    ifault = 9;
                    if (g - 1.0 > 0.0)
                        return;

                    //  ***  CALCULATE MORE TERMS in THE EQUATIONS FOR CONFIDENCE LIMITS
                    double gi = 1.0 - g;
                    double pf1 = pdose + g * vx / gi;
                    double pf2 = t / (Math.Abs(b) * gi);
                    double pf3 = gi / sw + varb * vx * vx;
                    if (het == 2)
                    {
                        pf3 = gi * c / (sw * i) + varb * vx * vx;
                    }
                    if (c2 > 0.0)
                    {
                        if (het == 2)
                        {
                            vardcb = vardcb * c / i;
                            covar = covar * c / i;
                        }
                        pf1 -= g * tm * covar / (varb * gi);
                        double pf3A = 1.0 / sw + tm * tm * vardcb;
                        if (het == 2)
                            pf3A = c / (sw * i) + tm * tm * vardcb;
                        pf3 = pf3A - 2 * vx * tm * covar + vx * vx * varb - g * (pf3A - tm * tm * covar * covar / varb);
                    }
                    ifault = 8;
                    if (pf3 < 0.0)
                        return;

                    double pf4 = pf2 * Math.Sqrt(pf3);
                    double ans1 = pf1 + pf4;
                    double ans2 = pf1 - pf4;
                    //  ***  IF LOG CONVERSION HAS BEEN USED CONVERT THE VALUES OF THE
                    //  ***  CONFIDENCE LIMITS
                    if (clog)
                    {
                        ans1 = Math.Exp(ans1 * Math.Log(10.0));
                        ans2 = Math.Exp(ans2 * Math.Log(10.0));
                    }
                    //  ***  SET THE CONFIDENCE LIMITS FOR NO HETEROGENEITY. PUT HET=2
                    //  ***  THEN GO BACK AND CALCULATE CONFIDENCE LIMITS FOR HETEROGENEITY
                    if (ibit == 0)
                    {
                        if (het == 1)
                        {
                            het = 2;
                            nohetllm = ans2;
                            nohetulm = ans1;
                        }
                        else
                        {
                            hetllm = ans2;
                            hetulm = ans1;
                            break;
                        }
                    }
                    else
                    {
                        if (het == 1)
                        {
                            het = 2;
                            nohetllq = ans2;
                            nohetulq = ans1;
                        }
                        else
                        {
                            hetllq = ans2;
                            hetulq = ans1;
                            break;
                        }
                    }
                }
                while (true);
                //  ***  IF LETHAL DOSE 50 HAS JUST BEEN CALCULATED THEN GO BACK AND
                //  ***  DO LETHAL DOSE 90
                if (ibit == 0)
                {
                    dose50 = dose;
                    ibit = 1;
                }
                else
                {
                    doseq = dose;
                    break;
                }
            }
            while (true);
            ifault = 0;
        }


        public static StepOutput PlotProbit(ParameterBag parameters)
        {
            MultipleLinearRegressionContext context = (MultipleLinearRegressionContext)parameters["context"].AsObject;
            int model = context.M;
            double[] x = context.X1;
            double[] y = context.H1;
            double a = context.Arg[1];
            double b = context.Arg[2];
            double sw = context.Arg[5];
            double s1 = context.Arg[6];
            double ici = context.Arg[16];
            bool clog = context.DoC;
            double t = context.Arg[13] < 0.05 ? PDF.tfromp(ici + (1.0 - ici) / 2.0, context.Arg[14]) : PDF.gauinv(ici + (1.0 - ici) / 2.0);

            string yAxisTitle = context.Labels[2] + " / " + context.Labels[1];
            string xAxisTitle = context.Labels[0];
            y[0] = Constant.MISSING; //  Force no point at (0,0)
            x[0] = Constant.MISSING;

            ParameterBag outputParameters = new();
            outputParameters.AddOutput("chart", ChartRendererFactory.PrepForLater(ChartType.Logit, new LogitOptions("Proportional Response with " + Formatting.XRound(ici * 100, 1) + "% CI", model, t, sw, s1, a, b, xAxisTitle, yAxisTitle, clog), new DoubleSeries(x, xAxisTitle), new DoubleSeries(y, yAxisTitle)));
            return new StepOutput(outputParameters);
        }

        public static StepOutput RptProbitInterpolateX(ParameterBag parameters)
        {
            MultipleLinearRegressionContext context = (MultipleLinearRegressionContext)parameters["context"].AsObject;
            int model = context.M;
            double a = context.Arg[1];
            double b = context.Arg[2];
            bool clog = context.DoC;
            double c2 = context.Arg[18];
            string[] label = context.Labels;

            // Interpolate X value
            double xval = parameters["newx"].AsDouble;
            if (xval < 0)
                throw new TemplateOperationCancelledException();

            ParameterBag outputParameters = new();
            if (xval == 0.0)
                xval = 1.0E-30;
            if (clog)
                xval = Math.Log(xval) / Math.Log(10.0);
            double yval = a + b * xval;
            outputParameters.AddOutput("x_lab", label[0]);
            outputParameters.AddOutput("x", xval);
            if (model == 1)
                yval = PDF.alnorm(yval);
            else
                yval = Math.Exp(yval * 2.0) / (1.0 + Math.Exp(yval * 2.0));
            outputParameters.AddOutput("resp", yval);
            if (c2 > 0)
            {
                yval = c2 + yval * (1.0 - c2);
                outputParameters.AddOutput("mort", "Incorporating natural mortality, proportional response = " + yval);
            }
            else
            {
                outputParameters.AddOutput("mort", string.Empty);
            }
            return new StepOutput(outputParameters);
        }


        public static StepOutput RptProbitInterpolateY(ParameterBag parameters)
        {
            MultipleLinearRegressionContext context = (MultipleLinearRegressionContext)parameters["context"].AsObject;
            int model = context.M;
            double a = context.Arg[1];
            double b = context.Arg[2];
            bool clog = context.DoC;
            double c2 = context.Arg[18];
            string[] label = context.Labels;
            double qdose;

            // Interpolate Y value
            double yval = parameters["newy"].AsDouble;
            if (yval <= 0 || yval >= 1)
                throw new TemplateOperationCancelledException();

            ParameterBag outputParameters = new();
            outputParameters.AddOutput("resp", yval);
            outputParameters.AddOutput("mort", c2 > 0 ? "Not considering natural mortality." : string.Empty);
            if (model == 1)
                qdose = PDF.gauinv(yval);
            else
                qdose = 0.5 * Math.Log(yval / (1.0 - yval));
            qdose = (qdose - a) / b;
            if (clog)
                qdose = Math.Exp(qdose * Math.Log(10.0));
            outputParameters.AddOutput("x_lab", label[0]);
            outputParameters.AddOutput("x", qdose);
            return new StepOutput(outputParameters);
        }


        public static StepOutput RptProbitMore(ParameterBag parameters)
        {
            MultipleLinearRegressionContext context = (MultipleLinearRegressionContext)parameters["context"].AsObject;
            int model = context.M;
            double a = context.Arg[1];
            double b = context.Arg[2];
            double varb = context.Arg[4];
            // double sw = context.ARG[ 5 ]; 
            double s1 = context.Arg[6];
            double s2 = context.Arg[7];
            double s3 = context.Arg[8];
            double seh = context.Arg[9];
            double se = context.Arg[10];
            double cse = context.Arg[11];
            double cseh = context.Arg[12];
            double hetp = context.Arg[13];
            // double ici = context.ARG[ 16 ]; 
            bool clog = context.DoC;
            // int nx = context.DF; 
            double c1 = context.Arg[17];
            double c2 = context.Arg[18];
            int laps = context.P;
            int k = context.DF;
            // string[] Label = context.Label; 
            double[] dv = context.DV;
            double[] sv = context.SV;
            double[] rv = context.RV;
            int i;

            ParameterBag outputParameters = new();
            outputParameters.AddOutput("itr", laps);
            outputParameters.AddOutput("sxx", s1);
            outputParameters.AddOutput("sxy", s2);
            outputParameters.AddOutput("syy", s3);
            outputParameters.AddOutput("var_b", varb);
            if (hetp < 0.05)
            {
                outputParameters.AddOutput("het", "with heterogeneity");
                outputParameters.AddOutput("seb", seh);
            }
            else
            {
                outputParameters.AddOutput("het", "without heterogeneity");
                outputParameters.AddOutput("seb", se);
            }
            if (c1 != 0)
            {
                IList<ParameterBag> naturalList = new List<ParameterBag>();
                outputParameters.AddOutput("*natural", naturalList);
                ParameterBag naturalParameters = new();
                naturalList.Add(naturalParameters);
                naturalParameters.AddOutput("c", c2);
                if (hetp < 0.05)
                {
                    naturalParameters.AddOutput("het_c", "with heterogeneity");
                    naturalParameters.AddOutput("seb_c", cseh);
                }
                else
                {
                    naturalParameters.AddOutput("het_c", "without heterogeneity");
                    naturalParameters.AddOutput("seb_c", cse);
                }
            }
            else
            {
                outputParameters.AddOutput("*natural", null);
            }
            IList<ParameterBag> obsList = new List<ParameterBag>();
            outputParameters.AddOutput("*obs", obsList);
            for (i = 1; i <= k; i++)
            {
                double xval = dv[i];
                if (xval == 0)
                    xval = 1.0E-30;
                if (clog)
                    xval = Math.Log(xval) / Math.Log(10.0);
                double yval = a + b * xval;
                // int ifa = 0; 
                if (model == 1)
                    yval = PDF.alnorm(yval);
                else
                    yval = Math.Exp(yval * 2.0) / (1.0 + Math.Exp(yval * 2.0));
                yval = c2 + yval * (1.0 - c2);
                double ex = yval * sv[i];
                ParameterBag obsParameters = new();
                obsList.Add(obsParameters);
                obsParameters.AddOutput("obs", i);
                obsParameters.AddOutput("sub", sv[i]);
                obsParameters.AddOutput("res", rv[i]);
                obsParameters.AddOutput("exp", ex);
                obsParameters.AddOutput("dev", rv[i] - ex);
            }
            return new StepOutput(outputParameters);
        }
    }
}
