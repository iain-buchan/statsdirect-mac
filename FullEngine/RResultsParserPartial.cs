using StatsDirect.Templates;
using System.Collections.Generic;
using System.IO;

namespace StatsDirect.R
{
    /// <summary>
    /// The hand-written half of the results parser. Windows reads the picture R drew with System.Drawing and returns it as a
    /// ReportPicture, which the HTML renderer embeds. Here the picture is the PNG R wrote (the metafile shim in RController, or
    /// png() in the script itself). Its size in the report comes from the PNG's own resolution, so a chart drawn at 144 dots
    /// per inch for a Retina display shows at the size R intended.
    /// </summary>
    partial class RResultsParser
    {
        private object PathToChart(string path)
        {
            string png = Path.ChangeExtension(path, ".png");
            if (!File.Exists(png))
                return "(Chart not drawn: R did not save " + Path.GetFileName(path) + ")";
            byte[] bytes = File.ReadAllBytes(png);
            if (!PngSize(bytes, out int width, out int height))
                return "(Chart not drawn: " + Path.GetFileName(png) + " is not a PNG)";
            return new ReportPicture(bytes, width, height);
        }

        /// <summary>The PNG's width and height as CSS pixels: its pixel size scaled by its recorded resolution, 144 dots per inch when it records none.</summary>
        internal static bool PngSize(byte[] bytes, out int width, out int height)
        {
            width = height = 0;
            if (bytes.Length < 33 || bytes[1] != (byte)'P' || bytes[2] != (byte)'N' || bytes[3] != (byte)'G')
                return false;
            int Int(int at) => (bytes[at] << 24) | (bytes[at + 1] << 16) | (bytes[at + 2] << 8) | bytes[at + 3];
            int pixelWidth = Int(16), pixelHeight = Int(20);
            double dotsPerInch = 144;
            for (int at = 8; at + 12 <= bytes.Length;)
            {
                int length = Int(at);
                string type = System.Text.Encoding.ASCII.GetString(bytes, at + 4, 4);
                if (type == "pHYs" && length == 9 && at + 8 + 9 <= bytes.Length && bytes[at + 16] == 1)
                {
                    int perMetre = Int(at + 8);
                    if (perMetre > 0) dotsPerInch = perMetre * 0.0254;
                    break;
                }
                if (type == "IDAT" || type == "IEND" || length < 0)
                    break;
                at += 12 + length;
            }
            width = (int)System.Math.Round(pixelWidth * 96 / dotsPerInch);
            height = (int)System.Math.Round(pixelHeight * 96 / dotsPerInch);
            return width > 0 && height > 0;
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
