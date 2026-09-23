using StatsDirect.Charting;
using StatsDirect.Templates;
using System;
using System.Text;

namespace StatsDirect.TemplateProcessing
{
    /// <summary>
    /// Something that turns an IRenderable into a piece of RTF.
    /// </summary>
    class RtfRenderer : IRenderableVisitor
    {
        private /* TODO: IPreferences*/ ITemplateHost Host { get; }
        private StringBuilder builder;

        public RtfRenderer(/* TODO: IPreferences*/ ITemplateHost host)
        {
            Host = host;
        }

        public string Render(IRenderable renderable)
        {
            builder = new StringBuilder();
            renderable.Accept(this);
            string s = builder.ToString();
            builder = null;
            return s;
        }

        void IRenderableVisitor.Visit(ReportTemplateAndParameters victim)
        {
            ReportRenderer renderer = GetReportRenderer(victim.Template.MimeType);
            builder.Append(renderer.Render(Host, victim.Template.Content, victim.Parameters));
            // ReportRenderer newRenderer = new CreoleRtfReportRenderer();
            // builder.Append(newRenderer.Render(Host, victim.Template.Content, victim.Parameters));
        }

        void IRenderableVisitor.Visit(ChartDefinition victim)
        {
            RtfImageRenderer.PlotAndReturnRtf(Host, victim, out string rtf);
            builder.Append(rtf);
        }

        private ReportRenderer GetReportRenderer(string mimeType)
        {
            if ("application/x-statsdirect-creole".Equals(mimeType))
                return new PrincipledCreoleRtfReportRenderer();
            throw new ArgumentOutOfRangeException(nameof(mimeType), mimeType, "Unknown MIME type when trying to obtain a report renderer. Is this report in a format that StatsDirect can render?");
        }
    }
}
