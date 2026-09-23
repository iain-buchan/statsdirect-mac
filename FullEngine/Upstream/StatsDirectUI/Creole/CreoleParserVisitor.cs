using System;
using System.Collections.Generic;
using System.Linq;
using Antlr4.Runtime.Tree;

namespace StatsDirect.Creole
{
    class CreoleParserVisitor<TResult> : ICreoleParserVisitor<ICreole<TResult>>
    {
        private static readonly IDictionary<string, char> NamedEntityTranslations = new Dictionary<string, char>
        {
            { "lt", '<' },
            { "gt", '>' },
            { "amp", '&' },
            { "quot", '"' },
            { "apos", '\'' },
            { "copy", '©' },
            { "reg", '®' },
            { "trade", '™' }
        };
        ICreole<TResult> IParseTreeVisitor<ICreole<TResult>>.Visit(IParseTree tree) => throw new NotImplementedException();

        ICreole<TResult> ICreoleParserVisitor<ICreole<TResult>>.VisitAttribute(CreoleParser.AttributeContext context)
        {
            string rawValue = context.value.Text;
            return new CreoleAttribute<TResult> { Name = context.name.Text, Value = rawValue[1..^1] };
        }

        ICreole<TResult> ICreoleParserVisitor<ICreole<TResult>>.VisitAttributes(CreoleParser.AttributesContext context)
        {
            return new CreoleAttributes<TResult>(context.attribute().Select(attribute => (CreoleAttribute<TResult>)attribute.Accept(this)).ToDictionary(creoleAttribute => (creoleAttribute).Name));
        }

        ICreole<TResult> ICreoleParserVisitor<ICreole<TResult>>.VisitBlock(CreoleParser.BlockContext context)
        {
            CreoleAttributes<TResult> attributes = (CreoleAttributes<TResult>)context.attributes().Accept(this);

            if (!attributes.Attributes.TryGetValue("name", out CreoleAttribute<TResult> nameAttribute))
                throw new CreoleParserException("<block> requires name attribute, which was not provided");
            string name = nameAttribute.Value;

            string separator = string.Empty;
            if (attributes.Attributes.TryGetValue("separator", out CreoleAttribute<TResult> separatorAttribute))
                separator = separatorAttribute.Value;

            return new CreoleBlock<TResult>
            {
                Contents = context.content().Accept(this),
                Name = name,
                Separator = separator
            };
        }

        ICreole<TResult> ICreoleParserVisitor<ICreole<TResult>>.VisitChardata(CreoleParser.ChardataContext context)
        {
            // Abstract: Chardata is always parsed as SignificantText.
            throw new NotImplementedException();
        }

        ICreole<TResult> IParseTreeVisitor<ICreole<TResult>>.VisitChildren(IRuleNode node) => throw new NotImplementedException();

        ICreole<TResult> ICreoleParserVisitor<ICreole<TResult>>.VisitCompoundSubstitution(CreoleParser.CompoundSubstitutionContext context)
        {
            return new CreoleSubstitution<TResult>
            {
                Path = context.path.Text,
                Format = context.format.Text[1..] // Token includes the separating colon
            };
        }

        ICreole<TResult> ICreoleParserVisitor<ICreole<TResult>>.VisitContent(CreoleParser.ContentContext context)
        {
            if (0 == context.ChildCount)
                return null;
            if (1 == context.ChildCount)
                return context.children[0].Accept(this);
            return new CreoleList<TResult>(context.children.Select(child => child.Accept(this)));
        }

        ICreole<TResult> ICreoleParserVisitor<ICreole<TResult>>.VisitDecimalEntityBody(CreoleParser.DecimalEntityBodyContext context)
        {
            // Contained text will be # then a string of decimal digits, which should be parsed as a character value.
            return new CreoleEntity<TResult>()
            {
                Value = (char)int.Parse(context.GetText()[1..])
            };
        }

        ICreole<TResult> ICreoleParserVisitor<ICreole<TResult>>.VisitDocument(CreoleParser.DocumentContext context)
        {
            CreoleParser.ElementContext[] elements = context.element();
            if (0 == elements.Length)
                return null;
            if (1 == elements.Length)
                return elements[0].Accept(this);
            return new CreoleList<TResult>(elements.Select(element => element.Accept(this)));
        }

        ICreole<TResult> ICreoleParserVisitor<ICreole<TResult>>.VisitElement(CreoleParser.ElementContext context)
        {
            // Abstract in the parser - see CreoleParser.g4.
            throw new NotImplementedException();
        }

        ICreole<TResult> ICreoleParserVisitor<ICreole<TResult>>.VisitEntity(CreoleParser.EntityContext context) => context.body.Accept(this);

        ICreole<TResult> ICreoleParserVisitor<ICreole<TResult>>.VisitEntityBody(CreoleParser.EntityBodyContext context)
        {
            // Abstract in the parser - DecimalEntityBody, HexEntityBody, or NamedEntityBody will always be used.
            throw new NotImplementedException();
        }

        ICreole<TResult> IParseTreeVisitor<ICreole<TResult>>.VisitErrorNode(IErrorNode node) => throw new NotImplementedException();

        ICreole<TResult> ICreoleParserVisitor<ICreole<TResult>>.VisitFormatting(CreoleParser.FormattingContext context)
        {
            return new CreoleFormatting<TResult>()
            {
                Contents = context.content().Accept(this),
                Format = context.tag.Text
            };
        }

        ICreole<TResult> ICreoleParserVisitor<ICreole<TResult>>.VisitHexEntityBody(CreoleParser.HexEntityBodyContext context)
        {
            // Contained text will be #x then a string of hex digits, which should be parsed as a character value.
            return new CreoleEntity<TResult>()
            {
                Value = (char)int.Parse(context.GetText()[2..], System.Globalization.NumberStyles.HexNumber)
            };
        }

        ICreole<TResult> ICreoleParserVisitor<ICreole<TResult>>.VisitInclude(CreoleParser.IncludeContext context)
        {
            return new CreoleInclude<TResult>
            {
                Source = ((CreoleAttribute<TResult>)context.attribute().Accept(this)).Value
            };
        }

        ICreole<TResult> ICreoleParserVisitor<ICreole<TResult>>.VisitInlineContent(CreoleParser.InlineContentContext context) => context.children[0].Accept(this);

        ICreole<TResult> ICreoleParserVisitor<ICreole<TResult>>.VisitLineBreak(CreoleParser.LineBreakContext context) => new CreoleLineBreak<TResult>();

        ICreole<TResult> ICreoleParserVisitor<ICreole<TResult>>.VisitNamedEntityBody(CreoleParser.NamedEntityBodyContext context)
        {
            // Contained text will be a string, which should be parsed as the name of an HTML entity.  We use a subset here; the full list, particularly for HTML5, is horribly large.
            return new CreoleEntity<TResult>()
            {
                Value = NamedEntityTranslations[context.GetText()]
            };
        }

        ICreole<TResult> ICreoleParserVisitor<ICreole<TResult>>.VisitParagraph(CreoleParser.ParagraphContext context) => new CreoleParagraph<TResult>() { Contents = context.content().Accept(this) };

        ICreole<TResult> ICreoleParserVisitor<ICreole<TResult>>.VisitReport(CreoleParser.ReportContext context) => context.content().Accept(this);

        ICreole<TResult> ICreoleParserVisitor<ICreole<TResult>>.VisitSignificantText(CreoleParser.SignificantTextContext context) => new CreoleText<TResult> { Text = context.GetText() };

        ICreole<TResult> ICreoleParserVisitor<ICreole<TResult>>.VisitSimpleSubstitution(CreoleParser.SimpleSubstitutionContext context)
        {
            return new CreoleSubstitution<TResult>
            {
                Path = context.path.Text,
                Format = "default"
            };
        }

        ICreole<TResult> ICreoleParserVisitor<ICreole<TResult>>.VisitSubstitution(CreoleParser.SubstitutionContext context)
        {
            // Abstract in the parser - will always be a SimpleSubstitution or a CompoundSubstitution.
            throw new NotImplementedException();
        }

        ICreole<TResult> ICreoleParserVisitor<ICreole<TResult>>.VisitTable(CreoleParser.TableContext context) => new CreoleTable<TResult> { Contents = context.content().Accept(this) };

        ICreole<TResult> ICreoleParserVisitor<ICreole<TResult>>.VisitTableDetail(CreoleParser.TableDetailContext context)
        {
            return new CreoleTableDetail<TResult>
            {
                Contents = context.content().Accept(this),
                Colspan = (null == context.colspan) ? 1 : int.Parse(((CreoleAttribute<TResult>)context.attribute().Accept(this)).Value)
            };
        }

        ICreole<TResult> ICreoleParserVisitor<ICreole<TResult>>.VisitTableHeader(CreoleParser.TableHeaderContext context)
        {
            return new CreoleTableHeader<TResult>()
            {
                Contents = context.content().Accept(this),
                Colspan = (null == context.colspan) ? 1 : int.Parse(((CreoleAttribute<TResult>)context.attribute().Accept(this)).Value)
            };
        }

        ICreole<TResult> ICreoleParserVisitor<ICreole<TResult>>.VisitTableRow(CreoleParser.TableRowContext context) => new CreoleTableRow<TResult>() { Contents = context.content().Accept(this) };

        ICreole<TResult> IParseTreeVisitor<ICreole<TResult>>.VisitTerminal(ITerminalNode node) => throw new NotImplementedException();
    }
}
