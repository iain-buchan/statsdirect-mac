using StatsDirect.Creole;
using StatsDirect.Templates;
using StatsDirect.Utilities;
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;

namespace StatsDirect.TemplateProcessing
{
    public class PrincipledCreoleRtfReportRenderer : ReportRenderer
    {
        const string RTF_REPORT_START = @"/split/{\rtf1\ansi\ansicpg1252\deff0\deflang2057{\fonttbl{\f0\fswiss Calibri;}{\f1\fswiss\fcharset0 Calibri;}{\f2\fswiss Courier New;}}{\colortbl ;\red0\green0\blue0;\red254\green254\blue254;\red0\green127\blue127;\red0\green0\blue255;\red0\green127\blue0;\red255\green0\blue0;\red127\green0\blue0;\red0\green0\blue127;\red127\green127\blue0;}\viewkind4\uc1\pard\li135\cf1\f0\fs20 ";
        const string RTF_REPORT_END = @"\par }";
        const string FirstCellOfTableMarker = "!!FIRSTCELLOFTABLE!!";

        public override string Render(/* TODO: IPreferences */ ITemplateHost host, string template, ParameterBag substitutions)
        {
            ICreole<IList<IStringOrDirective>> creole = CreoleReader.Parse<IList<IStringOrDirective>>(template, out string _);
            IList<IStringOrDirective> raw = creole.Accept(new InnerRtfReportRenderer(host, substitutions));
            return RTF_REPORT_START + Cook(raw) + RTF_REPORT_END;
        }

        private string Cook(IList<IStringOrDirective> raw)
        {
            // Smash double new paragraph markers into one; render everything else into one big string and return it.
            StringBuilder sb = new();
            // BEWARE: The inside of this loop may modify the loop variable to prevent testing skipped elements.
            for (int candidateIndex = 0; candidateIndex < raw.Count; candidateIndex++)
            {
                // Skip leading blank if present
                if (candidateIndex == 0 && raw[candidateIndex].IsBlankOrWhiteSpace)
                    continue;

                if (candidateIndex == raw.Count - 1)
                {
                    // We're at the final element and we've not skipped it.  Emit.
                    sb.Append(raw[candidateIndex].Rtf);
                    continue;
                }

                // We're at an earlier-than-last element and we're not skipping it.
                IStringOrDirective candidate = raw[candidateIndex];
                IStringOrDirective next = raw[candidateIndex + 1];
                IStringOrDirective maybeMerged = candidate.MaybeMergeWithNext(next);

                // If the merge came back empty, this one doesn't merge.  Emit it and try the next element for merging.
                if (null == maybeMerged)
                {
                    sb.Append(candidate.Rtf);
                    continue;
                }

                // The merge came back non-empty; the returned value is used to represent both this element and the next one.  Emit it and skip the next entry.
                // In theory, we should keep looking for further merges.  In reality, we presently (2019-10) only ever merge two adjacent newlines, so this code is sufficient.
                sb.Append(maybeMerged.Rtf);
                candidateIndex++;
            }
            return sb.ToString();
        }

        private class RtfFormatHolder
        {
            public IList<IStringOrDirective> Prefix { get; }
            public IList<IStringOrDirective> Suffix { get; }

            public RtfFormatHolder(string prefix)
                : this(new IStringOrDirective[] { new RtfThatIsNotANewParagraph(prefix) }, Array.Empty<IStringOrDirective>())
            {
            }

            public RtfFormatHolder(IList<IStringOrDirective> prefix, IList<IStringOrDirective> suffix)
            {
                Prefix = prefix;
                Suffix = suffix;
            }
        }

        private class InnerRtfReportRenderer : ICreoleVisitor<IList<IStringOrDirective>>
        {
            private static readonly Dictionary<string, RtfFormatHolder> rtfFormatting = new()
            {
                // Colour table entries: 1=black, 2=white, 3=dark cyan, 4=blue (CI), 5=green (pval), 6=red (warn), 7=dark red (subtotal), 8=dark blue (model/grandtotal).
                { "b", new RtfFormatHolder(@"\b") },
                { "ci", new RtfFormatHolder(@"\cf4") },
                { "grandtotal", new RtfFormatHolder(@"\cf8") },
                { "i", new RtfFormatHolder(@"\i") },
                { "model", new RtfFormatHolder(@"\cf8") },
                { "pre", new RtfFormatHolder(@"\f2") },
                { "pval", new RtfFormatHolder(@"\cf5") },
                { "score", new RtfFormatHolder(@"\cf3") },
                { "sub", new RtfFormatHolder(@"\sub") },
                { "subtitle", new RtfFormatHolder(new IStringOrDirective[] { new NewParagraph(), new RtfThatIsNotANewParagraph(@"\ul") }, new IStringOrDirective[] { new RtfThatIsNotANewParagraph(@"\par"), new NewParagraph() }) },
                { "subtotal", new RtfFormatHolder(@"\cf7") },
                { "sup", new RtfFormatHolder(@"\super") },
                { "title", new RtfFormatHolder(new IStringOrDirective[] { new NewParagraph(), new RtfThatIsNotANewParagraph(@"\ul\b") }, new IStringOrDirective[] { new RtfThatIsNotANewParagraph(@"\par"), new NewParagraph() }) },
                { "u", new RtfFormatHolder(@"\ul") },
                { "warn", new RtfFormatHolder(@"\cf6") }
            };

            private readonly Stack<ParameterBag> substitutionStack = new();
            private readonly /* TODO: IPreferences */ ITemplateHost host;

            /// <summary>
            /// State so that we can inject a little extra marker at the end of the first table cell in each table - used so that the RTF insertion can format the table later.
            /// </summary>
            private bool isFirstCellOfTable;

            public InnerRtfReportRenderer(/* TODO: IPreferences */ ITemplateHost host, ParameterBag substitutions)
            {
                this.host = host;
                substitutionStack.Push(substitutions);
            }

            IList<IStringOrDirective> ICreoleVisitor<IList<IStringOrDirective>>.Visit(CreoleAttribute<IList<IStringOrDirective>> victim)
            {
                // Should never see; ignore.
                return Array.Empty<IStringOrDirective>();
            }

            IList<IStringOrDirective> ICreoleVisitor<IList<IStringOrDirective>>.Visit(CreoleAttributes<IList<IStringOrDirective>> victim)
            {
                // Should never see; ignore.
                return Array.Empty<IStringOrDirective>();
            }

            IList<IStringOrDirective> ICreoleVisitor<IList<IStringOrDirective>>.Visit(CreoleBlock<IList<IStringOrDirective>> victim)
            {
                if (null == victim.Contents)
                    return Array.Empty<IStringOrDirective>();
                List<IStringOrDirective> list = new();
                if (substitutionStack.Peek().TryGetValue("*" + victim.Name, out FilledParameter innerList) && null != innerList && innerList.HasData)
                {
                    bool first = true;
                    foreach (ParameterBag inner in innerList.AsParameterBagList)
                    {
                        if (first)
                            first = false;
                        else
                            list.Add(new RtfThatIsNotANewParagraph(victim.Separator ));
                        substitutionStack.Push(inner);
                        list.AddRange(victim.Contents.Accept(this));
                        substitutionStack.Pop();
                    }
                }
                return list;
            }

            IList<IStringOrDirective> ICreoleVisitor<IList<IStringOrDirective>>.Visit(CreoleFormatting<IList<IStringOrDirective>> victim)
            {
                List<IStringOrDirective> list = new();
                list.Add(new RtfThatIsNotANewParagraph("{"));
                list.AddRange(ToRtfPrefix(victim.Format));
                list.Add(new RtfThatIsNotANewParagraph(" "));
                list.AddRange(MaybeAccept(victim.Contents));
                list.Add(new RtfThatIsNotANewParagraph("}"));
                list.AddRange(ToRtfSuffix(victim.Format));
                return list;
            }

            private IList<IStringOrDirective> ToRtfPrefix(string format) => rtfFormatting[format].Prefix;

            private IList<IStringOrDirective> ToRtfSuffix(string format) => rtfFormatting[format].Suffix;

            IList<IStringOrDirective> ICreoleVisitor<IList<IStringOrDirective>>.Visit(CreoleInclude<IList<IStringOrDirective>> victim)
            {
                // TODO: We should perhaps cache parsed templates in case they are used many times - this is expensive on repeated calls.
                string template = GetContent(victim.Source);
                ICreole<IList<IStringOrDirective>> creole = CreoleReader.Parse<IList<IStringOrDirective>>(template, out string _);
                return creole.Accept(this);
            }

            IList<IStringOrDirective> ICreoleVisitor<IList<IStringOrDirective>>.Visit(CreoleList<IList<IStringOrDirective>> victim)
            {
                List<IStringOrDirective> list = new();
                foreach (ICreole<IList<IStringOrDirective>> v in victim)
                    list.AddRange(v.Accept(this));
                return list;
            }

            IList<IStringOrDirective> ICreoleVisitor<IList<IStringOrDirective>>.Visit(CreoleSubstitution<IList<IStringOrDirective>> victim)
            {
                return new IStringOrDirective[] { new RtfThatIsNotANewParagraph(Substitute(victim)) };
            }

            private string Substitute(CreoleSubstitution<IList<IStringOrDirective>> victim)
            {
                object value = FindValue(victim.Path);
                if (null == value)
                    return string.Empty;
                if (value is string stringValue)
                    return stringValue;
                if (value is int intValue)
                    return intValue.ToString(CultureInfo.CurrentUICulture);
                if (value is IRenderable renderable)
                    return new RtfRenderer(host).Render(renderable);
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
                            return host.pval(Zvalp1(doubleValue));
                        case "zvalp2":
                            return host.pval(Zvalp2(doubleValue));
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

            IList<IStringOrDirective> ICreoleVisitor<IList<IStringOrDirective>>.Visit(CreoleTable<IList<IStringOrDirective>> victim)
            {
                isFirstCellOfTable = true;
                List<IStringOrDirective> list = new();
                list.Add(new NewParagraph());
                list.Add(new RtfThatIsNotANewParagraph("{"));
                list.AddRange(MaybeAccept(victim.Contents));
                list.Add(new RtfThatIsNotANewParagraph("}"));
                list.Add(new NewParagraph());
                return list;
            }

            IList<IStringOrDirective> ICreoleVisitor<IList<IStringOrDirective>>.Visit(CreoleTableRow<IList<IStringOrDirective>> victim)
            {
                List<IStringOrDirective> list = new();
                list.Add(new RtfThatIsNotANewParagraph(@"\trowd\trgaph135\trleft0\trautofit1"));
                list.AddRange(MaybeToCellsDefinition(victim.Contents));
                list.Add(new RtfThatIsNotANewParagraph(@" "));
                list.AddRange(MaybeAccept(victim.Contents));
                list.Add(new RtfThatIsNotANewParagraph(@"\row"));
                return list;
            }

            private IList<IStringOrDirective> MaybeToCellsDefinition(ICreole<IList<IStringOrDirective>> contents)
            {
                return null == contents
                    ? Array.Empty<IStringOrDirective>()
                    : contents.Accept(new CellsDefinitionRenderer(substitutionStack.Peek()));
            }

            IList<IStringOrDirective> ICreoleVisitor<IList<IStringOrDirective>>.Visit(CreoleTableDetail<IList<IStringOrDirective>> victim)
            {
                List<IStringOrDirective> list = new();
                list.Add(new RtfThatIsNotANewParagraph(@"\pard\intbl "));
                list.AddRange(MaybeAccept(victim.Contents));
                if (isFirstCellOfTable)
                {
                    list.Add(new RtfThatIsNotANewParagraph(FirstCellOfTableMarker));
                    isFirstCellOfTable = false;
                }
                list.Add(new RtfThatIsNotANewParagraph(@"\cell "));
                for (int spanner = 1; spanner < victim.Colspan; spanner++)
                    list.Add(new RtfThatIsNotANewParagraph(@"\pard\intbl\cell "));
                return list;
            }

            IList<IStringOrDirective> ICreoleVisitor<IList<IStringOrDirective>>.Visit(CreoleTableHeader<IList<IStringOrDirective>> victim)
            {
                List<IStringOrDirective> list = new();
                list.Add(new RtfThatIsNotANewParagraph(@"\pard\intbl {\ul "));
                list.AddRange(MaybeAccept(victim.Contents));
                list.Add(new RtfThatIsNotANewParagraph(@"}"));
                if (isFirstCellOfTable)
                {
                    list.Add(new RtfThatIsNotANewParagraph(FirstCellOfTableMarker));
                    isFirstCellOfTable = false;
                }
                list.Add(new RtfThatIsNotANewParagraph(@"\cell "));
                for (int spanner = 1; spanner < victim.Colspan; spanner++)
                    list.Add(new RtfThatIsNotANewParagraph(@"\pard\intbl {\ul}\cell "));
                return list;
            }

            IList<IStringOrDirective> ICreoleVisitor<IList<IStringOrDirective>>.Visit(CreoleText<IList<IStringOrDirective>> victim) => new IStringOrDirective[] { new RtfThatIsNotANewParagraph(victim.Text) };

            IList<IStringOrDirective> ICreoleVisitor<IList<IStringOrDirective>>.Visit(CreoleLineBreak<IList<IStringOrDirective>> victim) => new IStringOrDirective[] { new NewParagraph() };

            IList<IStringOrDirective> ICreoleVisitor<IList<IStringOrDirective>>.Visit(CreoleParagraph<IList<IStringOrDirective>> victim)
            {
                List<IStringOrDirective> list = new();
                list.Add(new NewParagraph());
                list.AddRange(MaybeAccept(victim.Contents));
                list.Add(new NewParagraph());
                return list;
            }

            IList<IStringOrDirective> ICreoleVisitor<IList<IStringOrDirective>>.Visit(CreoleEntity<IList<IStringOrDirective>> victim)
            {
                return new IStringOrDirective[] { new RtfThatIsNotANewParagraph(@"\'" + ((int)victim.Value).ToString("X")) };
            }

            private IList<IStringOrDirective> MaybeAccept(ICreole<IList<IStringOrDirective>> victimOrNull) => null == victimOrNull ? Array.Empty<IStringOrDirective>() : victimOrNull.Accept(this);

            private double Zvalp1(double xz)
            {
                double p = 1 - Numerics.PDF.alnorm(xz);
                if (p > 1 - p)
                    p = 1 - p;
                return p;
            }

            private double Zvalp2(double xz) => Zvalp1(xz) * 2;
        }

        private interface IStringOrDirective
        {
            IStringOrDirective MaybeMergeWithNext(IStringOrDirective next);

            string Rtf { get; }
            bool IsBlankOrWhiteSpace { get; }
        }

        private class NewParagraph : IStringOrDirective
        {
            string IStringOrDirective.Rtf => @"\par ";

            bool IStringOrDirective.IsBlankOrWhiteSpace => true;

            IStringOrDirective IStringOrDirective.MaybeMergeWithNext(IStringOrDirective next) => (next is NewParagraph) ? this : null;
        }

        private class RtfThatIsNotANewParagraph : IStringOrDirective
        {
            public string Rtf { get; private set; }

            bool IStringOrDirective.IsBlankOrWhiteSpace => string.IsNullOrWhiteSpace(Rtf);

            public RtfThatIsNotANewParagraph(string rtf)
            {
                Rtf = rtf;
            }

            IStringOrDirective IStringOrDirective.MaybeMergeWithNext(IStringOrDirective next) => null;

            public override string ToString() => Rtf;
        }

        private class CellsDefinitionRenderer : ICreoleVisitor<IList<IStringOrDirective>>
        {
            private readonly Stack<ParameterBag> substitutionStack = new();

            public CellsDefinitionRenderer(ParameterBag substitutions)
            {
                substitutionStack.Push(substitutions);
            }

            IList<IStringOrDirective> ICreoleVisitor<IList<IStringOrDirective>>.Visit(CreoleList<IList<IStringOrDirective>> victim)
            {
                List<IStringOrDirective> list = new();
                foreach (ICreole<IList<IStringOrDirective>> v in victim)
                    list.AddRange(v.Accept(this));
                return list;
            }

            IList<IStringOrDirective> ICreoleVisitor<IList<IStringOrDirective>>.Visit(CreoleAttribute<IList<IStringOrDirective>> victim) => Array.Empty<IStringOrDirective>();
            IList<IStringOrDirective> ICreoleVisitor<IList<IStringOrDirective>>.Visit(CreoleAttributes<IList<IStringOrDirective>> victim) => Array.Empty<IStringOrDirective>();
            IList<IStringOrDirective> ICreoleVisitor<IList<IStringOrDirective>>.Visit(CreoleBlock<IList<IStringOrDirective>> victim)
            {
                if (null == victim.Contents)
                    return Array.Empty<IStringOrDirective>();
                List<IStringOrDirective> list = new();
                if (substitutionStack.Peek().TryGetValue("*" + victim.Name, out FilledParameter innerList) && null != innerList && innerList.HasData)
                {
                    bool first = true;
                    foreach (ParameterBag inner in innerList.AsParameterBagList)
                    {
                        if (first)
                            first = false;
                        else
                            list.Add(new RtfThatIsNotANewParagraph(victim.Separator));
                        substitutionStack.Push(inner);
                        list.AddRange(victim.Contents.Accept(this));
                        substitutionStack.Pop();
                    }
                }
                return list;
            }
            IList<IStringOrDirective> ICreoleVisitor<IList<IStringOrDirective>>.Visit(CreoleEntity<IList<IStringOrDirective>> victim) => Array.Empty<IStringOrDirective>();
            IList<IStringOrDirective> ICreoleVisitor<IList<IStringOrDirective>>.Visit(CreoleFormatting<IList<IStringOrDirective>> victim) => Array.Empty<IStringOrDirective>();
            IList<IStringOrDirective> ICreoleVisitor<IList<IStringOrDirective>>.Visit(CreoleInclude<IList<IStringOrDirective>> victim) => Array.Empty<IStringOrDirective>();
            IList<IStringOrDirective> ICreoleVisitor<IList<IStringOrDirective>>.Visit(CreoleLineBreak<IList<IStringOrDirective>> victim) => Array.Empty<IStringOrDirective>();
            IList<IStringOrDirective> ICreoleVisitor<IList<IStringOrDirective>>.Visit(CreoleParagraph<IList<IStringOrDirective>> victim) => Array.Empty<IStringOrDirective>();
            IList<IStringOrDirective> ICreoleVisitor<IList<IStringOrDirective>>.Visit(CreoleSubstitution<IList<IStringOrDirective>> victim) => Array.Empty<IStringOrDirective>();
            IList<IStringOrDirective> ICreoleVisitor<IList<IStringOrDirective>>.Visit(CreoleTable<IList<IStringOrDirective>> victim) => Array.Empty<IStringOrDirective>();
            IList<IStringOrDirective> ICreoleVisitor<IList<IStringOrDirective>>.Visit(CreoleTableRow<IList<IStringOrDirective>> victim) => Array.Empty<IStringOrDirective>();
            IList<IStringOrDirective> ICreoleVisitor<IList<IStringOrDirective>>.Visit(CreoleTableDetail<IList<IStringOrDirective>> victim) => CellDefinition(victim.Colspan);
            IList<IStringOrDirective> ICreoleVisitor<IList<IStringOrDirective>>.Visit(CreoleTableHeader<IList<IStringOrDirective>> victim) => CellDefinition(victim.Colspan);
            IList<IStringOrDirective> ICreoleVisitor<IList<IStringOrDirective>>.Visit(CreoleText<IList<IStringOrDirective>> victim) => Array.Empty<IStringOrDirective>();

            private IList<IStringOrDirective> MaybeAccept(ICreole<IList<IStringOrDirective>> victimOrNull)
            {
                return null == victimOrNull ? Array.Empty<IStringOrDirective>() : victimOrNull.Accept(this);
            }

            private IList<IStringOrDirective> CellDefinition(int colspan)
            {
                if (colspan == 1)
                    return new IStringOrDirective[] { new RtfThatIsNotANewParagraph(@"\cellx0") };
                StringBuilder sb = new();
                sb.Append(@"\clmgf\cellx0");
                for (int spanner = 1; spanner < colspan; spanner++)
                    sb.Append(@"\clmrg\cellx0");
                return new IStringOrDirective[] { new RtfThatIsNotANewParagraph(sb.ToString()) };
            }
        }
    }
}
