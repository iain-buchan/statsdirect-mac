using System;

namespace StatsDirect.Expressions
{
    /// <summary>
    /// A representation of a part of an expression with two operands
    /// </summary>
    public class DyadicNode : INode
    {
        public INode Left { get; set; }
        public INode Right { get; set; }
        public DyadicOperator Operator { get; set; }

        public void Accept(IExpressionVisitor visitor)
        {
            visitor.Visit(this);
        }

        public InOutDataTypeDefinition InOut(DataType[] passedVariableTypes)
        {
            DyadicOperatorDefinition definition = DyadicOperatorRegistry.SoleInstance.DefinitionFor(Operator);
            // Find the first match, allowing for type promotion.
            DataType leftType = Left.DataType(passedVariableTypes);
            DataType rightType = Right.DataType(passedVariableTypes);
            foreach (InOutDataTypeDefinition candidate in definition.InOutDataTypeDefinitions)
                if (TypePromoter.CanBePromotedFromTo(leftType, candidate.InputTypes[0]) && TypePromoter.CanBePromotedFromTo(rightType, candidate.InputTypes[1]))
                    return candidate;
            throw new Exception("Type mismatch: " + Operator.ToString() + " doesn't expect parameters of type " + leftType.ToString() + " and " + rightType.ToString());
        }

        public DataType DataType(DataType[] passedVariableTypes)
        {
            return InOut(passedVariableTypes).ReturnType;
        }
    }
}
