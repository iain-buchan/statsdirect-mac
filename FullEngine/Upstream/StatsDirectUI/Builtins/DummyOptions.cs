using System.Collections.Generic;
using StatsDirect.Templates;

namespace StatsDirect.Builtins
{
    public class DummyOptions : IFillable
    {
        public string LargestCategoryTitle { get; set; }
        public List<string> CategoryNames { get; set; }
        public string VariableName { get; set; }
        public bool AllowUserToTreatAsContinuous { get; set; }

        ///  <summary>
        ///  The name that the user selected, or Nothing if &lt;none> was selected.
        ///  </summary>
        public int JDrop { get; set; }

        /// <summary>
        /// True if the user selected to treat the variable as continuous.
        /// </summary>
        public bool TreatAsContinuous { get; set; }

        public static string FillerToUse => "Dummy";

        // interface properties implemented by FillerToUse
        string IFillable.FillerToUse => FillerToUse;
    }
}