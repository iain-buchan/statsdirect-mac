using System;
using System.Xml.Serialization;

namespace StatsDirect.Templates
{
    [Serializable]
    public sealed class OptionOption
    {
        [XmlAttribute(AttributeName = "value")]
        public string Value { get; set; }

        [XmlIgnore]
        public Expression AvailableIfExpression { get; set; }

        [XmlText]
        public string Label { get; set; }

        [XmlAttribute(AttributeName = "available-if")]
        public string AvailableIfExpressionForXml
        {
            get => AvailableIfExpression?.Body;
            set => AvailableIfExpression = new Expression(value);
        }

        public bool AvailableIf(ITemplateProcessor processor, ParameterBag parameters)
        {
            if (null == AvailableIfExpression || null == AvailableIfExpression.Body)
                return true;
            object o = processor.Evaluate(AvailableIfExpression, parameters);
            return (bool)o;
        }

        public bool HasAvailableIf => null != AvailableIfExpression;

        public override string ToString()
        {
            return Label;
        }
    }
}
