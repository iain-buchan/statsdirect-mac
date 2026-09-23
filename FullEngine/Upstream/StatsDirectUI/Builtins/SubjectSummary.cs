namespace StatsDirect.Builtins
{
    class SubjectSummary
    {
        public int Index { get; set; }
        public double SubjectId { get; set; }
        public double Auc { get; set; }
        public double Baseline { get; set; }
        public double MinObservation { get; set; }
        public double MaxObservation { get; set; }
        public double TimeToMax { get; set; }
        public double SlopeToMax { get; set; }
        public double SlopeToMaxVariance { get; set; }
    }
}
