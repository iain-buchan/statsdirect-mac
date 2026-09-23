using System;
using System.Collections.Generic;
using System.Xml.Serialization;

namespace StatsDirect.Templates
{
    [Serializable]
    public sealed class OptionsOption
    {
        [XmlAttribute(AttributeName = "name")]
        public string Name { get; set; }

        [XmlText]
        public string Label { get; set; }

        [XmlAttribute(AttributeName = "selected")]
        public bool Selected { get; set; }
    }

    /// <summary>
    /// A parameter allowing selection of zero or more options from a list.
    /// </summary>
    [Serializable]
    public sealed class OptionsParameter: Parameter
    {
        private readonly IList<OptionsOption> options;

        public OptionsParameter()
        {
            options = new List<OptionsOption>();
        }

        /// <summary>
        /// A hint about the number of columns the UI should use to display options.
        /// </summary>
        /// <value>Defaults to 2</value>
        [XmlElement(ElementName = "columns")]
        public int Columns { get; set; } = 2;

        [XmlArray(ElementName = "options")]
        [XmlArrayItem(ElementName = "option")]
        public OptionsOption[] OptionsForXML
        {
            get
            {
                OptionsOption[] optionArray = new OptionsOption[options.Count];
                for (int i = 0; i < options.Count; i++)
                    optionArray[i] = options[i];
                return optionArray;
            }
            set
            {
                foreach (OptionsOption option in value)
                    options.Add(option);
            }
        }

        public IList<OptionsOption> Options => options;

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
