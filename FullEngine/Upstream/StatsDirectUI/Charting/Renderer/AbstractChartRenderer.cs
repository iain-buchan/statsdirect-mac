using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Text;
using Layout;
using StatsDirect.Charting.Scales;
using StatsDirect.Numerics;
using StatsDirect.Templates;
using StatsDirect.UI;

namespace StatsDirect.Charting.Renderer
{
    internal abstract class AbstractChartRenderer : IDisposable
    {
        protected readonly double Log2 = Math.Log(2.0);
        protected const int LegendLeftGap = 24;
        protected const int LegendTopGap = 70;
        protected const int LegendMarkerSize = 6;
        protected const int MinimumLegendGap = 6;
        protected const int LowestAllowedLegend = 30;
        protected const int MaxLabelLength = 50;
        protected const int MinimumXWhitespace = 70;
        private const double AXIS_LITTLE_TICK = 4;
        protected const double AxisBigTick = 7;
        private const int DEFAULT_METAFILE_HEIGHT = 800;
        private const int DEFAULT_METAFILE_WIDTH = 1132;
        protected const double DefaultXGap = 80;
        protected const double DefaultYGap = 80;
        protected const int LabelToAxisLabelGap = 3;
        private const int AXIS_LABEL_OFFSET_FROM_TICK = 3;

        protected const int AsciiYTxt = 3;
        protected const int AsciiXTxt = 15;
        private const int ASCII_X_EXT = 60;

        protected double DataMinX { get; set; }
        protected double DataMinGreaterThanZeroX { get; set; }
        protected double DataMaxX { get; set; }
        protected double DataMinY { get; set; }
        protected double DataMinGreaterThanZeroY { get; set; }
        protected double DataMaxY { get; set; }

        protected ChartDefinition Definition { get; set; }

        private FontDescriptor AxisLabelFontDescriptor { get; set; }
        private FontDescriptor AxisTitleFontDescriptor { get; set; }
        private FontDescriptor LabelFontDescriptor { get; set; }
        private FontDescriptor LegendFontDescriptor { get; set; }
        private FontDescriptor TitleFontDescriptor { get; set; }

        private float AxisLineThickness { get; set; }
        protected PenDescriptor AxisPen { get; private set; }
        private BrushDescriptor axisBrush;

        private bool isXAxisReversed;
        private bool isYAxisReversed;
        /// <summary>
        /// The X-position in canvas co-ordinates of the left-hand end of the chart's X-axis
        /// </summary>
        protected double XAxisCanvas { get; set; }
        /// <summary>
        /// The length in canvas co-ordinates of the chart's X-axis
        /// </summary>
        protected double XExtCanvas { get; set; }
        /// <summary>
        /// The Y-position in canvas co-ordinates of the bottom of the chart's Y-axis
        /// </summary>
        protected double YAxisCanvas { get; set; }
        protected double YExtCanvas { get; set; }

        protected double DivX { get; set; }
        protected double OffX { get; set; }
        protected double DivY { get; set; }
        protected double OffY { get; set; }

        protected int imageHeight = DEFAULT_METAFILE_HEIGHT;
        protected int imageWidth = DEFAULT_METAFILE_WIDTH;

        protected string[] TextCanvas { get; set; }

        private readonly ICanvasFactory canvasFactory;

        protected AbstractChartRenderer(ChartDefinition definition, ICanvasFactory canvasFactory)
        {
            DataMinX = double.MaxValue;
            DataMaxX = -double.MaxValue;
            DataMinY = double.MaxValue;
            DataMaxY = -double.MaxValue;

            Definition = definition;
            this.canvasFactory = canvasFactory;
            if (definition == null)
                return;
            DataMinX = definition.DataMinX;
            DataMinGreaterThanZeroX = definition.DataMinGreaterThanZeroX;
            DataMaxX = definition.DataMaxX;
            DataMinY = definition.DataMinY;
            DataMinGreaterThanZeroY = definition.DataMinGreaterThanZeroY;
            DataMaxY = definition.DataMaxY;
        }

        ///  <summary>
        ///  Sort the data for each series into ascending order.
        ///  Note and return the global minimum and maximum values.
        ///  </summary>
        /// <param name="seriesToUse"></param>
        protected static Layout.Range GetMinMaxSort(IList<ISeries> seriesToUse)
        {
            double min = double.MaxValue;
            double max = double.MinValue;
            foreach (ISeries s in seriesToUse)
            {
                DoubleSeries ds = (DoubleSeries)s;
                Array.Sort(ds.Data);
                if (ds.Data[0] < min)
                    min = ds.Data[0];
                if (ds.Data[ds.Data.Length - 1] > max)
                    max = ds.Data[ds.Data.Length - 1];
            }
            return new Layout.Range(min, max);
        }

        ///  <summary>
        ///  Prepare to plot a vector chart to the specified stream.
        ///  </summary>
        ///  <remarks></remarks>
        protected void StartVectorPlot(GenericOptions options = null, Legend legend = null)
        {
            if (!ChartPreferences.AreSharedValuesInitialised)
                ChartPreferences.InitSharedValues();

            //  Drawing objects
            if (!ReconstituteFonts())
            {
                ChartPreferences.InitFirstFonts();
                if (!ReconstituteFonts())
                    throw new Exception("Cannot find the fonts that StatsDirect uses for charting. If Calibri is not installed on your system, you can download it from https://www.microsoft.com/typography/fonts/font.aspx?FMID=1710");
            }

            AxisPen = new PenDescriptor(GrAxis, 1) { CapStyle = CapStyle.Square };
            axisBrush = BrushDescriptor.Black;

            // If we have any non-default options, set them now, so that we know what size e.g. fonts are when we're calculating e.g. legends.
            if (null != options)
                SetFontsAndThicknessesFromOptions(options);

            int extraWidth = 0;
            int extraHeight = 0;

            if (null != legend)
            {
                // Temporary canvas for sizing strings for legends
                Canvas = canvasFactory.Create(1, 1);
                switch (legend.Position)
                {
                    case LegendPosition.Bottom:
                        extraHeight += (int)Math.Ceiling(ChartPartSizer.Size(this, legend).Height);
                        break;
                    case LegendPosition.Left:
                        extraWidth += (int)Math.Ceiling(ChartPartSizer.Size(this, legend).Width);
                        break;
                    default:
                        throw new NotImplementedException("Only Left and Bottom legend locations are known");
                }
                Canvas.Dispose();
                Canvas = null;
            }

            Canvas = canvasFactory.Create(imageWidth + extraWidth, imageHeight + extraHeight);
        }

        ///  <summary>
        ///  Set up some appropriate default axes, allowing room for axis labels and for other elements that might be on the canvas.
        ///  </summary>
        ///  <remarks>Precondition: Chart is graphical, not ASCII</remarks>
        protected void DefaultAxes(Margin margin, Size axisLabelAndTicSpace)
        {
            XAxisCanvas = DefaultXGap + (margin?.Left ?? 0) + axisLabelAndTicSpace.Width;
            YAxisCanvas = DefaultYGap + (margin?.Bottom ?? 0) + axisLabelAndTicSpace.Height;
            XExtCanvas = ImageWidth - XAxisCanvas - (margin?.Right ?? 0) - DefaultXGap;
            YExtCanvas = ImageHeight - YAxisCanvas - DefaultYGap - (margin?.Top ?? 0);
        }

        protected void DefaultAsciiAxes()
        {
            XAxisCanvas = AsciiXTxt;
            XExtCanvas = ASCII_X_EXT;
            YAxisCanvas = 2; // Leave a line for the X-axis title, and another for the scale.  The axis will be plotted on line 2.
            YExtCanvas = TextCanvas.Length - 5;
        }

        private bool ReconstituteFonts()
        {
            AxisLabelFontDescriptor = ChartPreferences.DefaultAxisLabelFont;
            AxisTitleFontDescriptor = ChartPreferences.DefaultAxisTitleFont;
            LabelFontDescriptor = ChartPreferences.DefaultLabelFont;
            LegendFontDescriptor = ChartPreferences.DefaultLegendFont;
            TitleFontDescriptor = ChartPreferences.DefaultTitleFont;
            return
                null != AxisLabelFontDescriptor
                && null != AxisTitleFontDescriptor
                && null != LabelFontDescriptor
                && null != LegendFontDescriptor
                && null != TitleFontDescriptor;
        }

        ///  <summary>
        ///  Stop plotting a vector chart and release resources.
        ///  </summary>
        ///  <remarks></remarks>
        protected void EndVectorPlot()
        {
        }

        protected void DrawTitle(string title)
        {
            if (!string.IsNullOrEmpty(title))
                DrawStringInCanvasCoordinates(title, TitleFontDescriptor, BrushDescriptor.Black, XExtCanvas / 2 + XAxisCanvas, YAxisCanvas + YExtCanvas + 60, StringAlignment.Center, StringAlignment.Near);
        }

        private void DrawXAxisTitle(string title, double gapForAxisLabels)
        {
            if (!string.IsNullOrEmpty(title))
                DrawStringInCanvasCoordinates(title, AxisTitleFontDescriptor, BrushDescriptor.Black, XExtCanvas / 2 + XAxisCanvas, YAxisCanvas - gapForAxisLabels - LabelToAxisLabelGap, StringAlignment.Center, StringAlignment.Near);
        }

        private void DrawYAxisTitle(string title, double axisWidth)
        {
            double rightOfYAxisTitle = XAxisCanvas - axisWidth - LabelToAxisLabelGap;

            if (!string.IsNullOrEmpty(title))
            {
                using StringFormat txtFormat = new();
                txtFormat.Alignment = StringAlignment.Center;
                txtFormat.LineAlignment = StringAlignment.Far;
                Canvas.DrawStringAtAngle(title, AxisTitleFontDescriptor, BrushDescriptor.Black, rightOfYAxisTitle, YExtCanvas / 2.0 + YAxisCanvas, txtFormat, LabelDirection.Up);
            }
        }

        /// <summary>
        /// Draw the axes and chart title.  This must be the first drawing operation called.
        /// This is allowed to shift xAxis/xExt and yAxis/yExt around to make space.
        /// </summary>
        /// <param name="title">The title of the chart</param>
        /// <param name="x">The axis definition for the X-axis</param>
        /// <param name="y">The axis definition for the Y-axis</param>
        /// <param name="shouldBoxAxes"></param>
        /// <param name="useCalculatedScalesEvenWithDefinition"></param>
        /// <param name="legend"></param>
        /// <param name="chartAreaShape">If Square, the plot area is sized to square (the larger axis length will be reduced to the size of the smaller). If Default, the usual rectangular plot area will be used.</param>
        protected AxisScales LayoutChartAndDrawAxes(string title, AxisDefinition x, AxisDefinition y, bool shouldBoxAxes, bool useCalculatedScalesEvenWithDefinition, Legend legend = null, ChartAreaShape chartAreaShape = ChartAreaShape.Default)
        {
            SizeD legendSize = SizeD.Empty;
            if (null != legend)
                legendSize = ChartPartSizer.Size(this, legend);

            Margin plotAreaMargins = new()
            {
                Bottom = y.ExtraSpaceBeforeAxisStarts + (null != legend && legend.Position == LegendPosition.Bottom ? legendSize.Height : 0),
                Left = x.ExtraSpaceBeforeAxisStarts + (null != legend && legend.Position == LegendPosition.Left ? legendSize.Width : 0),
                Right = x.ExtraSpaceAfterAxisEnds,
                Top = y.ExtraSpaceAfterAxisEnds
            };

            Size extraSizeForAxes = CalculateAxisSizes(title, x, y, useCalculatedScalesEvenWithDefinition);

            if (IsAscii)
                DefaultAsciiAxes();
            else
                DefaultAxes(plotAreaMargins, extraSizeForAxes);
            if (ChartAreaShape.Square == chartAreaShape)
            {
                double smallerExt = Math.Min(XExtCanvas, YExtCanvas);
                XExtCanvas = smallerExt;
                YExtCanvas = smallerExt;
            }
            AxisScales ass = DrawAxes(title, x, y, shouldBoxAxes, useCalculatedScalesEvenWithDefinition, extraSizeForAxes);
            return ass;
        }

        protected AxisScales DrawAxes(string title, AxisDefinition x, AxisDefinition y, bool shouldBoxAxes, bool useCalculatedScalesEvenWithDefinition, Size extraSizeForAxes)
        {
            if (IsAscii)
            {
                if ((x.Mode & AxisMode.Line) == AxisMode.Line)
                    WriteAsciiYX((int)YAxisCanvas, (int)XAxisCanvas, new string('-', (int)XExtCanvas));

                if ((y.Mode & AxisMode.Line) == AxisMode.Line)
                {
                    for (int row = (int)YAxisCanvas + 1; row <= (int)YAxisCanvas + (int)YExtCanvas; row++)
                        WriteAsciiYX(row, (int)XAxisCanvas - 1, "|");
                }
                if ((x.Mode & AxisMode.Line) == AxisMode.Line && (y.Mode & AxisMode.Line) == AxisMode.Line)
                    WriteAsciiYX((int)YAxisCanvas, (int)XAxisCanvas - 1, "/");
            }
            else
            {
                // Draw the axis lines
                if ((x.Mode & AxisMode.Line) == AxisMode.Line)
                    AxisDrawline(XAxisCanvas, YAxisCanvas, XAxisCanvas + XExtCanvas, YAxisCanvas);

                if ((y.Mode & AxisMode.Line) == AxisMode.Line)
                    AxisDrawline(XAxisCanvas, YAxisCanvas + YExtCanvas, XAxisCanvas, YAxisCanvas);

                if (shouldBoxAxes)
                {
                    if ((x.Mode & AxisMode.Line) == AxisMode.Line)
                        AxisDrawline(XAxisCanvas + XExtCanvas, YAxisCanvas + YExtCanvas, XAxisCanvas, YAxisCanvas + YExtCanvas);
                    if ((y.Mode & AxisMode.Line) == AxisMode.Line)
                        AxisDrawline(XAxisCanvas + XExtCanvas, YAxisCanvas + YExtCanvas, XAxisCanvas + XExtCanvas, YAxisCanvas);
                }
            }

            IAxisScale xAxisScale;
            isXAxisReversed = x.Reverse;
            isYAxisReversed = y.Reverse;
            switch (x.Mode)
            {
                case AxisMode.LineOnly:
                case AxisMode.None:
                    //  Do nothing
                    xAxisScale = null;
                    DivX = 1;
                    OffX = XAxisCanvas;
                    break;
                case AxisMode.ReverseScale:
                case AxisMode.Scale:
                case AxisMode.ScaleWithoutLabels:
                    xAxisScale = DrawXScale((x.Mode & AxisMode.Labels) == AxisMode.Labels, x.ScaleType, useCalculatedScalesEvenWithDefinition);
                    // DrawXScale sets divx and offx
                    break;
                case AxisMode.Series:
                    if (null != x.Series)
                    {
                        xAxisScale = DrawXSeries(x.Series.Select(s => s.Title).ToList());
                        DivX = x.Series.Count;
                        OffX = XAxisCanvas;
                    }
                    else if (null != x.Labels)
                    {
                        xAxisScale = DrawXSeries(x.Labels);
                        DivX = x.Labels.Count;
                        OffX = XAxisCanvas;
                    }
                    else
                        xAxisScale = null;
                    break;
                default:
                    throw new NotImplementedException("Unknown X axis scale mode");
            }

            IAxisScale yAxisScale;
            switch (y.Mode)
            {
                case AxisMode.LineOnly:
                case AxisMode.None:
                    //  Do nothing
                    yAxisScale = null;
                    DivY = 1;
                    OffY = YAxisCanvas;
                    break;
                case AxisMode.ReverseScale:
                case AxisMode.Scale:
                case AxisMode.ScaleWithoutLabels:
                    yAxisScale = DrawYScale((x.Mode & AxisMode.Labels) == AxisMode.Labels, y.ScaleType, useCalculatedScalesEvenWithDefinition);
                    break;
                case AxisMode.Series:
                    if (null != y.Series)
                    {
                        yAxisScale = DrawYSeries(y.Series.Select(s => s.Title).ToList());
                        DivY = y.Series.Count;
                        OffY = YAxisCanvas;
                    }
                    else if (null != y.Labels)
                    {
                        yAxisScale = DrawYSeries(y.Labels);
                        DivY = y.Labels.Count;
                        OffY = YAxisCanvas;
                    }
                    else
                        yAxisScale = null;
                    break;
                default:
                    throw new NotImplementedException("Unknown X axis scale mode");
            }

            AxisScales axisScales = new() { X = xAxisScale, Y = yAxisScale };

            if (!IsAscii)
            {
                DrawXAxisTitle(x.Title, extraSizeForAxes.Height);
                DrawYAxisTitle(y.Title, extraSizeForAxes.Width);
            }

            // Draw the chart title now that we know it's safe to do so.
            if (IsAscii)
            {
                int chartWidth = TextCanvas[0].Length;
                string limitedTitle = title.Length > chartWidth
                    ? title.Substring(0, chartWidth - 3) + "..."
                    : title;
                int s = (chartWidth - limitedTitle.Length) / 2;
                WriteAsciiYX(TextCanvas.GetUpperBound(0), s, limitedTitle);
            }
            else
                DrawTitle(title);
            return axisScales;
        }

        protected Size CalculateAxisSizes(string title, AxisDefinition x, AxisDefinition y, bool useCalculatedScalesEvenWithDefinition)
        {
            double xHeight;
            isXAxisReversed = x.Reverse;
            isYAxisReversed = y.Reverse;
            // ReSharper disable once SwitchStatementMissingSomeCases
            switch (x.Mode)
            {
                case AxisMode.LineOnly:
                case AxisMode.None:
                    xHeight = 0;
                    break;
                case AxisMode.ReverseScale:
                case AxisMode.Scale:
                case AxisMode.ScaleWithoutLabels:
                    xHeight = CalculateXScaleHeight((x.Mode & AxisMode.Labels) == AxisMode.Labels, x.ScaleType, useCalculatedScalesEvenWithDefinition);
                    break;
                case AxisMode.Series:
                    if (null != x.Series)
                        xHeight = CalculateXSeriesHeight(x.Series.Select(s => s.Title).ToList());
                    else if (null != x.Labels)
                        xHeight = CalculateXSeriesHeight(x.Labels);
                    else
                        xHeight = 0;
                    break;
                default:
                    throw new NotImplementedException("Unknown X axis scale mode");
            }

            double yWidth;
            // ReSharper disable once SwitchStatementMissingSomeCases
            switch (y.Mode)
            {
                case AxisMode.LineOnly:
                case AxisMode.None:
                    //  Do nothing
                    yWidth = 0;
                    break;
                case AxisMode.ReverseScale:
                case AxisMode.Scale:
                case AxisMode.ScaleWithoutLabels:
                    yWidth = CalculateYScaleWidth((x.Mode & AxisMode.Labels) == AxisMode.Labels, y.ScaleType, useCalculatedScalesEvenWithDefinition);
                    break;
                case AxisMode.Series:
                    if (null != y.Series)
                        yWidth = CalculateYSeriesWidth(y.Series.Select(s => s.Title).ToList());
                    else if (null != y.Labels)
                        yWidth = CalculateYSeriesWidth(y.Labels);
                    else
                        yWidth = 0;
                    break;
                default:
                    throw new NotImplementedException("Unknown X axis scale mode");
            }

            return new Size((int)yWidth, (int)xHeight);
        }

        private IAxisScale DrawXScale(bool drawLabels, ScaleType scaleType, bool useCalculatedScalesEvenWithDefinition)
        {
            IAxisScale xAxisScale;
            if (IsAscii || drawLabels)
                xAxisScale = QAxisOrFromDefinition(DataMinX, DataMinGreaterThanZeroX, DataMaxX, false, scaleType, useCalculatedScalesEvenWithDefinition);
            else
            {
                //  Not ASCII, not drawing our own labels, so just set up 20 divisions
                xAxisScale = new LinearAxisScale(DataMinX, DataMaxX, DataMinX, DataMaxX, 5);
            }

            DataMinX = xAxisScale.MinimumDataValue;
            DataMaxX = xAxisScale.MaximumDataValue;
            DivX = Transform(xAxisScale.MaximumScaleValue, scaleType) - Transform(xAxisScale.MinimumScaleValue, scaleType);
            OffX = -(Transform(xAxisScale.MinimumScaleValue, scaleType) / DivX * XExtCanvas) + XAxisCanvas;

            if (!IsAscii)
            {
                LabelDirection direction = LabelDirection.Across;
                bool hasGridLines = false;
                DashStyleDescriptor gridLineDashStyle = DashStyleDescriptor.Solid;
                if (HasScaleParameters && Definition.ScaleParameters.X != null)
                {
                    direction = Definition.ScaleParameters.X.LabelDirection;
                    hasGridLines = Definition.ScaleParameters.X.HasGridLines;
                    gridLineDashStyle = Definition.ScaleParameters.X.GridLineDashStyle;
                }
                PenDescriptor gridLinePen = new(AxisPen.Color, 1)
                {
                    DashStyle = gridLineDashStyle
                };
                foreach (Tic tic in xAxisScale.Tics())
                {
                    double x1 = ToCanvasX(tic.Value, scaleType);
                    if (drawLabels)
                    {
                        AxisDrawStringAtAngleCT(tic.Label, x1, YAxisCanvas - AxisBigTick, direction);
                        AxisDrawline(x1, YAxisCanvas - AxisBigTick, x1, YAxisCanvas);
                    }
                    else
                    {
                        AxisDrawline(x1, YAxisCanvas - AXIS_LITTLE_TICK, x1, YAxisCanvas);
                    }
                    if (hasGridLines)
                        Canvas.DrawLine(gridLinePen, x1, YAxisCanvas, x1, YAxisCanvas + YExtCanvas);
                }
            }
            else
            {
                //  ASCII - always linear for now.  TODO: Log
                foreach (Tic tic in xAxisScale.Tics())
                {
                    string lab = tic.Label;
                    int s = ToAsciiX(tic.Value);
                    int s2 = s - (lab[0] == '-' ? 1 : 0);
                    WriteAsciiYX(AsciiYTxt - 2, s2, lab);
                    WriteAsciiYX(AsciiYTxt - 1, s, "+");
                }
            }
            return xAxisScale;
        }

        private double CalculateXScaleHeight(bool drawLabels, ScaleType scaleType, bool useCalculatedScalesEvenWithDefinition)
        {
            IAxisScale xAxisScale;
            if (IsAscii || drawLabels)
                xAxisScale = QAxisOrFromDefinition(DataMinX, DataMinGreaterThanZeroX, DataMaxX, false, scaleType, useCalculatedScalesEvenWithDefinition);
            else
            {
                //  Not ASCII, not drawing our own labels, so just set up 20 divisions
                xAxisScale = new LinearAxisScale(DataMinX, DataMaxX, DataMinX, DataMaxX, 5);
            }

            DataMinX = xAxisScale.MinimumDataValue;
            DataMaxX = xAxisScale.MaximumDataValue;
            // set a string mask that will fit OK

            double labelHeight = 0;
            if (!IsAscii)
            {
                LabelDirection direction = LabelDirection.Across;
                if (HasScaleParameters && Definition.ScaleParameters.X != null)
                    direction = Definition.ScaleParameters.X.LabelDirection;
                foreach (Tic tic in xAxisScale.Tics())
                {
                    //  Major tic - may or may not be labelled
                    if (drawLabels)
                        labelHeight = Math.Max(AxisMeasureStringAtAngle(tic.Label, direction).Height, labelHeight);
                }
            }
            else
            {
                //  ASCII
                foreach (Tic tic in xAxisScale.Tics())
                    labelHeight = Math.Max(labelHeight, tic.Label.Length);
            }
            return labelHeight + AxisBigTick;
        }

        /// <summary>
        /// A scale that the renderer wants used for its x axis in place of the definition's or a calculated one; the histogram uses it to put the tics at the bin mid-points.
        /// </summary>
        protected IAxisScale XAxisScaleOverride { get; set; }

        private IAxisScale QAxisOrFromDefinition(double qmin, double qMinGreaterThanZero, double qmax, bool isY, ScaleType scaleType, bool useCalculatedScalesEvenWithDefinition)
        {
            if (!isY && XAxisScaleOverride != null)
                return XAxisScaleOverride;
            if (Definition != null && Definition.HasScaleParameters && !useCalculatedScalesEvenWithDefinition)
            {
                //  Use the values in our scale parameters
                AxisScaleParameters asp = isY ? Definition.ScaleParameters.Y : Definition.ScaleParameters.X;
                if (asp?.AxisScale != null)
                    return asp.AxisScale;
            }
            //  If we get here, there was no prior definition - calculate it ourselves.
            return AxisScalerFactory.AxisScalerFor(scaleType).QAxis(qmin, qMinGreaterThanZero, qmax, isY, false);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="drawLabels"></param>
        /// <param name="scaleType"></param>
        /// <param name="useCalculatedScalesEvenWithDefinition"></param>
        /// <returns>The width of the axis, ticks, gap to labels, and labels</returns>
        private IAxisScale DrawYScale(bool drawLabels, ScaleType scaleType, bool useCalculatedScalesEvenWithDefinition)
        {
            const double axisLabelOffsetFromBigTick = 8;

            // find a neat axis division
            IAxisScale yAxisScale = QAxisOrFromDefinition(DataMinY, DataMinGreaterThanZeroY, DataMaxY, true, scaleType, useCalculatedScalesEvenWithDefinition);
            DataMinY = yAxisScale.MinimumDataValue;
            DataMaxY = yAxisScale.MaximumDataValue;
            DivY = Transform(yAxisScale.MaximumScaleValue, scaleType) - Transform(yAxisScale.MinimumScaleValue, scaleType);
            OffY = -(Transform(yAxisScale.MinimumScaleValue, scaleType) / DivY * YExtCanvas) + YAxisCanvas;

            // set a string mask that will fit OK
            LabelDirection direction = LabelDirection.Across;
            bool hasGridLines = false;
            DashStyleDescriptor gridLineDashStyle = DashStyleDescriptor.Solid;
            if (HasScaleParameters && Definition.ScaleParameters.Y != null)
            {
                direction = Definition.ScaleParameters.Y.LabelDirection;
                hasGridLines = Definition.ScaleParameters.Y.HasGridLines;
                gridLineDashStyle = Definition.ScaleParameters.Y.GridLineDashStyle;
            }

            if (!IsAscii)
            {
                PenDescriptor gridLinePen = new(AxisPen.Color, 1)
                {
                    DashStyle = gridLineDashStyle
                };
                foreach (Tic tic in yAxisScale.Tics())
                {
                    double y1 = ToCanvasY(tic.Value, scaleType);
                    if (drawLabels)
                    {
                        AxisDrawStringAtAngleRM(tic.Label, XAxisCanvas - (AxisBigTick + axisLabelOffsetFromBigTick), y1, direction);
                        AxisDrawline(XAxisCanvas - AxisBigTick, y1, XAxisCanvas, y1);
                    }
                    else
                    {
                        AxisDrawline(XAxisCanvas - AXIS_LITTLE_TICK, y1, XAxisCanvas, y1);
                    }
                    if (hasGridLines)
                        Canvas.DrawLine(gridLinePen, XAxisCanvas, y1, XAxisCanvas + XExtCanvas, y1);
                }
            }
            else
            {
                // ASCII
                foreach (Tic tic in yAxisScale.Tics())
                {
                    int y = ToAsciiY(tic.Value);
                    string lab = tic.Label;
                    WriteAsciiYX(y, (int)XAxisCanvas - 1 - lab.Length, lab);
                    WriteAsciiYX(y, (int)XAxisCanvas - 1, "+");
                }
            }
            return yAxisScale;
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="drawLabels"></param>
        /// <param name="scaleType"></param>
        /// <param name="useCalculatedScalesEvenWithDefinition"></param>
        /// <returns>The width of the axis, ticks, gap to labels, and labels</returns>
        private double CalculateYScaleWidth(bool drawLabels, ScaleType scaleType, bool useCalculatedScalesEvenWithDefinition)
        {
            const double axisLabelOffsetFromBigTick = 8;

            // find a neat axis division
            IAxisScale yAxisScale = QAxisOrFromDefinition(DataMinY, DataMinGreaterThanZeroY, DataMaxY, true, scaleType, useCalculatedScalesEvenWithDefinition);
            DataMinY = yAxisScale.MinimumDataValue;
            DataMaxY = yAxisScale.MaximumDataValue;

            // set a string mask that will fit OK
            LabelDirection direction = LabelDirection.Across;
            if (HasScaleParameters && Definition.ScaleParameters.Y != null)
                direction = Definition.ScaleParameters.Y.LabelDirection;

            double maxLabelWidth = 0;
            if (!IsAscii)
                foreach (Tic tic in yAxisScale.Tics())
                    if (drawLabels)
                        maxLabelWidth = Math.Max(maxLabelWidth, AxisMeasureStringAtAngle(tic.Label, direction).Width);
            return maxLabelWidth + AxisBigTick + axisLabelOffsetFromBigTick;
        }

        ///  <summary>
        ///  Draw the Y axis as a series
        ///  </summary>
        /// <returns>The width of the axis, ticks, gap to labels, and labels</returns>
        ///  <remarks>Labels are drawn centred between tics</remarks>
        private IAxisScale DrawYSeries(IList<string> labels)
        {
            const int axisLabelOffsetFromTick = 3;

            if (!IsAscii)
            {
                // Vector
                using StringFormat txtFormat = new();
                txtFormat.Alignment = StringAlignment.Far;
                txtFormat.LineAlignment = StringAlignment.Center;
                LabelDirection direction = LabelDirection.Across;
                bool hasGridLines = false;
                DashStyleDescriptor gridLineDashStyle = DashStyleDescriptor.Solid;
                if (HasScaleParameters && Definition.ScaleParameters.Y != null)
                {
                    direction = Definition.ScaleParameters.Y.LabelDirection;
                    hasGridLines = Definition.ScaleParameters.Y.HasGridLines;
                    gridLineDashStyle = Definition.ScaleParameters.Y.GridLineDashStyle;
                }
                PenDescriptor gridLinePen = new(AxisPen.Color, 1)
                {
                    DashStyle = gridLineDashStyle
                };
                double count = labels.Count;
                for (int y = 0; y < labels.Count; y++)
                {
                    double yctr = YAxisCanvas + YExtCanvas - (y + 0.5) / count * YExtCanvas;
                    double ytic = YAxisCanvas + YExtCanvas - y / count * YExtCanvas;
                    Canvas.DrawStringAtAngle(labels[y], AxisLabelFontDescriptor, axisBrush, XAxisCanvas - (AxisBigTick + axisLabelOffsetFromTick), yctr, txtFormat, direction);
                    AxisDrawline(XAxisCanvas - AxisBigTick, ytic, XAxisCanvas, ytic);
                    if (hasGridLines)
                        Canvas.DrawLine(gridLinePen, XAxisCanvas, ytic, XAxisCanvas + XExtCanvas, ytic);
                }
            }
            else
            {
                //  ASCII
                for (int y = 0; y < labels.Count; y++)
                {
                    int y2 = 3 + y * 2;
                    int l = labels[y].Length;
                    int q = 13 - l;
                    if (l >= 13)
                        q = 1;
                    WriteAsciiYX(y2, q, labels[y].Substring(0, Math.Min(l, 13)));
                    WriteAsciiYX(y2, 14, "|");
                    WriteAsciiYX(y2 + 1, 14, "+");
                }
            }

            return new CategoryAxisScale(labels.Count);
        }

        /// <returns>The width of the axis, ticks, gap to labels, and labels</returns>
        private double CalculateYSeriesWidth(IList<string> labels)
        {
            double maxLabelWidth = 0;
            if (!IsAscii)
            {
                // Vector
                LabelDirection direction = LabelDirection.Across;
                if (HasScaleParameters && Definition.ScaleParameters.Y != null)
                    direction = Definition.ScaleParameters.Y.LabelDirection;
                for (int y = 0; y < labels.Count; y++)
                    maxLabelWidth = Math.Max(maxLabelWidth, Canvas.MeasureStringAtAngle(labels[y], AxisLabelFontDescriptor, direction).Width);
            }

            return maxLabelWidth + AxisBigTick + AXIS_LABEL_OFFSET_FROM_TICK;
        }

        ///  <summary>
        ///  Draw the X axis as a series
        ///  </summary>
        private IAxisScale DrawXSeries(IList<string> labels)
        {
            if (!IsAscii)
            {
                using StringFormat txtFormat = new();
                txtFormat.Alignment = StringAlignment.Center;
                txtFormat.LineAlignment = StringAlignment.Near;
                LabelDirection direction = LabelDirection.Across;
                bool hasGridLines = false;
                DashStyleDescriptor gridLineDashStyle = DashStyleDescriptor.Solid;
                if (HasScaleParameters && Definition.ScaleParameters.X != null)
                {
                    direction = Definition.ScaleParameters.X.LabelDirection;
                    hasGridLines = Definition.ScaleParameters.X.HasGridLines;
                    gridLineDashStyle = Definition.ScaleParameters.X.GridLineDashStyle;
                }
                PenDescriptor gridLinePen = new(AxisPen.Color, 1)
                {
                    DashStyle = gridLineDashStyle
                };
                double count = labels.Count;
                for (int x = 0; x < labels.Count; x++)
                {
                    double xctr = XAxisCanvas + (x + 0.5) / count * XExtCanvas;
                    double xtic = XAxisCanvas + (x + 1.0) / count * XExtCanvas;
                    Canvas.DrawStringAtAngle(labels[x], AxisLabelFontDescriptor, axisBrush, xctr, YAxisCanvas - AxisBigTick, txtFormat, direction);
                    AxisDrawline(xtic, YAxisCanvas - AxisBigTick, xtic, YAxisCanvas);
                    if (hasGridLines)
                        Canvas.DrawLine(gridLinePen, xtic, YAxisCanvas, xtic, YAxisCanvas + YExtCanvas);
                }
            }
            return new CategoryAxisScale(labels.Count);
        }

        private double CalculateXSeriesHeight(IList<string> labels)
        {
            double maxHeight = 0;
            if (!IsAscii)
            {
                LabelDirection direction = LabelDirection.Across;
                if (HasScaleParameters && Definition.ScaleParameters.X != null)
                    direction = Definition.ScaleParameters.X.LabelDirection;
                for (int x = 0; x < labels.Count; x++)
                    maxHeight = Math.Max(maxHeight, Canvas.MeasureStringAtAngle(labels[x], AxisLabelFontDescriptor, direction).Height);
            }
            return maxHeight;
        }

        protected void AxisDrawline(double x1, double y1, double x2, double y2)
        {
            Canvas.DrawLine(AxisPen, x1, y1, x2, y2);
        }

        /// <summary>
        /// Draw axis text aligned to the right
        /// </summary>
        protected void AxisDrawStringAtAngleRM(string txt, double x1, double y1, LabelDirection direction)
        {
            using StringFormat alignTxt = new();
            alignTxt.Alignment = StringAlignment.Far;
            alignTxt.LineAlignment = StringAlignment.Center;
            Canvas.DrawStringAtAngle(txt, AxisLabelFontDescriptor, axisBrush, x1, y1, alignTxt, direction);
        }

        /// <summary>
        /// Draw axis text aligned to the right
        /// </summary>
        protected SizeD AxisMeasureStringAtAngle(string txt, LabelDirection direction)
        {
            using StringFormat alignTxt = new();
            alignTxt.Alignment = StringAlignment.Far;
            alignTxt.LineAlignment = StringAlignment.Center;
            return Canvas.MeasureStringAtAngle(txt, AxisLabelFontDescriptor, direction);
        }

        ///  <summary>
        ///  Draw axis text aligned to the centre
        ///  </summary>
        protected void AxisDrawStringAtAngleCT(string txt, double x1, double y1, LabelDirection direction)
        {
            using StringFormat alignTxt = new();
            alignTxt.Alignment = StringAlignment.Center;
            alignTxt.LineAlignment = StringAlignment.Near;
            Canvas.DrawStringAtAngle(txt, AxisLabelFontDescriptor, axisBrush, x1, y1, alignTxt, direction);
        }

        ///  <summary>
        ///  Draw axis text aligned to the centre
        ///  </summary>
        protected void AxisDrawStringAtAngleLT(string txt, double x1, double y1, LabelDirection direction)
        {
            using StringFormat alignTxt = new();
            alignTxt.Alignment = StringAlignment.Near;
            alignTxt.LineAlignment = StringAlignment.Near;
            Canvas.DrawStringAtAngle(txt, AxisLabelFontDescriptor, axisBrush, x1, y1, alignTxt, direction);
        }

        ///  <summary>
        ///  Draw legend text aligned to the left
        ///  </summary>
        protected void DrawStringLegendL(string txt, double x, double y)
        {
            DrawStringLegend(txt, x, y, StringAlignment.Near);
        }

        ///  <summary>
        ///  Draw legend text aligned to the left horizontally, middle vertically
        ///  </summary>
        ///  <remarks></remarks>
        protected void DrawStringLegendLC(string txt, double x, double y)
        {
            DrawStringLabel(txt, x, y, StringAlignment.Near, StringAlignment.Center);
        }

        ///  <summary>
        ///  Draw legend text
        ///  </summary>
        protected void DrawStringLegend(string txt, double x, double y, StringAlignment alignment)
        {
            using StringFormat alignTxt = new();
            alignTxt.Alignment = alignment;
            Canvas.DrawString(txt, LegendFontDescriptor, axisBrush, x, y, alignTxt);
        }

        ///  <summary>
        ///  Draw label text
        ///  </summary>
        protected void DrawStringLabel(string txt, double x, double y, StringAlignment alignment)
        {
            using StringFormat alignTxt = new();
            alignTxt.Alignment = alignment;
            Canvas.DrawString(txt, LabelFontDescriptor, axisBrush, x, y, alignTxt);
        }

        protected void DrawStringLabel(string txt, double x, double y, StringAlignment alignment, StringAlignment lineAlignment)
        {
            using StringFormat alignTxt = new();
            alignTxt.Alignment = alignment;
            alignTxt.LineAlignment = lineAlignment;
            Canvas.DrawString(txt, LabelFontDescriptor, axisBrush, x, y, alignTxt);
        }

        protected void DrawStringInCanvasCoordinates(string txt, FontDescriptor f, BrushDescriptor b, double x, double y, StringAlignment alignment, StringAlignment lineAlignment)
        {
            using StringFormat alignTxt = new();
            alignTxt.Alignment = alignment;
            alignTxt.LineAlignment = lineAlignment;
            Canvas.DrawString(txt, f, b, x, y, alignTxt);
        }

#if WARN_OBSOLETES
        [Obsolete("Ideally subclasses would never need to use canvas co-ordinates")]
#endif
        protected void DrawMarkerInCanvasCoordinates(double x, double y, double size, DoubleSeries series)
        {
            Canvas.DrawMarker(x, y, size, series.MarkerType.MarkerShape, series.MarkerType.IsMarkerFilled, GetMarkerPen(series.MarkerType));
        }

#if WARN_OBSOLETES
        [Obsolete("Ideally subclasses would never need to use canvas co-ordinates")]
#endif
        protected void DrawMarkerInCanvasCoordinates(double x, double y, double size, MarkerType mType)
        {
            Canvas.DrawMarker(x, y, size, mType.MarkerShape, mType.IsMarkerFilled, GetMarkerPen(mType));
        }

        protected void DrawMarkerInChartCoordinates(double x, double y, double size, MarkerType mType)
        {
            Canvas.DrawMarker(ToCanvasX(x), ToCanvasY(y), size, mType.MarkerShape, mType.IsMarkerFilled, GetMarkerPen(mType));
        }

        ///  <summary>
        ///  Draw the set of markers whose centre device co-ordinates are in xys.
        ///  </summary>
#if WARN_OBSOLETES
        [Obsolete("Ideally subclasses would never need to use canvas co-ordinates")]
#endif
        protected void DrawMarkerSeriesInCanvasCoordinates(PointF[] xys, double size, MarkerShape shape, bool isFilled, PenDescriptor markerPen, PenDescriptor linePen, bool joinMarkersWithLines, bool drawMarkers)
        {
            // sort by x, then by y
            Array.Sort(xys, new SortXThenY());

            PointF oldXy;
            if (joinMarkersWithLines)
            {
                // Plot joining lines
                // Set initial values so that the first line won't be drawn
                oldXy = xys[0];
                foreach (PointF xy in xys)
                {
                    if (xy.X >= 0 && xy.Y >= 0 && oldXy.X >= 0 && oldXy.Y >= 0 && (xy.X != oldXy.X || xy.Y != oldXy.Y))
                        DrawLineInCanvasCoordinates(linePen, xy.X, xy.Y, oldXy.X, oldXy.Y);
                    oldXy = xy;
                }
            }

            if (drawMarkers)
            {
                oldXy = new PointF(-1, -1);
                foreach (PointF xy in xys)
                {
                    if (xy.X != oldXy.X || xy.Y != oldXy.Y)
                    {
                        if (xy.X >= 0 && xy.Y >= 0)
                            DrawMarkerInCanvasCoordinates(xy.X, xy.Y, size, shape, isFilled, markerPen);
                        oldXy = xy;
                    }
                }
            }
        }

        ///  <summary>
        ///  Draw the set of markers whose centre device co-ordinates are in xys.
        ///  </summary>
#if WARN_OBSOLETES
        [Obsolete("Ideally subclasses would never need to use canvas co-ordinates")]
#endif
        protected void DrawMarkerSeriesInCanvasCoordinates(PointF[] xys, int size, MarkerType mt, bool joinMarkersWithLines, bool drawMarkers)
        {
            // sort by x, then by y
            Array.Sort(xys, new SortXThenY());

            PointF oldXy;
            if (joinMarkersWithLines)
            {
                // Plot joining lines
                // Set initial values so that the first line won't be drawn
                oldXy = xys[0];
                foreach (PointF xy in xys)
                {
                    if (xy.X >= 0 && xy.Y >= 0 && oldXy.X >= 0 && oldXy.Y >= 0 && (xy.X != oldXy.X || xy.Y != oldXy.Y))
                        DrawLineInCanvasCoordinates(GetLinePen(mt, false), xy.X, xy.Y, oldXy.X, oldXy.Y);
                    oldXy = xy;
                }
            }

            if (drawMarkers)
            {
                oldXy = new PointF(-1, -1);
                foreach (PointF xy in xys)
                {
                    if (xy.X != oldXy.X || xy.Y != oldXy.Y)
                    {
                        if (xy.X >= 0 && xy.Y >= 0)
                            DrawMarkerInCanvasCoordinates(xy.X, xy.Y, size, mt.MarkerShape, mt.IsMarkerFilled, GetMarkerPen(mt));
                        oldXy = xy;
                    }
                }
            }
        }

        protected double SafeToInt32(double d)
        {
            if (double.IsNaN(d) || d < int.MinValue || d > int.MaxValue)
                return 0;
            return Convert.ToInt32(d);
        }

        /// <summary>
        /// Convert a value from chart co-ordinates to canvas co-ordinates
        /// </summary>
        /// <param name="chartValue"></param>
        /// <param name="scaleType"></param>
        /// <returns></returns>
        protected float Transform(double chartValue, ScaleType scaleType)
        {
            switch (scaleType)
            {
                case ScaleType.Log10:
                    return chartValue > 0 ? (float)Math.Log10(chartValue) : 0;
                case ScaleType.LogNatural:
                    return chartValue > 0 ? (float)(Math.Log(chartValue) / Log2) : 0;
                default:
                    return (float)chartValue;
            }
        }

        protected double InverseTransform(double canvasValue, ScaleType scaleType)
        {
            switch (scaleType)
            {
                case ScaleType.Log10:
                    return Math.Pow(10, canvasValue);
                case ScaleType.LogNatural:
                    return Math.Pow(Math.E, canvasValue * Log2);
                default:
                    return canvasValue;
            }
        }

        protected double ToCanvasWidth(double chartX)
        {
            ScaleType scaleType = ScaleType.Linear;
            if (HasScaleParameters && Definition.ScaleParameters.X != null)
                scaleType = Definition.ScaleParameters.X.ScaleType;
            return ToCanvasWidth(chartX, scaleType);
        }

        protected double ToCanvasWidth(double chartX, ScaleType scaleType)
        {
            return Transform(chartX, scaleType) / DivX * XExtCanvas;
        }

        protected double ToCanvasX(double chartX)
        {
            ScaleType scaleType = ScaleType.Linear;
            if (HasScaleParameters && Definition.ScaleParameters.X != null)
                scaleType = Definition.ScaleParameters.X.ScaleType;
            return ToCanvasX(chartX, scaleType);
        }

        protected double ToCanvasX(double chartX, ScaleType scaleType)
        {
            double width = ToCanvasWidth(chartX, scaleType);
            if (isXAxisReversed)
                return XExtCanvas + XAxisCanvas + XAxisCanvas - (OffX + width);
            return OffX + width;
        }

        protected double FromCanvasWidth(double canvasWidth)
        {
            ScaleType scaleType = ScaleType.Linear;
            if (HasScaleParameters && Definition.ScaleParameters.X != null)
                scaleType = Definition.ScaleParameters.X.ScaleType;
            return FromCanvasWidth(canvasWidth, scaleType);
        }

        protected double FromCanvasWidth(double canvasWidth, ScaleType scaleType)
        {
            double rawChartWidth = canvasWidth * DivX / XExtCanvas;
            return InverseTransform(rawChartWidth, scaleType);
        }

        protected double InverseTransformX(double canvasX)
        {
            if (!HasScaleParameters || Definition.ScaleParameters.X == null)
                return canvasX;
            return InverseTransform(canvasX, Definition.ScaleParameters.X.ScaleType);
        }

        protected double ToCanvasHeight(double chartY)
        {
            ScaleType scaleType = ScaleType.Linear;
            if (HasScaleParameters && Definition.ScaleParameters.Y != null)
                scaleType = Definition.ScaleParameters.Y.ScaleType;
            return ToCanvasHeight(chartY, scaleType);
        }

        protected double ToCanvasHeight(double chartY, ScaleType scaleType)
        {
            double transformed = Transform(chartY, scaleType);
            return transformed / DivY * YExtCanvas;
        }

        protected double ToCanvasY(double chartY)
        {
            ScaleType scaleType = ScaleType.Linear;
            if (HasScaleParameters && Definition.ScaleParameters.Y != null)
                scaleType = Definition.ScaleParameters.Y.ScaleType;
            return ToCanvasY(chartY, scaleType);
        }

        protected double ToCanvasY(double chartY, ScaleType scaleType)
        {
            double height = ToCanvasHeight(chartY, scaleType);
            if (isYAxisReversed)
                return YExtCanvas + YAxisCanvas + YAxisCanvas - (OffY + height);
            return OffY + height;
        }

        protected double FromCanvasHeight(double canvasHeight)
        {
            ScaleType scaleType = ScaleType.Linear;
            if (HasScaleParameters && Definition.ScaleParameters.Y != null)
                scaleType = Definition.ScaleParameters.Y.ScaleType;
            return FromCanvasHeight(canvasHeight, scaleType);
        }

        protected double FromCanvasHeight(double canvasHeight, ScaleType scaleType)
        {
            double rawChartHeight = canvasHeight * DivY / YExtCanvas;
            return InverseTransform(rawChartHeight, scaleType);
        }

#if WARN_OBSOLETES
        [Obsolete("TODO: Get pyramid to use an x scale without tics and draw this in that way")]
#endif
        protected void DrawStringInCanvasCoordinates(string s, FontDescriptor font, BrushDescriptor brush, double x, double y, StringFormat txtFormat)
        {
            Canvas.DrawString(s, font, brush, x, y, txtFormat);
        }

        ///  <summary>
        ///  Cases:
        ///  Left-justify: (x,y) is centre of left-hand edge of text.
        ///  Right-justify: (x,y) is centre of right-hand edge of text.
        ///  </summary>
#if WARN_OBSOLETES
        [Obsolete("Ideally subclasses would never need to use canvas co-ordinates")]
#endif
        protected void DrawStringAtAngleInCanvasCoordinates(string s, FontDescriptor font, BrushDescriptor brush, double x, double y, StringFormat txtFormat, LabelDirection direction)
        {
            Canvas.DrawStringAtAngle(s, font, brush, x, y, txtFormat, direction);
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
#if WARN_OBSOLETES
        [Obsolete("Ideally subclasses would never need to use canvas co-ordinates")]
#endif
        protected void DrawSquareInCanvasCoordinates(PenDescriptor p, double x, double y, double size, bool fill)
        {
            Canvas.DrawSquare(p, x, y, size, fill);
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
#if WARN_OBSOLETES
        [Obsolete("Ideally subclasses would never need to use canvas co-ordinates")]
#endif
        protected void DrawDiamondInCanvasCoordinates(PenDescriptor p, double x, double y, double size, bool fill)
        {
            Canvas.DrawDiamond(p, x, y, size, fill);
        }

#if WARN_OBSOLETES
        [Obsolete("Ideally subclasses would never need to use canvas co-ordinates")]
#endif
        protected void DrawLineInCanvasCoordinates(PenDescriptor p, double x1, double y1, double x2, double y2)
        {
            Canvas.DrawLine(p, x1, y1, x2, y2);
        }

#if WARN_OBSOLETES
        [Obsolete("Ideally subclasses would never need to use canvas co-ordinates")]
#endif
        protected void DrawMarkerInCanvasCoordinates(double x, double y, double size, MarkerShape shape, bool isFilled, PenDescriptor p)
        {
            Canvas.DrawMarker(x, y, size, shape, isFilled, p);
        }

        protected void DrawMarkerInChartCoordinates(double x, double y, double size, MarkerShape shape, bool isFilled, PenDescriptor p)
        {
            Canvas.DrawMarker(ToCanvasX(x), ToCanvasY(y), size, shape, isFilled, p);
        }

#if WARN_OBSOLETES
        [Obsolete("Ideally subclasses would never need to use canvas co-ordinates")]
#endif
        protected void DrawRectangleInCanvasCoordinates(PenDescriptor p, BrushDescriptor b, double x, double y, double w, double h)
        {
            Canvas.DrawRectangle(p, b, x, y, w, h);
        }

#if WARN_OBSOLETES
        [Obsolete("Ideally subclasses would never need to use canvas co-ordinates")]
#endif
        protected SizeD MeasureStringInCanvasCoordinates(string s, FontDescriptor font)
        {
            return Canvas.MeasureString(s, font);
        }

#if WARN_OBSOLETES
        [Obsolete("Ideally subclasses would never need to use canvas co-ordinates")]
#endif
        protected double LegendFontHeightInCanvasCoordinates()
        {
            return Canvas.GetFontHeight(LegendFontDescriptor);
        }

        protected bool IsInsidePlotArea(AxisScales axisScales, double x, double y)
        {
            return y >= axisScales.Y.MinimumScaleValue && y <= axisScales.Y.MaximumScaleValue
                && x >= axisScales.X.MinimumScaleValue && x <= axisScales.X.MaximumScaleValue;
        }

        protected bool AreInsidePlotArea(AxisScales axisScales, double x1, double y1, double x2, double y2)
        {
            return IsInsidePlotArea(axisScales, x1, y1) && IsInsidePlotArea(axisScales, x2, y2);
        }

        protected void MaybeDrawLineInChartCoordinates(AxisScales axisScales, ColorDescriptor color, double x1, double y1, double x2, double y2)
        {
            MaybeDrawLineInChartCoordinates(axisScales, new PenDescriptor(color), x1, y1, x2, y2);
        }

        /// <summary>
        /// Draw the part of the line that lies within the plot area, if any.
        /// </summary>
        /// <remarks>
        /// A line with an end outside the plot area used to be left out altogether, so a fitted curve or confidence band stopped a whole segment short of the axis it was heading for.
        /// It is now clipped to the plot area instead. A line with a missing end is still not drawn.
        /// </remarks>
        protected void MaybeDrawLineInChartCoordinates(AxisScales axisScales, PenDescriptor p, double x1, double y1, double x2, double y2)
        {
            if (AreInsidePlotArea(axisScales, x1, y1, x2, y2))
            {
                DrawLineInChartCoordinates(p, x1, y1, x2, y2);
                return;
            }
            if (x1 == Constant.MISSING || y1 == Constant.MISSING || x2 == Constant.MISSING || y2 == Constant.MISSING)
                return;

            //  Clip in canvas coordinates, where the line is straight whatever the scale types (Liang-Barsky)
            double cx1 = ToCanvasX(x1);
            double cy1 = ToCanvasY(y1);
            double cx2 = ToCanvasX(x2);
            double cy2 = ToCanvasY(y2);
            double edgeA = ToCanvasX(axisScales.X.MinimumScaleValue);
            double edgeB = ToCanvasX(axisScales.X.MaximumScaleValue);
            double edgeC = ToCanvasY(axisScales.Y.MinimumScaleValue);
            double edgeD = ToCanvasY(axisScales.Y.MaximumScaleValue);
            foreach (double value in new[] { cx1, cy1, cx2, cy2, edgeA, edgeB, edgeC, edgeD })
                if (double.IsNaN(value) || double.IsInfinity(value))
                    return;
            double left = Math.Min(edgeA, edgeB);
            double right = Math.Max(edgeA, edgeB);
            double low = Math.Min(edgeC, edgeD);
            double high = Math.Max(edgeC, edgeD);

            double dx = cx2 - cx1;
            double dy = cy2 - cy1;
            double tEnter = 0.0;
            double tLeave = 1.0;
            double[] directions = { -dx, dx, -dy, dy };
            double[] distances = { cx1 - left, right - cx1, cy1 - low, high - cy1 };
            for (int edge = 0; edge < 4; edge++)
            {
                if (directions[edge] == 0.0)
                {
                    if (distances[edge] < 0.0)
                        return; // Parallel to this edge and outside it
                }
                else
                {
                    double t = distances[edge] / directions[edge];
                    if (directions[edge] < 0.0)
                        tEnter = Math.Max(tEnter, t);
                    else
                        tLeave = Math.Min(tLeave, t);
                }
            }
            if (tEnter > tLeave)
                return; // Wholly outside
            Canvas.DrawLine(p, cx1 + tEnter * dx, cy1 + tEnter * dy, cx1 + tLeave * dx, cy1 + tLeave * dy);
        }

        protected void DrawLineInChartCoordinates(ColorDescriptor color, double x1, double y1, double x2, double y2)
        {
            DrawLineInChartCoordinates(new PenDescriptor(color), x1, y1, x2, y2);
        }

        protected void DrawLineInChartCoordinates(PenDescriptor p, double x1, double y1, double x2, double y2)
        {
            Canvas.DrawLine(p, ToCanvasX(x1), ToCanvasY(y1), ToCanvasX(x2), ToCanvasY(y2));
        }

        protected void DrawRectangleInChartCoordinates(ColorDescriptor color, double left, double top, double width, double height)
        {
            Canvas.DrawRectangle(new PenDescriptor(color), null, ToCanvasX(left), ToCanvasY(top), ToCanvasWidth(width), ToCanvasHeight(height));
        }

        protected bool HasScaleParameters => Definition != null && Definition.HasScaleParameters;

        protected bool HasChartOptions => Definition?.ChartOptions != null;

        protected bool ShouldUseColour
        {
            get
            {
                bool useColour = SdApplication.SoleInstance.Preferences.ShouldUseColour;
                if (HasChartOptions)
                    useColour = Definition.ChartOptions.UseColour;
                return useColour;
            }
        }

        protected PenDescriptor GetMarkerPen(MarkerType mt)
        {
            return new PenDescriptor(ShouldUseColour ? mt.MarkerColor : GrBlack, mt.Width);
        }

        /// <summary>
        /// Return a new Pen of the given type. It is up to the caller to dispose of this.
        /// </summary>
        protected PenDescriptor GetLinePen(MarkerType mt, bool ignoreStyle)
        {
            PenDescriptor p = new(ShouldUseColour ? mt.LineColor : GrBlack, mt.Width);
            if (!ignoreStyle)
                p.DashStyle = mt.LineDashStyle;
            return p;
        }

        ///  <summary>
        ///  A colour to be used for drawing lines that are nominally black.
        ///  </summary>
        protected static ColorDescriptor GrBlack => ColorDescriptor.Black;

        ///  <summary>
        ///  A colour to be used for drawing lines that are nominally green.
        ///  </summary>
        protected ColorDescriptor GrGreen => ShouldUseColour ? ColorDescriptor.Green : ColorDescriptor.Black;

        ///  <summary>
        ///  A colour to be used for drawing lines that are nominally magenta.
        ///  </summary>
        protected ColorDescriptor GrMagenta => ShouldUseColour ? ColorDescriptor.Magenta : ColorDescriptor.Black;

        ///  <summary>
        ///  A colour to be used for drawing lines that are nominally red.
        ///  </summary>
        protected ColorDescriptor GrRed => ShouldUseColour ? ColorDescriptor.Red : ColorDescriptor.Black;

        ///  <summary>
        ///  A colour to be used for drawing axis lines
        ///  </summary>
        private ColorDescriptor GrAxis => ShouldUseColour ? ColorDescriptor.FromArgb(134, 134, 134) : ColorDescriptor.Black;

        public string GetAscii()
        {
            if (!IsAscii)
                throw new InvalidOperationException("Trying to get ASCII string for a non-ASCII chart");

            StringBuilder sb = new();
            for (int i = TextCanvas.GetUpperBound(0); i >= TextCanvas.GetLowerBound(0); i--)
                sb.AppendLine(TextCanvas[i]);
            return sb.ToString();
        }

        protected void WriteAsciiYX(int y, int x, string text)
        {
#if DEBUG
            if (y < 0 || y >= TextCanvas.Length)
                throw new Exception("y is out of the renderer's range");
#endif
            TextCanvas[y] = ReplaceAt(TextCanvas[y], x, text);
        }

        protected void WriteAsciiYX(int y, int x, char c)
        {
            TextCanvas[y] = ReplaceAt(TextCanvas[y], x, c);
        }

        private static string ReplaceAt(string buffer, int x, string text)
        {
            int l = buffer.Length;
            int tl = text.Length;
            return buffer.Substring(0, Math.Min(l, x)) + new string(' ', Math.Max(0, x - l)) + text + (x + tl >= l ? string.Empty : buffer.Substring(x + tl));
        }

        private static string ReplaceAt(string buffer, int x, char c)
        {
            return buffer.Substring(0, x) + c + buffer.Substring(x + 1);
        }

        protected void AssignMarkersToSeries()
        {
            if (Definition.XSeries.Count > 0)
                AssignMarkersToSeries(Definition.XSeries);
            if (Definition.YSeries.Count > 0)
                AssignMarkersToSeries(Definition.YSeries);
        }

        protected void AssignMarkersToSeries(GenericOptions opts)
        {
            if (Definition.XSeries.Count > 0)
                AssignMarkersToSeries(Definition.XSeries, opts);
            if (Definition.YSeries.Count > 0)
                AssignMarkersToSeries(Definition.YSeries, opts);
        }

        protected void AssignMarkersToSeries(IList<ISeries> s)
        {
            for (int i = 0; i < s.Count; i++)
            {
                DoubleSeries ds = (DoubleSeries)s[i];
                int mkr = ChartOptions.SeriesNumberToMarkerNumber(i);
                SetSeriesFromMarkerTypeAndOptions(ds, ChartPreferences.MarkerTypes[mkr], null);
            }
        }

        private static void SetSeriesFromMarkerTypeAndOptions(DoubleSeries ds, MarkerType mt, GenericOptions o)
        {
            ds.MarkerType = mt.Clone();
            if (o != null)
                ds.MarkerType.IsMarkerFilled = o.ShouldForceIsFilled ? o.ForcedIsFilled : mt.IsMarkerFilled;
        }

        protected void AssignMarkersToSeries(IList<ISeries> s, GenericOptions opts)
        {
            if (opts?.MarkerTypes == null || opts.MarkerTypes.Count < 1)
            {
                for (int i = 0; i < s.Count; i++)
                {
                    DoubleSeries ds = (DoubleSeries)s[i];
                    int mkr = ChartOptions.SeriesNumberToMarkerNumber(i);
                    SetSeriesFromMarkerTypeAndOptions(ds, ChartPreferences.MarkerTypes[mkr], opts);
                }
            }
            else
            {
                for (int i = 0; i < s.Count; i++)
                {
                    if (s[i] is DoubleSeries ds)
                    {
                        int mkr = i % opts.MarkerTypes.Count;
                        SetSeriesFromMarkerTypeAndOptions(ds, opts.MarkerTypes[mkr], opts);
                    }
                }
            }
        }

        public void Dispose()
        {
            Dispose(true);
            GC.SuppressFinalize(this);
        }

        protected virtual void Dispose(bool disposing)
        {
            Canvas?.Dispose();
        }

        private double ImageWidth => Canvas.Width;
        private double ImageHeight => Canvas.Height;

        ///  <summary>
        ///  Initialise everything required for an ASCII plot of the required number of lines, notably including the SH_TX array.
        ///  </summary>
        ///  <param name="lines">The number of lines of text in the ASCII plot</param>
        protected void StartAsciiPlot(int lines)
        {
            // Set up the plot area - this is in ASCII co-ordinates, i.e. characters.
            int width = ASCII_X_EXT + AsciiXTxt + 10;
            TextCanvas = new string[lines + 1];
            for (int c = 0; c <= TextCanvas.GetUpperBound(0); c++)
                TextCanvas[c] = new string(' ', width);
        }

        protected void EndAsciiPlot()
        {
            // Do nothing
        }

        protected void AsciiPlotPointInChartCoordinates(double x, double y)
        {
            int chartX = ToAsciiX(x);
            int chartY = ToAsciiY(y);
            // Check if a point has already been plotted
            switch (TextCanvas[chartY][chartX])
            {
                case ' ':
                    WriteAsciiYX(chartY, chartX, "*");
                    break;
                case '*':
                    WriteAsciiYX(chartY, chartX, "2");
                    break;
                case '9':
                    WriteAsciiYX(chartY, chartX, "X");
                    break;
                case '|':
                case '+':
                case '-':
                    return;
                default:
                    // Must be numeric; add 1
                    WriteAsciiYX(chartY, chartX, (char)(TextCanvas[chartY][chartX] + 1));
                    break;
            }
        }

        /// <summary>
        /// Marker lines are single values on the X or Y axis that the user has requested to be drawn.
        /// </summary>
        protected void MaybeDrawMarkerLines(AxisScales axisScales)
        {
            if (Definition?.ScaleParameters == null)
                return;
            if (Definition.ScaleParameters.X.MarkerLineValue.HasValue)
            {
                double x = Definition.ScaleParameters.X.MarkerLineValue.Value;
                DrawLineInChartCoordinates(GrBlack, x, axisScales.Y.MinimumScaleValue, x, axisScales.Y.MaximumScaleValue);
            }
            if (Definition.ScaleParameters.Y.MarkerLineValue.HasValue)
            {
                double y = Definition.ScaleParameters.Y.MarkerLineValue.Value;
                DrawLineInChartCoordinates(GrBlack, axisScales.X.MinimumScaleValue, y, axisScales.X.MaximumScaleValue, y);
            }
        }

        private void SetFontsAndThicknessesFromOptions(GenericOptions o)
        {
            if (o.UsesAxisLabelFontDescriptor && null != o.AxisLabelFontDescriptor)
                AxisLabelFontDescriptor = o.AxisLabelFontDescriptor;
            if (o.UsesAxisTitleFontDescriptor && null != o.AxisTitleFontDescriptor)
                AxisTitleFontDescriptor = o.AxisTitleFontDescriptor;
            if (o.UsesLegendFontDescriptor && null != o.LegendFontDescriptor)
                LegendFontDescriptor = o.LegendFontDescriptor;
            if (o.UsesTitleFontDescriptor && null != o.TitleFontDescriptor)
                TitleFontDescriptor = o.TitleFontDescriptor;

            if (o.UsesAxisLineThickness)
            {
                AxisLineThickness = o.AxisLineThickness;
                ColorDescriptor c = ColorDescriptor.Black;
                if (AxisPen != null)
                    c = AxisPen.Color;
                AxisPen = new PenDescriptor(c, AxisLineThickness);
            }
        }

        public static IList<MarkerType> MarkersFromDescriptors(IList<SeriesOptionsDescriptor> seriesOptionsDescriptors, bool shouldForceIsFilled, bool forcedIsFilled, bool shouldForceFillStyle, FillStyle forcedFillStyle)
        {
            IList<MarkerType> markerTypes = new List<MarkerType>(seriesOptionsDescriptors.Count);
            foreach (SeriesOptionsDescriptor t in seriesOptionsDescriptors)
            {
                int markerIndex = t.MarkerIndex;
                int mkr = ChartOptions.SeriesNumberToMarkerNumber(markerIndex);

                MarkerType clone = ChartPreferences.MarkerTypes[mkr].Clone();
                if (shouldForceIsFilled)
                    clone.IsMarkerFilled = forcedIsFilled;
                if (shouldForceFillStyle)
                    clone.MarkerFillStyle = forcedFillStyle;
                markerTypes.Add(clone);
            }
            return markerTypes;
        }

        protected BrushDescriptor MarkerTypeToBrush(MarkerType mt)
        {
            if (ShouldUseColour)
                return new BrushDescriptor(mt.MarkerColor);
            else
                return new BrushDescriptor(GrBlack) { FillStyle = mt.MarkerFillStyle };
        }

        protected static string MakeTitle(string useIfAvailable, string defaultTitle)
        {
            if (string.IsNullOrWhiteSpace(useIfAvailable))
                return defaultTitle;

            if (useIfAvailable.Length > MaxLabelLength)
                return useIfAvailable.Substring(0, MaxLabelLength);
            return useIfAvailable;
        }

#if WARN_OBSOLETES
        [Obsolete("Ideally subclasses would never need to use canvas co-ordinates")]
#endif
        protected double AxisLabelWidthInCanvasCoordinates(string s)
        {
            return MeasureStringInCanvasCoordinates(s, AxisLabelFontDescriptor).Width;
        }

#if WARN_OBSOLETES
        [Obsolete("Ideally subclasses would never need to use canvas co-ordinates")]
#endif
        protected double AxisLabelHeightInCanvasCoordinates(string s)
        {
            return MeasureStringInCanvasCoordinates(s, AxisLabelFontDescriptor).Height;
        }

#if WARN_OBSOLETES
        [Obsolete("Ideally subclasses would never need to use canvas co-ordinates")]
#endif
        protected double LabelWidthInCanvasCoordinates(string s)
        {
            return MeasureStringInCanvasCoordinates(s, LabelFontDescriptor).Width;
        }

#if WARN_OBSOLETES
        [Obsolete("Ideally subclasses would never need to use canvas co-ordinates")]
#endif
        protected double LabelHeightInCanvasCoordinates(string s)
        {
            return MeasureStringInCanvasCoordinates(s, LabelFontDescriptor).Height;
        }

#if WARN_OBSOLETES
        [Obsolete("Ideally subclasses would never need to use canvas co-ordinates")]
#endif
        internal double LegendWidthInCanvasCoordinates(string s)
        {
            return MeasureStringInCanvasCoordinates(s, LegendFontDescriptor).Width;
        }

#if WARN_OBSOLETES
        [Obsolete("Ideally subclasses would never need to use canvas co-ordinates")]
#endif
        internal double LegendHeightInCanvasCoordinates(string s)
        {
            return MeasureStringInCanvasCoordinates(s, LegendFontDescriptor).Height;
        }

#if WARN_OBSOLETES
        [Obsolete("Ideally subclasses would never need to use canvas co-ordinates")]
#endif
        protected double TitleWidthInCanvasCoordinates(string s)
        {
            return MeasureStringInCanvasCoordinates(s, TitleFontDescriptor).Width;
        }

        protected int ToAsciiX(double value)
        {
            return Convert.ToInt32(OffX + value / DivX * XExtCanvas);
        }

        protected int ToAsciiY(double value)
        {
            return Convert.ToInt32(OffY + value / DivY * YExtCanvas);
        }

        /// <summary>
        /// Detect and return minimum, minimum greater than zero and maximum values in the array.
        /// </summary>
        /// <param name="data"></param>
        /// <param name="min">Filled in with the global minimum value</param>
        /// <param name="minGreaterThanZero">Filled in with the global minimum value that is greater than zero.</param>
        /// <param name="max">Filled in with the global maximum value</param>
        /// <remarks>STYLE: Wouldn't this be better as a function returning some kind of data structure?</remarks>
        protected void GetMinMaxArray(double[] data, out double min, out double max, out double minGreaterThanZero)
        {
            min = double.MaxValue;
            minGreaterThanZero = double.MaxValue;
            max = double.MinValue;
            for (int i = data.GetLowerBound(0); i <= data.GetUpperBound(0); i++)
            {
                if (data[i] != Constant.MISSING)
                {
                    if (data[i] < min)
                        min = data[i];
                    if (data[i] > 0 && data[i] < minGreaterThanZero)
                        minGreaterThanZero = data[i];
                    if (data[i] > max)
                        max = data[i];
                }
            }
        }

        /// <summary>
        /// Detect and return minimum and maximum values in the array.
        /// </summary>
        /// <param name="data"></param>
        /// <param name="scaleType">The scale that will use the data.  For log scales, values of 0 or less are ignored.</param>
        protected Layout.Range GetMinMaxArray(double[] data, ScaleType scaleType)
        {
            bool ignoreZeroOrLess = scaleType == ScaleType.LogNatural || scaleType == ScaleType.Log10;
            double min = double.MaxValue;
            double max = double.MinValue;
            for (int i = data.GetLowerBound(0); i <= data.GetUpperBound(0); i++)
            {
                if (data[i] != Constant.MISSING && !(ignoreZeroOrLess && data[i] <= 0))
                {
                    if (data[i] < min)
                        min = data[i];
                    if (data[i] > max)
                        max = data[i];
                }
            }
            return new Layout.Range(min, max);
        }

        ///  <summary>
        ///  Draw a horizontal line at the specified offset from the Y origin.
        ///  </summary>
        ///  <param name="y">The offset, in device units</param>
        ///  <remarks></remarks>
        protected void DrawQCanvas(double y)
        {
            DrawLineInCanvasCoordinates(new PenDescriptor(GrGreen, 2), XAxisCanvas, y, XAxisCanvas + XExtCanvas, y);
        }

        /// <summary>
        /// Find an appropriate height for a chart with k series, between 1 and 5 times the nominal height.
        /// </summary>
        protected void ScaleHeight(int k)
        {
            if (k > 10)
            {
                double scaleYAxis = 1 + (k - 10) / 20.0;
                if (scaleYAxis > 5)
                    scaleYAxis = 5;
                imageHeight = (int)Math.Ceiling(scaleYAxis * DEFAULT_METAFILE_HEIGHT);
            }
        }

        protected void ScaleWidth(int k)
        {
            if (k > 10)
            {
                double scaleXAxis = 1 + (k - 10) / 20.0;
                if (scaleXAxis > 5)
                    scaleXAxis = 5;
                imageWidth = (int)Math.Ceiling(scaleXAxis * DEFAULT_METAFILE_WIDTH);
            }
        }

        protected void DrawLegend(Legend legend)
        {
            const int interRowGap = 6;
            const int markerToLegendGap = 12;
            const int borderWidth = 0;

            double left;
            double top;
            switch (legend.Position)
            {
                case LegendPosition.Bottom:
                    left = XAxisCanvas;
                    top = YAxisCanvas - LegendTopGap;
                    break;
                case LegendPosition.Left:
                    left = LegendLeftGap;
                    top = YAxisCanvas + YExtCanvas;
                    break;
                default:
                    throw new Exception("Only Left and Bottom legend positions known");
            }

            int i = 0;
            foreach (LegendEntry entry in legend.LegendEntries)
            {
                double legendFontHeight = LegendHeightInCanvasCoordinates("M");
                double rowHeight = Math.Max(LegendMarkerSize, legendFontHeight);
                double rowCentre = top - rowHeight * (i + 0.5) - interRowGap * i;
                DrawMarkerInCanvasCoordinates(left + borderWidth + LegendMarkerSize / 2.0, rowCentre, LegendMarkerSize, entry.MarkerType);
                DrawStringLegendLC(entry.Label, left + borderWidth + LegendMarkerSize + markerToLegendGap, rowCentre);
                i++;
            }
        }

        protected bool IsAscii => null != Definition && Definition.IsAscii;

        ///  <summary>
        ///  Sometimes we need to draw line charts (for example) with their points sorted.
        ///  This comparer sorts PointFs by increasing X, then by increasing Y.
        ///  </summary>
        private class SortXThenY : IComparer<PointF>
        {
            int IComparer<PointF>.Compare(PointF x, PointF y)
            {
                float xDiff = x.X - y.X;
                return xDiff == 0 ? Math.Sign(x.Y - y.Y) : Math.Sign(xDiff);
            }
        }

        public IStatsDirectCanvas Canvas { get; private set; }
    }
}