using System;
using System.IO;
using System.Threading;

namespace StatsDirect.Utilities
{
    /// <summary>
    /// Diagnostic trace of the start-up check for a new version: one line per step in %TEMP%\StatsDirect-diagnostics.log.
    /// </summary>
    internal static class DiagnosticLog
    {
        private static readonly object Gate = new();

        internal static void Write(string message)
        {
            try
            {
                string line = $"{DateTime.Now:HH:mm:ss.fff} thread {Environment.CurrentManagedThreadId} {message}{Environment.NewLine}";
                lock (Gate)
                    File.AppendAllText(Path.Combine(Path.GetTempPath(), "StatsDirect-update-check.log"), line);
            }
            catch (Exception)
            {
                // a diagnostic only
            }
        }
    }
}
