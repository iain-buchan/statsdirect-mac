using System;

namespace StatsDirect.Charting
{
    /// <summary>
    /// Immutable
    /// </summary>
    [Serializable]
    public class KaplanMeierOptions : GenericOptions
    {
        public int[,] Dead { get; }
        public int Groups { get; }
        public int[] cnx;
        public string[] GroupLabels { get; }
        public bool DrawTics { get; }
        public bool UseMarkers { get; }
        public double[,] X { get; }
        public double[,] Y { get; }
        public KaplanMeierPlotMode PlotMode { get; }
        public override bool ShowLegendIsRelevant => true;

        public override void Accept(IChartOptionVisitor visitor)
        {
            visitor.Visit(this);
        }

        public KaplanMeierOptions(int[,] dead, int groups, int[] cnx, string[] groupLabels, bool drawTics, bool useMarkers, double[,] x, double[,] y, KaplanMeierPlotMode plotMode, string xAxisTitle, string yAxisTitle, string title)
        {
            Dead = dead;
            Groups = groups;
            this.cnx = cnx;
            GroupLabels = groupLabels;
            DrawTics = drawTics;
            UseMarkers = useMarkers;
            X = x;
            Y = y;
            PlotMode = plotMode;
            XAxisTitle = xAxisTitle;
            YAxisTitle = yAxisTitle;
            Title = title;
        }
    }
}
