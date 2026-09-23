namespace StatsDirect.Expressions
{
    public class DoubleConstantNode : INode
    {
        public ParserConstant Constant { get; set; }

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
