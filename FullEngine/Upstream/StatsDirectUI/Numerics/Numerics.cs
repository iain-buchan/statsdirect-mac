namespace StatsDirect.Numerics
{
    using System;
    public static class Constant
    {
        /// <summary>
        /// smallest positive magnitude [SPREAL]
        /// </summary>
        public const double DBL_MIN = 2.2250738585072014E-308;
        /// <summary>
        /// largest relative spacing [EPSILON]
        /// </summary>
        public const double DBL_LRS = 2.22044604925031308085E-016;
        /// <summary>
        /// smallest relative spacing [EPSNEG]
        /// </summary>
        public const double DBL_SRS = 1.11022302462515654042E-016;
        /// <summary>
        /// log(DBL_MAX)
        /// </summary>
        public const double MAXEXP = 709.78271289338399672;

        public const double PI = 3.1415926535897932384626433832795028841971693993751d;
        public const double SQRTPI = 1.7724538509055160272981674833411451827975494561224d;
        /// <summary>
        /// log(sqrt(pi*2))
        /// </summary>
        public const double SQ2PIL = 0.918938533204672741780329736405617639861397473637;
        /// <summary>
        /// log(sqrt(pi/2))
        /// </summary>
        public const double SQPI2L = 0.225791352644727432363097614947441071785897339277;

        /// <summary>
        /// missing data value
        /// </summary>
        /// <remarks>was 1E+300 in SD2</remarks>
        public const double MISSING = double.MinValue;

        /// <summary>
        /// largest relative spacing of doubles = B**(-MACHEP)
        /// </summary>
        public const double EPSNEG = DBL_SRS;
        /// <summary>
        /// smallest positive double = B**(EMIN-1)
        /// </summary>
        public const double SPREAL = DBL_MIN;
        /// <summary>
        /// smallest relative spacing of doubles = B**(-D)
        /// </summary>
        public const double EPSILON = DBL_LRS;
    }

    /// <summary>
    /// Core numerical functions for .Net statistical algorithms, Iain Buchan, July 2003.
    /// </summary>
    public static class Base
    {
        /// <summary>
        /// Default seed for random number generators.
        /// </summary>
        public static int DefaultSeed()
        {
            return Environment.TickCount;
        }

        /// <summary>
        /// Sign transfer b to a (FORTRAN compatability).
        /// </summary>
        public static double dsign(double a, double b) => b < 0.0 ? -Math.Abs(a) : Math.Abs(a);

        /// <summary>
        /// Integer rounding function (FORTRAN compatability)
        /// </summary>
        public static double dnint(double a) => a > 0.0 ? (int)(a + 0.5) : (int)(a - 0.5);

        /// <summary>
        /// Safe Exponent
        /// </summary>
        /// <returns>double.MaxValue if this would overflow, otherwise Math.Exp(x)</returns>
        public static double SafeExp(double x) => x > Constant.MAXEXP ? double.MaxValue : Math.Exp(x);

        /// <summary>
        /// Safe square root (was Safe_Sqr in SD2).
        /// </summary>
        public static double SafeSqrt(double x) => x > 0.0 ? Math.Sqrt(x) : Constant.MISSING;

        /// <summary>
        /// Number of terms for 64 bit orthogonal series; error within eta.
        /// </summary>
        /// <remarks>
        /// Ref: R. Broucke, Algorithm 446, CACM., 16, 254 (1973).
        /// </remarks>
        public static int chebyinit(double[] cs, int n, double eta)
        {
            if (n < 1)
                return 0;

            double err = 0.0;
            int i = 0;
            for (int j = 1; j <= n; j++)
            {
                i = n - j;
                err += Math.Abs(cs[i]);
                if (err > eta)
                    return i;
            }
            return i;
        }

        /// <summary>
        /// Evaluate the n term Chebyshev series in a[].
        /// </summary>
        /// <remarks>
        /// Ref: R. Broucke, Algorithm 446, CACM., 16, 254 (1973).
        /// </remarks>
        public static double cheby(double x, double[] a, int n)
        {
            if (n < 1 || n > 1000) return double.NaN;
            if (x < -1.1 || x > 1.1) return double.NaN;
            double twox = x * 2;
            double b2 = 0;
            double b1 = 0;
            double b0 = 0;
            for (int i = 1; i <= n; i++)
            {
                b2 = b1;
                b1 = b0;
                b0 = twox * b1 - b2 + a[n - i];
            }
            return (b0 - b2) * 0.5;
        }

        /// <summary>
        /// Relative error logarithm log(1 + x).
        /// </summary>
        /// <remarks>
        /// Ref: netlib.org DLNREL algorithm by W. Fullerton of Los Alamos Scientific Laboratory.
        /// </remarks>
        public static double log1p(double x)
        {
            /* series for log1p on the interval -.375 to .375
                 *		          with weighted error   6.35e-32
                 *		           log weighted error  31.20
                 *		 significant figures required  30.93
                 *			  decimal places required  32.01
                 */

            // Chebychev series for log relative error log1p
            double[] alnrcs = {
								  +.10378693562743769800686267719098e+1,
								  -.13364301504908918098766041553133e+0,
								  +.19408249135520563357926199374750e-1,
								  -.30107551127535777690376537776592e-2,
								  +.48694614797154850090456366509137e-3,
								  -.81054881893175356066809943008622e-4,
								  +.13778847799559524782938251496059e-4,
								  -.23802210894358970251369992914935e-5,
								  +.41640416213865183476391859901989e-6,
								  -.73595828378075994984266837031998e-7,
								  +.13117611876241674949152294345011e-7,
								  -.23546709317742425136696092330175e-8,
								  +.42522773276034997775638052962567e-9,
								  -.77190894134840796826108107493300e-10,
								  +.14075746481359069909215356472191e-10,
								  -.25769072058024680627537078627584e-11,
								  +.47342406666294421849154395005938e-12,
								  -.87249012674742641745301263292675e-13,
								  +.16124614902740551465739833119115e-13,
								  -.29875652015665773006710792416815e-14,
								  +.55480701209082887983041321697279e-15,
								  -.10324619158271569595141333961932e-15,
								  +.19250239203049851177878503244868e-16,
								  -.35955073465265150011189707844266e-17,
								  +.67264542537876857892194574226773e-18,
								  -.12602624168735219252082425637546e-18,
								  +.23644884408606210044916158955519e-19,
								  -.44419377050807936898878389179733e-20,
								  +.83546594464034259016241293994666e-21,
								  -.15731559416479562574899253521066e-21,
								  +.29653128740247422686154369706666e-22,
								  -.55949583481815947292156013226666e-23,
								  +.10566354268835681048187284138666e-23,
								  -.19972483680670204548314999466666e-24,
								  +.37782977818839361421049855999999e-25,
								  -.71531586889081740345038165333333e-26,
								  +.13552488463674213646502024533333e-26,
								  -.25694673048487567430079829333333e-27,
								  +.48747756066216949076459519999999e-28,
								  -.92542112530849715321132373333333e-29,
								  +.17578597841760239233269760000000e-29,
								  -.33410026677731010351377066666666e-30,
								  +.63533936180236187354180266666666e-31};

            double xmin = -1.0 + Math.Sqrt(1.0 / Constant.DBL_LRS);

            const int nlnrel = 22;
            // for IEEE 64 bit

            if (x == 0.0) return 0.0;
            if (x == -1.0) return double.NegativeInfinity;
            if (x < -1.0) return double.NaN;

            if (Math.Abs(x) <= .375)
            {
                if (Math.Abs(x) < .5 * Constant.DBL_LRS) return x;
                if (0.0 < x && x < 1e-8 || -1e-9 < x && x < 0.0) return x * (1.0 - .5 * x);
                return x * (1.0 - x * cheby(x / .375, alnrcs, nlnrel));
            }
            if (x < xmin)
            {
                // low precision; x too close to -1
            }
            return Math.Log(1.0 + x);
        }

        /// <summary>
        /// Compute the Exponential minus 1 (note: due in C99 math library)
        /// </summary>
        public static double expm1(double x)
        {
            double y, a = Math.Abs(x);

            if (a < Constant.DBL_LRS)
                return x;
            if (a > 0.697)
                return Math.Exp(x) - 1.0;

            if (a > 1e-8)
            {
                y = Math.Exp(x) - 1.0;
            }
            else
            {
                y = (x / 2.0 + 1.0) * x;
            }
            y -= (1.0 + y) * (log1p(y) - x);
            return y;
        }
    } //end of Base class

    /// <summary>
    /// Basic probability distribution functions
    /// </summary>
    public static class PDF
    {
        /// <summary>
        /// normal deviate Z for a given lower tail area of P; Z is accurate to about 1 part in 10**16.  This version is for the many users who are not interested in ifault.
        /// </summary>
        /// <remarks>
        /// Wichura MJ. Algorithm AS 241: The Percentage Points of the Normal Distribution.
        /// Applied Statistics 1988, 37, 477-484.
        /// </remarks>
        public static double gauinv(double p) => gauinv(p, out int _);

        /// <summary>
        /// normal deviate Z for a given lower tail area of P; Z is accurate to about 1 part in 10**16.
        /// </summary>
        /// <remarks>
        /// Wichura MJ. Algorithm AS 241: The Percentage Points of the Normal Distribution.
        /// Applied Statistics 1988, 37, 477-484.
        /// </remarks>
        public static double gauinv(double p, out int ifault)
        {
            const double
                      zero = 0.0,
                      one = 1.0,
                      half = 0.50,
                      split1 = 0.4250,
                      split2 = 5.0,
                      const1 = 0.1806250,
                      const2 = 1.6,
                      a0 = 3.3871328727963666080,
                      a1 = 1.3314166789178437745e+2,
                      a2 = 1.9715909503065514427e+3,
                      a3 = 1.3731693765509461125e+4,
                      a4 = 4.5921953931549871457e+4,
                      a5 = 6.7265770927008700853e+4,
                      a6 = 3.3430575583588128105e+4,
                      a7 = 2.5090809287301226727e+3,
                      b1 = 4.2313330701600911252e+1,
                      b2 = 6.8718700749205790830e+2,
                      b3 = 5.3941960214247511077e+3,
                      b4 = 2.1213794301586595867e+4,
                      b5 = 3.9307895800092710610e+4,
                      b6 = 2.8729085735721942674e+4,
                      b7 = 5.2264952788528545610e+3,
                      c0 = 1.42343711074968357734,
                      c1 = 4.63033784615654529590,
                      c2 = 5.76949722146069140550,
                      c3 = 3.64784832476320460504,
                      c4 = 1.27045825245236838258,
                      c5 = 2.41780725177450611770e-1,
                      c6 = 2.27238449892691845833e-2,
                      c7 = 7.74545014278341407640e-4,
                      d1 = 2.05319162663775882187,
                      d2 = 1.67638483018380384940,
                      d3 = 6.89767334985100004550e-1,
                      d4 = 1.48103976427480074590e-1,
                      d5 = 1.51986665636164571966e-2,
                      d6 = 5.47593808499534494600e-4,
                      d7 = 1.05075007164441684324e-9,
                      e0 = 6.65790464350110377720,
                      e1 = 5.46378491116411436990,
                      e2 = 1.78482653991729133580,
                      e3 = 2.96560571828504891230e-1,
                      e4 = 2.65321895265761230930e-2,
                      e5 = 1.24266094738807843860e-3,
                      e6 = 2.71155556874348757815e-5,
                      e7 = 2.01033439929228813265e-7,
                      f1 = 5.99832206555887937690e-1,
                      f2 = 1.36929880922735805310e-1,
                      f3 = 1.48753612908506148525e-2,
                      f4 = 7.86869131145613259100e-4,
                      f5 = 1.84631831751005468180e-5,
                      f6 = 1.42151175831644588870e-7,
                      f7 = 2.04426310338993978564e-15;
            double r;

            ifault = 0;
            double q = p - half;
            if (Math.Abs(q) <= split1)
            {
                r = const1 - q * q;
                return q * (((((((a7 * r + a6) * r + a5) * r + a4) * r + a3)
                    * r + a2) * r + a1) * r + a0) /
                    (((((((b7 * r + b6) * r + b5) * r + b4) * r + b3)
                    * r + b2) * r + b1) * r + one);
            }
            if (q < zero)
                r = p;
            else
                r = one - p;

            if (r <= zero)
            {
                ifault = 1;
                return zero;
            }
            r = Math.Sqrt(-Math.Log(r));
            double val;
            if (r <= split2)
            {
                r -= const2;
                val = (((((((c7 * r + c6) * r + c5) * r + c4) * r + c3)
                         * r + c2) * r + c1) * r + c0) /
                      (((((((d7 * r + d6) * r + d5) * r + d4) * r + d3)
                         * r + d2) * r + d1) * r + one);
            }
            else
            {
                r -= split2;
                val = (((((((e7 * r + e6) * r + e5) * r + e4) * r + e3)
                         * r + e2) * r + e1) * r + e0) /
                      (((((((f7 * r + f6) * r + f5) * r + f4) * r + f3)
                         * r + f2) * r + f1) * r + one);
            }
            if (q < zero)
                val = -val;
            return val;
        }

        /// <summary>
        /// log of the absolute value of the gamma function
        /// </summary>
        /// <remarks>
        /// December 2003 Iain Buchan C# translation and adaptation
        /// August 1980 edition. W. Fullerton, c3, Los Alamos scientific lab.
        /// </remarks>
        public static double alogam(double x)
        {
            double xMax = double.MaxValue / Math.Log(double.MaxValue);
            double absX = Math.Abs(x);
            if (absX <= 10.0)
            {
                double dabsgx = Math.Abs(dgamma(x));
                return Math.Log(dabsgx);
            }
            if (absX > xMax)
                return double.NaN; // Overflow
            if (x > 0.0)
                return Constant.SQ2PIL + (x - 0.5) * Math.Log(x) - x + d9lgmc(absX);

            double sinPiAbsX = Math.Abs(Math.Sin(Constant.PI * absX));
            if (sinPiAbsX == 0.0)
                return double.NaN; // -ve argument

            // if (Math.Abs((x-dint(x-0.5))*alogam/x) < dxrel)
            //     low precision
            return Constant.SQPI2L + (x - 0.5) * Math.Log(absX) - x - Math.Log(sinPiAbsX) - d9lgmc(absX);
        }

        /// <summary>
        /// compute the log gamma correction factor for x .ge. 10. so that
        /// dlog (dgamma(x)) = dlog(dsqrt(2*pi)) + (x-.5)*dlog(x) - x + d9lgmc(x)
        /// </summary>
        /// <remarks>
        /// december 2003 iain buchan C# translation and adaptation
        /// august 1977 edition. w. fullerton, c3, los alamos scientific lab
        /// </remarks>
        private static double d9lgmc(double x)
        {
            if (x < 10.0)
                return double.NaN; // x must be > 10

            // series for algm on the interval  0. to  1.00000e-02
            //                      with weighted error   1.28e-31
            //                           log weighted error  30.89
            //                 significant figures required  29.81
            //                      decimal places required  31.48
            //
            double[] algmcs =
            {
				+0.166638948045186324720572965082e+0,
				-0.1384948176067563840732986059135e-4,
				+0.9810825646924729426157171547487e-8,
				-0.1809129475572494194263306266719e-10,
				+0.6221098041892605227126015543416e-13,
				-0.3399615005417721944303330599666e-15,
				+0.2683181998482698748957538846666e-17,
				-0.2868042435334643284144622399999e-19,
				+0.3962837061046434803679306666666e-21,
				-0.6831888753985766870111999999999e-23,
				+0.1429227355942498147573333333333e-24,
				-0.3547598158101070547199999999999e-26,
				+0.1025680058010470912000000000000e-27,
				-0.3401102254316748799999999999999e-29,
				+0.1276642195630062933333333333333e-30
            };

            // IEEE 64-bit Chebyshev orthogonal series = 5
            // for other systems call nalgm=Base.chebyinit(algmcs,15,Defs.DBL_SRS)
            const int nalgm = 5;
            double
                xbig = 1.0 / Math.Sqrt(Constant.DBL_SRS),
                xmax = Math.Exp(Math.Min(Math.Log(double.MaxValue / 12.0), -Math.Log(12.0 * Constant.DBL_SRS)));

            if (x < xmax)
            {
                if (x >= xbig)
                    return 1.0 / (12.0 * x);
                else
                    return Base.cheby(2.0 * Math.Pow(10.0 / x, 2.0) - 1.0, algmcs, nalgm) / x;
            }

            //  underflow
            return 0.0;
        }

        ///<summary>
        // june 2003 iain buchan f90 translation and adaptation
        // jan 1984 edition.  w. fullerton, c3, los alamos scientific lab.
        // jan 1994 wpp@ips.id.ethz.ch, ehg@research.att.com   declare xsml
        // complete gamma function
        ///</summary>
        public static double dgamma(double x)
        {
            // series for gam on the interval 0. to  1.00000e+00
            //                    with weighted error   5.79e-32
            //                         log weighted error  31.24
            //               significant figures required  30.00
            //                    decimal places required  32.05
            double[] gamcs = {	 0.8571195590989331421920062399942e-2,
								 0.4415381324841006757191315771652e-2,
								 0.5685043681599363378632664588789e-1,
								 -0.4219835396418560501012500186624e-2,
								 0.1326808181212460220584006796352e-2,
								 -0.1893024529798880432523947023886e-3,
								 0.3606925327441245256578082217225e-4,
								 -0.6056761904460864218485548290365e-5,
								 0.1055829546302283344731823509093e-5,
								 -0.1811967365542384048291855891166e-6,
								 0.3117724964715322277790254593169e-7,
								 -0.5354219639019687140874081024347e-8,
								 0.9193275519859588946887786825940e-9,
								 -0.1577941280288339761767423273953e-9,
								 0.2707980622934954543266540433089e-10,
								 -0.4646818653825730144081661058933e-11,
								 0.7973350192007419656460767175359e-12,
								 -0.1368078209830916025799499172309e-12,
								 0.2347319486563800657233471771688e-13,
								 -0.4027432614949066932766570534699e-14,
								 0.6910051747372100912138336975257e-15,
								 -0.1185584500221992907052387126192e-15,
								 0.2034148542496373955201026051932e-16,
								 -0.3490054341717405849274012949108e-17,
								 0.5987993856485305567135051066026e-18,
								 -0.1027378057872228074490069778431e-18,
								 0.1762702816060529824942759660748e-19,
								 -0.3024320653735306260958772112042e-20,
								 0.5188914660218397839717833550506e-21,
								 -0.8902770842456576692449251601066e-22,
								 0.1527474068493342602274596891306e-22,
								 -0.2620731256187362900257328332799e-23,
								 0.4496464047830538670331046570666e-24,
								 -0.7714712731336877911703901525333e-25,
								 0.1323635453126044036486572714666e-25,
								 -0.2270999412942928816702313813333e-26,
								 0.3896418998003991449320816639999e-27,
								 -0.6685198115125953327792127999999e-28,
								 0.1146998663140024384347613866666e-28,
								 -0.1967938586345134677295103999999e-29,
								 0.3376448816585338090334890666666e-30,
								 -0.5793070335782135784625493333333e-31};

            // IEEE 64-bit Chebyshev orthogonal series = 22
            // for other systems call ngamcs = Base.chebyinit(gamcs,42,0.1*Defs.DBL_SRS)
            const int ngamcs = 22;
            // IEEE 64-bit values for xmin and xmax are fixed here
            // for other systems call d9gaml(ref xmin, ref xmax)
            const double
                      xmax = 171.61447887182297,
                      xmin = -170.56749727266123;
            double
                ret,
                // dxrel = Math.Sqrt(Constant.DBL_LRS),
                xsml = Math.Exp(Math.Max(Math.Log(Constant.DBL_MIN), -Math.Log(double.MaxValue)) + 0.01);

            double y = Math.Abs(x);
            if (y <= 10.0)
            {
                // compute gamma(x) for -xbnd  <=  x  <=  xbnd.  reduce interval and find gamma(1+y) for 0.0  <=  y  <  1.0 first of all.
                int n = (int)x;
                if (x < 0.0) n -= 1;
                double xn = n;
                y = x - xn;
                n -= 1;
                ret = 0.9375 + Base.cheby(2.0 * y - 1.0, gamcs, ngamcs);
                if (n == 0) return ret;
                double xi;
                int i;
                if (n <= 0)
                {
                    n = -n;
                    if (x == 0.0) return double.NaN;
                    // compute gamma(x) for x  <  1.0
                    if (y < xsml) return double.NaN;
                    xn = n - 2;
                    if (x < 0.0 & x + xn == 0.0) return double.NaN;
                    //  if (x < -0.5 .and. Math.Abs((x-dint(x-0.5))/x) < dxrel) then low precision
                    xi = 0.0;
                    for (i = 1; i <= n; i++)
                    {
                        ret /= (x + xi);
                        xi += 1.0;
                    }
                    return ret;
                }
                // gamma(x) for x  >=  2.0 and x  <=  10.0
                xi = 1.0;
                for (i = 1; i <= n; i++)
                {
                    ret = (y + xi) * ret;
                    xi += 1.0;
                }
                return ret;
            }
            if (x > xmax) return double.NaN;
            ret = 0.0;
            if (x < xmin) return ret;
            ret = Math.Exp((y - 0.5) * Math.Log(y) - y + Constant.SQ2PIL + d9lgmc(y));
            if (x > 0.0) return ret;
            // if (Math.Abs((x-dint(x-0.5))/x)  <  dxrel) then low precision
            double sinpiy = Math.Sin(Constant.PI * y);
            if (sinpiy == 0.0) return double.NaN;
            ret = -Constant.PI / (y * sinpiy * ret);
            return ret;
        }

        /*///<summary>
        /// june 2003 iain buchan f90 translation and adaptation
        /// june 1977 edition.   w. fullerton, c3, los alamos scientific lab.
        ///
        /// calculate the minimum and maximum legal bounds for x in gamma(x).
        /// xmin and xmax are not the only bounds, but they are the only non-
        /// trivial ones to calculate.
        ///
        ///             output arguments --
        /// xmin   dble prec minimum legal value of x in gamma(x).  any smaller
        ///        value of x might result in underflow.
        /// xmax   dble prec maximum legal value of x in gamma(x).  any larger
        ///        value of x might cause overflow.
        ///</summary>
        private static void d9gaml (ref double xmin, ref double xmax)
        {
            int i;
            double xold, xln;
            double alnsml = Math.Log(Defs.DBL_MIN);
            double alnbig = Math.Log(Defs.DBL_MAX);
            xmin = double.NaN;
            xmax = double.NaN;
            xmin = -alnsml;
            for (i=1; i<=10; i++)
            {
                xold = xmin;
                xln = Math.Log(xmin);
                xmin = xmin - xmin*((xmin+0.5)*xln-xmin-.2258+alnsml)/(xmin*xln+0.5);
                if (Math.Abs(xmin-xold) < 0.005) break;
            }
            if (i >= 10)
            {
                xmin = double.NaN;
                return;
            }
            xmin = -xmin + 0.01;
            xmax = alnbig;
            for (i=1; i<=11; i++)
            {
                xold = xmax;
                xln = Math.Log(xmax);
                xmax = xmax - xmax*((xmax-0.5)*xln-xmax+.9189-alnbig)/(xmax*xln-0.5);
                if (Math.Abs(xmax-xold) < 0.005) break;
            }
            if (i >= 10)
            {
                xmax = double.NaN;
                return;
            }
            xmax = xmax - 0.01;
            xmin = Math.Max(xmin,-xmax+1.0);
            return;
        }*/

        /// <summary>
        /// computes incomplete beta function ratio for arguments
        /// x between zero and one, p and q positive.
        /// log of complete beta function, beta, assumed to be known.
        /// calculation of beta added
        /// </summary>
        /// <remarks>
        /// algorithm as 63  appl.statist. (1973), vol.22, no.3
        /// modified as per remark asr 19  (1977), vol.26, no. 1
        /// </remarks>
        public static double betain(double x, double p, double q, out int ifault)
        {
            bool index;
            double xx, pp, qq;

            //        define accuracy and initialize

            const double acu = 0.1e-15;
            double ret = x;

            //        test for admissibility of arguments

            ifault = 1;
            if (double.IsNaN(p) || double.IsNaN(q) || p <= 0.0 || q <= 0.0)
                return ret;
            ifault = 2;
            if (double.IsNaN(x) || x < 0.0 || x > 1.0)
                return ret;
            ifault = 0;
            if (x == 0.0 || x == 1.0)
                return ret;

            //     change tail if necessary and determine s

            double psq = p + q;
            double cx = 1.0 - x;
            if (p < psq * x)
            {
                xx = cx;
                cx = x;
                pp = q;
                qq = p;
                index = true;
            }
            else
            {
                xx = x;
                pp = p;
                qq = q;
                index = false;
            }
            double term = 1.0;
            double ai = 1.0;
            ret = 1.0;
            double zs = Base.dnint(qq + cx * psq);
            //
            //        use soper's reduction formulae
            //
            double rx = xx / cx;
            double temp = qq - ai;
            if (zs == 0.0) rx = xx;
            while (true)
            {
                term = term * temp * rx / (pp + ai);
                ret += term;
                temp = Math.Abs(term);
                if (temp <= acu & temp <= acu * ret)
                    break;
                ai += 1.0;
                zs -= 1.0;
                if (zs >= 0.0)
                {
                    temp = qq - ai;
                    if (zs == 0.0)
                        rx = xx;
                }
                else
                {
                    temp = psq;
                    psq += 1.0;
                }
            }

            //        calculate result

            double beta = alogam(p) + alogam(q) - alogam(p + q);
            ret = ret * Math.Exp(pp * Math.Log(xx) + (qq - 1.0) * Math.Log(cx) - beta) / pp;
            if (index)
                ret = 1.0 - ret;
            return ret;
        }

        /// <summary>	
        ///     Root finding by secant and modified Illinois method
        ///     AS 109 and AS 64 not stable  
        /// </summary>
        public static double xinbta(double pin, double qin, double p, out int ifault)
        {
            double x2, f2;
            double ret = double.NaN;
            if (pin <= 0.0)
            {
                ifault = 1;
                return ret;
            }
            if (qin <= 0.0)
            {
                ifault = 2;
                return ret;
            }
            if (p <= 0.0 || p > 1.0)
            {
                ifault = 3;
                return ret;
            }
            double x1 = p;
            double f1 = betain(x1, pin, qin, out ifault) - p;
            if (f1 == 0.0)
            {
                x2 = x1;
                return (x1 + x2) * 0.5;
            }
            x2 = p + 0.05;
            double xd = 0.05;
            if (x2 <= 0.0)
                f2 = -p;
            else if (x2 >= 1.0)
                f2 = 1.0 - p;
            else
                f2 = betain(x2, pin, qin, out ifault) - p;

            double slope = Math.Max(0.01, (f2 - f1) / xd);
            double delta = -f1 / slope;
            int iter = 0;
            while (true)
            {
                delta *= 2.0;
                iter++;
                if (iter > 100)
                {
                    x2 = 1.0;
                    break;
                }
                x2 = x1 + delta;
                if (x2 <= 0.0)
                    f2 = -p;
                else if (x2 >= 1.0)
                    f2 = 1.0 - p;
                else
                    f2 = betain(x2, pin, qin, out ifault) - p;

                if (f1 * f2 >= 0.0)
                    x1 = x2;
                else
                    break;
            }

            bool ibisec = false;
            ifault = 4;
            for (iter = 1; iter <= 100; iter++)
            {
                double xm = (x1 + x2) * 0.5;
                double fd = f2 - f1;
                xd = x2 - x1;
                if (xm != 0.0)
                {
                    if (Math.Abs(xd) < Math.Abs(xm * Constant.DBL_LRS))
                    {
                        ifault = 0;
                        break;
                    }
                }
                else
                {
                    if (Math.Abs(xd) < Constant.DBL_LRS)
                    {
                        ifault = 0;
                        break;
                    }
                }
                double x3 = ibisec ? xm : x2 - f2 * xd / fd;
                ibisec = false;

                double f3;
                if (x3 <= 0.0)
                    f3 = -p;
                else if (x3 >= 1.0)
                    f3 = 1.0 - p;
                else
                    f3 = betain(x3, pin, qin, out ifault) - p;
                if (f3 * f2 <= 0.0)
                {
                    x1 = x2;
                    f1 = f2;
                    x2 = x3;
                    f2 = f3;
                }
                else
                {
                    x2 = x3;
                    f2 = f3;
                    f1 *= 0.5;
                    if (Math.Abs(f2) > Math.Abs(f1))
                    {
                        f1 = 2.0 * f1;
                        ibisec = true;
                    }
                }
            }
            return (x1 + x2) * 0.5;
        }

        /// <summary>
        /// F (variance ratio) quantile from a tail area
        /// </summary>
        public static double ffromp(double dfd, double dfn, double p)
        {
            double a = dfd / 2.0;
            double b = dfn / 2.0;
            double ret = xinbta(a, b, p, out int ifault);
            if (ifault != 0)
                ret = double.NaN;
            else
                ret = (1.0 / ret - 1.0) * dfd / dfn;
            return ret;
        }

        /// <summary>
        /// Lower tail area for F (variance ratio)
        /// </summary>
        public static double fvalp(double f, double dfn, double dfd)
        {
            double ret = betain(dfd / (dfd + dfn * f), dfd / 2.0, dfn / 2.0, out int fault);
            if (fault != 0)
                ret = double.NaN;
            return ret;
        }

        /// <summary>
        /// Student t quantile from a lower tail area
        /// </summary>
        public static double tfromp(double p, double df)
        {
            int ifault;
            double ret;
            if (p < 1.0 - p)
                ret = finvt(2.0 * p, df, out ifault);
            else
                ret = -finvt(2.0 * (1.0 - p), df, out ifault);
            if (ifault != 0)
                ret = double.NaN;
            return ret;
        }

        /// <summary>
        /// Student t quantile from a two tail area
        /// </summary>
        public static double tfromp2(double p, double df)
        {
            double ret = finvt(p, df, out int ifault);
            if (ifault != 0)
                ret = double.NaN;
            return ret;
        }

        /// <summary>
        /// Two tail area for Student t
        /// </summary>
        public static double tvalp(double t, double df)
        {
            double ret = fvalp(t * t, 1.0, df);
            if (double.IsNaN(ret))
                return ret;
            ret *= 0.5;
            if (t < 0.0)
                ret = 1.0 - ret;
            return ret;
        }

        /// <summary>
        ///     finvt gives the two-tailed t percentage point
        /// </summary>
        /// <param name="t2">two-tailed area</param>
        ///<param name="df">degrees of freedom</param>
        ///<param name="ifault">zero if no fault, non-zero if fault</param>
        /// <returns>number such that the probability that the absolute value of a t random variable with df degrees of freedom will be greater than finvt is equal to t2</returns>
        ///<remarks>
        ///     reference: hill (1970 cacm 13, 619-620)
        ///
        ///     creation date: winter 1984 - modified IEB Sep 99
        ///
        ///     remark: max abs difference with mdsti less than
        ///             .6e-02 observed at 20 d.f. and p=.0004
        /// </remarks>
        private static double finvt(double t2, double df, out int ifault)
        {
            const double pib2 = 0.5 * Constant.PI;
            // double sr2=Math.Sqrt(2.0);
            double ret;
            ifault = 0;
            double p = t2;
            if (df == 2.0)
            {
                ret = Math.Sqrt(2.0 / (p * (2.0 - p)) - 2.0);
            }
            else if (df == 1.0)
            {
                p *= pib2;
                ret = Math.Cos(p) / Math.Sin(p);
            }
            else if (df < 60.0)
            {
                ret = xinbta(df / 2.0, 0.5, p, out ifault);
                ret = ifault != 0 ? double.NaN : Math.Sqrt(Math.Abs(df * (1.0 / ret - 1.0)));
            }
            else
            {
                double dn = df;
                double a = 1.0 / (dn - 0.5);
                double b = 48.0 / (a * a);
                double c = ((20700.0 * a / b - 98.0) * a - 16.0) * a + 96.36;
                double d = ((94.5 / (b + c) - 3.0) / b + 1.0) * Math.Sqrt(a * pib2) * dn;
                double x = d * p;
                double y = Math.Pow(x, 2.0 / dn);
                double pp = p * 0.5;
                x = gauinv(pp, out ifault);
                if (y <= 0.05 + a)
                    y = ((1.0 / (((dn + 6.0) / (dn * y) - 0.089 * d - 0.822) * (dn + 2.0) * 3.0) + 0.5 / (dn + 4.0)) * y - 1.0) * (dn + 1.0) / (dn + 2.0) + 1.0 / y;
                else
                {
                    y = x * x;
                    if (df < 5.0) c += 0.3 * (dn - 4.5) * (x + 0.6);
                    c = (((0.05 * d * x - 5.0) * x - 7.0) * x - 2.0) * x + b + c;
                    y = (((((0.4 * y + 6.3) * y + 36.0) * y + 94.5) / c - y - 3.0) / b + 1.0) * x;
                    y = a * y * y;
                    if (y > 0.002)
                        y = Math.Exp(y) - 1.0;
                    else
                        y = 0.5 * y * y + y;
                }
                ret = Math.Sqrt(dn * y);
                //  Newton polish of Hill's approximation, where the tail area is resolved well enough
                //  by tvalp: not for huge df, where Hill's expansion is already exact to rounding and tvalp is not, nor near t = 0.
                if (dn <= 2.0e6 && ret >= 0.01 && p > 0.0)
                {
                    double target = 0.5 * p;
                    double dp = tvalp(ret, dn) - target;
                    for (int it = 0; it < 8 && Math.Abs(dp) > 1.0e-13 * target; it++)
                    {
                        double dens = Math.Exp(alogam(0.5 * (dn + 1.0)) - alogam(0.5 * dn) - 0.5 * (dn + 1.0) * Math.Log(1.0 + ret * ret / dn)) / Math.Sqrt(dn * Constant.PI);
                        if (!(dens > 0.0))
                            break;
                        double step = dp / dens;
                        double trial = ret + step * (1.0 + step * ret * (dn + 1.0) / (2.0 * (ret * ret + dn)));
                        if (double.IsNaN(trial) || double.IsInfinity(trial) || trial <= 0.0)
                            break;
                        double dpTrial = tvalp(trial, dn) - target;
                        if (!(Math.Abs(dpTrial) < Math.Abs(dp)))
                            break;
                        ret = trial;
                        dp = dpTrial;
                    }
                }
            }
            return ret;
        }

        /// <summary>
        /// tail area of the chi-square distribution
        /// </summary>
        public static double chivalp(double x, double df)
        {
            // The upper tail is asked for as such. Taken as 1 minus the lower tail it could not be smaller than about 1e-16:
            // a chi-square of 80 with 1 degree of freedom gave exactly 0 where the area is 3.7e-19. Where gammad sums the
            // lower tail (x below the degrees of freedom) the result is the same 1 - sum as before.
            double ret = gammad(x / 2.0, df / 2.0, true, out int ifault);
            if (ifault != 0)
                ret = double.NaN;
            return ret;
        }

        /// <summary>
        /// tail area of the gamma distribution
        /// </summary>
        public static double gammad(double x, double p, out int ifault)
        {
            return gammad(x, p, false, out ifault);
        }

        /// <summary>
        /// lower tail area of the gamma distribution, or the upper tail if upper is true
        /// </summary>
        /// <remarks>
        /// AS 239 with the normal approximation for p > 1000 omitted: in double precision the series
        /// and continued fraction are accurate to about 1e-9 or better for any p, the approximation is not
        /// </remarks>
        public static double gammad(double x, double p, bool upper, out int ifault)
        {
            const double tol = Constant.DBL_SRS, zero = 0.0, one = 1.0, two = 2.0, xbig = 1.0e12;
            double
                elimit = Math.Log(Constant.DBL_MIN),
                oflo = Math.Sqrt(double.MaxValue);
            double pn1, arg, c, a;
            double ret = zero;
            if (p <= zero || x < zero || double.IsNaN(x) || double.IsNaN(p))
            {
                ifault = 1;
                return ret;
            }
            ifault = 0;
            if (x == zero)
            {
                ret = upper ? one : zero;
                return ret;
            }
            if (x > xbig)
            {
                ret = upper ? zero : one;
                return ret;
            }
            if (x <= one | x < p)
            {
                arg = p * Math.Log(x) - x - alogam(p + one);
                c = one;
                ret = one;
                a = p;
                for (; ; )
                {
                    a += one;
                    c = c * x / a;
                    ret += c;
                    if (c <= tol) break;
                }
                arg += Math.Log(ret);
                ret = zero;
                if (arg >= elimit) ret = Math.Exp(arg);
                if (upper) ret = one - ret;
            }
            else
            {
                arg = p * Math.Log(x) - x - alogam(p);
                a = one - p;
                double b = a + x + one;
                c = zero;
                pn1 = one;
                double pn2 = x;
                double pn3 = x + one;
                double pn4 = x * b;
                ret = pn3 / pn4;
                for (; ; )
                {
                    a += one;
                    b += two;
                    c += one;
                    double an = a * c;
                    double pn5 = b * pn3 - an * pn1;
                    double pn6 = b * pn4 - an * pn2;
                    if (Math.Abs(pn6) > zero)
                    {
                        double rn = pn5 / pn6;
                        if (Math.Abs(ret - rn) <= Math.Min(tol, tol * rn)) break;
                        ret = rn;
                    }
                    pn1 = pn3;
                    pn2 = pn4;
                    pn3 = pn5;
                    pn4 = pn6;
                    if (Math.Abs(pn5) >= oflo)
                    {
                        pn1 /= oflo;
                        pn2 /= oflo;
                        pn3 /= oflo;
                        pn4 /= oflo;
                    }
                }
                arg += Math.Log(ret);
                ret = upper ? zero : one;
                if (arg >= elimit)
                    ret = upper ? Math.Exp(arg) : one - Math.Exp(arg);
            }
            return ret;
        }

        /// <summary>
        /// Normal integral via the compliment of the error function
        /// </summary>
        public static double alnorm(double z)
        {
            if (double.IsNaN(z))
                return double.NaN;
            return 0.5 * derfc(-z * Math.Sqrt(0.5));
        }

        /// <summary>
        ///  Calculates the double precision error function for double precision argument.
        ///  Series for ERF on the interval  0. to  1.00000E+00
        ///                      with weighted error   1.28E-32
        ///                       log weighted error  31.89
        ///             significant figures required  31.05
        ///                  decimal places required  32.55
        /// </summary>
        /// <remarks>
        ///  Adaptation and translation of Netlib Saltec routine by Fullerton, W.
        /// </remarks>
        public static double derf(double x)
        {
            double[] erfcs = {
								  - 0.49046121234691808039984544033376e-1,
								  - 0.14226120510371364237824741899631,
								  + 0.10035582187599795575754676712933e-1,
								  - 0.57687646997674847650827025509167e-3,
								  + 0.27419931252196061034422160791471e-4,
								  - 0.11043175507344507604135381295905e-5,
								  + 0.38488755420345036949961311498174e-7,
								  - 0.11808582533875466969631751801581e-8,
								  + 0.32334215826050909646402930953354e-10,
								  - 0.79910159470045487581607374708595e-12,
								  + 0.17990725113961455611967245486634e-13,
								  - 0.37186354878186926382316828209493e-15,
								  + 0.71035990037142529711689908394666e-17,
								  - 0.12612455119155225832495424853333e-18,
								  + 0.20916406941769294369170500266666e-20,
								  - 0.32539731029314072982364160000000e-22,
								  + 0.47668672097976748332373333333333e-24,
								  - 0.65980120782851343155199999999999e-26,
								  + 0.86550114699637626197333333333333e-28,
								  - 0.10788925177498064213333333333333e-29,
								  + 0.12811883993017002666666666666666e-31};
            // For IEEE 64-bit Chebyshev interpolation terms = 11
            // for other systems call nterf = Base.chebyinit(erfcs,21,0.1*Defs.DBL_SRS)
            const int nterf = 11;
            double
                xbig = Math.Sqrt(-Math.Log(Constant.SQRTPI * Constant.DBL_SRS)),
                sqeps = Math.Sqrt(2.0 * Constant.DBL_SRS);
            double ret;
            double y = Math.Abs(x);
            if (y <= 1.0)
            {
                // ERF(X) = 1.0 - ERFC(X)  FOR  -1.0 <= X <= 1.0
                if (y <= sqeps)
                    ret = 2.0 * x / Constant.SQRTPI;
                else
                    ret = x * (1.0 + Base.cheby(2.0 * x * x - 1.0, erfcs, nterf));
            }
            else
            {
                // ERF(X) = 1.0 - ERFC(X) FOR Math.Abs(X) > 1.0
                ret = y <= xbig ? Base.dsign(1.0 - derfc(y), x) : Base.dsign(1.0, x);
            }
            return ret;
        }

        /// <summary>
        ///     calculates the double precision complementary error function for double precision argument.
        ///     series for erf        on the interval  0.          to  1.00000e+00
        ///                                        with weighted error   1.28e-32
        ///                                         log weighted error  31.89
        ///                               significant figures required  31.05
        ///                                    decimal places required  32.55
        ///     series for erc2       on the interval  2.50000e-01 to  1.00000e+00
        ///                                        with weighted error   2.67e-32
        ///                                         log weighted error  31.57
        ///                               significant figures required  30.31
        ///                                    decimal places required  32.42
        ///     series for erfc       on the interval  0.          to  2.50000e-01
        ///                                        with weighted error   1.53e-31
        ///                                         log weighted error  30.82
        ///                               significant figures required  29.47
        ///                                    decimal places required  31.70
        /// </summary>
        /// <remarks>
        ///     adaptation and translation of netlib saltec routine by w fullerton.
        /// </remarks>
        public static double derfc(double x)
        {
            double[] erfcs = {
								 - 0.49046121234691808039984544033376e-1,
								 - 0.14226120510371364237824741899631,
								 + 0.10035582187599795575754676712933e-1,
								 - 0.57687646997674847650827025509167e-3,
								 + 0.27419931252196061034422160791471e-4,
								 - 0.11043175507344507604135381295905e-5,
								 + 0.38488755420345036949961311498174e-7,
								 - 0.11808582533875466969631751801581e-8,
								 + 0.32334215826050909646402930953354e-10,
								 - 0.79910159470045487581607374708595e-12,
								 + 0.17990725113961455611967245486634e-13,
								 - 0.37186354878186926382316828209493e-15,
								 + 0.71035990037142529711689908394666e-17,
								 - 0.12612455119155225832495424853333e-18,
								 + 0.20916406941769294369170500266666e-20,
								 - 0.32539731029314072982364160000000e-22,
								 + 0.47668672097976748332373333333333e-24,
								 - 0.65980120782851343155199999999999e-26,
								 + 0.86550114699637626197333333333333e-28,
								 - 0.10788925177498064213333333333333e-29,
								 + 0.12811883993017002666666666666666e-31};
            double[] erc2cs = {
								  - 0.6960134660230950112739150826197e-1,
								  - 0.4110133936262089348982212084666e-1,
								  + 0.3914495866689626881561143705244e-2,
								  - 0.4906395650548979161280935450774e-3,
								  + 0.7157479001377036380760894141825e-4,
								  - 0.1153071634131232833808232847912e-4,
								  + 0.1994670590201997635052314867709e-5,
								  - 0.3642666471599222873936118430711e-6,
								  + 0.6944372610005012589931277214633e-7,
								  - 0.1371220902104366019534605141210e-7,
								  + 0.2788389661007137131963860348087e-8,
								  - 0.5814164724331161551864791050316e-9,
								  + 0.1238920491752753181180168817950e-9,
								  - 0.2690639145306743432390424937889e-10,
								  + 0.5942614350847910982444709683840e-11,
								  - 0.1332386735758119579287754420570e-11,
								  + 0.3028046806177132017173697243304e-12,
								  - 0.6966648814941032588795867588954e-13,
								  + 0.1620854541053922969812893227628e-13,
								  - 0.3809934465250491999876913057729e-14,
								  + 0.9040487815978831149368971012975e-15,
								  - 0.2164006195089607347809812047003e-15,
								  + 0.5222102233995854984607980244172e-16,
								  - 0.1269729602364555336372415527780e-16,
								  + 0.3109145504276197583836227412951e-17,
								  - 0.7663762920320385524009566714811e-18,
								  + 0.1900819251362745202536929733290e-18,
								  - 0.4742207279069039545225655999965e-19,
								  + 0.1189649200076528382880683078451e-19,
								  - 0.3000035590325780256845271313066e-20,
								  + 0.7602993453043246173019385277098e-21,
								  - 0.1935909447606872881569811049130e-21,
								  + 0.4951399124773337881000042386773e-22,
								  - 0.1271807481336371879608621989888e-22,
								  + 0.3280049600469513043315841652053e-23,
								  - 0.8492320176822896568924792422399e-24,
								  + 0.2206917892807560223519879987199e-24,
								  - 0.5755617245696528498312819507199e-25,
								  + 0.1506191533639234250354144051199e-25,
								  - 0.3954502959018796953104285695999e-26,
								  + 0.1041529704151500979984645051733e-26,
								  - 0.2751487795278765079450178901333e-27,
								  + 0.7290058205497557408997703680000e-28,
								  - 0.1936939645915947804077501098666e-28,
								  + 0.5160357112051487298370054826666e-29,
								  - 0.1378419322193094099389644800000e-29,
								  + 0.3691326793107069042251093333333e-30,
								  - 0.9909389590624365420653226666666e-31,
								  + 0.2666491705195388413323946666666e-31};
            double[] erfccs = {
								  + 0.715179310202924774503697709496e-1,
								  - 0.265324343376067157558893386681e-1,
								  + 0.171115397792085588332699194606e-2,
								  - 0.163751663458517884163746404749e-3,
								  + 0.198712935005520364995974806758e-4,
								  - 0.284371241276655508750175183152e-5,
								  + 0.460616130896313036969379968464e-6,
								  - 0.822775302587920842057766536366e-7,
								  + 0.159214187277090112989358340826e-7,
								  - 0.329507136225284321486631665072e-8,
								  + 0.722343976040055546581261153890e-9,
								  - 0.166485581339872959344695966886e-9,
								  + 0.401039258823766482077671768814e-10,
								  - 0.100481621442573113272170176283e-10,
								  + 0.260827591330033380859341009439e-11,
								  - 0.699111056040402486557697812476e-12,
								  + 0.192949233326170708624205749803e-12,
								  - 0.547013118875433106490125085271e-13,
								  + 0.158966330976269744839084032762e-13,
								  - 0.472689398019755483920369584290e-14,
								  + 0.143587337678498478672873997840e-14,
								  - 0.444951056181735839417250062829e-15,
								  + 0.140481088476823343737305537466e-15,
								  - 0.451381838776421089625963281623e-16,
								  + 0.147452154104513307787018713262e-16,
								  - 0.489262140694577615436841552532e-17,
								  + 0.164761214141064673895301522827e-17,
								  - 0.562681717632940809299928521323e-18,
								  + 0.194744338223207851429197867821e-18,
								  - 0.682630564294842072956664144723e-19,
								  + 0.242198888729864924018301125438e-19,
								  - 0.869341413350307042563800861857e-20,
								  + 0.315518034622808557122363401262e-20,
								  - 0.115737232404960874261239486742e-20,
								  + 0.428894716160565394623737097442e-21,
								  - 0.160503074205761685005737770964e-21,
								  + 0.606329875745380264495069923027e-22,
								  - 0.231140425169795849098840801367e-22,
								  + 0.888877854066188552554702955697e-23,
								  - 0.344726057665137652230718495566e-23,
								  + 0.134786546020696506827582774181e-23,
								  - 0.531179407112502173645873201807e-24,
								  + 0.210934105861978316828954734537e-24,
								  - 0.843836558792378911598133256738e-25,
								  + 0.339998252494520890627359576337e-25,
								  - 0.137945238807324209002238377110e-25,
								  + 0.563449031183325261513392634811e-26,
								  - 0.231649043447706544823427752700e-26,
								  + 0.958446284460181015263158381226e-27,
								  - 0.399072288033010972624224850193e-27,
								  + 0.167212922594447736017228709669e-27,
								  - 0.704599152276601385638803782587e-28,
								  + 0.297976840286420635412357989444e-28,
								  - 0.126252246646061929722422632994e-28,
								  + 0.539543870454248793985299653154e-29,
								  - 0.238099288253145918675346190062e-29,
								  + 0.109905283010276157359726683750e-29,
								  - 0.486771374164496572732518677435e-30,
								  + 0.152587726411035756763200828211e-30};
            // const double eta = 0.1*Defs.DBL_SRS;
            // For IEEE 64-bit Chebyshev interpolation terms = 11 for nterf, 24 for nterfc and 23 for nterc2
            // for other systems call
            //  nterf = Base.chebyinit(erfcs,21,eta)
            //  nterfc = Base.chebyinit(erfccs,59,eta)
            //  nterc2 = Base.chebyinit(erc2cs,49,eta)
            const int nterf = 11, nterfc = 24, nterc2 = 23;
            double
                xsml = -Math.Sqrt(-Math.Log(Constant.SQRTPI * Constant.DBL_SRS)),
                txmax = Math.Sqrt(-Math.Log(Constant.SQRTPI * Constant.DBL_MIN)),
                xmax = txmax - 0.5 * Math.Log(txmax) / txmax - 0.01,
                sqeps = Math.Sqrt(2.0 * Constant.DBL_SRS);
            // erfc(x) = 1.0 - erf(x)  for  x < xsml
            if (x <= xsml) return 2.0;
            if (x <= xmax)
            {
                double y = Math.Abs(x);
                if (y <= 1.0)
                {
                    // erfc(x) = 1.0 - erf(x)  for Math.Abs(x) <= 1.0
                    if (y < sqeps)
                        return 1.0 - 2.0 * x / Constant.SQRTPI;
                    return 1.0 - x * (1.0 + Base.cheby(2.0 * x * x - 1.0, erfcs, nterf));
                }
                // erfc(x) = 1.0 - erf(x)  for  1.0 < Math.Abs(x) <= xmax
                y *= y;
                double ret;
                if (y <= 4.0)
                    ret = Math.Exp(-y) / Math.Abs(x) * (0.5 + Base.cheby((8.0 / y - 5.0) / 3.0, erc2cs, nterc2));
                else
                    ret = Math.Exp(-y) / Math.Abs(x) * (0.5 + Base.cheby(8.0 / y - 1.0, erfccs, nterfc));
                if (x < 0.0) ret = 2.0 - ret;
                return ret;
            }
            //     x so big erfc underflows
            return 0.0;
        }

        /// <summary>
        ///
        ///     function  ppchi2
        ///       evaluates the percentage points of the chi-squared
        ///       probability distribution function.
        ///       g should equal ln(gamma(v/2.0)).
        ///
        ///     input variables:
        ///       p = left tail probability  (between 0.0000002 and 0.999998 for AS91)
        ///       v = degrees of freedom (a positive real number)
        ///     output variables:
        ///       ppchi2 = chi-square percentage point
        ///       ifault = 1 if p is out of range
        ///                2 if v is not positive
        ///                3 if function gammad returns a fault
        ///                0 otherwise
        ///     auxiliary functions rquired:
        ///       gauinv(p,if1) = normal percentage point
        ///       alogam(x) = ln(gamma(x))
        /// </summary>
        /// <remarks>
        ///     best, d.j. and roberts, d.e. (1975).
        ///       the percentage points of the chi-square distribution
        ///       algorithm as 91 appl. statist. vol. 24 no. 3, pp. 385-388.
        ///
        ///     available via the statlib archive, at http://lib.stat.cmu.edu/apstat/
        /// </remarks>
        public static double ppchi2(double prob, double v, out int ifault)
        {
            const double e = 0.5e-12, aa = 0.6931471805;
            double ch, q, p1, p2, t, a;
            //  after defining accuracy and ln(2), test arguments and initialize
            double p = prob;
            double ret = -1.0;
            ifault = 1;
            if (p < 0.000002 || p > 0.999998)
            {
                ret = ppchir(prob, v, out ifault);
                return ret;
            }
            if (v <= 0.0) 
                return ret;
            ifault = 0;
            double xx = 0.5 * v;
            double c = xx - 1.0;
            double g = alogam(xx);
            if (ifault != 0) 
                return ret;
            //  start approximation for small chi-squared
            if (v < -1.24 * Math.Log(p))
            {
                ch = Math.Pow(p * xx * Math.Exp(g + xx * aa), 1.0 / xx);
                if (ch - e < 0.0) return ch;
            }
            else
            {
                //  start approximation for v less than or equal to 0.32
                if (v <= 0.32)
                {
                    ch = 0.4;
                    a = Math.Log(1.0 - p);
                    for (; ; )
                    {
                        q = ch;
                        p1 = 1.0 + ch * (4.67 + ch);
                        p2 = ch * (6.73 + ch * (6.66 + ch));
                        t = -0.5 + (4.67 + 2.0 * ch) / p1 - (6.73 + ch * (13.32 + 3.0 * ch)) / p2;
                        ch -= (1.0 - Math.Exp(a + g + 0.5 * ch + c * aa) * p2 / p1) / t;
                        if (Math.Abs(q / ch - 1.0) - 0.01 <= 0.0) break;
                    }
                }
                else
                {
                    //  call to gauinv(p) - note that p has been tested above
                    double x = gauinv(p, out ifault);
                    if (ifault != 0) return ret;
                    //  start approximation using wilson and hilferty estimate
                    p1 = 0.222222 / v;
                    ch = v * Math.Pow(x * Math.Sqrt(p1) + 1.0 - p1, 3);
                    //  start approximation for p tending to 1
                    if (ch > 2.2 * v + 6.0) ch = -2.0 * (Math.Log(1.0 - p) - c * Math.Log(0.5 * ch) + g);
                }
            }
            //  call to incomplete gamma function and claculation of seven term taylor series
            for (int iteration = 0; ; iteration++)
            {
                q = ch;
                p1 = 0.5 * ch;
                p2 = p - gammad(p1, xx, out ifault);
                if (ifault != 0) return ret;
                t = p2 * Math.Exp(xx * aa + g + p1 - c * Math.Log(ch));
                double b = t / ch;
                a = 0.5 * t - b * c;
                double s1 = (210.0 + a * (140.0 + a * (105.0 + a * (84.0 + a * (70.0 + 60.0 * a))))) / 420.0;
                double s2 = (420.0 + a * (735.0 + a * (966.0 + a * (1141.0 + 1278.0 * a)))) / 2520.0;
                double s3 = (210.0 + a * (462.0 + a * (707.0 + 932.0 * a))) / 2520.0;
                double s4 = (252.0 + a * (672.0 + 1182.0 * a) + c * (294.0 + a * (889.0 + 1740.0 * a))) / 5040.0;
                double s5 = (84.0 + 264.0 * a + c * (175.0 + 606.0 * a)) / 2520.0;
                double s6 = (120.0 + c * (346.0 + 127.0 * c)) / 5040.0;
                ch += t * (1.0 + 0.5 * t * s1 - b * c * (s1 - b * (s2 - b * (s3 - b * (s4 - b * (s5 - b * s6))))));
                if (Math.Abs(q / ch - 1.0) <= e)
                    break;
                // At several million degrees of freedom the rounding in the incomplete gamma moves chi-square by about 1e-12 of
                // itself, so successive values can stay further apart than e for ever and the loop never ended (0.999 with ten
                // million degrees of freedom froze the program). The bisection used outside this routine's range of p settles
                // it. A call that converges, as every ordinary one does within a few steps, returns exactly what it did.
                if (iteration >= 100)
                    return ppchir(prob, v, out ifault);
            }
            ret = ch;
            return ret;
        }

        /// <summary>
        ///     chi-square percentage point for p outside the range of AS 91:
        ///     the tail with the smaller probability is bracketed from a Wilson and Hilferty
        ///     start (or the small chi-square approximation) and the root is found by bisection
        /// </summary>
        private static double ppchir(double p, double df, out int ifault)
        {
            const double eps = 10.0 * Constant.DBL_LRS;
            const int maxit = 2200;
            ifault = 1;
            if (p <= 0.0 | p >= 1.0 | double.IsNaN(p)) return double.NaN;
            ifault = 2;
            if (df <= 0.0 | double.IsNaN(df)) return double.NaN;
            bool upper = p > 0.5;
            double q = upper ? 1.0 - p : p;
            //  f(x) = sgn * (tail(x) - q) increases with x
            double sgn = upper ? -1.0 : 1.0;
            double xint = gauinv(p, out ifault);
            if (ifault != 0) return double.NaN;
            double x0 = 2.0 / (9.0 * df);
            double x1 = df * Math.Pow(1.0 - x0 + xint * Math.Sqrt(x0), 3.0);
            if (!(x1 > 0.0))
                x1 = 2.0 * Math.Exp((Math.Log(p) + alogam(0.5 * df + 1.0)) * 2.0 / df);
            if (!(x1 > 0.0))
                x1 = Constant.DBL_MIN;
            double f1 = ppchirf(x1, df, upper, q, sgn, out ifault);
            if (ifault != 0) return double.NaN;
            double x2 = x1;
            double f2 = f1;
            int iter = 0;
            if (f1 < 0.0)
            {
                //  start too small: double until the root is bracketed
                do
                {
                    x1 = x2;
                    f1 = f2;
                    x2 *= 2.0;
                    f2 = ppchirf(x2, df, upper, q, sgn, out ifault);
                    if (ifault != 0 || double.IsInfinity(x2) || ++iter > maxit) return double.NaN;
                }
                while (f2 < 0.0);
            }
            else
            {
                //  start too large: halve until the root is bracketed
                do
                {
                    x2 = x1;
                    f2 = f1;
                    x1 *= 0.5;
                    f1 = ppchirf(x1, df, upper, q, sgn, out ifault);
                    if (ifault != 0 || ++iter > maxit) return double.NaN;
                }
                while (f1 > 0.0 && x1 > 0.0);
            }
            //  bisection
            for (iter = 1; iter <= maxit; iter++)
            {
                double xm = 0.5 * (x1 + x2);
                if (x2 - x1 <= eps * xm) break;
                double fm = ppchirf(xm, df, upper, q, sgn, out ifault);
                if (ifault != 0) return double.NaN;
                if (fm == 0.0) return xm;
                if (fm < 0.0)
                    x1 = xm;
                else
                    x2 = xm;
            }
            return 0.5 * (x1 + x2);
        }

        private static double ppchirf(double x, double df, bool upper, double q, double sgn, out int ifault)
        {
            return sgn * (gammad(0.5 * x, 0.5 * df, upper, out ifault) - q);
        }

        public static void bino(int n, double p, int k, ref double term, ref double plo, ref double phi, out int ifault)
        {
            int i;
            double sml = Math.Log(Constant.DBL_MIN);
            //     cumulative and point binomial distribution
            if (p < 0.0 | p > 1.0)
            {
                ifault = 1;
                return;
            }
            if (n < k)
            {
                ifault = 2;
                return;
            }
            ifault = 0;

            double xn = n;
            // double xk = k;
            plo = 0.0;
            double xn1 = xn + 1.0;
            for (i = 0; i <= k; i++)
            {
                double xi = i;
                term = alogam(xn1) - alogam(xi + 1.0) - alogam(xn1 - xi) + xi * Math.Log(p) + (xn - xi) * Math.Log(1.0 - p);
                if (term > sml) plo += Math.Exp(term);
            }
            if (term > sml) term = Math.Exp(term);
            if (term < 0.0) term = 0.0;
            phi = 1.0 - plo + term;
        }

        /// <summary>
        ///     cumulative binomial distribution for two sided inference
        ///
        ///	updated 1/2/02 - Alan Gibbs 2 * p1 not acceptable if p &lt;> 0.5
        /// </summary>
        public static void bino2(int n, double p, int k, out double p1, out double p2, out int ifault)
        {
            double xi, px;
            int i;
            double sml = Math.Log(Constant.DBL_MIN);
            if (p < 0.0 | p > 1.0)
            {
                ifault = 1;
                p1 = Constant.MISSING;
                p2 = Constant.MISSING;
                return;
            }
            if (n < k)
            {
                ifault = 2;
                p1 = Constant.MISSING;
                p2 = Constant.MISSING;
                return;
            }
            ifault = 0;

            if (p == 0.0)
            {
                p1 = 0.5;
                p2 = 1.0;
                return;
            }
            if (p == 1.0)
            {
                if (k == n)
                {
                    p1 = 0.5;
                    p2 = 1.0;
                }
                else
                {
                    p1 = 0.0;
                    p2 = 0.0;
                }
                return;
            }
            double xn = n;
            double xn1 = xn + 1.0;
            double[] pr = new double[n + 1];
            for (i = 0; i <= n; i++)
            {
                xi = i;
                double term = alogam(xn1) - alogam(xi + 1.0) - alogam(xn1 - xi) + xi * Math.Log(p) + (xn - xi) * Math.Log(1.0 - p);
                pr[i] = term > sml ? Math.Exp(term) : 0.0;
            }
            // tails summed from the smallest terms
            double plo = 0.0;
            for (i = 0; i <= k; i++) plo += pr[i];
            double phi = 0.0;
            for (i = n; i >= k; i--) phi += pr[i];
            p1 = phi < plo ? phi : plo;
            // two sided P: total probability of the counts no more likely than the observed count (the relative tolerance keeps equal probabilities equal despite rounding)
            double z = pr[k] * (1.0 + 1.0e-7);
            p2 = 0.0;
            for (i = 0; i <= n; i++)
            {
                px = pr[i];
                if (px <= z) p2 += px;
            }
        }


        /// <summary>
        ///     cumulative binomial distribution for mid-point inference
        /// </summary>
        public static void binomid(int n, double p, int k, out double p1, out double p2, out int ifault)
        {
            int i;
            double sml = Math.Log(Constant.DBL_MIN);
            if (p < 0.0 | p > 1.0)
            {
                ifault = 1;
                p1 = Constant.MISSING;
                p2 = Constant.MISSING;
                return;
            }
            if (n < k)
            {
                ifault = 2;
                p1 = Constant.MISSING;
                p2 = Constant.MISSING;
                return;
            }
            ifault = 0;

            if (p == 0.0)
            {
                p1 = 0.5;
                p2 = 1.0;
                return;
            }
            if (p == 1.0)
            {
                if (k == n)
                {
                    p1 = 0.5;
                    p2 = 1.0;
                }
                else
                {
                    p1 = 0.0;
                    p2 = 0.0;
                }
                return;
            }
            double xn = n;
            double plo = 0.0;
            double term = 0.0;
            double xn1 = xn + 1.0;
            for (i = 0; i <= k; i++)
            {
                double xi = i;
                term = alogam(xn1) - alogam(xi + 1.0) - alogam(xn1 - xi) + xi * Math.Log(p) + (xn - xi) * Math.Log(1.0 - p);
                if (term > sml) plo += Math.Exp(term);
            }
            if (term > sml) term = Math.Exp(term);
            if (term < 0.0) term = 0.0;
            double phi = 1.0 - plo + term;
            p1 = phi < plo ? phi : plo;
            p1 -= term / 2.0;
            p2 = 2.0 * p1;
        }

        /// <summary>
        ///     cumulative poisson distribution
        /// </summary>
        public static void poisson(double xlam, int k, out double phi, out double plo, out double term, out int ifault)
        {
            term = ppoiseq(k, xlam);
            plo = ppoisle(k, xlam);
            phi = 1.0 - plo + term;
            ifault = double.IsNaN(term) || double.IsNaN(plo) ? 1 : 0;
        }

        /// <summary>
        ///     inverse cumulative Poisson distribution by simple bisection
        ///     set idx = 3 if input p is plo else input p is assumed to be phi
        ///     this function returns the Poisson mean associated with p and k (nl)
        /// </summary>
        public static void poissoni(ref int idx, double p, out double xmid, out double trm, out double phi, out double plo, int nl, out int ifault)
        {
            const double acc = Constant.DBL_LRS;
            double dx, fmid;
            const int imax = 1000;
            double xnl = nl;
            const double x1 = acc;
            double x2 = 0.0;
            //     find upper limit for mean where phi is almost 1
            int istep = 0;
            for (; ; )
            {
                x2 += xnl;
                poisson(x2, nl, out phi, out plo, out trm, out ifault);
                if (ifault != 0) break;
                dx = idx == 2 ? Math.Abs(1.0 - phi) : Math.Abs(0.0 - plo);
                istep += 1;
                if (istep > imax)
                {
                    ifault = 1;
                    break;
                }
                if (dx <= acc)
                    break;
            }
            //     bisect to converge upon p
            double bis = x1;
            dx = x2 - x1;
            istep = 0;
            if (idx == 2)
            {
                for (; ; )
                {
                    dx *= 0.5;
                    xmid = bis + dx;
                    poisson(xmid, nl, out phi, out plo, out trm, out ifault);
                    fmid = phi;
                    if (ifault != 0)
                        break;
                    if (fmid - p <= 0.0) bis = xmid;
                    if (Math.Abs(dx) <= acc || Math.Abs(fmid - p) == 0.0)
                        break;
                    istep++;
                    if (istep > imax)
                    {
                        ifault = 3;
                        break;
                    }
                }
            }
            else
            {
                for (; ; )
                {
                    dx *= 0.5;
                    xmid = bis + dx;
                    poisson(xmid, nl, out phi, out plo, out trm, out ifault);
                    fmid = plo;
                    if (ifault != 0) break;
                    if (fmid - p > 0.0) bis = xmid;
                    if ((Math.Abs(dx) <= acc) | (Math.Abs(fmid - p) == 0.0)) break;
                    istep += 1;
                    if (istep > imax)
                    {
                        ifault = 3;
                        break;
                    }
                }
            }
        }

        /// <summary>
        ///       probability that a poisson random variable = k with mean theta
        /// </summary>
        private static double ppoiseq(int k, double theta)
        {
            double smexe = Math.Log(Constant.DBL_MIN);
            if (theta <= 0.0) return double.NaN;
            if (k < 0) return 0.0;
            double temp = theta + alogam(k + 1);
            double ex = -1.0 * temp + k * Math.Log(theta);
            if (ex >= smexe)
                return Math.Exp(ex);
            return 0.0;
        }

        /// <summary>
        ///       probability that a poisson random variable &lt;= k with mean theta
        /// </summary>
        private static double ppoisle(int k, double theta)
        {
            double pe;
            const double
                      eps = Constant.DBL_LRS,
                      sml = 2.0 * Constant.DBL_MIN;
            double alnsml = Math.Log(sml);
            if (theta <= 0.0) return double.NaN;
            if (k < 0) return 0.0;
            int k1 = k + 1;
            //      lambda = 0, special
            if (theta <= eps)
                pe = 1.0;
            else
            {
                //      prep forward calc
                double x = theta;
                double y = 1.0;
                int jj = 1;
                double p1 = -theta;
                int icnt = (int)(p1 / alnsml);
                p1 -= icnt * alnsml;
                p1 = Math.Exp(p1);
                //      prep backward calc
                double x2 = k;
                double y2 = theta;
                double g = x2 * Math.Log(y2);
                double h = k1;
                h = alogam(h);
                double p2 = -y2 + g - h;
                int kcnt = (int)(p2 / alnsml);
                p2 -= kcnt * alnsml;
                p2 = Math.Exp(p2);
                g = 1.0;
                h = 1.0;
                if (icnt == 0) g = 1.0 - p1;
                if (kcnt == 0) h = 1.0 - p2;
                pe = 0.0;
                //      work out which end to calculate from
                for (; ; )
                {
                    int j = icnt - kcnt;
                    double temp;
                    if (j > 0.0 | (j == 0.0 & p1 <= p2))
                    {
                        //        forward
                        //        no need to scale, just store term
                        if (icnt == 0) pe += p1;
                        if (jj != k1)
                        {
                            //         next term (recursion)
                            p1 = p1 * x / y;
                            if (p1 >= h)
                            {
                                //          scale
                                temp = p1 * sml;
                                if (temp != 0.0)
                                {
                                    p1 = temp;
                                    icnt -= 1;
                                }
                            }
                            jj += 1;
                            y += 1.0;
                        }
                        else
                        {
                            break;
                        }
                    }
                    else
                    {
                        //        backward
                        //        no need to scale, just store term
                        if (kcnt == 0) pe += p2;
                        if (jj != k1)
                        {
                            //         next term (recursion)
                            p2 = p2 * x2 / y2;
                            if (p2 >= g)
                            {
                                //          scale
                                temp = p2 * sml;
                                if (temp != 0.0)
                                {
                                    p2 = temp;
                                    kcnt -= 1;
                                }
                            }
                            k1 -= 1;
                            x2 -= 1.0;
                        }
                        else
                        {
                            break;
                        }
                    }
                }
            }
            if (pe > 1.0) pe = 1.0;
            return pe;
        }

        /// <summary>
        ///       expected normal order statistics
        /// </summary>
        public static double expnos(int i, int n)
        {
            double[] q = {
                0.0,
                /*data q(1)*/ -.2995732273553875e01, /*q(2)*/ -.2302585092993988e01,
                /*data q(3)*/ -.1897119984885843e01, /*q(4)*/ -.1609437912434071e01,
                /*data q(5)*/ -.1386294361119867e01, /*q(6)*/ -.1203972804325917e01,
                /*data q(7)*/ -.1049822124498661e01, /*q(8)*/ -.9162907318741406e00,
                /*data q(9)*/ -.7985076962177587e00, /*q(10)*/ -.6931471805599337e00,
                /*data q(11)*/ -.5978370007556099e00, /*q(12)*/ -.510825623765981e00,
                /*data q(13)*/ -.4307829160924453e00, /*q(14)*/ -.356674943938724e00,
                /*data q(15)*/ -.2876820724517732e00, /*q(16)*/ -.2231435513142025e00,
                /*data q(17)*/ -.162518929497768e00, /*q(18)*/ -.1053605156578198e00,
                /*data q(19)*/ -.5129329438754439e-01, /*q(20)*/ .5773159728050793e-14,
                /*data q(21)*/ .4879016416943751e-01, /*q(22)*/ .9531017980433021e-01,
                /*data q(23)*/ .1397619423751639e00, /*q(24)*/ .1823215567939596e00,
                /*data q(25)*/ .2231435513142145e00, /*q(26)*/ .2623642644674957e00,
                /*data q(27)*/ .3001045924503426e00, /*q(28)*/ .3364722366212173e00,
                /*data q(29)*/ .3715635564324873e00, /*q(30)*/ .4054651081081685e00,
                /*data q(31)*/ .4382549309311592e00, /*q(32)*/ .4700036292457395e00,
                /*data q(33)*/ .5007752879124931e00, /*q(34)*/ .5306282510621742e00,
                /*data q(35)*/ .5596157879354263e00, /*q(36)*/ .5877866649021226e00,
                /*data q(37)*/ .615185639090237e00, /*q(38)*/ .6418538861723983e00,
                /*data q(39)*/ .6678293725756588e00, /*q(40)*/ .6931471805599486e00,
                /*data q(41)*/ .7178397931503201e00, /*q(42)*/ .7419373447293805e00,
                /*data q(43)*/ .7654678421395746e00, /*q(44)*/ .7884573603642733e00,
                /*data q(45)*/ .8109302162163319e00, /*q(46)*/ .8329091229351071e00,
                /*data q(47)*/ .8544153281560706e00, /*q(48)*/ .8754687373539028e00,
                /*data q(49)*/ .8960880245566385e00, /*q(50)*/ .9162907318741579e00,
                /*data q(51)*/ .9360933591703376e00, /*q(52)*/ .9555114450274392e00,
                /*data q(53)*/ .9745596399981336e00, /*q(54)*/ .9932517730102861e00,
                /*data q(55)*/ .1011600911678482e01, /*q(56)*/ .1029619417181161e01,
                /*data q(57)*/ .1047318994280562e01, /*q(58)*/ .1064710736992431e01,
                /*data q(59)*/ .1081805170351731e01, /*q(60)*/ .1098612288668112e01,
                /*data q(61)*/ .1115141590619323e01, /*q(62)*/ .1131402111491103e01,
                /*data q(63)*/ .1147402452837544e01, /*q(64)*/ .1163150809805683e01,
                /*data q(65)*/ .1178654996341648e01, /*q(66)*/ .1193922468472437e01,
                /*data q(67)*/ .1208960345836977e01, /*q(68)*/ .1223775431622118e01,
                /*data q(69)*/ .1238374231043271e01, /*q(70)*/ .125276296849537e01,
                /*data q(71)*/ .1266947603487327e01, /*q(72)*/ .1280933845462066e01,
                /*data q(73)*/ .1294727167594402e01, /*q(74)*/ .1308332819650181e01,
                /*data q(75)*/ .1321755839982321e01, /*q(76)*/ .1335001066732342e01,
                /*data q(77)*/ .1348073148299695e01, /*q(78)*/ .1360976553135603e01,
                /*data q(79)*/ .1373715578913033e01, /*q(80)*/ .1386294361119893e01,
                /*data q(81)*/ .139871688111845e01, /*q(82)*/ .1410986973710264e01,
                /*data q(83)*/ .1423108334242609e01, /*q(84)*/ .1435084525289324e01,
                /*data q(85)*/ .1446918982936327e01, /*q(86)*/ .1458615022699519e01,
                /*data q(87)*/ .1470175845100595e01, /*q(88)*/ .1481604540924217e01,
                /*data q(89)*/ .1492904096178151e01, /*q(90)*/ .1504077396776276e01,
                /*data q(91)*/ .1515127232962861e01, /*q(92)*/ .1526056303495051e01,
                /*data q(93)*/ .1536867219599267e01, /*q(94)*/ .1547562508716015e01,
                /*data q(95)*/ .1558144618046552e01, /*q(96)*/ .1568615917913847e01,
                /*data q(97)*/ .1578978704949394e01, /*q(98)*/ .1589235205116583e01,
                /*data q(99)*/ .1599387576580601e01, /*q(100)*/ .1609437912434102e01,
                /*data q(101)*/ .161938824328727e01, /*q(102)*/ .1629240539730282e01,
                /*data q(103)*/ .1638996714675647e01, /*q(104)*/ .1648658625587383e01,
                /*data q(105)*/ .1658228076603534e01, /*q(106)*/ .1667706820558078e01,
                /*data q(107)*/ .1677096560907917e01, /*q(108)*/ .168639895357023e01,
                /*data q(109)*/ .1695615608675154e01, /*q(110)*/ .1704748092238427e01,
                /*data q(111)*/ .1713797927758345e01, /*q(112)*/ .1722766597741105e01,
                /*data q(113)*/ .1731655545158351e01, /*q(114)*/ .1740466174840506e01,
                /*data q(115)*/ .1749199854809261e01, /*q(116)*/ .1757857917552375e01,
                /*data q(117)*/ .1766441661243767e01, /*q(118)*/ .1774952350911676e01,
                /*data q(119)*/ .178339121955754e01, /*q(120)*/ .1791759469228057e01,
                /*data q(121)*/ .1800058272042752e01, /*q(122)*/ .1808288771179267e01,
                /*data q(123)*/ .1816452081818428e01, /*q(124)*/ .1824549292051047e01,
                /*data q(125)*/ .1832581463748312e01, /*q(126)*/ .1840549633397489e01,
                /*data q(127)*/ .1848454812904602e01, /*q(128)*/ .1856297990365628e01,
                /*data q(129)*/ .1864080130807683e01, /*q(130)*/ .1871802176901593e01,
                /*data q(131)*/ .1879465049647162e01, /*q(132)*/ .1887069649032381e01,
                /*data q(133)*/ .1894616854667764e01, /*q(134)*/ .1902107526396922e01,
                /*data q(135)*/ .190954250488444e01, /*q(136)*/ .1916922612182063e01,
                /*data q(137)*/ .1924248652274135e01, /*q(138)*/ .1931521411603215e01,
                /*data q(139)*/ .1938741659576702e01, /*q(140)*/ .1945910149055315e01,
                /*data q(141)*/ .1953027616824179e01, /*q(142)*/ .1960094784047271e01,
                /*data q(143)*/ .1967112356705918e01, /*q(144)*/ .1974081026022011e01,
                /*data q(145)*/ .1981001468866585e01, /*q(146)*/ .1987874348154347e01,
                /*data q(147)*/ .1994700313224747e01, /*q(148)*/ .2001480000210126e01,
                /*data q(149)*/ .200821403239147e01, /*q(150)*/ .2014903020542266e01,
                /*data q(151)*/ .2021547563260935e01, /*q(152)*/ .2028148247292287e01};
            double[] r = {
                0.0,
                /*data r(1)*/ -.1476596622751468e-13, /*r(2)*/ -.2176037128265329e-13,
                /*data r(3)*/ -.3186340080674248e-13, /*r(4)*/ -.4662936703425763e-13,
                /*data r(5)*/ -.6805667140952435e-13, /*r(6)*/ -.9914291609903131e-13,
                /*data r(7)*/ -.1438849039914305e-12, /*r(8)*/ -.2083888617221634e-12,
                /*data r(9)*/ -.3010924842783875e-12, /*r(10)*/ -.4338751580236049e-12,
                /*data r(11)*/ -.6238343175370696e-12, /*r(12)*/ -.8946177132433506e-12,
                /*data r(13)*/ -.1279865102788698e-11, /*r(14)*/ -.1826427897812512e-11,
                /*data r(15)*/ -.2600142323675495e-11, /*r(16)*/ -.3692490757607623e-11,
                /*data r(17)*/ -.5230926802837565e-11, /*r(18)*/ -.739230898719146e-11,
                /*data r(19)*/ -.1042099739839586e-10, /*r(20)*/ -.1465461085825204e-10,
                /*data r(21)*/ -.2055788872489286e-10, /*r(22)*/ -.287685431037107e-10,
                /*data r(23)*/ -.401599864482697e-10, /*r(24)*/ -.5592504237640184e-10,
                /*data r(25)*/ -.776885222849778e-10, /*r(26)*/ -.1076574385252767e-09,
                /*data r(27)*/ -.1488228429491196e-09, /*r(28)*/ -.2052263914575559e-09,
                /*data r(29)*/ -.2823158374142204e-09, /*r(30)*/ -.3874147670086474e-09,
                /*data r(31)*/ -.5303423257515197e-09, /*r(32)*/ -.7242291213807226e-09,
                /*data r(33)*/ -.9865877009111562e-09, /*r(34)*/ -.134071243086345e-08,
                /*data r(35)*/ -.181750781257116e-08, /*r(36)*/ -.2457865025640902e-08,
                /*data r(37)*/ -.3315746016587054e-08, /*r(38)*/ -.4462172419302919e-08,
                /*data r(39)*/ -.5990371439069619e-08, /*r(40)*/ -.8022391894107592e-08,
                /*data r(41)*/ -.1071759031715677e-07, /*r(42)*/ -.1428347994534444e-07,
                /*data r(43)*/ -.1898956265833513e-07, /*r(44)*/ -.2518491036346734e-07,
                /*data r(45)*/ -.3332044906657968e-07, /*r(46)*/ -.4397711691582782e-07,
                /*data r(47)*/ -.5790134206524873e-07, /*r(48)*/ -.7604960806059773e-07,
                /*data r(49)*/ -.9964426813848227e-07, /*r(50)*/ -.130243238016349e-06,
                /*data r(51)*/ -.1698267550907938e-06, /*r(52)*/ -.2209050566660918e-06,
                /*data r(53)*/ -.2866516130081046e-06, /*r(54)*/ -.3710674767571234e-06,
                /*data r(55)*/ -.4791833914221242e-06, /*r(56)*/ -.6173075625315513e-06,
                /*data r(57)*/ -.7933284666339352e-06, /*r(58)*/ -.1017083759745548e-05,
                /*data r(59)*/ -.1300808299914155e-05, /*r(60)*/ -.1659676521578845e-05,
                /*data r(61)*/ -.2112456933732011e-05, /*r(62)*/ -.2682299376960864e-05,
                /*data r(63)*/ -.3397678896843112e-05, /*r(64)*/ -.4293523687114815e-05,
                /*data r(65)*/ -.5412558555603229e-05, /*r(66)*/ -.6806899766264155e-05,
                /*data r(67)*/ -.8539941936205909e-05, /*r(68)*/ -.1068858289760318e-04,
                /*data r(69)*/ -.1334583807120353e-04, /*r(70)*/ -.1662390190597559e-04,
                /*data r(71)*/ -.2065772028172582e-04, /*r(72)*/ -.2560914438540419e-04,
                /*data r(73)*/ -.3167174337748929e-04, /*r(74)*/ -.3907636006878421e-04,
                /*data r(75)*/ -.4809750068383132e-04, /*r(76)*/ -.5906065646521043e-04,
                /*data r(77)*/ -.7235066117105132e-04, /*r(78)*/ -.8842119423939519e-04,
                /*data r(79)*/ -.1078055442862845e-03, /*r(80)*/ -.1311287514194654e-03,
                /*data r(81)*/ -.1591212492720841e-03, /*r(82)*/ -.1926341283980515e-03,
                /*data r(83)*/ -.2326561413768194e-03, /*r(84)*/ -.2803325663186314e-03,
                /*data r(85)*/ -.3369860390946651e-03, /*r(86)*/ -.4041394552135121e-03,
                /*data r(87)*/ -.4835410295067237e-03, /*r(88)*/ -.577191585409949e-03,
                /*data r(89)*/ -.6873741253905021e-03, /*r(90)*/ -.8166857098364631e-03,
                /*data r(91)*/ -.9680716434015077e-03, /*r(92)*/ -.1144861935423052e-02,
                /*data r(93)*/ -.1350809964748202e-02, /*r(94)*/ -.1590133239375676e-02,
                /*data r(95)*/ -.1867556098180926e-02, /*r(96)*/ -.2188354156192187e-02,
                /*data r(97)*/ -.2558400247160518e-02, /*r(98)*/ -.2984211568374077e-02,
                /*data r(99)*/ -.3472997683837415e-02, /*r(100)*/ -.4032708994200948e-02,
                /*data r(101)*/ -.4672085236439271e-02, /*r(102)*/ -.5400703534551409e-02,
                /*data r(103)*/ -.622902548585991e-02, /*r(104)*/ -.7168442737160194e-02,
                /*data r(105)*/ -.823132048231313e-02, /*r(106)*/ -.9431038299075455e-02,
                /*data r(107)*/ -.1078202773905185e-01, /*r(108)*/ -.1229980609144914e-01,
                /*data r(109)*/ -.1400100575938433e-01, /*r(110)*/ -.1590339871712135e-01,
                /*data r(111)*/ -.180259155577274e-01, /*r(112)*/ -.2038865869285799e-01,
                /*data r(113)*/ -.2301290932896313e-01, /*r(114)*/ -.2592112791607553e-01,
                /*data r(115)*/ -.2913694784510533e-01, /*r(116)*/ -.3268516225556619e-01,
                /*data r(117)*/ -.3659170390600892e-01, /*r(118)*/ -.4088361815209435e-01,
                /*data r(119)*/ -.455890291700683e-01, /*r(120)*/ -.5073709965425603e-01,
                /*data r(121)*/ -.56357984303983e-01, /*r(122)*/ -.6248277749609433e-01,
                /*data r(123)*/ -.6914345561223305e-01, /*r(124)*/ -.7637281455373084e-01,
                /*data r(125)*/ -.8420440303017174e-01, /*r(126)*/ -.926724522495226e-01,
                /*data r(127)*/ -.1018118026676539e00, /*r(128)*/ -.1116578284729239e00,
                /*data r(129)*/ -.1222463604874165e00, /*r(130)*/ -.133613608160869e00,
                /*data r(131)*/ -.1457960813170513e00, /*r(132)*/ -.1588305122863204e00,
                /*data r(133)*/ -.1727537790234482e00, /*r(134)*/ -.1876028297678836e00,
                /*data r(135)*/ -.203414609755745e00, /*r(136)*/ -.2202259904404449e00,
                /*data r(137)*/ -.2380737016233259e00, /*r(138)*/ -.2569942668383629e00,
                /*data r(139)*/ -.2770239422771288e00, /*r(140)*/ -.2981986594829503e00,
                /*data r(141)*/ -.3205539719875162e00, /*r(142)*/ -.3441250060099932e00,
                /*data r(143)*/ -.3689464152886534e00, /*r(144)*/ -.3950523400687012e00,
                /*data r(145)*/ -.4224763702277728e00, /*r(146)*/ -.4512515124827797e00,
                /*data r(147)*/ -.4814101615884777e00, /*r(148)*/ -.5129840754094268e00,
                /*data r(149)*/ -.5460043537227704e00, /*r(150)*/ -.5805014205893657e00,
                /*data r(151)*/ -.616505010115022e00, /*r(152)*/ -.6540441554116743e00,
                /*data r(153)*/ -.7338416953693647e00, /*r(154)*/ -.7761545927302784e00,
                /*data r(155)*/ -.8201120483516769e00, /*r(156)*/ -.8657395226816005e00,
                /*data r(157)*/ -.9130617648111405e00, /*r(158)*/ -.9621028181688563e00,
                /*data r(159)*/ -.1012886027819567e01, /*r(160)*/ -.1065434049189583e01,
                /*data r(161)*/ -.111976885804932e01, /*r(162)*/ -.1175911761593625e01,
                /*data r(163)*/ -.1233883410469901e01, /*r(164)*/ -.1293703811614035e01,
                /*data r(165)*/ -.1355392341764083e01, /*r(166)*/ -.1418967761531539e01,
                /*data r(167)*/ -.1484448229919664e01, /*r(168)*/ -.1551851319187785e01,
                /*data r(169)*/ -.1621194029969489e01, /*r(170)*/ -.1692492806561346e01,
                /*data r(171)*/ -.1765763552306998e01, /*r(172)*/ -.1841021645009272e01,
                /*data r(173)*/ -.1918281952310279e01, /*r(174)*/ -.1997558846986307e01,
                /*data r(175)*/ -.2078866222110689e01, /*r(176)*/ -.216221750604375e01,
                /*data r(177)*/ -.2247625677214329e01, /*r(178)*/ -.2335103278662453e01,
                /*data r(179)*/ -.2424662432317242e01, /*r(180)*/ -.2516314852988339e01,
                /*data r(181)*/ -.2610071862052941e01, /*r(182)*/ -.2705944400823903e01,
                /*data r(183)*/ -.280394304358751e01, /*r(184)*/ -.2904078010302258e01,
                /*data r(185)*/ -.300635917895243e01, /*r(186)*/ -.3110796097552495e01,
                /*data r(187)*/ -.3217397995800287e01, /*r(188)*/ -.3326173796378607e01,
                /*data r(189)*/ -.3437132125906423e01, /*r(190)*/ -.3550281325542148e01,
                /*data r(191)*/ -.3665629461242573e01, /*r(192)*/ -.3783184333682046e01,
                /*data r(193)*/ -.3902953487837305e01, /*r(194)*/ -.4024944222244003e01,
                /*data r(195)*/ -.4149163597931659e01, /*r(196)*/ -.427561844704416e01,
                /*data r(197)*/ -.4404315381153292e01, /*r(198)*/ -.4535260799273172e01,
                /*data r(199)*/ -.4668460895583632e01, /*r(200)*/ -.4803921666870696e01,
                /*data r(201)*/ -.4941648919692438e01, /*r(202)*/ -.5081648277278704e01,
                /*data r(203)*/ -.5223925186172927e01, /*r(204)*/ -.5368484922624293e01,
                /*data r(205)*/ -.5515332598738667e01, /*r(206)*/ -.5664473168396457e01,
                /*data r(207)*/ -.5815911432945259e01, /*r(208)*/ -.5969652046675234e01,
                /*data r(209)*/ -.6125699522085338e01, /*r(210)*/ -.6284058234947415e01,
                /*data r(211)*/ -.6444732429175935e01, /*r(212)*/ -.6607726221510343e01,
                /*data r(213)*/ -.6773043606017728e01, /*r(214)*/ -.6940688458421271e01,
                /*data r(215)*/ -.7110664540262647e01, /*r(216)*/ -.7282975502903613e01,
                /*data r(217)*/ -.7457624891374113e01, /*r(218)*/ -.7634616148071119e01,
                /*data r(219)*/ -.7813952616316348e01, /*r(220)*/ -.799563754377673e01,
                /*data r(221)*/ -.8179674085752888e01, /*r(222)*/ -.8366065308344028e01,
                /*data r(223)*/ -.8554814191487645e01, /*r(224)*/ -.874592363188728e01,
                /*data r(225)*/ -.8939396445825637e01, /*r(226)*/ -.913523537187268e01,
                /*data r(227)*/ -.9333443073489079e01, /*r(228)*/ -.9534022141533047e01,
                /*data r(229)*/ -.9736975096667792e01, /*r(230)*/ -.9942304391691628e01,
                /*data r(231)*/ -.1015001241375612e02, /*r(232)*/ -.1036010148652729e02,
                /*data r(233)*/ -.1057257387225042e02, /*r(234)*/ -.1078743177374731e02,
                /*data r(235)*/ -.1100467733631163e02, /*r(236)*/ -.1122431264960134e02,
                /*data r(237)*/ -.1144633974936864e02, /*r(238)*/ -.1167076061919396e02,
                /*data r(239)*/ -.1189757719215191e02, /*r(240)*/ -.1212679135238504e02,
                /*data r(241)*/ -.123584049366392e02, /*r(242)*/ -.1259241973571053e02,
                /*data r(243)*/ -.1282883749596439e02, /*r(244)*/ -.1306765992055022e02,
                /*data r(245)*/ -.1330888867094168e02, /*r(246)*/ -.1355252536795449e02,
                /*data r(247)*/ -.1379857159319925e02, /*r(248)*/ -.1404702889012706e02,
                /*data r(249)*/ -.1429789876529278e02, /*r(250)*/ -.1455118268930635e02,
                /*data r(251)*/ -.1480688209835897e02, /*r(252)*/ -.1506499839383404e02,
                /*data r(253)*/ -.1532553294603481e02, /*r(254)*/ -.1558848709213367e02,
                /*data r(255)*/ -.1585386213820371e02, /*r(256)*/ -.1612165936169902e02,
                /*data r(257)*/ -.1639188000998599e02, /*r(258)*/ -.1666452530256692e02,
                /*data r(259)*/ -.1693959643039488e02, /*r(260)*/ -.1721709455901047e02,
                /*data r(261)*/ -.1749702082947138e02, /*r(262)*/ -.1777937635198566e02,
                /*data r(263)*/ -.1806416222321361e02, /*r(264)*/ -.1835137949577754e02,
                /*data r(265)*/ -.1864102922238369e02, /*r(266)*/ -.189331124198754e02,
                /*data r(267)*/ -.1922763010220532e02, /*r(268)*/ -.1952458319757374e02,
                /*data r(269)*/ -.19823972740809e02, /*r(270)*/ -.2012579960891278e02,
                /*data r(271)*/ -.2043006470011414e02, /*r(272)*/ -.2073676889383496e02,
                /*data r(273)*/ -.2104591330797427e02, /*r(274)*/ -.2135749842050528e02,
                /*data r(275)*/ -.2167152524762946e02, /*r(276)*/ -.2198799468102285e02,
                /*data r(277)*/ -.2230690739766362e02, /*r(278)*/ -.2262826449094309e02,
                /*data r(279)*/ -.2295206679539271e02, /*r(280)*/ -.2327831358784527e02,
                /*data r(281)*/ -.2360700885084431e02, /*r(282)*/ -.239381499780087e02,
                /*data r(283)*/ -.2427173857908781e02, /*r(284)*/ -.2460777636910266e02,
                /*data r(285)*/ -.2494626609563959e02, /*r(286)*/ -.2528719836457364e02,
                /*data r(287)*/ -.2563058098225117e02, /*r(288)*/ -.2597643264459843e02,
                /*data r(289)*/ -.263247198835277e02, /*r(290)*/ -.2667545493252539e02,
                /*data r(291)*/ -.2702865902505768e02, /*r(292)*/ -.2738426643199774e02,
                /*data r(293)*/ -.2774237990392581e02, /*r(294)*/ -.281028915785649e02,
                /*data r(295)*/ -.2846601955651443e02, /*r(296)*/ -.2883135892061681e02,
                /*data r(297)*/ -.2919937053309059e02, /*r(298)*/ -.2956976269276488e02,
                /*data r(299)*/ -.299422139888006e02, /*r(300)*/ -.3031843563374089e02,
                /*data r(301)*/ -.3069654585839969e02, /*r(302)*/ -.3107731835391748e02,
                /*data r(303)*/ -.3145868591044658e02, /*r(304)*/ -.3184645144145535e02};
            double[] s ={
                0.0,
                /*data s(1)*/ -.2979893853320468e02, /*s(2)*/ -.2942018853320467e02,
                /*data s(3)*/ -.2904393853320467e02, /*s(4)*/ -.2867018853320467e02,
                /*data s(5)*/ -.2829893853320467e02, /*s(6)*/ -.2793018853320467e02,
                /*data s(7)*/ -.2756393853320467e02, /*s(8)*/ -.2720018853320467e02,
                /*data s(9)*/ -.2683893853320467e02, /*s(10)*/ -.2648018853320467e02,
                /*data s(11)*/ -.2612393853320467e02, /*s(12)*/ -.2577018853320467e02,
                /*data s(13)*/ -.2541893853320467e02, /*s(14)*/ -.2507018853320467e02,
                /*data s(15)*/ -.2472393853320467e02, /*s(16)*/ -.2438018853320467e02,
                /*data s(17)*/ -.2403893853320467e02, /*s(18)*/ -.2370018853320467e02,
                /*data s(19)*/ -.2336393853320467e02, /*s(20)*/ -.2303018853320467e02,
                /*data s(21)*/ -.2269893853320467e02, /*s(22)*/ -.2237018853320467e02,
                /*data s(23)*/ -.2204393853320467e02, /*s(24)*/ -.2172018853320467e02,
                /*data s(25)*/ -.2139893853320467e02, /*s(26)*/ -.2108018853320467e02,
                /*data s(27)*/ -.2076393853320467e02, /*s(28)*/ -.2045018853320467e02,
                /*data s(29)*/ -.2013893853320467e02, /*s(30)*/ -.1983018853320467e02,
                /*data s(31)*/ -.1952393853320466e02, /*s(32)*/ -.1922018853320467e02,
                /*data s(33)*/ -.1891893853320467e02, /*s(34)*/ -.1862018853320466e02,
                /*data s(35)*/ -.1832393853320467e02, /*s(36)*/ -.1803018853320466e02,
                /*data s(37)*/ -.1773893853320467e02, /*s(38)*/ -.1745018853320467e02,
                /*data s(39)*/ -.1716393853320466e02, /*s(40)*/ -.1688018853320466e02,
                /*data s(41)*/ -.1659893853320466e02, /*s(42)*/ -.1632018853320466e02,
                /*data s(43)*/ -.1604393853320466e02, /*s(44)*/ -.1577018853320466e02,
                /*data s(45)*/ -.1549893853320466e02, /*s(46)*/ -.1523018853320466e02,
                /*data s(47)*/ -.1496393853320466e02, /*s(48)*/ -.1470018853320466e02,
                /*data s(49)*/ -.1443893853320466e02, /*s(50)*/ -.1418018853320466e02,
                /*data s(51)*/ -.1392393853320466e02, /*s(52)*/ -.1367018853320466e02,
                /*data s(53)*/ -.1341893853320466e02, /*s(54)*/ -.1317018853320466e02,
                /*data s(55)*/ -.1292393853320466e02, /*s(56)*/ -.1268018853320466e02,
                /*data s(57)*/ -.1243893853320466e02, /*s(58)*/ -.1220018853320466e02,
                /*data s(59)*/ -.1196393853320466e02, /*s(60)*/ -.1173018853320466e02,
                /*data s(61)*/ -.1149893853320466e02, /*s(62)*/ -.1127018853320466e02,
                /*data s(63)*/ -.1104393853320466e02, /*s(64)*/ -.1082018853320466e02,
                /*data s(65)*/ -.1059893853320466e02, /*s(66)*/ -.1038018853320466e02,
                /*data s(67)*/ -.1016393853320466e02, /*s(68)*/ -.995018853320466e01,
                /*data s(69)*/ -.973893853320466e01, /*s(70)*/ -.953018853320466e01,
                /*data s(71)*/ -.932393853320466e01, /*s(72)*/ -.912018853320466e01,
                /*data s(73)*/ -.891893853320466e01, /*s(74)*/ -.872018853320466e01,
                /*data s(75)*/ -.852393853320466e01, /*s(76)*/ -.833018853320466e01,
                /*data s(77)*/ -.813893853320466e01, /*s(78)*/ -.795018853320466e01,
                /*data s(79)*/ -.776393853320466e01, /*s(80)*/ -.758018853320466e01,
                /*data s(81)*/ -.739893853320466e01, /*s(82)*/ -.722018853320466e01,
                /*data s(83)*/ -.704393853320466e01, /*s(84)*/ -.687018853320466e01,
                /*data s(85)*/ -.669893853320466e01, /*s(86)*/ -.653018853320466e01,
                /*data s(87)*/ -.636393853320466e01, /*s(88)*/ -.620018853320466e01,
                /*data s(89)*/ -.603893853320466e01, /*s(90)*/ -.588018853320466e01,
                /*data s(91)*/ -.572393853320466e01, /*s(92)*/ -.5570188533204661e01,
                /*data s(93)*/ -.5418938533204661e01, /*s(94)*/ -.5270188533204661e01,
                /*data s(95)*/ -.5123938533204661e01, /*s(96)*/ -.4980188533204661e01,
                /*data s(97)*/ -.4838938533204661e01, /*s(98)*/ -.4700188533204661e01,
                /*data s(99)*/ -.4563938533204661e01, /*s(100)*/ -.4430188533204661e01,
                /*data s(101)*/ -.4298938533204661e01, /*s(102)*/ -.4170188533204661e01,
                /*data s(103)*/ -.4043938533204662e01, /*s(104)*/ -.3920188533204662e01,
                /*data s(105)*/ -.3798938533204662e01, /*s(106)*/ -.3680188533204662e01,
                /*data s(107)*/ -.3563938533204662e01, /*s(108)*/ -.3450188533204662e01,
                /*data s(109)*/ -.3338938533204662e01, /*s(110)*/ -.3230188533204662e01,
                /*data s(111)*/ -.3123938533204662e01, /*s(112)*/ -.3020188533204663e01,
                /*data s(113)*/ -.2918938533204663e01, /*s(114)*/ -.2820188533204663e01,
                /*data s(115)*/ -.2723938533204663e01, /*s(116)*/ -.2630188533204663e01,
                /*data s(117)*/ -.2538938533204663e01, /*s(118)*/ -.2450188533204664e01,
                /*data s(119)*/ -.2363938533204664e01, /*s(120)*/ -.2280188533204664e01,
                /*data s(121)*/ -.2198938533204664e01, /*s(122)*/ -.2120188533204665e01,
                /*data s(123)*/ -.2043938533204665e01, /*s(124)*/ -.1970188533204665e01,
                /*data s(125)*/ -.1898938533204665e01, /*s(126)*/ -.1830188533204665e01,
                /*data s(127)*/ -.1763938533204665e01, /*s(128)*/ -.1700188533204666e01,
                /*data s(129)*/ -.1638938533204666e01, /*s(130)*/ -.1580188533204666e01,
                /*data s(131)*/ -.1523938533204666e01, /*s(132)*/ -.1470188533204667e01,
                /*data s(133)*/ -.1418938533204667e01, /*s(134)*/ -.1370188533204667e01,
                /*data s(135)*/ -.1323938533204668e01, /*s(136)*/ -.1280188533204668e01,
                /*data s(137)*/ -.1238938533204668e01, /*s(138)*/ -.1200188533204668e01,
                /*data s(139)*/ -.1163938533204669e01, /*s(140)*/ -.1130188533204669e01,
                /*data s(141)*/ -.1098938533204669e01, /*s(142)*/ -.1070188533204669e01,
                /*data s(143)*/ -.104393853320467e01, /*s(144)*/ -.102018853320467e01,
                /*data s(145)*/ -.9989385332046704e00, /*s(146)*/ -.9801885332046707e00,
                /*data s(147)*/ -.9639385332046709e00, /*s(148)*/ -.9501885332046712e00,
                /*data s(149)*/ -.9389385332046715e00, /*s(150)*/ -.9301885332046718e00,
                /*data s(151)*/ -.9239385332046721e00, /*s(152)*/ -.9201885332046724e00,
                /*data s(153)*/ -.920188533204673e00, /*s(154)*/ -.9239385332046733e00,
                /*data s(155)*/ -.9301885332046736e00, /*s(156)*/ -.9389385332046738e00,
                /*data s(157)*/ -.9501885332046741e00, /*s(158)*/ -.9639385332046744e00,
                /*data s(159)*/ -.9801885332046747e00, /*s(160)*/ -.998938533204675e00,
                /*data s(161)*/ -.1020188533204675e01, /*s(162)*/ -.1043938533204676e01,
                /*data s(163)*/ -.1070188533204676e01, /*s(164)*/ -.1098938533204676e01,
                /*data s(165)*/ -.1130188533204676e01, /*s(166)*/ -.1163938533204677e01,
                /*data s(167)*/ -.1200188533204677e01, /*s(168)*/ -.1238938533204677e01,
                /*data s(169)*/ -.1280188533204678e01, /*s(170)*/ -.1323938533204678e01,
                /*data s(171)*/ -.1370188533204678e01, /*s(172)*/ -.1418938533204678e01,
                /*data s(173)*/ -.1470188533204679e01, /*s(174)*/ -.1523938533204679e01,
                /*data s(175)*/ -.1580188533204679e01, /*s(176)*/ -.163893853320468e01,
                /*data s(177)*/ -.170018853320468e01, /*s(178)*/ -.1763938533204681e01,
                /*data s(179)*/ -.1830188533204681e01, /*s(180)*/ -.1898938533204681e01,
                /*data s(181)*/ -.1970188533204682e01, /*s(182)*/ -.2043938533204682e01,
                /*data s(183)*/ -.2120188533204682e01, /*s(184)*/ -.2198938533204683e01,
                /*data s(185)*/ -.2280188533204683e01, /*s(186)*/ -.2363938533204684e01,
                /*data s(187)*/ -.2450188533204684e01, /*s(188)*/ -.2538938533204684e01,
                /*data s(189)*/ -.2630188533204685e01, /*s(190)*/ -.2723938533204685e01,
                /*data s(191)*/ -.2820188533204686e01, /*s(192)*/ -.2918938533204686e01,
                /*data s(193)*/ -.3020188533204686e01, /*s(194)*/ -.3123938533204687e01,
                /*data s(195)*/ -.3230188533204687e01, /*s(196)*/ -.3338938533204688e01,
                /*data s(197)*/ -.3450188533204688e01, /*s(198)*/ -.3563938533204689e01,
                /*data s(199)*/ -.3680188533204689e01, /*s(200)*/ -.3798938533204689e01,
                /*data s(201)*/ -.392018853320469e01, /*s(202)*/ -.404393853320469e01,
                /*data s(203)*/ -.4170188533204691e01, /*s(204)*/ -.4298938533204691e01,
                /*data s(205)*/ -.4430188533204692e01, /*s(206)*/ -.4563938533204692e01,
                /*data s(207)*/ -.4700188533204693e01, /*s(208)*/ -.4838938533204693e01,
                /*data s(209)*/ -.4980188533204694e01, /*s(210)*/ -.5123938533204694e01,
                /*data s(211)*/ -.5270188533204695e01, /*s(212)*/ -.5418938533204695e01,
                /*data s(213)*/ -.5570188533204696e01, /*s(214)*/ -.5723938533204696e01,
                /*data s(215)*/ -.5880188533204697e01, /*s(216)*/ -.6038938533204697e01,
                /*data s(217)*/ -.6200188533204698e01, /*s(218)*/ -.6363938533204698e01,
                /*data s(219)*/ -.6530188533204699e01, /*s(220)*/ -.66989385332047e01,
                /*data s(221)*/ -.68701885332047e01, /*s(222)*/ -.7043938533204701e01,
                /*data s(223)*/ -.7220188533204701e01, /*s(224)*/ -.7398938533204702e01,
                /*data s(225)*/ -.7580188533204702e01, /*s(226)*/ -.7763938533204703e01,
                /*data s(227)*/ -.7950188533204703e01, /*s(228)*/ -.8138938533204704e01,
                /*data s(229)*/ -.8330188533204704e01, /*s(230)*/ -.8523938533204705e01,
                /*data s(231)*/ -.8720188533204706e01, /*s(232)*/ -.8918938533204706e01,
                /*data s(233)*/ -.9120188533204706e01, /*s(234)*/ -.9323938533204708e01,
                /*data s(235)*/ -.9530188533204708e01, /*s(236)*/ -.9738938533204708e01,
                /*data s(237)*/ -.995018853320471e01, /*s(238)*/ -.1016393853320471e02,
                /*data s(239)*/ -.1038018853320471e02, /*s(240)*/ -.1059893853320471e02,
                /*data s(241)*/ -.1082018853320471e02, /*s(242)*/ -.1104393853320471e02,
                /*data s(243)*/ -.1127018853320471e02, /*s(244)*/ -.1149893853320471e02,
                /*data s(245)*/ -.1173018853320471e02, /*s(246)*/ -.1196393853320471e02,
                /*data s(247)*/ -.1220018853320471e02, /*s(248)*/ -.1243893853320472e02,
                /*data s(249)*/ -.1268018853320472e02, /*s(250)*/ -.1292393853320472e02,
                /*data s(251)*/ -.1317018853320472e02, /*s(252)*/ -.1341893853320472e02,
                /*data s(253)*/ -.1367018853320472e02, /*s(254)*/ -.1392393853320472e02,
                /*data s(255)*/ -.1418018853320472e02, /*s(256)*/ -.1443893853320472e02,
                /*data s(257)*/ -.1470018853320472e02, /*s(258)*/ -.1496393853320472e02,
                /*data s(259)*/ -.1523018853320472e02, /*s(260)*/ -.1549893853320472e02,
                /*data s(261)*/ -.1577018853320472e02, /*s(262)*/ -.1604393853320473e02,
                /*data s(263)*/ -.1632018853320473e02, /*s(264)*/ -.1659893853320473e02,
                /*data s(265)*/ -.1688018853320473e02, /*s(266)*/ -.1716393853320473e02,
                /*data s(267)*/ -.1745018853320473e02, /*s(268)*/ -.1773893853320473e02,
                /*data s(269)*/ -.1803018853320473e02, /*s(270)*/ -.1832393853320473e02,
                /*data s(271)*/ -.1862018853320473e02, /*s(272)*/ -.1891893853320473e02,
                /*data s(273)*/ -.1922018853320473e02, /*s(274)*/ -.1952393853320473e02,
                /*data s(275)*/ -.1983018853320474e02, /*s(276)*/ -.2013893853320474e02,
                /*data s(277)*/ -.2045018853320474e02, /*s(278)*/ -.2076393853320474e02,
                /*data s(279)*/ -.2108018853320474e02, /*s(280)*/ -.2139893853320474e02,
                /*data s(281)*/ -.2172018853320474e02, /*s(282)*/ -.2204393853320474e02,
                /*data s(283)*/ -.2237018853320474e02, /*s(284)*/ -.2269893853320475e02,
                /*data s(285)*/ -.2303018853320474e02, /*s(286)*/ -.2336393853320474e02,
                /*data s(287)*/ -.2370018853320474e02, /*s(288)*/ -.2403893853320475e02,
                /*data s(289)*/ -.2438018853320475e02, /*s(290)*/ -.2472393853320475e02,
                /*data s(291)*/ -.2507018853320475e02, /*s(292)*/ -.2541893853320475e02,
                /*data s(293)*/ -.2577018853320475e02, /*s(294)*/ -.2612393853320475e02,
                /*data s(295)*/ -.2648018853320475e02, /*s(296)*/ -.2683893853320475e02,
                /*data s(297)*/ -.2720018853320476e02, /*s(298)*/ -.2756393853320475e02,
                /*data s(299)*/ -.2793018853320476e02, /*s(300)*/ -.2829893853320476e02,
                /*data s(301)*/ -.2867018853320476e02, /*s(302)*/ -.2904393853320476e02,
                /*data s(303)*/ -.2942018853320476e02, /*s(304)*/ -.2979893853320476e02};
            int j;
            int ii = i;
            double x = 0.0;
            if (n < 1)
                return x;
            if (i < 1)
                ii = 1;
            if (i > n)
                ii = n;
            int ioe = n % 2;
            int m = (n + 1) / 2;
            if (ii - m == 0 && ioe != 0)
                return 0.0;
            const double seta = Constant.DBL_MIN;
            double smexe = Math.Log(seta);
            double alogp5 = Math.Log(0.5);
            double f = 0.0;
            double fn = n + 1;
            double fr = n + 1 - ii;
            double fi = ii;
            fn = alogam(fn);
            fr = alogam(fr);
            fi = alogam(fi);
            double fff = fn - fr - fi;
            double ri = ii - 1;
            double rn = n - ii;
            double p = fff + q[152] + ri * r[1] + rn * r[304] + s[1];
            if (p >= smexe + alogp5) f = -0.5 * Math.Exp(p);
            for (j = 2; j <= 152; j++)
            {
                p = fff + q[153 - j] + ri * r[j] + rn * r[305 - j] + s[j];
                if (p >= smexe) f -= Math.Exp(p);
            }
            for (j = 153; j <= 303; j++)
            {
                p = fff + q[j - 152] + ri * r[j] + rn * r[305 - j] + s[j];
                if (p >= smexe) f += Math.Exp(p);
            }
            p = fff + q[152] + ri * r[304] + rn * r[1] + s[304];
            if (p >= smexe + alogp5) f += 0.5 * Math.Exp(p);
            return -.05 * f;
        }

        //  Gauss-Legendre rule with 16 points on [-1, 1]: the positive nodes and their weights (the rule is symmetric)
        private static readonly double[] GaussLegendre16Nodes = { 0.989400934991649932596154173450, 0.944575023073232576077988415535, 0.865631202387831743880467897712, 0.755404408355003033895101194847, 0.617876244402643748446671764049, 0.458016777657227386342419442984, 0.281603550779258913230460501460, 0.0950125098376374401853193354250 };
        private static readonly double[] GaussLegendre16Weights = { 0.0271524594117540948517805724560, 0.0622535239386478928628438369944, 0.0951585116824927848099251076022, 0.124628971255533872052476282192, 0.149595988816576732081501730547, 0.169156519395002538189312079030, 0.182603415044923588866763667969, 0.189450610455068496285396723208 };

        //  Composite Gauss-Legendre integral of f over [a, b] in equal panels
        private static double GaussLegendre(Func<double, double> f, double a, double b, int panels)
        {
            double width = (b - a) / panels;
            double half = 0.5 * width;
            double sum = 0.0;
            for (int panel = 0; panel < panels; panel++)
            {
                double mid = a + (panel + 0.5) * width;
                for (int i = 0; i < 8; i++)
                {
                    double x = half * GaussLegendre16Nodes[i];
                    sum += GaussLegendre16Weights[i] * (f(mid + x) + f(mid - x));
                }
            }
            return sum * half;
        }

        //  P(range of k standard normal variates <= w)
        private static double RangeProbability(double w, int k)
        {
            if (w <= 0.0)
                return 0.0;
            double root2pi = Math.Sqrt(2.0 * Constant.PI);
            return k * GaussLegendre(z => Math.Exp(-0.5 * z * z) / root2pi * Math.Pow(alnorm(z + w) - alnorm(z), k - 1), -9.0, 9.0, 8);
        }

        //  The Studentized range distribution for few residual degrees of freedom, by direct integration over the
        //  distribution of the residual standard deviation: P(Q <= q) = E[ P(range <= q S) ], S = chi / root df.
        //  The series routine (qprob) is accurate only to two or three decimals below five degrees of freedom.
        private static double SmallDfRangeCdf(double q, int k, double df)
        {
            if (q <= 0.0)
                return 0.0;
            //  Integrate over y = log S, which spreads the small values of S where, for many means and a large q, the
            //  range probability rises from 0 to 1 within a narrow band; the limits are the chi-square points at 1e-12
            double ylo = 0.5 * Math.Log(ppchi2(1.0e-12, df, out int _) / df);
            double yhi = 0.5 * Math.Log(ppchi2(1.0 - 1.0e-12, df, out int _) / df);
            double logConstant = 0.5 * df * Math.Log(df) - (0.5 * df - 1.0) * Math.Log(2.0) - alogam(0.5 * df);
            return GaussLegendre(y =>
            {
                double s = Math.Exp(y);
                return Math.Exp(logConstant + df * y - 0.5 * df * s * s) * RangeProbability(q * s, k);
            }, ylo, yhi, 32);
        }

        private static double SmallDfRangeQuantile(double p, int k, double df)
        {
            //  Bracket the point around the series routine's value (within a few per cent), then the Illinois method
            int[] ir = new int[4];
            double guess = cv(p, 1.0, k, df, ir);
            if (ir[1] != 0 || ir[2] != 0 || ir[3] != 0 || !(guess > 0.0))
                guess = 10.0;
            double a = 0.5 * guess;
            double b = 2.0 * guess;
            double fa = SmallDfRangeCdf(a, k, df) - p;
            double fb = SmallDfRangeCdf(b, k, df) - p;
            while (fa > 0.0 && a > 1.0e-6)
            {
                a *= 0.5;
                fa = SmallDfRangeCdf(a, k, df) - p;
            }
            while (fb < 0.0 && b < 1.0e6)
            {
                b *= 2.0;
                fb = SmallDfRangeCdf(b, k, df) - p;
            }
            int side = 0;
            double c = a;
            for (int i = 0; i < 100 && Math.Abs(b - a) > 1.0e-11 * Math.Max(1.0, Math.Abs(b)); i++)
            {
                c = (a * fb - b * fa) / (fb - fa);
                double fc = SmallDfRangeCdf(c, k, df) - p;
                if (fc == 0.0)
                    break;
                if (fc * fb > 0.0)
                {
                    b = c;
                    fb = fc;
                    if (side == -1)
                        fa *= 0.5;
                    side = -1;
                }
                else
                {
                    a = c;
                    fa = fc;
                    if (side == 1)
                        fb *= 0.5;
                    side = 1;
                }
            }
            return c;
        }

        public static double quantsr(double p, double t, double df)
        {
            if (df < 1.0)
                return Constant.MISSING;
            if (t == 2.0)   //  two means: the range is root 2 times |t|, so the point comes exactly from Student's t
                return Math.Sqrt(2.0) * tfromp2(1.0 - p, df);
            if (df < 5.0)
                return SmallDfRangeQuantile(p, (int)Math.Round(t), df);
            int[] ir = new int[4];
            double retval = cv(p, 1.0, t, df, ir);
            for (int i = 1; i <= 3; i++)
            {
                if (0 != ir[i])
                    return Constant.MISSING;
            }
            return retval;
        }

        public static double probsr(double q, double t, double df)
        {
            if (df < 1.0)
                return Constant.MISSING;
            if (t == 2.0)
                return 1.0 - 2.0 * tvalp(q / Math.Sqrt(2.0), df);   //  tvalp is the one tail area
            if (df < 5.0)
                return SmallDfRangeCdf(q, (int)Math.Round(t), df);
            int[] ir = new int[3];
            double retval = qprob(q, 1.0, t, df, ir);
            for (int i = 1; i <= 2; i++)
            {
                if (0 != ir[i])
                    return Constant.MISSING;
            }
            return retval;
        }

        /// <summary>
        /// uses secant method to find critical values.
        /// 
        /// program will not terminate if ir(1) or ir(2) are raised.
        /// program will terminate if ir(3) is raised.
        ///
        /// if difference between successive iterates &lt; eps, search is terminated
        /// </summary>
        /// <param name="p">confidence level (1 - alpha)</param>
        /// <param name="rr">no. of rows or groups</param>
        /// <param name="cc">no. of columns or treatments</param>
        /// <param name="df">degrees of freedom of error term</param>
        /// <param name="ir">ir(1) = error flag = 1 if wprob probability > 1
        /// ir(2) = error flag = 1 if qprob probability > 1
        /// ir(3) = error flag = 1 if convergence not reached in 50 iterations
        ///                    = 2 if df &lt; 2</param>
        /// <returns>critical value</returns>
        /// <remarks>
        /// see copenhaver, margaret diponzio & holland, burt s.:
        /// multiple comparisons of simple effects in the two-way analysis
        /// of variance with fixed effects.  journal of statistical computation
        /// and simulation, vol.30, pp.1-15, 1988.
        /// </remarks>
        private static double cv(double p, double rr, double cc, double df, int[] ir/* [4] */)
        {
            const double eps = 0.00000001;
            int[] it = new int[3];
            // df must be > 1
            if (df < 2.0)
            {
                ir[3] = 2;
                return 0;
            }
            int iter = 0;
            // initial value using user-written function
            ir[1] = 0;
            ir[2] = 0;
            ir[3] = 0;
            // find prob(value < x0)
            double x0 = qinv(p, cc, df);
            double valx0 = qprob(x0, rr, cc, df, it) - p;
            if (1 == it[1])
                ir[1] = 1;
            // find second iterate and prob(value < x1)
            // if first iterate has probability value exceeding p then second iterate is 1 less than first iterate else it is 1 greater
            if (1 == it[2])
                ir[2] = 1;
            double x1;
            if (valx0 > 0.0)
            {
                x1 = Math.Max(0.0, x0 - 1.0);
            }
            else
            {
                x1 = x0 + 1.0;
            }
            double valx1 = qprob(x1, rr, cc, df, it) - p;
            if (1 == it[1])
                ir[1] = 1;
            // find new iterate
            if (1 == it[2])
                ir[2] = 1;
            do
            {
                double retval = x1 - valx1 * (x1 - x0) / (valx1 - valx0);
                valx0 = valx1;
                // new iterate must be >= 0
                x0 = x1;
                if (retval < 0.0)
                {
                    retval = 0.0;
                    // valx1 = -p; - redundant statement
                }
                // find prob(value < new iterate)
                valx1 = qprob(retval, rr, cc, df, it) - p;
                if (1 == it[1])
                    ir[1] = 1;
                if (1 == it[2])
                    ir[2] = 1;
                x1 = retval;
                iter++;
                if (51 == iter)
                {
                    ir[3] = 1;
                    return retval;
                }
                // if the difference between two successive iterates < epsilon, stop   
                if (Math.Abs(x1 - x0) < eps)
                    return retval;
            } while (true);
            // Should never get here
        }

        /// <summary>
        /// </summary>
        /// <param name="q">value of studentized range</param>
        /// <param name="rr">no. of rows or groups</param>
        /// <param name="cc">no. of columns or treatments</param>
        /// <param name="df">degrees of freedom of error term</param>
        /// <param name="ir">
        /// ir(1) = error flag = 1 if wprob probability > 1
        /// ir(2) = error flag = 1 if qprob probability > 1
        /// </param>
        /// <returns>probability integral from (0, q)</returns>
        /// <remarks>program will not terminate if er(1) or er(2) are raised.</remarks>
        private static double qprob(double q, double rr, double cc, double df, int[] ir)
        {
            // all references in wprob and alogam to abramowitz and stegun
            // are from the following reference:           
            // abramowitz, milton and stegun, irene a.  handbook of mathematical  
            // functions.  new york:  dover publications, inc. (1970).
            // all constants taken from this text are given to 25 significant digits.     

            // nlegq = order of legendre quadrature
            // ihalfq = int ((nlegq + 1) / 2)
            // eps = max. allowable value of integral
            //
            // eps1 & eps2 = values below which there is no contribution to integral.
            // d.f. <= dhaf:   integral is divided into ulen1 length intervals.  else      
            // d.f. <= dquar:  integral is divided into ulen2 length intervals.  else      
            // d.f. <= deigh:  integral is divided into ulen3 length intervals.  else      
            // d.f. <= dlarg:  integral is divided into ulen4 length intervals.
            //
            // d.f. > dlarg:   the range is used to calculate integral.
            const int nlegq = 16;
            const int ihalfq = 8;
            const double eps = 1.0;
            const double eps1 = -30.0;
            const double eps2 = 1.0e-14;
            const double dhaf = 100.0;
            const double dquar = 800.0;
            const double deigh = 5000.0;
            const double dlarg = 25000.0;
            const double ulen1 = 1.0;
            const double ulen2 = 0.5;
            const double ulen3 = 0.25;
            const double ulen4 = 0.125;
            /*
            c   the coefficients and nodes for the legendre quadrature used in qprob
            c   and wprob were calculated using the algorithms found in:    
            c   stroud, a. h. and secrest, d.  gaussian quadrature formulas.  englewood     
            c   cliffs, new jersey:  prentice-hall, inc, 1966.                      
            c
            c   all values matched the tables (provided in same reference) to 30 significant digits.                                                 
            c        
            c   fortran functions erf, erfc, qexp, log, and qsqrt have maximum relative error:                                        
            c        
            c   max(calc(x) - true(x)) / true(x))                  
            c        
            c   of 8 * 10 ** -33.                                   
            c
            c   f(x) = .5 + erf(x / sqrt(2)) / 2      for x > 0
            c
            c   f(x) = erfc( -x / sqrt(2)) / 2        for x < 0
            c
            c   where f(x) is standard normal c. d. f.
            c
            c   if degrees of freedom large, approximate integral with range distribution.
            c
             */
            // r2 = log(2)
            const double r2 = 0.693147180559945309417232121458;
            // xlegq = legendre 16-point nodes
            double[] xlegq = new[]
            {
                0.0, /* Fortran arrays are 1-based, this is a fake entry */
                0.989400934991649932596154173450e+00, 
                0.944575023073232576077988415535e+00, 
                0.865631202387831743880467897712e+00, 
                0.755404408355003033895101194847e+00, 
                0.617876244402643748446671764049e+00, 
                0.458016777657227386342419442984e+00, 
                0.281603550779258913230460501460e+00, 
                0.950125098376374401853193354250e-01
            };
            // alegq = legendre 16-point coefficients
            double[] alegq = new[]
            {
                0.0, /* Fortran arrays are 1-based, this is a fake entry */
                0.271524594117540948517805724560e-01, 
                0.622535239386478928628438369944e-01, 
                0.951585116824927848099251076022e-01, 
                0.124628971255533872052476282192e+00, 
                0.149595988816576732081501730547e+00, 
                0.169156519395002538189312079030e+00, 
                0.182603415044923588866763667969e+00, 
                0.189450610455068496285396723208e+00
            };
            ir[1] = 0;
            ir[2] = 0;
            double retval = 0.0;
            if (df > dlarg)
            {
                retval = wprob(q, rr, cc, out int it);
                if (1 == it)
                    ir[1] = 1;
                return retval;
            }
            // calculate leading constant
            double f2 = df * 0.5;
            double f2lf = f2 * Math.Log(df) - df * r2 - alogam(f2);
            double f21 = f2 - 1.0;

            // integral is divided into unit, half-unit, quarter-unit, or          
            // eighth-unit length intervals depending on the value of the          
            // degrees of freedom.                                                 
            double ff4 = df * 0.25;
            double ulen;
            if (df <= dhaf)
            {
                ulen = ulen1;
            }
            else if (df <= dquar)
            {
                ulen = ulen2;
            }
            else if (df <= deigh)
            {
                ulen = ulen3;
            }
            else
            {
                ulen = ulen4;
            }

            f2lf += Math.Log(ulen);

            // integrate over each subinterval                                     
            for (int i = 1; i <= 50; i++)
            {
                double otsum = 0.0;

                // legendre quadrature with order = nlegq                          
                // nodes (stored in xlegq) are symmetric around zero.              
                double twa1 = (2.0 * i - 1.0) * ulen;
                for (int jj = 1; jj <= nlegq; jj++)
                {
                    int j;
                    double t1;
                    if (ihalfq < jj)
                    {
                        j = jj - ihalfq;
                        t1 = f2lf + f21 * Math.Log(twa1 + xlegq[j] * ulen) - (xlegq[j] * ulen + twa1) * ff4;
                    }
                    else
                    {
                        j = jj;
                        t1 = f2lf + f21 * Math.Log(twa1 - xlegq[j] * ulen) + (xlegq[j] * ulen - twa1) * ff4;
                    }

                    // if exp(t1) < 9e-14, then doesn't contribute to integral     
                    if (t1 >= eps1)
                    {
                        double qsqz;
                        if (ihalfq < jj)
                        {
                            qsqz = q * Math.Sqrt((xlegq[j] * ulen + twa1) * 0.5);
                        }
                        else
                        {
                            qsqz = q * Math.Sqrt((-(xlegq[j] * ulen) + twa1) * 0.5);
                        }

                        // call wprob to find integral of range portion 
                        double wprb = wprob(qsqz, rr, cc, out int it);
                        if (1 == it)
                        {
                            ir[1] = 1;
                        }
                        double rotsum = wprb * alegq[j] * Math.Exp(t1);
                        otsum = rotsum + otsum;
                    }

                    // end legendre integral for interval i                            
                    // if integral for interval i < 1e-14, then stop.  however, in order to avoid small area under left tail, at least 1/ulen intervals are calculated
                }
                if (i * ulen >= 1.0 && otsum <= eps2)
                {
                    break;
                }
                // end of interval i                                                   
                retval += otsum;
            }
            if (retval > eps)
                ir[2] = 1;
            if (retval > 1.0 && retval <= eps)
            {
                retval = 1.0;
            }
            return retval;
        }

        /// <summary>
        /// calculates integral of hartley's form of the range.
        /// program will not terminate if ir is raised.
        /// </summary>
        /// <param name="w">value of range</param>
        /// <param name="rr">no. of rows or groups</param>
        /// <param name="cc">no. of columns or treatments</param>
        /// <param name="ir">error flag = 1 if wprob probability > 1</param>
        /// <returns>returned probability integral from (0, w)</returns>
        private static double wprob(double w, double rr, double cc, out int ir)
        {
            // bb = upper limit of legendre integration                            
            // eps = maximum acceptable value of integral                          
            // nleg = order of legendre quadrature                                 
            // ihalf = int ((nleg + 1) / 2)                                        
            // wlar = value of range above which wincr1 intervals are used to calculate second part of integral, else wincr2 intervals are used.                                     
            // eps1, eps2, eps3 = values which are used as cutoffs for terminating or modifying a calculation.                                         
            const double bb = 8.0;
            const double eps = 1.0;
            const int nleg = 12;
            const int ihalf = 6;
            const double wlar = 3.0;
            const double wincr1 = 2.0;
            const double wincr2 = 3.0;
            const double eps1 = -30.0;
            const double eps2 = -50.0;
            const double eps3 = 60.0;

            // sq2pii = 1 / sqrt(2 * pi);  from abramowitz & stegun, p. 3.         
            // qsqr2 = sqrt(2)                                                     
            // xleg = legendre 12-point nodes                                      
            // aleg = legendre 12-point coefficients                               
            const double sq2pii = 0.3989422804014326779399461;
            const double qsqr2 = 1.41421356237309504880168872421;
            double[] xleg = new[]
        {
            0.0, /* Fortran arrays are 1-based, this is a fake entry */
            0.981560634246719250690549090149e+00, 
            0.904117256370474856678465866119e+00, 
            0.769902674194304687036893833213e+00, 
            0.587317954286617447296702418941e+00, 
            0.367831498998180193752691536644e+00, 
            0.125233408511468915472441369464e+00
        };
            double[] aleg = new[]
        {
            0.0, /* Fortran arrays are 1-based, this is a fake entry */
            0.471753363865118271946159614850e-01, 
            0.106939325995318430960254718194e+00, 
            0.160078328543346226334652529543e+00, 
            0.203167426723065921749064455810e+00, 
            0.233492536538354808760849898925e+00, 
            0.249147045813402785000562436043e+00
        };
            ir = 0;
            double qsqz = w * 0.5;
            // if w >= 16 then integral lower bound (occurs for c=20) is 0.99999999999995  
            // so return a value of 1.
            double retval = 1.0;

            // find (f(w/2) - 1) ** cc (first term in integral of hartley's form).
            if (qsqz >= bb)
                return retval;

            // if wprob ** cc < 2e-22 then set wprob = 0                           
            retval = derf(qsqz / qsqr2);
            retval = retval >= Math.Exp(eps2 / cc) ? Math.Pow(retval, cc) : 0.0;

            // if w is large then second component of integral is small, so fewer  
            // intervals are needed. 
            double wincr = w > wlar ? wincr1 : wincr2;

            // find integral of second term of hartley's form for integral of the range for equal-length intervals using legendre quadrature.  
            // limits of integration are from (w/2, 8).
            // two or three equal-length intervals are used.
            // blb and bub are lower and upper limits of integration.
            double blb = qsqz;
            double binc = (bb - qsqz) / wincr;
            double bub = blb + binc;
            double einsum = 0.0;
            double cc1 = cc - 1.0;

            // integrate over each interval
            for (double wi = 1; wi <= wincr; wi++)
            {
                double elsum = 0.0;
                double a = 0.5 * (bub + blb);

                // legendre quadrature with order = nleg
                double b = 0.5 * (bub - blb);

                for (int jj = 1; jj <= nleg; jj++)
                {
                    int j;
                    double xx;
                    if (ihalf < jj)
                    {
                        j = nleg - jj + 1;
                        xx = xleg[j];
                    }
                    else
                    {
                        j = jj;
                        xx = -xleg[j];
                    }
                    double c = b * xx;
                    double ac = a + c;

                    // if exp(-qexpo/2) < 9e-14, then doesn't contribute to integral       
                    double qexpo = ac * ac;

                    if (qexpo > eps3)
                        break;

                    double pplus;
                    if (ac > 0.0)
                    {
                        pplus = 1.0 + derf(ac / qsqr2);
                    }
                    else
                    {
                        pplus = derfc(-(ac / qsqr2));
                    }

                    double pminus;
                    if (ac > w)
                    {
                        pminus = 1.0 + derf(ac / qsqr2 - w / qsqr2);
                    }
                    else
                    {
                        pminus = derfc(w / qsqr2 - ac / qsqr2);
                    }

                    // if rinsum ** (cc-1) < 9e-14, then doesn't contribute to integral
                    double rinsum = pplus * 0.5 - pminus * 0.5;
                    if (rinsum >= Math.Exp(eps1 / cc1))
                    {
                        rinsum = aleg[j] * Math.Exp(-(0.5 * qexpo)) * Math.Pow(rinsum, cc1);
                        elsum += rinsum;
                    }
                    // end legendre quadrature
                }
                elsum = 2.0 * b * cc * sq2pii * elsum;
                einsum += elsum;
                blb = bub;
                bub += binc;
                // end integration of second term
            }

            // if wprob ** rr < 9e-14, then return 0.0
            retval = einsum + retval;
            if (retval <= Math.Exp(eps1 / rr))
            {
                return 0.0;
            }
            retval = Math.Pow(retval, rr);
            if (retval > eps)
                ir = 1;
            if (retval > 1.0 && retval < eps)
            {
                return 1.0;
            }
            return retval;
        }

        /// <summary>
        /// finds percentage point of the studentized range which is used as initial estimate for the secant method.
        /// </summary>
        /// <param name="p">percentage point</param>
        /// <param name="c">no. of columns or treatments</param>
        /// <param name="v">degrees of freedom</param>
        /// <returns>initial estimate</returns>
        /// <remarks>
        /// function is adapted from portion of algorithm as 70                    
        /// from applied statistics (1974) ,vol. 23, no. 1                         
        /// by odeh, r. e. and evans, j. o.                              
        /// </remarks>
        private static double qinv(double p, double c, double v)
        {
            // vmax is cutoff above which degrees of freedom is treated as infinity.
            const double vmax = 120.0;

            const double p0 = 0.322232421088;
            const double q0 = 0.993484626060e-01;
            const double p1 = -1.0;
            const double q1 = 0.588581570495;
            const double p2 = -0.342242088547;
            const double q2 = 0.531103462366;
            const double p3 = -0.204231210125;
            const double q3 = 0.103537752850;
            const double p4 = -0.453642210148e-04;
            const double q4 = 0.38560700634e-02;
            const double c1 = 0.8832;
            const double c2 = 0.2368;
            const double c3 = 1.214;
            const double c4 = 1.208;
            const double c5 = 1.4142;
            double ps = 0.5 - 0.5 * p;
            double yi = Math.Sqrt(Math.Log(1.0 / (ps * ps)));
            double t = yi + ((((yi * p4 + p3) * yi + p2) * yi + p1) * yi + p0) / ((((yi * q4 + q3) * yi + q2) * yi + q1) * yi + q0);
            if (v < vmax)
                t += (t * t * t + t) / v / 4.0;
            double q = c1 - c2 * t;
            if (v < vmax)
                q = q - c3 / v + c4 * t / v;
            return t * (q * Math.Log(c - 1.0) + c5);
        }

        public delegate double ffunDelegate(int k, double d, double s, double[] a, double[] b, double[] c);
        public delegate double fDelegate(ffunDelegate ffun, int k, double d, double dnu, double sup, double dinfnu, double[] a, double[] b, double[] c);

        /// <summary>
        /// function glv integrates with respect to chi/sqrt(2) density using gauss-legendre quadrature
        /// </summary>
        /// <param name="ffun">external function could be gh1d</param>
        /// <param name="k">number of treatments (passed onto inside integral)</param>
        /// <param name="d">critical value       (passed onto inside integral)</param>
        /// <param name="dnu">degrees of freedom of s</param>
        /// <param name="sup">upper integration limit of sqrt(nu/2)*s (= + infinity internally if on input sup is &lt; 0 for critical value calculations)</param>
        /// <param name="dinfnu"></param>
        /// <param name="av"></param>
        /// <param name="bv"></param>
        /// <param name="cv"></param>
        /// <returns></returns>
        /// <remarks>programmer: jason c. hsu.  last revision: 05-18-88 by wcs for vector processing</remarks>
        public static double glv(ffunDelegate ffun, int k, double d, double dnu, double sup, double dinfnu, double[] av, double[] bv, double[] cv)
        {
            const double pbot = 1e-10;
            const double pup = 1.0 - 1e-10;
            double[] pl = new double[49]; // Upper bound 48
            double[] wl = new double[49]; // Upper bound 48

            double rdnu = Math.Sqrt(dnu);
            double sr2 = Math.Sqrt(2.0);
            pl[1] = 0.998771007252426118600541491563;
            pl[2] = 0.993530172266350757547928750849;
            pl[3] = 0.984124583722826857744583600027;
            pl[4] = 0.970591592546247250461411983801;
            pl[5] = 0.952987703160430860722960666026;
            pl[6] = 0.931386690706554333114174380102;
            pl[7] = 0.905879136715569672822074835671;
            pl[8] = 0.876572020274247885905693554805;
            pl[9] = 0.843588261624393530711089844520;
            pl[10] = 0.807066204029442627082553043025;
            pl[11] = 0.767159032515740339253855437523;
            pl[12] = 0.724034130923814654674482233494;
            pl[13] = 0.677872379632663905211851280676;
            pl[14] = 0.628867396776513623995164933070;
            pl[15] = 0.577224726083972703817809238540;
            pl[16] = 0.523160974722233033678225869138;
            pl[17] = 0.466902904750958404544928861651;
            pl[18] = 0.408686481990716729916225495815;
            pl[19] = 0.348755886292160738159817937270;
            pl[20] = 0.287362487355455576735886461317;
            pl[21] = 0.224763790394689061224865440175;
            pl[22] = 0.161222356068891718056437390783;
            pl[23] = 0.970046992094626989300539558536e-1;
            pl[24] = 0.323801709628693620333222431521e-1;

            wl[1] = 0.315334605230583863267731154389e-2;
            wl[2] = 0.732755390127626210238397962179e-2;
            wl[3] = 0.114772345792345394895926676091e-1;
            wl[4] = 0.155793157229438487281769558345e-1;
            wl[5] = 0.196161604573555278144607196522e-1;
            wl[6] = 0.235707608393243791405193013784e-1;
            wl[7] = 0.274265097083569482000738362625e-1;
            wl[8] = 0.311672278327980889020657568464e-1;
            wl[9] = 0.347772225647704388925485859638e-1;
            wl[10] = 0.382413510658307063172172565237e-1;
            wl[11] = 0.415450829434647492140588223611e-1;
            wl[12] = 0.446745608566942804194485871259e-1;
            wl[13] = 0.476166584924904748259066234789e-1;
            wl[14] = 0.503590355538544749578076190879e-1;
            wl[15] = 0.528901894851936670955050562647e-1;
            wl[16] = 0.551995036999841628682034951916e-1;
            wl[17] = 0.572772921004032157051502346847e-1;
            wl[18] = 0.591148396983956357464748174335e-1;
            wl[19] = 0.607044391658938800529692320278e-1;
            wl[20] = 0.620394231598926639041977841376e-1;
            wl[21] = 0.631141922862540256571260227502e-1;
            wl[22] = 0.639242385846481866239062018255e-1;
            wl[23] = 0.644661644359500822065041936577e-1;
            wl[24] = 0.647376968126839225030249387366e-1;

            for (int i = 1; i <= 24; i++)
            {
                pl[i + 24] = -pl[i];
                wl[i + 24] = wl[i];
            }

            // ----------------------------------------------------------------
            // if nu (d.f.) greater than or equal to ifni assume s = sigma
            //
            // note:  in the sigma known (infinite degress of freedom) case,
            //        the upper bound on s is plus infinity, as it should be,
            //        because the power is either 1-alpha or 0
            // ----------------------------------------------------------------
            if (dnu > dinfnu)
            {
                return ffun(k, d, 1.0, av, bv, cv);
            }
            double dnb2 = 0.50 * dnu;
            double gdnb2 = alogam(dnb2);
            // -------------------------
            // b=lower integration limit
            // u=upper integration limit
            // -------------------------
            double b = Math.Sqrt(0.50 * ppchi2(pbot, dnu, out int ifault));
            double u = sup >= 0.0 ? sup : Math.Sqrt(0.50 * ppchi2(pup, dnu, out ifault));
            //  With few degrees of freedom the integrand changes quickly over a narrow band of s, so the interval is split into panels
            int panels = dnu < 5.0 ? 16 : 1;
            double wid = (u - b) / panels;
            double hwid = 0.50 * wid;
            double sum = 0.0;
            for (int panel = 0; panel < panels; panel++)
            {
                double pb = b + panel * wid;
                for (int i = 1; i <= 48; i++)
                {
                    double q = hwid * (1.0 + pl[i]) + pb;
                    double s = sr2 * q / rdnu;
                    double vgh = ffun(k, d, s, av, bv, cv);
                    double gama = (dnu - 1.0) * Math.Log(q) - q * q - gdnb2;
                    sum += vgh * Math.Exp(gama) * wid * wl[i];
                }
            }
            return sum;
        }

        /// <summary>
        /// gauss-hermites for 2-sided mcc (dunnett)inference with 1 factor
        /// </summary>
        /// <param name="k">number of treatments</param>
        /// <param name="d">critical value</param>
        /// <param name="s">chi/sqrt(nu) variable</param>
        /// <param name="a"></param>
        /// <param name="b"></param>
        /// <param name="c"></param>
        /// <returns></returns>
        /// <remarks>last revision: 02-04-91 by jch</remarks>
        public static double ghc1(int k, double d, double s, double[] a, double[] b, double[] c)
        {
            double[] ph = new double[49]; // Upper bound 48
            double[] wh = new double[49]; // Upper bound 48
            double[] zh = new double[49]; // Upper bound 48
            double[] xn = new double[97]; // Upper bound 96
            double[] vcdfn = new double[97]; // Upper bound 96
            double[] vfmc = new double[49]; // Upper bound 48

            double sr2 = Math.Sqrt(2.0);
            double srpi = Math.Sqrt(Constant.PI);

            ph[1] = 0.897531508193168706215358223476e1;
            ph[2] = 0.831075219070478413034784782670e1;
            ph[3] = 0.775929551976577463923770264126e1;
            ph[4] = 0.726604655416435040282062777183e1;
            ph[5] = 0.681006457807414138661792830624e1;
            ph[6] = 0.638056409618641062386710795477e1;
            ph[7] = 0.597107222501354540770712331894e1;
            ph[8] = 0.557731698122372862626895168709e1;
            ph[9] = 0.519628771879236454097986825550e1;
            ph[10] = 0.482575722813320948395976669772e1;
            ph[11] = 0.446401454693445890384147501246e1;
            ph[12] = 0.410970460356059023650054924395e1;
            ph[13] = 0.376172649022835778750118455640e1;
            ph[14] = 0.341916596936388461135547839399e1;
            ph[15] = 0.308124898864510584970840484976e1;
            ph[16] = 0.274730862482238321948145392074e1;
            ph[17] = 0.241676090487321645904643205900e1;
            ph[18] = 0.208908666094427643599567785406e1;
            ph[19] = 0.176381757989530000622984196672e1;
            ph[20] = 0.144052522013756518650995755277e1;
            ph[21] = 0.111881215240215656333400026648e1;
            ph[22] = 0.798304627778562231219097373434;
            ph[23] = 0.478646337594496098233148980980;
            ph[24] = 0.159492935848862470507111125726;

            wh[1] = 0.793555146077399683862306435342e-35;
            wh[2] = 0.598461269331387842583125604487e-30;
            wh[3] = 0.368503608015066987944041141543e-26;
            wh[4] = 0.556457746890228483635284540092e-23;
            wh[5] = 0.318838732350513844269483296100e-20;
            wh[6] = 0.873015960118667654492535811908e-18;
            wh[7] = 0.131515962265840851189411917719e-15;
            wh[8] = 0.119758986547917935294761992879e-13;
            wh[9] = 0.704693258154588908419691347901e-12;
            wh[10] = 0.281529653783816910883414782888e-10;
            wh[11] = 0.793046749516538231102728561821e-9;
            wh[12] = 0.162251413589576983699842464296e-7;
            wh[13] = 0.246865899366975047772528943937e-6;
            wh[14] = 0.284725869173484808307111697909e-5;
            wh[15] = 0.252859902774848890255132137567e-4;
            wh[16] = 0.175150431801172828786962777660e-3;
            wh[17] = 0.956392319819415276734092656065e-3;
            wh[18] = 0.415300491197755245156800170082e-2;
            wh[19] = 0.144449615749810994172466181382e-1;
            wh[20] = 0.404796769846038489872299218363e-1;
            wh[21] = 0.918222970792851793180659667553e-1;
            wh[22] = 0.169204471945641106711260999076;
            wh[23] = 0.253961542664759097659625200207;
            wh[24] = 0.311001030377963078884809767240;

            for (int i = 1; i <= 24; i++)
            {
                ph[i + 24] = -ph[i];
                wh[i + 24] = wh[i];
                // --------------------------------------------------------------
                // transform to weight function exp(-z^2/2) instead of exp(-z^2);
                // must divide integral by sqrt(pi) to effect integration w.r.t.
                // standard normal density
                // --------------------------------------------------------------
                zh[i] = sr2 * ph[i];
                zh[i + 24] = -zh[i];
            }

            int km1 = k - 1;
            double f = 0.0;
            double dts = d * s;
            // m = number of gauss-hermite quadrature points
            const int m = 48;
            const int m2 = m * 2;

            for (int i = 1; i <= m; i++)
            {
                vfmc[i] = 1.0;
            }

            for (int j = 1; j <= km1; j++)
            {
                for (int i = 1; i <= m; i++)
                {
                    double azh = a[j] * zh[i];
                    xn[i] = -(azh + dts) * c[j];
                    xn[i + m] = -(azh - dts) * c[j];
                }

                // ----------------------------------------------------
                // ncdfv computes the upper tail area of a n(o,1) curve
                // ----------------------------------------------------
                ncdfv(m2, xn, vcdfn);

                // ----------------------------------------------------
                // compute product integrand at each of the m xn points
                // ----------------------------------------------------
                for (int i = 1; i <= m; i++)
                {
                    vfmc[i] *= vcdfn[i] - vcdfn[i + m];
                }
            }
            // -------------------------------------
            // accumulate (product integrand)*weight
            // -------------------------------------
            for (int i = 1; i <= m; i++)
            {
                f += vfmc[i] * wh[i];
            }
            // -----------------------------------------------------
            // effect integration w.r.t. the standard normal density
            // instead of w.r.t. weight function exp(-z^2)
            // -----------------------------------------------------
            return f / srpi;
        }

        /// <summary>
        /// evaluates the tail area of the standard normal curve from x to infinity
        /// </summary>
        /// <param name="m"></param>
        /// <param name="xn">input array of m x's</param>
        /// <param name="cdf">output array of m cdfn's</param>
        /// <remarks>
        /// algorithm as66 appl. statist.(1973)
        /// vol.22, pp.424 by hill   
        ///
        /// available via the statlib archive, at http://lib.stat.cmu.edu/apstat/
        /// and in applied statistics algorithms, 
        /// http://lib.stat.cmu.edu/griffiths-hill/
        /// edited by griffiths and hill,
        /// published by wiley
        ///
        /// last revision: 05-26-88 wcs
        /// </remarks>
        private static void ncdfv(int m, double[] xn, double[] cdf)
        {
            const double con = 1.280;
            // ltone should be set to the value at which the upper tail area becomes 1.0.
            // If a machine produces n decimal digits in its real numbers, then set ltone=(n+9)/3.
            // For example, on cray x-mp/28, set ltone=7; on pyramid 90x, set ltone=8.
            const double ltone = 7.0;
            double[] ah = new double[8];
            double[] bh = new double[13];
            ah[1] = 0.398942280444;
            ah[2] = 0.399903438504;
            ah[3] = 5.758854804580;
            ah[4] = 29.821355780800;
            ah[5] = 2.624331216790;
            ah[6] = 48.695993069200;
            ah[7] = 5.928857244380;

            bh[1] = 0.398942280385;
            bh[2] = 3.805200000000e-8;
            bh[3] = 1.000006153020;
            bh[4] = 3.980647940000e-4;
            bh[5] = 1.986153813640;
            bh[6] = 0.151679116635;
            bh[7] = 5.293303249260;
            bh[8] = 4.838591280800;
            bh[9] = 15.150897245100;
            bh[10] = 0.742380924027;
            bh[11] = 30.789933034000;
            bh[12] = 3.990194170110;

            for (int j = 1; j <= m; j++)
            {
                double z = xn[j];
                int i = 1;
                if (z < 0.0)
                {
                    i = 0;
                    z = -z;
                }
                if (z > ltone)
                {
                    cdf[j] = 0.0;
                }
                else
                {
                    double y = 0.50 * z * z;
                    if (z <= con)
                    {
                        cdf[j] = 0.50 - z * (ah[1] - ah[2] * y / (y + ah[3] - ah[4] / (y + ah[5] + ah[6] / (y + ah[7]))));
                    }
                    if (z > con)
                    {
                        cdf[j] = bh[1] * Math.Exp(-y) / (z - bh[2] + bh[3] / (z + bh[4] + bh[5] / (z - bh[6] + bh[7] / (z + bh[8] - bh[9] / (z + bh[10] + bh[11] / (z + bh[12]))))));
                    }
                }
                if (0 == i)
                    cdf[j] = 1.0 - cdf[j];
            }
        }

        /// <summary>
        /// gauss-hermites for mca (tukey) inference with 1 factor
        /// </summary>
        /// <param name="k">number of treatments</param>
        /// <param name="d">critical value</param>
        /// <param name="s">chi/sqrt(nu) variable</param>
        /// <param name="a"></param>
        /// <param name="b"></param>
        /// <param name="c"></param>
        /// <returns></returns>
        /// <remarks>last revision: 02-13-91 by jch</remarks>
        public static double gha1(int k, double d, double s, double[] a, double[] b, double[] c)
        {
            double[] ph = new double[49]; // Upper bound 48
            double[] wh = new double[49]; // Upper bound 48
            double[] zh = new double[49]; // Upper bound 48
            double[] xn = new double[97]; // Upper bound 96
            double[] vcdfn = new double[97]; // Upper bound 96
            double sr2 = Math.Sqrt(2.0);
            double srpi = Math.Sqrt(Constant.PI);
            ph[1] = 0.897531508193168706215358223476e1;
            ph[2] = 0.831075219070478413034784782670e1;
            ph[3] = 0.775929551976577463923770264126e1;
            ph[4] = 0.726604655416435040282062777183e1;
            ph[5] = 0.681006457807414138661792830624e1;
            ph[6] = 0.638056409618641062386710795477e1;
            ph[7] = 0.597107222501354540770712331894e1;
            ph[8] = 0.557731698122372862626895168709e1;
            ph[9] = 0.519628771879236454097986825550e1;
            ph[10] = 0.482575722813320948395976669772e1;
            ph[11] = 0.446401454693445890384147501246e1;
            ph[12] = 0.410970460356059023650054924395e1;
            ph[13] = 0.376172649022835778750118455640e1;
            ph[14] = 0.341916596936388461135547839399e1;
            ph[15] = 0.308124898864510584970840484976e1;
            ph[16] = 0.274730862482238321948145392074e1;
            ph[17] = 0.241676090487321645904643205900e1;
            ph[18] = 0.208908666094427643599567785406e1;
            ph[19] = 0.176381757989530000622984196672e1;
            ph[20] = 0.144052522013756518650995755277e1;
            ph[21] = 0.111881215240215656333400026648e1;
            ph[22] = 0.798304627778562231219097373434;
            ph[23] = 0.478646337594496098233148980980;
            ph[24] = 0.159492935848862470507111125726;

            wh[1] = 0.793555146077399683862306435342e-35;
            wh[2] = 0.598461269331387842583125604487e-30;
            wh[3] = 0.368503608015066987944041141543e-26;
            wh[4] = 0.556457746890228483635284540092e-23;
            wh[5] = 0.318838732350513844269483296100e-20;
            wh[6] = 0.873015960118667654492535811908e-18;
            wh[7] = 0.131515962265840851189411917719e-15;
            wh[8] = 0.119758986547917935294761992879e-13;
            wh[9] = 0.704693258154588908419691347901e-12;
            wh[10] = 0.281529653783816910883414782888e-10;
            wh[11] = 0.793046749516538231102728561821e-9;
            wh[12] = 0.162251413589576983699842464296e-7;
            wh[13] = 0.246865899366975047772528943937e-6;
            wh[14] = 0.284725869173484808307111697909e-5;
            wh[15] = 0.252859902774848890255132137567e-4;
            wh[16] = 0.175150431801172828786962777660e-3;
            wh[17] = 0.956392319819415276734092656065e-3;
            wh[18] = 0.415300491197755245156800170082e-2;
            wh[19] = 0.144449615749810994172466181382e-1;
            wh[20] = 0.404796769846038489872299218363e-1;
            wh[21] = 0.918222970792851793180659667553e-1;
            wh[22] = 0.169204471945641106711260999076;
            wh[23] = 0.253961542664759097659625200207;
            wh[24] = 0.311001030377963078884809767240;
            for (int i = 1; i <= 24; i++)
            {
                ph[i + 24] = -ph[i];
                wh[i + 24] = wh[i];

                // --------------------------------------------------------------
                // transform to weight function exp(-z^2/2) instead of exp(-z^2);
                // must divide integral by sqrt(pi) to effect integration w.r.t.
                // standard normal density
                // --------------------------------------------------------------
                zh[i] = sr2 * ph[i];
                zh[i + 24] = -zh[i];
            }
            int km1 = k - 1;
            double f = 0.0;
            double dts = d * s;
            // m = number of gauss-hermite quadrature points
            const int m = 48;
            const int m2 = m * 2;
            b[1] = b[1];
            for (int i = 1; i <= m; i++)
            {
                double azh = a[1] * zh[i];
                xn[i] = -azh * c[1];
                xn[i + m] = -(azh - dts) * c[1];
            }
            // ----------------------------------------------------
            // ncdfv computes the upper tail area of a n(o,1) curve
            // ----------------------------------------------------
            ncdfv(m2, xn, vcdfn);
            // --------------------------------------------------------
            // compute the product integrand at each of the m xn points
            // --------------------------------------------------------
            for (int i = 1; i <= m; i++)
            {
                f += Math.Pow(vcdfn[i] - vcdfn[i + m], km1) * wh[i];
            }
            // -------------------------------------
            // accumulate (product integrand)*weight
            // -------------------------------------
            f *= k;
            // -----------------------------------------------------
            // effect integration w.r.t. the standard normal density
            // instead of w.r.t. weight function exp(-z^2)
            // -----------------------------------------------------
            return f / srpi;
        }
    }
}