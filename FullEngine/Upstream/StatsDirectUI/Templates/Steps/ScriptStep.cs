using System.Xml.Serialization;

namespace StatsDirect.Templates
{
    public sealed class ScriptStep: Step
    {
        private InputDuringStep requiresInput;
        private bool requiresGrid;

        [XmlAttribute(AttributeName = "language")]
        public string Language { get; set; }

        [XmlAttribute(AttributeName = "requires-grid")]
        public bool RequiresGridForXml 
        {
            get => requiresGrid;
            set => requiresGrid = value;
        }

        [XmlAttribute(AttributeName = "entry-point")]
        public string EntryPoint { get; set; }

        [XmlText]
        public string Body { get; set; }

        public override StepOutput ExecuteInternal(ITemplateProcessor processor, ParameterBag parameters)
        {
            return processor.ExecuteInternal(this, parameters);
        }

        [XmlAttribute(AttributeName = "requires-input")]
        public InputDuringStep RequiresInputForXml
        {
            get => requiresInput;
            set => requiresInput = value;
        }

        public override InputDuringStep RequiresInputGiven(ParameterBag parameters)
        {
            return requiresInput;
        }

        [XmlIgnore]
        public override bool RequiresGrid => requiresGrid;

        public override void Accept(IStepVisitor visitor)
        {
            visitor.Visit(this);
        }
    }
}
