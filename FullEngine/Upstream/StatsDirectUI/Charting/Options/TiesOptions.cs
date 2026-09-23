using System;

namespace StatsDirect.Charting
{
    [Serializable]
    public class TiesOptions : GenericOptions
    {
        public double[] x;
        public double[] y;
        public int nx;
        public double lla;
        public double ula;
        public double gamma;
        public string v0Title;
        public string v1Title;
        public double mean;

        public override bool ShowLegendIsRelevant => false;

        public override void Accept(IChartOptionVisitor visitor)
        {
            visitor.Visit(this);
        }

        public TiesOptions(double[] x, double[] y, int nx, double lla, double ula, double gamma, string v0Title, string v1Title, double mean)
        {
            this.x = x;
            this.y = y;
            this.nx = nx;
            this.lla = lla;
            this.ula = ula;
            this.gamma = gamma;
            this.v0Title = v0Title;
            this.v1Title = v1Title;
            this.mean = mean;
        }
    }
}
