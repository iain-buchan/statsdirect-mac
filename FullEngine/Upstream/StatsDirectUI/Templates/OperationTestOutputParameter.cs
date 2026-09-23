using System.ComponentModel;
using System.Xml.Serialization;

namespace StatsDirect.Templates
{
    public class OperationTestOutputParameter : IOperationTestParameter
    {
        [XmlAttribute(AttributeName = "name")]
        public string Name { get; set; }

        [XmlAttribute(AttributeName = "missing")]
        [DefaultValue(false)]
        public bool ShouldBeMissing { get; set; }

        [XmlText]
        public string Value { get; set; }
    }
}