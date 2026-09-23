using StatsDirect.Data;

namespace StatsDirect.Templates
{
    public static class VariableFactory
    {
        /// <summary>
        /// Returns a new variable suitable for holding values produced from an expression of output type dataType.  If there's no suitable variable type, returns null.
        /// </summary>
        /// <param name="dataType"></param>
        /// <returns></returns>
        public static IVariable EmptyVariableFor(Expressions.DataType dataType)
        {
            switch (dataType)
            {
                case Expressions.DataType.Boolean:
                    return new BooleanVariable();
                case Expressions.DataType.Double:
                case Expressions.DataType.Integer:
                    return new DoubleVariable();
                case Expressions.DataType.String:
                    return new StringVariable();
            }
            // If we get here, nothing matched.
            return null;
        }
    }
}
