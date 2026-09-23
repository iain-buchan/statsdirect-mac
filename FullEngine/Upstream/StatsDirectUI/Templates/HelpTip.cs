using System;
using System.Xml.Serialization;

namespace StatsDirect.Templates
{
    [Serializable]
    public class HelpTip
    {
        [XmlAttribute(AttributeName = "lang")]
        public string Lang { get; set; }

        [XmlText]
        public string Text { get; set; }
    }
}
