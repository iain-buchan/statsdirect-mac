using StatsDirect.Data;
using StatsDirect.Templates;

namespace StatsDirect.Builtins
{
    public class CategoriseOptions : IFillable
    {
        public string Title { get; set; }
        public double[] PassX { get; set; }
        public string[] Categories { get; set; }
        public int[] Counts { get; set; }
        public DoubleVariable Data { get; set; }

        public string FillerToUse => "Categorise";
    }
}