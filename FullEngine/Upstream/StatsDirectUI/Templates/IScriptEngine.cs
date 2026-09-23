namespace StatsDirect.Templates
{
    /// <summary>
    /// The amountof top-and-tail in the code being presented to the engine
    /// </summary>
    public enum ScriptType
    {
        /// <summary>
        /// A single statement that returns a value
        /// </summary>
        Expression,
        /// <summary>
        /// A multiple-statement code fragment that returns a value
        /// </summary>
        Function,
        /// <summary>
        /// A multiple-statement code fragment that does not return a value
        /// </summary>
        Method,
        /// <summary>
        /// Arbitrary code that may be contained in multiple functions.
        /// One should be the entry point that accepts an ITemplateHost as the first parameter, a ParameterBag as the second, and returns a ParameterBag.
        /// </summary>
        MultipleMethods,
        /// <summary>
        /// A multiple-statement code fragment that takes a host, parameter bag and parameter and returns a bool
        /// </summary>
        Validator
    }

    public interface IScriptEngine
    {
        /// <summary>
        /// Runs the script's step entry point.  If it doesn't have one, throws an exception.
        /// </summary>
        /// <returns>Whatever the script returned</returns>
        object Run(string scriptLanguage, string code, ScriptType scriptType, ITemplateHost host, ParameterBag parameters, Parameter parameter, string entryPoint);

        /// <summary>
        /// Checks that the script could be run - for example, by compiling it.
        /// </summary>
        /// <returns>null if the check succeeded, a (hopefully informative) diagnostic message if the check failed</returns>
        string Check(string scriptLanguage, string code, ScriptType scriptType, string entryPoint);
    }
}
