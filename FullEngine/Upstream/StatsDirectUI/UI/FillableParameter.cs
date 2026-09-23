using StatsDirect.Templates;

namespace StatsDirect.UI
{
    /// <summary>
    /// A shim to allow fillables to be passed around as Parameters, and hence filled in by the UI.
    /// </summary>
    public class FillableParameter : Parameter
    {
        public FillableParameter(string name, IFillable fillable)
        {
            Name = name;
            Fillable = fillable;
        }

        public IFillable Fillable { get; }

        public override InputDuringStep RequiresInputGiven(ParameterBag parameters)
        {
            return MustRequest || null != Name && null != parameters && !parameters.ContainsKey(Name) ? InputDuringStep.SometimesOrAlways : InputDuringStep.Never;
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
