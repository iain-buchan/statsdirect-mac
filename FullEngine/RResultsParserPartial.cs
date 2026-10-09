using System.Collections.Generic;
using System.IO;

namespace StatsDirect.R
{
    /// <summary>
    /// The hand-written half of the results parser. Windows turns the metafile R drew into RTF for its report; here the
    /// chart is the PNG that the Mac's metafile shim wrote beside the requested path, and it goes into the HTML report as a
    /// fragment (the value is the fragment's token).
    /// </summary>
    partial class RResultsParser
    {
        private object PathToChart(string path)
        {
            return ReportFragments.Chart(path);
        }

        private static string PathToName(string path)
        {
            return Path.GetFileNameWithoutExtension(path);
        }

        private static string ToStringBody(string rawParsedString)
        {
            return rawParsedString.Substring(1, rawParsedString.Length - 2).Replace("\\\"", "\"");
        }

        private static Dictionary<string, object> CoalesceNamesAndValues(List<string> names, List<object> values, List<string> titles)
        {
            Dictionary<string, object> coalesced = new();
            for (int i = 0; i < names.Count; i++)
            {
                string name = names[i];
                object value = values[i];
                if (value is List<object>)
                {
                    string title = null != titles && titles.Count > i ? titles[i] : names[i];
                    coalesced[name] = new TitleAndValue { Title = title, Value = value };
                }
                else
                {
                    coalesced[name] = value;
                }
            }
            return coalesced;
        }
    }

    public class TitleAndValue
    {
        public string Title;
        public object Value;
    }
}
