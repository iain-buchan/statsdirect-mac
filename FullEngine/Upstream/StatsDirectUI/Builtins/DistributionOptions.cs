using StatsDirect.Templates;

namespace StatsDirect.Builtins
{
    public class DistributionOptions : IFillable
    {
        public DistributionType SelectedTest { get; set; }
        public string FillerToUse => "Distribution";
    }
}