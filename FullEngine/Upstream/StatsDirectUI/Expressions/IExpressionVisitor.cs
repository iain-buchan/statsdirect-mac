namespace StatsDirect.Expressions
{
    public interface IExpressionVisitor
    {
        void Visit(BooleanConstantNode node);
        void Visit(DoubleNode node);
        void Visit(DoubleConstantNode node);
        void Visit(DyadicNode node);
        void Visit(FunctionNode node);
        void Visit(IntegerNode node);
        void Visit(MonadicNode node);
        void Visit(StringNode node);
        void Visit(VariableNode node);
    }
}
