using System;
using System.Xml.Serialization;

namespace StatsDirect.Templates
{
    [Serializable]
    public sealed class BuiltinStep: Step
    {
        private string functionName;

        [XmlAttribute(AttributeName = "function-name")]
        public string FunctionName
        {
            get => functionName;
            set => functionName = value;
        }

        public override void Accept(IStepVisitor visitor)
        {
            visitor.Visit(this);
        }

        public override StepOutput ExecuteInternal(ITemplateProcessor processor, ParameterBag parameters)
        {
            return processor.ExecuteInternal(this, parameters);
        }

        public override InputDuringStep RequiresInputGiven(ParameterBag parameters)
        {
            return BuiltinRegistry.SoleInstance.Builtin(functionName).RequiresInputGiven(parameters);
        }
    }
}
