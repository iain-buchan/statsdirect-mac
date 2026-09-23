using StatsDirect.Numerics;
using System;

namespace StatsDirect.Builtins
{
    /// <summary>
    /// Named "Context" because this was originally a way of storing regression calculations and passing them to follow-on operations.  It's now a general calculation tool in addition to that use.
    /// </summary>
    [Serializable]
    public class SimpleLinearRegressionContext
    {
        public double[] X { get; private set; }
        public double[] Y { get; private set; }
        private bool calculated;

        public double YIntercept { get; private set; }
        public double Slope { get; private set; }
        public int DF { get; private set; }
        public double CIT { get; private set; }
        public double P0 { get; private set; }
        public double SumX { get; private set; }
        public double SSX { get; private set; }
        public double SSY { get; private set; }
        public double SDX { get; private set; }
        public double SSREG { get; private set; }
        public double MS { get; private set; }
        public double PERT { get; private set; }
        /// <summary>
        /// Correlation coefficient
        /// </summary>
        public double R { get; private set; }
        /// <summary>
        /// Estimated standard error
        /// </summary>
        public double SeEst { get; private set; }
        public int NX { get; private set; }
        /// <summary>
        /// True iff correlation coefficient is 1 or -1
        /// </summary>
        public bool IsPerfectCorrelation { get; private set; }
        public double A { get; set; }
        public double G { get; set; }
        public string XTitle { get; }
        public string YTitle { get; }

        /// <summary>
        /// Create a context to calculate the results of a linear regression on x and y.
        /// </summary>
        /// <param name="x">0-based</param>
        /// <param name="y">0-based</param>
        public SimpleLinearRegressionContext(double[] x, double[] y, string xTitle, string yTitle)
        {
            X = x;
            Y = y;
            XTitle = xTitle;
            YTitle = yTitle;
            NX = X.Length;
        }

        /// <summary>
        /// Apply function to each element of X, storing the result back into X.
        /// </summary>
        public void ApplyToX(Func<double, double> function)
        {
            for (int i = 0; i < X.Length; i++)
                X[i] = function.Invoke(X[i]);
        }

        /// <summary>
        /// Apply function to each element of Y, storing the result back into Y.
        /// </summary>
        public void ApplyToY(Func<double, double> function)
        {
            for (int i = 0; i < Y.Length; i++)
                Y[i] = function.Invoke(Y[i]);
        }

        public void CalculateLeastSquaresMethod()
        {
            if (calculated)
                return;

            SumX = 0.0;
            double sumy = 0.0;
            double sumxy = 0.0;
            double sys = 0.0;
            double sxs = 0.0;
            for (int n = 0; n < NX; n++)
            {
                double x = X[n];
                double y = Y[n];
                SumX += x;
                sxs += x * x;
                sumy += y;
                sys += y * y;
                sumxy += x * y;
            }
            SSX = sxs - SumX * SumX / NX;
            SSY = sys - sumy * sumy / NX;
            SDX = Math.Sqrt(SSX / (NX - 1));
            double xy = sumxy - SumX * sumy / NX;
            Slope = xy / SSX;
            YIntercept = sumy / NX - Slope * (SumX / NX);
            R = xy / Math.Sqrt(SSX * SSY);
            IsPerfectCorrelation = Math.Abs(R) >= 1;
            SSREG = xy * xy / SSX;
            double ssres = SSY - SSREG;
            MS = ssres / (NX - 2);
            SeEst = MS > 0.0 ? Math.Sqrt(MS) : Constant.MISSING;
            calculated = true;
        }

        /// <summary>
        /// Release any hold on large data arrays as we may be serialised
        /// </summary>
        public SimpleLinearRegressionContext StripForOutput()
        {
            X = null;
            Y = null;
            return this;
        }

        public void CalcRcia(double regressionGamma)
        {
            // Either this will have data, or CalculateLeastSquaresMethod() will have been run and NX will have been set.
            if (null != X)
                NX = X.Length;
            DF = NX - 2;
            MathDbl.civ(DF, out double cit, regressionGamma, out double P0);
            PERT = cit;
            CIT = cit;
            this.P0 = P0;
        }
    }
}
