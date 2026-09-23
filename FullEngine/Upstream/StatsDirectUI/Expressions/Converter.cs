using System;
using Antlr4.Runtime;
using System.Text;
using System.Globalization;

namespace StatsDirect.Expressions
{
    public class Converter
    {
        /// <param name="invariantNotation">true for a formula that ships with the program, which is written with a decimal point whatever the regional settings</param>
        public static bool IsValid(string expr, bool invariantNotation = false)
        {
            AntlrInputStream input = new(expr);
            StatsDirectExpressionLexer lexer = new(input)
            {
                Separators = invariantNotation ? StatsDirectExpressionLexer.SeparatorStructure.CommaDot : GetSeparatorStructure()
            };
            CommonTokenStream tokenStream = new(lexer);
            StatsDirectExpressionParser parser = new(tokenStream);
            StringBuilder errorBuilder = new();
            parser.RemoveErrorListeners();
            parser.AddErrorListener(new AccumulateErrors(errorBuilder));
            StatsDirectExpressionParser.RContext retval;
            try
            {
                retval = parser.r();
            }
            catch (Exception)
            {
                // the parser's own actions throw for such things as a name that is not a variable ("abc"): that is an invalid
                // expression, not a reason for the validation itself to fail
                return false;
            }
            if (parser.NumberOfSyntaxErrors > 0)
                return false;

            // The parser seems to dislike recognising EOF (for some reason - TODO: find out why) so instead test that we're at EOF at the end of the parse
            if (!"<EOF>".Equals(parser.CurrentToken.Text))
                return false;
            if (null == retval || null == retval.node)
                return false;
            return true;
        }

        /// <param name="invariantNotation">true for a formula that ships with the program, which is written with a decimal point whatever the regional settings</param>
        public static string ConvertToCSharp(string expr, DataType[] passedVariableTypes, bool inputsAreObjects, out DataType resultType, bool invariantNotation = false)
        {
            AntlrInputStream input = new(expr);
            StatsDirectExpressionLexer lexer = new(input)
            {
                Separators = invariantNotation ? StatsDirectExpressionLexer.SeparatorStructure.CommaDot : GetSeparatorStructure()
            };
            CommonTokenStream tokenStream = new(lexer);
            StatsDirectExpressionParser parser = new(tokenStream);
            StringBuilder errorBuilder = new();
            parser.RemoveErrorListeners();
            parser.AddErrorListener(new AccumulateErrors(errorBuilder));
            StatsDirectExpressionParser.RContext retval = parser.r();
            if (parser.NumberOfSyntaxErrors > 0)
                throw new Exception("Couldn't parse your expression: " + errorBuilder);

            // The parser seems to dislike recognising EOF (for some reason - TODO: find out why) so instead test that we're at EOF at the end of the parse
            if (!"<EOF>".Equals(parser.CurrentToken.Text))
                throw new Exception("Couldn't parse your expression: syntax error near \"" + parser.CurrentToken.Text + "\"");
            if (null == retval || null == retval.node)
                throw new Exception("Syntax error");
            return new CSharpRenderer().Render(retval.node, passedVariableTypes, inputsAreObjects, out resultType);
        }

        private static StatsDirectExpressionLexer.SeparatorStructure GetSeparatorStructure()
        {
            CultureInfo c = CultureInfo.CurrentCulture;
            if (".".Equals(c.NumberFormat.NumberDecimalSeparator))
            {
                if (",".Equals(c.NumberFormat.NumberGroupSeparator))
                    return StatsDirectExpressionLexer.SeparatorStructure.CommaDot;
                else if (" ".Equals(c.NumberFormat.NumberGroupSeparator))
                    return StatsDirectExpressionLexer.SeparatorStructure.SpaceDot;
                else
                {
                    // TODO: Other formats
                    return StatsDirectExpressionLexer.SeparatorStructure.CommaDot;
                }
            }
            else if (",".Equals(c.NumberFormat.NumberDecimalSeparator))
            {
                return StatsDirectExpressionLexer.SeparatorStructure.DotComma;
            }
            else
            {
                // TODO: How to handle other locales?
                return StatsDirectExpressionLexer.SeparatorStructure.CommaDot;
            }
        }

        private class AccumulateErrors : IAntlrErrorListener<IToken>
        {
            private readonly StringBuilder sb;

            public AccumulateErrors(StringBuilder sb)
            {
                this.sb = sb;
            }

            public void SyntaxError(IRecognizer recognizer, IToken offendingSymbol, int line, int charPositionInLine, string msg, RecognitionException e)
            {
                sb.AppendLine("Line " + line + ", character " + charPositionInLine + ": " + msg);
                if (offendingSymbol == null || sb.ToString().Contains("thousands separators"))
                    return;
                bool decimalComma = ",".Equals(CultureInfo.CurrentCulture.NumberFormat.NumberDecimalSeparator);
                string text = offendingSymbol.Text ?? string.Empty;
                if (!decimalComma && ",".Equals(text))
                {
                    // a comma where none is expected is usually a thousands separator, which an expression does not take
                    sb.AppendLine("Numbers are typed without thousands separators (1234.5). A comma or a semicolon separates the arguments of a function.");
                }
                else if (decimalComma && (".".Equals(text) || text.StartsWith(",", StringComparison.Ordinal)))
                {
                    // a point is the usual thousands separator here; and a comma straight before a digit begins a number (",5" is 0,5),
                    // so that X1,5 is two values side by side
                    sb.AppendLine("Numbers are typed without thousands separators (1234,5). The comma is the decimal separator, so separate the arguments of a function with a semicolon, or put a space after the comma: PT(X1; 5) or PT(X1, 5).");
                }
            }
        }
    }
}