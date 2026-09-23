using System.Xml.Serialization;

namespace StatsDirect.Templates
{
    /// <summary>
    /// A scripted validator, called as string Validate(ITemplateHost host, FilledParameter parameters, Parameter parameter)
    /// </summary>
    public class CustomValidator
    {
        [XmlAttribute("name")]
        public string Name { get; set; }

        [XmlAttribute("language")]
        public string Language { get; set; }

        [XmlText]
        public string Script { get; set; }
    }
}
