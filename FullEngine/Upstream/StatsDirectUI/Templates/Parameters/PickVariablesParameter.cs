using System;
using System.Xml.Serialization;

namespace StatsDirect.Templates
{
    [Serializable]
    public sealed class PickVariablesParameter: Parameter
    {
        private bool preSelectVariables = true;
        private int minimumVariables = 1;
        private int maximumVariables = int.MaxValue;

        [XmlElement(ElementName = "preselect-variables")]
        public bool PreSelectVariables
        {
            get => preSelectVariables;
            set => preSelectVariables = value;
        }

        [XmlElement(ElementName = "minimum-variables")]
        public int MinimumVariables
        {
            get => minimumVariables;
            set => minimumVariables = value;
        }

        [XmlElement(ElementName = "maximum-variables")]
        public int MaximumVariables
        {
            get => maximumVariables;
            set => maximumVariables = value;
        }

        [XmlElement(ElementName = "parameter-name")]
        public string ParameterName { get; set; }

        [XmlElement(ElementName = "label-as")]
        public Expression LabelAsExpression { get; set; }

        [XmlIgnore]
        public bool HasLabelAs => null != LabelAsExpression && null != LabelAsExpression.Body;

        public string LabelAs(ITemplateProcessor processor, ParameterBag parameters, int zeroBasedVariableNumber)
        {
            if (!HasLabelAs)
                return "Variable " + (zeroBasedVariableNumber + 1).ToString();
            ParameterBag parametersIncludingVariableNumber = parameters.Copy();
            parametersIncludingVariableNumber.AddInput("variableNumber", zeroBasedVariableNumber);
            return (string)processor.Evaluate(LabelAsExpression, parametersIncludingVariableNumber);
        }

        public override InputDuringStep RequiresInputGiven(ParameterBag parameters)
        {
            return MustRequest || !parameters.ContainsKey(Name) ? InputDuringStep.SometimesOrAlways : InputDuringStep.Never;
        }

        public override void Accept(IParameterVisitor visitor)
        {
            visitor.Visit(this);
        }

        public override ParameterBag AllDefaults(ITemplateProcessor processor, ParameterBag context)
        {
            return new ParameterBag();
        }
    }
}
