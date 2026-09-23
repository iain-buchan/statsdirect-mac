namespace StatsDirect.Expressions
{
    public class DoubleNode : INode
    {
        public double Value { get; set; }

        public DataType DataType(DataType[] passedVariableTypes)
        {
            return Expressions.DataType.Double;
        }

        public void Accept(IExpressionVisitor visitor)
        {
            visitor.Visit(this);
        }
    }
}
