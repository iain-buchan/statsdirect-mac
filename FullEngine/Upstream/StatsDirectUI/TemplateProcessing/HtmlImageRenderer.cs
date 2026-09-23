using System;
using System.IO;
using System.Text;
using StatsDirect.Charting;
using StatsDirect.Templates;

namespace StatsDirect.TemplateProcessing
{
    public static class HtmlImageRenderer
    {
        private static readonly ICanvasFactory CANVAS_FACTORY = new SvgCanvasFactory();

        public static ParameterBag PlotAndReturnHtml(/* TODO: IPreferences*/ ITemplateHost host, ChartDefinition cd, out string html)
        {
            try
            {
                using IChartRenderer ch = ChartRendererFactory.ChartRendererFor(cd, CANVAS_FACTORY);
                ParameterBag results = ch.Plot(host, false);
                if (cd.IsAscii)
                    html = ch.GetAscii().Replace(Environment.NewLine, "<br />");
                else
                    html = new StreamReader(ch.Canvas.DetachAndReturnImageStream(), Encoding.UTF8).ReadToEnd();
                return results;
            }
            catch (Exception ex) when (ex is not StatsDirect.Utilities.TemplateOperationCancelledException && ex is not OutOfMemoryException)
            {
                // as in RtfImageRenderer: keep the report and say why the chart is missing
                html = "<p>(Chart not drawn: " + System.Net.WebUtility.HtmlEncode(ex.Message) + ")</p>";
                return new ParameterBag();
            }
        }
    }
}
