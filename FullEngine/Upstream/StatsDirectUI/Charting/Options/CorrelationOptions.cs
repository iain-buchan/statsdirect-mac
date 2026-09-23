using System;

namespace StatsDirect.Charting
{
    [Serializable]
    public class CorrelationOptions : GenericOptions
    {
        public int K { get; }
        public string[] Titles { get; }
        public double[] Odr { get; }
        public double[] Odrl { get; }
        public double[] Odru { get; }
        public double[] Gn { get; }
        public CorrelationRowType[] Pg { get; }
        public string Cap { get; }
        public string Qid { get; }
        public Transformation Xform { get; }
        public bool IsDifference { get; }
        public override bool ShowLegendIsRelevant => false;

        public override void Accept(IChartOptionVisitor visitor)
        {
            visitor.Visit(this);
        }

        public CorrelationOptions(int k, string[] titles, double[] odr, double[] odrl, double[] odru, double[] gn, CorrelationRowType[] pg, string cap, string qid, Transformation xform, bool isDifference)
        {
            K = k;
            Titles = titles;
            Odr = odr;
            Odrl = odrl;
            Odru = odru;
            Gn = gn;
            Pg = pg;
            Cap = cap;
            Qid = qid;
            Xform = xform;
            IsDifference = isDifference;
        }
    }
}
