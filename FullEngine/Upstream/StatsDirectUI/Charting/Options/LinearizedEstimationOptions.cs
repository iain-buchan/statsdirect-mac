using System;

namespace StatsDirect.Charting
{
    [Serializable]
    public class LinearizedEstimationOptions : GenericOptions
    {
        public LinearizedEstimationOptions(string title, int model, double a, double b, string xAxisTitle, string yAxisTitle)
        {
            XAxisTitle = xAxisTitle;
            YAxisTitle = yAxisTitle;
            Title = title;
            Model = model;
            A = a;
            B = b;
        }

        public int Model { get; }
        public double A { get; }
        public double B { get; }
        public override bool ShowLegendIsRelevant => false;

        public override void Accept(IChartOptionVisitor visitor)
        {
            visitor.Visit(this);
        }
    }
}
