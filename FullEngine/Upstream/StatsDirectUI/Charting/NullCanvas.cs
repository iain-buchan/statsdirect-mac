using StatsDirect.Templates;
using System;
using System.Drawing;
using System.IO;

namespace StatsDirect.Charting
{
    /// <summary>
    /// A chart drawing surface that does nothing, and is used when you want to get parameters out of a charting call without plotting anything.
    /// </summary>
    partial class NullCanvas : IStatsDirectCanvas
    {
        public double Width { get => 0; }
        public double Height { get => 0; }

        public NullCanvas(double width, double height)
        {
        }

        public void DrawString(string s, FontDescriptor font, BrushDescriptor brush, double x, double y, StringFormat txtFormat)
        {
        }

        public void DrawStringAtAngle(string s, FontDescriptor font, BrushDescriptor brush, double x, double y, StringFormat txtFormat, LabelDirection direction)
        {
        }

        public SizeD MeasureStringAtAngle(string s, FontDescriptor font, LabelDirection direction)
        {
            return SizeD.Empty;
        }

        public SizeD MeasureString(string s, FontDescriptor font)
        {
            return SizeD.Empty;
        }

        public void DrawSquare(PenDescriptor p, double x, double y, double size, bool fill)
        {
        }

        public void DrawDiamond(PenDescriptor p, double x, double y, double size, bool fill)
        {
        }

        public void DrawMarker(double x, double y, double size, MarkerShape shape, bool isFilled, PenDescriptor p)
        {
        }

        private void DrawEllipse(PenDescriptor p, BrushDescriptor b, double x, double y, double w, double h)
        {
        }

        public void DrawRectangle(PenDescriptor p, BrushDescriptor b, double x, double y, double w, double h)
        {
        }

        public void DrawLine(PenDescriptor p, double x1, double y1, double x2, double y2)
        {
        }

        public double GetFontHeight(FontDescriptor f)
        {
            return 0;
        }

        #region IDisposable Support
        private bool disposedValue;

        protected virtual void Dispose(bool disposing)
        {
            if (!disposedValue)
            {
                if (disposing)
                {
                }

                disposedValue = true;
            }
        }

        public void Dispose()
        {
            Dispose(true);
        }

        public Stream DetachAndReturnImageStream()
        {
            throw new NotImplementedException();
        }
        #endregion
    }
}
