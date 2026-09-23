namespace StatsDirect.Templates
{
    public class Builtin : IBuiltin
    {
        private readonly BuiltinFunction func;

        public Builtin(string name, BuiltinFunction func)
        {
            Name = name;
            this.func = func;
        }

        StepOutput IBuiltin.Invoke(ITemplateHost host, ParameterBag parameters) => func(host, parameters);

        InputDuringStep IMightRequireInput.RequiresInputGiven(ParameterBag parameters) => InputDuringStep.SometimesOrAlways;

        public string Name { get; }
    }
}
