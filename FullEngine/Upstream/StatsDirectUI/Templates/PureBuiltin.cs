namespace StatsDirect.Templates
{
    public class PureBuiltin : IBuiltin
    {
        readonly string name;
        private readonly PureBuiltinFunction func;

        public PureBuiltin(string name, PureBuiltinFunction func)
        {
            this.name = name;
            this.func = func;
        }

        StepOutput IBuiltin.Invoke(ITemplateHost host, ParameterBag parameters)
        {
            return func(parameters);
        }

        InputDuringStep IMightRequireInput.RequiresInputGiven(ParameterBag parameters)
        {
            return InputDuringStep.Never;
        }

        string IBuiltin.Name => name;
    }
}
