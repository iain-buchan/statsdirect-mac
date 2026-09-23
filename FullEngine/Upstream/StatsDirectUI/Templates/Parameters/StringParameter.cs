using System.Xml.Serialization;

namespace StatsDirect.Templates
{
    public sealed class StringParameter: RangeParameter
    {
        /// <summary>
        /// The default value for this parameter, or null for no default.
        /// </summary>
        public string DefaultValue(ITemplateProcessor processor, ParameterBag parameters)
        {
            if (null == DefaultValueExpression)
                return null;
            return processor.Evaluate(DefaultValueExpression, parameters).ToString();
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

        /// <summary>
        /// The maximum length for this parameter, or 0 for no maximum.
        /// </summary>
        [XmlElement(ElementName = "maximum-length")]
        public int MaxLength { get; set; }

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
