using System;
using System.Collections.Generic;

namespace StatsDirect.Charting
{
    [Serializable]
    public class MHOptions : ForestishOptions
    {
        public double rmh { get; }
        public double ll { get; }
        public double ul { get; }
        public IList<bool> lerr { get; }
        public IList<bool> uerr { get; }
        public string cap { get; }
        public int pbias { get; }
        public string qid { get; }
        /// <summary>
        /// For test of IncludeTable, the result.  Where not required, set null to assume all true.
        /// </summary>
        public IList<bool> Included { get; }
        public int LowerBound { get; }

        public override bool ShowLegendIsRelevant => false;

        public override void Accept(IChartOptionVisitor visitor)
        {
            visitor.Visit(this);
        }

        public MHOptions(int lowerBound, int k, IList<double> odw, IList<string> titles, double rmh, double ll, double ul, double cco, IList<double> odr, IList<double> odrl, IList<double> odru, IList<bool> lerr, IList<bool> uerr, bool[] included, string cap, int pbias, string qid)
        {
            LowerBound = lowerBound;
            this.k = k;
            GroupSizes = odw;
            Titles = titles;
            this.rmh = rmh;
            this.ll = ll;
            this.ul = ul;
            this.cco = cco;
            OddsRatios = odr;
            OddsRatioLcis = odrl;
            OddsRatioUcis = odru;
            this.lerr = lerr;
            this.uerr = uerr;
            Included = included;
            this.cap = cap;
            this.pbias = pbias;
            this.qid = qid;
        }
    }
}
