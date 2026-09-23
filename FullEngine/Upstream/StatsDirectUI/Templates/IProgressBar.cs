using System;

namespace StatsDirect.Templates
{
    /// <summary>
    /// Callback interface for a progress bar.
    /// </summary>
    public interface IProgressBar : IDisposable
    {
        /// <summary>
        /// Notes that any current progress operation has now finished.
        /// A host that shows a progress bar might hide the progress bar, for example.
        /// </summary>
        void Finish();

        /// <summary>
        /// A long-running operation is now fractionComplete complete, ranging from 0.0 to 1.0.
        /// A host may elect to update its progress notification.
        /// </summary>
        /// <param name="fractionComplete"></param>
        /// <returns>true if the caller should abandon the long-running operation, false if the operation should continue.</returns>
        bool Update(double fractionComplete);
    }
}
