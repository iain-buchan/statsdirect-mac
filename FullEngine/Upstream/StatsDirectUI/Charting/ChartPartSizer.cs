using System;

using StatsDirect.Charting.Renderer;

namespace StatsDirect.Charting
{
    class ChartPartSizer : IChartSizableVisitor
    {
        private SizeD cachedSize;
        private readonly AbstractChartRenderer chartRenderer;

        public static SizeD Size(AbstractChartRenderer ch, IChartSizable sizable)
        {
            return new ChartPartSizer(ch).SizeInternal(sizable);
        }

        private ChartPartSizer(AbstractChartRenderer chartRenderer)
        {
            this.chartRenderer = chartRenderer;
        }

        private SizeD SizeInternal(IChartSizable sizable)
        {
            sizable.Accept(this);
            return cachedSize;
        }

        void IChartSizableVisitor.Visit(Legend legend)
        {
            const int INTER_ROW_GAP = 6;
            const int LEGEND_MARKER_SIZE = 6;
            const int MARKER_TO_LEGEND_GAP = 12;
            const int BORDER_WIDTH = 0;

            int rows = legend.LegendEntries.Count;
            double legendFontHeight = chartRenderer.LegendHeightInCanvasCoordinates("M");
            double rowHeight = Math.Max(LEGEND_MARKER_SIZE, legendFontHeight);
            double totalHeight = rows * rowHeight + (rows - 1) * INTER_ROW_GAP + BORDER_WIDTH * 2;

            double widestLegend = 0;
            foreach (LegendEntry entry in legend.LegendEntries)
            {
                double legendWidth = chartRenderer.LegendWidthInCanvasCoordinates(entry.Label);
                if (legendWidth > widestLegend)
                    widestLegend = legendWidth;
            }
            double totalWidth = LEGEND_MARKER_SIZE + MARKER_TO_LEGEND_GAP + widestLegend + 2 * BORDER_WIDTH;

            cachedSize = new SizeD(totalWidth, totalHeight);
        }
    }
}
