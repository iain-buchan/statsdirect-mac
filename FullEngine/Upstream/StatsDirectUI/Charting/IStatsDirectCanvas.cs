using System;
using System.Drawing;
using System.IO;
using StatsDirect.Templates;

namespace StatsDirect.Charting
{
    /// <summary>
    /// A chart drawing surface that is appropriate for ChartRenderer to draw on.  (0, 0) is at the bottom-left of the canvas.
    /// </summary>
    public interface IStatsDirectCanvas : IDisposable
    {
        void DrawString(string text, FontDescriptor font, BrushDescriptor brush, double x, double y, StringFormat txtFormat);

        ///  <summary>
        ///  Cases:
        ///  Left-justify: (x,y) is centre of left-hand edge of text.
        ///  Right-justify: (x,y) is centre of right-hand edge of text.
        ///  </summary>
        ///  <param name="s"></param>
        ///  <param name="font"></param>
        ///  <param name="brush"></param>
        ///  <param name="x">The </param>
        ///  <param name="y"></param>
        ///  <param name="txtFormat"></param>
        ///  <param name="direction"></param>
        void DrawStringAtAngle(string s, FontDescriptor font, BrushDescriptor brush, double x, double y, StringFormat txtFormat, LabelDirection direction);

        ///  <returns>The bounding size of s drawn with txtFormat</returns>
        SizeD MeasureStringAtAngle(string s, FontDescriptor font, LabelDirection direction);

        ///  <summary>
        ///  Draw a square of side size, centred on (x, y).
        ///  </summary>
        ///  <param name="p">The pen with which to draw the outline and, if filled, from which to take the fill colour.</param>
        ///  <param name="x"></param>
        ///  <param name="y"></param>
        ///  <param name="size"></param>
        ///  <param name="fill">If true, fill the square; if false, merely draw the outline.</param>
        ///  <remarks></remarks>
        void DrawSquare(PenDescriptor p, double x, double y, double size, bool fill);

        ///  <summary>
        ///  Draw a diamond of diameter size, centred on (x, y)
        ///  </summary>
        ///  <param name="p">The pen with which to draw the outline and, if filled, from which to take the fill colour.</param>
        ///  <param name="x"></param>
        ///  <param name="y"></param>
        ///  <param name="size"></param>
        ///  <param name="fill">If true, fill the square; if false, merely draw the outline.</param>
        /// <remarks></remarks>
        void DrawDiamond(PenDescriptor p, double x, double y, double size, bool fill);

        void DrawMarker(double x, double y, double size, MarkerShape shape, bool isFilled, PenDescriptor p);
        void DrawRectangle(PenDescriptor p, BrushDescriptor b, double x, double y, double w, double h);
        void DrawLine(PenDescriptor p, double x1, double y1, double x2, double y2);
        double GetFontHeight(FontDescriptor f);
        SizeD MeasureString(string s, FontDescriptor font);

        double Width { get; }
        double Height { get; }

        /// <summary>
        /// 
        /// </summary>
        /// <returns>A Stream which is live and, if read from its current point to its end, gives an Image.  Note that this detaches the Stream from the SDCanvas to prevent its disposal, so only call this once per SDCanvas!</returns>
        Stream DetachAndReturnImageStream();
    }
}