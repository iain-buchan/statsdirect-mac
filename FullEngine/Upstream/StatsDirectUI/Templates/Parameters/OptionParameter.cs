using System;
using System.Collections.Generic;
using System.Xml.Serialization;

namespace StatsDirect.Templates
{
    /// <summary>
    /// A parameter allowing selection of one option from a list.
    /// </summary>
    [Serializable]
    public sealed class OptionParameter: Parameter
    {
        private readonly IList<OptionOption> options;

        public OptionParameter()
        {
            options = new List<OptionOption>();
        }

        /// <summary>
        /// A hint about the number of columns the UI should use to display options.
        /// </summary>
        /// <value>Defaults to 2</value>
        [XmlElement(ElementName = "columns")]
        public int Columns { get; set; } = 2;

        [XmlElement(ElementName="format-type")]
        public OptionFormatType OptionFormatType { get; set; } = OptionFormatType.Radio;

        [XmlArray(ElementName="options")]
        [XmlArrayItem(ElementName = "option")]
        public OptionOption[] OptionsForXML
        {
            get
            {
                OptionOption[] optionArray = new OptionOption[options.Count];
                for (int i = 0; i < options.Count; i++)
                    optionArray[i] = options[i];
                return optionArray;
            }
            set
            {
                foreach (OptionOption option in value)
                    options.Add(option);
            }
        }

        [XmlElement(ElementName = "default-value")]
        public Expression DefaultValueExpression { get; set; }

        public string DefaultValue(ITemplateProcessor processor, ParameterBag parameters)
        {
            if (null == DefaultValueExpression || null == DefaultValueExpression.Body)
                return null;
            object o = processor.Evaluate(DefaultValueExpression, parameters);
            if (null == o)
                return null;
            return o.ToString();
        }

        /// <summary>
        /// true iff the parameter defines a default.
        /// </summary>
        public bool HasDefaultValue => null != DefaultValueExpression;

        [XmlIgnore]
        public IList<OptionOption> Options => options;

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
            return new ParameterBag(Name, FilledParameterFactory.Default(DefaultValue(processor, context)));
        }
    }
}
