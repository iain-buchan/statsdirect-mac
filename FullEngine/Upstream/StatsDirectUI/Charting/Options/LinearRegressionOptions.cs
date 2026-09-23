using System;

namespace StatsDirect.Charting
{
    [Serializable]
    public class LinearRegressionOptions : ChartOptions
    {
        public double Slope { get; set; }
        public double Intercept { get; set; }
        public bool FullWidth { get; set; }

        public override bool ShowLegendIsRelevant => false;

        public override void Accept(IChartOptionVisitor visitor)
        {
            visitor.Visit(this);
        }
    }
}
