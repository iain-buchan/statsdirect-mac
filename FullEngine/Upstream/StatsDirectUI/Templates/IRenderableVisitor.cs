using StatsDirect.Charting;

namespace StatsDirect.Templates
{
    public interface IRenderableVisitor
    {
        void Visit(ReportTemplateAndParameters victim);
        void Visit(ChartDefinition victim);
    }
}