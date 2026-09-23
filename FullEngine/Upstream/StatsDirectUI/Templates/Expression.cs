using System;
using System.Xml.Serialization;

namespace StatsDirect.Templates
{
    /// <summary>
    /// Expressions starting with "=" are evaluated.
    /// Expressions that are integer are returned as Int32.
    /// Expressions that are floating-point are returned as Double.
    /// Anything else is returned as String.
    /// </summary>
    [Serializable]
    public sealed class Expression
    {
        public Expression()
        {
            Language = "CSharp";
        }

        public Expression(string body)
            : this()
        {
            Body = body;
        }

        [XmlText]
        public string Body { get; set; }

        [XmlAttribute(AttributeName="language")]
        public string Language { get; set; }

        public override string ToString()
        {
            return "Expression(" + (null == Body ? "null" : "\"" + Body + "\"") + ")";
        }
    }
}
