using System;

namespace StatsDirect.Expressions
{
    public class MonadicNode : INode
    {
        public INode Node { get; set; }
        public MonadicOperator Operator { get; set; }

        public DataType DataType(DataType[] passedVariableTypes)
        {
            DataType inputType = Node.DataType(passedVariableTypes);
            MonadicOperatorDefinition definition = MonadicOperatorRegistry.SoleInstance.DefinitionFor(Operator);
            foreach (InOutDataTypeDefinition candidate in definition.InOutDataTypeDefinitions)
                if (TypePromoter.CanBePromotedFromTo(inputType, candidate.InputTypes[0]))
                    return candidate.ReturnType;
            // If we get here, our input type is illegal
            throw new Exception("Type mismatch: " + Operator.ToString() + " doesn't expect a parameter of type " + inputType.ToString());
        }

        public void Accept(IExpressionVisitor visitor)
        {
            visitor.Visit(this);
        }
    }
}
