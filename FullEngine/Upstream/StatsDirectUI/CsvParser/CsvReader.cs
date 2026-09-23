using System;
using System.Collections.Generic;
using System.Text;
using Antlr4.Runtime;
using System.IO;

namespace StatsDirect.CsvParser
{
    class CsvReader
    {
            public static List<List<string>> Read(TextReader csvReader)
            {
                AntlrInputStream input = new(csvReader);
                CsvLexer lexer = new(input);
                CommonTokenStream tokenStream = new(lexer);
                CsvParser parser = new(tokenStream);
                StringBuilder errorBuilder = new();
                parser.RemoveErrorListeners();
                parser.AddErrorListener(new AccumulateErrors(errorBuilder));
                CsvParser.FileContext fileContext = parser.file();
                if (parser.NumberOfSyntaxErrors > 0)
                    throw new Exception("Invalid CSV file: " + errorBuilder);

                // The parser seems to dislike recognising EOF (for some reason - TODO: find out why) so instead test that we're at EOF at the end of the parse
                if (!"<EOF>".Equals(parser.CurrentToken.Text))
                    throw new Exception("Couldn't parse your expression: syntax error near \"" + parser.CurrentToken.Text + "\"");
                if (null == fileContext || null == fileContext.retval)
                    throw new Exception("Syntax error");
                return fileContext.retval;
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
                }
            }
        }
    }
