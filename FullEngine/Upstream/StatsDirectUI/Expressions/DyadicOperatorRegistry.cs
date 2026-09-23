using System.Collections.Generic;

namespace StatsDirect.Expressions
{
    /// <remarks>Singleton.</remarks>
    public class DyadicOperatorRegistry
    {
        private readonly Dictionary<DyadicOperator, DyadicOperatorDefinition> definitions;

        private static DyadicOperatorRegistry soleInstance;

        public static DyadicOperatorRegistry SoleInstance => soleInstance ?? (soleInstance = new DyadicOperatorRegistry());

        private DyadicOperatorRegistry()
        {
            // A few useful parameters that can be re-used
            InOutDataTypeDefinition bbb = new(DataType.Boolean, new[] { DataType.Boolean, DataType.Boolean });
            InOutDataTypeDefinition bdd = new(DataType.Boolean, new[] { DataType.Double, DataType.Double });
            InOutDataTypeDefinition bii = new(DataType.Boolean, new[] { DataType.Integer, DataType.Integer });
            InOutDataTypeDefinition bss = new(DataType.Boolean, new[] { DataType.String, DataType.String });
            InOutDataTypeDefinition ddd = new(DataType.Double, new[] { DataType.Double, DataType.Double });
            InOutDataTypeDefinition iii = new(DataType.Integer, new[] { DataType.Integer, DataType.Integer });
            InOutDataTypeDefinition ssb = new(DataType.String, new[] { DataType.String, DataType.Boolean });
            InOutDataTypeDefinition ssd = new(DataType.String, new[] { DataType.String, DataType.Double });
            InOutDataTypeDefinition ssi = new(DataType.String, new[] { DataType.String, DataType.Integer });
            InOutDataTypeDefinition sss = new(DataType.String, new[] { DataType.String, DataType.String });
            definitions = new Dictionary<DyadicOperator, DyadicOperatorDefinition>();
            AddAll(new[]
            {
                new DyadicOperatorDefinition(DyadicOperator.IntegerDivide,       "SDMath.Idiv({0}, {1})",       new[] { ddd }), // Idiv returns a double: typed as Integer it made a comparison of a whole number with an integer division throw at run time
                new DyadicOperatorDefinition(DyadicOperator.Pow,                 "Math.Pow({0}, {1})",          new[] { ddd }),
                new DyadicOperatorDefinition(DyadicOperator.Add,                 "({0}) + ({1})",               new[] { iii, ddd, sss, ssd, ssi, ssb }),
                new DyadicOperatorDefinition(DyadicOperator.And,                 "({0}) && ({1})",              new[] { bbb }),
                new DyadicOperatorDefinition(DyadicOperator.Divide,              "({0}) / ({1})",               new[] { ddd }),
                new DyadicOperatorDefinition(DyadicOperator.Modulo,              "({0}) % ({1})",               new[] { ddd }),
                new DyadicOperatorDefinition(DyadicOperator.Multiply,            "({0}) * ({1})",               new[] { ddd }),
                new DyadicOperatorDefinition(DyadicOperator.Or,                  "({0}) || ({1})",              new[] { bbb }),
                new DyadicOperatorDefinition(DyadicOperator.Subtract,            "({0}) - ({1})",               new[] { iii, ddd }),
                new DyadicOperatorDefinition(DyadicOperator.Equal,               "({0}).CompareTo({1}) == 0",   new[] { bbb, bii, bdd, bss }),
                new DyadicOperatorDefinition(DyadicOperator.GreaterThan,         "({0}).CompareTo({1}) > 0",    new[] { bii, bdd, bss }),
                new DyadicOperatorDefinition(DyadicOperator.GreaterThanOrEqual,  "({0}).CompareTo({1}) >= 0",   new[] { bii, bdd, bss }),
                new DyadicOperatorDefinition(DyadicOperator.LessThan,            "({0}).CompareTo({1}) < 0",    new[] { bii, bdd, bss }),
                new DyadicOperatorDefinition(DyadicOperator.LessThanOrEqual,     "({0}).CompareTo({1}) <= 0",   new[] { bii, bdd, bss }),
                new DyadicOperatorDefinition(DyadicOperator.NotEqual,            "({0}).CompareTo({1}) != 0",   new[] { bbb, bii, bdd, bss })
            });

        }

        private void AddAll(IEnumerable<DyadicOperatorDefinition> definitions)
        {
            foreach (DyadicOperatorDefinition definition in definitions)
                this.definitions.Add(definition.Operator, definition);
        }

        public DyadicOperatorDefinition DefinitionFor(DyadicOperator op)
        {
            definitions.TryGetValue(op, out DyadicOperatorDefinition definition);
            return definition;
        }
    }
}
