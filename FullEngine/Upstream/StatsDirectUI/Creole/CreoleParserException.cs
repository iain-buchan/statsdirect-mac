using System;
using System.Runtime.Serialization;

namespace StatsDirect.Creole
{
    [Serializable]
    public class CreoleParserException : Exception
    {
        public CreoleParserException()
        {
        }

        public CreoleParserException(string message) : base(message)
        {
        }

        public CreoleParserException(string message, Exception innerException) : base(message, innerException)
        {
        }
    }
}