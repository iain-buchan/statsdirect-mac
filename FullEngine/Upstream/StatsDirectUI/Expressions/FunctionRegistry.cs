using System.Collections.Generic;

namespace StatsDirect.Expressions
{
    /// <remarks>Singleton.</remarks>
    public class FunctionRegistry
    {
        private readonly Dictionary<string, FunctionDefinition> functionDefinitions;

        private static FunctionRegistry soleInstance;

        public static FunctionRegistry SoleInstance => soleInstance ?? (soleInstance = new FunctionRegistry());

        private FunctionRegistry()
        {
            // A few useful parameters that can be re-used
            ArgumentDefinition df = new("df", DataType.Double);
            ArgumentDefinition df1 = new("df1", DataType.Double);
            ArgumentDefinition df2 = new("df2", DataType.Double);
            ArgumentDefinition dfd = new("dfd", DataType.Double);
            ArgumentDefinition dfn = new("dfn", DataType.Double);
            ArgumentDefinition k = new("k", DataType.Double);
            ArgumentDefinition logDefFalse = new("log", DataType.Boolean, false, "false");
            ArgumentDefinition mean = new("mean", DataType.Double);
            ArgumentDefinition meanDef0 = new("mean", DataType.Double, false, "0");
            ArgumentDefinition n = new("n", DataType.Double);
            ArgumentDefinition ncpDefMissing = new("ncp", DataType.Double, false, "StatsDirect.Numerics.Constant.MISSING");
            ArgumentDefinition p = new("p", DataType.Double);
            ArgumentDefinition q = new("q", DataType.Double);
            ArgumentDefinition r = new("r", DataType.Double);
            ArgumentDefinition sdDef1 = new("sd", DataType.Double, false, "1");
            ArgumentDefinition x = new("x", DataType.Double);
            ArgumentDefinition logP = new("log.p", DataType.Boolean, true, "false");
            ArgumentDefinition lowerTail = new("lower.tail", DataType.Boolean, true, "true");

            ArgumentDefinition[] xOnly = new[] { x };

            functionDefinitions = new Dictionary<string, FunctionDefinition>();
            AddAll(new[]
            {
                new FunctionDefinition("ABS",                DataType.Double, "Math.Abs",            xOnly),
                new FunctionDefinition("ALOGIT",             DataType.Double, "SDMath.Alogit",       xOnly),

                new FunctionDefinition("ACOS",               DataType.Double, "Math.Acos",           xOnly),
                new FunctionDefinition("ACOSINE",            DataType.Double, "Math.Acos",           xOnly),
                new FunctionDefinition("ACOSH",              DataType.Double, "SDMath.Acosh",        xOnly),
                new FunctionDefinition("ACOSINEH",           DataType.Double, "SDMath.Acosh",        xOnly),
                new FunctionDefinition("HYPERBOLICACOS",     DataType.Double, "SDMath.Acosh",        xOnly),
                new FunctionDefinition("HYPERBOLICACOSINE",  DataType.Double, "SDMath.Acosh",        xOnly),
                new FunctionDefinition("ACOT",               DataType.Double, "SDMath.Acot",         xOnly),
                new FunctionDefinition("ACOTAN",             DataType.Double, "SDMath.Acot",         xOnly),
                new FunctionDefinition("ACOTANGENT",         DataType.Double, "SDMath.Acot",         xOnly),
                new FunctionDefinition("ACOTH",              DataType.Double, "SDMath.Acoth",        xOnly),
                new FunctionDefinition("ACOTANGENTH",        DataType.Double, "SDMath.Acoth",        xOnly),
                new FunctionDefinition("HYPERBOLICACOT",     DataType.Double, "SDMath.Acoth",        xOnly),
                new FunctionDefinition("HYPERBOLICACOTANGENT", DataType.Double, "SDMath.Acoth",      xOnly),
                new FunctionDefinition("ACSC",               DataType.Double, "SDMath.Acsc",         xOnly),
                new FunctionDefinition("ACOSEC",             DataType.Double, "SDMath.Acsc",         xOnly),
                new FunctionDefinition("ACOSECANT",          DataType.Double, "SDMath.Acsc",         xOnly),
                new FunctionDefinition("ACSCH",              DataType.Double, "SDMath.Acsch",        xOnly),
                new FunctionDefinition("ACOSECH",            DataType.Double, "SDMath.Acsch",        xOnly),
                new FunctionDefinition("ACOSECANTH",         DataType.Double, "SDMath.Acsch",        xOnly),
                new FunctionDefinition("HYPERBOLICACSC",     DataType.Double, "SDMath.Acsch",        xOnly),
                new FunctionDefinition("HYPERBOLICACOSEC",   DataType.Double, "SDMath.Acsch",        xOnly),
                new FunctionDefinition("HYPERBOLICACOSECANT",DataType.Double, "SDMath.Acsch",        xOnly),
                new FunctionDefinition("ASEC",               DataType.Double, "SDMath.Asec",         xOnly),
                new FunctionDefinition("ASECANT",            DataType.Double, "SDMath.Asec",         xOnly),
                new FunctionDefinition("ASECH",              DataType.Double, "SDMath.Asech",        xOnly),
                new FunctionDefinition("ASECANTH",           DataType.Double, "SDMath.Asech",        xOnly),
                new FunctionDefinition("HYPERBOLICASEC",     DataType.Double, "SDMath.Asech",        xOnly),
                new FunctionDefinition("HYPERBOLICASECANT",  DataType.Double, "SDMath.Asech",        xOnly),
                new FunctionDefinition("ASIN",               DataType.Double, "Math.Asin",           xOnly),
                new FunctionDefinition("ASINE",              DataType.Double, "Math.Asin",           xOnly),
                new FunctionDefinition("ASINH",              DataType.Double, "SDMath.Asinh",        xOnly),
                new FunctionDefinition("ASINEH",             DataType.Double, "SDMath.Asinh",        xOnly),
                new FunctionDefinition("HYPERBOLICASIN",     DataType.Double, "SDMath.Asinh",        xOnly),
                new FunctionDefinition("HYPERBOLICASINE",    DataType.Double, "SDMath.Asinh",        xOnly),
                new FunctionDefinition("ATAN",               DataType.Double, "Math.Atan",           xOnly),
                new FunctionDefinition("ATANGENT",           DataType.Double, "Math.Atan",           xOnly),
                new FunctionDefinition("ATANH",              DataType.Double, "SDMath.Atanh",        xOnly),
                new FunctionDefinition("ATANGENTH",          DataType.Double, "SDMath.Atanh",        xOnly),
                new FunctionDefinition("HYPERBOLICATAN",     DataType.Double, "SDMath.Atanh",        xOnly),
                new FunctionDefinition("HYPERBOLICATANGENT", DataType.Double, "SDMath.Atanh",        xOnly),

                new FunctionDefinition("ARCCOS",             DataType.Double, "Math.Acos",           xOnly),
                new FunctionDefinition("ARCCOSINE",          DataType.Double, "Math.Acos",           xOnly),
                new FunctionDefinition("ARCCOSH",            DataType.Double, "SDMath.Acosh",        xOnly),
                new FunctionDefinition("ARCCOSINEH",         DataType.Double, "SDMath.Acosh",        xOnly),
                new FunctionDefinition("HYPERBOLICARCCOS",   DataType.Double, "SDMath.Acosh",        xOnly),
                new FunctionDefinition("HYPERBOLICARCCOSINE",DataType.Double, "SDMath.Acosh",        xOnly),
                new FunctionDefinition("ARCCOT",             DataType.Double, "SDMath.Acot",         xOnly),
                new FunctionDefinition("ARCCOTAN",           DataType.Double, "SDMath.Acot",         xOnly),
                new FunctionDefinition("ARCCOTANGENT",       DataType.Double, "SDMath.Acot",         xOnly),
                new FunctionDefinition("ARCCOTH",            DataType.Double, "SDMath.Acoth",        xOnly),
                new FunctionDefinition("ARCCOTANGENTH",      DataType.Double, "SDMath.Acoth",        xOnly),
                new FunctionDefinition("HYPERBOLICARCCOT",   DataType.Double, "SDMath.Acoth",        xOnly),
                new FunctionDefinition("HYPERBOLICARCCOTANGENT", DataType.Double, "SDMath.Acoth",    xOnly),
                new FunctionDefinition("ARCCSC",             DataType.Double, "SDMath.Acsc",         xOnly),
                new FunctionDefinition("ARCCOSEC",           DataType.Double, "SDMath.Acsc",         xOnly),
                new FunctionDefinition("ARCCOSECANT",        DataType.Double, "SDMath.Acsc",         xOnly),
                new FunctionDefinition("ARCCSCH",            DataType.Double, "SDMath.Acsch",        xOnly),
                new FunctionDefinition("ARCCOSECH",          DataType.Double, "SDMath.Acsch",        xOnly),
                new FunctionDefinition("ARCCOSECANTH",       DataType.Double, "SDMath.Acsch",        xOnly),
                new FunctionDefinition("HYPERBOLICARCCSC",   DataType.Double, "SDMath.Acsch",        xOnly),
                new FunctionDefinition("HYPERBOLICARCCOSEC", DataType.Double, "SDMath.Acsch",        xOnly),
                new FunctionDefinition("HYPERBOLICARCCOSECANT", DataType.Double, "SDMath.Acsch",     xOnly),
                new FunctionDefinition("ARCSEC",             DataType.Double, "SDMath.Asec",         xOnly),
                new FunctionDefinition("ARCSECANT",          DataType.Double, "SDMath.Asec",         xOnly),
                new FunctionDefinition("ARCSECH",            DataType.Double, "SDMath.Asech",        xOnly),
                new FunctionDefinition("ARCSECANTH",         DataType.Double, "SDMath.Asech",        xOnly),
                new FunctionDefinition("HYPERBOLICARCSEC",   DataType.Double, "SDMath.Asech",        xOnly),
                new FunctionDefinition("HYPERBOLICARCSECANT",DataType.Double, "SDMath.Asech",        xOnly),
                new FunctionDefinition("ARCSIN",             DataType.Double, "Math.Asin",           xOnly),
                new FunctionDefinition("ARCSINE",            DataType.Double, "Math.Asin",           xOnly),
                new FunctionDefinition("ARCSINH",            DataType.Double, "SDMath.Asinh",        xOnly),
                new FunctionDefinition("ARCSINEH",           DataType.Double, "SDMath.Asinh",        xOnly),
                new FunctionDefinition("HYPERBOLICARCSIN",   DataType.Double, "SDMath.Asinh",        xOnly),
                new FunctionDefinition("HYPERBOLICARCSINE",  DataType.Double, "SDMath.Asinh",        xOnly),
                new FunctionDefinition("ARCTAN",             DataType.Double, "Math.Atan",           xOnly),
                new FunctionDefinition("ARCTANGENT",         DataType.Double, "Math.Atan",           xOnly),
                new FunctionDefinition("ARCTANH",            DataType.Double, "SDMath.Atanh",        xOnly),
                new FunctionDefinition("ARCTANGENTH",        DataType.Double, "SDMath.Atanh",        xOnly),
                new FunctionDefinition("HYPERBOLICARCTAN",   DataType.Double, "SDMath.Atanh",        xOnly),
                new FunctionDefinition("HYPERBOLICARCTANGENT", DataType.Double, "SDMath.Atanh",      xOnly),

                new FunctionDefinition("BINOMIAL",           DataType.Double, "SDMath.Binomial",     new[] { n, r, p }),
                new FunctionDefinition("BINOMIALP",          DataType.Double, "SDMath.Binomialp",    new[] { n, r, p }),
                new FunctionDefinition("BINOMIALTAIL",       DataType.Double, "SDMath.BinomialTail", new[] { n, r, p }),
                new FunctionDefinition("CEXP",               DataType.Double, "SDMath.Cexp",         xOnly),
                new FunctionDefinition("CHI2TAIL",           DataType.Double, "SDMath.Chi2Tail",     new[] { df, q }),
                new FunctionDefinition("CINT",               DataType.Double, "SDMath.Cint",         xOnly),
                new FunctionDefinition("CLOG",               DataType.Double, "SDMath.Clog",         xOnly),
                new FunctionDefinition("COS",                DataType.Double, "Math.Cos",            xOnly),
                new FunctionDefinition("COSINE",             DataType.Double, "Math.Cos",            xOnly),
                new FunctionDefinition("COSH",               DataType.Double, "SDMath.Cosh",         xOnly),
                new FunctionDefinition("COSINEH",            DataType.Double, "SDMath.Cosh",         xOnly),
                new FunctionDefinition("HYPERBOLICCOS",      DataType.Double, "SDMath.Cosh",         xOnly),
                new FunctionDefinition("HYPERBOLICCOSINE",   DataType.Double, "SDMath.Cosh",         xOnly),
                new FunctionDefinition("COT",                DataType.Double, "SDMath.Cot",          xOnly),
                new FunctionDefinition("COTAN",              DataType.Double, "SDMath.Cot",          xOnly),
                new FunctionDefinition("COTANGENT",          DataType.Double, "SDMath.Cot",          xOnly),
                new FunctionDefinition("COTH",               DataType.Double, "SDMath.Coth",         xOnly),
                new FunctionDefinition("COTANH",             DataType.Double, "SDMath.Coth",         xOnly),
                new FunctionDefinition("COTANGENTH",         DataType.Double, "SDMath.Coth",         xOnly),
                new FunctionDefinition("HYPERBOLICCOT",      DataType.Double, "SDMath.Coth",         xOnly),
                new FunctionDefinition("HYPERBOLICCOTAN",    DataType.Double, "SDMath.Coth",         xOnly),
                new FunctionDefinition("HYPERBOLICCOTANGENT",DataType.Double, "SDMath.Coth",         xOnly),
                new FunctionDefinition("CSC",                DataType.Double, "SDMath.Csc",          xOnly),
                new FunctionDefinition("COSEC",              DataType.Double, "SDMath.Csc",          xOnly),
                new FunctionDefinition("COSECANT",           DataType.Double, "SDMath.Csc",          xOnly),
                new FunctionDefinition("CSCH",               DataType.Double, "SDMath.Csch",         xOnly),
                new FunctionDefinition("COSECH",             DataType.Double, "SDMath.Csch",         xOnly),
                new FunctionDefinition("COSECANTH",          DataType.Double, "SDMath.Csch",         xOnly),
                new FunctionDefinition("HYPERBOLICCSC",      DataType.Double, "SDMath.Csch",         xOnly),
                new FunctionDefinition("HYPERBOLICCOSEC",    DataType.Double, "SDMath.Csch",         xOnly),
                new FunctionDefinition("HYPERBOLICCOSECANT", DataType.Double, "SDMath.Csch",         xOnly),
                new FunctionDefinition("DBINOM",             DataType.Double, "SDMath.Dbinom",       new[] { r, n, p, logDefFalse }),
                new FunctionDefinition("DEG",                DataType.Double, "SDMath.Deg",          xOnly),
                new FunctionDefinition("DPOIS",              DataType.Double, "SDMath.Dpois",        new[] { k, mean, logP }),
                new FunctionDefinition("EXP",                DataType.Double, "Math.Exp",            xOnly),
                new FunctionDefinition("FIX",                DataType.Double, "Math.Truncate",          xOnly),
                new FunctionDefinition("FTAIL",              DataType.Double, "SDMath.Ftail",        new[] { dfn, dfd, q }),
                new FunctionDefinition("INT",                DataType.Double, "Math.Floor",          xOnly),
                new FunctionDefinition("INVCHI2TAIL",        DataType.Double, "SDMath.InvChi2Tail",  new[] { df, p }),
                new FunctionDefinition("INVFTAIL",           DataType.Double, "SDMath.InvFtail",     new[] { dfn, dfd, p }),
                new FunctionDefinition("INVNORMAL",          DataType.Double, "SDMath.Iz",           new[] { p }),
                new FunctionDefinition("INVPOISSONTAIL",     DataType.Double, "SDMath.InvPoissonTail", new[] { mean, k }),
                new FunctionDefinition("INVTTAIL",           DataType.Double, "SDMath.InvTTail",     new[] { df, p }),
                new FunctionDefinition("IZ",                 DataType.Double, "SDMath.Iz",           new[] { p }),
                new FunctionDefinition("LN",                 DataType.Double, "Math.Log",            xOnly),
                new FunctionDefinition("LNNORMAL",           DataType.Double, "SDMath.Lz",           new[] { q }),
                new FunctionDefinition("LOG",                DataType.Double, "Math.Log",            xOnly),
                new FunctionDefinition("LOG!",               DataType.Double, "SDMath.LogFactorial", xOnly),
                new FunctionDefinition("LOGFACTORIAL",       DataType.Double, "SDMath.LogFactorial", xOnly),
                new FunctionDefinition("LOGIT",              DataType.Double, "SDMath.Logit",        xOnly),
                new FunctionDefinition("LOGZ",               DataType.Double, "SDMath.Lz",           new[] { q }),
                new FunctionDefinition("LZ",                 DataType.Double, "SDMath.Lz",           new[] { q }),
                new FunctionDefinition("NORMAL",             DataType.Double, "SDMath.Lz",           new[] { q }),
                new FunctionDefinition("PBINOM",             DataType.Double, "SDMath.Pbinom",       new[] { r, n, p, lowerTail, logP }),
                new FunctionDefinition("PCHISQ",             DataType.Double, "SDMath.Pchisq",       new[] { q, df, lowerTail, logP }),
                new FunctionDefinition("PF",                 DataType.Double, "SDMath.Pf",           new[] { q, df1, df2, lowerTail, logP }),
                new FunctionDefinition("PNORM",              DataType.Double, "SDMath.Pnorm",        new[] { q, meanDef0, sdDef1, lowerTail, logP }),
                new FunctionDefinition("POISSONP",           DataType.Double, "SDMath.Poissonp",     new[] { mean, k }),
                new FunctionDefinition("POISSONTAIL",        DataType.Double, "SDMath.PoissonTail",  new[] { mean, k }),
                new FunctionDefinition("PPOIS",              DataType.Double, "SDMath.Ppois",        new[] { k, mean, lowerTail, logP }),
                new FunctionDefinition("PT",                 DataType.Double, "SDMath.Pt",           new[] { q, df, ncpDefMissing, lowerTail, logP }),
                new FunctionDefinition("PZ",                 DataType.Double, "SDMath.Lz",           new[] { q }),
                new FunctionDefinition("QCHISQ",             DataType.Double, "SDMath.Qchisq",       new[] { p, df, lowerTail, logP }),
                new FunctionDefinition("QF",                 DataType.Double, "SDMath.Qf",           new[] { p, df1, df2, lowerTail, logP }),
                new FunctionDefinition("QNORM",              DataType.Double, "SDMath.Qnorm",        new[] { p, meanDef0, sdDef1, lowerTail, logP }),
                new FunctionDefinition("QPOIS",              DataType.Double, "SDMath.Qpois",        new[] { p, mean, lowerTail, logP }),
                new FunctionDefinition("QT",                 DataType.Double, "SDMath.Qt",           new[] { p, df, ncpDefMissing, lowerTail, logP }),
                new FunctionDefinition("RAD",                DataType.Double, "SDMath.Rad",          xOnly),
                new FunctionDefinition("SEC",                DataType.Double, "SDMath.Sec",          xOnly),
                new FunctionDefinition("SECANT",             DataType.Double, "SDMath.Sec",          xOnly),
                new FunctionDefinition("SECH",               DataType.Double, "SDMath.Sech",         xOnly),
                new FunctionDefinition("SECANTH",            DataType.Double, "SDMath.Sech",         xOnly),
                new FunctionDefinition("HYPERBOLICSEC",      DataType.Double, "SDMath.Sech",         xOnly),
                new FunctionDefinition("HYPERBOLICSECANT",   DataType.Double, "SDMath.Sech",         xOnly),
                new FunctionDefinition("SIN",                DataType.Double, "Math.Sin",            xOnly),
                new FunctionDefinition("SINE",               DataType.Double, "Math.Sin",            xOnly),
                new FunctionDefinition("SINH",               DataType.Double, "SDMath.Sinh",         xOnly),
                new FunctionDefinition("SINEH",              DataType.Double, "SDMath.Sinh",         xOnly),
                new FunctionDefinition("HYPERBOLICSIN",      DataType.Double, "SDMath.Sinh",         xOnly),
                new FunctionDefinition("HYPERBOLICSINE",     DataType.Double, "SDMath.Sinh",         xOnly),
                new FunctionDefinition("SQR",                DataType.Double, "Math.Sqrt",           xOnly),
                new FunctionDefinition("SQRT",               DataType.Double, "Math.Sqrt",           xOnly),
                new FunctionDefinition("TAN",                DataType.Double, "Math.Tan",            xOnly),
                new FunctionDefinition("TANGENT",            DataType.Double, "Math.Tan",            xOnly),
                new FunctionDefinition("TANH",               DataType.Double, "SDMath.Tanh",         xOnly),
                new FunctionDefinition("TANGENTH",           DataType.Double, "SDMath.Tanh",         xOnly),
                new FunctionDefinition("HYPERBOLICTAN",      DataType.Double, "SDMath.Tanh",         xOnly),
                new FunctionDefinition("HYPERBOLICTANGENT",  DataType.Double, "SDMath.Tanh",         xOnly),
                new FunctionDefinition("TRUNC",              DataType.Double, "Math.Truncate",          xOnly),
                new FunctionDefinition("TTAIL",              DataType.Double, "SDMath.TTail",        new[] { df, q }),
                new FunctionDefinition("UZ",                 DataType.Double, "SDMath.Uz",           new[] { q })
            });
        }

        private void AddAll(IEnumerable<FunctionDefinition> definitions)
        {
            foreach (FunctionDefinition functionDefinition in definitions)
                functionDefinitions.Add(functionDefinition.Name, functionDefinition);
        }

        public FunctionDefinition FunctionNamed(string name)
        {
            functionDefinitions.TryGetValue(name, out FunctionDefinition functionDefinition);
            return functionDefinition;
        }
    }
}
