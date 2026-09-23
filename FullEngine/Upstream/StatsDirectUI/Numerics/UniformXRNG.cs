using System;

namespace StatsDirect.Numerics
{
    public class UniformXRNG
    {
        private MersenneTwister RNG;

        public double GenCauchy(double location, double scl)
        {
            double u = RNG.NextDoubleX();
            return location + scl * Math.Tan(Constant.PI * u);
        }

        public double GenLogistic(double location, double scl)
        {
            double u = RNG.NextDoubleX();
            return location + scl * Math.Log(u / (1.0 - u));
        }

        public double GenUni()
        {
            return RNG.NextDoubleX();
        }

        public double GenUniAB(double a, double b, bool isCount)
        {
            double z, y;

            if (a > b)
            {
                y = b;
                z = a;
            }
            else
            {
                y = a;
                z = b;
            }
            double r1 = RNG.NextDoubleX();
            if (isCount)
            {
                return Math.Floor(y + r1 * (z - y + 1));
            }
            return Math.Min(Math.Max(y * (1.0 - r1) + z * r1, y), z);
        }

        public double GenWeibull(double shape, double scl)
        {
            double u = RNG.NextDoubleX();
            return scl * Math.Pow(-Math.Log(u), 1.0 / shape);
        }

        public void Seed(int sd, MersenneTwister rug)
        {

            RNG = null;
            if (rug == null)
            {
                RNG = new MersenneTwister();
                RNG.Seed(sd);
            }
            else
            {
                RNG = rug;
            }
        }

        public void Seed(int sd)
        {
            Seed(sd, null);
        }
    }
}
