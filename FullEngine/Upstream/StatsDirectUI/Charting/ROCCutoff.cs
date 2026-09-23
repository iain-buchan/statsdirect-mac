using StatsDirect.Templates;

namespace StatsDirect.Charting
{
    public class ROCCutoff : IFillable
    {
        public ROCSeriesRecord SeriesRecord { get; set; }
        public string Title { get; set; }

        public string FillerToUse => "ROCCutoff";
    }
}
