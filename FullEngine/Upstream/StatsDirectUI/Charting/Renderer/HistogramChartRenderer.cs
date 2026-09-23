using Layout;
using StatsDirect.Charting.Scales;
using StatsDirect.Templates;
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Globalization;

namespace StatsDirect.Charting.Renderer
{
    internal class HistogramChartRenderer : AbstractChartRenderer, IChartRenderer
    {
        public HistogramChartRenderer(ChartDefinition definition, ICanvasFactory canvasFactory)
            : base(definition, canvasFactory)
        {
        }

        ScaleParameters IChartRenderer.GetScaleParameters()
        {
            HistogramOptions options = (HistogramOptions)Definition.ChartOptions;
            bool showRelativeFrequencies = options.ShowRelativeFrequencies;

            //  We're looking over multiple histograms and getting a merged view
            double minX = double.MaxValue;
            double maxX = double.MinValue;
            double maxY = 0.0;

            for (int i = 0; i < Definition.YSeries.Count; i++)
            {
                HistogramSeriesOptions so = options.HistoSeriesOptions[i];
                if (null == so.BinsDescriptor)
                    so.Reset(true, 0, (DoubleSeries)Definition.YSeries[i], options.BinChoiceMethod);

                //  Set up our axis bounds for the X axis - we do this ourselves and don't allow the neatening code to amend it.
                minX = Math.Min(minX, so.BinsDescriptor.LowestEdge);
                maxX = Math.Max(maxX, so.BinsDescriptor.HighestEdge);

                //  Find the number of values in each bin, and hence the size of the histogram's y axis.
                //  This works because the bins are always of equal width in the histograms we choose to plot - if they weren't, we'd have to scale by the width
                double seriesMaxY = 0;
                int points = 0;
                for (int bindex = 0; bindex < so.BinsDescriptor.Bins; bindex++)
                {
                    points += so.BinsDescriptor.Counts[bindex];
                    seriesMaxY = Math.Max(seriesMaxY, so.BinsDescriptor.Counts[bindex]);
                }
                if (showRelativeFrequencies)
                    seriesMaxY /= points;
                if (seriesMaxY > maxY)
                    maxY = seriesMaxY;
            }
            ScaleParameters sp = new()
            {
                X = { AllowedScaleTypes = new[] { ScaleType.Linear }, Min = minX, Max = maxX },
                Y = { AllowedScaleTypes = new[] { ScaleType.Linear }, Min = 0, Max = maxY }
            };
            return sp;
        }

        ParameterBag IChartRenderer.Plot(/* TODO: IPreferences*/ ITemplateHost _, bool isForReturnedParametersOnly)
        {
            if (isForReturnedParametersOnly)
                return new ParameterBag();

            HistogramOptions options = (HistogramOptions)Definition.ChartOptions;
            IList<ISeries> seriesToUse = Definition.YSeries;
            MarkerType[] originalMarkerTypes = null;
            //  A space to save drawn ASCII plots until required
            List<string> savedLines = null;

            //  Ensure the data is sorted
            Layout.Range dataRangeX = GetMinMaxSort(seriesToUse);
            DataMinX = dataRangeX.Min;
            DataMaxX = dataRangeX.Max;

            // get settings for plot
            bool overlayNormalCurve = options.OverlayNormalCurve;

            try
            {
                if (!IsAscii)
                {
                    //  If there's more than one series, they're to be plotted separately.  Each plot is the same height as the original.
                    imageHeight *= seriesToUse.Count;

                    StartVectorPlot(options);

                    originalMarkerTypes = ChartPreferences.MarkerTypes;
                    ChartPreferences.PushAndCloneMarkerTypes();
                    for (int i = 0; i < originalMarkerTypes.Length; i++)
                        ChartPreferences.MarkerTypes[i].Width = options.LineWidth;
                    AssignMarkersToSeries(seriesToUse);
                }
                else
                {
                    // ASCII plot
                    savedLines = new List<string>();
                }

                for (int seriesIndex = 0; seriesIndex < seriesToUse.Count; seriesIndex++)
                {
                    DoubleSeries s = (DoubleSeries)seriesToUse[seriesIndex];
                    HistogramSeriesOptions so = options.HistoSeriesOptions[seriesIndex];
                    string title = so.ChartTitle;

                    BinsDescriptor descriptor = so.BinsDescriptor;
                    double minimumBinMidpoint = (descriptor.Edges[0] + descriptor.Edges[1]) / 2.0;
                    double maximumBinMidpoint = (descriptor.Edges[descriptor.Bins] + descriptor.Edges[descriptor.Bins - 1]) / 2.0;
                    double binMidpointInterval = (maximumBinMidpoint - minimumBinMidpoint) / (descriptor.Bins - 1);

                    //  Set up our axis bounds for the X axis - we do this ourselves and don't allow the neatening code to amend it.
                    if (!options.PoolVariablesForBins)
                    {
                        DataMinX = double.MaxValue;
                        DataMaxX = double.MinValue;
                    }
                    DataMinX = Math.Min(DataMinX, descriptor.LowestEdge);
                    DataMaxX = Math.Max(DataMaxX, descriptor.HighestEdge);
                    DataMinY = 0;
                    DataMaxY = double.MinValue;

                    //  Find the number of values in each bin, and hence the size of the histogram's y axis.
                    //  This works because the bins are always of equal width in the histograms we choose to plot - if they weren't, we'd have to scale by the width
                    double seriesMaxY = 0;
                    int points = 0;
                    for (int bindex = 0; bindex < descriptor.Bins; bindex++)
                    {
                        points += descriptor.Counts[bindex];
                        seriesMaxY = Math.Max(seriesMaxY, descriptor.Counts[bindex]);
                    }
                    if (options.ShowRelativeFrequencies)
                        seriesMaxY /= points;
                    if (seriesMaxY > DataMaxY)
                        DataMaxY = seriesMaxY;

                    double proportionScaler = options.ShowRelativeFrequencies ? 1.0 / s.Points : 1.0;

                    if (!IsAscii)
                    {
                        // Plot a Metafile version
                        int heightPerChart = imageHeight / seriesToUse.Count; //  Should end up as the old MetaH
                        double thisChartTop = imageHeight - seriesIndex * heightPerChart;
                        double thisChartBottom = thisChartTop - heightPerChart;

                        //  The x axis is labelled at the bin mid-points, as the bins are specified and as the axis title says, not at neat round values.
                        //  Only when the axis spans exactly this series' bins: with "pool variables" it can span several series' differing bin grids, and then
                        //  the neat scale is kept, as before (as it is for a degenerate range, which the scaler reports properly).  Set before the axis space
                        //  is measured, so that the measured labels are the ones drawn.
                        XAxisScaleOverride = descriptor.LowestEdge == DataMinX && descriptor.HighestEdge == DataMaxX && descriptor.HighestEdge > descriptor.LowestEdge
                            ? new HistogramAxisScale(descriptor.LowestEdge, descriptor.HighestEdge, descriptor.Bins)
                            : null;

                        //  No longer the default Y axis!
                        Size extraSpaceForAxes = CalculateAxisSizes(title,
                            new AxisDefinition(options.HistoSeriesOptions[seriesIndex].XAxisTitle, AxisMode.Scale, Definition.ScaleParameters.X.ScaleType),
                            new AxisDefinition(options.HistoSeriesOptions[seriesIndex].YAxisTitle, AxisMode.Scale, Definition.ScaleParameters.Y.ScaleType),
                            true);
                        DefaultAxes(null, extraSpaceForAxes);
                        YAxisCanvas = thisChartBottom + Math.Min(Math.Floor(imageHeight / 8.0), DefaultYGap);
                        YExtCanvas = heightPerChart - Math.Min(heightPerChart / 4.0, 2 * DefaultYGap);

                        //  If necessary, extend the Y axis to accommodate the normal curve
                        if (overlayNormalCurve)
                        {
                            double mxy = PlotNormalCurve(descriptor.LowestEdge, binMidpointInterval, descriptor.Bins, s, proportionScaler, null);
                            if (mxy > DataMaxY)
                                DataMaxY = mxy;
                        }

                        // Draw the axes
                        AxisScales ass = DrawAxes(title,
                            new AxisDefinition(options.HistoSeriesOptions[seriesIndex].XAxisTitle, AxisMode.Scale, Definition.ScaleParameters.X.ScaleType),
                            new AxisDefinition(options.HistoSeriesOptions[seriesIndex].YAxisTitle, AxisMode.Scale, Definition.ScaleParameters.Y.ScaleType),
                            false,
                            true,
                            extraSpaceForAxes);
                        XAxisScaleOverride = null;

                        // Plot each bar
                        PenDescriptor markerPen = GetMarkerPen(s.MarkerType);
                        for (int c = 0; c < descriptor.Bins; c++)
                        {
                            // plot a bar at an absolute position (maxX / 20)
                            double x1 = ToCanvasX(descriptor.Edges[c]);
                            double x2 = ToCanvasX(descriptor.Edges[c + 1]);
                            double value = descriptor.Counts[c] * proportionScaler;
                            double y1 = ToCanvasY(value);
                            double y2 = YAxisCanvas;
                            DrawRectangleInCanvasCoordinates(markerPen, null, x1, y1, x2 - x1, y1 - y2);
                        }

                        //  ZInt was calculated at Mp*2
                        if (overlayNormalCurve)
                            PlotNormalCurve(descriptor.LowestEdge, binMidpointInterval, descriptor.Bins, s, proportionScaler, markerPen);

                        MaybeDrawMarkerLines(ass);
                    }
                    else
                    {
                        // Plot one ASCII histogram per series.  The cheat is to plot each one, save it, and concatenate at the end!
                        StartAsciiPlot(descriptor.Bins + 4);
                        // Draw the scale

                        // the ASCII version is plotted sideways
                        // so save the current X value
                        // get the values needed to plot the X axis
                        DataMinX = 0;
                        DataMaxX = DataMaxY;

                        LayoutChartAndDrawAxes(title,
                            new AxisDefinition(null, AxisMode.Scale, Definition.ScaleParameters.X.ScaleType),
                            new AxisDefinition(null, AxisMode.LineOnly, Definition.ScaleParameters.Y.ScaleType),
                            false, true);

                        string mask = "G12";
                        for (int c = 0; c < descriptor.Bins; c++)
                        {
                            int barLength = Convert.ToInt32(descriptor.Counts[c] * proportionScaler / DataMaxY * 60);
                            WriteAsciiYX(c + AsciiYTxt, AsciiXTxt + 5, new string('=', barLength));
                            if (descriptor.Counts[c] > 0 && barLength == 0)
                                WriteAsciiYX(c + AsciiYTxt, AsciiXTxt + 5, ":");

                            double midpoint = (descriptor.Edges[c] + descriptor.Edges[c + 1]) / 2.0;
                            string buf = midpoint.ToString(mask);
                            WriteAsciiYX(c + AsciiYTxt, AsciiXTxt - buf.Length + 4, buf);

                            buf = descriptor.Counts[c].ToString(CultureInfo.InvariantCulture);
                            WriteAsciiYX(c + AsciiYTxt, 1, buf);
                        }

                        WriteAsciiYX(0, AsciiXTxt, options.HistoSeriesOptions[seriesIndex].XAxisTitle);

                        WriteAsciiYX(descriptor.Bins + AsciiYTxt, 16, "Mid-points");
                        WriteAsciiYX(descriptor.Bins + AsciiYTxt, 1, "Counts");
                        TextCanvas[2] = string.Concat("     ", TextCanvas[2].AsSpan(0, Math.Min(TextCanvas[2].Length, 85)));
                        TextCanvas[1] = string.Concat("     ", TextCanvas[1].AsSpan(0, Math.Min(TextCanvas[1].Length, 85)));
                        TextCanvas[0] = string.Concat("     ", TextCanvas[0].AsSpan(0, Math.Min(TextCanvas[0].Length, 85)));

                        //  Save this plot
                        for (int i = TextCanvas.Length - 1; i >= 0; i--)
                            savedLines.Insert(0, TextCanvas[i]);

                        //  Separator
                        savedLines.Insert(0, string.Empty);
                    }
                }

                if (!IsAscii)
                {
                    EndVectorPlot();
                }
                else
                {
                    //  Fill in the output in its expected place from our saved place
                    TextCanvas = new string[savedLines.Count];
                    for (int i = 0; i < savedLines.Count; i++)
                        TextCanvas[i] = savedLines[i];
                }

                return new ParameterBag();
            }
            finally
            {
                if (originalMarkerTypes != null)
                {
                    //  TODO: Resource leak on pens?
                    ChartPreferences.PopMarkerTypes();
                }
            }
        }


        /// <summary>
        /// Returns the maximum value of a normal curve from the specified series and bin values.
        /// </summary>
        /// <param name="zmin">The x value at which the curve starts: the lowest bin edge</param>
        /// <param name="zint">The width of a bin</param>
        /// <param name="count">The number of bins</param>
        /// <param name="s">The series whose data is to be used for the calculation</param>
        /// <param name="p">Draws using p if set; merely returns the maximum value if null</param>
        /// <returns>The maximum value of y</returns>
        private double PlotNormalCurve(double zmin, double zint, int count, DoubleSeries s, double proportionScaler, PenDescriptor p)
        {
            // Setup the plotting variables
            double xbar = s.Sum / s.Points;
            double sdv = s.StdDev;
            double sumx = zmin;
            double bins = zint * s.Points * (1.0 / (sdv * Math.Sqrt(2.0 * Math.PI)));

            //  Multiply the count to give more steps
            int div = Math.Max(1, Convert.ToInt32(XExtCanvas / count / 5));
            count *= div;
            zint /= div;

            //  Move the cursor to the start
            double y = bins * Math.Exp(-0.5 * Math.Pow((sumx - xbar) / sdv, 2.0)) * proportionScaler;
            double yMax = y;
            double yold = ToCanvasY(y);
            //  Each point of the curve belongs at its own x value, as the bars do. It used to be spread evenly over the whole axis, which shifted and widened it whenever the axis did not run exactly from the first to the last bin mid-point.
            double xold = ToCanvasX(sumx);

            for (int c = 1; c <= count; c++)
            {
                sumx += zint;
                y = bins * Math.Exp(-0.5 * Math.Pow((sumx - xbar) / sdv, 2.0)) * proportionScaler;
                if (y > yMax)
                    yMax = y;
                if (null != p)
                {
                    double y1 = ToCanvasY(y);
                    double x1 = ToCanvasX(sumx);
                    DrawLineInCanvasCoordinates(p, xold, yold, x1, y1);
                    xold = x1;
                    yold = y1;
                }
            }
            return yMax;
        }
    }
}
