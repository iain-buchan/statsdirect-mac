using System;
using System.Collections.Generic;
using System.Xml.Serialization;

namespace StatsDirect.Templates
{
    [Serializable,
       XmlType(Namespace="http://www.statsdirect.com/schemas/Operation.xsd", TypeName="iteration")]
    public class IterationStep: Step
    {
        private readonly IList<Step> steps;
        private string lowerBoundParameterName;
        private string upperBoundParameterName;
        private int? lowerBound;
        private int? upperBound;
        private string loopVariableName;

        public IterationStep()
        {
            steps = new List<Step>();
        }

        [XmlArray(ElementName = "steps"),
            XmlArrayItem(ElementName = "builtin", Type = typeof(BuiltinStep)),
            XmlArrayItem(ElementName = "chart", Type = typeof(ChartStep)),
            XmlArrayItem(ElementName = "iteration", Type = typeof(IterationStep)),
            XmlArrayItem(ElementName = "report", Type = typeof(ReportStep)),
            XmlArrayItem(ElementName = "script", Type = typeof(ScriptStep)),
            XmlArrayItem(ElementName = "parameters", Type = typeof(ParametersStep)),
            XmlArrayItem(ElementName = "test", Type = typeof(TestStep))
        ]
        public Step[] StepsForXml
        {
            get
            {
                Step[] stepArray = new Step[steps.Count];
                for (int i = 0; i < steps.Count; i++)
                    stepArray[i] = steps[i];
                return stepArray;
            }
            set
            {
                foreach (Step step in value)
                    steps.Add(step);
            }
        }

        [XmlElement(ElementName = "lower-bound")]
        public int? LowerBound
        {
            get => lowerBound;
            set => lowerBound = value;
        }

        [XmlElement(ElementName = "upper-bound")]
        public int? UpperBound
        {
            get => upperBound;
            set => upperBound = value;
        }

        [XmlElement(ElementName = "lower-bound-parameter")]
        public string LowerBoundParameterName
        {
            get => lowerBoundParameterName;
            set => lowerBoundParameterName = value;
        }

        [XmlElement(ElementName = "upper-bound-parameter")]
        public string UpperBoundParameterName
        {
            get => upperBoundParameterName;
            set => upperBoundParameterName = value;
        }

        [XmlElement(ElementName = "loop-variable-name")]
        public string LoopVariableName
        {
            get => loopVariableName;
            set => loopVariableName = value;
        }

        /// <summary>
        /// The steps that will be run as the body of the iteration.
        /// </summary>
        public IList<Step> Steps => steps;

        public override StepOutput ExecuteInternal(ITemplateProcessor processor, ParameterBag parameters)
        {
            return processor.ExecuteInternal(this, parameters);
        }

        public override bool RequiresGrid
        {
            get
            {
                foreach (Step step in steps)
                    if (step.RequiresGrid)
                        return true;
                return false;
            }
        }

        public override InputDuringStep RequiresInputGiven(ParameterBag parameters)
        {
            return GetInputRequirement(steps, parameters);
        }

        internal override void NoteOperation(Operation operation)
        {
            base.NoteOperation(operation);
            foreach (Step s in steps)
                s.NoteOperation(operation);
        }

        public override void Accept(IStepVisitor visitor)
        {
            visitor.Visit(this);
        }
    }
}
