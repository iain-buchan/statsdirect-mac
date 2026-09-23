using Antlr4.Runtime;
using System.Text;

namespace StatsDirect.Creole
{
    public static class CreoleReader
    {
        public static bool IsValid(string expr, out string errors)
        {
            CreoleParser parser = new(new CommonTokenStream(new CreoleLexer(new AntlrInputStream(expr))));
            StringBuilder errorBuilder = AccumulateErrors.Wrap(parser);
            CreoleParser.DocumentContext retval = parser.document();
            if (parser.NumberOfSyntaxErrors > 0)
            {
                errors = errorBuilder.ToString();
                return false;
            }

            if (null == retval)
            {
                errors = "No specific syntax error, but the parser didn't return a node";
                return false;
            }
            errors = null;
            return true;
        }

        public static ICreole<TResult> Parse<TResult>(string expr, out string errors)
        {
            CreoleParser parser = new(new CommonTokenStream(new CreoleLexer(new AntlrInputStream(expr))));
            StringBuilder errorBuilder = AccumulateErrors.Wrap(parser);
            CreoleParser.DocumentContext retval = parser.document();
            if (parser.NumberOfSyntaxErrors > 0)
            {
                errors = errorBuilder.ToString();
                return null;
            }

            if (null == retval)
            {
                errors = "No specific syntax error, but the parser didn't return a node";
                return null;
            }
            errors = null;
            return retval.Accept(new CreoleParserVisitor<TResult>());
        }

        private class AccumulateErrors : IAntlrErrorListener<IToken>
        {
            private readonly StringBuilder sb;

            public static StringBuilder Wrap(Parser parser)
            {
                StringBuilder errorBuilder = new();
                parser.RemoveErrorListeners();
                parser.AddErrorListener(new AccumulateErrors(errorBuilder));
                return errorBuilder;
            }

            public AccumulateErrors(StringBuilder sb)
            {
                this.sb = sb;
            }

            public void SyntaxError(IRecognizer recognizer, IToken offendingSymbol, int line, int charPositionInLine, string msg, RecognitionException e)
            {
                sb.AppendLine("Line " + line + ", character " + charPositionInLine + ": " + msg);
            }
        }
    }
}