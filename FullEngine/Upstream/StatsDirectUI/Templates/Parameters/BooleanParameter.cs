using System;
using System.Xml.Serialization;

namespace StatsDirect.Templates
{
    [Serializable]
    public sealed class BooleanParameter: Parameter, IDefaultParameter<bool>
    {
        private Expression defaultValue;

        public bool? DefaultValue(ITemplateProcessor processor, ParameterBag parameters)
        {
            if (null == defaultValue || null == defaultValue.Body)
                return null;
            object o = processor.Evaluate(defaultValue, parameters);
            if (o is bool)
                return (bool)o;
            return (bool?)o;
        }

        /// <summary>
        /// true iff the parameter defines a default.
        /// </summary>
        public bool HasDefaultValue => null != defaultValue;

        [XmlElement(ElementName = "default-value")]
        public Expression DefaultValueExpression
        {
            get => defaultValue;
            set => defaultValue = value;
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
            bool? value = DefaultValue(processor, context);
            if (value.HasValue)
                return new ParameterBag(Name, FilledParameterFactory.Default(value.Value));
            return new ParameterBag();
        }
    }
}
