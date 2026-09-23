namespace StatsDirect.Numerics
{
    public class GammaRNG
    {

        private const double SQRT32 = 5.656854;
        private const double EXP_M1 = (double)0.36787944117144232159M; //  EXP(-1) = 1/E

        private const double Q1 = 0.04166669;
        private const double Q2 = 0.02083148;
        private const double Q3 = 0.00801191;
        private const double Q4 = 0.00144121;
        private const double Q5 = -0.00007388;
        private const double Q6 = 0.00024511;
        private const double Q7 = 0.0002424;

        private const double A1 = 0.3333333;
        private const double A2 = -0.250003;
        private const double A3 = 0.2000062;
        private const double A4 = -0.1662921;
        private const double A5 = 0.1423657;
        private const double A6 = -0.1367177;
        private const double A7 = 0.1233795;

        private double AA;
        private double AAA;

        private double S2, S, D;
        private double SI, Q0, B, C;

        private bool SEEDED;

        private MersenneTwister RNG;
        private ExponentialRNG RNGEXP;
        private NormalRNG RNGNORM;

        // TRANSMISSINGCOMMENT: Method GenChiSq
        public double GenChiSq(double df)
        {
            double c2a = df / 2.0;
            const double c2b = 2.0;
            return GenGamma(c2a, c2b);
        }


        // TRANSMISSINGCOMMENT: Method GenF
        public double GenF(double dfn, double dfd)
        {
            double a1f = dfn / 2.0;
            double a2f = dfd / 2.0;
            const double fb = 2.0;
            double r1 = GenGamma(a1f, fb);
            double r2 = GenGamma(a2f, fb);
            return double.IsNaN(r1) || double.IsNaN(r2) ? double.NaN : dfd * r1 / (dfn * r2);
        }


        // TRANSMISSINGCOMMENT: Method GenGamma
        public double GenGamma(double a, double scaler)
        {
            double genGammaReturn;
            double x, v, q, e;


            if (SEEDED == false)
            {
                Seed(Base.DefaultSeed(), null);
            }

            if (a < 1.0)
            { //  GS algorithm for parameters a < 1

                e = 1.0 + EXP_M1 * a;
                do
                {
                    double P = e * RNG.NextDoubleX();
                    if (P >= 1.0)
                    {
                        x = -System.Math.Log((e - P) / a);
                        if (RNGEXP.GenExp() >= (1.0 - a) * System.Math.Log(x))
                        {
                            break;
                        }
                    }
                    else
                    {
                        x = System.Math.Exp(System.Math.Log(P) / a);
                        if (RNGEXP.GenExp() >= x)
                        {
                            break;
                        }
                    }
                } while (true);
                genGammaReturn = scaler * x;
                return genGammaReturn;
            }

            // a >= 1 : GD algorithm
            // Step 1: Recalculations of s2, s, d if a has changed
            if (a != AA)
            {
                AA = a;
                S2 = a - 0.5;
                S = System.Math.Sqrt(S2);
                D = SQRT32 - S * 12.0;
            }

            // Step 2: t = standard normal deviate, x = (s,1/2) -normal deviate.
            // immediate acceptance (i)
            double t = RNGNORM.GenNorm(0.0D, 1.0D);
            x = S + 0.5 * t;
            double ret_val = x * x;
            if (t >= 0.0)
            {
                genGammaReturn = scaler * ret_val;
                return genGammaReturn;
            }

            // Step 3: u = 0,1 - uniform sample. squeeze acceptance (s)
            double u = RNG.NextDoubleX();
            if (D * u <= t * t * t)
            {
                genGammaReturn = scaler * ret_val;
                return genGammaReturn;
            }

            // Step 4: recalculations of q0, b, si, c if necessary
            if (a != AAA)
            {
                AAA = a;
                double r = 1.0 / a;
                Q0 = ((((((Q7 * r + Q6) * r + Q5) * r + Q4) * r + Q3) * r + Q2) * r + Q1) * r;

                // Approximation depending on size of parameter a
                // The constants in the expressions for b, si and c were established by numerical experiments

                if (a <= 3.686)
                {
                    B = 0.463 + S + 0.178 * S2;
                    SI = 1.235;
                    C = 0.195 / S - 0.079 + 0.16 * S;
                }
                else if (a <= 13.022)
                {
                    B = 1.654 + 0.0076 * S2;
                    SI = 1.68 / S + 0.275;
                    C = 0.062 / S + 0.024;
                }
                else
                {
                    B = 1.77;
                    SI = 0.75;
                    C = 0.1515 / S;
                }
            }

            // Step 5: no quotient test if x not positive

            if (x > 0.0)
            {
                // Step 6: calculation of v and quotient q
                v = t / (S + S);
                if (System.Math.Abs(v) <= 0.25)
                {
                    q = Q0 + 0.5 * t * t * ((((((A7 * v + A6) * v + A5) * v + A4) * v + A3) * v + A2) * v + A1) * v;
                }
                else
                {
                    q = Q0 - S * t + 0.25 * t * t + (S2 + S2) * System.Math.Log(1.0 + v);
                }

                // Step 7: quotient acceptance (q)
                if (System.Math.Log(1.0 - u) <= q)
                {
                    genGammaReturn = scaler * ret_val;
                    return genGammaReturn;
                }
            }

            do
            {
                // Step 8: e = standard exponential deviate
                //   u =  0,1 -uniform deviate
                //   t = (b,si)-double exponential (laplace) sample */
                e = RNGEXP.GenExp();
                u = RNG.NextDoubleX();
                u = u + u - 1.0;
                if (u < 0.0)
                {
                    t = B - SI * e;
                }
                else
                {
                    t = B + SI * e;
                }
                // Step  9:  rejection if t < tau(1) = -0.71874483771719
                if (t >= -0.71874483771719)
                {
                    // Step 10:  calculation of v and quotient
                    v = t / (S + S);
                    if (System.Math.Abs(v) <= 0.25)
                    {
                        q = Q0 + 0.5 * t * t * ((((((A7 * v + A6) * v + A5) * v + A4) * v + A3) * v + A2) * v + A1) * v;
                    }
                    else
                    {
                        q = Q0 - S * t + 0.25 * t * t + (S2 + S2) * System.Math.Log(1.0 + v);
                    }
                    // Step 11:  hat acceptance (h)
                    //  if q not positive go to step 8
                    if (q > 0.0)
                    {
                        double w = Base.expm1(q);
                        //  original had approximation with relative error < 2e-7
                        //  if t is rejected sample again at step 8
                        if (C * System.Math.Abs(u) <= w * System.Math.Exp(e - 0.5 * t * t))
                        {
                            break;
                        }

                        // original--->
                        // If q <= 0.5 Then
                        //  w = ((((e5 * q + e4) * q + e3) * q + e2) * q + e1) * q
                        // ElseIf q < 15# Then
                        //  w = Exp(q) - 1#
                        // Else
                        //  If (q + e - 0.5 * t * t) > 87.49823 Then Exit Do
                        //  If c * Abs(u) <= Exp(q + e - 0.5 * t * t) Then Exit Do
                        // End If
                        // If c * Abs(u) <= w * Exp(e - 0.5 * t * t) Then Exit Do
                        // <--------
                    }
                }
            }
            while (true); // repeat .. until  `t' is accepted
            x = S + 0.5 * t;
            genGammaReturn = scaler * x * x;

            return genGammaReturn;
        }

        public double GenT(double df)
        {
            double genTReturn;

            double a = df / 2.0;
            const double tb = 2.0;
            if (a <= 0.0)
            {
                genTReturn = double.NaN;
            }
            else
            {
                double r1 = RNGNORM.GenNorm(0.0D, 1.0D);
                double r2 = GenGamma(a, tb);
                if (!double.IsNaN(r2))
                {
                    genTReturn = r1 * System.Math.Sqrt(df / r2);
                }
                else
                {
                    genTReturn = double.NaN;
                }
            }
            return genTReturn;
        }

        public void Seed(int sd, MersenneTwister rug, ExponentialRNG ruge, NormalRNG rugn)
        {
            RNG = null;
            RNGEXP = null;
            RNGNORM = null;
            if (rug == null)
            {
                RNG = new MersenneTwister();
                RNG.Seed(sd);
            }
            else
            {
                RNG = rug;
            }
            if (ruge == null)
            {
                RNGEXP = new ExponentialRNG();
                RNGEXP.Seed(sd, ref RNG);
            }
            else
            {
                RNGEXP = ruge;
            }
            if (rugn == null)
            {
                RNGNORM = new NormalRNG();
                RNGNORM.Seed(sd, ref RNG);
            }
            else
            {
                RNGNORM = rugn;
            }
            AA = 0.0;
            AAA = 0.0;
            SEEDED = true;
        }

        public void Seed(int sd)
        {
            Seed(sd, null);
        }

        public void Seed(int sd, MersenneTwister rug)
        {
            Seed(sd, rug, null);
        }

        public void Seed(int sd, MersenneTwister rug, ExponentialRNG ruge)
        {
            Seed(sd, rug, ruge, null);
        }


    }


}
