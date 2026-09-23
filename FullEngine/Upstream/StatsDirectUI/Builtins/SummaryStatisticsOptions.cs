using StatsDirect.Templates;

namespace StatsDirect.Builtins
{
    public class SummaryStatisticsOptions : IFillable
    {
        public string Text;

        string IFillable.FillerToUse => "SummaryStatistics";
    }
}