using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using StatsDirect.Templates;

namespace StatsDirect.Charting
{
    /// <summary>
    /// A chart drawing surface that is backed with an Enhanced Metafile.
    /// </summary>
    class EmfCanvas : IStatsDirectCanvas
    {
        private Metafile metafile;
        private Graphics metafileGraphics;
        private Stream outputStream;

        public double Width { get; }

        public double Height { get; }

        public EmfCanvas(double width, double height)
        {
            Width = width;
            Height = height;
            SetupGraphics();
        }

        private void SetupGraphics()
        {
            outputStream = new MemoryStream();
            //  Create temporary graphics object for metafile creation and get handle to its device context.
            using Bitmap b = new(1, 1, PixelFormat.Format32bppArgb);
            using Graphics newGraphics = Graphics.FromImage(b);
            //  Create metafile object to do the recording.
            IntPtr hdc = newGraphics.GetHdc();
            metafile = new Metafile(outputStream, hdc, new RectangleF(0, 0, (float)Width, (float)Height), MetafileFrameUnit.Pixel, EmfType.EmfPlusDual);
            newGraphics.ReleaseHdc(hdc);

            metafileGraphics = Graphics.FromImage(metafile);
            metafileGraphics.SmoothingMode = SmoothingMode.AntiAlias;
        }

        public void DrawString(string s, FontDescriptor font, BrushDescriptor b, double x, double y, StringFormat txtFormat)
        {
            if (null != b)
            {
                Brush brush = GetBrush(b);
                if (null != brush)
                    metafileGraphics.DrawString(s, FontCache.Font(font), brush, Convert.ToSingle(x), Convert.ToSingle(Height - y), txtFormat);
            }
        }

        ///  <summary>
        ///  Cases:
        ///  Left-justify: (x,y) is centre of left-hand edge of text.
        ///  Right-justify: (x,y) is centre of right-hand edge of text.
        ///  </summary>
        ///  <param name="s"></param>
        ///  <param name="font"></param>
        ///  <param name="brush"></param>
        ///  <param name="x"></param>
        ///  <param name="y"></param>
        ///  <param name="txtFormat"></param>
        ///  <param name="direction"></param>
        ///  <returns>The bounding size of s drawn in direction with txtFormat</returns>
        /// <remarks></remarks>
        public void DrawStringAtAngle(string s, FontDescriptor font, BrushDescriptor b, double x, double y, StringFormat txtFormat, LabelDirection direction)
        {
            //  Work out how to fiddle the text alignment
            if (txtFormat.LineAlignment == StringAlignment.Center && txtFormat.Alignment == StringAlignment.Far)
            {
                //  Middle-right: Vertical text needs fiddling, otherwise we're OK.
                if (direction == LabelDirection.Up)
                {
                    txtFormat = (StringFormat)txtFormat.Clone();
                    txtFormat.LineAlignment = StringAlignment.Far;
                    txtFormat.Alignment = StringAlignment.Center;
                }
                else if (direction == LabelDirection.Down)
                {
                    txtFormat = (StringFormat)txtFormat.Clone();
                    txtFormat.LineAlignment = StringAlignment.Near;
                    txtFormat.Alignment = StringAlignment.Center;
                }
            }
            else if (txtFormat.LineAlignment == StringAlignment.Near && txtFormat.Alignment == StringAlignment.Center)
            {
                //  Top-centre: Anything other than across needs fiddling.
                if (direction == LabelDirection.Down || direction == LabelDirection.SlopeDown)
                {
                    txtFormat = (StringFormat)txtFormat.Clone();
                    txtFormat.LineAlignment = StringAlignment.Center;
                    txtFormat.Alignment = StringAlignment.Near;
                }
                else if (direction == LabelDirection.SlopeUp || direction == LabelDirection.Up)
                {
                    txtFormat = (StringFormat)txtFormat.Clone();
                    txtFormat.LineAlignment = StringAlignment.Center;
                    txtFormat.Alignment = StringAlignment.Far;
                }
            }
            if (null != b)
            {
                Brush brush = GetBrush(b);
                if (null != brush)
                {
                    float angle = DirectionToAngle(direction);
                    metafileGraphics.TranslateTransform(Convert.ToSingle(x), Convert.ToSingle(Height - y));
                    metafileGraphics.RotateTransform(angle);
                    metafileGraphics.DrawString(s, FontCache.Font(font), brush, 0, 0, txtFormat);
                    // Undo the transform
                    metafileGraphics.RotateTransform(0f - angle);
                    metafileGraphics.TranslateTransform(0f - Convert.ToSingle(x), 0f - Convert.ToSingle(Height - y));
                }
            }
        }

        public SizeD MeasureStringAtAngle(string s, FontDescriptor font, LabelDirection direction)
        { 
            SizeF uprightSize = metafileGraphics.MeasureString(s, FontCache.Font(font));
            SizeD boundingSize = ToBoundingSize(uprightSize, direction);
            return boundingSize;
        }

        private static float DirectionToAngle(LabelDirection direction)
        {
            switch (direction)
            {
                case LabelDirection.Across:
                    return 0.0F;
                case LabelDirection.Up:
                    return -90.0F;
                case LabelDirection.Down:
                    return 90.0F;
                case LabelDirection.SlopeUp:
                    return -45.0F;
                case LabelDirection.SlopeDown:
                    return 45.0F;
            }

            return 0;
        }

        public static SizeD ToBoundingSize(SizeF uprightSize, LabelDirection direction)
        {
            switch (direction)
            {
                case LabelDirection.Across:
                    return new SizeD(uprightSize.Width, uprightSize.Height);
                case LabelDirection.Up:
                case LabelDirection.Down:
                    return new SizeD(uprightSize.Height, uprightSize.Width);
                case LabelDirection.SlopeDown:
                case LabelDirection.SlopeUp:
                    float diagonal = Convert.ToSingle((uprightSize.Width + uprightSize.Height) * Math.Sin(Math.PI / 4.0));
                    return new SizeD(diagonal, diagonal);
            }

            return SizeD.Empty;
        }

        public SizeD MeasureString(string s, FontDescriptor font)
        {
            SizeF sizeF = metafileGraphics.MeasureString(s, FontCache.Font(font));
            return new SizeD(sizeF.Width, sizeF.Height);
        }

        public Stream DetachAndReturnImageStream()
        {
            if (null != metafileGraphics)
            {
                metafileGraphics.Dispose();
                metafileGraphics = null;
            }
            if (null != metafile)
            {
                metafile.Dispose();
                metafile = null;
            }
            if (null == outputStream)
                return null;
            Stream temp = outputStream;
            outputStream = null;
            temp.Position = 0;
            return temp;
        }

        ///  <summary>
        ///  Draw a square of side size, centred on (x, y).
        ///  </summary>
        ///  <param name="p">The pen with which to draw the outline and, if filled, from which to take the fill colour.</param>
        ///  <param name="x"></param>
        ///  <param name="y"></param>
        ///  <param name="size"></param>
        ///  <param name="fill">If true, fill the square; if false, merely draw the outline.</param>
        ///  <remarks></remarks>
        public void DrawSquare(PenDescriptor p, double x, double y, double size, bool fill)
        {
            double size2 = size / 2;
            PointF[] pt = new PointF[5];
            pt[0].X = Convert.ToSingle(x - size2);
            pt[0].Y = Convert.ToSingle(Height - (y - size2));
            pt[1].X = Convert.ToSingle(x - size2);
            pt[1].Y = Convert.ToSingle(Height - (y + size2));
            pt[2].X = Convert.ToSingle(x + size2);
            pt[2].Y = Convert.ToSingle(Height - (y + size2));
            pt[3].X = Convert.ToSingle(x + size2);
            pt[3].Y = Convert.ToSingle(Height - (y - size2));
            pt[4].X = Convert.ToSingle(x - size2);
            pt[4].Y = Convert.ToSingle(Height - (y - size2));
            DrawAndOrFillPolygon(p, fill, pt);
        }

        ///  <summary>
        ///  Draw a diamond of diameter size, centred on (x, y)
        ///  </summary>
        ///  <param name="p">The pen with which to draw the outline and, if filled, from which to take the fill colour.</param>
        ///  <param name="x"></param>
        ///  <param name="y"></param>
        ///  <param name="size"></param>
        ///  <param name="fill">If true, fill the square; if false, merely draw the outline.</param>
        /// <remarks></remarks>
        public void DrawDiamond(PenDescriptor p, double x, double y, double size, bool fill)
        {
            double size2 = size / 2;
            PointF[] pt = new PointF[5];
            pt[0].X = Convert.ToSingle(x - size2);
            pt[0].Y = Convert.ToSingle(Height - y);
            pt[1].X = Convert.ToSingle(x);
            pt[1].Y = Convert.ToSingle(Height - (y - size2));
            pt[2].X = Convert.ToSingle(x + size2);
            pt[2].Y = Convert.ToSingle(Height - y);
            pt[3].X = Convert.ToSingle(x);
            pt[3].Y = Convert.ToSingle(Height - (y + size2));
            pt[4].X = Convert.ToSingle(x - size2);
            pt[4].Y = Convert.ToSingle(Height - y);
            DrawAndOrFillPolygon(p, fill, pt);
        }

        private void DrawAndOrFillPolygon(PenDescriptor p, bool fill, PointF[] pt)
        {
            if (fill)
            {
                using Brush b = new SolidBrush(ToColor(p.Color));
                metafileGraphics.FillPolygon(b, pt);
            }
            // Draw the diamond
            metafileGraphics.DrawPolygon(GetPen(p), pt);
        }

        private Color ToColor(ColorDescriptor color)
        {
            return Color.FromArgb(color.R, color.G, color.B);
        }

        public void DrawMarker(double x, double y, double size, MarkerShape shape, bool isFilled, PenDescriptor p)
        {
            double size2 = size * 2;
            BrushDescriptor b = isFilled ? new BrushDescriptor(p.Color) : null;
            PenDescriptor pd = isFilled ? PenDescriptor.White : p;

            switch (shape)
            {
                case MarkerShape.Circle:
                    if (isFilled)
                        FillEllipse(new BrushDescriptor(p.Color), x - size, y + size, size2, size2);
                    else
                        DrawEllipse(p, x - size, y + size, size2, size2);
                    break;
                case MarkerShape.Square:
                    DrawRectangle(p, b, x - size, y + size, size2, size2);
                    break;
                case MarkerShape.Triangle:
                    {
                        PointF[] points =
                        {
                            new PointF(Convert.ToSingle(x - size), Convert.ToSingle(Height - (y - size))),
                            new PointF(Convert.ToSingle(x), Convert.ToSingle(Height - (y + size))),
                            new PointF(Convert.ToSingle(x + size), Convert.ToSingle(Height - (y - size)))
                        };
                        if (isFilled)
                            metafileGraphics.FillPolygon(GetBrush(b), points); // Guaranteed not to be called with a null brush
                        else
                            metafileGraphics.DrawPolygon(GetPen(p), points);
                    }
                    break;
                case MarkerShape.Plus:
                    //  Same filled or unfilled
                    DrawLine(p, x - size, y, x + size, y);
                    DrawLine(p, x, y - size, x, y + size);
                    break;
                case MarkerShape.Cross:
                    //  Same filled or unfilled
                    DrawLine(p, x - size, y - size, x + size, y + size);
                    DrawLine(p, x - size, y + size, x + size, y - size);
                    break;
                case MarkerShape.CircleLine:
                    if (isFilled)
                        FillEllipse(new BrushDescriptor(p.Color), x - size, y + size, size2, size2);
                    else
                        DrawEllipse(p, x - size, y + size, size2, size2);
                    DrawLine(pd, x, y - size, x, y + size);
                    break;
                case MarkerShape.SquareLine:
                    DrawRectangle(p, b, x - size, y + size, size2, size2);
                    DrawLine(pd, x - size, y + size, x + size, y - size);
                    break;
                case MarkerShape.SquareCross:
                    DrawRectangle(p, b, x - size, y + size, size2, size2);
                    DrawLine(pd, x - size, y - size, x + size, y + size);
                    DrawLine(pd, x - size, y + size, x + size, y - size);
                    break;
                case MarkerShape.Diamond:
                    DrawDiamond(p, x, y, size2, isFilled);
                    break;
                case MarkerShape.SurvivalTic:
                    DrawLine(p, x - size, y - size, x + size, y - size);
                    DrawLine(p, x + size, y - size, x + size, y + size);
                    break;
                default:
                    throw new ArgumentException("Don't know how to draw style's shape", nameof(shape));
            }
        }

        private void FillEllipse(BrushDescriptor b, double x, double y, double w, double h)
        {
            if (null != b)
            {
                Brush brush = GetBrush(b);
                if (null != brush)
                    metafileGraphics.FillEllipse(brush, Convert.ToInt32(Convert.ToSingle(x)), Convert.ToInt32(Convert.ToSingle(Height - y)), Convert.ToInt32(Convert.ToSingle(w)), Convert.ToInt32(Convert.ToSingle(h)));
            }
        }

        private void DrawEllipse(PenDescriptor p, double x, double y, double w, double h)
        {
            metafileGraphics.DrawEllipse(GetPen(p), Convert.ToSingle(x), Convert.ToSingle(Height - y), Convert.ToSingle(w), Convert.ToSingle(h));
        }

        private Brush GetBrush(BrushDescriptor b)
        {
            // TODO: Cache
            return ToBrush(b);
        }

        public void DrawRectangle(PenDescriptor p, BrushDescriptor b, double x, double y, double w, double h)
        {
            if (null != b)
            {
                Brush brush = GetBrush(b);
                if (null != brush)
                    metafileGraphics.FillRectangle(brush, Convert.ToSingle(x), Convert.ToSingle(Height - y), Convert.ToSingle(w), Convert.ToSingle(h));
            }
            if (null != p)
                metafileGraphics.DrawRectangle(GetPen(p), Convert.ToSingle(x), Convert.ToSingle(Height - y), Convert.ToSingle(w), Convert.ToSingle(h));
        }

        private Pen GetPen(PenDescriptor p)
        {
            // TODO: Cache
            return new Pen(ToColor(p.Color), (float)p.LineThickness) { DashStyle = ToDashStyle(p.DashStyle) };
        }

        private DashStyle ToDashStyle(DashStyleDescriptor dashStyle)
        {
            switch (dashStyle)
            {
                case DashStyleDescriptor.Solid:
                    return DashStyle.Solid;
                case DashStyleDescriptor.Dash:
                    return DashStyle.Dash;
                case DashStyleDescriptor.Dot:
                    return DashStyle.Dot;
                case DashStyleDescriptor.DashDot:
                    return DashStyle.DashDot;
                case DashStyleDescriptor.DashDotDot:
                    return DashStyle.DashDotDot;
                default:
                    return DashStyle.Custom;
            }
        }

        public void DrawLine(PenDescriptor p, double x1, double y1, double x2, double y2)
        {
            metafileGraphics.DrawLine(GetPen(p), Convert.ToSingle(Math.Round(x1, 0)), Convert.ToSingle(Math.Round(Height - y1, 0)), Convert.ToSingle(Math.Round(x2, 0)), Convert.ToSingle(Math.Round(Height - y2, 0)));
        }

        public double GetFontHeight(FontDescriptor f)
        {
            return FontCache.Font(f).GetHeight(metafileGraphics);
        }

        #region IDisposable Support
        private bool disposedValue;

        protected virtual void Dispose(bool disposing)
        {
            if (!disposedValue)
            {
                if (disposing)
                {
                    metafile?.Dispose();
                    metafileGraphics?.Dispose();
                    outputStream?.Dispose();
                }

                disposedValue = true;
            }
        }

        public void Dispose()
        {
            Dispose(true);
        }
        #endregion

        private Brush ToBrush(BrushDescriptor b)
        {
            switch (b.FillStyle)
            {
                case FillStyle.None:
                    return null;
                case FillStyle.Crosshatch:
                    return new HatchBrush(HatchStyle.DiagonalCross, ToColor(b.Color), Color.White);
                case FillStyle.BackwardDiagonal:
                    return new HatchBrush(HatchStyle.BackwardDiagonal, ToColor(b.Color), Color.White);
                case FillStyle.ForwardDiagonal:
                    return new HatchBrush(HatchStyle.ForwardDiagonal, ToColor(b.Color), Color.White);
                case FillStyle.Solid:
                    return new SolidBrush(ToColor(b.Color));
                default:
                    throw new ArgumentOutOfRangeException(nameof(b), b.FillStyle, "FillStyle Values between 0 and 4 accepted");
            }
        }
    }
}
