using System.Collections.Generic;
using System.Linq;

namespace StatsDirect.Expressions
{
    public class DyadicOperatorDefinition
    {
        public DyadicOperator Operator { get; }
        public string ClrFormat { get; }
        public List<InOutDataTypeDefinition> InOutDataTypeDefinitions { get; }

        public DyadicOperatorDefinition(DyadicOperator op, string clrFormat, IEnumerable<InOutDataTypeDefinition> inOutDataTypeDefinitions)
        {
            Operator = op;
            ClrFormat = clrFormat;

            if (null == inOutDataTypeDefinitions)
                InOutDataTypeDefinitions = new List<InOutDataTypeDefinition>();
            else
                InOutDataTypeDefinitions = new List<InOutDataTypeDefinition>(inOutDataTypeDefinitions);
        }

        public override string ToString()
        {
            return Operator.ToString() + "(" + string.Join(", ", InOutDataTypeDefinitions.Select(x=>x.ToString()).ToArray()) + ")";
        }
    }
}
