using System.Collections.Generic;
using System.Linq;

namespace StatsDirect.Expressions
{
    public class MonadicOperatorDefinition
    {
        public MonadicOperator Operator { get; }
        public string ClrName { get; }
        public List<InOutDataTypeDefinition> InOutDataTypeDefinitions { get; }

        public MonadicOperatorDefinition(MonadicOperator op, string clrName, IEnumerable<InOutDataTypeDefinition> inOutDataTypeDefinitions)
        {
            Operator = op;
            ClrName = clrName;

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
