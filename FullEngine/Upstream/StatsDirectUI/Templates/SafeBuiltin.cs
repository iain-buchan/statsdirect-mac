namespace StatsDirect.Templates
{
    public class SafeBuiltin : IBuiltin
    {
        private readonly SafeBuiltinFunction func;

        public SafeBuiltin(string name, SafeBuiltinFunction func)
        {
            Name = name;
            this.func = func;
        }

        StepOutput IBuiltin.Invoke(ITemplateHost host, ParameterBag parameters)
        {
            return func(host, parameters);
        }

        InputDuringStep IMightRequireInput.RequiresInputGiven(ParameterBag parameters)
        {
            return InputDuringStep.Never;
        }

        public string Name { get; }
    }
}
