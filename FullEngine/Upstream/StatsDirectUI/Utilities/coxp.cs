namespace StatsDirect.Utilities
{
    /// <summary>
    /// Used in coxreg and sdchart, so has to be somewhere central.
    /// </summary>
    public class CoxP
    {
        public int Stratum { get; set; }
        public double Time { get; set; }
        public int Id { get; set; }
        public int Censor { get; set; }
        public double S { get; set; }
        public double H { get; set; }
        public double Exb { get; set; }
        public int Index { get; set; }
    }
}
