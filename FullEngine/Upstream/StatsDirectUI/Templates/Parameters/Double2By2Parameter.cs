using System;
using System.Xml.Serialization;

namespace StatsDirect.Templates
{
    [Serializable]
    public sealed class Double2By2Parameter: Parameter
    {
        [XmlElement(ElementName = "columns-prompt")]
        public string ColumnsPrompt { get; set; }

        [XmlElement(ElementName = "left-column-prompt")]
        public string LeftColumnPrompt { get; set; }

        [XmlElement(ElementName = "right-column-prompt")]
        public string RightColumnPrompt { get; set; }

        [XmlElement(ElementName = "rows-prompt")]
        public string RowsPrompt { get; set; }

        [XmlElement(ElementName = "top-row-prompt")]
        public string TopRowPrompt { get; set; }

        [XmlElement(ElementName = "bottom-row-prompt")]
        public string BottomRowPrompt { get; set; }

        [XmlElement(ElementName = "top-left-name")]
        public string TopLeftName { get; set; }

        [XmlElement(ElementName = "top-right-name")]
        public string TopRightName { get; set; }

        [XmlElement(ElementName = "bottom-left-name")]
        public string BottomLeftName { get; set; }

        [XmlElement(ElementName = "bottom-right-name")]
        public string BottomRightName { get; set; }

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
