using System;
using System.IO;
using StatsDirect.Charting;
using StatsDirect.Templates;
using StatsDirect.Utilities;

namespace StatsDirect.TemplateProcessing
{
    public static class RtfImageRenderer
    {
        public static ICanvasFactory CANVAS_FACTORY = new EmfCanvasFactory();

        public static ParameterBag PlotAndReturnRtf(/* TODO: IPreferences*/ ITemplateHost host, ChartDefinition cd, out string rtf)
        {
            try
            {
                using IChartRenderer ch = ChartRendererFactory.ChartRendererFor(cd, CANVAS_FACTORY);
                ParameterBag results = ch.Plot(host, false);
                if (cd.IsAscii)
                    rtf = ch.GetAscii().Replace(Environment.NewLine, Formatting.RTFCRLF);
                else
                {
                    EmfCanvas emfCanvas = (EmfCanvas)ch.Canvas;
                    rtf = ImageStreamToRtf(emfCanvas.DetachAndReturnImageStream(), (int)emfCanvas.Width, (int)emfCanvas.Height);
                }
                return results;
            }
            catch (Exception ex) when (ex is not StatsDirect.Utilities.TemplateOperationCancelledException && ex is not OutOfMemoryException)
            {
                // A chart that cannot be drawn (for example an axis that cannot be scaled for values near 1e8 with a small
                // spread) stopped the whole report with an internal error. The report is kept, and says why the chart is missing.
                rtf = "\\par (Chart not drawn: " + RtfText(ex.Message) + ")\\par ";
                return new ParameterBag();
            }
        }

        private static string RtfText(string s)
        {
            System.Text.StringBuilder b = new();
            foreach (char c in s)
            {
                if (c == '\\' || c == '{' || c == '}')
                    b.Append('\\').Append(c);
                else if (c >= ' ' && c <= '~')
                    b.Append(c);
                else if (c == '\n')
                    b.Append(' ');
                else if (c > '~')
                    b.Append("\\u").Append((int)c).Append('?');
            }
            return b.ToString();
        }

        public static string ImageStreamToRtf(Stream stream, int width, int height)
        {
            try
            {
                return RtfImageConverter.MetastreamToRtf(stream, width, height);
            }
            catch (OutOfMemoryException ex)
            {
                throw new Exception("Couldn't convert a chart to RTF", ex);
            }
        }
    }
}
