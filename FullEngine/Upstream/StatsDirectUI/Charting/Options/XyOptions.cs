using System;

namespace StatsDirect.Charting
{
    [Serializable]
    public class XyOptions : GenericOptions
    {
        public double[] X { get; }
        public double[] Y { get; }
        public bool ZPlot { get; }
        public DataMinMax MinMaxY { get; }
        public override bool ShowLegendIsRelevant => false;

        public override void Accept(IChartOptionVisitor visitor)
        {
            visitor.Visit(this);
        }

        public XyOptions(double[] x, double[] y, string xtxt, string ytxt, string title, bool zPlot, DataMinMax minMaxY)
        {
            X = x;
            Y = y;
            XAxisTitle = xtxt;
            YAxisTitle = ytxt;
            Title = title;
            ZPlot = zPlot;
            MinMaxY = minMaxY;
        }
    }
}
