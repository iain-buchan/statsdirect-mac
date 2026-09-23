using System.Collections.Generic;
using System.Linq;

namespace StatsDirect.Expressions
{
    public class FunctionDefinition
    {
        public string Name { get; }
        public string ClrName { get; }
        public List<ArgumentDefinition> ArgumentDefinitions { get; }
        public DataType DataType { get; }

        public FunctionDefinition(string name, DataType dataType, string clrName, IEnumerable<ArgumentDefinition> argumentDefinitions)
        {
            Name = name;
            ClrName = clrName;
            DataType = dataType;

            ArgumentDefinitions = null == argumentDefinitions
                ? new List<ArgumentDefinition>()
                : new List<ArgumentDefinition>(argumentDefinitions);
        }

        public override string ToString()
        {
            return Name + "(" + string.Join(", ", ArgumentDefinitions.Select(x=>x.ToString()).ToArray()) + ")";
        }
    }
}
