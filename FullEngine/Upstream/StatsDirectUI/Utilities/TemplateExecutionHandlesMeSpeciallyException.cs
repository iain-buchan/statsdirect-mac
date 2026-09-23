using System;
using System.Runtime.Serialization;

namespace StatsDirect.Utilities
{
    /// <summary>
    /// A marker for exceptions that are used within StatsDirect to unwind the stack out of operations in a controlled way.
    /// These should not necessarily be shown to an end user as errors; look at the catch(es) of this for the special handling.
    /// </summary>
    [Serializable]
    public abstract class TemplateExecutionHandlesMeSpeciallyException : Exception
    {
        protected TemplateExecutionHandlesMeSpeciallyException(string message)
            : base(message)
        {
        }

        protected TemplateExecutionHandlesMeSpeciallyException(string message, Exception innerException)
            : base(message, innerException)
        {
        }

        protected TemplateExecutionHandlesMeSpeciallyException()
        {
        }
    }
}