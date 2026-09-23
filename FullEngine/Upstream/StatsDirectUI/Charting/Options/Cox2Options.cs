using StatsDirect.Data;
using System;

namespace StatsDirect.Charting
{
    [Serializable]
    public class Cox2Options : GenericOptions
    {
        public int[] gn { get; }
        public int igroups { get; }
        public double[] xp { get; }
        public double[] yp { get; }
        public ColumnData[] cdat1 { get; }
        public int groupid { get; }
        public override bool ShowLegendIsRelevant => true;

        public override void Accept(IChartOptionVisitor visitor)
        {
            visitor.Visit(this);
        }

        public Cox2Options(int[] gn, int igroups, double[] xp, double[] yp, ColumnData[] cdat1, int groupid)
        {
            this.gn = gn;
            this.igroups = igroups;
            this.xp = xp;
            this.yp = yp;
            this.cdat1 = cdat1;
            this.groupid = groupid;
        }
    }
}
