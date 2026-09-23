using System;
using System.Xml.Serialization;
using StatsDirect.TemplateProcessing;

namespace StatsDirect.Templates
{
    [Serializable, XmlType(Namespace = "http://www.statsdirect.com/schemas/Operation.xsd", TypeName = "report-template")]
    public sealed class ReportStep: Step
    {
        [XmlAttribute(AttributeName="filename")]
        public string FileName { get; set; }

        [XmlText]
        public string Text { get; set; }

        [XmlAttribute(AttributeName="type")]
        public string MimeType { get; set; }

        public string GetContent()
        {
            if (null != Text)
                return Text;
            return ReportRenderer.GetContent(FileName);
        }

        public override StepOutput ExecuteInternal(ITemplateProcessor processor, ParameterBag parameters) => processor.ExecuteInternal(this, parameters);

        /// <summary>
        /// Doesn't need to be told where to put the output as that's now UI state rather than requested on demand.
        /// </summary>
        public override InputDuringStep RequiresInputGiven(ParameterBag parameters) => InputDuringStep.Never;

        public override void Accept(IStepVisitor visitor) => visitor.Visit(this);
    }
}
