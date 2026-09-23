using System;

namespace StatsDirect.Charting
{
    [Serializable]
    public class XyzOptions : GenericOptions
    {
        public double[] x;
        public double[] y;
        public double[] z;
        public bool zPlot;
        public DataMinMax minMaxY;
        public override bool ShowLegendIsRelevant => false;

        public override void Accept(IChartOptionVisitor visitor)
        {
            visitor.Visit(this);
        }

        public XyzOptions(double[] x, double[] y, double[] z, string xtxt, string ytxt, string title, bool zPlot, DataMinMax minMaxY)
        {
            this.x = x;
            this.y = y;
            this.z = z;
            XAxisTitle = xtxt;
            YAxisTitle = ytxt;
            Title = title;
            this.zPlot = zPlot;
            this.minMaxY = minMaxY;
        }
    }
}
