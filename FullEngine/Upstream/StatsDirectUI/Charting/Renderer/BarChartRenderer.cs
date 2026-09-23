using StatsDirect.Charting.Scales;
using StatsDirect.Numerics;
using StatsDirect.Templates;
using System;
using System.Collections.Generic;

namespace StatsDirect.Charting.Renderer
{
    class BarChartRenderer : AbstractChartRenderer, IChartRenderer
    {
        public BarChartRenderer(ChartDefinition definition, ICanvasFactory canvasFactory)
            : base(definition, canvasFactory)
        {
        }

        ScaleParameters IChartRenderer.GetScaleParameters()
        {
            BarOptions bOptions = (BarOptions)Definition.ChartOptions;

            // No false origins
            DataMinY = 0;

            //  Stacked and 100% stacked charts require different scaling
            if (bOptions.Stacked)
            {
                if (bOptions.Stacked100Percent)
                {
                    DataMaxY = 100;
                }
                else
                {
                    double largestSoFar = 0;

                    for (int offset = 0; offset < ((DoubleSeries)Definition.YSeries[0]).Points; offset++)
                    {
                        double thisTotal = 0;
                        foreach (DoubleSeries s in Definition.YSeries)
                            if (s.Data[offset] != Constant.MISSING)
                                thisTotal += s.Data[offset];
                        if (thisTotal > largestSoFar)
                            largestSoFar = thisTotal;
                    }
                    //  Ensure there's always *some* size to the axis
                    if (largestSoFar == 0)
                        largestSoFar = 1;
                    DataMaxY = largestSoFar;
                }
            }

            // Label orientation: As standard, there are 80 characters across.
            const int maxLabelChars = 80;
            int longestTitle = 0;
            foreach (string title in bOptions.SeriesTitles)
                if (title.Length > longestTitle)
                    longestTitle = title.Length;
            LabelDirection preferredLabelDirection = LabelDirection.Across;
            if (longestTitle * bOptions.SeriesTitles.Length > maxLabelChars)
                preferredLabelDirection = LabelDirection.Up;

            return new ScaleParameters
            {
                X =
                {
                    AllowedScaleTypes = new[] { ScaleType.Category },
                    Max = 0,
                    Min = 0,
                    LabelDirection = preferredLabelDirection
                },
                Y =
                {
                    AllowedScaleTypes = new[] { ScaleType.Linear },
                    Max = DataMaxY,
                    Min = DataMinY
                }
            };
        }


        ///  <summary>
        ///  Plot a bar, stacked bar or 100% stacked bar chart.
        ///  </summary>
        ///  <remarks></remarks>
        ParameterBag IChartRenderer.Plot(/* TODO: IPreferences*/ ITemplateHost _, bool isForReturnedParametersOnly)
        {
            if (isForReturnedParametersOnly)
                return new ParameterBag();

            Definition = Definition.Clone();

            IList<ISeries> seriesToUse = Definition.YSeries;
            BarOptions bOptions = (BarOptions)Definition.ChartOptions;

            string xAxisTitle = bOptions.XAxisTitle;
            string yAxisTitle = bOptions.YAxisTitle;

            // If we've been asked to flip rows and columns, do so
            if (bOptions.Stacked && bOptions.RotateWhenStacked)
            {
                string[] oldSeriesTitles = bOptions.SeriesTitles;

                // The new series titles are the old series names
                string[] newSeriesTitles = new string[seriesToUse.Count];
                for (int i = 0; i < seriesToUse.Count; i++)
                    newSeriesTitles[i] = seriesToUse[i].Title;

                // One new series for each old title
                List<ISeries> newSeriesToUse = new(oldSeriesTitles.Length);
                foreach (string t in oldSeriesTitles)
                {
                    ISeries s = new DoubleSeries(new double[seriesToUse.Count], t);
                    newSeriesToUse.Add(s);
                }

                // Rotate the data
                for (int oldSeries = 0; oldSeries < seriesToUse.Count; oldSeries++)
                    for (int oldRow = 0; oldRow < oldSeriesTitles.Length; oldRow++)
                        ((DoubleSeries)newSeriesToUse[oldRow]).Data[oldSeries] = ((DoubleSeries)seriesToUse[oldSeries]).Data[oldRow];

                // Assign.  The rotated series replace the originals (Definition and its options are our own clone): adding them alongside listed both sets
                // of names in the legend and, as SetMarkers appends a descriptor for each series, coloured the segments differently from the legend.
                bOptions.SeriesTitles = newSeriesTitles;
                Definition.YSeries.Clear();
                Definition.AddYSeries(newSeriesToUse);
                seriesToUse = newSeriesToUse;

                // Ensure we have enough markers
                bOptions.SeriesOptions.Clear();
                bOptions.SetMarkers(seriesToUse);
                bOptions.MarkerTypes = MarkersFromDescriptors(bOptions.SeriesOptions, bOptions.ShouldForceIsFilled,
                                                              bOptions.ForcedIsFilled, bOptions.ShouldForceFillStyle,
                                                              bOptions.ForcedFillStyle);
            }

            //  Sort out the axes for different chart types
            if (bOptions.Stacked)
            {
                if (bOptions.Stacked100Percent)
                {
                    //  Y axis scales 0-100
                    DataMinY = 0;
                    DataMaxY = 100;
                }
                else
                {
                    //  Add up the bars and scale to that maximum
                    double largestSetOfBars = 0;
                    for (int barIndex = 0; barIndex < ((DoubleSeries)seriesToUse[0]).Data.Length; barIndex++)
                    {
                        //  Missing data leads to missing bars
                        double totalOfAllBars = 0;
                        for (int seriesIndex = 0; seriesIndex < seriesToUse.Count; seriesIndex++)
                        {
                            double seriesValue = ((DoubleSeries)seriesToUse[seriesIndex]).Data[barIndex];
                            if (seriesValue != Constant.MISSING)
                                totalOfAllBars += seriesValue;
                        }
                        largestSetOfBars = Math.Max(largestSetOfBars, totalOfAllBars);
                    }
                    DataMaxY = largestSetOfBars;
                }
            }

            //  If there's a legend, work out how many series there are and extend the plot area as required to hold the legend
            bool shouldDrawLegend = bOptions.Stacked || bOptions.ShowLegend && bOptions.ShowLegendIsRelevant;

            Legend legend = null;
            if (shouldDrawLegend)
            {
                legend = new Legend { Position = LegendPosition.Bottom };
                for (int i = 0; i < Definition.YSeries.Count; i++)
                {
                    ISeries series = Definition.YSeries[i];
                    MarkerType mt = bOptions.MarkerTypes[i].Clone();
                    mt.MarkerShape = MarkerShape.Square;
                    legend.LegendEntries.Add(new LegendEntry { Label = series.Title, MarkerType = mt });
                }
            }

            //  Plot
            if (bOptions.Orientation == ChartOrientation.Horizontal)
            {
                //  Flip the series, and hence the min/max values
                Definition = Definition.Clone();
                Definition.SwapXAndYSeries();
                AxisScaleParameters tempAxisScaleParameters = Definition.ScaleParameters.X;
                Definition.ScaleParameters.X = Definition.ScaleParameters.Y;
                Definition.ScaleParameters.Y = tempAxisScaleParameters;
                DataMinX = DataMinY;
                DataMaxX = DataMaxY;
                DataMinY = 0;
                DataMaxY = 0;
                string temp = yAxisTitle;
                yAxisTitle = xAxisTitle;
                xAxisTitle = temp;

                StartVectorPlot(bOptions, legend);

                // Draw the scale
                AssignMarkersToSeries(bOptions);

                AxisScales axisScales = LayoutChartAndDrawAxes(Definition.ChartOptions.Title,
                    new AxisDefinition(xAxisTitle, AxisMode.Scale, Definition.ScaleParameters.X.ScaleType),
                    new AxisDefinition(yAxisTitle, AxisMode.Series, Definition.ScaleParameters.Y.ScaleType) { Labels = bOptions.SeriesTitles },
                    bOptions.ShouldBoxAxes, false,
                    legend);
                DivY = ((DoubleSeries)seriesToUse[0]).Points;
                OffY = -(0 / DivY * YExtCanvas) + YAxisCanvas;

                double eachAreaHeight = YExtCanvas / DivY;
                double eachBarHeightFraction;
                double eachBarHeight;
                double totalBarHeightFraction;
                if (bOptions.Stacked)
                {
                    eachBarHeightFraction = Math.Min(1.0, Math.Max(bOptions.MaxBarWidth, 0.01));
                    eachBarHeight = eachAreaHeight * eachBarHeightFraction;
                    totalBarHeightFraction = eachBarHeightFraction;
                }
                else
                {
                    eachBarHeightFraction = Math.Min(1.0 / seriesToUse.Count, Math.Max(bOptions.MaxBarWidth, 0.01));
                    eachBarHeight = eachAreaHeight * eachBarHeightFraction;
                    totalBarHeightFraction = eachBarHeightFraction * seriesToUse.Count;
                }
                double eachSideWhiteSpaceHeightFraction = (1.0 - totalBarHeightFraction) / 2.0;
                double eachSideWhiteSpaceHeight = eachSideWhiteSpaceHeightFraction * eachAreaHeight;

                //  Work through the columns - this plots each series in turn, rather than all the bars in increasing Y-order.  It's easier on pen/brush resources but requires a little more calculation.
                for (int c = 0; c < seriesToUse.Count; c++)
                {
                    DoubleSeries s = (DoubleSeries)seriesToUse[c];
                    MarkerType mt = bOptions.MarkerTypes[c];
                    double bottomOffsetInArea;
                    if (bOptions.Stacked)
                        bottomOffsetInArea = eachBarHeight + eachSideWhiteSpaceHeight;
                    else
                        bottomOffsetInArea = (seriesToUse.Count - c) * eachBarHeight + eachSideWhiteSpaceHeight;

                    PenDescriptor barPen = GetLinePen(s.MarkerType, true);
                    BrushDescriptor barBrush = MarkerTypeToBrush(mt);

                    for (int barIndex = 0; barIndex < s.Data.Length; barIndex++)
                    {
                        double thisData = s.Data[barIndex];
                        //  Missing data leads to missing bars
                        if (thisData != Constant.MISSING)
                        {
                            double totalBelowThisBar = 0;
                            double totalOfAllBars = 0;
                            //  Data exists.  For stacked and 100% stacked bars, we now need to position and scale the bar.
                            if (bOptions.Stacked)
                            {
                                for (int probeIndex = 0; probeIndex < seriesToUse.Count; probeIndex++)
                                {
                                    double probeValue = ((DoubleSeries)seriesToUse[probeIndex]).Data[barIndex];
                                    if (probeValue != Constant.MISSING)
                                    {
                                        if (probeIndex < c)
                                            totalBelowThisBar += probeValue;
                                        totalOfAllBars += probeValue;
                                    }
                                }
                                //  By now: totalOfAllBars contains the total for all bars; totalBelowThisBar contains the total of bars that have already been drawn; thisData contains our own bar length
                                if (bOptions.Stacked100Percent)
                                {
                                    if (totalOfAllBars <= 0)
                                        thisData = Constant.MISSING;
                                    else
                                    {
                                        //  Scale to percent
                                        thisData = thisData / totalOfAllBars * 100.0;
                                        totalBelowThisBar = totalBelowThisBar / totalOfAllBars * 100.0;
                                    }
                                }
                                //  By now, totalBelowThisBar contains the sum of all the values below this bar scaled appropriately for 100% scaling if required.
                                //  thisData also contains appropriately scaled data.
                            }

                            //  If we should, draw this bar
                            if (thisData != Constant.MISSING)
                            {
                                //  Prevent portions of bars being drawn below the X axis
                                double dataW;
                                double dataLowX;
                                //  Dim dataHighX As Double = totalBelowThisBar + thisData
                                if (totalBelowThisBar < axisScales.X.MinimumScaleValue)
                                {
                                    dataW = thisData + totalBelowThisBar - axisScales.X.MinimumScaleValue;
                                    dataLowX = axisScales.X.MinimumScaleValue;
                                }
                                else
                                {
                                    dataW = thisData;
                                    dataLowX = totalBelowThisBar;
                                }

                                if (dataW > 0)
                                {
                                    double areaYOffset = (s.Data.Length - 1 - barIndex) * eachAreaHeight;
                                    double barH = eachBarHeight;
                                    double barW = ToCanvasWidth(dataW);
                                    double barY = OffY + areaYOffset + bottomOffsetInArea;
                                    double barX = ToCanvasX(dataLowX);
                                    DrawRectangleInCanvasCoordinates(barPen, barBrush, barX, barY, barW, barH);
                                }
                            }
                        }
                    }
                }
                MaybeDrawMarkerLines(axisScales);

                //  Legend
                if (shouldDrawLegend)
                    DrawLegend(legend);
            }
            else
            {
                //  Not horizontal, so vertical

                StartVectorPlot(bOptions, legend);
                AssignMarkersToSeries(bOptions);

                //  Get overall minima and maxima
                double min = 0; // We don't do false origins, so axis minimum cannot be greater than zero
                double minGreaterThanZero = double.MaxValue;
                double max = double.MinValue;
                foreach (DoubleSeries s in seriesToUse)
                {
                    min = Math.Min(min, s.Min);
                    minGreaterThanZero = Math.Min(minGreaterThanZero, s.MinGreaterThanZero);
                    max = Math.Max(max, s.Max);
                }
                DataMinY = min; // HACK!  TODO: We really need to fix up the references to min, DataMin and so on.

                AxisScales axisScales = LayoutChartAndDrawAxes(Definition.ChartOptions.Title,
                    new AxisDefinition(xAxisTitle, AxisMode.Series, Definition.ScaleParameters.X.ScaleType) { Labels = bOptions.SeriesTitles },
                    new AxisDefinition(yAxisTitle, AxisMode.Scale, Definition.ScaleParameters.Y.ScaleType),
                    bOptions.ShouldBoxAxes, false,
                    legend);
                DivX = ((DoubleSeries)seriesToUse[0]).Points;
                OffX = -(0 / DivX * XExtCanvas) + XAxisCanvas;

                double eachAreaWidth = XExtCanvas / DivX;
                double eachBarWidthFraction;
                double eachBarWidth;
                double totalBarWidthFraction;
                if (bOptions.Stacked)
                {
                    eachBarWidthFraction = Math.Min(1.0, Math.Max(bOptions.MaxBarWidth, 0.01));
                    eachBarWidth = eachAreaWidth * eachBarWidthFraction;
                    totalBarWidthFraction = eachBarWidthFraction;
                }
                else
                {
                    eachBarWidthFraction = Math.Min(1.0 / seriesToUse.Count, Math.Max(bOptions.MaxBarWidth, 0.01));
                    eachBarWidth = eachAreaWidth * eachBarWidthFraction;
                    totalBarWidthFraction = eachBarWidthFraction * seriesToUse.Count;
                }
                double eachSideWhiteSpaceWidthFraction = (1.0 - totalBarWidthFraction) / 2.0;
                double eachSideWhiteSpaceWidth = eachSideWhiteSpaceWidthFraction * eachAreaWidth;

                // work through the columns - this plots each series in turn, rather than all the bars in increasing X-order
                for (int c = 0; c < seriesToUse.Count; c++)
                {
                    DoubleSeries s = (DoubleSeries)seriesToUse[c];
                    MarkerType mt = bOptions.MarkerTypes[c];
                    double leftOffsetInArea;
                    if (bOptions.Stacked)
                        leftOffsetInArea = eachSideWhiteSpaceWidth;
                    else
                        leftOffsetInArea = c * eachBarWidth + eachSideWhiteSpaceWidth;

                    PenDescriptor barPen = GetLinePen(s.MarkerType, false);
                    BrushDescriptor barBrush = MarkerTypeToBrush(mt);
                    for (int barIndex = 0; barIndex < s.Data.Length; barIndex++)
                    {
                        double thisData = s.Data[barIndex];
                        //  Missing data leads to missing bars
                        if (thisData != Constant.MISSING)
                        {
                            double totalBelowThisBar = 0;
                            //  Data exists.  For stacked and 100% stacked bars, we now need to position and scale the bar.
                            if (bOptions.Stacked)
                            {
                                double totalOfAllBars = 0;
                                for (int probeIndex = 0; probeIndex < seriesToUse.Count; probeIndex++)
                                {
                                    double probeValue = ((DoubleSeries)seriesToUse[probeIndex]).Data[barIndex];
                                    if (probeValue != Constant.MISSING)
                                    {
                                        if (probeIndex < c)
                                        {
                                            totalBelowThisBar += probeValue;
                                        }
                                        totalOfAllBars += probeValue;
                                    }
                                }
                                //  By now: totalOfAllBars contains the total for all bars; totalBelowThisBar contains the total of bars that have already been drawn; thisData contains our own bar length
                                if (bOptions.Stacked100Percent)
                                {
                                    if (totalOfAllBars <= 0)
                                    {
                                        thisData = Constant.MISSING;
                                    }
                                    else
                                    {
                                        //  Scale to percent
                                        thisData = thisData / totalOfAllBars * 100.0;
                                        totalBelowThisBar = totalBelowThisBar / totalOfAllBars * 100.0;
                                    }
                                }
                                //  By now, totalBelowThisBar contains the sum of all the values below this bar scaled appropriately for 100% scaling if required.
                                //  thisData also contains appropriately scaled data.
                            }

                            //  If we should, draw this bar
                            if (thisData != Constant.MISSING)
                            {
                                //  Prevent portions of bars being drawn below the X axis
                                double dataH;
                                double dataLowY;
                                //  Dim dataHighX As Double = totalBelowThisBar + thisData
                                if (totalBelowThisBar < axisScales.Y.MinimumScaleValue)
                                {
                                    dataH = thisData + totalBelowThisBar - axisScales.Y.MinimumScaleValue;
                                    dataLowY = axisScales.Y.MinimumScaleValue;
                                }
                                else
                                {
                                    dataH = thisData;
                                    dataLowY = totalBelowThisBar;
                                }

                                if (dataH > 0)
                                {
                                    double areaXOffset = barIndex * eachAreaWidth;
                                    double barW = eachBarWidth;
                                    double barH = dataH / DivY * YExtCanvas;
                                    double barX = OffX + areaXOffset + leftOffsetInArea;
                                    double barY = ToCanvasY(dataLowY + dataH);
                                    DrawRectangleInCanvasCoordinates(barPen, barBrush, barX, barY, barW, barH);
                                }
                            }
                        }
                    }

                }
                MaybeDrawMarkerLines(axisScales);

                //  Legend
                if (shouldDrawLegend)
                    DrawLegend(legend);
            }
            EndVectorPlot();
            return new ParameterBag();
        }
    }
}
