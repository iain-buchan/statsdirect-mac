namespace StatsDirect.Utilities
{
    /// <summary>
    /// Hands back integers that are known to be non-negative, distinct and monotonically increasing.  No other guarantees are provided.
    /// </summary>
    public sealed class TakeANumber
    {
        private int currentValue;

        public int Next() => currentValue++;
    }
}
