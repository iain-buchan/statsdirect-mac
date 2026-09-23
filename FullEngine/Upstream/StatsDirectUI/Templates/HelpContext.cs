using System;
using System.Xml.Serialization;

namespace StatsDirect.Templates
{
    [Serializable]
    public class HelpContext
    {
        [XmlAttribute(AttributeName="chm-id")]
        public int ChmId { get; set; }

        [XmlAttribute(AttributeName = "url")]
        public string Url { get; set; }
    }
}
