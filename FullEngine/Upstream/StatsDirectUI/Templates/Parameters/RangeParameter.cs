using System.Xml.Serialization;

namespace StatsDirect.Templates
{
    /// <summary>
    /// Abstract superclass for parameters that hold a single value taken from a range:
    /// Date, Double, Integer, String.
    /// </summary>
    public abstract class RangeParameter : Parameter
    {
        protected RangeParameter()
        {
            ShowLimits = true;
        }

        /// <summary>
        /// If false, an input real value will be used in preference to the default.
        /// If true, the default will be (re-)evaluated in preference to any input value.
        /// </summary>
        /// <value>false</value>
        [XmlElement(ElementName = "force-default")]
        public bool ForceDefault { get; set; }

        /// <summary>
        /// If false, the operation suggests that any interface need not show minimum and maximum limits.
        /// If true, the operation suggests that any interface should show limits.
        /// </summary>
        /// <value>false</value>
        [XmlElement(ElementName = "show-limits")]
        public bool ShowLimits { get; set; }

        public override InputDuringStep RequiresInputGiven(ParameterBag parameters)
        {
            return MustRequest || null != Name && null != parameters && !parameters.ContainsKey(Name) ? InputDuringStep.SometimesOrAlways : InputDuringStep.Never;
        }
    }
}
