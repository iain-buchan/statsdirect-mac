using System;
using System.Xml.Serialization;
using StatsDirect.Utilities;

namespace StatsDirect.Templates
{
    /// <summary>
    /// Extract the named data frame from the input parameters and cause the host to display it
    /// </summary>
    [Serializable, XmlType(Namespace = "http://www.statsdirect.com/schemas/Operation.xsd", TypeName = "output-frame")]
    public sealed class OutputFrameStep: Step
    {
        public OutputFrameStep()
        {
            MissingIndicator = Formatting.ASTERISK;
            DefaultPlacement = RelativePosition.AfterSelection;
        }

        /// <summary>
        /// The name of the parameter containing the frame to be output
        /// </summary>
        [XmlAttribute(AttributeName="frame-name")]
        public string ParameterName { get; set; }

        [XmlAttribute(AttributeName="keep-selection")]
        public bool KeepSelection { get; set; }

        [XmlAttribute(AttributeName = "formulae")]
        public bool IsFormulae { get; set; }

        [XmlAttribute(AttributeName = "missing-indicator")]
        public string MissingIndicator { get; set; }

        [XmlAttribute(AttributeName="default-placement")]
        public RelativePosition DefaultPlacement { get; set; }

        public override StepOutput ExecuteInternal(ITemplateProcessor processor, ParameterBag parameters) => processor.ExecuteInternal(this, parameters);

        /// <summary>
        /// Requires input if the output location has not been selected.
        /// </summary>
        public override InputDuringStep RequiresInputGiven(ParameterBag parameters) => InputDuringStep.SometimesOrAlways;

        public override void Accept(IStepVisitor visitor) => visitor.Visit(this);
    }
}
