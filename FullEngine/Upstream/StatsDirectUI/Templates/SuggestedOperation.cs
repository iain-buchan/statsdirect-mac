using System.Xml.Serialization;

namespace StatsDirect.Templates
{
    public class SuggestedOperation
    {
        [XmlText]
        public string Name { get; set; }

        [XmlIgnore]
        public Expression SuggestIf { get; set; }

        [XmlAttribute(AttributeName = "suggest-if")]
        public string SuggestIfBodyForXml
        {
            get => null == SuggestIf ? null : SuggestIf.Body;
            set
            {
                if (null == SuggestIf)
                    SuggestIf = new Expression();
                SuggestIf.Body = value;
            }
        }

        [XmlAttribute(AttributeName = "suggest-if-language")]
        public string SuggestIfLanguageForXml
        {
            get => null == SuggestIf ? null : SuggestIf.Language;
            set
            {
                if (null == SuggestIf)
                    SuggestIf = new Expression();
                SuggestIf.Language = value;
            }
        }
    }
}
