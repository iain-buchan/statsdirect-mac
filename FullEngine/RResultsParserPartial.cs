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
            // The engine's scripts draw SVG (Windows through R's cairo device, the Mac through svglite); a raster still goes the PNG way.
            if (path.EndsWith(".svg", System.StringComparison.OrdinalIgnoreCase))
            {
                if (!File.Exists(path))
                    return "(Chart not drawn: R did not save " + Path.GetFileName(path) + ")";
                ReportVectorPicture vector = VectorPicture(File.ReadAllText(path));
                return vector ?? (object)("(Chart not drawn: " + Path.GetFileName(path) + " is not an SVG picture)");
            }
            string png = Path.ChangeExtension(path, ".png");
            if (!File.Exists(png))
                return "(Chart not drawn: R did not save " + Path.GetFileName(path) + ")";
            byte[] bytes = File.ReadAllBytes(png);
            if (!PngSize(bytes, out int width, out int height))
                return "(Chart not drawn: " + Path.GetFileName(png) + " is not a PNG)";
            return new ReportPicture(bytes, width, height);
        }

        /// <summary>
        /// The SVG R drew, as the engine's vector picture: the markup from the svg element on (R's XML declaration dropped), sized
        /// from the element's width and height (pt, in, cm, mm or px at 96 per inch; no unit means px) or, failing those, from the
        /// viewBox. Both quote styles are read: R's cairo device writes double quotes, svglite single ones. Null when there is no svg element.
        /// </summary>
        internal static ReportVectorPicture VectorPicture(string text)
        {
            int start = text.IndexOf("<svg", System.StringComparison.OrdinalIgnoreCase);
            if (start < 0)
                return null;
            string markup = text.Substring(start).TrimEnd();
            int end = markup.IndexOf('>');
            if (end < 0)
                return null;
            string element = markup.Substring(0, end);
            double width = Length(Attribute(element, "width")), height = Length(Attribute(element, "height"));
            if (!(width > 0 && height > 0))
            {
                string[] box = (Attribute(element, "viewBox") ?? string.Empty).Split(new[] { ' ', ',' }, System.StringSplitOptions.RemoveEmptyEntries);
                if (box.Length == 4 && double.TryParse(box[2], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out width)
                    && double.TryParse(box[3], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out height) && width > 0 && height > 0) { }
                else
                    return null;
            }
            return new ReportVectorPicture(markup, (int)System.Math.Round(width), (int)System.Math.Round(height));
        }

        static string Attribute(string element, string name)
        {
            var match = System.Text.RegularExpressions.Regex.Match(element, @"(?<![\w:-])" + name + @"\s*=\s*(""([^""]*)""|'([^']*)')", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
            return match.Success ? (match.Groups[2].Success ? match.Groups[2].Value : match.Groups[3].Value) : null;
        }

        // A CSS length in pixels at 96 to the inch; 0 when it cannot be read.
        static double Length(string value)
        {
            if (string.IsNullOrWhiteSpace(value))
                return 0;
            value = value.Trim();
            double perUnit = 1;
            foreach (var (unit, pixels) in new[] { ("pt", 96.0 / 72), ("in", 96.0), ("cm", 96.0 / 2.54), ("mm", 96.0 / 25.4), ("px", 1.0) })
                if (value.EndsWith(unit, System.StringComparison.OrdinalIgnoreCase)) { perUnit = pixels; value = value.Substring(0, value.Length - 2).Trim(); break; }
            return double.TryParse(value, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out double number) && number > 0 ? number * perUnit : 0;
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
