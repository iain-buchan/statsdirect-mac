namespace StatsDirect.Charting
{
    public class BinsDescriptor
    {
        /// <summary>
        /// One count per bin
        /// </summary>
        public int[] Counts { get; set; }
        /// <summary>
        /// One edge per bin, plus the upper edge of the last bin in Edges[Edges.Length - 1].
        /// </summary>
        public double[] Edges { get; set; }
        public int Bins => Counts.Length;
        public double LowestEdge => Edges[0];
        public double HighestEdge => Edges[Edges.Length - 1];
    }
}
