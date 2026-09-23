using System;
using System.Collections.Generic;
using System.Text;

namespace StatsDirect.Expressions
{
    public class CSharpRenderer : IExpressionVisitor
    {
        private StringBuilder activeBuilder;
        private readonly Dictionary<ParserConstant, string> parserConstants;
        private readonly Dictionary<DataType, string> clrTypes;
        private DataType[] passedVariableTypes;
        private bool renderObjectArray;

        public CSharpRenderer()
        {
            parserConstants = new Dictionary<ParserConstant, string>
            {
                { ParserConstant.E, "Math.E" },
                { ParserConstant.False, "false" },
                { ParserConstant.Pi, "Math.PI" },
                { ParserConstant.True, "true" }
            };
            clrTypes = new Dictionary<DataType, string>
            {
                { DataType.Boolean, "bool" },
                { DataType.Double, "double" },
                { DataType.Integer, "int" },
                { DataType.String, "string" }
            };
        }

        public string Render(INode node, DataType[] passedVariableTypes, bool renderObjectArray, out DataType returnType)
        {
            this.passedVariableTypes = passedVariableTypes;
            this.renderObjectArray = renderObjectArray;
            returnType = node.DataType(passedVariableTypes);
            return Render(node);
        }

        private string Render(INode node)
        {
            activeBuilder = new StringBuilder();
            node.Accept(this);
            return activeBuilder.ToString();
        }

        private string RenderInNewContext(INode node)
        {
            StringBuilder savedSb = activeBuilder;
            activeBuilder = new StringBuilder();
            string rendered = Render(node);
            activeBuilder = savedSb;
            return rendered;
        }

        public void Visit(BooleanConstantNode node)
        {
            if (parserConstants.TryGetValue(node.Constant, out string cSharpValue))
            {
                activeBuilder.Append(cSharpValue);
                return;
            }
            throw new Exception("Unknown constant");
        }

        public void Visit(DoubleNode node)
        {
            // invariant culture and round-trip format: with a decimal comma in the Windows locale "7,5D" is not C#
            activeBuilder.Append(node.Value.ToString("R", System.Globalization.CultureInfo.InvariantCulture));
            activeBuilder.Append("D");
        }

        public void Visit(DoubleConstantNode node)
        {
            if (parserConstants.TryGetValue(node.Constant, out string cSharpValue))
            {
                activeBuilder.Append(cSharpValue);
                return;
            }
            throw new Exception("Unknown constant");
        }

        public void Visit(DyadicNode node)
        {
            DyadicOperatorDefinition definition = DyadicOperatorRegistry.SoleInstance.DefinitionFor(node.Operator);
            if (null == definition)
                throw new Exception("Unknown dyadic operation");

            InOutDataTypeDefinition typesAfterPromotion = node.InOut(passedVariableTypes);
            string lhs = RenderWithPossibleTypePromotion(node.Left, typesAfterPromotion.InputTypes[0]);
            string rhs = RenderWithPossibleTypePromotion(node.Right, typesAfterPromotion.InputTypes[1]);
            activeBuilder.Append(string.Format(definition.ClrFormat, lhs, rhs));
        }

        private string RenderWithPossibleTypePromotion(INode node, DataType typeAfterPromotion)
        {
            if (GetTypePromotionStrings(node.DataType(passedVariableTypes), typeAfterPromotion, out string prePromote, out string postPromote))
                return prePromote + RenderInNewContext(node) + postPromote;
            else
                return RenderInNewContext(node);
        }

        private static bool GetTypePromotionStrings(DataType from, DataType to, out string prePromote, out string postPromote)
        {
            // Integers can be promoted to doubles
            if (from == DataType.Integer && to == DataType.Double)
            {
                prePromote = "(double)(";
                postPromote = ")";
                return true;
            }
            // Everything else is either default or incompatible (which should have been caught earlier); either way, we don't write in anything special.
            prePromote = string.Empty;
            postPromote = string.Empty;
            return false;
        }

        public void Visit(FunctionNode node)
        {
            // Check for positional parameters after named ones.  We don't allow these, as we don't know what the position is.
            bool foundNamedParameter = false;
            foreach (Argument argument in node.Arguments)
            {
                if (null != argument)
                {
                    if (null == argument.ExplicitParameterName)
                    {
                        // Positional parameter
                        if (foundNamedParameter)
                            throw new Exception("Once you start using named parameters, all parameters afterwards must also be named.");
                    }
                    else
                    {
                        foundNamedParameter = true;
                    }
                }
            }

            FunctionDefinition functionDefinition = FunctionRegistry.SoleInstance.FunctionNamed(node.Name);
            if (null == functionDefinition)
                throw new Exception("No function named '" + node.Name + "' is known.");

            // Fill in parameter values using an array.  First set defaults, then overwrite with any positional parameters, then overwrite with any named parameters.
            List<ArgumentDefinition> defs = functionDefinition.ArgumentDefinitions;
            string[] parameterValues = new string[defs.Count];
            for (int i = 0; i < parameterValues.Length; i++)
                parameterValues[i] = defs[i].Default;
            for (int i = 0; i < node.Arguments.Count; i++)
            {
                Argument argument = node.Arguments[i];
                if (null != argument)
                {
                    if (null == argument.ExplicitParameterName)
                    {
                        // Positional
                        if (i >= parameterValues.Length)
                            throw new Exception("Too many arguments to " + functionDefinition);
                        parameterValues[i] = RenderInNewContext(argument.Node);
                    }
                    else
                    {
                        // Named
                        bool found = false;
                        for (int pos = 0; pos < defs.Count; pos++)
                        {
                            if (argument.ExplicitParameterName.Equals(defs[pos].Name))
                            {
                                found = true;
                                parameterValues[pos] = RenderInNewContext(argument.Node);
                                break;
                            }
                        }
                        if (!found)
                            throw new Exception(functionDefinition + "has no named argument called '" + argument.ExplicitParameterName + "'");
                    }
                }
            }

            // By the time we get here, all parameters should have been filled in.  If there are any remaining nulls, they don't have a default or a value from the caller, so fail.
            for (int i = 0; i < parameterValues.Length; i++)
            {
                if (null == parameterValues[i])
                    throw new Exception("You must supply a value for " + defs[i].Name + " in " + functionDefinition);
            }

            activeBuilder.Append(functionDefinition.ClrName);
            activeBuilder.Append("(");
            activeBuilder.Append(string.Join(", ", parameterValues));
            activeBuilder.Append(")");
        }

        public void Visit(IntegerNode node)
        {
            // written for the compiler, not for the reader: some regional settings (Norwegian, Swedish, Finnish) give a negative
            // number the typographic minus sign, which is not C#, so that -2 could not be evaluated at all
            activeBuilder.Append(node.Value.ToString(System.Globalization.CultureInfo.InvariantCulture));
        }

        public void Visit(MonadicNode node)
        {
            MonadicOperatorDefinition definition = MonadicOperatorRegistry.SoleInstance.DefinitionFor(node.Operator);
            activeBuilder.Append(definition.ClrName);
            activeBuilder.Append('(');
            node.Node.Accept(this);
            activeBuilder.Append(')');
        }

        public void Visit(StringNode node)
        {
            activeBuilder.Append('"');
            // C# strings embed \ as \\ and " as \"; ensure this is respected or we'll get parse errors or (worse) compilation of arbitrary code.
            // The backslash first, then the quote. In the other order the backslash just put before a quote was doubled, which
            // left the quote bare: the text after it was compiled as code.
            activeBuilder.Append(node.Value.Replace("\\", "\\\\").Replace("\"", "\\\""));
            activeBuilder.Append('"');
        }

        public void Visit(VariableNode node)
        {
            if (passedVariableTypes.Length < node.Index)
                throw new Exception("You can only use a variable that will be passed into the expression. You've used variable " + node.Index + ", but only " + passedVariableTypes.Length + " variable(s) will be passed in.");
            if (renderObjectArray)
            {
                // Variables in the expression are 1-based; variables in C# are 0-based.
                activeBuilder.Append('(');
                activeBuilder.Append(clrTypes[passedVariableTypes[node.Index - 1]]);
                activeBuilder.Append(')');
            }
            // Variables are passed in as a double array x[].
            activeBuilder.Append("x[");
            // Variables in the expression are 1-based; variables in C# are 0-based.
            activeBuilder.Append(node.Index - 1);
            activeBuilder.Append(']');
        }
    }
}
