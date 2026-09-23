namespace StatsDirect.Expressions
{
    public class FunctionNode : INode
    {
        public string Name { get; set; }
        public Arguments Arguments { get; set; }

        public DataType DataType(DataType[] passedVariableTypes)
        {
            FunctionDefinition definition = FunctionRegistry.SoleInstance.FunctionNamed(Name);
            // the same words as the renderer uses: a mistyped name used to be reported as "Object reference not set to an instance of an object"
            if (null == definition)
                throw new System.Exception("No function named '" + Name + "' is known.");
            return definition.DataType;
        }

        public void Accept(IExpressionVisitor visitor)
        {
            visitor.Visit(this);
        }
    }
}
