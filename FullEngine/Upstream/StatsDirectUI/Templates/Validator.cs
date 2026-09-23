using System;
using System.Xml.Serialization;

namespace StatsDirect.Templates
{
    [Serializable]
    public class Validator
    {
        /// <summary>
        /// A way in which the data should be validated
        /// </summary>
        [XmlElement("name")]
        public string ValidatorName { get; set; }

        [XmlElement("test-if-true")]
        public Expression TestIfTrueExpression { get; set; }

        [XmlIgnore]
        public bool HasTestIfTrueExpression => null != TestIfTrueExpression;
    }
}
