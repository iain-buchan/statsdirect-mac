using StatsDirect.Data;
using StatsDirect.Numerics;
using StatsDirect.Utilities;

using System;
namespace StatsDirect.Builtins
{
    public static class Random
    {
        private const string BADPARA = "The parameters are not acceptable.";

        public static DataFrame RndPoisson(int rows, int cols, double xm, int seed)
        {
            PoissonRNG rng = new();
            rng.Seed(seed, null);
            string ti = $"Poisson (seed {seed}, mean {xm})";
            DataFrame outputFrame = new();
            for (int c = 0; c < cols; c++)
            {
                DoubleVariable v = new(rows, ti);
                outputFrame.Variables.Add(v);
                for (int n = 0; n < rows; n++)
                    v.Data[n] = rng.GenPoisson(xm);
            }
            return outputFrame;
        }

        public static DataFrame RndUni(int rows, int cols, double a, double b, bool isCount, int seed)
        {
            UniformXRNG rng = new();
            rng.Seed(seed, null);
            DataFrame outputFrame = new();
            if (a != Constant.MISSING && b != Constant.MISSING)
            {
                string ti = $"Uniform {Math.Min(a, b)} to {Math.Max(a, b)} (seed {seed})";
                for (int c = 0; c < cols; c++)
                {
                    DoubleVariable v = new(rows, ti);
                    outputFrame.Variables.Add(v);
                    for (int n = 0; n < rows; n++)
                        v.SetData(n, rng.GenUniAB(a, b, isCount));
                }
            }
            else
            {
                string ti = $"Uniform 0 to 1 (seed {seed})";
                for (int c = 0; c < cols; c++)
                {
                    DoubleVariable v = new(rows, ti);
                    outputFrame.Variables.Add(v);
                    for (int n = 0; n < rows; n++)
                        v.Data[n] = rng.GenUni();
                }
            }
            return outputFrame;
        }

        public static DataFrame RndBino(int rows, int cols, int nn, double pp, int seed)
        {
            BinomialRND rng = new();
            rng.Seed(seed);
            double nx = Convert.ToDouble(nn);
            string ti = $"Binomial (seed {seed}, n = {nn}, p = {pp})";
            DataFrame outputFrame = new();
            for (int c = 0; c < cols; c++)
            {
                DoubleVariable v = new(rows, ti);
                outputFrame.Variables.Add(v);
                for (int n = 0; n < rows; n++)
                    v.Data[n] = rng.GenBinom(nx, pp);
            }
            return outputFrame;
        }

        public static DataFrame RndExpo(int rows, int cols, double m, int seed)
        {
            ExponentialRNG rng = new();

            const string mx = "Exponential deviates";
            if (m <= 0.0 || rows <= 0)
                throw new TemplateOperationCancelledException(BADPARA, mx);

            rng.Seed(seed);
            string ti = $"Exponential (seed {seed}, rate = {m})";
            DataFrame outputFrame = new();
            for (int c = 0; c < cols; c++)
            {
                DoubleVariable v = new(rows, ti);
                outputFrame.Variables.Add(v);
                for (int n = 0; n < rows; n++)
                    v.Data[n] = rng.GenExp() / m;
            }
            return outputFrame;
        }

        public static DataFrame RndF(int rows, int cols, double dfn, double dfd, int seed)
        {
            const string mx = "F deviates";
            if (dfn <= 0.0 || dfd <= 0.0 || rows <= 0)
                throw new TemplateOperationCancelledException(BADPARA, mx);

            GammaRNG rng = new();
            rng.Seed(seed);
            string ti = $"F (seed {seed}, dfn = {dfn}, dfd = {dfd})";
            DataFrame outputFrame = new();
            for (int c = 0; c < cols; c++)
            {
                DoubleVariable v = new(rows, ti);
                outputFrame.Variables.Add(v);
                for (int n = 0; n < rows; n++)
                    v.Data[n] = rng.GenF(dfn, dfd);
            }
            return outputFrame;
        }

        public static DataFrame RndGeom(int rows, int cols, double a, int seed)
        {
            const string mx = "Geometric deviates";
            if (rows <= 0 || a <= 0.0 || a > 1.0)
                throw new TemplateOperationCancelledException(BADPARA, mx);

            PoissonRNG rng = new();
            rng.Seed(seed);
            string ti = $"Geometric (seed {seed}, P = {a})";
            DataFrame outputFrame = new();
            for (int c = 0; c < cols; c++)
            {
                DoubleVariable v = new(rows, ti);
                outputFrame.Variables.Add(v);
                for (int n = 0; n < rows; n++)
                    v.Data[n] = rng.GenGeom(a);
            }
            return outputFrame;
        }

        public static DataFrame RndNegBin(int rows, int cols, double a, double b, int seed)
        {
            const string mx = "Negative binomial deviates";
            if (rows <= 0 || b <= 0.0 || b > 1.0 || a <= 0.0)
                throw new TemplateOperationCancelledException(BADPARA, mx);

            PoissonRNG rng = new();
            rng.Seed(seed);
            string ti = $"Negative binomial (seed {seed}, size = {a}, P = {b})";
            DataFrame outputFrame = new();
            for (int c = 0; c < cols; c++)
            {
                DoubleVariable v = new(rows, ti);
                outputFrame.Variables.Add(v);
                for (int n = 0; n < rows; n++)
                    v.Data[n] = rng.GenNegbin(a, b);
            }
            return outputFrame;
        }

        public static DataFrame RndBeta(int rows, int cols, double a, double b, int seed)
        {
            const string mx = "beta deviates";
            if (rows <= 0 || b <= 0.0 || a <= 0.0)
                throw new TemplateOperationCancelledException(BADPARA, mx);

            BetaRNG rng = new();
            rng.Seed(seed);
            string ti = $"Beta (seed {seed}, a = {a}, b = {b})";
            DataFrame outputFrame = new();
            for (int c = 0; c < cols; c++)
            {
                DoubleVariable v = new(rows, ti);
                outputFrame.Variables.Add(v);
                for (int n = 0; n < rows; n++)
                    v.Data[n] = rng.GenBeta(a, b);
            }
            return outputFrame;
        }

        public static DataFrame RndCauchy(int rows, int cols, double a, double b, int seed)
        {
            const string mx = "Cauchy deviates";
            if (rows <= 0 || b < 0.0)
                throw new TemplateOperationCancelledException(BADPARA, mx);

            UniformXRNG rng = new();
            rng.Seed(seed);
            string ti = $"Cauchy (seed {seed}, loc = {a}, scl = {b})";
            DataFrame outputFrame = new();
            for (int c = 0; c < cols; c++)
            {
                DoubleVariable v = new(rows, ti);
                outputFrame.Variables.Add(v);
                for (int n = 0; n < rows; n++)
                    v.Data[n] = rng.GenCauchy(a, b);
            }
            return outputFrame;
        }

        public static DataFrame RndWeibull(int rows, int cols, double a, double b, int seed)
        {
            const string mx = "Weibull deviates";
            if (rows <= 0 || a <= 0.0 || b <= 0.0)
                throw new TemplateOperationCancelledException(BADPARA, mx);

            UniformXRNG rng = new();
            rng.Seed(seed);
            string ti = $"Weibull (seed {seed}, shp = {a}, scl = {b})";
            DataFrame outputFrame = new();
            for (int c = 0; c < cols; c++)
            {
                DoubleVariable v = new(rows, ti);
                outputFrame.Variables.Add(v);
                for (int n = 0; n < rows; n++)
                    v.Data[n] = rng.GenWeibull(a, b);
            }
            return outputFrame;
        }

        public static DataFrame RndLogit(int rows, int cols, double a, double b, int seed)
        {
            const string mx = "Logistic deviates";
            if (rows <= 0)
                throw new TemplateOperationCancelledException(BADPARA, mx);

            UniformXRNG rng = new();
            rng.Seed(seed);
            string ti = $"Logistic (seed {seed}, loc = {a}, scl = {b})";
            DataFrame outputFrame = new();
            for (int c = 0; c < cols; c++)
            {
                DoubleVariable v = new(rows, ti);
                outputFrame.Variables.Add(v);
                for (int n = 0; n < rows; n++)
                    v.Data[n] = rng.GenLogistic(a, b);
            }
            return outputFrame;
        }

        public static DataFrame RndT(int rows, int cols, double df, int seed)
        {
            const string mx = "Student t deviates";
            if (df <= 0.0 || rows <= 0)
                throw new TemplateOperationCancelledException(BADPARA, mx);

            GammaRNG rng = new();
            rng.Seed(seed);
            string ti = $"Student t (seed {seed}, df = {df})";
            DataFrame outputFrame = new();
            for (int c = 0; c < cols; c++)
            {
                DoubleVariable v = new(rows, ti);
                outputFrame.Variables.Add(v);
                for (int n = 0; n < rows; n++)
                    v.Data[n] = rng.GenT(df);
            }
            return outputFrame;
        }

        public static DataFrame RndChi(int rows, int cols, double df, int seed)
        {
            const string mx = "Chi-square deviates";
            if (df <= 0.0 || rows <= 0)
                throw new TemplateOperationCancelledException(BADPARA, mx);

            GammaRNG rng = new();
            rng.Seed(seed);
            string ti = $"Chi-square (seed {seed}, df = {df})";
            DataFrame outputFrame = new();
            for (int c = 0; c < cols; c++)
            {
                DoubleVariable v = new(rows, ti);
                outputFrame.Variables.Add(v);
                for (int n = 0; n < rows; n++)
                {
                    double e = rng.GenChiSq(df);
                    if (e == Constant.MISSING)
                        throw new TemplateOperationCancelledException(BADPARA, mx);
                    v.Data[n] = e;
                }
            }
            return outputFrame;
        }

        public static DataFrame RndGamma(int rows, int cols, double a, double b, int seed)
        {
            const string mx = "Gamma deviates";
            // both parameters must be positive: B = 0 filled the column with zeros and a negative B gave negative "gamma" deviates
            if (a <= 0.0 || b <= 0.0 || rows <= 0)
                throw new TemplateOperationCancelledException(BADPARA, mx);

            GammaRNG rng = new();
            rng.Seed(seed);
            string ti = $"Gamma (seed {seed}, A = {a}, B = {b})";
            DataFrame outputFrame = new();
            for (int c = 0; c < cols; c++)
            {
                DoubleVariable v = new(rows, ti);
                outputFrame.Variables.Add(v);
                for (int n = 0; n < rows; n++)
                    v.Data[n] = rng.GenGamma(a, b);
            }
            return outputFrame;
        }

        public static DataFrame RndLogNorm(int rows, int cols, double xm, double sd, int seed)
        {
            const string mx = "Lognormal deviates";
            if (sd < 0)
                throw new TemplateOperationCancelledException(BADPARA, mx);

            NormalRNG rng = new();
            rng.Seed(seed);
            string ti = $"Lognormal (seed {seed}, log mean = {xm}, log sd = {sd})";
            DataFrame outputFrame = new();
            for (int c = 0; c < cols; c++)
            {
                DoubleVariable v = new(rows, ti);
                outputFrame.Variables.Add(v);
                for (int n = 0; n < rows; n++)
                    v.Data[n] = Formatting.SafeExp(rng.GenNorm(xm, sd));
            }
            return outputFrame;
        }

        public static DataFrame RndNorm(int rows, int cols, double xm, double sd, int seed)
        {
            NormalRNG rng = new();
            rng.Seed(seed);
            string ti = $"Normal (seed {seed}, mean = {xm}, sd = {sd})";
            DataFrame outputFrame = new();
            for (int c = 0; c < cols; c++)
            {
                DoubleVariable v = new(rows, ti);
                outputFrame.Variables.Add(v);
                for (int n = 0; n < rows; n++)
                    v.Data[n] = rng.GenNorm(xm, sd);
            }
            return outputFrame;
        }
    }
}
