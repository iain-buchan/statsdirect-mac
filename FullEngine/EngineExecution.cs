using System;
using System.Threading;

// Protect the original engine's shared caches while allowing many suspended
// forms. A form yields this lock only at a host input boundary; its stack,
// parameter bags, report and input history remain private to its job.
internal static class EngineExecution {
    internal static readonly object Gate = new();

    internal static T WaitForInput<T>(Func<T> wait) {
        Monitor.Exit(Gate);
        try { return wait(); }
        finally { Monitor.Enter(Gate); }
    }
}
