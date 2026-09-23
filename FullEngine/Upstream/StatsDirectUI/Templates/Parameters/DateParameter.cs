using System;
using System.Xml.Serialization;

namespace StatsDirect.Templates
{
    [Serializable]
    public sealed class DateParameter: RangeParameter
    {
        /// <summary>
        /// The default value for this parameter, or null for no default.
        /// </summary>
        public DateTime DefaultValue(ITemplateProcessor processor, ParameterBag parameters)
        {
            return (DateTime)processor.Evaluate(DefaultValueExpression, parameters);
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
