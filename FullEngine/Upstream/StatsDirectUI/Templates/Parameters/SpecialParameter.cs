using System;
using System.Xml.Serialization;

namespace StatsDirect.Templates
{
    /// <summary>
    /// A rather unpleasant hack for several parameters which will only be used in a very few operations and are always acquired in the top bar.
    /// A more principled version would separate out the definitions of the various parameters into a general data acquisition language, but that's rather beyond SD 3.0.
    /// </summary>
    [Serializable]
    public sealed class SpecialParameter: Parameter
    {
        [XmlElement(ElementName="type")]
        public string SpecialType { get; set; }

        [XmlIgnore]
        public object ExtraData { get; set; }

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
