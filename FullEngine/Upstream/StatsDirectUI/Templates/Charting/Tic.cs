namespace StatsDirect.Templates
{
    /// <summary>
    /// A tic is a mark on a chart axis.  It appears at some point on the axis (stored in chart co-ordinates), with a given label.
    /// </summary>
    public class Tic
    {
        public double Value { get; }
        public string Label { get; }

        public Tic (double value, string label)
        {
            Value = value;
            Label = label;
        }
    }
}
