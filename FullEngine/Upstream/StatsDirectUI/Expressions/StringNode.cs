namespace StatsDirect.Expressions
{
    public class StringNode : INode
    {
        public string Value { get; set; }

        public DataType DataType(DataType[] passedVariableTypes)
        {
                return Expressions.DataType.String;
        }

        public void Accept(IExpressionVisitor visitor)
        {
            visitor.Visit(this);
        }
    }
}
