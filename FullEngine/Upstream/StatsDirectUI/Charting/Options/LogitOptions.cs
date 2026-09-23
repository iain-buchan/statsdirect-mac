using System;

namespace StatsDirect.Charting
{
    [Serializable]
    public class LogitOptions : GenericOptions
    {
        public int model;
        public double t;
        public double sw;
        public double s1;
        public double a;
        public double b;
        public bool modelIsLog10;
        public override bool ShowLegendIsRelevant => false;

        public override void Accept(IChartOptionVisitor visitor)
        {
            visitor.Visit(this);
        }

        public LogitOptions(string title, int model, double t, double sw, double s1, double a, double b, string xAxisTitle, string yAxisTitle, bool modelIsLog10)
        {
            Title = title;
            XAxisTitle = xAxisTitle;
            YAxisTitle = yAxisTitle;
            this.model = model;
            this.t = t;
            this.sw = sw;
            this.s1 = s1;
            this.a = a;
            this.b = b;
            this.modelIsLog10 = modelIsLog10;
        }
    }
}
