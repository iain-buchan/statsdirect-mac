using StatsDirect.Templates;

namespace StatsDirect.UI
{
    /// <summary>
    /// A shim to allow chart options to be passed around as Parameters, and hence filled in by the UI
    /// </summary>
    public class ChartOptionsParameter : Parameter
    {
        private readonly Charting.ChartDefinition chartDefinition;

        public ChartOptionsParameter(string name, Charting.ChartDefinition chartDefinition)
        {
            Name = name;
            this.chartDefinition = chartDefinition;
        }

        public Charting.ChartDefinition ChartDefinition => chartDefinition;

        public override InputDuringStep RequiresInputGiven(ParameterBag parameters)
        {
            return InputDuringStep.SometimesOrAlways;
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
