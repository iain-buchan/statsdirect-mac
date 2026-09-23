using System.Collections.Generic;

namespace StatsDirect.Templates
{
    /// <summary>
    /// An interface for parameter memory.
    /// </summary>
    public interface ISession
    {
        /// <summary>
        /// A location to store parameters that will persist as long as the host does and are kept per-operation.
        /// </summary>
        IDictionary<string, ParameterBag> SessionParametersPerOperation { get; }

        /// <summary>
        /// A location to store parameters that will persist as long as the host does and are common across all operations that use the same name for their parameters.
        /// </summary>
        ParameterBag SessionParametersAcrossOperations { get; }
    }
}
