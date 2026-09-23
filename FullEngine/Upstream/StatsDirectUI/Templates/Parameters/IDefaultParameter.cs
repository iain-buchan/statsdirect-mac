namespace StatsDirect.Templates
{
    /// <summary>
    /// Defines what must be implemented if this parameter is to have defaults.
    /// </summary>
    /// <typeparam name="T">The type of the default parameter.  This must be a value type (integer, boolean, double, or a structure - something that doesn't already allow a null pointer).</typeparam>
    interface IDefaultParameter<T> where T : struct
    {
        /// <summary>
        /// true iff the parameter defines a default.
        /// </summary>
        bool HasDefaultValue { get; }

        /// <summary>
        /// The default value for this parameter, or null for no default.
        /// </summary>
        T? DefaultValue(ITemplateProcessor processor, ParameterBag parameters);
    }
}
