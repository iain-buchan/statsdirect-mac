using System;
using System.Collections.Generic;
using System.Xml.Serialization;

namespace StatsDirect.Templates
{
    [Serializable,
       XmlType(Namespace="http://www.statsdirect.com/schemas/Operation.xsd", TypeName="settings")]
    public class ParametersStep: Step
    {
        public ParametersStep()
        {
            Parameters = new List<Parameter>();
        }

        [XmlElement(ElementName = "boolean", Type = typeof(BooleanParameter))]
        [XmlElement(ElementName = "confidence-interval", Type = typeof(ConfidenceIntervalParameter))]
        [XmlElement(ElementName = "date", Type = typeof(DateParameter))]
        [XmlElement(ElementName = "double", Type = typeof(DoubleParameter))]
        [XmlElement(ElementName = "double-2-by-2", Type = typeof(Double2By2Parameter))]
        [XmlElement(ElementName = "double-2-by-2-by-k", Type = typeof(Double2By2ByKParameter))]
        [XmlElement(ElementName = "edit-grid", Type = typeof(EditGridParameter))]
        [XmlElement(ElementName = "frame", Type = typeof(FrameParameter))]
        [XmlElement(ElementName = "frame2d", Type = typeof(Frame2DParameter))]
        [XmlElement(ElementName = "grouped-covariance", Type = typeof(GroupedCovarianceParameter))]
        [XmlElement(ElementName = "integer", Type = typeof(IntegerParameter))]
        [XmlElement(ElementName = "option", Type = typeof(OptionParameter))]
        [XmlElement(ElementName = "multiple-options", Type = typeof(OptionsParameter))]
        [XmlElement(ElementName = "pick-from-list", Type = typeof(PickFromListParameter))]
        [XmlElement(ElementName = "pick-variables", Type = typeof(PickVariablesParameter))]
        [XmlElement(ElementName = "special", Type = typeof(SpecialParameter))]
        [XmlElement(ElementName = "string", Type = typeof(StringParameter))]
        public Parameter[] ParametersForXml
        {
            get
            {
                Parameter[] parameterArray = new Parameter[Parameters.Count];
                for (int i = 0; i < Parameters.Count; i++)
                    parameterArray[i] = Parameters[i];
                return parameterArray;
            }
            set
            {
                foreach (Parameter parameter in value)
                    Parameters.Add(parameter);
            }
        }

        /// <summary>
        /// The parameters that will be requested before the operation steps are processed, in the order in which they will be requested.
        /// </summary>
        public IList<Parameter> Parameters { get; }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="processor"></param>
        /// <param name="parms"></param>
        /// <param name="isRedo"></param>
        /// <returns></returns>
        /// <remarks>Note that this may return parameters with key->null; it is up to the caller to deal with this.</remarks>
        public override StepOutput ExecuteInternal(ITemplateProcessor processor, ParameterBag parms) => processor.ExecuteInternal(this, parms);

        public override void PrepareInternal(ITemplateProcessor processor, ParameterBag parms) => processor.PrepareInternal(this, parms);

        internal override void NoteOperation(Operation operation)
        {
            base.NoteOperation(operation);
            foreach (Parameter parameter in Parameters)
                parameter.Operation = operation;
        }

        public override bool RequiresGrid
        {
            get
            {
                foreach (Parameter parameter in Parameters)
                    if (parameter.RequiresGrid)
                        return true;
                return false;
            }
        }

        public override InputDuringStep RequiresInputGiven(ParameterBag bag)
        {
            foreach (Parameter parameter in Parameters)
                switch (parameter.RequiresInputGiven(bag))
                {
                    case InputDuringStep.SometimesOrAlways:
                        return InputDuringStep.SometimesOrAlways;
                    default:
                        // Do nothing
                        break;
                }
            return InputDuringStep.Never; 
        }

        public override void Accept(IStepVisitor visitor) => visitor.Visit(this);
    }
}
