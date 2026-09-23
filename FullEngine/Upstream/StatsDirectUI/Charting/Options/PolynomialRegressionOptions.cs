using System;

namespace StatsDirect.Charting
{
    [Serializable]
    public class PolynomialRegressionOptions : ChartOptions
    {
        public int mode;
        public double[,] xtxi;
        public double[] bd;
        public double rss;
        public int nx;
        public int p;
        public double gamma;
        public override bool ShowLegendIsRelevant => false;

        public PolynomialRegressionOptions(string title, int mode, double[,] xtxi, double[] bd, double rss, int nx, int p, double gamma, string xAxisTitle, string yAxisTitle)
        {
            Title = title;
            XAxisTitle = xAxisTitle;
            YAxisTitle = yAxisTitle;
            this.mode = mode;
            this.xtxi = xtxi;
            this.bd = bd;
            this.rss = rss;
            this.nx = nx;
            this.p = p;
            this.gamma = gamma;
        }


        public override void Accept(IChartOptionVisitor visitor)
        {
            visitor.Visit(this);
        }
    }
}
