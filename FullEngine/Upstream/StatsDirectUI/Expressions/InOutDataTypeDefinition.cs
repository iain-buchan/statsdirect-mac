using System.Collections.Generic;
using System.Linq;

namespace StatsDirect.Expressions
{
    public class InOutDataTypeDefinition
    {
        public DataType ReturnType { get; }
        public DataType[] InputTypes { get; }

        public InOutDataTypeDefinition(DataType returnType, IEnumerable<DataType> inputTypes)
        {
            ReturnType = returnType;
            InputTypes = inputTypes.ToArray();
        }
    }
}