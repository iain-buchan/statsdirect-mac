using System;
using System.Drawing;
namespace StatsDirect.Charting {
    // The vector canvas needs alignment values only. This local type keeps the
    // original chart renderers independent of System.Drawing's Windows GDI object.
    public sealed class StringFormat : IDisposable, ICloneable {
        public StringAlignment Alignment { get; set; } = StringAlignment.Near;
        public StringAlignment LineAlignment { get; set; } = StringAlignment.Near;
        public object Clone() => MemberwiseClone();
        public void Dispose() { }
    }
}
