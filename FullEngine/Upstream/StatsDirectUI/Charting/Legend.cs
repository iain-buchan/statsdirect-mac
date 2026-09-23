using System.Collections.Generic;

namespace StatsDirect.Charting
{
    /// <summary>
    /// A sequence of items to be drawn at some point on a chart as a legend.
    /// </summary>
    public class Legend : IChartSizable
    {
        public LegendPosition Position { get; set; }

        public IList<LegendEntry> LegendEntries { get; }

        public Legend()
        {
            LegendEntries = new List<LegendEntry>();
            Position = LegendPosition.Left;
        }

        void IChartSizable.Accept(IChartSizableVisitor visitor)
        {
            visitor.Visit(this);
        }
    }

    /// <summary>
    /// One item in a Legend.
    /// </summary>
    public class LegendEntry
    {
        public MarkerType MarkerType { get; set; }
        public string Label { get; set; }
    }

    public enum LegendPosition
    {
        NotSet = 0,
        Left,
        Bottom
    }
}
