using System;

namespace StatsDirect.Charting
{
    [Serializable]
    public class LAbbeOptions : GenericOptions
    {
        public int k;
        public double[,] o;
        public double rmh;
        public override bool ShowLegendIsRelevant => false;

        public override void Accept(IChartOptionVisitor visitor)
        {
            visitor.Visit(this);
        }

        public LAbbeOptions(int k, double[,] o, double rmh)
        {
            this.k = k;
            this.o = o;
            this.rmh = rmh;
        }
    }
}
