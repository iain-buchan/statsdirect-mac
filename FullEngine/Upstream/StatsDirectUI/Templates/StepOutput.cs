using System;

namespace StatsDirect.Templates
{
    /// <summary>
    /// At least the thing that is handed out of builtins. TODO: Is this also the thing that is handed between parts of a step?  Between UI and template processing?
    /// </summary>
    /// <remarks>Immutable.</remarks>
    public class StepOutput
    {
        public ParameterBag ParameterBag { get; }

        public StepOutput(ParameterBag parameterBag)
        {
            ParameterBag = parameterBag;
        }

        internal static StepOutput Empty() => new(new ParameterBag());
    }
}
