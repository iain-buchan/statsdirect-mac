namespace StatsDirect.Templates
{
    public class ReportTemplateAndParameters: IRenderable
    {
        public ReportTemplate Template { get; }
        public ParameterBag Parameters { get; }

        public ReportTemplateAndParameters(ReportTemplate template, ParameterBag parameters)
        {
            Template = template;
            Parameters = parameters;
        }

        void IRenderable.Accept(IRenderableVisitor visitor)
        {
            visitor.Visit(this);
        }
    }
}