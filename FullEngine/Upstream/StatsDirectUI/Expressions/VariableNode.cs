using System;

namespace StatsDirect.Expressions
{
    public class VariableNode : INode
    {
        public int Index { get; set; }

        public DataType DataType(DataType[] passedVariableTypes)
        {
            // Index is 1-based, array indices in C# (hence passedVariableTypes) start from 0.
            if (passedVariableTypes.Length < Index)
                throw new Exception("You can only use a variable that will be passed into the expression. You've used variable " + Index + ", but only " + passedVariableTypes.Length + " variable(s) will be passed in.");
            return passedVariableTypes[Index - 1];
        }

        public void Accept(IExpressionVisitor visitor)
        {
            visitor.Visit(this);
        }
    }
}
