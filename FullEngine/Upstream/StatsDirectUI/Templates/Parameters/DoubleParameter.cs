using System;
using System.Xml.Serialization;

namespace StatsDirect.Templates
{
    [Serializable]
    public sealed class DoubleParameter: RangeParameter, IDefaultParameter<double>
    {
        public double? DefaultValue(ITemplateProcessor processor, ParameterBag parameters)
        {
            if (null == DefaultValueExpression || null == DefaultValueExpression.Body)
                return null;
            object o = processor.Evaluate(DefaultValueExpression, parameters);
            if (o is int)
                return (int)o;
            return (double?)o;
        }

        /// <summary>
        /// true iff the parameter defines a default.
        /// </summary>
        public bool HasDefaultValue => null != DefaultValueExpression;

        public double MinimumValue(ITemplateProcessor processor, ParameterBag parameters)
        {
            if (null == MinimumValueExpression || null == MinimumValueExpression.Body)
                return double.MinValue;
            object o = processor.Evaluate(MinimumValueExpression, parameters);
            if (o is int)
                return (int)o;
            return (double)o;
        }

        public double MaximumValue(ITemplateProcessor processor, ParameterBag parameters)
        {
            if (null == MaximumValueExpression || null == MaximumValueExpression.Body)
                return double.MaxValue;
            object o = processor.Evaluate(MaximumValueExpression, parameters);
            if (o is int)
                return (int)o;
            return (double)o;
        }

        [XmlElement(ElementName = "default-value")]
        public Expression DefaultValueExpression { get; set; }

        [XmlElement(ElementName = "minimum-value")]
        public Expression MinimumValueExpression { get; set; }

        [XmlElement(ElementName = "maximum-value")]
        public Expression MaximumValueExpression { get; set; }

        public override void Accept(IParameterVisitor visitor)
        {
            visitor.Visit(this);
        }

        public override ParameterBag AllDefaults(ITemplateProcessor processor, ParameterBag context)
        {
            double? defaultValue = DefaultValue(processor, context);
            if (defaultValue.HasValue)
                return new ParameterBag(Name, FilledParameterFactory.Default(defaultValue.Value));
            return new ParameterBag();
        }
    }
}
