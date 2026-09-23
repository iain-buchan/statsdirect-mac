using System;
using System.Xml.Serialization;

namespace StatsDirect.Templates
{
    [Serializable]
    public sealed class IntegerParameter: RangeParameter, IDefaultParameter<int>
    {
        private int minimumValue = int.MinValue;
        private int maximumValue = int.MaxValue;

        /// <summary>
        /// The default value for this parameter, or null for no default.
        /// </summary>
        public int? DefaultValue(ITemplateProcessor processor, ParameterBag parameters)
        {
            if (null == DefaultValueExpression || null == DefaultValueExpression.Body)
                return null;
            object o = processor.Evaluate(DefaultValueExpression, parameters);
            return (int?)o;
        }

        /// <summary>
        /// true iff the parameter defines a default.
        /// </summary>
        public bool HasDefaultValue => null != DefaultValueExpression;

        /// <summary>
        /// The default value for this parameter, or null for no default.
        /// </summary>
        [XmlElement(ElementName = "default-value")]
        public Expression DefaultValueExpression { get; set; }

        [XmlElement(ElementName = "minimum-value")]
        public int MinimumValue
        {
            get => minimumValue;
            set => minimumValue = value;
        }

        [XmlElement(ElementName = "maximum-value")]
        public int MaximumValue
        {
            get => maximumValue;
            set => maximumValue = value;
        }

        public override void Accept(IParameterVisitor visitor)
        {
            visitor.Visit(this);
        }

        public override ParameterBag AllDefaults(ITemplateProcessor processor, ParameterBag context)
        {
            int? defaultValue = DefaultValue(processor, context);
            if (defaultValue.HasValue)
                return new ParameterBag(Name, FilledParameterFactory.Default(defaultValue.Value));
            return new ParameterBag();
        }
    }
}
