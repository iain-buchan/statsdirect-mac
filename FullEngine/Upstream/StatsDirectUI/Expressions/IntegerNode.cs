namespace StatsDirect.Expressions
{
    public class IntegerNode : INode
    {
        public int Value { get; set; }

        public DataType DataType(DataType[] passedVariableTypes)
        {
            return Expressions.DataType.Integer;
        }

        public void Accept(IExpressionVisitor visitor)
        {
            visitor.Visit(this);
        }
    }
}
