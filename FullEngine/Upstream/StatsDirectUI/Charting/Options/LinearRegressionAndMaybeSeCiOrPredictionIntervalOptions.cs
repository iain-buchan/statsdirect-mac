using System;

namespace StatsDirect.Charting
{
    [Serializable]
    public class LinearRegressionAndMaybeSeCiOrPredictionIntervalOptions : LinearRegressionOptions
    {
        public double pert;
        public int nx;
        public double ms;
        public double sumx;
        public double ssx;
        public bool isPredictionInterval;

        public LinearRegressionAndMaybeSeCiOrPredictionIntervalOptions(string title, double slope, double intercept, bool fullWidth, string xAxisTitle, string yAxisTitle, double pert, int nx, double ms, double sumx, double ssx, bool isPredictionInterval)
        {
            Title = title;
            Slope = slope;
            Intercept = intercept;
            FullWidth = fullWidth;
            XAxisTitle = xAxisTitle;
            YAxisTitle = yAxisTitle;
            this.pert = pert;
            this.nx = nx;
            this.ms = ms;
            this.sumx = sumx;
            this.ssx = ssx;
            this.isPredictionInterval = isPredictionInterval;
        }

        public override bool ShowLegendIsRelevant => false;

        public override void Accept(IChartOptionVisitor visitor)
        {
            visitor.Visit(this);
        }
    }
}
