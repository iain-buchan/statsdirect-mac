using System;

namespace StatsDirect.Numerics
{
    public partial class ExFortran
    {
        //  Residual degrees of freedom above which the residual variance is taken as known in the multiple comparison integrals
        internal const double SigmaKnownDegreesOfFreedom = 1.0e7;
        ///  <summary>
        ///  ppq2 integrates |q*| for 2-sided MCA inference
        ///  </summary>
        ///  <param name="km1"></param>
        ///  <param name="fact1"></param>
        ///  <param name="nu"></param>
        ///  <param name="cc"></param>
        ///  <param name="d"></param>
        ///  <param name="ifault"></param>
        ///  <remarks>last Fortran revision: 6/4/97 by ieb, converted to VB.Net 2008-04-25</remarks>
        public static void ppq2(int km1, double[] fact1, int nu, out double cc, double d, out int ifault)
        {
            double[] a = new double[km1 + 1];
            double[] b = new double[km1 + 1];
            double[] c = new double[km1 + 1];

            const double dinfnu = SigmaKnownDegreesOfFreedom;
            ifault = 0;
            int k = km1 + 1;
            double dnu = Convert.ToDouble(nu);
            if (km1 < 1 || nu < 2)
            {
                ifault = 7;
                cc = Constant.MISSING;
                return;
            }
            for (int j = 1; j <= km1; j++)
            {
                a[j] = fact1[j];
                if (a[j] * a[j] > 1.0)
                {
                    ifault = 9;
                    cc = Constant.MISSING;
                    return;
                }
                c[j] = 1.0 / Math.Sqrt(1.0 - a[j] * a[j]);
            }
            cc = PDF.glv(PDF.gha1, k, d, dnu, -1.0, dinfnu, a, b, c);
        }


        ///  <summary>
        ///  ppd2 integrates |d*| for 2-sided MCC inference
        ///  </summary>
        ///  <param name="km1"></param>
        ///  <param name="fact1"></param>
        ///  <param name="nu"></param>
        ///  <param name="cc"></param>
        ///  <param name="d"></param>
        ///  <param name="ifault"></param>
        ///  <remarks>last Fortran revision: 6/4/97 by ieb, converted to VB.Net 2008-04-25</remarks>
        public static void ppd2(int km1, double[] fact1, int nu, out double cc, double d, out int ifault)
        {
            double[] a = new double[km1 + 1];
            double[] b = new double[km1 + 1];
            double[] c = new double[km1 + 1];

            const double dinfnu = SigmaKnownDegreesOfFreedom;
            ifault = 0;
            int k = km1 + 1;
            double dnu = Convert.ToDouble(nu);
            if (km1 < 1 || nu < 2)
            {
                ifault = 7;
                cc = Constant.MISSING;
                return;
            }
            for (int j = 1; j <= km1; j++)
            {
                a[j] = fact1[j];
                if (a[j] * a[j] > 1.0)
                {
                    ifault = 9;
                    cc = Constant.MISSING;
                    return;
                }
                c[j] = 1.0 / Math.Sqrt(1.0 - a[j] * a[j]);
            }
            cc = PDF.glv(PDF.ghc1, k, d, dnu, -1.0, dinfnu, a, b, c);
        }


        ///  <summary>
        ///  dmca computes critical values for 2-sided MCA inference
        ///  </summary>
        ///  <param name="km1"></param>
        ///  <param name="fact1"></param>
        ///  <param name="nu"></param>
        ///  <param name="cc"></param>
        ///  <param name="d"></param>
        ///  <param name="ifault"></param>
        ///  <remarks>last Fortran revision: 6/4/97 by ieb, converted to VB.Net 2008-04-25</remarks>
        public static void dmca(int km1, double[] fact1, int nu, double cc, out double d, out int ifault)
        {
            double[] a = new double[km1 + 1];
            double[] b = new double[km1 + 1];
            double[] c = new double[km1 + 1];

            const double dinfnu = SigmaKnownDegreesOfFreedom;

            //  initialize default tolerence (eps) on cc
            //  eps=0.20d-05
            const double eps = 0.0000000002;

            //  initialize default tolerence (dstop) on half width of interval
            //  dstop=0.5d-03
            const double dstop = 0.00000005;

            //  initialize default bound on number of iteration (itmax)
            const int itmax = 21;
            int k = km1 + 1;
            double dnu = Convert.ToDouble(nu);
            if (km1 < 1 || nu < 2)
            {
                ifault = 7;
                d = Constant.MISSING;
                return;
            }

            //  initialize correlations
            for (int j = 1; j <= km1; j++)
            {
                //  ----------------------
                //  a = factor pattern
                //  c = 1 / sqrt(uniqueness))
                //  ----------------------
                a[j] = fact1[j];
                if (a[j] * a[j] > 1.0)
                {
                    ifault = 9;
                    d = Constant.MISSING;
                    return;
                }
                c[j] = 1.0 / Math.Sqrt(1.0 - a[j] * a[j]);
            }
            if (cc <= 0.0 || cc >= 1.0)
            {
                ifault = 8;
                d = Constant.MISSING;
                return;
            }

            //  find critical value

            //  -----------------------------------------------
            //  obtain upper and lower bounds on critical value
            //  -----------------------------------------------
            bdmca2(k, cc, nu, dnu, out double dhigh, out double dlow, dinfnu);

            //  ------------------------------------------------------------
            //  compute critical value d by the modified regula falsi method
            //  ------------------------------------------------------------
            ModifiedRegulaFalsi(PDF.gha1, k, PDF.glv, cc, dhigh, dlow, out double w, dnu, -1.0, dstop, eps, itmax, out int _, out int _, out ifault, dinfnu, a, b, c);
            d = w;
        }

        ///  <summary>
        ///  dmcc computes critical values for constrained mcc inference
        ///  </summary>
        ///  <param name="km1"></param>
        ///  <param name="fact1"></param>
        ///  <param name="nu"></param>
        ///  <param name="cc"></param>
        ///  <param name="d"></param>
        ///  <param name="ifault"></param>
        ///  <remarks>last Fortran revision: 6/4/97 by ieb, converted to VB.Net 2008-04-25</remarks>
        public static void dmcc(int km1, double[] fact1, int nu, double cc, out double d, out int ifault)
        {
            double[] a = new double[km1 + 1];
            double[] b = new double[km1 + 1];
            double[] c = new double[km1 + 1];

            const double dinfnu = SigmaKnownDegreesOfFreedom;

            //  initialize default tolerence (eps) on cc
            const double eps = 0.0000000002;
            //  eps=0.20d-05

            //  initialize default tolerence (dstop) on half width of interval
            //  dstop=0.5d-03
            const double dstop = 0.00000005;

            //  initialize default bound on number of iteration (itmax)
            if (km1 < 1 || nu < 2)
            {
                ifault = 7;
                d = Constant.MISSING;
                return;
            }
            const int itmax = 21;
            int k = km1 + 1;
            double dnu = Convert.ToDouble(nu);

            //  initialize correlations
            for (int j = 1; j <= km1; j++)
            {
                //  a = factor pattern
                //  c = 1 / sqrt(uniqueness))
                a[j] = fact1[j];
                if (a[j] * a[j] > 1.0)
                {
                    ifault = 9;
                    d = Constant.MISSING;
                    return;
                }
                c[j] = 1.0 / Math.Sqrt(1.0 - a[j] * a[j]);
            }
            if (cc <= 0.0 || cc >= 1.0)
            {
                ifault = 8;
                d = Constant.MISSING;
                return;
            }

            //  find critical value

            //  obtain upper and lower bounds on critical value
            bdmcc2(k, cc, nu, dnu, out double dhigh, out double dlow, dinfnu);

            //  compute critical value d by the modified regula falsi method
            ModifiedRegulaFalsi(PDF.ghc1, k, PDF.glv, cc, dhigh, dlow, out double w, dnu, -1.0, dstop, eps, itmax, out int _, out int _, out ifault, dinfnu, a, b, c);
            d = w;
        }


        ///  <summary>
        ///  obtains upper and lower bounds for two-sided mcc critical value
        ///  </summary>
        ///  <param name="k">number of treatments, including control</param>
        ///  <param name="cc">confidence level</param>
        ///  <param name="nu">degrees of freedom</param>
        ///  <param name="dnu"></param>
        ///  <param name="dhall">upper bound of critical value (output)</param>
        ///  <param name="dlall">lower bound of critical value (output)</param>
        ///  <param name="dinfnu"></param>
        ///  <remarks></remarks>
        public static void bdmcc2(int k, double cc, int nu, double dnu, out double dhall, out double dlall, double dinfnu)
        {
            if (dnu > dinfnu)
            {
                //  ---------------------------
                //  infinite d.f. (normal) case
                //  ---------------------------
                double cumu = 0.5 + 0.5 * cc;
                dlall = PDF.gauinv(cumu, out int ifault);
                //  ------------------------------------------------------------
                //  obtain upper bound by sidak's and mixture inequalities
                //  by sidak's inequality, the 0 correlation (independent) case
                //  gives an upper bound regardless of the original correlations
                //  ------------------------------------------------------------
                cumu = 0.5 + 0.5 * Math.Exp(Math.Log(cc) / Convert.ToDouble(k - 1));
                dhall = PDF.gauinv(cumu, out ifault);
            }
            else
            {
                //  ---------------------------------
                //  finite d.f. (t distribution) case
                //  ---------------------------------
                double tail = 1.0 - cc;
                dlall = PDF.tfromp2(tail, Convert.ToDouble(nu));
                //  ------------------------------------------------------------
                //  obtain upper bound by sidak's inequality
                //  by sidak's inequality, the 0 correlation (independent) case
                //  gives an upper bound regardless of the original correlations
                //  ------------------------------------------------------------
                tail = 1.0 - Math.Exp(Math.Log(cc) / Convert.ToDouble(k - 1));
                dhall = PDF.tfromp2(tail, Convert.ToDouble(nu));
            }
        }


        ///  <summary>
        ///  mrgfls is modified regula falsi subroutine
        ///  reference: thisted p. 171
        ///  conte and de door, 2nd edition, pp. 84-85.
        ///  </summary>
        ///  <param name="ffun">integrand function   (passed onto inside integral)</param>
        ///  <param name="k"></param>
        ///  <param name="f">name of function such that zero of  f-c  is sought. name must appear in an external statement in the calling program.</param>
        ///  <param name="c"></param>
        ///  <param name="a">endpoint of interval wherein zero is sought / endpoint of interval containing the zero (in/out).</param>
        ///  <param name="b">endpoint of interval wherein zero is sought / endpoint of interval containing the zero (in/out).</param>
        ///  <param name="w">best estimate of the zero (out)</param>
        ///  <param name="dnu"></param>
        ///  <param name="sup"></param>
        ///  <param name="xtol">desired length of output interval</param>
        ///  <param name="ftol">desired size of f(w)</param>
        ///  <param name="ntol">no more than ntol interation steps will be carried out</param>
        ///  <param name="iflag">-1, failure, since f has same sign at input points.
        ///  2, termination because abs(a-b) .le. xtol.
        ///  1, termination because abs(f(w)) .le. ftol.
        ///  3, termination because ntol steps were carried out.</param>
        ///  <param name="iter"></param>
        ///  <param name="ifault"></param>
        ///  <param name="dinfnu"></param>
        ///  <param name="av"></param>
        ///  <param name="bv"></param>
        ///  <param name="cv"></param>
        ///  <remarks>last revision: 07-01-85 by jch
        ///  
        ///  The modified regula falsi method linearly interpolates between the points (a,fa) and (b,fb), with fa*fb &lt; 0, to get a new point (w,f(w)) which replaces one of these in
        ///  such a way that again fa*fb &lt; 0.  In addition, the ordinate of a point staying in the game for more than one step is cut in half at each subsequent step.
        ///  </remarks>
        private static void ModifiedRegulaFalsi(PDF.ffunDelegate ffun, int k, PDF.fDelegate f, double c, double a, double b, out double w, double dnu, double sup, double xtol, double ftol, int ntol, out int iflag, out int iter, out int ifault, double dinfnu, double[] av, double[] bv, double[] cv)
        {
            iter = 0;
            ifault = 0;
            double fa = f(ffun, k, a, dnu, sup, dinfnu, av, bv, cv) - c;
            if (Math.Abs(fa) <= ftol)
            {
                w = a;
                iflag = 3;
                return;
            }
            double signfa = Base.dsign(1.0, fa);
            double fb = f(ffun, k, b, dnu, sup, dinfnu, av, bv, cv) - c;
            if (Math.Abs(fb) <= ftol)
            {
                w = b;
                iflag = 4;
                return;
            }
            if (k != 2)
            {
                //  ---------------------
                //  check for sign change
                //  ---------------------
                if (signfa * fb > 0.0)
                {
                    iflag = -1;
                    ifault = 2;
                    w = Constant.MISSING;
                    return;
                }
            }
            w = a;
            double fw = fa;
            for (int n = 1; n <= ntol; n++)
            {
                //  -------------------------------------------
                //  check for sufficiently close function value
                //  -------------------------------------------
                if (Math.Abs(fw) <= ftol)
                {
                    iflag = 1;
                    return;
                }
                //  -------------------------------------
                //  check for sufficiently small interval
                //  -------------------------------------
                if (Math.Abs(b - a) / 2.0 <= xtol)
                {
                    iflag = 2;
                    return;
                }
                //  ------------------------
                //  find intercept of secant
                //  ------------------------
                w = (fa * b - fb * a) / (fa - fb);
                double prevfw = Base.dsign(1.0, fw);
                fw = f(ffun, k, w, dnu, sup, dinfnu, av, bv, cv) - c;
                iter = n;
                //  ----------------------
                //  change to new interval
                //  ----------------------
                if (signfa * fw >= 0.0)
                {
                    a = w;
                    fa = fw;
                    if (fw * prevfw > 0.0)
                    {
                        fb /= 2.0;
                    }
                    continue;
                }
                b = w;
                fb = fw;
                if (fw * prevfw > 0.0)
                {
                    fa /= 2.0;
                }
            }
            iflag = 3;
            ifault = 1;
        }


        ///  <summary>
        ///  obtains upper and lower bounds for two-sided mca critical value
        ///  </summary>
        ///  <param name="k">number of treatments</param>
        ///  <param name="cc">confidence level</param>
        ///  <param name="nu">degrees of freedom</param>
        ///  <param name="dnu"></param>
        ///  <param name="dhall">upper bound of critical value (out)</param>
        ///  <param name="dlall">lower bound of critical value</param>
        ///  <param name="dinfnu"></param>
        ///  <remarks>last revision: 11-25-87 by jch</remarks>
        private static void bdmca2(int k, double cc, int nu, double dnu, out double dhall, out double dlall, double dinfnu)
        {
            if (dnu > dinfnu)
            {
                //  ---------------------------
                //  infinite d.f. (normal) case
                //  ---------------------------
                double cumu = 0.5 + 0.5 * cc;
                dlall = PDF.gauinv(cumu, out int ifault);
                //  ------------------------------------------------------
                //  obtain upper bound by sidak's and mixture inequalities
                //  ------------------------------------------------------
                cumu = 0.5 + 0.5 * Math.Exp(Math.Log(cc) / (k * (k - 1) / 2));
                dhall = PDF.gauinv(cumu, out ifault);
            }
            else
            {
                //  ---------------------------------
                //  finite d.f. (t distribution) case
                //  ---------------------------------
                double tail = 1.0 - cc;
                dlall = PDF.tfromp2(tail, Convert.ToDouble(nu));
                //  ----------------------------------------
                //  obtain upper bound by sidak's inequality
                //  ----------------------------------------
                tail = 1.0 - Math.Exp(Math.Log(cc) / (k * (k - 1) / 2));
                dhall = PDF.tfromp2(tail, Convert.ToDouble(nu));
            }
        }


        ///  <summary>
        ///  probabilities of non-central t
        ///  </summary>
        ///  <param name="t"></param>
        ///  <param name="idf"></param>
        ///  <param name="delta"></param>
        ///  <param name="ifault"></param>
        ///  <returns></returns>
        public static double pnct(double t, int idf, double delta, out int ifault)
        {
            ifault = 0;
            if (idf <= 0)
            {
                ifault = 1;
                return Constant.MISSING;
            }
            const double pi = Constant.PI;
            double s2pi = Math.Sqrt(2.0 * pi);
            double rs2pi = 1.0 / s2pi;
            const double r2pi = 0.5 / pi;
            double emin = Math.Sqrt(-1.9 * Math.Log(Constant.SPREAL));
            double df = Convert.ToDouble(idf);
            int i1 = (int)Math.Floor((double)idf - 2 * (idf / 2));
            double a = t / Math.Sqrt(df);
            double b = df / (df + t * t);
            double sb = Math.Sqrt(b);
            double da = delta * a;
            double dsb = delta * sb;
            double dasb = a * dsb;
            double p1 = PDF.alnorm(dasb);
            double f2 = 0.0;
            if (Math.Abs(dsb) < emin)
            {
                f2 = a * sb * Math.Exp(-0.5 * dsb * dsb) * p1 * rs2pi;
            }
            double f1 = b * da * f2;
            if (Math.Abs(delta) < emin)
            {
                f1 += b * a * r2pi * Math.Exp(-0.5 * delta * delta);
            }
            double sum = 0.0;
            double p;
            if (idf != 1)
            {
                sum = i1 <= 0 ? f2 : f1;
                if (idf >= 4)
                {
                    int idfm2 = idf - 2;
                    double az = 1.0;
                    double fz = 2.0;
                    for (int l = 2; l <= idfm2; l += 2)
                    {
                        double fkm1 = fz - 1.0;
                        f2 = b * (da * az * f1 + f2) * fkm1 / fz;
                        az = 1.0 / (az * fkm1);
                        f1 = b * (da * az * f2 + f1) * fz / (fz + 1.0);
                        if (i1 <= 0)
                        {
                            sum += f2;
                        }
                        else
                        {
                            sum += f1;
                        }
                        az = 1.0 / (az * fz);
                        fz += 2.0;
                    }
                }
                if (i1 <= 0)
                {
                    p1 = PDF.alnorm(-delta);
                    p = p1 + sum * s2pi;
                }
                else
                {
                    p1 = PDF.alnorm(-dsb);
                    p = dnctint(ref dsb, ref a);
                    p = p1 + 2.0 * (p + sum);
                }
            }
            else
            {
                p1 = PDF.alnorm(-dsb);
                p = dnctint(ref dsb, ref a);
                p = p1 + 2.0 * (p + sum);
            }
            return p;
        }


        private static double dnctint(ref double y, ref double z)
        {
            const double twopi = 2.0 * Constant.PI;
            const double oned2p = 1.0 / twopi;
            double expov = -Math.Log(Constant.SPREAL) - Constant.EPSILON;
            const double eps = Constant.EPSILON;
            double b = Math.Abs(y);
            double a = Math.Abs(z);
            if (a == 0.0)
                return 0.0;

            double big1 = Math.Pow(double.MaxValue, 0.25);
            double big2 = big1 / Math.Log(big1);
            double t = 0;
            if (a > big2)
            {
                t = 0.5 * (1.0 - PDF.alnorm(b));
                if (z < 0.0)
                    t = -t;
                return t; // AUDIT FIX (finding 3)
            }
            double ta = Math.Atan(a);
            if (b == 0.0)
            {
                t = oned2p * ta;
                if (z < 0.0)
                    t = -t;
                return t; // AUDIT FIX (finding 3)
            }
            if (a * b > 4.0)
            {
                t = 0.25 - 0.5 * (PDF.alnorm(b) - 0.5);
                if (z < 0.0)
                    t = -t;
                return t; // AUDIT FIX (finding 3)
            }
            double hsqb = 0.5 * b * b;
            if (hsqb <= expov)
            {
                double bexp = Math.Exp(-hsqb);
                double asq = a * a;
                double a4 = asq * asq;
                double b4 = hsqb * hsqb;
                double a4b4 = a4 * b4;
                double ahsqb = a * hsqb;
                double ab4 = a * b4 * 0.5;
                double f = 1.0;
                double sum = 0.0;
                double g = 3.0;
                do
                {
                    double g1 = g;
                    double ber = 0.0;
                    double ter = ab4;
                    do
                    {
                        ber += ter;
                        if (ter > ber * eps)
                        {
                            ter *= hsqb / g1;
                            g1 += 1.0;
                        }
                        else
                        {
                            break;
                        }
                    }
                    while (true);
                    double d1 = (ber + ahsqb) / f;
                    double d2 = ber * asq / (f + 2.0);
                    double d = d1 - d2;
                    sum += d;
                    t = ta - sum * bexp;
                    double aeps;
                    if (t > 0.0)
                    {
                        aeps = eps * t;
                    }
                    else
                    {
                        aeps = eps;
                    }
                    ahsqb *= a4b4 / ((g - 1.0) * g);
                    ab4 *= a4b4 / ((g + 1.0) * g);
                    f += 4.0;
                    g += 2.0;
                    if (d2 * bexp < aeps)
                    {
                        break;
                    }
                }
                while (true);
                t *= oned2p;
                if (z < 0.0)
                {
                    t = -t;
                }
            }
            return t;
        }


        ///  <summary>
        ///  Abramowitz M and Stegun I A (1972) Handbook of Mathematical Functions (3rd Edition) Dover Publications
        /// 
        ///  CDF of the noncentral chisquare
        ///  a = degrees of freedom, a > 0
        ///  d = noncentrality parameter, d > 0
        ///  x = the value at which the cdf is to be computed, x > 0
        ///  </summary>
        ///  <param name="df"></param>
        ///  <param name="elambda"></param>
        ///  <param name="xx"></param>
        ///  <returns></returns>
        ///  <remarks></remarks>
        public static double nchi2(double df, double elambda, double xx)
        {
            if (xx <= 0.0)
                return 0.0;
            double x = 0.5 * xx;
            double del = 0.5 * elambda;
            int k = (int)Math.Floor(del);
            double a = 0.5 * df + k;
            double gamkf = gamf(x, a);
            if (gamkf == Constant.MISSING)
                return Constant.MISSING;
            double gamkb = gamkf;
            if (del == 0.0)
                return gamkf;
            double poikf = poipro(ref k, ref del);
            double poikb = poikf;
            double gl = PDF.alogam(a);
            if (gl == Constant.MISSING)
                return Constant.MISSING;
            double xtermf = Math.Exp((a - 1.0) * Math.Log(x) - x - gl);
            double xtermb = xtermf * x / a;
            double sum = poikf * gamkf;
            double remain = 1.0 - poikf;
            int i = 0;
            do
            {
                i += 1;
                xtermf = xtermf * x / (a + i - 1.0);
                gamkf -= xtermf;
                poikf = poikf * del / (k + i);
                double termf = poikf * gamkf;
                sum += termf;
                double error = remain * gamkf;
                remain -= poikf;
                if (i > k)
                {
                    if (error <= 0.000000000001 || i > 5000)
                        break;
                }
                else
                {
                    xtermb = xtermb * (a - i + 1.0) / x;
                    gamkb += xtermb;
                    poikb = poikb * (k - i + 1.0) / del;
                    double termb = gamkb * poikb;
                    sum += termb;
                    remain -= poikb;
                    if (remain <= 0.000000000001 || i > 5000)
                    {
                        break;
                    }
                }
            }
            while (true);
            return i > 5000 ? Constant.MISSING : sum;
        }


        // TRANSMISSINGCOMMENT: Method poipro
        private static double poipro(ref int k, ref double el)
        {
            double ek = k;
            double gl = PDF.alogam(ek + 1.0);
            if (gl == Constant.MISSING)
            {
                return Constant.MISSING;
            }
            return Math.Exp(-el + ek * Math.Log(el) - gl);
        }

        private static double gamf(double x, double a)
        {
            double gl = PDF.alogam(a + 1.0);
            if (double.IsNaN(x)||double.IsNaN(a)) // IEB 18 Jul 18: prevent a loop if x is NaN
                return Constant.MISSING;
            if (gl == Constant.MISSING)
                return Constant.MISSING;

            double com = Math.Exp(a * Math.Log(x) - gl - x);
            if (com == 0.0)
            {
                return 0.0;
            }
            double term = 1.0;
            double sum = 1.0;
            double one = 1.0;
            do
            {
                term = term * x / (a + one);
                sum += term;
                if (term <= 0.000000000001) 
                {
                    break;
                }
                one += 1.0;
            }
            while (true);
            return Math.Min(com * sum, 1.0);
        }


        ///  <summary>
        ///  cumulative poisson distribution
        ///  </summary>
        ///  <param name="xlam"></param>
        ///  <param name="k"></param>
        ///  <param name="phi"></param>
        ///  <param name="plo"></param>
        ///  <param name="term"></param>
        ///  <param name="ifault"></param>
        ///  <remarks></remarks>
        public static void poisson(double xlam, int k, out double phi, out double plo, out double term, out int ifault)
        {
            term = ppoiseq(k, xlam);
            plo = ppoisle(k, xlam);
            phi = 1.0 - plo + term;
            ifault = term == Constant.MISSING || plo == Constant.MISSING ? 1 : 0;
        }


        ///  <summary>
        ///  inverse cumulative poisson distribution by simple bisection
        ///  </summary>
        ///  <param name="idx"></param>
        ///  <param name="p"></param>
        ///  <param name="xmid">Mean</param>
        ///  <param name="trm"></param>
        ///  <param name="phi"></param>
        ///  <param name="plo"></param>
        ///  <param name="nl"></param>
        ///  <param name="ifault">If non-zero, a fault has occurred during the calculation</param>
        ///  <remarks></remarks>
        public static void poissoni(int idx, double p, out double xmid, out double trm, out double phi, out double plo, int nl, out int ifault)
        {
            const double acc = Constant.EPSILON;
            const int imax = 1000;
            double xnl = Convert.ToDouble(nl);
            const double x1 = acc;
            double x2 = 0.0;

            //  find upper limit for mean where phi is almost 1
            int istep = 0;
            double dx;
            do
            {
                x2 += xnl;
                poisson(x2, nl, out phi, out plo, out trm, out ifault);
                if (ifault != 0)
                {
                    break;
                }
                dx = idx == 2 ? Math.Abs(1.0 - phi) : Math.Abs(0.0 - plo);
                istep += 1;
                if (istep > imax)
                {
                    ifault = 1;
                    break;
                }
                if (dx <= acc)
                {
                    break;
                }
            }
            while (true);

            //  bisect to converge upon p
            double bis = x1;
            dx = x2 - x1;
            istep = 0;
            if (idx == 2)
            {
                do
                {
                    dx *= 0.5;
                    xmid = bis + dx;
                    poisson(xmid, nl, out phi, out plo, out trm, out ifault);
                    double fmid = phi;
                    if (ifault != 0)
                    {
                        break;
                    }
                    if (fmid - p <= 0.0)
                    {
                        bis = xmid;
                    }
                    if (Math.Abs(dx) <= acc || Math.Abs(fmid - p) == 0.0)
                    {
                        break;
                    }
                    istep += 1;
                    if (istep > imax)
                    {
                        ifault = 3;
                        break;
                    }
                }
                while (true);
            }
            else
            {
                do
                {
                    dx *= 0.5;
                    xmid = bis + dx;
                    poisson(xmid, nl, out phi, out plo, out trm, out ifault);
                    double fmid = plo;
                    if (ifault != 0)
                        break;
                    if (fmid - p > 0.0)
                        bis = xmid;
                    if (Math.Abs(dx) <= acc || Math.Abs(fmid - p) == 0.0)
                        break;
                    istep += 1;
                    if (istep > imax)
                    {
                        ifault = 3;
                        break;
                    }
                }
                while (true);
            }
        }

        ///  <summary>
        ///  inverse cumulative poisson distribution by simple bisection
        ///  </summary>
        ///  <param name="idx"></param>
        ///  <param name="p"></param>
        ///  <param name="mean">Mean</param>
        ///  <param name="trm"></param>
        ///  <param name="phi"></param>
        ///  <param name="plo"></param>
        ///  <param name="nl"></param>
        ///  <param name="ifault">If non-zero, a fault has occurred during the calculation</param>
        ///  <remarks></remarks>
        public static void poissonNl(int idx, double p, double mean, out double trm, out double phi, out double plo, out int nl, out int ifault)
        {
            const double acc = Constant.EPSILON;
            const int imax = 1000;
            const int x1 = 1;
            int x2 = 0;

            //  find upper limit for nl where phi is almost 1
            int istep = 0;
            do
            {
                x2 += (int)Math.Ceiling(mean);
                poisson(mean, x2, out phi, out plo, out trm, out ifault);
                if (ifault != 0)
                    break;
                double dx = idx == 2 ? Math.Abs(1.0 - phi) : Math.Abs(0.0 - plo);
                istep += 1;
                if (istep > imax)
                {
                    ifault = 1;
                    break;
                }
                if (dx <= acc)
                    break;
            }
            while (true);

            //  bisect to converge upon p
            int bis = x1;
            int intdx = x2 - x1;
            istep = 0;
            if (idx == 2)
            {
                do
                {
                    intdx = (intdx + 1) / 2;
                    nl = bis + intdx;
                    poisson(mean, nl, out phi, out plo, out trm, out ifault);
                    double fmid = phi;
                    if (ifault != 0)
                    {
                        break;
                    }
                    if (fmid - p <= 0.0)
                    {
                        bis = nl;
                    }
                    if (Math.Abs(intdx) <= 1 || Math.Abs(fmid - p) == 0.0)
                    {
                        break;
                    }
                    istep += 1;
                    if (istep > imax)
                    {
                        ifault = 3;
                        break;
                    }
                }
                while (true);
            }
            else
            {
                do
                {
                    int lastIntdx = intdx;
                    intdx = (intdx + 1) / 2;
                    nl = bis + intdx;
                    poisson(mean, nl, out phi, out plo, out trm, out ifault);
                    double fmid = plo;
                    if (ifault != 0)
                        break;
                    if (fmid - p <= 0.0)
                        bis = nl;
                    if (Math.Abs(lastIntdx) <= 1 || Math.Abs(fmid - p) == 0.0)
                        break;
                    istep += 1;
                    if (istep > imax)
                    {
                        ifault = 3;
                        break;
                    }
                }
                while (true);
            }
        }

        ///  <summary>
        ///  probability that a poisson random variable = k with mean theta
        ///  </summary>
        ///  <param name="k"></param>
        ///  <param name="theta"></param>
        ///  <returns></returns>
        ///  <remarks></remarks>
        public static double ppoiseq(int k, double theta)
        {
            if (theta <= 0.0)
            {
                return Constant.MISSING;
            }
            if (k < 0)
            {
                return 0.0;
            }
            double smexe = Math.Log(Constant.DBL_MIN);
            double temp = theta + PDF.alogam(Convert.ToDouble(k + 1));
            double ex = -1.0 * temp + k * Math.Log(theta);
            return ex >= smexe ? Math.Exp(ex) : 0.0;
        }


        ///  <summary>
        ///  probability that a poisson random variable &lt;= k with mean theta
        ///  </summary>
        ///  <param name="k"></param>
        ///  <param name="theta"></param>
        ///  <returns></returns>
        ///  <remarks></remarks>
        public static double ppoisle(int k, double theta)
        {
            if (theta <= 0.0)
            {
                return Constant.MISSING;
            }
            if (k < 0)
            {
                return 0.0;
            }
            int k1 = k + 1;
            const double eps = Constant.EPSILON;
            const double sml = 2 * Constant.DBL_MIN;
            double alnsml = Math.Log(sml);
            //  Lambda = 0, special
            double pe;
            if (theta <= eps)
            {
                pe = 1.0;
            }
            else
            {
                //  prep forward calc
                double x = theta;
                double y = 1.0;
                int jj = 1;
                double p1 = -theta;
                int icnt = (int)Math.Floor(p1 / alnsml);
                p1 -= icnt * alnsml;
                p1 = Math.Exp(p1);
                //  prep backward calc
                double x2 = k;
                double y2 = theta;
                double g = x2 * Math.Log(y2);
                double h = k1;
                h = PDF.alogam(h);
                double p2 = -y2 + g - h;
                int kcnt = (int)Math.Floor(p2 / alnsml);
                p2 -= kcnt * alnsml;
                p2 = Math.Exp(p2);
                g = 1.0;
                h = 1.0;
                if (icnt == 0)
                {
                    g = 1.0 - p1;
                }
                if (kcnt == 0)
                {
                    h = 1.0 - p2;
                }
                pe = 0.0;
                //  work out which end to calculate from
                do
                {
                    int j = icnt - kcnt;
                    if (j > 0.0 || j == 0.0 && p1 <= p2)
                    {
                        //  forward
                        //  no need to scale, just store term
                        if (icnt == 0)
                        {
                            pe += p1;
                        }
                        if (jj != k1)
                        {
                            //  next term (recursion)
                            p1 = p1 * x / y;
                            if (p1 >= h)
                            {
                                //  scale
                                double temp = p1 * sml;
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
                        //  backward
                        //  no need to scale, just store term
                        if (kcnt == 0)
                        {
                            pe += p2;
                        }
                        if (jj != k1)
                        {
                            //  next term (recursion)
                            p2 = p2 * x2 / y2;
                            if (p2 >= g)
                            {
                                //  scale
                                double temp = p2 * sml;
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
                while (true);
            }
            if (pe > 1.0)
            {
                pe = 1.0;
            }
            return pe;
        }


        ///  <summary>
        ///  non-central t quantiles
        ///  </summary>
        ///  <param name="p"></param>
        ///  <param name="idf"></param>
        ///  <param name="delta"></param>
        ///  <param name="ifault"></param>
        ///  <returns></returns>
        public static double tnct(double p, int idf, double delta, out int ifault)
        {
            if (p <= 0.0 || p >= 1.0)
            {
                ifault = 1;
                return Constant.MISSING;
            }
            if (idf <= 0)
            {
                ifault = 2;
                return Constant.MISSING;
            }
            const double eps = Constant.EPSILON;
            double xinit = PDF.gauinv(p, out ifault) + delta;
            if (ifault != 0)
            {
                return Constant.MISSING;
            }
            double x1 = xinit;
            double f1 = pnct(x1, idf, delta, out ifault) - p;
            if (ifault != 0)
            {
                return Constant.MISSING;
            }
            double x2;
            double xd;
            if (f1 == 0.0)
            {
                x2 = x1;
                return (x1 + x2) * 0.5;
            }
            if (Math.Abs(xinit) >= 1.0)
            {
                x2 = xinit * 1.05;
                xd = x2 - x1;
            }
            else
            {
                x2 = xinit + 0.05;
                xd = 0.05;
            }
            double f2 = pnct(x2, idf, delta, out ifault) - p;
            if (ifault != 0)
            {
                return Constant.MISSING;
            }
            double slope = Math.Max(0.01, (f2 - f1) / xd);
            double del = -f1 / slope;
            int iter = 0;
            do
            {
                del = 2.0 * del;
                iter += 1;
                if (iter > 200)
                {
                    ifault = 3;
                    return Constant.MISSING;
                }
                x2 = x1 + del;
                f2 = pnct(x2, idf, delta, out ifault) - p;
                if (ifault != 0)
                {
                    return Constant.MISSING;
                }
                if (f1 * f2 >= 0.0)
                {
                    x1 = x2;
                }
                else
                {
                    break;
                }
            }
            while (true);
            bool ibisec = false;
            for (iter = 1; iter <= 100; iter++)
            {
                double xm = (x1 + x2) * 0.5;
                double fd = f2 - f1;
                xd = x2 - x1;
                if (xm != 0.0)
                {
                    if (Math.Abs(xd) < Math.Abs(xm * eps))
                    {
                        return (x1 + x2) * 0.5;
                    }
                }
                else
                {
                    if (Math.Abs(xd) < eps)
                    {
                        return (x1 + x2) * 0.5;
                    }
                }
                double x3 = ibisec ? xm : x2 - f2 * xd / fd;
                ibisec = false;
                double f3 = pnct(x3, idf, delta, out ifault) - p;
                if (ifault != 0)
                {
                    return Constant.MISSING;
                }
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
    }
}
