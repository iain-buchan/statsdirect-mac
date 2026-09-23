using System;
using System.Xml.Serialization;

namespace StatsDirect.Templates
{
    /// <summary>
    /// A parameter allowing entry of a data column with a header column.
    /// </summary>
    [Serializable]
    public sealed class EditGridParameter: Parameter
    {
        private string keyVariable;
        private string valueVariable;
        private string source;

        /// <summary>
        /// The title of the StringVariable that will be used as the non-editable header.
        /// </summary>
        [XmlElement(ElementName = "key-variable")]
        public string KeyVariable
        {
            get => keyVariable;
            set => keyVariable = value;
        }

        /// <summary>
        /// The title of the StringVariable that will be used as the editable value.
        /// </summary>
        [XmlElement(ElementName = "value-variable")]
        public string ValueVariable
        {
            get => valueVariable;
            set => valueVariable = value;
        }

        /// <summary>
        /// The name of the frame from which the variables will be drawn (may be the same asthe parameter name, in which case it will be edited in place).
        /// </summary>
        [XmlElement(ElementName = "source")]
        public string Source
        {
            get => source;
            set => source = value;
        }

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
