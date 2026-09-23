namespace StatsDirect.Templates
{
    /// <summary>
    /// User interface communication between engine and host.  TODO: This needs a complete rework for a web-based interface.
    /// </summary>
    public interface IScriptEngineHost
    {
        /// <summary>
        /// Return a clean, initialised instance of a script engine capable of running code in the specified language.
        /// </summary>
        /// <returns></returns>
        IScriptEngine GetScriptEngine(string language);
    }
}
