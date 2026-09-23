namespace StatsDirect.Expressions
{
    public interface INode
    {
        void Accept(IExpressionVisitor visitor);
        DataType DataType(DataType[] passedVariableTypes);
    }
}
