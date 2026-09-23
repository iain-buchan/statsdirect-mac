using StatsDirect.TemplateProcessing;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;

namespace StatsDirect.R
{
    partial class RResultsParser
    {
        private object PathToChart(string path)
        {
            int width;
            int height;
            using (Image i = Metafile.FromFile(path))
            {
                width = i.Width;
                height = i.Height;
            }
            using Stream s = File.OpenRead(path);
            return RtfImageConverter.MetastreamToRtf(s, width, height);
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
