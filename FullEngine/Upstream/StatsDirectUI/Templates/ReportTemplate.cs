namespace StatsDirect.Templates
{
    public class ReportTemplate
    {
        public string Content { get; }
        public string MimeType { get; }

        public ReportTemplate(string content, string mimeType)
        {
            Content = content;
            MimeType = mimeType;
        }
    }
}