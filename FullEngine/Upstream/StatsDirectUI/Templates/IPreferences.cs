namespace StatsDirect.Templates
{
    /// <summary>
    /// An interface for retrieving preferences that the engine needs to know about.  Eventually, IFormatting will be removed from this.
    /// </summary>
    public interface IPreferences : IFormatting
    {
        /// <summary>
        /// The current set of preferences.
        /// Hosts MAY provide a way to change these through the interface.  If they do, they SHOULD persist them between invocations.
        /// </summary>
        SDPreferences Preferences { get; }
    }
}
