using System;
using System.Collections.Generic;
using System.IO;
using System.Net;

namespace StatsDirect.R
{
    /// <summary>
    /// HTML that the engine's Creole report cannot carry itself. A report template substitutes a value as encoded text, and
    /// the Creole grammar knows no image tag, so the chart R drew and the R script are registered here: the value in the
    /// parameter bag is a token, the template substitutes the token, and OutputReport replaces it with the HTML once the
    /// report is rendered. Fragments belong to the thread that runs the operation.
    /// </summary>
    public static class ReportFragments
    {
        const string Prefix = "statsdirectfragment";
        [ThreadStatic] static Dictionary<string, string> fragments;

        public static bool IsToken(string value) => value != null && value.StartsWith(Prefix, StringComparison.Ordinal);

        public static string Register(string html)
        {
            fragments ??= new Dictionary<string, string>();
            string token = Prefix + Guid.NewGuid().ToString("N");
            fragments[token] = html;
            return token;
        }

        public static string Resolve(string html)
        {
            if (fragments == null || fragments.Count == 0 || !html.Contains(Prefix))
                return html;
            foreach (KeyValuePair<string, string> pair in fragments)
                html = html.Replace(pair.Key, pair.Value);
            return html;
        }

        public static void Clear()
        {
            fragments = null;
        }

        /// <summary>
        /// The chart R drew for a metafile path: the PNG the Mac device wrote beside it, shown at half its pixel size because
        /// it was drawn at 144 dots per inch. The width and height attributes let the report exports size it.
        /// </summary>
        public static string Chart(string path)
        {
            string png = Path.ChangeExtension(path, ".png");
            if (!File.Exists(png))
                return Register("<p class=\"note\">(Chart not drawn: R did not save " + WebUtility.HtmlEncode(Path.GetFileName(path)) + ")</p>");
            byte[] bytes = File.ReadAllBytes(png);
            string size = string.Empty;
            if (bytes.Length > 24 && bytes[1] == (byte)'P' && bytes[2] == (byte)'N' && bytes[3] == (byte)'G')
            {
                int width = (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
                int height = (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
                if (width > 0 && height > 0)
                    size = " width=\"" + (width + 1) / 2 + "\" height=\"" + (height + 1) / 2 + "\"";
            }
            return Register("<img class=\"r-chart\" alt=\"Chart drawn by R\"" + size + " style=\"max-width:100%;height:auto\" src=\"data:image/png;base64," + Convert.ToBase64String(bytes) + "\" />");
        }

        /// <summary>The R script, preformatted.</summary>
        public static string Script(string text)
        {
            return Register("<pre class=\"r-script\">" + WebUtility.HtmlEncode(text) + "</pre>");
        }
    }
}
