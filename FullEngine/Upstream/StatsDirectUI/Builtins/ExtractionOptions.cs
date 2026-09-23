using StatsDirect.Data;
using StatsDirect.Templates;

namespace StatsDirect.Builtins
{
    public class ExtractionOptions : IFillable
    {
        public string Title { get; set; }
        public DataFrame DataFrame { get; set; }
        public DataFrame IdentifiersFrame { get; set; }
        public string IdentifierNames { get; set; }

        public string FillerToUse => "Extraction";
    }
}