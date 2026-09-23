using StatsDirect.Numerics;
using StatsDirect.Data;
using StatsDirect.Templates;
using StatsDirect.Utilities;

using System;

namespace StatsDirect.Builtins
{
    public static class Agreement
    {

        public static StepOutput RptUniversalAgreement(ParameterBag parameters)
        {
            int nobs = 0;
            string title = null;
            string refIdent = null;
            GatherUniversalAgreementData(parameters, out int n, out int b, out int c, out double[,,] data, out bool standard, ref nobs, ref title, ref refIdent);

            double delta;
            double edel;
            double var;
            double gam;
            double r;
            double p;

            if (standard)
                AgreeStandard(n, b, c, data, out delta, out edel, out var, out gam, out r, out p);
            else
                Agree(n, b, c, data, out delta, out edel, out var, out gam, out r, out p);

            ParameterBag outputParameters = new();

            outputParameters.AddOutput("name", title);
            outputParameters.AddOutput("nobs", nobs);
            outputParameters.AddOutput("n", n);
            outputParameters.AddOutput("b", b);
            outputParameters.AddOutput("c", c);
            outputParameters.AddOutput("ref", refIdent);
            outputParameters.AddOutput("delta", delta);
            outputParameters.AddOutput("edel", edel);
            outputParameters.AddOutput("vardel", var);
            outputParameters.AddOutput("skewdel", gam);
            outputParameters.AddOutput("R", r);
            outputParameters.AddOutput("p", p);
            return new StepOutput(outputParameters);
        }


        private static void GatherUniversalAgreementData(ParameterBag parameters, out int n, out int b, out int c, out double[,,] data, out bool standard, ref int nobs, ref string title, ref string refIdent)
        {
            DataFrame dataFrame = parameters["data"].AsDataFrame;
            DoubleVariable dataVariable = (DoubleVariable)dataFrame.Variables[0];
            DataFrame ratersFrame = parameters["raters"].AsDataFrame;
            ClassifierVariable ratersVariable = (ClassifierVariable)ratersFrame.Variables[0];
            DataFrame objectsFrame = parameters["objects"].AsDataFrame;
            ClassifierVariable objectsVariable = (ClassifierVariable)objectsFrame.Variables[0];
            bool hasCategories = parameters.ContainsKey("categories") && parameters["categories"] != null;
            ClassifierVariable categoriesVariable = null;
            if (hasCategories)
            {
                DataFrame categoriesFrame = parameters["categories"].AsDataFrame;
                categoriesVariable = (ClassifierVariable)categoriesFrame.Variables[0];
            }

            n = objectsVariable.GroupCount;
            b = ratersVariable.GroupCount;
            c = 1;
            if (hasCategories)
                c = categoriesVariable.GroupCount;

            data = new double[n + 1, b + 1, c + 1];
            for (int i = 1; i <= n; i++)
                for (int j = 1; j <= b; j++)
                    for (int k = 1; k <= c; k++)
                        data[i, j, k] = Constant.MISSING;

            //  In the XML we ask the user to select "Which observer is a reference standard (leave blank for none)?" then set the standard flag to true if there is a reference standard
            standard = parameters.ContainsKey("reference");
            if (standard)
            {
                //  Work out which group number is the reference.  This is a bit ugly as the parameter is a boolean array based on what was passed in - which in this case is an alpha-sorted list of the group names.
                string[] groupNames = ratersVariable.SortedCategoryNames;
                bool[] standardArray = (bool[])parameters["reference"].AsObject;
                string referenceName = null;
                for (int finder = 0; finder <= groupNames.Length; finder++)
                {
                    if (standardArray[finder])
                    {
                        referenceName = groupNames[finder];
                        break;
                    }
                }
                if (referenceName == null)
                    throw new Exception("Could not match reference standard string");

                //  set the ref string to "Observer <name of reference category>" if there is a reference category
                refIdent = "Observer " + referenceName;

                //  Find the ID of the reference observer
                int referenceGroupNumber;
                for (referenceGroupNumber = 0; referenceGroupNumber < ratersVariable.GroupCount; referenceGroupNumber++)
                {
                    if (ratersVariable.Groups[referenceGroupNumber].Label == referenceName)
                        break;
                }
                if (referenceGroupNumber == ratersVariable.GroupCount)
                {
                    //  Should never happen - the earlier exception should have caught this case.  However, on the principle of belt and braces...
                    throw new Exception("Couldn't find reference standard in the group list");
                }
                //  rebase the coding of the observer variable so that the reference standard is the first observer.
                //  We do this the most obvious way: if the observer isn't id 0, swap its ID with 0.
                //  TODO: Is this always valid?  Is this proof against changes in the way group IDs are assigned?
                if (referenceGroupNumber > 0)
                {
                    Group oldZeroGroup = ratersVariable.Groups[0];
                    double oldZeroId = ratersVariable.Groups[0].Id;
                    double oldReferenceGroupId = ratersVariable.Groups[referenceGroupNumber].Id;
                    ratersVariable.Groups[0] = ratersVariable.Groups[referenceGroupNumber];
                    ratersVariable.Groups[referenceGroupNumber] = oldZeroGroup;
                    ratersVariable.Groups[0].Id = oldZeroId;
                    ratersVariable.Groups[referenceGroupNumber].Id = oldReferenceGroupId;
                    for (int i = 0; i < ratersVariable.Data.Length; i++)
                    {
                        int val = Convert.ToInt32(ratersVariable.Data[i]);
                        if (val == 0)
                        {
                            val = referenceGroupNumber;
                        }
                        else if (val == referenceGroupNumber)
                        {
                            val = 0;
                        }
                        ratersVariable.SetData(i, val);
                    }
                }
            }
            else
            {
                refIdent = "None";
            }

            nobs = 0;
            for (int row = 0; row < dataVariable.Length; row++)
            {
                double measurement = dataVariable.Data[row];
                double raterId = ratersVariable.Data[row];
                double objectId = objectsVariable.Data[row];
                double categoryId = 0;
                if (hasCategories)
                {
                    categoryId = categoriesVariable.Data[row];
                }
                if (!(measurement == Constant.MISSING || raterId == Constant.MISSING || objectId == Constant.MISSING || categoryId == Constant.MISSING))
                {
                    if (data[Convert.ToInt32(objectId) + 1, Convert.ToInt32(raterId) + 1, Convert.ToInt32(categoryId) + 1] != Constant.MISSING)
                    {
                        string specerr = hasCategories
                            ? "Object " + objectId + ", judge " + raterId + ", category " + categoryId + " has more than one measurement assigned."
                            : "Object " + objectId + ", judge " + raterId + " has more than one measurement assigned.";
                        throw new TemplateOperationCancelledException(specerr, "Universal agreement R");
                    }
                    data[Convert.ToInt32(objectId) + 1, Convert.ToInt32(raterId) + 1, Convert.ToInt32(categoryId) + 1] = measurement;
                    nobs += 1;
                }
            }

            //  Check for missing data and complain if any is found
            for (int i = 1; i <= n; i++)
            {
                for (int j = 1; j <= b; j++)
                {
                    for (int k = 1; k <= c; k++)
                    {
                        if (data[i, j, k] == Constant.MISSING)
                        {
                            string specerr = hasCategories
                                ? "A measurement must be specified for each judge, object and category."
                                : "A measurement must be specified for each judge and object.";
                            throw new TemplateOperationCancelledException(specerr, "Universal agreement R");
                        }
                    }
                }
            }

            if (hasCategories)
                title = dataVariable.Title + " (" + categoriesVariable.CommaSeparatedCategoryNames + ")";
            else
                title = dataVariable.Title;
        }

        public static StepOutput RptUniversalRCompare(ParameterBag parameters)
        {
            double r1 = parameters["r1_in"].AsDouble;
            double r2 = parameters["r2_in"].AsDouble;
            double mu1 = parameters["mu1_in"].AsDouble;
            double mu2 = parameters["mu2_in"].AsDouble;
            double var1 = parameters["var1_in"].AsDouble;
            double var2 = parameters["var2_in"].AsDouble;
            double gam1 = parameters["gam1_in"].AsDouble;
            double gam2 = parameters["gam2_in"].AsDouble;

            if (r1 == Constant.MISSING || r2 == Constant.MISSING || mu1 == Constant.MISSING || mu2 == Constant.MISSING || var1 == Constant.MISSING || var2 == Constant.MISSING || gam1 == Constant.MISSING || gam2 == Constant.MISSING)
                throw new TemplateOperationCancelledException("Please fill in all 8 values", "Compare two R values");

            double dr = r1 - r2;
            double dm = mu1 - mu2;
            double e1 = mu1 / (1.0 - r1);
            double e2 = mu2 / (1.0 - r2);
            double vard = (Math.Pow(mu1, 2.0) * var2 + Math.Pow(mu2, 2.0) * var1) / (Math.Pow(mu1, 2.0) * Math.Pow(mu2, 2.0));
            double sig1 = Math.Sqrt(var1);
            double sig2 = Math.Sqrt(var2);
            double sigd = Math.Sqrt(vard);
            double gamd = (Math.Pow(mu1, 3.0) * Math.Pow(sig2, 3.0) * gam2 - Math.Pow(mu2, 3.0) * Math.Pow(sig1, 3.0) * gam1) / (Math.Pow(mu1, 3.0) * Math.Pow(mu2, 3.0) * Math.Pow(sigd, 3.0));
            double t = dr / sigd;
            double p1 = Pgamt((mu1 - e1) / sig1, gam1);
            double p2 = Pgamt((mu2 - e2) / sig2, gam2);
            double pd = Pgamt(t, gamd);

            ParameterBag outputParameters = new();

            outputParameters.AddOutput("r1", r1);
            outputParameters.AddOutput("r2", r2);
            outputParameters.AddOutput("mu1", mu1);
            outputParameters.AddOutput("mu2", mu2);
            outputParameters.AddOutput("var1", var1);
            outputParameters.AddOutput("var2", var2);
            outputParameters.AddOutput("gam1", gam1);
            outputParameters.AddOutput("gam2", gam2);
            outputParameters.AddOutput("dr", dr);
            outputParameters.AddOutput("dm", dm);
            outputParameters.AddOutput("vard", vard);
            outputParameters.AddOutput("gamd", gamd);
            outputParameters.AddOutput("p1", p1);
            outputParameters.AddOutput("p2", p2);
            outputParameters.AddOutput("pd", pd * 2.0);
            return new StepOutput(outputParameters);
        }


        ///  <summary>
        ///  calculates the value for delta and the value for the coefficient of agreement, r.
        ///  exact values for the mean (edel), variance (var), and skewness (gam) of the delta distribution are computed.
        ///  </summary>
        ///  <param name="n">number of objects observed</param>
        ///  <param name="b">number of observers/judges</param>
        ///  <param name="c">number of dimensions/responses</param>
        ///  <param name="data">matrix (n,b,c) containing the raw score values</param>
        ///  <param name="delta">observed (realized) value of delta</param>
        ///  <param name="edel">expected (mean) value of delta</param>
        ///  <param name="var">variance of the delta distribution</param>
        ///  <param name="gam">skewness of the delta distribution</param>
        ///  <param name="r">delta-based agreement coefficient</param>
        ///  <param name="p">probability of agreement coefficient</param>
        public static void Agree(int n, int b, int c, double[,,] data, out double delta, out double edel, out double var, out double gam, out double r, out double p)
        {
            int i, j, k;
            int ix, ir, irr;
            int jss, iss;
            double[,] d = new double[n * b + 1, n * b + 1];
            double[,,] sj = new double[n + 1, b + 1, b + 1];
            double[,,] sj2 = new double[n + 1, b + 1, b + 1];
            double[,] vi = new double[b + 1, b + 1];
            double[,,] sj3 = new double[n + 1, b + 1, b + 1];
            double[,,] uj = new double[n + 1, b + 1, b + 1];
            double[,,] wi = new double[b + 1, b + 1, b + 1];
            double[,,] yij = new double[b + 1, b + 1, b + 1];
            double[,] uij = new double[b + 1, b + 1];
            double[,,] zijk = new double[b + 1, b + 1, b + 1];
            double[,] sij = new double[b + 1, b + 1];
            double[,] sij2 = new double[b + 1, b + 1];
            double[,] sij3 = new double[b + 1, b + 1];
            double[,] tij2 = new double[b + 1, b + 1];
            double[,] tij3 = new double[b + 1, b + 1];

            const double zero = 0.0;
            for (i = 1; i <= n; i++)
            {
                for (j = 1; j <= b; j++)
                {
                    for (k = i; k <= n; k++)
                    {
                        int lo = 1;
                        if (i == k)
                        {
                            lo = j;
                        }
                        int l;
                        for (l = lo; l <= b; l++)
                        {
                            int ij = b * (i - 1) + j;
                            int kl = b * (k - 1) + l;
                            d[ij, kl] = zero;
                            int m;
                            for (m = 1; m <= c; m++)
                            {
                                d[ij, kl] = d[ij, kl] + Math.Pow(data[i, j, m] - data[k, l, m], 2.0);
                            }
                            d[ij, kl] = Math.Pow(d[ij, kl], 0.5);
                            d[kl, ij] = d[ij, kl];
                        }
                    }
                }
            }
            for (ix = 1; ix <= b; ix++)
            {
                for (ir = 1; ir <= b; ir++)
                {
                    if (ir != ix)
                    {
                        sij[ir, ix] = zero;
                        sij2[ir, ix] = zero;
                        sij3[ir, ix] = zero;
                        for (i = 1; i <= n; i++)
                        {
                            sj[i, ir, ix] = zero;
                            sj2[i, ir, ix] = zero;
                            sj3[i, ir, ix] = zero;
                            for (j = 1; j <= n; j++)
                            {
                                irr = (i - 1) * b + ir;
                                jss = (j - 1) * b + ix;
                                sj[i, ir, ix] = sj[i, ir, ix] + d[irr, jss];
                                sj2[i, ir, ix] = sj2[i, ir, ix] + Math.Pow(d[irr, jss], 2.0);
                                sj3[i, ir, ix] = sj3[i, ir, ix] + Math.Pow(d[irr, jss], 3.0);
                            }
                            sij[ir, ix] = sij[ir, ix] + sj[i, ir, ix];
                            sij2[ir, ix] = sij2[ir, ix] + sj2[i, ir, ix];
                            sij3[ir, ix] = sij3[ir, ix] + sj3[i, ir, ix];
                        }
                    }
                }
            }
            double t2 = zero;
            if (b > 2)
            {
                int it;
                for (it = 3; it <= b; it++)
                {
                    for (ix = 2; ix < it; ix++)
                    {
                        for (ir = 1; ir < ix; ir++)
                        {
                            wi[ir, ix, it] = zero;
                            wi[ix, ir, it] = zero;
                            wi[it, ir, ix] = zero;
                            yij[ir, ix, it] = zero;
                            zijk[ir, ix, it] = zero;
                            for (i = 1; i <= n; i++)
                            {
                                wi[ir, ix, it] = wi[ir, ix, it] + sj[i, ir, ix] * sj[i, ir, it];
                                wi[ix, ir, it] = wi[ix, ir, it] + sj[i, ix, ir] * sj[i, ix, it];
                                wi[it, ir, ix] = wi[it, ir, ix] + sj[i, it, ir] * sj[i, it, ix];
                                for (j = 1; j <= n; j++)
                                {
                                    irr = b * (i - 1) + ir;
                                    jss = b * (j - 1) + ix;
                                    int jtt = b * (j - 1) + it;
                                    iss = b * (i - 1) + ix;
                                    yij[ir, ix, it] = yij[ir, ix, it] + d[irr, jss] * sj[i, ir, it] * sj[j, ix, it] + d[irr, jtt] * sj[i, ir, ix] * sj[j, it, ix] + d[iss, jtt] * sj[i, ix, ir] * sj[j, it, ir];
                                    for (k = 1; k <= n; k++)
                                    {
                                        int ktt = (k - 1) * b + it;
                                        zijk[ir, ix, it] = zijk[ir, ix, it] + d[irr, jss] * d[irr, ktt] * d[jss, ktt];
                                    }
                                }
                            }
                            t2 = t2 + sij[ir, ix] * sij[ir, it] * sij[ix, it] - sij[ix, it] * wi[ir, ix, it] * n - sij[ir, it] * wi[ix, ir, it] * n - sij[ir, ix] * wi[it, ir, ix] * n + yij[ir, ix, it] * n * n - zijk[ir, ix, it] * n * n * n;
                        }
                    }
                }
                t2 = 6.0 * t2 / (n - 1);
            }
            for (ix = 2; ix <= b; ix++)
            {
                for (ir = 1; ir < ix; ir++)
                {
                    tij2[ir, ix] = zero;
                    tij3[ir, ix] = zero;
                    vi[ir, ix] = zero;
                    uij[ir, ix] = zero;
                    for (i = 1; i <= n; i++)
                    {
                        tij2[ir, ix] = tij2[ir, ix] + Math.Pow(sj[i, ir, ix], 2.0) + Math.Pow(sj[i, ix, ir], 2.0);
                        tij3[ir, ix] = tij3[ir, ix] + Math.Pow(sj[i, ir, ix], 3.0) + Math.Pow(sj[i, ix, ir], 3.0);
                        vi[ir, ix] = vi[ir, ix] + sj[i, ir, ix] * sj2[i, ir, ix] + sj[i, ix, ir] * sj2[i, ix, ir];
                        uj[i, ir, ix] = zero;
                        for (j = 1; j <= n; j++)
                        {
                            irr = b * (i - 1) + ir;
                            jss = b * (j - 1) + ix;
                            uj[i, ir, ix] = uj[i, ir, ix] + d[irr, jss] * sj[i, ir, ix] * sj[j, ix, ir];
                        }
                        uij[ir, ix] = uij[ir, ix] + uj[i, ir, ix];
                    }
                }
            }
            edel = zero;
            var = zero;
            double t1 = zero;
            for (ix = 2; ix <= b; ix++)
            {
                for (ir = 1; ir < ix; ir++)
                {
                    if (n > 2)
                        t1 = t1 + 4.0 * Math.Pow(sij[ir, ix], 3.0) - sij[ir, ix] * tij2[ir, ix] * 6.0 * n + uij[ir, ix] * 6.0 * n * n + tij3[ir, ix] * 2.0 * n * n + sij[ir, ix] * sij2[ir, ix] * 3.0 * n * n - vi[ir, ix] * 3.0 * n * n * n + sij3[ir, ix] * Math.Pow(n, 4.0);
                    edel += sij[ir, ix];
                    var = var + sij[ir, ix] * sij[ir, ix] - tij2[ir, ix] * n + sij2[ir, ix] * n * n;
                }
            }
            if (n > 2)
            {
                t1 /= (n - 2);
            }
            double fac = n * b * (b - 1) / 2.0;
            double con = 1.0 / (fac * n);
            var = var * con * con / (n - 1);
            gam = Math.Pow(con, 3.0) * (t1 - t2) / (n - 1) / Math.Sqrt(Math.Pow(var, 3.0));
            edel = con * edel;
            delta = zero;
            for (ix = 2; ix <= b; ix++)
            {
                for (ir = 1; ir < ix; ir++)
                {
                    for (i = 1; i <= n; i++)
                    {
                        irr = (i - 1) * b + ir;
                        iss = (i - 1) * b + ix;
                        delta += d[irr, iss];
                    }
                }
            }
            delta /= fac;
            double t = (delta - edel) / Math.Sqrt(var);
            p = Pgamt(t, gam);
            r = 1.0 - delta / edel;
        }


        ///  <summary>
        ///  Calculates the probability of a value of t being less than or equal to the observed value of t.
        ///  </summary>
        ///  <param name="t">standardized test statistic</param>
        ///  <param name="gam">skewness of the delta distribution</param>
        ///  <return>probability of the test statistic</return>
        private static double Pgamt(double t, double gam)
        {
            double w;

            const double zero = 0.0;
            double pi = 4.0 * Math.Atan(1.0);
            if (Math.Abs(gam) >= 0.01)
            {

                double r = 2.0 / Math.Abs(gam);
                double d = r * r;
                for (int i = 1; i <= 9; i++)
                    d *= (r * r + i);
                double f = r * r + 10.0;
                double u = (2.0 * f - 1.0) * Math.Log(f) / 2.0 - f + Math.Log(2.0 * pi) / 2.0 - Math.Log(d) + 1.0 / (12.0 * f) - 1.0 / (360.0 * f * f * f);
                const double g1 = 0.045;
                const double g2 = 0.09;
                const double g3 = 0.015;
                double h1 = zero;
                double h2 = zero;
                double a = r * r - 1.0;
                double b = r * r * (Math.Log(r) - 1.0) - u;
                w = -1.99 / gam;
                double y;
                double h0;
                double h3;
                double h4;
                double x;
                if (gam >= zero)
                {

                    if (t < w)
                        return zero;
                    x = t;
                    y = t + 9.0;
                    for (int i = 1; i <= 99; i++)
                    {
                        h1 += Math.Exp(a * Math.Log(r + x + g1 * (2.0 * i - 1.0)) - r * (x + g1 * (2.0 * i - 1.0)) + b);
                        h2 += Math.Exp(a * Math.Log(r + x + g2 * i) - r * (x + g2 * i) + b);
                    }
                    h0 = Math.Exp(a * Math.Log(r + x) - r * x + b);
                    h3 = Math.Exp(a * Math.Log(r + y) - r * y + b);
                    h4 = Math.Exp(a * Math.Log(r + x + g1 * 199.0) - r * (x + g1 * 199.0) + b);
                    return 1.0 - g3 * (h0 + (h1 + h4) * 4.0 + 2.0 * h2 + h3);

                }

                if (t > w)
                    return 1.0;
                x = t - 9.0;
                y = t;
                for (int i = 1; i <= 99; i++)
                {
                    h1 += Math.Exp(a * Math.Log(r - x - g1 * (2.0 * i - 1.0)) + r * (x + g1 * (2.0 * i - 1.0)) + b);
                    h2 += Math.Exp(a * Math.Log(r - x - g2 * i) + r * (x + g2 * i) + b);
                }
                h0 = Math.Exp(a * Math.Log(r - x) + r * x + b);
                h3 = Math.Exp(a * Math.Log(r - y) + r * y + b);
                h4 = Math.Exp(a * Math.Log(r - x - g1 * 199.0) + r * (x + g1 * 199.0) + b);
                return g3 * (h0 + (h1 + h4) * 4.0 + 2.0 * h2 + h3);
            }

            const double e1 = 0.31938153;
            const double e2 = -0.356563782;
            const double e3 = 1.781477937;
            const double e4 = -1.821255978;
            const double e5 = 1.330274429;
            const double h = 0.2316419;
            w = 1.0 / (h * Math.Abs(t) + 1.0);
            double prob = ((((e5 * w + e4) * w + e3) * w + e2) * w + e1) * w * Math.Exp(-t * t / 2.0) / Math.Sqrt(pi * 2.0);
            if (t > zero)
                prob = 1.0 - prob;
            return prob;
        }

        ///  <summary>
        ///  multivariate measure of agreement between a set of raters and a standdard (or correct set) of responses.
        ///  </summary>
        ///  <param name="kn">number of objects observed</param>
        ///  <param name="km">number of observers/judges</param>
        ///  <param name="kr">number of dimensions/responses</param>
        ///  <param name="tdata">matrix (n,b,c) containing the raw score values</param>
        ///  <param name="delta">observed (realized) value of delta</param>
        ///  <param name="edel">expected (mean) value of delta</param>
        ///  <param name="var">variance of the delta distribution</param>
        ///  <param name="gam">skewness of the delta distribution</param>
        ///  <param name="rho">delta-based agreement coefficient</param>
        ///  <param name="prob">probability of agreement coefficient</param>
        private static void AgreeStandard(int kn, int km, int kr, double[,,] tdata, out double delta, out double edel, out double var, out double gam, out double rho, out double prob)
        {
            double[] c1 = new double[km + 1];
            double[] c2 = new double[km + 1];
            double[] c3 = new double[km + 1];
            double[,] d = new double[2 * kn + 1, 2 * kn + 1];
            double[,,] data = new double[kn + 1, 3, kr + 1];
            double[] del = new double[km + 1];
            double[,,] sj1 = new double[kn + 1, 3, 3];
            double[,,] sj2 = new double[kn + 1, 3, 3];
            double[,,] sj3 = new double[kn + 1, 3, 3];
            double[,,] uj = new double[kn + 1, 3, 3];

            for (int i = 1; i <= kn; i++)
                for (int j = 1; j <= kr; j++)
                    data[i, 1, j] = tdata[i, 1, j];
            for (int i = 2; i <= km; i++)
            {
                for (int j = 1; j <= kn; j++)
                    for (int k = 1; k <= kr; k++)
                        data[j, 2, k] = tdata[j, i, k];

                AgreeStdCalc(kn, kr, d, data, sj1, sj2, sj3, uj, out double cum1, out double cum2, out double cum3, out delta);

                del[i] = delta;
                c1[i] = cum1;
                c2[i] = cum2;
                c3[i] = cum3;
            }
            delta = 0.0;
            double c11 = 0.0;
            double c22 = 0.0;
            double c33 = 0.0;
            for (int i = 2; i <= km; i++)
            {
                delta += del[i];
                c11 += c1[i];
                c22 += c2[i];
                c33 += c3[i];
            }
            edel = c11;
            var = c22;
            gam = c33 / Math.Sqrt(Math.Pow(var, 3.0));
            double t = (delta - edel) / Math.Sqrt(var);
            rho = 1.0 - delta / edel;

            prob = Pgamt(t, gam);
        }

        private static void AgreeStdCalc(int kn, int kr, double[,] d, double[,,] data, double[,,] sj1, double[,,] sj2, double[,,] sj3, double[,,] uj, out double cum1, out double cum2, out double cum3, out double delta)
        {
            int i;
            int irr, ix, j, jss;
            double[,] sij1 = new double[3, 3];
            double[,] sij2 = new double[3, 3];
            double[,] sij3 = new double[3, 3];
            double[,] tij2 = new double[3, 3];
            double[,] tij3 = new double[3, 3];
            double[,] uij = new double[3, 3];
            double[,] vi = new double[3, 3];

            for (i = 1; i <= 2 * kn; i++)
                for (j = 1; j <= 2 * kn; j++)
                    d[i, j] = 0.0;
            for (i = 1; i <= kn; i++)
            {
                for (j = 1; j <= 2; j++)
                {
                    int k;
                    for (k = i; k <= kn; k++)
                    {
                        int lo = 1;
                        if (i == k)
                            lo = j;
                        int l;
                        for (l = lo; l <= 2; l++)
                        {
                            int ij = 2 * (i - 1) + j;
                            int kl = 2 * (k - 1) + l;
                            d[ij, kl] = 0.0;
                            int m;
                            for (m = 1; m <= kr; m++)
                                d[ij, kl] = d[ij, kl] + Math.Pow(data[i, j, m] - data[k, l, m], 2.0);
                            d[ij, kl] = Math.Pow(d[ij, kl], 0.5);
                            d[kl, ij] = d[ij, kl];
                        }
                    }
                }
            }
            for (ix = 1; ix <= 2; ix++)
            {
                int ir;
                for (ir = 1; ir <= 2; ir++)
                {
                    if (ir != ix)
                    {
                        sij1[ir, ix] = 0.0;
                        sij2[ir, ix] = 0.0;
                        sij3[ir, ix] = 0.0;
                        for (i = 1; i <= kn; i++)
                        {
                            sj1[i, ir, ix] = 0.0;
                            sj2[i, ir, ix] = 0.0;
                            sj3[i, ir, ix] = 0.0;
                            for (j = 1; j <= kn; j++)
                            {
                                irr = (i - 1) * 2 + ir;
                                jss = (j - 1) * 2 + ix;
                                sj1[i, ir, ix] = sj1[i, ir, ix] + d[irr, jss];
                                sj2[i, ir, ix] = sj2[i, ir, ix] + Math.Pow(d[irr, jss], 2.0);
                                sj3[i, ir, ix] = sj3[i, ir, ix] + Math.Pow(d[irr, jss], 3.0);
                            }
                            sij1[ir, ix] = sij1[ir, ix] + sj1[i, ir, ix];
                            sij2[ir, ix] = sij2[ir, ix] + sj2[i, ir, ix];
                            sij3[ir, ix] = sij3[ir, ix] + sj3[i, ir, ix];
                        }
                    }
                }
            }
            const double t2 = 0.0;
            tij2[1, 2] = 0.0;
            tij3[1, 2] = 0.0;
            vi[1, 2] = 0.0;
            uij[1, 2] = 0.0;
            for (i = 1; i <= kn; i++)
            {
                tij2[1, 2] = tij2[1, 2] + Math.Pow(sj1[i, 1, 2], 2.0) + Math.Pow(sj1[i, 2, 1], 2.0);
                tij3[1, 2] = tij3[1, 2] + Math.Pow(sj1[i, 1, 2], 3.0) + Math.Pow(sj1[i, 2, 1], 3.0);
                vi[1, 2] = vi[1, 2] + sj1[i, 1, 2] * sj2[i, 1, 2] + sj1[i, 2, 1] * sj2[i, 2, 1];
                uj[i, 1, 2] = 0.0;
                for (j = 1; j <= kn; j++)
                {
                    irr = 2 * (i - 1) + 1;
                    jss = 2 * (j - 1) + 2;
                    uj[i, 1, 2] = uj[i, 1, 2] + d[irr, jss] * sj1[i, 1, 2] * sj1[j, 2, 1];
                }
                uij[1, 2] = uij[1, 2] + uj[i, 1, 2];
            }
            double t1 = 0.0;
            if (kn > 2)
            {
                t1 = t1 + 4.0 * Math.Pow(sij1[1, 2], 3.0) - sij1[1, 2] * tij2[1, 2] * 6.0 * kn + uij[1, 2] * 6.0 * kn * kn + tij3[1, 2] * 2.0 * kn * kn + sij1[1, 2] * sij2[1, 2] * 3.0 * kn * kn - vi[1, 2] * 3.0 * kn * kn * kn + sij3[1, 2] * Math.Pow(kn, 4.0);
                t1 /= Convert.ToDouble(kn - 2);
            }
            double c1 = 1.0 / Convert.ToDouble(kn * kn);
            double c2 = c1 * c1;
            double c3 = c2 * c1;
            cum1 = c1 * sij1[1, 2];
            cum2 = (sij1[1, 2] * sij1[1, 2] - tij2[1, 2] * kn + sij2[1, 2] * kn * kn) * c2 / Convert.ToDouble(kn - 1);
            cum3 = c3 * (t1 - t2) / Convert.ToDouble(kn - 1);
            delta = 0.0;
            for (i = 1; i <= kn; i++)
            {
                irr = (i - 1) * 2 + 1;
                int iss = (i - 1) * 2 + 2;
                delta += d[irr, iss];
            }
            delta /= Convert.ToDouble(kn);
        }

        public static StepOutput RptUniversalAgreementSimulateExactP(IProgressBarHost host, ParameterBag parameters)
        {
            int nobs = 0;
            string title = null;
            string refIdent = null;
            GatherUniversalAgreementData(parameters, out int n, out int b, out int c, out double[,,] data, out bool _, ref nobs, ref title, ref refIdent);

            // Agree(n, b, c, data, out double delta, out double edel, out double var, out double gam, out double r, out double t);
            // double prob = Pgamt(t, gam);

            int iterations = parameters["iterations"].AsInt32;
            double ci = parameters["ci"].AsDouble;
            int seed = parameters["seed"].AsInt32;

            Rmrbp(host, 1.0, n, b, c, 0, 0, 0, data, 0, seed, iterations, out int ir, out int mpd);
            ParameterBag outputParameters = new();
            double p = Convert.ToDouble(ir) / Convert.ToDouble(mpd);
            outputParameters.AddOutput("p", p);
            //  CI
            MathDbl.binci(Convert.ToDouble(ir), Convert.ToDouble(mpd), out double ll, out double ul, ci, out string warn);
            outputParameters.AddOutput("pc", 100.0 * ci);
            outputParameters.AddOutput("ll", ll);
            outputParameters.AddOutput("ul", ul);
            outputParameters.AddOutput("warn", warn);
            outputParameters.AddOutput("k", mpd);
            return new StepOutput(outputParameters);
        }

        private static void Rmrbp(IProgressBarHost host, double v, int kg, int kb, int kr, int ia, int ic, int lr, double[,,] data, int h, int iseed, int ms, out int mp, out int mpd)
        {

            //          THIS FORTRAN PROGRAM COMPUTES THE TEST STATISTIC AND ASSOCIATED
            //          P-VALUE FOR AN ANALYSIS OF A RANDOMIZED BLOCK EXPERIMENT (MRBP3).
            //          THE CORRESPONDENCE BETWEEN A CORRELATION ANALYSIS AND A
            //          RANDOMIZED BLOCK EXPERIMENT CAN BE USED TO GET A CORRELATION
            //          COEFFICIENT AS WELL. THE MAXIMUM VALUES OF G, B AND R CAN BE
            //          CHANGED FOR ANY EXAMPLE.  THE PRESENT MAXIMUM VALUES OF G, B
            //          AND R IN THIS PROGRAM ARE RESPECTIVELY 10, 12 AND 15.

            //        THIS PROGRAM IS CAPABLE OF PERFORMING (1) REPEATED MRBP ANALYSES
            //        IN 1.0 OPERATION, (2) ALIGNMENT WITHIN BLOCKS, (3) DISTANCE
            //        FUNCTION COMMENSURATION, AND (4) C(G,H) RANKS TEST.

            //          PROGRAM MODIFIED 2/8/2003

            //        THE DATA MATRIX MUST BE IN THE FOLLOWING SEQUENCE WITH EACH
            //        OBJECT'S R RESPONSE VALUES ON A SEPARATE LINE AS FOLLOWS:

            //          A(1,1,1),A(1,1,2),...,A(1,1,R)
            //          A(1,2,1),A(1,2,2),...,A(1,2,R)
            //           ...
            //          A(1,B,1),A(1,B,2),...,A(1,B,R)
            //          A(2,1,1),A(2,1,2),...,A(2,1,R)
            //           ...
            //          A(2,B,1),A(2,B,2),...,A(2,B,R)
            //           ...
            //          A(G,1,1),A(G,1,2),...,A(G,1,R)
            //           ...
            //          A(G,B,1),A(G,B,2),...,A(G,B,R)

            //    THE INPUT DATA ARE IN FREE FORMAT.  SPECIFICALLY, V IS DISTANCE EXP1.0NT,
            //    G IS # OF GROUPS, B IS # OF BLOCKS, R IS # OF RESPONSES, IA = 1 IMPLIES
            //    ALIGNMENT, IC = 1 IMPLIES COMMENSURATION, AND LR = 1 IMPLIES C(G,H)
            //    RANKS TEST.   NOTE: ASSOCIATE G, B AND R WITH KG, KB AND KR IN PROGRAM.

            double[] ad = new double[kr + 1];
            double[,] xm = new double[kb + 1, kr + 1];
            double[,,] x = new double[kg + 1, kb + 1, kr + 1];
            double dm1 = 0;
            double dm2 = 0;
            double a2 = 0;

            if (lr == 1)
            {
                // ia = 0; Redundant assignment PJC 2012/04/09
                // ic = 0; Redundant assignment PJC 2012/04/09 
                Rank(kg, kb, kr, h, ref data);
            }
            else
            {

                if (ia != 0)
                {
                    for (int i = 1; i <= kg; i++)
                        for (int j = 1; j <= kb; j++)
                            for (int k = 1; k <= kr; k++)
                                x[i, j, k] = data[i, j, k];
                    for (int j = 1; j <= kb; j++)
                    {
                        for (int k = 1; k <= kr; k++)
                        {
                            double a1 = 1.0E+200;
                            double sum1 = a1;
                            for (int i1 = 1; i1 <= kg; i1++)
                            {
                                double sum = 0.0;
                                for (int i2 = 1; i2 <= kg; i2++)
                                    sum += Math.Abs(data[i2, j, k] - x[i1, j, k]);
                                if (sum < a1)
                                {
                                    dm1 = x[i1, j, k];
                                    a1 = sum;
                                    a2 = a1 * 1.0000000001;
                                }
                                if (sum < a2 & dm1 != x[i1, j, k])
                                {
                                    dm2 = x[i1, j, k];
                                    sum1 = sum;
                                }
                            }
                            if (sum1 > a2)
                                dm2 = dm1;
                            xm[j, k] = (dm1 + dm2) / 2.0;
                        }
                    }
                    for (int i = 1; i <= kg; i++)
                        for (int j = 1; j <= kb; j++)
                            for (int k = 1; k <= kr; k++)
                                data[i, j, k] = data[i, j, k] - xm[j, k];
                }
                if (ic != 0 & kr != 1)
                {
                    for (int k = 1; k <= kr; k++)
                    {
                        ad[k] = 0.0;
                        for (int i1 = 1; i1 <= kg; i1++)
                            for (int i2 = 1; i2 <= kg; i2++)
                                for (int j1 = 2; j1 <= kb; j1++)
                                    for (int j2 = 1; j2 < j1; j2++)
                                        ad[k] += Math.Pow(Math.Abs(data[i1, j1, k] - data[i2, j2, k]), v);
                        ad[k] = Math.Pow(ad[k], 1.0 / v);
                    }
                    for (int i = 1; i <= kg; i++)
                        for (int j = 1; j <= kb; j++)
                            for (int k = 1; k <= kr; k++)
                                data[i, j, k] = data[i, j, k] / ad[k];
                }

            }
            Calc(host, v, kg, kb, kr, iseed, ms, data, out mp, out mpd);
        }

        private static void Rank(int kg, int kb, int kr, int h, ref double[,,] data)
        {

            double[] rks = new double[kg + 1];

            double ym = 1.0 * (kg + 1) / 2;
            for (int j = 1; j <= kb; j++)
            {
                for (int k = 1; k <= kr; k++)
                {
                    double cl = 1.0E+30;
                    for (int i = 1; i <= kg; i++)
                        if (data[i, j, k] < cl)
                            cl = data[i, j, k];
                    for (int i = 1; i <= kg; i++)
                        data[i, j, k] = data[i, j, k] - cl + 1.0;
                    const double phi = 1.0 + 0.000000000001;
                    double a1 = 0.0;
                    double a2 = 0.0;
                    double a3 = 1.0 * kg - 0.1;
                    double b1 = 0.0 - 1.0E+30;
                    double b2 = 1.0E+30;
                    while (a2 <= a3)
                    {
                        for (int i = 1; i <= kg; i++)
                            if (data[i, j, k] > b1 & data[i, j, k] < b2)
                                b2 = data[i, j, k] * phi;
                        for (int i = 1; i <= kg; i++)
                        {
                            double w = Math.Abs(1.0 - data[i, j, k] / b2);
                            if (w < 0.00000000001)
                                a1 += 1;
                        }
                        double a4 = a2 + (a1 + 1) / 2;
                        for (int i = 1; i <= kg; i++)
                        {
                            double w = Math.Abs(1.0 - data[i, j, k] / b2);
                            if (w < 0.00000000001)
                                rks[i] = a4;
                        }
                        a2 += a1;
                        a1 = 0.0;
                        b1 = b2;
                        b2 = 1.0E+30;
                    }
                    for (int i = 1; i <= kg; i++)
                    {
                        double w = Math.Abs(rks[i] - ym);
                        if (w < 0.001)
                            data[i, j, k] = 0.0;
                        else
                            data[i, j, k] = (rks[i] - ym) * Math.Pow(Math.Abs(rks[i] - ym), h - 1);
                    }
                }
            }
        }


        private static void Calc(IProgressBarHost host, double v, int kg, int kb, int kr, int iseed, int ms, double[,,] data, out int mp, out int mpd)
        {

            double[,] d = new double[kb * (kg - 1) + kb + 1, kb * (kg - 1) + kb + 1];
            // double[,] dt = new double[kg + 1, kr + 1]; Array never referenced.  PJC 2012/04/09.
            int lo, l, ij, kl, is0, is1, irr, iss, i, j, k, iw, m;
            MersenneTwister rng = new();
            int trigger = Convert.ToInt32(ms / 1000) + 1;

            if (iseed != 0)
                rng.Seed(iseed);
            else
                rng.Seed();

            double y = v / 2.0;
            double bc2 = 1.0 * kb * (kb - 1) / 2.0;
            int kbg = kb * kg;
            for (i = 1; i <= kbg; i++)
                for (j = 1; j <= kbg; j++)
                    d[i, j] = 0.0;
            for (i = 1; i <= kg; i++)
            {
                for (j = 1; j <= kb; j++)
                {
                    for (k = i; k <= kg; k++)
                    {
                        lo = 1;
                        if (i == k)
                            lo = j;
                        for (l = lo; l <= kb; l++)
                        {
                            ij = kb * (i - 1) + j;
                            kl = kb * (k - 1) + l;
                            d[ij, kl] = 0.0;
                            for (m = 1; m <= kr; m++)
                                d[ij, kl] = d[ij, kl] + Math.Pow(data[i, j, m] - data[k, l, m], 2.0);
                            d[ij, kl] = Math.Pow(d[ij, kl], y);
                            d[kl, ij] = d[ij, kl];
                        }
                    }
                }
            }
            double delta = 0.0;
            for (is0 = 2; is0 <= kb; is0++)
            {
                is1 = is0 - 1;
                for (int ir = 1; ir <= is1; ir++)
                {
                    for (i = 1; i <= kg; i++)
                    {
                        irr = (i - 1) * kb + ir;
                        iss = (i - 1) * kb + is0;
                        delta += d[irr, iss];
                    }
                }
            }
            double c0 = bc2 * kg;
            delta /= c0;
            double dx = delta * 1.000000000001;
            mp = 0;

            using IProgressBar progress = host.StartProgress("Simulating exact P", true);
            int ctr = 0;

            mpd = ms;
            for (iw = 1; iw <= ms; iw++)
            {
                for (j = 2; j <= kb; j++)
                {
                    for (i = 1; i <= kg; i++)
                    {
                        int ix = rng.NextInteger(1, kg);
                        for (k = 1; k <= kr; k++)
                        {
                            double tmp = data[i, j, k];
                            data[i, j, k] = data[ix, j, k];
                            data[ix, j, k] = tmp;
                        }
                    }
                }
                for (i = 1; i <= kbg; i++)
                    for (j = 1; j <= kbg; j++)
                        d[i, j] = 0.0;
                for (i = 1; i <= kg; i++)
                {
                    for (j = 1; j <= kb; j++)
                    {
                        for (k = i; k <= kg; k++)
                        {
                            lo = 1;
                            if (i == k)
                                lo = j;
                            for (l = lo; l <= kb; l++)
                            {
                                ij = kb * (i - 1) + j;
                                kl = kb * (k - 1) + l;
                                d[ij, kl] = 0.0;
                                for (m = 1; m <= kr; m++)
                                    d[ij, kl] = d[ij, kl] + Math.Pow(data[i, j, m] - data[k, l, m], 2.0);
                                d[ij, kl] = Math.Pow(d[ij, kl], y);
                                d[kl, ij] = d[ij, kl];
                            }
                        }
                    }
                }
                double dz = 0.0;
                for (is0 = 2; is0 <= kb; is0++)
                {
                    is1 = is0 - 1;
                    for (int ir = 1; ir <= is1; ir++)
                    {
                        for (i = 1; i <= kg; i++)
                        {
                            irr = (i - 1) * kb + ir;
                            iss = (i - 1) * kb + is0;
                            dz += d[irr, iss];
                        }
                    }
                }
                dz /= c0;
                if (dz < dx)
                    mp += 1;

                ctr += 1;
                if (ctr > trigger)
                {
                    bool bailout = progress.Update(Convert.ToDouble(iw) / Convert.ToDouble(ms));
                    ctr = 0;
                    if (bailout)
                    {
                        mpd = iw;
                        break;
                    }
                }

            }
        }
    }
}
