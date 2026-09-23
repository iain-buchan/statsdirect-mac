using System;

namespace StatsDirect.Charting
{
    [Serializable]
    public class BiasMAOptions : GenericOptions
    {
        public double[] x;
        public double[] yy;
        public double[] yw;
        public int rows;
        public double[] cl;
        public double[] cu;
        public double cco;
        public double cit;
        public double rmh;
        public Transformation xform;
        public bool diagonal;

        public override bool ShowLegendIsRelevant => false;

        public override void Accept(IChartOptionVisitor visitor)
        {
            visitor.Visit(this);
        }

        public BiasMAOptions(double[] x, double[] yy, double[] yw, int rows, string xtxt, double[] cl, double[] cu, double cco, double cit, double rmh, Transformation xform, bool diagonal)
        {
            this.x = x;
            this.yy = yy;
            this.yw = yw;
            this.rows = rows;
            XAxisTitle = xtxt;
            this.cl = cl;
            this.cu = cu;
            this.cco = cco;
            this.cit = cit;
            this.rmh = rmh;
            this.xform = xform;
            this.diagonal = diagonal;
        }
    }
}
