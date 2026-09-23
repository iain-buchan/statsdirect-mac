using System;
using System.Collections.Generic;

namespace StatsDirect.Charting
{
    [Serializable]
    public class EffectOptions : ForestishOptions
    {
        public IList<double> ControlGroupSizes { get; }
        public IList<double> ExperimentGroupSizes { get; }
        public double rmh { get; }
        public double ll { get; }
        public double ul { get; }
        public string cap { get; }
        public int pbias { get; }
        public string qid { get; }

        public override bool ShowLegendIsRelevant => false;

        public override void Accept(IChartOptionVisitor visitor)
        {
            visitor.Visit(this);
        }

        public EffectOptions(int k, double[] controlGroupSizes, double[] experimentGroupSizes, string[] titles, double rmh, double ll, double ul, double cco, double[] oddsRatios, double[] oddsRatioLcis, double[] oddsRatioUcis, string cap, int pbias, string qid)
        {
            this.k = k;
            ControlGroupSizes = controlGroupSizes;
            ExperimentGroupSizes = experimentGroupSizes;
            Titles = titles;
            this.rmh = rmh;
            this.ll = ll;
            this.ul = ul;
            this.cco = cco;
            OddsRatios = oddsRatios;
            OddsRatioLcis = oddsRatioLcis;
            OddsRatioUcis = oddsRatioUcis;
            this.cap = cap;
            this.pbias = pbias;
            this.qid = qid;
        }
    }
}
