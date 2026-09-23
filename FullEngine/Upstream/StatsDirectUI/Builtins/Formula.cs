using System;
using System.Collections.Generic;

using StatsDirect.Numerics;
using StatsDirect.Templates;
using StatsDirect.Utilities;

namespace StatsDirect.Builtins
{
    public static class Formula
    {
        private struct TwoLng : IComparable<TwoLng>
        {
            public int Id;
            public int Rx;

            private int CompareTo(TwoLng other) => Id.CompareTo(other.Id);

            // interface methods implemented by CompareTo
            int IComparable<TwoLng>.CompareTo(TwoLng other) => CompareTo(other);
        }

        private const string BigErr = "(err: number too big)";

        private static int AutoSeed(ParameterBag parameters)
        {
            if (parameters.ContainsKey("seed") && parameters["seed"] != null && parameters["seed"].IsInt32)
                return parameters["seed"].AsInt32;

            return Base.DefaultSeed();
        }

        public static StepOutput RptRandomBlock(ParameterBag parameters)
        {
            int seed = AutoSeed(parameters);
            MersenneTwister mt = new(seed);
            int n = parameters["n"].AsInt32;
            if (n < 4)
                n = 4;
            int blockSize = -1;
            if (parameters.ContainsKey("b"))
                blockSize = parameters["b"].AsInt32;
            bool blockSizeIsRandom = blockSize <= 0;
            if (!blockSizeIsRandom)
            {
                if (blockSize < 2)
                    blockSize = 2;
            }
            int t = parameters["t"].AsInt32;
            if (t < 2)
                t = 2;
            if (n / (double)t != Math.Floor(n / (double)t))
                throw new InvalidDataException("Number of subjects must be divisible by the number of treatments");

            ParameterBag outputParameters = new();
            outputParameters.AddOutput("seed_out", seed);
            outputParameters.AddOutput("n_out", n);
            outputParameters.AddOutput("t_out", t);

            TwoLng[] x;
            int ctr;
            if (!blockSizeIsRandom)
            {
                // FIXED BLOCK SIZE
                if (n / (double)blockSize != Math.Floor(n / (double)blockSize))
                {
                    string warning = $"The final block size will be {n % blockSize} not {blockSize} because the number of subjects is not divisible by the block size.";
                    outputParameters.AddOutput("*blockSizeWarn", new List<ParameterBag>() { new ParameterBag("warning", new FilledStringParameter(FilledParameterDirection.Output, warning)) });
                }

                int bks = (int)Math.Floor((double)n / blockSize);
                if (blockSize / (double)t != Math.Floor(blockSize / (double)t))
                    throw new InvalidDataException("Block size must be divisible by the number of treatments");

                x = new TwoLng[blockSize * bks + 1];
                ctr = 0;
                do
                {
                    // curtail the random block size selection if we are at the end of the allocation space
                    int bs = n - ctr < blockSize ? n - ctr : blockSize;

                    // for each block allocate the block pattern as treatments in alphanumeric order
                    for (int j = 1; j <= (int)Math.Floor((double)bs / t); j++)
                    {
                        for (int i = 1; i <= t; i++)
                        {
                            ctr += 1;
                            x[ctr].Rx = i;
                        }
                    }
                    // randomise the order of the block pattern by allocating an order number at random for each element then bubble sort the array
                    int high = ctr;
                    int low = ctr - bs + 1;
                    for (int j = high; j >= low; j--)
                        x[j].Id = (int)Math.Floor((high - low + 1) * mt.NextDouble() + low);

                    // exit the loop if all subjects have been allocated a block
                    if (ctr >= n)
                        break;
                }
                while (true);
                outputParameters.AddOutput("b_out", blockSize);
            }
            else
            {
                // RANDOM BLOCK SIZE
                int minBlockMult = 2;
                int maxBlockMult = 4;
                //  allocate a two-element array: treatment element & subject/order element
                x = new TwoLng[n + 1];
                ctr = 0;
                int bks = 0;
                do
                {
                    bks += 1;
                    // allocate at random a block size of between 'low' and 'high' times the number of treatment groups
                    int bs;
                    if (n - ctr < maxBlockMult * t)
                    {
                        // curtail the random block size selection if we are at the end of the allocation space
                        bs = n - ctr;
                    }
                    else
                    {
                        // pick a multiplier at random between 'low' and 'high' if there is room in the allocation space
                        bs = t * (int)Math.Floor((maxBlockMult - minBlockMult + 1) * mt.NextDouble() + minBlockMult);
                    }
                    // for each block allocate the block pattern as treatments in alphanumeric order
                    for (int j = 1; j <= (int)Math.Floor((double)bs / t); j++)
                    {
                        for (int i = 1; i <= t; i++)
                        {
                            ctr += 1;
                            x[ctr].Rx = i;
                        }
                    }
                    // randomise the order of the block pattern by allocating an order number at random for each element then bubble sort the array
                    int high = ctr;
                    int low = ctr - bs + 1;
                    for (int j = high; j >= low; j--)
                        x[j].Id = (int)Math.Floor((high - low + 1) * mt.NextDouble() + low);

                    // exit the loop if all subjects have been allocated a block
                    if (ctr >= n)
                        break;
                }
                while (true);
                outputParameters.AddOutput("b", "random between " + minBlockMult * t + " and " + maxBlockMult * t);
            }

            //  sort the id numbers within blocks
            Array.Sort(x, 1, ctr);

            List<ParameterBag> subjectsList = new();
            outputParameters.AddOutput("*subjects", subjectsList);
            for (int i = 1; i <= n; i++)
            {
                ParameterBag subjectsParameters = new();
                subjectsList.Add(subjectsParameters);
                subjectsParameters.AddOutput("id", i);
                subjectsParameters.AddOutput("rx", new string(Convert.ToChar(64 + x[i].Rx), 1));
            }
            return new StepOutput(outputParameters);
        }

        public static StepOutput RptSizeCorrelation(ParameterBag parameters)
        {
            double p = parameters["p"].AsDouble;
            double a = parameters["a"].AsDouble;
            double r0 = parameters["r0"].AsDouble;
            double r1 = parameters["r1"].AsDouble;
            if (p >= 1.0 || p < 0.000001)
                p = 0.8;
            if (a >= 1.0 || p < 0.000001)
                p = 0.05;

            if (r0 < 0.0 || r0 > 1.0 || r1 <= 0.0 || r1 >= 1.0)
                throw new InvalidDataException();

            double xsig = a / 2.0;
            double zsig = PDF.gauinv(1.0 - xsig, out int flt);
            if (flt != 0)
                throw new InvalidDataException();
            double zpow = PDF.gauinv(p, out flt);
            if (flt != 0)
                throw new InvalidDataException();

            double ztot = zpow + zsig;
            double dif = Math.Abs(Power.fisher_z1(r0) - Power.fisher_z1(r1));
            double sn = Math.Pow(ztot / dif, 2.0) + 3.0;
            // smallest integer n at which the Fisher z power (z ~ N(z(r), 1 / (n - 3))) reaches the target
            if (sn < int.MaxValue)
            {
                sn = Math.Max(Math.Ceiling(sn), 4.0);
                while (sn > 4.0 && x_rpower(dif, sn - 1.0, zsig) >= p)
                    sn -= 1.0;
                while (sn < int.MaxValue && x_rpower(dif, sn, zsig) < p)
                    sn += 1.0;
            }
            else
                sn = Math.Floor(sn) + 1;

            ParameterBag outputParameters = new();
            outputParameters.AddOutput("alpha", a);
            outputParameters.AddOutput("power", p);
            outputParameters.AddOutput("r0Fmt", r0);
            outputParameters.AddOutput("r1Fmt", r1);
            outputParameters.AddOutput("size", sn);
            return new StepOutput(outputParameters);
        }

        /// <summary>
        /// two sided power for a difference dif between Fisher z transformed correlation coefficients with n pairs
        /// </summary>
        private static double x_rpower(double dif, double n, double zsig)
        {
            double z = dif * Math.Sqrt(n - 3.0);
            return PDF.alnorm(z - zsig) + PDF.alnorm(-z - zsig);
        }

        public static StepOutput RptSizeSurvival(ParameterBag parameters)
        {
            double hr = 0;
            double et = 0;

            double power = parameters["p"].AsDouble;
            double alpha = parameters["a"].AsDouble;
            double beta = 1.0 - power;
            double ct = parameters["ct"].AsDouble;
            double at = parameters["at"].AsDouble;
            double fut = parameters["fut"].AsDouble;
            double M = parameters["m"].AsDouble;
            if (ct != 0.0)
            {
                bool hasEt = "time".Equals(parameters["time-or-hr"].AsString);
                // hr is the hazard of experimental subjects relative to controls, as the prompt asks for it. With exponential
                // survival the hazard is ln(2) / median, so the hazards are in the inverse ratio of the median survival times.
                if (hasEt)
                {
                    et = parameters["et"].AsDouble;
                    hr = ct / et;
                }
                else
                {
                    hr = parameters["hr"].AsDouble;
                    et = ct / hr;
                }
            }
            if (ct > 0.0 && et > 0.0 && power > 0.0 && power < 1.0 && alpha > 0.0 && alpha < 1.0 && hr != 1.0 && hr > 0.0 && !double.IsInfinity(hr) && at >= 0.0 && fut >= 0.0 && at + fut > 0.0)
            {
                if (at == 0.0)
                    at = fut * 0.00004;
                if (M <= 0.0)
                    M = 1;
                double avt = (ct + et) / 2.0;
                double pa = (1.0 - Math.Exp(-Math.Log(2.0) * at / avt)) / (Math.Log(2.0) * at / avt);
                double P = 1.0 - pa * Math.Exp(-Math.Log(2.0) * fut / avt);
                double zalpha = zcvalue(alpha / 2.0);
                double zbeta = zcvalue(beta);
                double n;
                try
                {
                    n = Math.Pow(zalpha + zbeta, 2.0) * ((1.0 + 1.0 / M) / P) / Math.Pow(Math.Log(hr), 2.0);
                    // rounded as the other sample size functions round. It used to add one and then round up, one subject more than they give.
                    n = Math.Floor(n) + 1;
                }
                catch (Exception)
                {
                    n = -1.0;
                }

                ParameterBag outputParameters = new();
                outputParameters.AddOutput("ctFmt", ct);
                // the experimental median is shown whichever way the inputs were given, so that the direction of the ratio is visible
                outputParameters.AddOutput("etFmt", et);
                outputParameters.AddOutput("hrFmt", hr);
                outputParameters.AddOutput("atFmt", at);
                outputParameters.AddOutput("futFmt", fut);
                outputParameters.AddOutput("alpha", alpha);
                outputParameters.AddOutput("power", power);
                if (n == -1.0)
                {
                    outputParameters.AddOutput("size", BigErr);
                    outputParameters.AddOutput("controls", BigErr);
                }
                else
                {
                    outputParameters.AddOutput("size", n);
                    outputParameters.AddOutput("controls", Math.Ceiling(n * M));
                }
                List<ParameterBag> assumptionsList = new();
                outputParameters.AddOutput("*assumptions", assumptionsList);
                if (2.0 * zalpha + zbeta <= 3.1)
                    assumptionsList.Add(x_disclaim(1.0 - beta, 1.0 - beta + alpha / 2.0, n));
                return new StepOutput(outputParameters);
            }
            throw new InvalidDataException();
        }

        private static double x_f(int f, double n, double alpha, double beta, double k, double M)
        {
            double x_fReturn = 0;

            if (f == 1)
            {
                if (beta == 0.0)
                    return Constant.MISSING;

                double alpha_t = PDF.tfromp(alpha / 2.0, n - 1.0);
                //  Reproduce previous behaviour
                if (double.IsNaN(alpha_t))
                    alpha_t = Constant.MISSING;
                double beta_t = PDF.tfromp(beta, n - 1.0);
                //  Reproduce previous behaviour
                if (double.IsNaN(beta_t))
                    beta_t = Constant.MISSING;
                x_fReturn = Math.Pow(alpha_t + beta_t, 2.0) / Math.Pow(k, 2.0) - n;
                //  Reproduce previous behaviour
                if (double.IsInfinity(x_fReturn))
                    x_fReturn = 0;
            }
            else if (f == 2)
            {
                if (beta == 0.0)
                    return Constant.MISSING;

                double t1 = PDF.tfromp(alpha / 2.0, n * (M + 1.0) - 2.0);
                if (double.IsNaN(t1))
                    t1 = Constant.MISSING;
                double t2 = PDF.tfromp(beta, n * (M + 1.0) - 2.0);
                if (double.IsNaN(t2))
                    t2 = Constant.MISSING;
                x_fReturn = (1.0 + 1.0 / M) * Math.Pow(t1 + t2, 2.0) / Math.Pow(k, 2.0) - n;
                //  Reproduce previous behaviour
                if (double.IsInfinity(x_fReturn))
                    x_fReturn = 0;
            }
            return x_fReturn;
        }

        private static void x_tsample(double aa, double bb, double kk, double mm, int typ, ref double xn, out int ifault)
        {
            double n0;

            double alpha = aa;
            double beta = bb;
            int er;
            ifault = 1;
            double k = kk;
            double m = mm;
            if (typ == 1)
            {
                n0 = Math.Pow(x_zvalc(alpha / 2.0, out er) + x_zvalc(beta, out er), 2.0) / Math.Pow(k, 2.0); // TODO: This has always been unable to detect one of the errors in er on this line.
                if (er != 0)
                    return;
                ifault = 2;
                x_zroot(1, ref n0, 0.0001, ref xn, alpha, beta, k, m, ref er);
            }
            else
            {
                n0 = (1.0 + 1.0 / m) * Math.Pow(x_zvalc(alpha / 2.0, out er) + x_zvalc(beta, out er), 2.0) / Math.Pow(k, 2.0); // TODO: This has always been unable to detect one of the errors in er on this line.
                if (er != 0)
                    return;
                ifault = 2;
                x_zroot(2, ref n0, 0.0001, ref xn, alpha, beta, k, m, ref er);
            }
            if (er != 0)
                xn = n0;
            else
                ifault = 0;
        }

        private static void x_zroot(int f, ref double x0, double eps, ref double xn, double alpha, double beta, double k, double m, ref int er)
        {
            const int imax = 200;
            double x1 = x0 + 1;
            int iter = 0;
            do
            {
                double fx0 = x_f(f, x0, alpha, beta, k, m);
                double fx1 = x_f(f, x1, alpha, beta, k, m);
                if (Math.Abs(fx0) <= eps)
                {
                    xn = x0;
                    break;
                }
                iter++;
                if (iter > imax)
                {
                    er = 1;
                    break;
                }
                double xnext = x1 - fx1 * (x1 - x0) / (fx1 - fx0);
                x0 = x1;
                x1 = xnext;
            }
            while (true);
        }

        private static double x_zvalc(double alpha, out int er) => -PDF.gauinv(alpha, out er);

        public static StepOutput RptRandomPairs(ParameterBag parameters)
        {
            int seed = AutoSeed(parameters);
            MersenneTwister mt = new(seed);
            int pairs = parameters["pairs"].AsInt32;
            bool balance = pairs >= 1 && Math.Floor(pairs / 2.0) == pairs / 2.0 && parameters["balance"].AsBoolean;

            ParameterBag outputParameters = new();
            if (balance)
                outputParameters.AddOutput("seedAndNote", seed + ",  balanced allocation");
            else
                outputParameters.AddOutput("seedAndNote", seed);

            if (pairs >= 1)
            {
                bool[] rand = new bool[pairs + 1 /* VB to C# conversion */ ];
                if (balance)
                {
                    for (int n = 1; n <= pairs; n++)
                        rand[n] = !rand[n - 1];
                    for (int tn = 1; tn <= 3; tn++)
                    {
                        for (int n = 1; n <= pairs; n++)
                        {
                            int nrp = Convert.ToInt32(Math.Floor(pairs * mt.NextDouble()) + 1);
                            (rand[nrp], rand[n]) = (rand[n], rand[nrp]);
                        }
                    }
                }
                else
                {
                    for (int n = 1; n <= pairs; n++)
                        rand[n] = mt.NextDouble() >= 0.5;
                }
                List<ParameterBag> pairsList = new();
                outputParameters.AddOutput("*pairs", pairsList);
                for (int n = 1; n <= pairs; n++)
                {
                    string f = n < 10000 ? "####  " : "#####  ";
                    ParameterBag pairsParameters = new();
                    pairsList.Add(pairsParameters);
                    pairsParameters.AddOutput("index", n.ToString(f));
                    pairsParameters.AddOutput("random", rand[n] ? "Control - Intervention" : "Intervention - Control");
                }
                return new StepOutput(outputParameters);
            }
            throw new InvalidDataException();
        }

        public static StepOutput RptRandomUnPaired(ParameterBag parameters)
        {
            int seed = AutoSeed(parameters);
            MersenneTwister mt = new(seed);
            const int low = 1;
            int high = parameters["high"].AsInt32;
            if (high >= 2 && high % high / 2 == 0)
            {
                int dimit = Math.Abs(high - low) + 1;
                int[] rand = new int[dimit + 1 /* VB to C# conversion */ ];
                int[] arand = new int[(int)Math.Floor((double)dimit / 2) + 1 ];
                int[] brand = new int[(int)Math.Floor((double)dimit / 2) + 1 ];
                for (int N = low; N <= high; N++)
                    rand[N] = N;
                for (int N = low; N <= high; N++)
                {
                    int nrp = (int)Math.Floor((high - low + 1) * mt.NextDouble() + low);
                    (rand[nrp], rand[N]) = (rand[N], rand[nrp]);
                }
                int halfHigh = Convert.ToInt32(high / 2);
                for (int N = low; N <= halfHigh; N++)
                {
                    arand[N] = rand[N];
                    brand[N] = rand[halfHigh + N];
                }
                Array.Sort(arand, 1, halfHigh);
                Array.Sort(brand, 1, halfHigh);

                ParameterBag outputParameters = new();
                // outputParameters.AddOutput("seed", seed); Not required as input seed is preserved in output
                List<ParameterBag> allocationsList = new();
                outputParameters.AddOutput("*allocations", allocationsList);
                for (int N = 1; N <= halfHigh; N++)
                {
                    ParameterBag allocationsParameters = new();
                    allocationsList.Add(allocationsParameters);
                    allocationsParameters.AddOutput("case", arand[N]);
                    allocationsParameters.AddOutput("control", brand[N]);
                }
                return new StepOutput(outputParameters);
            }
            throw new InvalidDataException();
        }

        public static StepOutput RptRandomXY(ParameterBag parameters)
        {
            int seed = AutoSeed(parameters);
            MersenneTwister mt = new(seed);
            int low = parameters["low"].AsInt32;
            int high = parameters["high"].AsInt32;
            if (low > high)
                (high, low) = (low, high);
            if (low >= 0 & high >= 1)
            {
                int[] rand = new int[high + 2 ];
                for (int N = low; N <= high; N++)
                    rand[N] = N;
                for (int tn = 1; tn <= 3; tn++)
                {
                    for (int N = low; N <= high; N++)
                    {
                        int nrp = (int)Math.Floor((high - low + 1) * mt.NextDouble() + low);
                        (rand[nrp], rand[N]) = (rand[N], rand[nrp]);
                    }
                }

                ParameterBag outputParameters = new();
                // outputParameters.AddOutput("seed", seed); Not required as input seed is preserved in output
                List<ParameterBag> allocationsList = new();
                outputParameters.AddOutput("*allocations", allocationsList);
                for (int N = low; N <= high; N++)
                {
                    ParameterBag allocationsParameters = new();
                    allocationsList.Add(allocationsParameters);
                    allocationsParameters.AddOutput("index", N.ToString("#####"));
                    allocationsParameters.AddOutput("random", rand[N]);
                }
                return new StepOutput(outputParameters);
            }
            throw new InvalidDataException();
        }

        public static StepOutput RptSizeIndCase(ParameterBag parameters)
        {
            double power = parameters["p"].AsDouble;
            double alpha = parameters["a"].AsDouble;
            double beta = 1.0 - power;
            double p0 = parameters["p0"].AsDouble;
            if (p0 > 1.0)
                p0 = 1.0;
            if (p0 < 0.0)
                p0 = 0.0;
            bool hasP1 = "prop".Equals(parameters["prop-or-or"].AsString);
            double p1;
            if (hasP1)
            {
                p1 = parameters["p1"].AsDouble;
            }
            else
            {
                double r = parameters["r"].AsDouble;
                p1 = p0 * r / (1.0 + p0 * (r - 1.0));
            }
            if (p1 > 1.0)
                p1 = 1.0;
            if (p1 < 0.0)
                p1 = 0.0;
            double M = parameters["m"].AsDouble;
            if (p1 != p0 && M > 0)
            {
                double N;
                double ncor = 0;
                double zalpha = 0; double pbar = 0;

                try
                {
                    zalpha = zcvalue(alpha / 2.0);
                    pbar = (p1 + M * p0) / (M + 1.0);
                    double nx = Math.Pow(zalpha * Math.Sqrt((1.0 + 1.0 / M) * pbar * (1.0 - pbar)) + zcvalue(1.0 - power) * Math.Sqrt(p0 * (1.0 - p0) / M + p1 * (1.0 - p1)), 2.0) / Math.Pow(p0 - p1, 2.0);
                    N = Math.Floor(nx) + 1.0;
                    ncor = Math.Floor(nx / 4.0 * Math.Pow(1.0 + Math.Sqrt(1.0 + 2.0 * (M + 1.0) / (nx * M * Math.Abs(p0 - p1))), 2.0)) + 1.0;
                }
                catch (Exception)
                {
                    N = -1.0;
                }

                ParameterBag outputParameters = new();
                outputParameters.AddOutput("pc", p0);
                outputParameters.AddOutput("ps", p1);
                outputParameters.AddOutput("cpc", M);
                outputParameters.AddOutput("alpha", alpha);
                outputParameters.AddOutput("power", power);
                if (N == -1.0)
                {
                    outputParameters.AddOutput("case", BigErr);
                    outputParameters.AddOutput("controls", BigErr);
                    outputParameters.AddOutput("case_corr", BigErr);
                    outputParameters.AddOutput("controls_corr", BigErr);
                }
                else
                {
                    outputParameters.AddOutput("case", N);
                    outputParameters.AddOutput("controls", Math.Floor(M * N));
                    outputParameters.AddOutput("case_corr", ncor);
                    outputParameters.AddOutput("controls_corr", Math.Floor(M * ncor));
                }
                double sigmaa = Math.Sqrt(p0 * (1.0 - p0) / M + p1 * (1.0 - p1));
                double sigma0 = Math.Sqrt((1.0 + 1.0 / M) * pbar * (1.0 - pbar));
                double zbeta = zcvalue(1.0 - power);
                List<ParameterBag> assumptionsList = new();
                outputParameters.AddOutput("*assumptions", assumptionsList);
                if (2.0 * (sigma0 / sigmaa) * zalpha + zbeta <= 3.1)
                    assumptionsList.Add(x_disclaim(1.0 - beta, 1.0 - beta + alpha / 2.0, N));
                return new StepOutput(outputParameters);
            }
            throw new InvalidDataException();
        }

        public static StepOutput RptSizeIndProp(ParameterBag parameters)
        {
            double P1;
            double zalpha = 0; double pbar = 0;
            double ncor = 0;

            double power = parameters["p"].AsDouble;
            double alpha = parameters["a"].AsDouble;
            double beta = 1.0 - power;
            double P0 = parameters["p0"].AsDouble;
            if (P0 > 1.0)
                P0 = 1.0;
            if (P0 < 0.0)
                P0 = 0.0;
            bool hasP1 = "prop".Equals(parameters["prop-or-or"].AsString);
            if (hasP1)
            {
                P1 = parameters["p1"].AsDouble;
            }
            else
            {
                double r = parameters["r"].AsDouble;
                P1 = P0 * r;
            }
            if (P1 > 1.0)
                P1 = 1.0;
            if (P1 < 0.0)
                P1 = 0.0;
            double M = parameters["m"].AsDouble;
            if (P1 != P0 && M > 0)
            {
                double N;
                try
                {
                    zalpha = zcvalue(alpha / 2.0);
                    pbar = (P1 + M * P0) / (M + 1.0);
                    double nx = Math.Pow(zalpha * Math.Sqrt((1.0 + 1.0 / M) * pbar * (1.0 - pbar)) + zcvalue(1.0 - power) * Math.Sqrt(P0 * (1.0 - P0) / M + P1 * (1.0 - P1)), 2.0) / Math.Pow(P0 - P1, 2.0);
                    N = Math.Floor(nx) + 1.0;
                    ncor = Math.Floor(nx / 4.0 * Math.Pow(1.0 + Math.Sqrt(1.0 + 2.0 * (M + 1.0) / (nx * M * Math.Abs(P0 - P1))), 2.0)) + 1.0;
                }
                catch (Exception)
                {
                    N = -1.0;
                }

                ParameterBag outputParameters = new();
                outputParameters.AddOutput("pc", P0);
                outputParameters.AddOutput("ps", P1);
                outputParameters.AddOutput("cpc", M);
                outputParameters.AddOutput("alpha", alpha);
                outputParameters.AddOutput("power", power);
                if (N == -1.0)
                {
                    outputParameters.AddOutput("case", BigErr);
                    outputParameters.AddOutput("controls", BigErr);
                    outputParameters.AddOutput("case_corr", BigErr);
                    outputParameters.AddOutput("controls_corr", BigErr);
                }
                else
                {
                    outputParameters.AddOutput("case", N);
                    outputParameters.AddOutput("controls", Math.Floor(M * N));
                    outputParameters.AddOutput("case_corr", ncor);
                    outputParameters.AddOutput("controls_corr", Math.Floor(M * ncor));
                }
                double sigmaa = Math.Sqrt(P0 * (1.0 - P0) / M + P1 * (1.0 - P1));
                double sigma0 = Math.Sqrt((1.0 + 1.0 / M) * pbar * (1.0 - pbar));
                double zbeta = zcvalue(1.0 - power);
                List<ParameterBag> assumptionsList = new();
                outputParameters.AddOutput("*assumptions", assumptionsList);
                if (2.0 * (sigma0 / sigmaa) * zalpha + zbeta <= 3.1)
                    assumptionsList.Add(x_disclaim(1.0 - beta, 1.0 - beta + alpha / 2.0, N));
                return new StepOutput(outputParameters);
            }
            throw new InvalidDataException();
        }

        public static StepOutput RptSizeMatchCase(ParameterBag parameters)
        {

            double power = parameters["p"].AsDouble;
            double alpha = parameters["a"].AsDouble;
            double beta = 1.0 - power;
            double ph = parameters["ph"].AsDouble;
            double p0 = parameters["p0"].AsDouble;
            double ps = parameters["ps"].AsDouble;
            double M = parameters["m"].AsDouble;
            ssize(alpha, beta, ph, p0, M, ps, out double N, out double FM, out double sigmar, out int fault);

            ParameterBag outputParameters = new();
            outputParameters.AddOutput("corr", ph);
            outputParameters.AddOutput("pc", p0);
            outputParameters.AddOutput("odds", ps);
            outputParameters.AddOutput("cpc", M);
            outputParameters.AddOutput("alpha", alpha);
            outputParameters.AddOutput("power", power);
            List<ParameterBag> lowerList = new();
            outputParameters.AddOutput("*lower", lowerList);
            if (beta >= 0.8)
                lowerList.Add(new ParameterBag());
            if (fault == 0)
            {
                //  TODO: RTF_DeleteBlock() on the illegal piece, which is always removed in valid cases.
                outputParameters.AddOutput("size", N);
                List<ParameterBag> reductionList = new();
                outputParameters.AddOutput("*reduction", reductionList);
                if (M > 1)
                {
                    ParameterBag reductionParameters = new();
                    reductionList.Add(reductionParameters);
                    reductionParameters.AddOutput("controls", M);
                    reductionParameters.AddOutput("reduction", FM);
                }
                double zalpha = zcvalue(alpha / 2.0);
                double zbeta = zcvalue(beta);
                List<ParameterBag> assumptionsList = new();
                outputParameters.AddOutput("*assumptions", assumptionsList);
                if (2.0 * sigmar * zalpha + zbeta <= 3.1)
                    assumptionsList.Add(x_disclaim(1.0 - beta, 1.0 - beta + alpha / 2.0, N));
                return new StepOutput(outputParameters);
            }
            throw new InvalidDataException();
        }

        public static StepOutput RptSizeMatchProp(ParameterBag parameters)
        {
            double P1;
            double N = 0;
            const string caption = "Comparision of proportions for paired cohort study";

            double power = parameters["p"].AsDouble;
            double alpha = parameters["a"].AsDouble;
            double BETA = 1.0 - power;
            double P0 = parameters["p0"].AsDouble;
            if (P0 > 1.0)
                P0 = 1.0;
            if (P0 < 0.0)
                P0 = 0.0;
            double ph = parameters["ph"].AsDouble;
            bool hasRr = "rr".Equals(parameters["er-or-rr"].AsString);
            if (hasRr)
            {
                double rr = parameters["rr"].AsDouble;
                P1 = rr * P0;
            }
            else
            {
                P1 = parameters["p1"].AsDouble;
            }
            if (P1 > 1.0)
                P1 = 1.0;
            if (P1 < 0.0)
                P1 = 0.0;
            if (P1 != P0 && ph > -1.0 && ph < 1.0)
            {
                ParameterBag outputParameters = new();
                outputParameters.AddOutput("pc", P0);
                outputParameters.AddOutput("ps", P1);
                outputParameters.AddOutput("r", ph);
                outputParameters.AddOutput("alpha", alpha);
                outputParameters.AddOutput("power", power);
                double zalpha = zcvalue(alpha / 2.0);
                double zbeta = zcvalue(BETA);
                double Q1 = 1.0 - P1;
                double Q0 = 1.0 - P0;
                double p10 = P1 * Q0 - ph * Math.Sqrt(P1 * Q1 * P0 * Q0);
                double p01 = Q1 * P0 - ph * Math.Sqrt(P1 * Q1 * P0 * Q0);
                double pa = p10 / (p01 + p10);
                double qa = 1.0 - pa;
                if (pa * qa <= 0.0)
                    throw new TemplateOperationCancelledException("Calculation not possible, try a smaller value for correlation.", caption);
                try
                {
                    N = Math.Floor(Math.Pow(zalpha * 0.5 + zbeta * Math.Sqrt(Math.Abs(pa * qa)), 2.0) / (Math.Pow(pa - 0.5, 2.0) * (p01 + p10))) + 1.0;
                    outputParameters.AddOutput("size", N);
                }
                catch (Exception)
                {
                    outputParameters.AddOutput("size", BigErr);
                }
                List<ParameterBag> assumptionsList = new();
                outputParameters.AddOutput("*assumptions", assumptionsList);
                if (2 * (0.5 / Math.Sqrt(Math.Abs(pa * qa))) * zalpha + zbeta <= 3.1)
                {
                    assumptionsList.Add(x_disclaim(1.0 - BETA, 1.0 - BETA + alpha / 2.0, N));
                }
                return new StepOutput(outputParameters);
            }
            throw new InvalidDataException();
        }


        private static double zcvalue(double alph) => -PDF.gauinv(alph);

        private static void ssize(double salpha, double sBeta, double sr, double sp0, double M, double xspsi, out double N, out double FM, out double sigmar, out int er)
        {
            double n1 = 0;
            double nm = 0;

            double[] t = new double[1000 + 1];
            er = 0;
            double rm = M;
            double r = sr;
            double P0 = sp0;
            double dpsi = xspsi;
            double zalpha = zcvalue(salpha / 2.0);
            double zbeta = zcvalue(sBeta);
            N = 0;
            FM = 0;
            sigmar = 0;
            if (dpsi <= 0)
            {
                er = 2;
                return;
            }
            MathDbl.pone(P0, dpsi, r, out double P1, out bool impossible);
            if (impossible)
            {
                er = 1;
                return;
            }
            double Q1 = 1.0 - P1;
            double Q0 = 1.0 - P0;
            double p01 = P0 + r * Math.Sqrt(Q1 * P0 * Q0 / P1);
            double p00 = P0 - r * Math.Sqrt(P1 * P0 * Q0 / Q1);
            double q01 = 1.0 - p01;
            double q00 = 1.0 - p00;
            int im = (int)Math.Floor(M);
            do
            {
                double C1 = 1;
                double C2 = rm;
                for (int i = 1; i <= im; i++)
                {
                    t[i] = P1 * C1 * Math.Pow(p01, i - 1) * Math.Pow(q01, im - i + 1) + Q1 * C2 * Math.Pow(p00, i) * Math.Pow(q00, im - i);
                    C1 = C2;
                    C2 = C2 * (rm - i) / ((double)i + 1);
                }
                double E1 = 0;
                for (int i = 1; i <= im; i++)
                    E1 += i * t[i] / (rm + 1.0);
                double v1 = 0.0;
                for (int i = 1; i <= im; i++)
                    v1 += i * t[i] * (rm - i + 1.0) / Math.Pow(rm + 1.0, 2.0);
                double epsi = 0.0;
                for (int i = 1; i <= im; i++)
                    epsi += i * t[i] * dpsi / (i * dpsi + rm - i + 1.0);
                double vpsi = 0;
                for (int i = 1; i <= im; i++)
                    vpsi += i * t[i] * dpsi * (rm - i + 1.0) / Math.Pow(i * dpsi + rm - i + 1, 2.0);
                double S1 = Math.Sqrt(v1);
                double spsi = Math.Sqrt(vpsi);
                sigmar = S1 / spsi;
                if (rm > 1.0)
                {
                    nm = Math.Pow(zbeta * spsi + zalpha * S1, 2.0) / Math.Pow(epsi - E1, 2.0);
                    N = Math.Floor(nm) + 1.0;
                    rm = 1.0;
                    im = 1;
                }
                else if (rm == 1.0)
                {
                    n1 = Math.Pow(zbeta * spsi + zalpha * S1, 2.0) / Math.Pow(epsi - E1, 2.0);
                    break;
                }
                else
                {
                    break;
                }
            }
            while (true);
            if (M > 1)
            {
                FM = Convert.ToDouble(Convert.ToInt64(nm)) / Convert.ToDouble(Convert.ToInt64(n1));
            }
            else
            {
                N = Math.Floor(n1) + 1.0;
                FM = 1.0;
            }
        }


        public static StepOutput RptSizePaired(ParameterBag parameters)
        {
            double N;
            double xn = 0;

            double P = parameters["p"].AsDouble;
            double a = parameters["a"].AsDouble;
            double D = parameters["d"].AsDouble;
            double sd = parameters["sd"].AsDouble;
            if (P >= 1.0 || P < 0.000001)
                P = 0.8;
            if (a >= 1.0 || P < 0.000001)
                P = 0.05;
            double k = D / sd;
            bool ok = true;
            const double omega = 0.0001;
            if (Math.Abs(k) < omega)
            {
                k = omega;
                ok = false;
            }
            double b = 1.0 - P;
            double M = 1.0;
            x_tsample(a, b, k, M, 1, ref xn, out int flt);
            if (xn < Convert.ToDouble(int.MaxValue))
            {
                N = Math.Floor(xn) + 1.0;
                if (ok)
                    N = x_ncsize(false, a, P, D, sd, M, N);
            }
            else
            {
                N = int.MaxValue;
                ok = false;
            }
            if (flt == 0 || flt == 2)
            {
                ParameterBag outputParameters = new();
                outputParameters.AddOutput("tt", "a paired or single sample");
                x_tres(outputParameters, false, a, b, P, M, N, D, sd);
                if (!ok)
                    outputParameters.AddOutput("*sample_size_warn", new List<ParameterBag>{ new ParameterBag() });
                return new StepOutput(outputParameters);
            }
            throw new InvalidDataException();
        }


        public static StepOutput RptSizePopSurvey(ParameterBag parameters)
        {
            // double af = 2; 
            double ps = parameters["ps"].AsDouble;
            double P = parameters["p"].AsDouble;
            double xd = parameters["xd"].AsDouble;
            double cco = parameters["cco"].AsDouble;
            if (cco <= 0.0 | cco >= 1.0)
            {
                cco = 0.95;
            }
            double cit = PDF.gauinv(cco + (1.0 - cco) / 2.0, out int fault);
            if (fault == 0)
            {
                double xza = cit;
                P /= 100.0;
                xd /= 100.0;
                if (xd <= 0.0 | ps <= 0.0)
                {
                    throw new InvalidDataException();
                }
                double sn = xza * xza * P * (1.0 - P) / (xd * xd);
                sn /= (1.0 + sn / ps);

                ParameterBag outputParameters = new();
                outputParameters.AddOutput("estimate", ps);
                outputParameters.AddOutput("rate", P * 100);
                outputParameters.AddOutput("deviation", xd * 100);
                outputParameters.AddOutput("level", 100 * cco);
                outputParameters.AddOutput("size", Math.Floor(sn) + 1);
                return new StepOutput(outputParameters);
            }
            return null;
        }


        public static StepOutput RptSizeUnPaired(ParameterBag parameters)
        {
            double N; double xn = 0;

            double P = parameters["p"].AsDouble;
            double a = parameters["a"].AsDouble;
            double D = parameters["d"].AsDouble;
            double sd = parameters["sd"].AsDouble;
            double M = parameters["m"].AsDouble;
            if (P >= 1 || P < 0.000001)
                P = 0.8;
            if (a >= 1 || P < 0.000001)
                P = 0.05;

            double k = D / sd;
            bool ok = true;
            const double omega = 0.0001;
            if (Math.Abs(k) < omega)
            {
                k = omega;
                ok = false;
            }
            double b = 1.0 - P;
            if (M <= 0)
                M = 1;
            x_tsample(a, b, k, M, 2, ref xn, out int fault);
            if (xn < Convert.ToDouble(int.MaxValue))
            {
                N = Math.Floor(xn) + 1L;
                if (ok)
                    N = x_ncsize(true, a, P, D, sd, M, N);
            }
            else
            {
                N = int.MaxValue;
                ok = false;
            }
            if (fault == 0 || fault == 2)
            {
                ParameterBag outputParameters = new();
                outputParameters.AddOutput("tt", "an unpaired two sample");
                x_tres(outputParameters, true, a, b, P, M, N, D, sd);
                if (!ok)
                    outputParameters.AddOutput("*sample_size_warn", new List<ParameterBag> { new ParameterBag() });
                return new StepOutput(outputParameters);
            }
            throw new InvalidDataException();
        }

        private static ParameterBag x_disclaim(double ll, double ul, double N)
        {
            ParameterBag outputParameters = new();
            outputParameters.AddOutput("cases", N);
            outputParameters.AddOutput("no_less", ll);
            outputParameters.AddOutput("no_greater", ul);
            return outputParameters;
        }

        private static double x_tpower(bool unpaired, double alpha, double delta, double sd, double m, double n) => unpaired ? Power.tstpower(alpha, delta, sd, n, m) : Power.ptpower(alpha, delta, sd, n);

        /// <summary>
        /// smallest integer sample size (per experimental group if unpaired) whose two sided non-central t power reaches the target, searched from the approximation n0
        /// </summary>
        private static double x_ncsize(bool unpaired, double alpha, double power, double delta, double sd, double m, double n0)
        {
            double n = Math.Max(n0, 2.0);
            double pw = x_tpower(unpaired, alpha, delta, sd, m, n);
            if (pw != Constant.MISSING && pw >= power)
            {
                while (n > 2.0)
                {
                    pw = x_tpower(unpaired, alpha, delta, sd, m, n - 1.0);
                    if (pw == Constant.MISSING || pw < power)
                        break;
                    n -= 1.0;
                }
                return n;
            }
            for (int i = 0; i < 1000; i++)
            {
                n += 1.0;
                pw = x_tpower(unpaired, alpha, delta, sd, m, n);
                if (pw != Constant.MISSING && pw >= power)
                    return n;
            }
            return n0;
        }

        private static void x_tres(ParameterBag outputParameters, bool unpaired, double alpha, double b, double power, double m, double n, double delta, double sd)
        {
            int ierr = 0;

            outputParameters.AddOutput("alpha", alpha);
            outputParameters.AddOutput("power", power);
            outputParameters.AddOutput("mean", unpaired ? "between means" : "of mean from zero");
            outputParameters.AddOutput("delta", delta);
            outputParameters.AddOutput("sd", sd);
            double df = n - 1.0;
            List<ParameterBag> controlsList = new();
            outputParameters.AddOutput("*controls", controlsList);
            if (unpaired)
            {
                ParameterBag controlsParameters = new();
                controlsList.Add(controlsParameters);
                controlsParameters.AddOutput("con_per", m);
                df = n * (m + 1) - 2.0;
            }
            outputParameters.AddOutput("size", n);

            List<ParameterBag> pairsList = new();
            outputParameters.AddOutput("*pairs", pairsList);
            List<ParameterBag> subjectsList = new();
            outputParameters.AddOutput("*subjects", subjectsList);
            if (unpaired)
            {
                ParameterBag subjectsParameters = new();
                subjectsList.Add(subjectsParameters);
                subjectsParameters.AddOutput("con_tot", Math.Floor(m * n));
            }
            else
            {
                pairsList.Add(new ParameterBag());
            }
            outputParameters.AddOutput("df", df);
            double ta = PDF.tfromp(alpha / 2.0, df);
            double tb = PDF.tfromp(b / 2.0, df);
            List<ParameterBag> assumptionsList = new();
            outputParameters.AddOutput("*assumptions", assumptionsList);
            if (ierr == 0 & 2.0 * ta + tb <= 3.1)
                assumptionsList.Add(x_disclaim(1.0 - b, 1.0 - b + alpha / 2.0, n));
        }
    }
}
