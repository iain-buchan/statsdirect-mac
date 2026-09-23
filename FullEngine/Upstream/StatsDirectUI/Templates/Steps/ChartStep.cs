using System.Xml.Serialization;

namespace StatsDirect.Templates
{
    /// <summary>
    /// Superclass for chart templates.  Subclasses may be made for particular types of chart; this contains data common to all.
    /// </summary>
    public class ChartStep : Step
    {
        public ChartStep()
        {
            RequestUserInput = true;
        }

        [XmlElement(ElementName = "chart-type")]
        public ChartType ChartType { get; set; }

        [XmlElement(ElementName = "chart-name")]
        public string ChartName { get; set; }

        [XmlElement(ElementName = "chart-title")]
        public string ChartTitle { get; set; }

        [XmlElement(ElementName = "box-axes")]
        public bool ShouldBoxAxes { get; set; }

        [XmlElement(ElementName = "ascii")]
        public bool IsAscii { get; set; }

        [XmlElement(ElementName = "request-user-input")]
        public bool RequestUserInput { get; set; }

        [XmlElement(ElementName = "x-axis-title")]
        public Expression XAxisTitleExpression { get; set; }

        [XmlElement(ElementName = "y-axis-title")]
        public Expression YAxisTitleExpression { get; set; }

        [XmlElement(ElementName = "x-series-data")]
        public string XSeriesDataName { get; set; }

        [XmlElement(ElementName = "y-series-data")]
        public string YSeriesDataName { get; set; }

        public string XAxisTitle(ITemplateProcessor processor, ParameterBag parameters)
        {
            if (null == XAxisTitleExpression || null == XAxisTitleExpression.Body)
                return null;
            return (string)processor.Evaluate(XAxisTitleExpression, parameters);
        }

        public string YAxisTitle(ITemplateProcessor processor, ParameterBag parameters)
        {
            if (null == YAxisTitleExpression || null == YAxisTitleExpression.Body)
                return null;
            return (string)processor.Evaluate(YAxisTitleExpression, parameters);
        }

        public override StepOutput ExecuteInternal(ITemplateProcessor processor, ParameterBag parameters)
        {
            return processor.ExecuteInternal(this, parameters);
        }

        public override InputDuringStep RequiresInputGiven(ParameterBag parameters)
        {
            return InputDuringStep.Never;
        }

        public override void Accept(IStepVisitor visitor)
        {
            visitor.Visit(this);
        }
    }
}
