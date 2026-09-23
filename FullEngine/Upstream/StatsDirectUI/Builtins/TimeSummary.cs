namespace StatsDirect.Builtins
{
    class TimeSummary
    {
        public int Index { get; set; }
        public double Time { get; set; }
        public int N { get; set; }
        public double Sum { get; set; }
        public double Mean { get; set; }
        public double Variance { get; set; }
        public double Sd { get; set; }
        public double Se { get; set; }
        public double Weight { get; set; }
        public double MeanTimesWeight { get; set; }
        public double VarTWeighted { get; set; }
        public double DfDenominator { get; set; }
        public double Median { get; set; }
        public double LowerQuartile { get; set; }
        public double UpperQuartile { get; set; }
        public double InterquartileRange { get; set; }
    }
}
