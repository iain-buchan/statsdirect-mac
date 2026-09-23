namespace StatsDirect.Templates
{
    /// <summary>
    /// A convenient aggregation of preferences and progress bar, for marking methods that only require these.  TODO: Use this information to simplify calls.
    /// </summary>
    public interface IPreferencesAndProgressBar: IPreferences, IProgressBarHost
    {
    }
}
