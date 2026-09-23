using System;
using System.Collections.Generic;
using System.Text;
using System.Text.RegularExpressions;
using StatsDirect.Templates;

namespace StatsDirect.TemplateProcessing
{
    public class CreoleRtfReportRenderer : ReportRenderer
    {
        const string RTF_REPORT_START = @"/split/{\rtf1\ansi\ansicpg1252\deff0\deflang2057{\fonttbl{\f0\fswiss Calibri;}{\f1\fswiss\fcharset0 Calibri;}{\f2\fswiss Courier New;}}{\colortbl ;\red0\green0\blue0;\red254\green254\blue254;\red0\green127\blue127;\red0\green0\blue255;\red0\green127\blue0;\red255\green0\blue0;\red127\green0\blue0;\red0\green0\blue127;\red127\green127\blue0;}\viewkind4\uc1\pard\li135\cf1\f0\fs20 ";
        const string RTF_REPORT_END = @"\par }";

        public override string Render(/* TODO: IPreferences */ ITemplateHost host, string template, ParameterBag substitutions)
        {
            // Before doing anything else, replace any {...} in the creole with \{...\}.  Do it now because we're about to put a whole load of {...} into the substituted RTF and won't be able to tell the difference later.
            string protectedTemplate = template.Replace(@"{", @"\{").Replace(@"}", @"\}");

            string templateWithInclusions = ResolveTemplates(protectedTemplate, new List<string>());
            string templateWithPossibleDeadBlocks = SubstituteInternal(host, templateWithInclusions, substitutions);
            string substitutedTemplate = RemoveBlocks(templateWithPossibleDeadBlocks);
            return Prettify(substitutedTemplate);
        }

        /// <summary>
        /// Takes a creole template with all values substituted in.  Returns a form of that suitable for direct output into a report by replacing the remaining creole with RTF.
        /// </summary>
        private static string Prettify(string substitutedTemplate)
        {
            Dictionary<string, string> substitutions = new()
            {
                // Colour table entries: 1=black, 2=white, 3=dark cyan, 4=blue (CI), 5=green (pval), 6=red (warn), 7=dark red (subtotal), 8=dark blue (model/grandtotal).
                { "<report>", string.Empty },
                { "</report>", string.Empty },
                { "<b>", @"{\b " },
                { "</b>", @"}" },
                { "<br/>", @"\par " },
                { "<br />", @"\par " },
                { "<ci>", @"{\cf4 " },
                { "</ci>", @"}" },
                { "<grandtotal>", @"{\cf8 " },
                { "</grandtotal>", @"}" },
                { "<i>", @"{\i " },
                { "</i>", @"}" },
                { "<model>", @"{\cf8 " },
                { "</model>", @"}" },
                { "<p>", string.Empty },
                { "</p>", @"\par\par " },
                { "<pre>", @"{\f2 " },
                { "</pre>", @"}" },
                { "<pval>", @"{\cf5 " },
                { "</pval>", @"}" },
                { "<score>", @"{\cf3 " },
                { "</score>", @"}" },
                { "<sub>", @"{\sub " },
                { "</sub>", @"}" },
                { "<subtitle>", @"{\ul " },
                { "</subtitle>", @"}\par\par " },
                { "<subtotal>", @"{\cf7 " },
                { "</subtotal>", @"}" },
                { "<sup>", @"{\super " },
                { "</sup>", @"}" },
                { "<td>", @"\pard\intbl " },
                { "</td>", @"\cell " },
                { "<tdfirst>", @"\pard\intbl!!FIRST!! " },
                { "</tdfirst>", @"\cell " },
                { "<tdspan/>", @"\pard\intbl!!SPAN!!\cell " },
                { "<th>", @"\pard\intbl {\ul " },
                { "</th>", @"}\cell " },
                { "<thfirst>", @"\pard\intbl!!FIRST!! {\ul " },
                { "</thfirst>", @"}\cell " },
                { "<thspan/>", @"\pard\intbl!!SPAN!!\cell " },
                { "<table>", @"{" },
                { "</table>", @"}\par " },
                { "<title>", @"{\ul\b " },
                { "</title>", @"}\par\par " },
                { "<tr>", @"\trowd\trgaph135\trleft0\trautofit1!!CELLDEFINITION!! " },
                { "</tr>", @"\row " + Environment.NewLine },
                { "<u>", @"{\ul " },
                { "</u>", @"}" },
                { "<warn>", @"{\cf6 " },
                { "</warn>", @"}" },
                { "&amp;", @"&" },
                { "&gt;", @">" },
                { "&lt;", @"<" },
                { "&#xb1;", @"\'b1" },
                { "&#xb2;", @"\'b2" },
                { "&#xe9;", @"\'e9" }
            };

            string afterSubstitutions = substitutedTemplate.Trim();

            foreach (KeyValuePair<string, string> pair in substitutions)
                afterSubstitutions = afterSubstitutions.Replace(pair.Key, pair.Value);
            // RTF tables need a certain amount of fixup: they need a \cellx0 for each cell in the row.
            // ASSUMPTION: An entire table row is on one line in the source and hence in the translated data.
            // ASSUMPTION: There is at lease one non-table line between tables.  This is used to detect the first row of a table in order to insert some text that is later removed when fixing up the table.
            string[] splitResults = afterSubstitutions.Split('\n');
            StringBuilder finalOutput = new();
            Regex cellFinder = new(@"\\intbl(?:!!(?<span>[A-Z]+)!!)?");
            bool wasInTable = false;
            finalOutput.Append(RTF_REPORT_START);
            foreach (string unchangedLine in splitResults)
            {
                // Do not propagate blank lines
                if (string.IsNullOrWhiteSpace(unchangedLine))
                    continue;

                bool isInTable = false;
                string line = unchangedLine.Trim();
                if (line.Contains(@"\row"))
                {
                    MatchCollection matches = cellFinder.Matches(line);
                    // If we have a table row with no cells, it's invalid - prevent it from being emitted.
                    if (matches.Count > 0)
                    {
                        isInTable = true;
                        // If we get here, there are some cells in this line.  We need one \cellx<width> for each \cell, placed at the end of the row data (which we know ends with \!!CELLSHERE!! from the translation of </tr>).
                        StringBuilder cellxs = new();
                        foreach (Match m in matches)
                        {
                            string spanString = m.Groups["span"].Value;
                            if ("FIRST".Equals(spanString))
                                cellxs.Append(@"\clmgf");
                            else if ("SPAN".Equals(spanString))
                                cellxs.Append(@"\clmrg");
                            cellxs.Append(@"\cellx0");
                            // cellxs.Append(@"\clNoWrap\cellx0");
                        }

                        // If this is the first line of a new table, mark the first table cell so that the RTF inserter can get hold of it later.
                        if (!wasInTable)
                        {
                            // The contents of each cell will end with "\cell " - note the space at the end.  We can drop some marker text into the first cell by finding the first occurrence and adding that marker.
                            int pos = line.IndexOf(@"\cell ", StringComparison.InvariantCulture);
                            if (pos >= 0)
                                line = line.Substring(0, pos) + "!!FIRSTCELLOFTABLE!!" + line.Substring(pos);
                        }

                        finalOutput.AppendLine(line
                            .Replace("!!FIRST!!", string.Empty)
                            .Replace("!!SPAN!!", string.Empty)
                            .Replace(@"!!CELLDEFINITION!!", cellxs.ToString())
                            );
                    }
                }
                else
                    finalOutput.AppendLine(line);
                wasInTable = isInTable;
            }
            finalOutput.Append(RTF_REPORT_END);
            return finalOutput.ToString();
        }

        /// <summary>
        /// Get rid of any &lt;block name="xxx">...&lt;/block> pairs that have not already been substituted
        /// </summary>
        private static string RemoveBlocks(string templateWithPossibleDeadBlocks)
        {
            StringBuilder sb = new();
            int sourcePosition = 0;
            do
            {
                int startOfTemplate = templateWithPossibleDeadBlocks.IndexOf("<block", sourcePosition, StringComparison.Ordinal);
                if (startOfTemplate < 0)
                {
                    sb.Append(templateWithPossibleDeadBlocks.Substring(sourcePosition));
                    return sb.ToString();
                }

                sb.Append(templateWithPossibleDeadBlocks.Substring(sourcePosition, startOfTemplate - sourcePosition));
                int t = startOfTemplate;
                int l = t;
                do
                {
                    t = templateWithPossibleDeadBlocks.IndexOf("<block", t + 1, StringComparison.Ordinal); // Note lack of trailing slash as we want to match any template name
                    l = templateWithPossibleDeadBlocks.IndexOf("</block>", l + 1, StringComparison.Ordinal);
                } while (t >= 0 && t <= l);
                if (-1 == l)
                {
                    throw new Exception("Mismatched start and end blocks in template");
                }
                sourcePosition = l + 8;
            } while (true);
        }

        /// <summary>
        /// Search for strings of the form &lt;include src="name"/> in the template; where they exist, replace them with the named template
        /// </summary>
        /// <param name="rawCreole">The RTF to examine for inclusions</param>
        /// <param name="knownInclusions"></param>
        /// <returns>The RTF with inclusions replaced</returns>
        private static string ResolveTemplates(string rawCreole, ICollection<string> knownInclusions)
        {
            StringBuilder sb = new();
            int sourcePosition = 0;
            do
            {
                int startOfInclusion = rawCreole.IndexOf("<include src=", sourcePosition, StringComparison.Ordinal);
                if (startOfInclusion < 0)
                {
                    sb.Append(rawCreole.Substring(sourcePosition));
                    return sb.ToString();
                }

                int endOfInclusion = rawCreole.IndexOf("/>", startOfInclusion + 1, StringComparison.Ordinal);
                if (-1 == endOfInclusion)
                    throw new Exception("No terminating > after a <include");

                sb.Append(rawCreole.Substring(sourcePosition, startOfInclusion - sourcePosition));
                string includedName = rawCreole.Substring(startOfInclusion + 13, endOfInclusion - (startOfInclusion + 13));
                includedName = includedName.Trim();
                if (includedName.StartsWith("\""))
                    includedName = includedName.Substring(1);
                if (includedName.EndsWith("\""))
                    includedName = includedName.Substring(0, includedName.Length - 1);
                if (!knownInclusions.Contains(includedName))
                {
                    knownInclusions.Add(includedName);
                    string includedContent = GetContent(includedName);
                    sb.Append(ResolveTemplates(includedContent, knownInclusions));
                    knownInclusions.Remove(includedName);
                }
                sourcePosition = endOfInclusion + 2;
            } while (true);
        }

        /// <summary>
        /// Recursively fill in any values in this block, examining the template for nested blocks.
        /// </summary>
        private string SubstituteInternal(/* TODO: IPreferences */ ITemplateHost host, string template, ParameterBag substitutions)
        {
            if (null != substitutions)
            {
                // TODO: Horribly inefficient, but will suffice for now
                bool foundNestedKey = false;
                foreach (KeyValuePair<string, FilledParameter> pair in substitutions.Pairs)
                {
                    if (pair.Key.StartsWith("*"))
                    {
                        foundNestedKey = true;
                        // A nested value.  Look for a nested template with the given name and fill it in.
                        string nestedTemplateName = pair.Key.Substring(1);
                        string nestedTemplate = FindNestedTemplate(template, nestedTemplateName);
                        while (null != nestedTemplate)
                        {
                            IList<ParameterBag> value = null;
                            if (null != pair.Value)
                                value = pair.Value.AsParameterBagList;
                            string nestedResult = SubstituteInternal(host, nestedTemplate, value);
                            template = template.Replace(nestedTemplate, nestedResult);
                            nestedTemplate = FindNestedTemplate(template, nestedTemplateName);
                        }
                    }
                    else
                    {
                        string value = string.Empty;
                        string valueP = string.Empty;
                        string valueU = string.Empty;
                        if (null != pair.Value && pair.Value.HasData)
                        {
                            if (pair.Value.AsObject is IRenderable renderable)
                            {
                                // We know we have to render to RTF, so this is legit
                                value = new RtfRenderer(host).Render(renderable);
                            }
                            else
                            {
                                value = pair.Value.AsObject.ToString();
                                if (pair.Value.IsDouble)
                                {
                                    valueU = host.RoundU(pair.Value.AsDouble);
                                    valueP = host.pval(pair.Value.AsDouble);
                                }
                                else
                                    valueU = valueP = value;
                            }
                        }
                        template = template.Replace("@" + pair.Key + "", value);
                        template = template.Replace("@{" + pair.Key + ":roundx}", valueU);
                        template = template.Replace("@{" + pair.Key + ":round0}", valueU);
                        template = template.Replace("@{" + pair.Key + ":round1}", valueU);
                        template = template.Replace("@{" + pair.Key + ":round2}", valueU);
                        template = template.Replace("@{" + pair.Key + ":roundu}", valueU);
                        template = template.Replace("@{" + pair.Key + ":pval}", valueP);
                    }
                }
                // We may have a nested template, but nothing to put in it.  If this is the case, delete the template.
                if (!foundNestedKey)
                {
                    string nestedTemplate = FindNestedTemplate(template, null);
                    if (null != nestedTemplate)
                        template = template.Replace(nestedTemplate, string.Empty);
                }
            }
            return template;
        }

        /// <summary>
        /// Recursively fill in a template.  We've found a nested template; clone it as many times as we have values, and fill it in.
        /// If there are no values, remove the template entirely.
        /// </summary>
        private string SubstituteInternal(/* TODO: IPreferences */ ITemplateHost host, string template, IEnumerable<ParameterBag> substitutions)
        {
            // If the template still has a /bs templatename/.../bf/ pair, strip them.
            if (template.StartsWith("<block"))
            {
                template = template.Substring(template.IndexOf('>', 1) + 1);
                if (template.EndsWith("</block>"))
                {
                    template = template.Substring(0, template.Length - 8);
                }
            }

            // We now have a naked template.  Replicate it the appropriate number of times, and fill it in.
            string filledValue = string.Empty;
            if (null != substitutions)
            {
                foreach (ParameterBag substitutionDictionary in substitutions)
                {
                    filledValue += SubstituteInternal(host, template, substitutionDictionary);
                }
            }
            return filledValue;
        }

        /// <summary>
        /// Find the first template (starting with &lt;block name="templateName">) in the string, and return the substring up to a matching &lt;/block>.
        /// </summary>
        /// <param name="template"> </param>
        /// <param name="templateName">The name of the template to find.  This may be blank, in which case &lt;block> is searched for; or null, in which case any template name will do.</param>
        private static string FindNestedTemplate(string template, string templateName)
        {
            string searchSuffix = string.Empty;
            if (null != templateName)
                searchSuffix = (0 == templateName.Length ? templateName : " name=\"" + templateName + "\"") + ">";

            int startOfTemplate = template.IndexOf("<block" + searchSuffix, StringComparison.Ordinal);
            if (startOfTemplate >= 0)
            {
                int t = startOfTemplate;
                int l = t;
                do
                {
                    t = template.IndexOf("<block", t + 1, StringComparison.Ordinal); // Note lack of trailing slash as we want to match any template name
                    l = template.IndexOf("</block>", l + 1, StringComparison.Ordinal);
                } while (t >= 0 && t <= l);
                if (-1 == l)
                {
                    throw new Exception("Mismatched start and end blocks in template: there is no end block for \"" + templateName + "\"");
                }
                return template.Substring(startOfTemplate, l - startOfTemplate + 8);
            }

            // If we get here, there's no nested template with the given name.
            return null;
        }
    }
}
