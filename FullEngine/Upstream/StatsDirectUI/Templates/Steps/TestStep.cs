using System;
using System.Collections.Generic;
using System.Xml.Serialization;

namespace StatsDirect.Templates
{
    [XmlType(Namespace="http://www.statsdirect.com/schemas/Operation.xsd", TypeName="test")]
    public class TestStep: Step
    {
        public TestStep()
        {
            TrueSteps = new List<Step>();
            FalseSteps = new List<Step>();
        }

        // Remember to change Operation::StepsForXml and TestStep::FalseStepsForXml if you change this list
        [XmlArray(ElementName = "iftrue"),
            XmlArrayItem(ElementName = "builtin", Type = typeof(BuiltinStep)),
            XmlArrayItem(ElementName = "chart", Type = typeof(ChartStep)),
            XmlArrayItem(ElementName = "iteration", Type = typeof(IterationStep)),
            XmlArrayItem(ElementName = "output-frame", Type = typeof(OutputFrameStep)),
            XmlArrayItem(ElementName = "parameters", Type = typeof(ParametersStep)),
            XmlArrayItem(ElementName = "report", Type = typeof(ReportStep)),
            XmlArrayItem(ElementName = "script", Type = typeof(ScriptStep)),
            XmlArrayItem(ElementName = "test", Type = typeof(TestStep))
        ]
        public Step[] TrueStepsForXml
        {
            get
            {
                Step[] stepArray = new Step[TrueSteps.Count];
                for (int i = 0; i < TrueSteps.Count; i++)
                    stepArray[i] = TrueSteps[i];
                return stepArray;
            }
            set
            {
                foreach (Step step in value)
                    TrueSteps.Add(step);
            }
        }

        // Remember to change Operation::StepsForXml and TestStep::TrueStepsForXml if you change this list
        [XmlArray(ElementName = "iffalse"),
            XmlArrayItem(ElementName = "builtin", Type = typeof(BuiltinStep)),
            XmlArrayItem(ElementName = "chart", Type = typeof(ChartStep)),
            XmlArrayItem(ElementName = "iteration", Type = typeof(IterationStep)),
            XmlArrayItem(ElementName = "output-frame", Type = typeof(OutputFrameStep)),
            XmlArrayItem(ElementName = "parameters", Type = typeof(ParametersStep)),
            XmlArrayItem(ElementName = "report", Type = typeof(ReportStep)),
            XmlArrayItem(ElementName = "script", Type = typeof(ScriptStep)),
            XmlArrayItem(ElementName = "test", Type = typeof(TestStep))
        ]
        public Step[] FalseStepsForXml
        {
            get
            {
                Step[] stepArray = new Step[FalseSteps.Count];
                for (int i = 0; i < FalseSteps.Count; i++)
                    stepArray[i] = FalseSteps[i];
                return stepArray;
            }
            set
            {
                foreach (Step step in value)
                    FalseSteps.Add(step);
            }
        }

        [XmlElement(ElementName = "condition")]
        public Expression Condition { get; set; }

        /// <summary>
        /// The steps that will be run if the condition evaluates to true.
        /// </summary>
        public IList<Step> TrueSteps { get; }

        /// <summary>
        /// The steps that will be run if the condition evaluates to false.
        /// </summary>
        public IList<Step> FalseSteps { get; }

        public override StepOutput ExecuteInternal(ITemplateProcessor processor, ParameterBag parameters)
        {
            return processor.ExecuteInternal(this, parameters);
        }

        public override bool RequiresGrid
        {
            get
            {
                foreach (Step step in TrueSteps)
                    if (step.RequiresGrid)
                        return true;
                foreach (Step step in FalseSteps)
                    if (step.RequiresGrid)
                        return true;
                return false;
            }
        }

        public override InputDuringStep RequiresInputGiven(ParameterBag parameters)
        {
            InputDuringStep trueRequirement = GetInputRequirement(TrueSteps, parameters);
            InputDuringStep falseRequirement = GetInputRequirement(FalseSteps, parameters);

            // If the requirements are the same, that's the overall requirement
            if (trueRequirement == falseRequirement)
                return trueRequirement;

            // Otherwise, they're different.  In all such cases, it's a resounding maybe - which means we have to assume yes.
            return InputDuringStep.SometimesOrAlways;
        }

        public override bool IsOrContains(Step candidate)
        {
            if (base.IsOrContains(candidate))
                return true;

            foreach (Step s in TrueSteps)
                if (s.IsOrContains(candidate))
                    return true;
            foreach (Step s in FalseSteps)
                if (s.IsOrContains(candidate))
                    return true;
            return false;
        }

        public override HasInput ShouldRequestTargetAfter(Step stepToFind, Type stepType, bool found, out Step stepFound)
        {
            // If we're actually looking for this step (unlikely!) then we've found it.
            if (this == stepToFind)
            {
                // TODO: Should we evaluate both arms at this point and return something saner?
                stepFound = null;
                return HasInput.NoAndTypeNotFound;
            }

            HasInput trueSide = ShouldRequestTargetAfter(stepToFind, TrueSteps, stepType, found, out stepFound);
            if (trueSide != HasInput.NoAndTypeNotFound)
                return trueSide;
            HasInput falseSide = ShouldRequestTargetAfter(stepToFind, FalseSteps, stepType, found, out stepFound);
            return falseSide;
        }

        internal override void NoteOperation(Operation operation)
        {
            base.NoteOperation(operation);
            foreach (Step s in TrueSteps)
            {
                s.NoteOperation(operation);
            }
            foreach (Step s in FalseSteps)
            {
                s.NoteOperation(operation);
            }
        }

        public override void Accept(IStepVisitor visitor)
        {
            visitor.Visit(this);
        }
    }
}
