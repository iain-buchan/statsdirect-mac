namespace StatsDirect.Templates
{
    /// <summary>
    /// For how long should the value of a parameter be preserved?
    /// </summary>
    public enum ParameterLifetime
    {
        /// <summary>
        /// The parameter is not preserved past the end of this operation
        /// </summary>
        Operation,
        /// <summary>
        /// The parameter is preserved for the session, but only for use within this operation
        /// </summary>
        SessionForThisOperation,
        /// <summary>
        /// The parameter is preserved for the session, for all operations that use the same named parameter.  Beware - the type is not checked!
        /// </summary>
        SessionForAllOperations
    }
}