namespace StatsDirect.Templates
{
    /// <summary>
    /// Something that can hand a progress reporter to the engine.
    /// </summary>
    public interface IProgressBarHost
    {
        /// <summary>
        /// Notes that an operation has started with the specified description that might take a while.
        /// A host might elect to show a progress bar at this point, for example.
        /// </summary>
        /// <param name="operationDescription"></param>
        /// <param name="provideProgress">true to indicate that the caller will provide meaningful progress information via fractionComplete in UpdateProgress, so a progress bar might be appropriate.
        /// False to indicate that the caller will provide no meaningful progress, so a marquee might be appropriate.</param>
        /// <param name="display">true (default) to display the bar, false to follow the logic but not display the bar. Occasionally useful when you want to display a bar depending on (say) the size of the calculation without requiring two code paths.</param>
        IProgressBar StartProgress(string operationDescription, bool provideProgress, bool display = true);
    }
}
