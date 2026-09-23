using System;

namespace StatsDirect.Numerics
{
    public class PoissonRNG
    {
        private const double A0 = -0.5;
        private const double A1 = 0.3333333;
        private const double A2 = -0.2500068;
        private const double A3 = 0.2000118;
        private const double A4 = -0.1661269;
        private const double A5 = 0.1421878;
        private const double A6 = -0.1384794;
        private const double A7 = 0.125006;

        private double ONE_7;
        private double ONE_12;
        private double ONE_24;

        private readonly double[] FACT = new double[10];

        private int L;
        private int M;
        private double B1;
        private double B2;
        private double C;
        private double C0;
        private double C1;
        private double C2;
        private double C3;
        private readonly double[] PP = new double[37];
        private double P0;
        private double P;
        private double Q;
        private double S;
        private double D;
        private double OMEGA;
        private double BIG_L;

        private double MUPREV;
        private double MUPREV2;
        // private double MUOLD; 

        private readonly double Sqr2PI = Math.Pow(2.0 * Constant.PI, -0.5);

        private bool SEEDED;

        private MersenneTwister RNG;
        private ExponentialRNG RNGEXP;
        private NormalRNG RNGNORM;
        private GammaRNG RNGGAMMA;

        /// <summary>
        ///  generate lambda as exponential with scale parameter p / (1 - p).
        ///  return a Poisson deviate with mean lambda.
        /// 
        ///  Devroye, L. (1986).
        ///  Non-Uniform Random Variate Generation.
        ///  New York: Springer-Verlag.
        /// </summary>
        /// <param name="p"></param>
        /// <returns></returns>
        public double GenGeom(double p)
        {
            return GenPoisson(RNGEXP.GenExp() * ((1.0 - p) / p));
        }

        /// <summary>
        /// random deviates from the negative binomial distribution.
        ///  generate lambda as gamma with shape parameter n and scale parameter p/(1-p).
        ///  return a Poisson deviate with mean lambda.
        /// 
        ///  Devroye, L. (1986).
        ///  Non-Uniform Random Variate Generation.
        ///  New York: Springer-Verlag.
        /// </summary>
        /// <param name="n"></param>
        /// <param name="p"></param>
        /// <returns></returns>
        public double GenNegbin(double n, double p)
        {
            if (n <= 0.0 || p <= 0.0 || p > 1.0)
            {
                return double.NaN;
            }
            if (SEEDED == false)
            {
                Seed(Base.DefaultSeed(), null);
            }
            return GenPoisson(RNGGAMMA.GenGamma(n, (1.0 - p) / p));
        }

        public double GenPoisson(double mu)
        {
            double genPoissonReturn = 0;

            bool new_big_mu = false;

            if (SEEDED == false)
            {
                Seed(Base.DefaultSeed());
            }

            double u;

            if (mu <= 0.0)
            {
                genPoissonReturn = 0.0;
                return genPoissonReturn;
            }

            bool big_mu = mu >= 10.0;
            if (big_mu)
                new_big_mu = false;

            if (!(big_mu && mu == MUPREV))
            { // /* maybe compute new persistent par.s */


                if (big_mu)
                {
                    new_big_mu = true;
                    //  Case A. (recalculation of s,d,l  because mu has changed):
                    //  The poisson probabilities pk exceed the discrete normal probabilities fk whenever k >= m(mu).
                    MUPREV = mu;
                    S = Math.Sqrt(mu);
                    D = 6.0 * mu * mu;
                    BIG_L = Math.Floor(mu - 1.1484);
                    //  an upper bound to m(mu) for all mu >= 10.

                }
                else
                { //  Small mu ( < 10) -- not using normal approx.


                    //  Case B. (start new table and calculate p0 if necessary)
                    //  muprev = 0.;-* such that next time, mu != muprev
                    if (mu != MUPREV)
                    {
                        MUPREV = mu;
                        M = Math.Max(1, (int)Math.Floor(mu));
                        L = 0; //  pp[] is already ok up to pp[l]
                        P = Math.Exp(-mu);
                        Q = P;
                        P0 = Q;
                    }

                    do
                    {
                        bool skip = false;
                        // Step U. uniform sample for inversion method
                        u = RNG.NextDouble();
                        if (u <= P0)
                        {
                            genPoissonReturn = 0.0;
                            return genPoissonReturn;
                        }

                        // Step T. table comparison until the end pp[l] of the pp-table of cumulative poisson probabilities (0.458 > ~= pp[9](= 0.45792971447) for mu=10 )
                        int k;
                        if (L != 0)
                        {
                            int j = 1;
                            if (u > 0.458)
                            {
                                j = Math.Min(L, M);
                            }
                            for (k = j; k <= L; k++)
                            {
                                if (u <= PP[k])
                                {
                                    genPoissonReturn = k;
                                    return genPoissonReturn;
                                }
                            }
                            if (L == 35)
                            {
                                skip = true;
                            }
                        }
                        if (skip == false)
                        {
                            //  Step C. creation of new poisson probabilities p[l..] and their cumulatives q =: pp[k]
                            L += 1;
                            int counter = L;
                            for (k = counter; k <= 35; k++)
                            {
                                P = P * mu / k;
                                Q += P;
                                PP[k] = Q;
                                if (u <= Q)
                                {
                                    L = k;
                                    genPoissonReturn = Convert.ToDouble(k);
                                    return genPoissonReturn;
                                }
                            }
                            L = 35;
                        }
                    }
                    while (true);
                } // mu < 10
            } //  end {initialize persistent vars}

            // Only if mu >= 10 : ----------->

            // Step N. normal sample
            double g = mu + S * RNGNORM.GenNorm(0.0D, 1.0D);

            if (g >= 0.0)
            {
                double pois = Math.Floor(g);
                //  Step I. immediate acceptance if pois is large enough
                if (pois >= BIG_L)
                {
                    genPoissonReturn = pois;
                    return genPoissonReturn;
                }
                // Step S. squeeze acceptance
                double fk = pois;
                double difmuk = mu - fk;
                u = RNG.NextDouble(); //  ~ U(0,1) - sample
                if (D * u >= difmuk * difmuk * difmuk)
                {
                    genPoissonReturn = pois;
                    return genPoissonReturn;
                }

                // Step P. preparations for steps Q and H. (recalculations of parameters if necessary)
                if (new_big_mu || mu != MUPREV2)
                {
                    MUPREV2 = mu;
                    OMEGA = Sqr2PI / S;
                    //  The quantities b1, b2, c3, c2, c1, c0 are for the Hermite approximations to the discrete normal probabilities fk.
                    B1 = ONE_24 / mu;
                    B2 = 0.3 * B1 * B1;
                    C3 = ONE_7 * B1 * B2;
                    C2 = B2 - 15.0 * C3;
                    C1 = B1 - 6.0 * B2 + 45.0 * C3;
                    C0 = 1.0 - B1 + 3.0 * B2 - 15.0 * C3;
                    C = 0.1069 / mu; // guarantees majorization by the 'hat'-function.
                }

                double fx;
                double del;
                double fy;
                double v;
                double px;
                double py;
                double x;
                if (g >= 0.0)
                {
                    // 'subroutine' F : calculation of px,py,fx,fy.
                    if (pois < 10)
                    { // { use factorials from table fact[]

                        px = -mu;
                        py = Math.Pow(mu, pois) / FACT[(int)Math.Floor(pois)];
                    }
                    else
                    {
                        //  Case pois >= 10 uses polynomial approximation a0-a7 for accuracy when advisable
                        del = ONE_12 / fk;
                        del *= (1.0 - 4.8 * del * del);
                        v = difmuk / fk;
                        if (Math.Abs(v) <= 0.25)
                        {
                            px = fk * v * v * (((((((A7 * v + A6) * v + A5) * v + A4) * v + A3) * v + A2) * v + A1) * v + A0) - del;
                        }
                        else
                        { //  |v| > 1/4

                            px = fk * Math.Log(1.0 + v) - difmuk - del;
                        }
                        py = Sqr2PI / Math.Sqrt(fk);
                    }
                    x = (0.5 - difmuk) / S;
                    x *= x;
                    fx = -0.5 * x;
                    fy = OMEGA * (((C3 * x + C2) * x + C1) * x + C0);
                    //  Step Q. Quotient acceptance (rare case)
                    if (fy - u * fy <= py * Math.Exp(px - fx))
                    {
                        genPoissonReturn = pois;
                        return genPoissonReturn;
                    }
                }

                do
                {
                    //  Step E. Exponential Sample

                    double e = RNGEXP.GenExp();

                    // sample t from the Laplace 'hat'(if t <= -0.6744 then pk < fk for all mu >= 10.)
                    u = 2.0 * RNG.NextDouble() - 1.0;
                    double t = 1.8 + Base.dsign(e, u);
                    if (t > -0.6744)
                    {
                        pois = Math.Floor(mu + S * t);
                        fk = pois;
                        difmuk = mu - fk;

                        // 'subroutine' F : calculation of px,py,fx,fy.
                        if (pois < 10)
                        { // { use factorials from table fact[]

                            px = -mu;
                            py = Math.Pow(mu, pois) / FACT[(int)Math.Floor(pois)];
                        }
                        else
                        {
                            //  Case pois >= 10 uses polynomial approximation a0-a7 for accuracy when advisable
                            del = ONE_12 / fk;
                            del *= (1.0 - 4.8 * del * del);
                            v = difmuk / fk;
                            if (Math.Abs(v) <= 0.25)
                            {
                                px = fk * v * v * (((((((A7 * v + A6) * v + A5) * v + A4) * v + A3) * v + A2) * v + A1) * v + A0) - del;
                            }
                            else
                            { //  |v| > 1/4

                                px = fk * Math.Log(1.0 + v) - difmuk - del;
                            }
                            py = Sqr2PI / Math.Sqrt(fk);
                        }
                        x = (0.5 - difmuk) / S;
                        x *= x;
                        fx = -0.5 * x;
                        fy = OMEGA * (((C3 * x + C2) * x + C1) * x + C0);

                        //  Step H. Hat acceptance (E is repeated on rejection)
                        if (C * Math.Abs(u) <= py * Math.Exp(px + e) - fy * Math.Exp(fx + e))
                            break;
                    } //  t > -.67
                }
                while (true);
                genPoissonReturn = pois;
            }
            return genPoissonReturn;
        }

        public void Seed(int sd, MersenneTwister rug)
        {

            RNG = null;
            RNGEXP = null;
            RNGNORM = null;
            RNGGAMMA = null;
            if (rug == null)
            {
                RNG = new MersenneTwister();
                RNG.Seed(sd);
            }
            else
            {
                RNG = rug;
            }
            RNGEXP = new ExponentialRNG();
            RNGNORM = new NormalRNG();
            RNGGAMMA = new GammaRNG();
            RNGEXP.Seed(sd, ref RNG);
            RNGNORM.Seed(sd, ref RNG);
            RNGGAMMA.Seed(sd, RNG, RNGEXP, RNGNORM);
            ONE_7 = 1.0 / 7.0;
            ONE_12 = 1.0 / 12.0;
            ONE_24 = 1.0 / 24.0;
            FACT[0] = 1.0;
            FACT[1] = 1.0;
            FACT[2] = 2.0;
            FACT[3] = 6.0;
            FACT[4] = 24.0;
            FACT[5] = 120.0;
            FACT[6] = 720.0;
            FACT[7] = 5040.0;
            FACT[8] = 40320.0;
            FACT[9] = 362880.0;
            MUPREV = 0.0;
            MUPREV2 = 0.0;
            // MUOLD = 0.0; 
            SEEDED = true;
        }

        public void Seed(int sd)
        {
            Seed(sd, null);
        }
    }
}
