using StatsDirect.Templates;

namespace StatsDirect.Builtins
{
    public static class Distribution
    {
        public static StepOutput DistNormal(IUserInterface host, ParameterBag parameters) => DistributionOf(host, parameters, DistributionType.Z);

        public static StepOutput DistT(IUserInterface host, ParameterBag parameters) => DistributionOf(host, parameters, DistributionType.T);

        public static StepOutput DistF(IUserInterface host, ParameterBag parameters) => DistributionOf(host, parameters, DistributionType.F);

        public static StepOutput DistChiSquare(IUserInterface host, ParameterBag parameters) => DistributionOf(host, parameters, DistributionType.ChiSq);

        public static StepOutput DistQ(IUserInterface host, ParameterBag parameters) => DistributionOf(host, parameters, DistributionType.Q);

        public static StepOutput DistBinomial(IUserInterface host, ParameterBag parameters) => DistributionOf(host, parameters, DistributionType.Binomial);

        public static StepOutput DistPoisson(IUserInterface host, ParameterBag parameters) => DistributionOf(host, parameters, DistributionType.Poisson);

        public static StepOutput DistKendall(IUserInterface host, ParameterBag parameters) => DistributionOf(host, parameters, DistributionType.Kendall);

        public static StepOutput DistSpearman(IUserInterface host, ParameterBag parameters) => DistributionOf(host, parameters, DistributionType.Rho);

        public static StepOutput DistNonCentralT(IUserInterface host, ParameterBag parameters) => DistributionOf(host, parameters, DistributionType.NonCentralT);

        private static StepOutput DistributionOf(IUserInterface host, ParameterBag parameters, DistributionType selectedTest)
        {
            DistributionOptions distributionOptions = new() { SelectedTest = selectedTest };
            ParameterBag outputParameters = host.Amend(distributionOptions, parameters);
            return new StepOutput(outputParameters);
        }
    }
}
