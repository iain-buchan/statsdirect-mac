namespace StatsDirect.Templates
{
    /// <summary>
    /// An interface for handling formatting.  Eventually, only templates should care about this.
    /// </summary>
    public interface IFormatting
    {
        string RoundU(double amount);

        /// <summary>
        /// Format a probability, using the default number of decimal places
        /// </summary>
        string pval(double p);

        string pval_half(double p);
    }
}
