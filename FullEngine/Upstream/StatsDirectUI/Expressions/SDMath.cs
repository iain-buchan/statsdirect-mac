using System;
using StatsDirect.Numerics;

namespace StatsDirect.Expressions
{
    /// <summary>
    /// Implementations of functions referred to by the expression calculator.
    /// </summary>
    public static class SDMath
    {
        public static double Factorial(double n)
        {
            if (n < 0.0)
                return Constant.MISSING;
            if (n == 0.0)
                return 1.0;
            if (0.0 <= n && n <= 50.0)
            {
                if (n != Math.Floor(n))
                    return Math.Exp(PDF.alogam(n + 1.0));
                double Q = 1.0;
                for (int j = Convert.ToInt32(n); j >= 1; j--)
                    Q *= j;
                return Q;
            }
            double a = PDF.alogam(n + 1.0);
            double maxExp = Math.Log(double.MaxValue);
            return a > maxExp ? Constant.MISSING : Math.Exp(a);
        }

        // The hyperbolic functions and their inverses come from the runtime library. The textbook formulas in exponentials,
        // squares and logarithms that stood here overflowed or cancelled where the answer is an ordinary number:
        // ASINH(-1e8) and ASINH(1e200) were infinite, ASINH(1e-20) and ATANH(1e-20) were 0, TANH(1000) and COTH(1000) were
        // not a number, SINH(710) was infinite. The inverses of the reciprocal functions use acsch x = asinh(1/x), and
        // asech x = acosh(1/x), acoth x = atanh(1/x) except near 1, where the quotient 1/x throws away what 1 - x still holds.
        public static double Asinh(double arg)
        {
            return Math.Asinh(arg);
        }

        public static double Acosh(double arg)
        {
            return Math.Acosh(arg);
        }

        public static double Atanh(double arg)
        {
            return Math.Atanh(arg);
        }

        public static double Asech(double arg)
        {
            // just below 1 the quotient 1/x falls on the coarser grid above 1 and acosh(1/x) loses up to half the figures of
            // 1 - x, which is itself exact there; log(1 + sqrt((1 - x)(1 + x))) - log x adds two non-negative terms instead
            if (arg >= 0.5 && arg <= 1.0)
                return Log1p(Math.Sqrt((1.0 - arg) * (1.0 + arg))) - Math.Log(arg);
            return Math.Acosh(1.0 / arg);
        }

        public static double Acsch(double arg)
        {
            return Math.Asinh(1.0 / arg);
        }

        public static double Acoth(double arg)
        {
            // acoth x = log((x + 1) / (x - 1)) / 2 = log(1 + 2 / (|x| - 1)) / 2 with the sign of x. |x| - 1 is exact just
            // beyond 1, where atanh(1/x) loses figures, and 2 / (|x| - 1) is small for a large x, where the plain logarithm did
            double half = 0.5 * Log1p(2.0 / (Math.Abs(arg) - 1.0));
            return arg < 0.0 ? -half : half;
        }

        // Inverse secant, cosecant and cotangent by the reciprocal identities: asec x = acos(1/x) in [0, pi],
        // acsc x = asin(1/x) in [-pi/2, pi/2], acot x = pi/2 - atan x in (0, pi), continuous through x = 0.
        // The formulas that stood here were those of an old table of "derived math functions", which is wrong for all
        // three: sec(ASEC(2)) was 1.53, csc(ACSC(2)) was 1.32 and cot(ACOT(2)) was -2, where each should be 2.
        public static double Asec(double arg)
        {
            return Math.Acos(1.0 / arg);
        }

        public static double Acsc(double arg)
        {
            return Math.Asin(1.0 / arg);
        }

        public static double Acot(double arg)
        {
            return Math.Atan2(1.0, arg);
        }

        public static double Sinh(double arg)
        {
            return Math.Sinh(arg);
        }

        // CLOG (common logarithm) and COSH are in the function registry, and CLOG is in the help, but neither method existed,
        // so an expression using them could not be compiled.
        public static double Cosh(double arg)
        {
            return Math.Cosh(arg);
        }

        public static double Clog(double arg)
        {
            return Math.Log10(arg);
        }

        public static double Tanh(double arg)
        {
            return Math.Tanh(arg);
        }

        public static double Sech(double arg)
        {
            return 1.0 / Math.Cosh(arg);
        }

        public static double Csch(double arg)
        {
            return 1.0 / Math.Sinh(arg);
        }

        public static double Coth(double arg)
        {
            return 1.0 / Math.Tanh(arg);
        }

        public static double Cexp(double arg)
        {
            return Math.Exp(arg * Math.Log(10.0));
        }

        public static double LogFactorial(double arg)
        {
            return arg < 0.0 ? Constant.MISSING : PDF.alogam(arg + 1.0);
        }

        public static double Sec(double arg)
        {
            return 1.0 / Math.Cos(arg);
        }

        public static double Csc(double arg)
        {
            return 1.0 / Math.Sin(arg);
        }

        public static double Cot(double arg)
        {
            return 1.0 / Math.Tan(arg);
        }

        public static double Alogit(double arg)
        {
            // exp(arg) / (1 + exp(arg)) is infinity over infinity, NaN, for arg above about 709.8
            double term = arg >= 0.0 ? 1.0 / (1.0 + Math.Exp(-arg)) : Math.Exp(arg) / (1.0 + Math.Exp(arg));
            if (term <= Constant.EPSNEG)
                return 0.0;
            if (term >= 1.0 - Constant.EPSNEG)
                return 1.0;
            return term;
        }

        public static double Lz(double arg)
        {
            return PDF.alnorm(arg);
        }

        public static double Uz(double arg)
        {
            // the upper tail at z is the lower tail at -z; 1 - lower lost an upper tail below about 1e-16
            return PDF.alnorm(-arg);
        }

        public static double Iz(double arg)
        {
            // the deviate with upper tail area arg is minus the one with that lower tail area; 1 - arg lost a small arg
            double term = PDF.gauinv(arg, out int ifault);
            if (ifault != 0)
                throw new ArgumentOutOfRangeException(nameof(arg), arg, "gauinv returned fault");
            return 0.0 - term; // not -term: IZ(0.5) would be the negative zero that is displayed as -0
        }

        public static double Deg(double arg)
        {
            return arg * 0.0174532925199433;
        }

        public static double Rad(double arg)
        {
            return arg * 57.2957795130824;
        }

        public static double Logit(double x)
        {
            if (x < 0.0 || x > 1.0)
                throw new ArgumentOutOfRangeException(nameof(x), x, "logit: x must be between 0 and 1");
            if (x == 0.0)
                x = Constant.EPSNEG;
            else if (x == 1.0)
                x = 1.0 - Constant.EPSNEG;
            return Math.Log(x / (1.0 - x));
        }

        public static double Cint(double arg)
        {
            return Convert.ToDouble(Convert.ToInt64(arg));
        }

        public static double TTail(double df, double q)
        {
            return PDF.tvalp(q, df);
        }

        public static double InvTTail(double df, double p)
        {
            return PDF.tfromp(p, df);
        }

        /// <summary>
        /// probability of k events, which is the density
        /// </summary>
        /// <param name="mean"></param>
        /// <param name="k"></param>
        /// <returns></returns>
        public static double Poissonp(double mean, double k)
        {
            ExFortran.poisson(mean, (int)Math.Floor(k), out double _, out double _, out double term, out int fault);
            return fault != 0 ? Constant.MISSING : term;
        }

        /// <summary>
        /// probability of k or more events
        /// </summary>
        /// <param name="mean"></param>
        /// <param name="k"></param>
        /// <returns></returns>
        public static double PoissonTail(double mean, double k)
        {
            return PoissonAtLeast(Math.Floor(k), mean);
        }

        /// <summary>
        /// P(X &gt;= k) for a Poisson variable, computed directly as the lower incomplete gamma ratio P(k, mean), by the identity
        /// between the Poisson sum and the incomplete gamma integral. The engine's routine returns 1 - P(X &lt;= k) + P(X = k), which
        /// loses a small upper tail entirely: P(X &gt; 100) with a mean of 2 came out as 0 where it is 3.7e-131.
        /// </summary>
        private static double PoissonAtLeast(double k, double mean)
        {
            if (double.IsNaN(k) || double.IsNaN(mean) || mean < 0.0 || mean == Constant.MISSING || k == Constant.MISSING)
                return Constant.MISSING;
            if (k <= 0.0)
                return 1.0;
            if (mean == 0.0)
                return 0.0;
            double tail = PDF.gammad(mean, k, false, out int fault);
            return fault != 0 ? Constant.MISSING : tail;
        }

        /// <summary>
        /// P(X &gt;= r) for a binomial variable, computed directly as the incomplete beta ratio I_p(r, n - r + 1), by the identity
        /// between the binomial sum and the incomplete beta integral, not as 1 - P(X &lt;= r) + P(X = r).
        /// </summary>
        private static double BinomialAtLeast(double r, double n, double p)
        {
            if (double.IsNaN(r) || double.IsNaN(n) || double.IsNaN(p) || n < 0.0 || p < 0.0 || p > 1.0 || r == Constant.MISSING || n == Constant.MISSING || p == Constant.MISSING)
                return Constant.MISSING;
            if (r <= 0.0)
                return 1.0;
            if (r > n)
                return 0.0;
            double tail = PDF.betain(p, r, n - r + 1.0, out int fault);
            return fault != 0 ? Constant.MISSING : tail;
        }

        /// <summary>
        /// probability of k or a more extreme number of events, in the direction away from the mean:
        /// P(X &gt;= k) when k is at or above the mean, P(X &lt;= k) when k is below it
        /// </summary>
        /// <param name="mean"></param>
        /// <param name="k"></param>
        /// <returns></returns>
        /// <remarks>
        /// The author's definition (20 September 2026). Since version 3 this had taken a probability and returned a count,
        /// by a bisection on the lower tail that could never return 0 or 1.
        /// </remarks>
        public static double InvPoissonTail(double mean, double k)
        {
            double events = Math.Floor(k);
            if (events >= mean)
                return PoissonAtLeast(events, mean);
            ExFortran.poisson(mean, (int)events, out double _, out double plo, out double _, out int fault);
            return fault != 0 ? Constant.MISSING : plo;
        }

        /// <summary>
        /// r or fewer sucesses
        /// </summary>
        /// <param name="n"></param>
        /// <param name="r"></param>
        /// <param name="p"></param>
        /// <returns></returns>
        public static double Binomial(double n, double r, double p)
        {
            ExFortran.bino((int)Math.Floor(n), p, (int)Math.Floor(r), out double _, out double dplo, out double _, out int fault);
            return fault != 0 ? Constant.MISSING : dplo;
        }

        /// <summary>
        /// exactly r sucesses
        /// </summary>
        /// <param name="n"></param>
        /// <param name="r"></param>
        /// <param name="p"></param>
        /// <returns></returns>
        public static double Binomialp(double n, double r, double p)
        {
            ExFortran.bino((int)Math.Floor(n), p, (int)Math.Floor(r), out double dterm, out double _, out double _, out int fault);
            return fault != 0 ? Constant.MISSING : dterm;
        }

        /// <summary>
        /// r or more sucesses
        /// </summary>
        /// <param name="n"></param>
        /// <param name="r"></param>
        /// <param name="p"></param>
        /// <returns></returns>
        public static double BinomialTail(double n, double r, double p)
        {
            return BinomialAtLeast(Math.Floor(r), Math.Floor(n), p);
        }

        public static double Chi2Tail(double df, double q)
        {
            return PDF.chivalp(q, df);
        }

        public static double InvChi2Tail(double df, double p)
        {
            // p is an upper tail area, as CHI2TAIL returns
            return Qchisq(p, df, false, false);
        }

        public static double Ftail(double dfn, double dfd, double q)
        {
            if (q == Constant.MISSING || dfn == Constant.MISSING || dfd == Constant.MISSING)
                return Constant.MISSING;
            return PDF.fvalp(q, dfn, dfd);
        }

        public static double InvFtail(double dfn, double dfd, double p)
        {
            // p is an upper tail area, as FTAIL returns
            return Qf(p, dfn, dfd, false, false);
        }

        public static double Pnorm(double q, double mean, double sd, bool lowerTail, bool logP)
        {
            // The upper tail at z is the lower tail at -z, by symmetry, and is computed as such: taken as 1 - lower it was lost
            // once it fell below about 1e-16 (PNORM(10, 0, 1, FALSE) was 0 where it is 7.6e-24).
            double z = (q - mean) / sd;
            if (!lowerTail)
                z = -z;
            return logP ? LogNormalLowerTail(z) : PDF.alnorm(z);
        }

        private const double LogRoot2Pi = 0.91893853320467274178;

        /// <summary>
        /// The logarithm of the standard normal lower tail area at z: log1p of the other tail when the area is near 1, and where
        /// the area itself is beyond a double (z below -35, an area under 1e-268) the asymptotic series
        /// Phi(z) = phi(z) / |z| (1 - 1/z^2 + 3/z^4 - 15/z^6 + ...), Abramowitz and Stegun 26.2.12. The logarithm used to be taken
        /// of an area that had already become 0.
        /// </summary>
        private static double LogNormalLowerTail(double z)
        {
            if (double.IsNaN(z))
                return double.NaN;
            if (z > 0.0)
                return Log1p(-PDF.alnorm(-z));
            if (z >= -35.0)
                return Math.Log(PDF.alnorm(z));
            return -0.5 * z * z - Math.Log(-z) - LogRoot2Pi + Math.Log(NormalTailSeries(z));
        }

        /// <summary>1 - 1/z^2 + 3/z^4 - 15/z^6 + ..., for z below -35: Phi(z) is phi(z) / |z| times this, so Phi(z) / phi(z) is this over |z|</summary>
        private static double NormalTailSeries(double z)
        {
            double z2 = z * z, sum = 1.0, term = 1.0;
            for (int j = 1; j <= 30; j++)
            {
                term *= -(2.0 * j - 1.0) / z2;
                sum += term;
                if (Math.Abs(term) < 1.0E-17)
                    break;
            }
            return sum;
        }

        public static double Qnorm(double p, double mean, double sd, bool lowerTail, bool logP)
        {
            double z = StandardNormalQuantile(p, logP);
            if (z == Constant.MISSING)
                return Constant.MISSING;
            // the deviate for an upper tail area is minus the one for the same lower tail area; 1 - p lost a small p altogether
            if (!lowerTail)
                z = -z;
            // the quantile of Normal(mean, sd); mean and sd used to be ignored
            return mean + sd * z;
        }

        /// <summary>
        /// The standard normal deviate with lower tail area p, or exp(p) when p is a logarithm, without forming exp(p) or
        /// 1 - exp(p) where they cannot hold the probability.
        /// </summary>
        private static double StandardNormalQuantile(double p, bool logP)
        {
            int fault;
            double z;
            if (!logP)
            {
                z = PDF.gauinv(p, out fault);
                return fault != 0 ? Constant.MISSING : z;
            }
            if (double.IsNaN(p) || p > 0.0 || p == Constant.MISSING || double.IsNegativeInfinity(p))
                return Constant.MISSING;
            if (p > -0.6931471805599453)
            {
                // a probability above one half: invert the other tail, 1 - exp(p) = -2 sinh(p/2) exp(p/2), which keeps a p very near 0
                double other = -2.0 * Math.Sinh(p / 2.0) * Math.Exp(p / 2.0);
                z = PDF.gauinv(other, out fault);
                return fault != 0 ? Constant.MISSING : -z;
            }
            if (p >= -700.0)
            {
                z = PDF.gauinv(Math.Exp(p), out fault);
                return fault != 0 ? Constant.MISSING : z;
            }
            // exp(p) is beyond a double: Newton iteration on the logarithm of the tail area, starting where phi(z) / |z| = exp(p)
            double r = Math.Sqrt(-2.0 * p);
            if (double.IsInfinity(r))
                return Constant.MISSING;
            z = -(r - (Math.Log(r) + LogRoot2Pi) / r);
            for (int i = 0; i < 30; i++)
            {
                // The step is (log Phi(z) - p) Phi(z) / phi(z), and z stays far below -35 here, where the ratio is the tail series
                // over |z|. Rebuilding the ratio as exp(log Phi + z^2 / 2 + ...) cancels two numbers the size of p, which for a p
                // beyond about -1e16 left only rounding noise and threw z to infinity.
                double step = z < -35.0
                    ? (LogNormalLowerTail(z) - p) * NormalTailSeries(z) / -z
                    : (LogNormalLowerTail(z) - p) * Math.Exp(LogNormalLowerTail(z) + 0.5 * z * z + LogRoot2Pi);
                z -= step;
                if (Math.Abs(step) <= 1.0E-15 * Math.Abs(z))
                    break;
            }
            return double.IsNaN(z) || double.IsInfinity(z) ? Constant.MISSING : z;
        }

        public static double Pt(double q, double df, double ncp, bool lowerTail, bool logP)
        {
            double p;
            if (ncp == Constant.MISSING || ncp == 0.0)
            {
                // central t, for any degrees of freedom. tvalp is the upper tail area, so the lower tail at q is the upper tail at
                // -q; each tail is computed directly and not as 1 minus the other
                p = lowerTail ? PDF.tvalp(-q, df) : PDF.tvalp(q, df);
            }
            else
            {
                p = NoncentralT(q, df, ncp);
                if (p == Constant.MISSING)
                    return Constant.MISSING;
                if (!lowerTail)
                    p = 1.0 - p;
            }
            if (logP)
                p = Math.Log(p);
            return p;
        }

        public static double Qt(double p, double df, double ncp, bool lowerTail, bool logP)
        {
            if (logP)
                p = Math.Exp(p);
            // central t, for any degrees of freedom; tfromp takes an upper tail area, and the quantile for a lower tail area is
            // minus the one for the same upper tail area
            // (0.0 - x and x + 0.0, not -x and x: the median would otherwise be the negative zero that is displayed as -0)
            if (ncp == Constant.MISSING || ncp == 0.0)
                return lowerTail ? 0.0 - PDF.tfromp(p, df) : PDF.tfromp(p, df) + 0.0;
            if (!lowerTail)
                p = 1.0 - p;
            if (HasWholeDegreesOfFreedom(df))
            {
                double q = ExFortran.tnct(p, (int)df, ncp, out int fault);
                return fault != 0 ? Constant.MISSING : q;
            }
            return NoncentralTQuantile(p, df, ncp);
        }

        private static bool HasWholeDegreesOfFreedom(double df)
        {
            return df == Math.Floor(df) && df >= 1.0 && df <= int.MaxValue;
        }

        /// <summary>
        /// Lower tail area of the non-central t distribution. With whole degrees of freedom this is the routine of the engine, as
        /// before. That routine takes whole degrees of freedom only, and PT and QT used to round fractional ones down without
        /// saying so, even for a non-centrality of 0 (PT(1, 2.5, 0) was the value for 2 degrees of freedom). Fractional degrees
        /// of freedom use the series of Lenth (1989), Algorithm AS 243, Applied Statistics 38:185-189, which holds for any
        /// positive degrees of freedom, and above a million the normal approximation of Abramowitz and Stegun 26.7.10.
        /// </summary>
        private static double NoncentralT(double t, double df, double ncp)
        {
            if (double.IsNaN(t) || double.IsNaN(df) || double.IsNaN(ncp) || t == Constant.MISSING || df == Constant.MISSING || df <= 0.0)
                return Constant.MISSING;
            if (HasWholeDegreesOfFreedom(df))
            {
                double whole = ExFortran.pnct(t, (int)df, ncp, out int wholeFault);
                return wholeFault != 0 ? Constant.MISSING : whole;
            }
            if (double.IsInfinity(t))
                return t > 0.0 ? 1.0 : 0.0;
            const int maxTerms = 2000;
            const double errorBound = 1.0E-15;
            bool negative = t < 0.0;
            double del = negative ? -ncp : ncp;
            double lambda = del * del;
            // exp(-lambda / 2) starts the series; beyond this it is 0 in a double and the series cannot be summed
            if (lambda > 1400.0)
                return Constant.MISSING;
            // Above a million degrees of freedom the series loses figures (it rests on the difference of two log gammas of size
            // df ln df) and its first incomplete beta takes a number of terms in proportion to df, so that a single call ran for
            // minutes. T is then normal to better than 1e-9: Abramowitz and Stegun 26.7.10.
            if (df > 1.0E6)
            {
                double quarter = 1.0 / (4.0 * df);
                double scale = Math.Sqrt(1.0 + 2.0 * quarter * t * t);
                if (double.IsInfinity(scale))
                    return t > 0.0 ? 1.0 : 0.0;
                return PDF.alnorm((t * (1.0 - quarter) - ncp) / scale);
            }
            double tt = t * t;
            // t * t is beyond a double for |t| above about 1.3e154; x is then 1 to within a double and 1 - x = df / t^2
            bool beyond = double.IsInfinity(tt);
            double x = beyond ? 1.0 : tt / (tt + df);
            double oneMinusX = beyond ? 0.0 : df / (tt + df); // known accurately, which 1 - x formed from x is not once t^2 dwarfs df
            double tnc = 0.0;
            if (x > 0.0)
            {
                double p = 0.5 * Math.Exp(-0.5 * lambda);
                double q = 0.79788456080286535588 * p * del; // sqrt(2 / pi)
                double s = 0.5 - p;
                double a = 0.5, b = 0.5 * df;
                double logRxb = beyond ? b * (Math.Log(df) - 2.0 * Math.Log(Math.Abs(t))) : -b * Log1p(tt / df);
                double rxb = beyond ? Math.Exp(logRxb) : Math.Pow(oneMinusX, b); // (1 - x)^b
                double albeta = 0.57236494292470008707 + PDF.alogam(b) - PDF.alogam(a + b); // ln(sqrt(pi)) + ln gamma(b) - ln gamma(a + b)
                // I_x(a, b) = 1 - I_(1-x)(b, a): with heavy tails (few degrees of freedom, a huge t) the answer lies in 1 - x
                int fault;
                double xodd = x > 0.5 ? 1.0 - PDF.betain(oneMinusX, b, a, out fault) : PDF.betain(x, a, b, out fault);
                if (fault != 0)
                    return Constant.MISSING;
                double godd = 2.0 * rxb * Math.Exp(a * Math.Log(x) - albeta);
                double xeven = 1.0 - rxb;
                double geven = b * x * rxb;
                // (1 - x)^b falls below a double once (df / 2) ln(1 + t^2 / df) passes about 744, yet with a large non-centrality
                // the terms it starts grow back to matter some hundreds of steps on: their logarithms are carried then
                bool carryLogs = rxb < TinyTail;
                double logGodd = 0.0, logGeven = 0.0;
                if (carryLogs)
                {
                    logGodd = Math.Log(2.0) + logRxb + a * Math.Log(x) - albeta;
                    logGeven = Math.Log(b * x) + logRxb;
                    godd = Math.Exp(logGodd);
                    geven = Math.Exp(logGeven);
                }
                tnc = p * xodd + q * xeven;
                bool converged = false;
                for (int en = 1; en <= maxTerms; en++)
                {
                    a += 1.0;
                    xodd -= godd;
                    xeven -= geven;
                    if (carryLogs)
                    {
                        logGodd += Math.Log(x * (a + b - 1.0) / a);
                        logGeven += Math.Log(x * (a + b - 0.5) / (a + 0.5));
                        godd = Math.Exp(logGodd);
                        geven = Math.Exp(logGeven);
                    }
                    else
                    {
                        godd *= x * (a + b - 1.0) / a;
                        geven *= x * (a + b - 0.5) / (a + 0.5);
                    }
                    p *= lambda / (2.0 * en);
                    q *= lambda / (2.0 * en + 1.0);
                    s -= p;
                    tnc += p * xodd + q * xeven;
                    if (2.0 * s * (xodd - godd) <= errorBound)
                    {
                        converged = true;
                        break;
                    }
                }
                if (!converged)
                    return Constant.MISSING;
            }
            tnc += PDF.alnorm(-del);
            if (negative)
                tnc = 1.0 - tnc;
            return Math.Min(Math.Max(tnc, 0.0), 1.0);
        }

        /// <summary>
        /// The t with lower tail area p under NoncentralT, by bracketing and bisection; the area rises steadily with t. The area
        /// is good to about 1e-15, so a p (or 1 - p) below 1e-10 cannot be located to more than a few figures and is refused.
        /// </summary>
        private static double NoncentralTQuantile(double p, double df, double ncp)
        {
            if (double.IsNaN(p) || p < 1.0E-10 || p > 1.0 - 1.0E-10)
                return Constant.MISSING;
            double low = ncp - 1.0, high = ncp + 1.0, step = 1.0;
            for (int i = 0; ; i++)
            {
                double area = NoncentralT(low, df, ncp);
                if (area == Constant.MISSING || i > 1100)
                    return Constant.MISSING;
                if (area < p)
                    break;
                step *= 2.0;
                low -= step;
            }
            step = 1.0;
            for (int i = 0; ; i++)
            {
                double area = NoncentralT(high, df, ncp);
                if (area == Constant.MISSING || i > 1100)
                    return Constant.MISSING;
                if (area > p)
                    break;
                step *= 2.0;
                high += step;
            }
            if (double.IsInfinity(low) || double.IsInfinity(high))
                return Constant.MISSING;
            for (int i = 0; i < 2000 && high - low > 1.0E-13 * Math.Max(1.0, Math.Abs(low) + Math.Abs(high)); i++)
            {
                double mid = 0.5 * (low + high);
                double area = NoncentralT(mid, df, ncp);
                if (area == Constant.MISSING)
                    return Constant.MISSING;
                if (area < p)
                    low = mid;
                else
                    high = mid;
            }
            return 0.5 * (low + high);
        }

        public static double Dpois(double k, double mean, bool logP)
        {
            double events = Math.Floor(k);
            ExFortran.poisson(mean, (int)events, out double _, out double _, out double term, out int fault);
            if (fault != 0)
                return Constant.MISSING;
            if (!logP)
                return term;
            // the logarithm of a probability too small for a double comes from the logarithm of the term, not from the 0 it became
            if (term < TinyTail && events >= 0.0 && mean > 0.0)
                return LogPoissonTerm(events, mean);
            return Math.Log(term);
        }

        /// <summary>
        /// P(X &lt;= k) for a Poisson variable as the upper incomplete gamma ratio Q(k + 1, mean), the other tail of the same
        /// function that gives PoissonAtLeast, so the two tails sum to 1; 1 for a mean of zero.
        /// PPOIS and QPOIS share it so that one inverts the other. The engine's summation (POISSON) agrees with it to about
        /// 1e-11; near 1 with a mean of 10000 that sum is out by 5e-12, which was enough to put QPOIS one count short.
        /// </summary>
        private static double PoissonAtMost(double k, double mean)
        {
            if (double.IsNaN(k) || double.IsNaN(mean) || mean < 0.0 || mean == Constant.MISSING || k == Constant.MISSING)
                return Constant.MISSING;
            if (k < 0.0)
                return 0.0;
            if (mean == 0.0)
                return 1.0;
            double tail = PDF.gammad(mean, k + 1.0, true, out int fault);
            return fault != 0 ? Constant.MISSING : tail;
        }

        public static double Ppois(double k, double mean, bool lowerTail, bool logP)
        {
            // The upper tail is P(X > k) = P(X >= k + 1), and it is computed directly: taking it as 1 - P(X <= k)
            // lost it altogether once it fell below about 1e-16 (and its logarithm with it).
            double events = Math.Floor(k);
            double lower = PoissonAtMost(events, mean), upper = PoissonAtLeast(events + 1.0, mean);
            if (lower == Constant.MISSING || upper == Constant.MISSING)
                return Constant.MISSING;
            if (!logP)
                return lowerTail ? lower : upper;
            double smallLog = double.NaN;
            if (mean > 0.0 && events >= 0.0)
            {
                // the logarithm of a tail too small for a double, summed in log space from the probability of the nearest count
                if (!lowerTail && upper < TinyTail)
                    smallLog = LogPoissonTerm(events + 1.0, mean) + Math.Log(TailSeries(j => mean / (events + 1.0 + j)));
                if (lowerTail && lower < TinyTail)
                    smallLog = LogPoissonTerm(events, mean) + Math.Log(TailSeries(j => j > events ? 0.0 : (events - j + 1.0) / mean));
            }
            return LogOfTail(lowerTail ? lower : upper, lowerTail ? upper : lower, smallLog);
        }

        private const double TinyTail = 1.0E-290;

        /// <summary>
        /// The logarithm of a tail probability: through log1p of the other tail when the probability is near 1 (where log(1 - tiny)
        /// would be 0), and from a sum in log space when it is too small for a double.
        /// </summary>
        private static double LogOfTail(double tail, double otherTail, double logWhenTiny)
        {
            if (tail < TinyTail && !double.IsNaN(logWhenTiny))
                return logWhenTiny;
            if (tail > 0.5)
                return Log1p(-otherTail);
            return Math.Log(tail);
        }

        /// <summary>log(1 + x), accurate for small x, where log(1 + x) computed directly loses x altogether</summary>
        private static double Log1p(double x)
        {
            double u = 1.0 + x;
            if (u == 1.0)
                return x + 0.0; // + 0.0 turns a negative zero, which would be displayed as -0, into zero
            if (double.IsPositiveInfinity(x))
                return x;
            // the rounding error made in forming 1 + x is cancelled by dividing by the same (u - 1)
            return Math.Log(u) * x / (u - 1.0);
        }

        /// <summary>1 + r1 + r1 r2 + r1 r2 r3 + ..., where ratio(j) is the jth ratio of successive terms (j = 1, 2, ...); stops when a term no longer counts.</summary>
        private static double TailSeries(Func<int, double> ratio)
        {
            double sum = 1.0, term = 1.0;
            for (int j = 1; j < 100000000; j++)
            {
                term *= ratio(j);
                if (term <= 0.0 || double.IsNaN(term))
                    break;
                sum += term;
                if (term < sum * 1.0E-17)
                    break;
            }
            return sum;
        }

        private static double LogPoissonTerm(double k, double mean)
        {
            return -mean + k * Math.Log(mean) - PDF.alogam(k + 1.0);
        }

        private static double LogBinomialTerm(double r, double n, double p)
        {
            return PDF.alogam(n + 1.0) - PDF.alogam(r + 1.0) - PDF.alogam(n - r + 1.0) + r * Math.Log(p) + (n - r) * Math.Log(1.0 - p);
        }

        /// <summary>
        /// The Poisson quantile: the smallest k with P(X &lt;= k) &gt;= p (for the upper tail, the smallest k with
        /// P(X &gt; k) &lt;= p), 0 for a mean of zero, infinity for a lower tail probability of 1.
        /// </summary>
        /// <remarks>
        /// The guard against rounding when p is exactly a tail value is RELATIVE to p. An absolute slack of 1e-13 was used
        /// here first, which made every p below 1e-13 return 0. The tail is compared with p on the scale p was given on - upper
        /// tail with upper tail, logarithm with logarithm - so a small upper tail is not lost in 1 - p, nor a tiny one in exp(p).
        /// The search brackets and bisects on k, the tail being monotone in k.
        /// </remarks>
        public static double Qpois(double p, double mean, bool lowerTail, bool logP)
        {
            if (double.IsNaN(p) || double.IsNaN(mean) || mean < 0.0 || p == Constant.MISSING || mean == Constant.MISSING)
                return Constant.MISSING;
            if (logP ? p > 0.0 : p < 0.0 || p > 1.0)
                return Constant.MISSING;
            if (mean == 0.0)
                return 0.0;
            double none = logP ? double.NegativeInfinity : 0.0, all = logP ? 0.0 : 1.0;
            if (p == (lowerTail ? none : all))
                return 0.0;
            if (p == (lowerTail ? all : none))
                return double.PositiveInfinity;

            // Rounding guard, so that a p which is exactly a tail value gives that count and not the next one. A fixed few
            // multiples of eps would suit tails good to 1e-15. The tails here carry the rounding of
            // exp(k ln(mean) - mean - lgamma(k + 1)), about eps times the size of those three parts (3e-11 with a mean of 10000),
            // and that error is relative to whichever tail is the smaller, the one computed directly; on the log scale it is an
            // absolute error in the logarithm of a small tail and a relative one in the logarithm of a tail near 1.
            const double eps = 2.220446049250313E-16;
            double logMean = Math.Abs(Math.Log(mean));
            double smallSide = logP ? Math.Min(1.0, Math.Abs(p)) : Math.Min(p, 1.0 - p);
            // true when k is at or beyond the quantile
            bool Reached(double k, out bool failed)
            {
                double tail = Ppois(k, mean, lowerTail, logP);
                failed = tail == Constant.MISSING || double.IsNaN(tail);
                double accuracy = 8.0 * eps * (1.0 + mean + (k + 1.0) * logMean + Math.Abs(PDF.alogam(k + 2.0)));
                double slack = accuracy * smallSide + 8.0 * eps * Math.Abs(p);
                if (lowerTail)
                    return tail >= p - slack;
                // an upper tail is not nudged past certainty, which every k would satisfy
                if (p + slack >= (logP ? 0.0 : 1.0))
                    slack = 0.0;
                return tail <= p + slack;
            }

            // bracket: low is short of the quantile (or is -1), high has reached it
            double low = -1.0;
            double high = Math.Max(1.0, Math.Ceiling(mean));
            bool failedHere;
            while (!Reached(high, out failedHere))
            {
                if (failedHere || high > 1.0E9)
                    return Constant.MISSING;
                low = high;
                high *= 2.0;
            }
            if (failedHere)
                return Constant.MISSING;
            while (high - low > 1.0)
            {
                double mid = Math.Floor((low + high) / 2.0);
                if (Reached(mid, out failedHere))
                    high = mid;
                else
                    low = mid;
                if (failedHere)
                    return Constant.MISSING;
            }
            return high;
        }

        public static double Pbinom(double r, double n, double p, bool lowerTail, bool logP)
        {
            double successes = Math.Floor(r), trials = Math.Floor(n);
            // P(X > r) = P(X >= r + 1), computed directly (see BinomialAtLeast); 1 - P(X <= r) lost small upper tails
            double upper = BinomialAtLeast(successes + 1.0, trials, p);
            if (upper == Constant.MISSING)
                return Constant.MISSING;
            double lower;
            if (successes < 0.0)
                lower = 0.0;
            else if (successes >= trials || p == 0.0)
                lower = 1.0;
            else if (p == 1.0)
                lower = 0.0; // fewer than n successes cannot happen; the engine's sum takes log(0) when p is 0 or 1
            else
            {
                ExFortran.bino((int)trials, p, (int)successes, out double _, out lower, out double _, out int fault);
                if (fault != 0)
                    return Constant.MISSING;
            }
            if (!logP)
                return lowerTail ? lower : upper;
            double smallLog = double.NaN;
            if (p > 0.0 && p < 1.0 && successes >= 0.0)
            {
                // the logarithm of a tail too small for a double, summed in log space from the probability of the nearest count
                double odds = p / (1.0 - p);
                if (!lowerTail && upper < TinyTail && successes + 1.0 <= trials)
                    smallLog = LogBinomialTerm(successes + 1.0, trials, p) + Math.Log(TailSeries(j => (trials - successes - j) / (successes + 1.0 + j) * odds));
                if (lowerTail && lower < TinyTail)
                    smallLog = LogBinomialTerm(successes, trials, p) + Math.Log(TailSeries(j => (successes - j + 1.0) / (trials - successes + j) / odds));
            }
            return LogOfTail(lowerTail ? lower : upper, lowerTail ? upper : lower, smallLog);
        }

        public static double Dbinom(double r, double n, double p, bool logP)
        {
            double successes = Math.Floor(r), trials = Math.Floor(n);
            ExFortran.bino((int)trials, p, (int)successes, out double dterm, out double _, out double _, out int fault);
            if (fault != 0)
                return Constant.MISSING;
            if (!logP)
                return dterm;
            // the logarithm of a probability too small for a double comes from the logarithm of the term, not from the 0 it became
            if (dterm < TinyTail && p > 0.0 && p < 1.0 && successes >= 0.0 && successes <= trials)
                return LogBinomialTerm(successes, trials, p);
            return Math.Log(dterm);
        }

        public static double Pchisq(double q, double df, bool lowerTail, bool logP)
        {
            // Each tail is computed as itself: the lower tail used to be 1 minus the upper, which lost a small one altogether
            // (PCHISQ(5, 100) was 0 where it is 2.2e-46). Chi-square cannot be negative, so everything lies above a negative q
            // (the engine's routine refuses one).
            double lower, upper;
            if (q < 0.0 && df > 0.0 && q != Constant.MISSING)
            {
                lower = 0.0;
                upper = 1.0;
            }
            else
            {
                upper = PDF.chivalp(q, df);
                lower = PDF.gammad(q / 2.0, df / 2.0, false, out int fault);
                if (fault != 0)
                    lower = double.NaN;
            }
            if (!logP)
                return lowerTail ? lower : upper;
            double tail = lowerTail ? lower : upper;
            double smallLog = double.NaN;
            if (tail < TinyTail && q > 0.0 && df > 0.0)
                smallLog = lowerTail ? LogGammaLowerTail(df / 2.0, q / 2.0) : LogGammaUpperTail(df / 2.0, q / 2.0);
            return LogOfTail(tail, lowerTail ? upper : lower, smallLog);
        }

        /// <summary>
        /// log of the lower incomplete gamma ratio P(a, x) from its series x^a e^-x / gamma(a + 1) (1 + x / (a + 1) + x^2 / ((a + 1)(a + 2)) + ...),
        /// for a tail too small for a double (x far below a)
        /// </summary>
        private static double LogGammaLowerTail(double a, double x)
        {
            return a * Math.Log(x) - x - PDF.alogam(a + 1.0) + Math.Log(TailSeries(j => x / (a + j)));
        }

        /// <summary>
        /// log of the upper incomplete gamma ratio Q(a, x) from x^(a - 1) e^-x / gamma(a) (1 + (a - 1) / x + (a - 1)(a - 2) / x^2 + ...),
        /// Abramowitz and Stegun 6.5.32, for a tail too small for a double (x beyond a). The terms fall while k is below a + x,
        /// and change sign once k passes a; for a whole number a the series ends and is exact.
        /// </summary>
        private static double LogGammaUpperTail(double a, double x)
        {
            double sum = 1.0, term = 1.0;
            for (int k = 1; k < 1000000; k++)
            {
                double next = term * (a - k) / x;
                if (next == 0.0 || Math.Abs(next) > Math.Abs(term))
                    break;
                term = next;
                sum += term;
                if (Math.Abs(term) < 1.0E-17 * Math.Abs(sum))
                    break;
            }
            return (a - 1.0) * Math.Log(x) - x - PDF.alogam(a) + Math.Log(sum);
        }

        public static double Qchisq(double p, double df, bool lowerTail, bool logP)
        {
            if (logP)
                p = Math.Exp(p);
            // a small upper tail area cannot survive 1 - p (INVCHI2TAIL(1, 1e-20) gave no answer): it is inverted as an upper tail
            if (!lowerTail && p < 1.0E-6)
                return ChiSquareFromUpperTail(p, df);
            if (!lowerTail)
                p = 1.0 - p;
            double result = PDF.ppchi2(p, df, out int fault);
            return fault != 0 ? Constant.MISSING : result;
        }

        /// <summary>The chi-square with upper tail area p, by bracketing and bisection on the upper tail itself; for a small p.</summary>
        private static double ChiSquareFromUpperTail(double p, double df)
        {
            // an area below the smallest normal double is refused: the tail is cut to 0 there, so every such area would give the
            // chi-square for 2.2e-308, and a subnormal area (the exp of a log p below -708.4) keeps too few digits to invert
            if (double.IsNaN(p) || double.IsNaN(df) || p < Constant.DBL_MIN || p >= 1.0 || df <= 0.0 || p == Constant.MISSING || df == Constant.MISSING)
                return Constant.MISSING;
            double low = 0.0, high = df + 10.0;
            for (int i = 0; ; i++)
            {
                double area = PDF.chivalp(high, df);
                if (double.IsNaN(area) || i > 1100)
                    return Constant.MISSING;
                if (area < p)
                    break;
                low = high;
                high *= 2.0;
            }
            for (int i = 0; i < 2000 && high - low > 1.0E-15 * high; i++)
            {
                double mid = 0.5 * (low + high);
                double area = PDF.chivalp(mid, df);
                if (double.IsNaN(area))
                    return Constant.MISSING;
                if (area > p)
                    low = mid;
                else
                    high = mid;
            }
            double chiSquare = 0.5 * (low + high);
            // the answer is given only if the tail area at it comes back as p (beyond about 1e12 degrees of freedom it does not)
            return Math.Abs(PDF.chivalp(chiSquare, df) - p) <= 1.0E-6 * p ? chiSquare : Constant.MISSING;
        }

        public static double Pf(double q, double df1, double df2, bool lowerTail, bool logP)
        {
            // fvalp is the upper tail area, I_x(df2 / 2, df1 / 2) at x = df2 / (df2 + df1 q), an argument formed without
            // subtraction. Up to F = 1 the lower tail is the same function with the arguments exchanged at
            // df1 q / (df2 + df1 q), also formed without subtraction; taken as 1 minus the upper tail it lost a small lower tail
            // altogether (PF(0.001, 40, 10) was 0 where it is 1.1e-44). Beyond F = 1 that argument closes on 1 and loses its
            // figures, and the lower tail is 1 minus the upper, which cannot lose anything there. F cannot be negative, so
            // everything lies above a negative q.
            // A missing value is a huge negative sentinel, not a number to take a tail area of (QF and INVFTAIL return it when
            // they give no answer): with 1 degree of freedom it came out as a lower tail of exactly 1.
            if (q == Constant.MISSING || df1 == Constant.MISSING || df2 == Constant.MISSING)
                return Constant.MISSING;
            double lower, upper;
            if (q < 0.0 && q != Constant.MISSING && df1 > 0.0 && df2 > 0.0)
            {
                lower = 0.0;
                upper = 1.0;
            }
            else
            {
                upper = PDF.fvalp(q, df1, df2);
                if (q > 1.0)
                    lower = 1.0 - upper;
                else
                {
                    lower = PDF.betain(df1 * q / (df2 + df1 * q), df1 / 2.0, df2 / 2.0, out int fault);
                    lower = fault != 0 ? double.NaN : lower + 0.0; // + 0.0: a negative zero q comes back as -0, which would be displayed as -0
                }
            }
            if (!logP)
                return lowerTail ? lower : upper;
            return LogOfTail(lowerTail ? lower : upper, lowerTail ? upper : lower, double.NaN);
        }

        public static double Qf(double p, double df1, double df2, bool lowerTail, bool logP)
        {
            if (logP)
                p = Math.Exp(p);
            // A small tail area (below 1e-6) is inverted as itself: turned into the other tail and back it was lost, and the
            // engine routine loses accuracy there and then gives no answer. A small lower tail area is the upper tail area of
            // 1 / F with the degrees of freedom exchanged.
            if (p > 0.0 && p < 1.0E-6)
                return lowerTail ? Reciprocal(FFromUpperTail(p, df2, df1)) : FFromUpperTail(p, df1, df2);
            // Otherwise the engine routine, ffromp(denominator df, numerator df, upper tail area), as before - but its answer is
            // kept only if the tail area at it comes back as asked. For some arguments it does not: a lower tail area of 1.1e-6
            // with 1 and 1000 degrees of freedom gave a negative F, and an upper tail area of 0.0005 with 1 and 1e8 gave 3.34
            // where F is 12.12. Those are inverted directly. An area of 0 or 1, or arguments the routine refuses, are left to it.
            double upper = lowerTail ? 1.0 - p : p, lower = lowerTail ? p : 1.0 - p;
            double f = PDF.ffromp(df2, df1, upper);
            if (!(upper > 0.0 && upper < 1.0 && df1 > 0.0 && df2 > 0.0))
                return f;
            if (FGivesTail(f, upper, lower, df1, df2))
                return f;
            double direct = upper <= lower ? FFromUpperTail(upper, df1, df2) : Reciprocal(FFromUpperTail(lower, df2, df1));
            if (direct != Constant.MISSING)
                return direct;
            return Constant.MISSING;
        }

        private static double Reciprocal(double f)
        {
            return f == Constant.MISSING ? Constant.MISSING : 1.0 / f;
        }

        /// <summary>true when the smaller of the two tail areas at f is the one asked for, to 9 figures</summary>
        private static bool FGivesTail(double f, double upper, double lower, double dfn, double dfd)
        {
            if (!(f > 0.0) || double.IsInfinity(f))
                return false;
            double want = Math.Min(upper, lower), got;
            if (upper <= lower)
                got = PDF.fvalp(f, dfn, dfd);
            else
            {
                got = PDF.betain(dfn * f / (dfd + dfn * f), dfn / 2.0, dfd / 2.0, out int fault);
                if (fault != 0)
                    return false;
            }
            return Math.Abs(got - want) <= 1.0E-9 * want;
        }

        /// <summary>
        /// The F with upper tail area p, by bisection on the logarithm of F from e^-700 up to the largest F at which the tail
        /// area can be formed: 0 when even e^-700 leaves less than p above it; infinity when the largest double still leaves
        /// more (which can be told only with a numerator of 1 degree of freedom or less; otherwise no answer). The answer is
        /// given only if the tail area at it comes back as p. An area below the smallest normal double is refused: it keeps too
        /// few digits to invert.
        /// </summary>
        private static double FFromUpperTail(double p, double dfn, double dfd)
        {
            if (double.IsNaN(p) || double.IsNaN(dfn) || double.IsNaN(dfd) || p < Constant.DBL_MIN || p >= 1.0 || dfn <= 0.0 || dfd <= 0.0 || p == Constant.MISSING)
                return Constant.MISSING;
            // each tail area takes time in proportion to the degrees of freedom, and some sixty are needed: beyond two million a
            // single answer would take many seconds, so none is given (a chi-square quantile over its degrees of freedom serves there)
            if (dfn > 2.0E6 || dfd > 2.0E6)
                return Constant.MISSING;
            // ln F. The top is the largest F at which the tail area can be formed: fvalp takes dfd / (dfd + dfn F), and once dfn F
            // overflows that is exactly 0 and the bisection would settle on the overflow point. 709.78 is just under ln of the largest double.
            double low = -700.0, high = 709.78 - Math.Log(Math.Max(1.0, dfn));
            double atLow = PDF.fvalp(Math.Exp(low), dfn, dfd), atHigh = PDF.fvalp(Math.Exp(high), dfn, dfd);
            if (double.IsNaN(atLow) || double.IsNaN(atHigh))
                return Constant.MISSING;
            if (atLow <= p)
                return 0.0;
            if (atHigh >= p)
                return dfn <= 1.0 ? double.PositiveInfinity : Constant.MISSING;
            for (int i = 0; i < 200 && high - low > 1.0E-15 * Math.Max(1.0, Math.Abs(low) + Math.Abs(high)); i++)
            {
                double mid = 0.5 * (low + high);
                double area = PDF.fvalp(Math.Exp(mid), dfn, dfd);
                if (double.IsNaN(area))
                    return Constant.MISSING;
                if (area > p)
                    low = mid;
                else
                    high = mid;
            }
            double f = Math.Exp(0.5 * (low + high));
            // where the tail area itself jumps (far fewer than one degree of freedom) the bisection settles on the jump: no answer then
            return Math.Abs(PDF.fvalp(f, dfn, dfd) - p) <= 1.0E-6 * p ? f : Constant.MISSING;
        }

        // Unary minus for the expression evaluator. A missing value, which is a huge negative sentinel, stays missing: a plain
        // minus sign would turn it into +1.8E308, which nothing downstream recognises as missing.
        public static int Negate(int value)
        {
            return 0 - value;
        }

        public static double Negate(double value)
        {
            return value == Constant.MISSING ? value : 0.0 - value; // 0 - x, not -x: the negative of zero is zero, not the IEEE "-0"
        }

        public static double Idiv(double numerator, double denominator)
        {
            // Integer division: both operands lose their fractions, then so does the quotient. In doubles, because (int) casts
            // threw for a divisor between -1 and 1 (stopping a whole worksheet column) and saturated above 2^31.
            if (numerator == Constant.MISSING || denominator == Constant.MISSING || double.IsNaN(numerator) || double.IsNaN(denominator))
                return Constant.MISSING;
            double n = Math.Truncate(numerator), d = Math.Truncate(denominator);
            return d == 0.0 ? Constant.MISSING : Math.Truncate(n / d);
        }
    }
}
