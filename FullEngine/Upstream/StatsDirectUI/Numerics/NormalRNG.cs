namespace StatsDirect.Numerics
{
    public class NormalRNG
    {

        private const double BIG = 134217728;

        private bool SEEDED;

        private MersenneTwister RNG;

        public double GenLnNorm(double lnmean, double lnsd)
        {
            // get mean and var of lognormal
            // a = Exp(xm + sd * sd / 2#)
            // b = Exp(2# * xm + 2# * sd * sd) - Exp(2# * xm + sd * sd)

            return lnsd < 0.0 ? double.NaN : Base.SafeExp(GenNorm(lnmean, lnsd));
        }

        public double GenNorm(double mean, double sd)
        {
            //  inversion method

            if (SEEDED == false)
            {
                Seed(Base.DefaultSeed());
            }
            double v1 = RNG.NextDoubleX();
            v1 = System.Math.Floor(BIG * v1) + RNG.NextDoubleX();
            double x = PDF.gauinv(v1 / BIG, out int ifault);
            return ifault != 0 ? double.NaN : x * sd + mean;
        }

        public void Seed(int sd, ref MersenneTwister rug)
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
            SEEDED = true;
        }

        public void Seed(int sd)
        {
            MersenneTwister transTemp0 = null;
            Seed(sd, ref transTemp0);
        }
    }
}
