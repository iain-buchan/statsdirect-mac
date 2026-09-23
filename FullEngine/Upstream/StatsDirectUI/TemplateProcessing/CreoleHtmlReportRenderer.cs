using StatsDirect.Creole;
using StatsDirect.Templates;
using StatsDirect.Utilities;
using System.Collections.Generic;
using System.Globalization;
using System.Net;
using System.Text;

namespace StatsDirect.TemplateProcessing
{
    public class CreoleHtmlReportRenderer : ReportRenderer
    {
        public override string Render(/* TODO: IPreferences */ ITemplateHost host, string template, ParameterBag substitutions)
        {
            ICreole<string> creole = CreoleReader.Parse<string>(template, out string _);
            return creole.Accept(new InnerHtmlReportRenderer(host, substitutions));
        }

        private class InnerHtmlReportRenderer : ICreoleVisitor<string>
        {
            private static readonly Dictionary<string, IWrapper> rtfFormatting = new()
            {
                { "b", new TagRenderer("b") },
                { "ci", new SpanRenderer("ci") },
                { "grandtotal", new SpanRenderer("grandtotal") },
                { "i", new TagRenderer("i") },
                { "model", new SpanRenderer("model") },
                { "pre", new TagRenderer("pre") },
                { "pval", new SpanRenderer("pval") },
                { "score", new SpanRenderer("score") },
                { "sub", new TagRenderer("sub") },
                { "subtitle", new TagRenderer("h2") },
                { "subtotal", new SpanRenderer("subtotal") },
                { "sup", new TagRenderer("sup") },
                { "title", new TagRenderer("h1") },
                { "u", new TagRenderer("u") },
                { "warn", new SpanRenderer("warn") }
            };

            private readonly Stack<ParameterBag> substitutionStack = new();
            private readonly /* TODO: IPreferences */ ITemplateHost host;

            public InnerHtmlReportRenderer(/* TODO: IPreferences */ ITemplateHost host, ParameterBag substitutions)
            {
                this.host = host;
                substitutionStack.Push(substitutions);
            }

            string ICreoleVisitor<string>.Visit(CreoleAttribute<string> victim)
            {
                // Should never see; ignore.
                return string.Empty;
            }

            string ICreoleVisitor<string>.Visit(CreoleAttributes<string> victim)
            {
                // Should never see; ignore.
                return string.Empty;
            }

            string ICreoleVisitor<string>.Visit(CreoleBlock<string> victim)
            {
                if (null == victim.Contents)
                    return string.Empty;
                StringBuilder sb = new();
                if (substitutionStack.Peek().TryGetValue("*" + victim.Name, out FilledParameter innerList) && null != innerList && innerList.HasData)
                {
                    bool first = true;
                    foreach (ParameterBag inner in innerList.AsParameterBagList)
                    {
                        if (first)
                            first = false;
                        else
                            sb.Append(victim.Separator);
                        substitutionStack.Push(inner);
                        sb.Append(victim.Contents.Accept(this));
                        substitutionStack.Pop();
                    }
                }
                return sb.ToString();
            }

            string ICreoleVisitor<string>.Visit(CreoleFormatting<string> victim)
            {
                IWrapper wrapper = rtfFormatting[victim.Format];
                return wrapper.Open
                    + MaybeAccept(victim.Contents)
                    + wrapper.Close;
            }

            string ICreoleVisitor<string>.Visit(CreoleInclude<string> victim)
            {
                // TODO: We should perhaps cache parsed templates in case they are used many times - this is expensive on repeated calls.
                string template = GetContent(victim.Source);
                ICreole<string> creole = CreoleReader.Parse<string>(template, out string _);
                return creole.Accept(this);
            }

            string ICreoleVisitor<string>.Visit(CreoleList<string> victim)
            {
                StringBuilder sb = new();
                foreach (ICreole<string> v in victim)
                    sb.Append(v.Accept(this));
                return sb.ToString();
            }

            string ICreoleVisitor<string>.Visit(CreoleSubstitution<string> victim)
            {
                object value = FindValue(victim.Path);
                if (null == value)
                    return string.Empty;
                if (value is string stringValue)
                    return stringValue;
                if (value is int intValue)
                    return intValue.ToString(CultureInfo.CurrentUICulture);
                if (value is IRenderable renderable)
                    return new HtmlRenderer(host).Render(renderable);
                if (value is double doubleValue)
                    switch (victim.Format)
                    {
                        case "pval":
                            return host.pval(doubleValue);
                        case "pval_half":
                            return host.pval_half(doubleValue);
                        case "roundu":
                            return host.RoundU(doubleValue);
                        case "roundx":
                            return host.RoundU(doubleValue);
                        case "round0":
                            return Formatting.XRound(doubleValue, 0);
                        case "round1":
                            return Formatting.XRound(doubleValue, 1);
                        case "round2":
                            return Formatting.XRound(doubleValue, 2);
                        case "round3":
                            return Formatting.XRound(doubleValue, 3);
                        case "zvalp1":
                            return host.pval(zvalp1(doubleValue));
                        case "zvalp2":
                            return host.pval(zvalp2(doubleValue));
                        case "default":
                            return doubleValue.ToString();
                        default:
                            // TODO: Warn.
                            return value.ToString();
                    }
                // Nothing we know how to render specially, so just call ToString() on it and hope.
                return value.ToString();
            }

            private object FindValue(string path)
            {
                foreach (ParameterBag candidate in substitutionStack)
                    if (candidate.TryGetValue(path, out FilledParameter value))
                        return value.AsObject;
                // If we get here, no such value exists.
                return null;
            }

            string ICreoleVisitor<string>.Visit(CreoleTable<string> victim)
            {
                return "<table>"
                    + MaybeAccept(victim.Contents)
                    + "</table>";
            }

            string ICreoleVisitor<string>.Visit(CreoleTableRow<string> victim)
            {
                return @"<tr>"
                    + MaybeAccept(victim.Contents)
                    + @"</tr>";
            }

            string ICreoleVisitor<string>.Visit(CreoleTableDetail<string> victim)
            {
                return @"<td"
                    + (victim.Colspan > 1 ? (" colspan=\"" + victim.Colspan + "\"") : string.Empty)
                    + ">"
                    + MaybeAccept(victim.Contents)
                    + @"</td>";
            }

            string ICreoleVisitor<string>.Visit(CreoleTableHeader<string> victim)
            {
                return @"<th"
                    + (victim.Colspan > 1 ? (" colspan=\"" + victim.Colspan + "\"") : string.Empty)
                    + ">"
                    + MaybeAccept(victim.Contents)
                    + @"</th>";
            }

            string ICreoleVisitor<string>.Visit(CreoleText<string> victim)
            {
                return victim.Text;
            }

            string ICreoleVisitor<string>.Visit(CreoleLineBreak<string> victim)
            {
                return @"<br />";
            }

            string ICreoleVisitor<string>.Visit(CreoleParagraph<string> victim)
            {
                return @"<p>"
                    + MaybeAccept(victim.Contents)
                    + @"</p>";
            }

            private string MaybeAccept(ICreole<string> victimOrNull)
            {
                return null == victimOrNull ? string.Empty : victimOrNull.Accept(this);
            }

            string ICreoleVisitor<string>.Visit(CreoleEntity<string> victim)
            {
                return WebUtility.HtmlEncode(string.Empty + victim.Value);
            }

            double zvalp1(double xz)
            {
                double p = 1 - Numerics.PDF.alnorm(xz);
                if (p > 1 - p)
                    p = 1 - p;
                return p;
            }

            double zvalp2(double xz)
            {
                double p = 1 - Numerics.PDF.alnorm(xz);
                if (p > 1 - p)
                    p = 1 - p;
                return p * 2;
            }

            private interface IWrapper
            {
                string Open { get; }
                string Close { get; }
            }

            private class TagRenderer: IWrapper
            {
                private string Tag { get; }

                public TagRenderer(string tag)
                {
                    Tag = tag;
                }

                string IWrapper.Open => "<" + Tag + ">";

                string IWrapper.Close => "</" + Tag + ">";
            }

            private class SpanRenderer: IWrapper
            {
                private string CssClass { get; }

                public SpanRenderer(string cssClass)
                {
                    CssClass = cssClass;
                }

                string IWrapper.Open => "<span class=\"" + CssClass + "\">";

                string IWrapper.Close => "</span>";
            }
        }
    }
}
