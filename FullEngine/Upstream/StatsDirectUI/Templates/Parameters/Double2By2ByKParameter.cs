using System;

namespace StatsDirect.Templates
{
    [Serializable]
    public sealed class Double2By2ByKParameter: Parameter
    {
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
