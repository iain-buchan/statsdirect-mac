using System;
using System.Xml.Serialization;

namespace StatsDirect.Templates
{
    /// <summary>
    /// A parameter allowing selection of multiple items from a variable in a data frame.
    /// </summary>
    [Serializable]
    public sealed class PickFromListParameter: Parameter
    {
        /// <summary>
        /// If true, multiple items may be selected from the list.
        /// If false, one item may be selected.
        /// </summary>
        [XmlElement(ElementName = "allow-multiple")]
        public bool AllowMultiple { get; set; }

        /// <summary>
        /// If true, there's a "none" entry at the top of the list.
        /// If false, only the list entries are present.
        /// </summary>
        [XmlElement(ElementName = "include-none-entry")]
        public bool IncludeNoneEntry { get; set; }

        /// <summary>
        /// The name of the frame whose first StringVariable will be used to provide labels for the selection.
        /// </summary>
        [XmlElement(ElementName = "source")]
        public string Source { get; set; }

        public override InputDuringStep RequiresInputGiven(ParameterBag parameters)
        {
            return MustRequest || null != Name && null != parameters && !parameters.ContainsKey(Name) ? InputDuringStep.SometimesOrAlways : InputDuringStep.Never;
        }

        public override void Accept(IParameterVisitor visitor)
        {
            visitor.Visit(this);
        }

        public override ParameterBag AllDefaults(ITemplateProcessor processor, ParameterBag context)
        {
            return new ParameterBag();
        }
    }
}
