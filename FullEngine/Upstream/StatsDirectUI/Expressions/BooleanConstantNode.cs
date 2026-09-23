namespace StatsDirect.Expressions
{
    public class BooleanConstantNode : INode
    {
        public ParserConstant Constant { get; set; }

        public DataType DataType(DataType[] passedVariableTypes)
        {
            return Expressions.DataType.Boolean;
        }

        public void Accept(IExpressionVisitor visitor)
        {
            visitor.Visit(this);
        }
    }
}
