using Layout;
using StatsDirect.Charting.Scales;
using StatsDirect.Numerics;
using StatsDirect.Templates;
using System;
using System.Collections.Generic;
using System.Linq;

namespace StatsDirect.Charting.Renderer
{
    class BoxWhiskerChartRenderer : AbstractChartRenderer, IChartRenderer
    {
        //  Box and Whisker constants
        private const double WHISKER_END_LENGTH = 9;
        private const double OUTLIER_RADIUS = 4;
        private const double BOX_FRACTION_OF_SPACE = 0.667;
        private const double WHISKER_FRACTION_OF_BOX = 0.333;
        private const int MAX_GRAPHICAL_TITLE_LENGTH = 30;

        public BoxWhiskerChartRenderer(ChartDefinition definition, ICanvasFactory canvasFactory)
            : base(definition, canvasFactory)
        {
        }

        ScaleParameters IChartRenderer.GetScaleParameters()
        {
            //  If only X series have been passed in, we're vertical.  If only Y, we're horizontal.  If both or neither, we can't plot.
            if (Definition.XSeries.Count == 0 && Definition.YSeries.Count == 0)
                throw new ArgumentException("Must have at least one series to plot a box+whisker plot");
            if (Definition.XSeries.Count > 0 && Definition.YSeries.Count > 0)
                throw new ArgumentException("Cannot plot a box+whisker plot with both X and Y series");
            IList<ISeries> SeriesToUse = Definition.YSeries.Count > 0 ? Definition.YSeries : Definition.XSeries;

            // sort the array and get the min, max values
            Layout.Range dataRangeX = GetMinMaxSort(SeriesToUse);
            DataMinX = dataRangeX.Min;
            DataMaxX = dataRangeX.Max;

            return new ScaleParameters
            {
                X = { AllowedScaleTypes = new[] { ScaleType.Linear }, Min = DataMinX, Max = DataMaxX },
                Y = { AllowedScaleTypes = new[] { ScaleType.Category } }
            };
        }

        ///  <summary>
        ///  Plot a box and whisker chart.
        ///  </summary>
        ///  <remarks></remarks>
        ParameterBag IChartRenderer.Plot(/* TODO: IPreferences*/ ITemplateHost _, bool isForReturnedParametersOnly)
        {
            if (isForReturnedParametersOnly)
                return new ParameterBag();

            //  If only X series have been passed in, we're vertical.  If only Y, we're horizontal.  If both or neither, we can't plot.
            if (Definition.XSeries.Count == 0 && Definition.YSeries.Count == 0)
                throw new ArgumentException("Must have at least one series to plot a box+whisker plot");
            if (Definition.XSeries.Count > 0 && Definition.YSeries.Count > 0)
                throw new ArgumentException("Cannot plot a box+whisker plot with both X and Y series");
            IList<ISeries> seriesToUse = Definition.YSeries.Count > 0 ? Definition.YSeries : Definition.XSeries;

            BoxWhiskerOptions bwOptions = (BoxWhiskerOptions)Definition.ChartOptions;

            if (IsAscii)
                return PlotBoxWhiskerAscii(seriesToUse);

            // Choose a sane upper limit for label lengths
            foreach (ISeries series in seriesToUse)
                series.Title = series.Title.Length > MAX_GRAPHICAL_TITLE_LENGTH ? series.Title[..MAX_GRAPHICAL_TITLE_LENGTH] + "…" : series.Title;
            if (bwOptions.Orientation == ChartOrientation.Horizontal)
                return PlotBoxWhiskerHorizontal(seriesToUse);
            return PlotBoxWhiskerVertical(seriesToUse);
        }

        private ParameterBag PlotBoxWhiskerHorizontal(IList<ISeries> seriesToUse)
        {
            ScaleHeight(seriesToUse.Count + 1);

            // sort the array and get the min, max values
            Layout.Range dataRangeX = GetMinMaxSort(seriesToUse);
            DataMinX = dataRangeX.Min;
            DataMaxX = dataRangeX.Max;

            BoxWhiskerOptions bwOptions = (BoxWhiskerOptions)Definition.ChartOptions;

            double p = (1.0 - bwOptions.Cco) / 2.0;
            if (p > 1.0 - p)
                p = 1.0 - p;

            // Plot a Metafile version
            StartVectorPlot(bwOptions);
            AssignMarkersToSeries();

            AxisScales axisScales = LayoutChartAndDrawAxes(Definition.ChartOptions.Title,
                new AxisDefinition(bwOptions.XAxisTitle, AxisMode.Scale, Definition.ScaleParameters.X.ScaleType),
                new AxisDefinition(null, AxisMode.Series, Definition.ScaleParameters.Y.ScaleType) { Series = seriesToUse },
                false, false);
            MarkerType mt = ChartPreferences.MarkerTypes[10];
            ColorDescriptor black = ColorDescriptor.Black;
            MarkerType crossMarker = new() { MarkerShape = MarkerShape.Cross, MarkerColor = black, MarkerSize = 10 };
            MarkerType filledDiamondMarker = new() { MarkerShape = MarkerShape.Diamond, IsMarkerFilled = true, MarkerColor = black, MarkerSize = 10 };
            MarkerType hollowCircleMarker = new() { MarkerShape = MarkerShape.Circle, MarkerColor = black, MarkerSize = 10 };
            MarkerType filledCircleMarker = new() { MarkerShape = MarkerShape.Circle, IsMarkerFilled = true, MarkerColor = black, MarkerSize = 10 };

            PenDescriptor blackPen = GetMarkerPen(mt);
            PenDescriptor dottedBlackPen = GetMarkerPen(mt);
            dottedBlackPen.DashStyle = DashStyleDescriptor.Dot;

            // work through the columns
            for (int c = 0; c < seriesToUse.Count; c++)
            {
                DoubleSeries s = (DoubleSeries)seriesToUse[c];
                PlotBoxWhiskerCalc(s, bwOptions.Method, p, out double centre, out double boxL, out double boxR, out double innerFenceL, out double innerFenceR, bwOptions.UseInnerFence, out double outerFenceL, out double outerFenceR, bwOptions.UseOuterFence, out double otherMark, out bool _);

                // Plot graphic
                // #1316: Plot labels are plotted top-down, data was plotted bottom-up.  Reverse the data so that the first series is at the top to match the labels.
                double yctr = seriesToUse.Count - c - 0.5;

                double halfBoxHeight = 0.5 * BOX_FRACTION_OF_SPACE;
                double yTop = yctr + halfBoxHeight;
                double yBottom = yctr - halfBoxHeight;

                // Draw marker, centre line and box
                DrawRectangleInChartCoordinates(black, boxL, yTop, boxR - boxL, yTop - yBottom); //  Box
                if (bwOptions.MarkMeanAndMedian)
                {
                    //  Other mark
                    DrawMarkerInChartCoordinates(otherMark, yctr, 10, crossMarker);
                }
                DrawMarkerInChartCoordinates(centre, yctr, 10, filledDiamondMarker);
                DrawLineInChartCoordinates(black, centre, yTop, centre, yBottom); //  Centre line

                //  Draw whiskers, fences etc.
                double halfWhiskerHeight = halfBoxHeight * WHISKER_FRACTION_OF_BOX;
                yTop = yctr + halfWhiskerHeight;
                yBottom = yctr - halfWhiskerHeight;

                //  Left-hand fences
                bool gatedInnerL = bwOptions.Method != BoxWhiskerOptions.BoxWhiskerMethod.SevenNumberSummary && bwOptions.Method != BoxWhiskerOptions.BoxWhiskerMethod.BowleySummary && s.Data[0] < innerFenceL && innerFenceL < boxL;
                bool gatedOuterL = s.Data[0] < outerFenceL && outerFenceL < boxL;

                // double outerFenceLX = ToCanvasX(gatedOuterL ? outerFenceL : s.Data[ 0 ]);

                //  Draw inner fence
                //  The inner fence goes to the first one of:
                //  - The inner fence for seven number and Bowley plots;
                //  - The inner fence if both inner and outer fences are selected and there's at least one outlier beyond it;
                //  - Not drawn otherwise.
                if (bwOptions.Method == BoxWhiskerOptions.BoxWhiskerMethod.SevenNumberSummary || bwOptions.Method == BoxWhiskerOptions.BoxWhiskerMethod.BowleySummary)
                {
                    PenDescriptor innerPen;
                    if (bwOptions.UseOuterFence || bwOptions.Method == BoxWhiskerOptions.BoxWhiskerMethod.SevenNumberSummary || bwOptions.Method == BoxWhiskerOptions.BoxWhiskerMethod.BowleySummary)
                        innerPen = dottedBlackPen;
                    else
                        innerPen = blackPen;
                    DrawLineInChartCoordinates(innerPen, innerFenceL, yTop, innerFenceL, yBottom);
                }

                //  Draw min whisker
                //  The min whisker goes to the first one of:
                //  - The outer fence for seven number and Bowley plots;
                //  - The first data point inside the inner fence if inner fence is selected;
                //  - The first data point inside the outer fence if outer fence is selected;
                //  - The min data point otherwise.
                double minWhiskerL = 0;
                if (bwOptions.Method == BoxWhiskerOptions.BoxWhiskerMethod.SevenNumberSummary || bwOptions.Method == BoxWhiskerOptions.BoxWhiskerMethod.BowleySummary)
                {
                    minWhiskerL = outerFenceL;
                }
                else if (bwOptions.UseInnerFence)
                {
                    for (int i = 0; i < s.Data.Length; i++)
                    {
                        if (s.Data[i] >= innerFenceL)
                        {
                            minWhiskerL = s.Data[i];
                            break;
                        }
                    }
                }
                else if (bwOptions.UseOuterFence)
                {
                    for (int i = 0; i < s.Data.Length; i++)
                    {
                        if (s.Data[i] >= outerFenceL)
                        {
                            minWhiskerL = s.Data[i];
                            break;
                        }
                    }
                }
                else
                {
                    minWhiskerL = s.Data[0];
                }

                //  Draw min whisker to outer limit
                DrawLineInChartCoordinates(black, minWhiskerL, yctr, boxL, yctr);

                //  Draw outer marker
                bool shouldDrawOuterBracketL = !(bwOptions.Method == BoxWhiskerOptions.BoxWhiskerMethod.SevenNumberSummary || bwOptions.Method == BoxWhiskerOptions.BoxWhiskerMethod.BowleySummary) && !(gatedOuterL || gatedInnerL);
                DrawLineInChartCoordinates(black, minWhiskerL, yTop, minWhiskerL, yBottom);
                if (shouldDrawOuterBracketL)
                {
                    DrawLineInChartCoordinates(black, minWhiskerL + FromCanvasWidth(WHISKER_END_LENGTH), yTop, minWhiskerL, yTop);
                    DrawLineInChartCoordinates(black, minWhiskerL, yBottom, minWhiskerL + FromCanvasWidth(WHISKER_END_LENGTH), yBottom);
                }

                //  Min outliers - below outer fence
                const double outlierRadius = OUTLIER_RADIUS;
                if (gatedInnerL)
                {
                    for (int r = 0; r < s.Data.Length; r++)
                    {
                        if (s.Data[r] < innerFenceL && (s.Data[r] >= outerFenceL || !gatedOuterL))
                            DrawMarkerInChartCoordinates(s.Data[r], yctr, 2 * outlierRadius, hollowCircleMarker);
                    }
                }
                if (gatedOuterL)
                {
                    for (int r = 0; r < s.Data.Length; r++)
                    {
                        if (s.Data[r] < outerFenceL)
                            DrawMarkerInChartCoordinates(s.Data[r], yctr, 2 * outlierRadius, filledCircleMarker);
                    }
                }

                //  Right-hand fences
                bool gatedInnerR = bwOptions.Method != BoxWhiskerOptions.BoxWhiskerMethod.SevenNumberSummary && bwOptions.Method != BoxWhiskerOptions.BoxWhiskerMethod.BowleySummary && s.Data[^1] > innerFenceR && innerFenceR > boxR;
                bool gatedOuterR = s.Data[^1] > outerFenceR && outerFenceR > boxR;

                // double outerFenceRX = ToCanvasX(gatedOuterR ? outerFenceR : s.Data[ s.Data.Length - 1 ]);

                //  Draw inner fence
                //  The inner fence goes to the first one of:
                //  - The inner fence for seven number and Bowley plots;
                //  - The inner fence if both inner and outer fences are selected and there's at least one outlier betond it;
                //  - Not drawn otherwise.
                if (bwOptions.Method == BoxWhiskerOptions.BoxWhiskerMethod.SevenNumberSummary || bwOptions.Method == BoxWhiskerOptions.BoxWhiskerMethod.BowleySummary)
                {
                    PenDescriptor innerPen;
                    if (bwOptions.UseOuterFence || bwOptions.Method == BoxWhiskerOptions.BoxWhiskerMethod.SevenNumberSummary || bwOptions.Method == BoxWhiskerOptions.BoxWhiskerMethod.BowleySummary)
                        innerPen = dottedBlackPen;
                    else
                        innerPen = blackPen;
                    DrawLineInChartCoordinates(innerPen, innerFenceR, yTop, innerFenceR, yBottom);
                }

                //  Draw max whisker
                //  The max whisker goes to the first one of:
                //  - The outer fence for seven number and Bowley plots;
                //  - The last data point below the inner fence if inner fence is selected;
                //  - The last data point below the outer fence if outer fence is selected;
                //  - The max data point otherwise.
                double maxWhiskerR = 0;
                if (bwOptions.Method == BoxWhiskerOptions.BoxWhiskerMethod.SevenNumberSummary || bwOptions.Method == BoxWhiskerOptions.BoxWhiskerMethod.BowleySummary)
                {
                    maxWhiskerR = outerFenceR;
                }
                else if (bwOptions.UseInnerFence)
                {
                    for (int i = s.Data.Length - 1; i >= 0; i--)
                    {
                        if (s.Data[i] <= innerFenceR)
                        {
                            maxWhiskerR = s.Data[i];
                            break;
                        }
                    }
                }
                else if (bwOptions.UseOuterFence)
                {
                    for (int i = s.Data.Length - 1; i >= 0; i--)
                    {
                        if (s.Data[i] <= outerFenceR)
                        {
                            maxWhiskerR = s.Data[i];
                            break;
                        }
                    }
                }
                else
                {
                    maxWhiskerR = s.Data[^1];
                }
                DrawLineInChartCoordinates(black, maxWhiskerR, yctr, boxR, yctr);

                //  Outer fence
                // ReSharper disable ConvertToConstant.Local
                bool shouldDrawOuterFenceR = true;
                // ReSharper restore ConvertToConstant.Local
                // If (gatedInnerR OrElse gatedOuterR) _
                //     AndAlso Not (bwOptions.Method = BoxWhiskerOptions.BoxWhiskerMethod.SevenNumberSummary OrElse bwOptions.Method = BoxWhiskerOptions.BoxWhiskerMethod.BowleySummary) Then
                // If bwOptions.UseInnerFence AndAlso (Not bwOptions.UseOuterFence) AndAlso gatedInnerR Then
                //  At least one inner outlier, and we're not using the outer fence.  The inner fence will have been drawn; we should not draw this as well.
                // shouldDrawOuterFenceR = False
                // End If
                bool shouldDrawOuterBracketR = shouldDrawOuterFenceR && !(bwOptions.Method == BoxWhiskerOptions.BoxWhiskerMethod.SevenNumberSummary || bwOptions.Method == BoxWhiskerOptions.BoxWhiskerMethod.BowleySummary) && !(gatedOuterR || gatedInnerR);
                if (shouldDrawOuterFenceR)
                {
                    DrawLineInChartCoordinates(black, maxWhiskerR, yTop, maxWhiskerR, yBottom);
                    if (shouldDrawOuterBracketR)
                    {
                        DrawLineInChartCoordinates(black, maxWhiskerR - FromCanvasWidth(WHISKER_END_LENGTH), yTop, maxWhiskerR, yTop);
                        DrawLineInChartCoordinates(black, maxWhiskerR, yBottom, maxWhiskerR - FromCanvasWidth(WHISKER_END_LENGTH), yBottom);
                    }
                }

                //  Max outliers
                if (gatedInnerR)
                {
                    for (int r = 0; r < s.Data.Length; r++)
                    {
                        if (s.Data[r] > innerFenceR && (s.Data[r] <= outerFenceR || !gatedOuterR))
                            DrawMarkerInChartCoordinates(s.Data[r], yctr, 2 * outlierRadius, hollowCircleMarker);
                    }
                }
                if (gatedOuterR)
                {
                    for (int r = 0; r < s.Data.Length; r++)
                    {
                        if (s.Data[r] > outerFenceR)
                            DrawMarkerInChartCoordinates(s.Data[r], yctr, 2 * outlierRadius, filledCircleMarker);
                    }
                }
            }
            MaybeDrawMarkerLines(axisScales);
            EndVectorPlot();
            return new ParameterBag();
        }

        private ParameterBag PlotBoxWhiskerVertical(IList<ISeries> seriesToUse)
        {
            ScaleWidth(seriesToUse.Count + 1);

            // sort the array and get the min, max values
            Layout.Range dataRangeX = GetMinMaxSort(seriesToUse);
            DataMinX = dataRangeX.Min;
            DataMaxX = dataRangeX.Max;

            BoxWhiskerOptions bwOptions = (BoxWhiskerOptions)Definition.ChartOptions;

            double p = (1.0 - bwOptions.Cco) / 2.0;
            if (p > 1.0 - p)
                p = 1.0 - p;

            // Plot a Metafile version
            StartVectorPlot(bwOptions);
            AssignMarkersToSeries();
            //  Not horizontal, so vertical

            //  Swap over the X and Y axis definitions, as we've flipped the drawing
            Definition = Definition.Clone(); //  Make sure the swaps are safe!
            (Definition.ScaleParameters.Y, Definition.ScaleParameters.X) = (Definition.ScaleParameters.X, Definition.ScaleParameters.Y);

            //  Ensure the X and Y series are where we need them to be for drawing axes
            Definition.SwapXAndYSeries();

            AxisScales axisScales = LayoutChartAndDrawAxes(Definition.ChartOptions.Title,
                new AxisDefinition(null, AxisMode.Series, Definition.ScaleParameters.X.ScaleType) { Series = seriesToUse },
                new AxisDefinition(bwOptions.XAxisTitle, AxisMode.Scale, Definition.ScaleParameters.Y.ScaleType),
                false, false);

            PenDescriptor blackPen = GetMarkerPen(ChartPreferences.MarkerTypes[10]);
            PenDescriptor dottedBlackPen = GetMarkerPen(ChartPreferences.MarkerTypes[10]);
            dottedBlackPen.DashStyle = DashStyleDescriptor.Dot;

            // work through the columns
            for (int c = 0; c < seriesToUse.Count; c++)
            {
                DoubleSeries s = (DoubleSeries)seriesToUse[c];
                PlotBoxWhiskerCalc(s, bwOptions.Method, p, out double centre, out double boxB, out double boxT, out double innerFenceB, out double innerFenceT, bwOptions.UseInnerFence, out double outerFenceB, out double outerFenceT, bwOptions.UseOuterFence, out double otherMark, out bool _);

                // Plot graphic
                double xctr = ToCanvasWidth(c + 0.5);

                double halfBoxWidth = ToCanvasWidth(0.5 * BOX_FRACTION_OF_SPACE);
                double xc = OffX + xctr;
                double xr = xc + halfBoxWidth;
                double xl = xc - halfBoxWidth;


                // Draw marker, centre line and box
                DrawRectangleInCanvasCoordinates(blackPen, null, xl, ToCanvasY(boxT), xr - xl, ToCanvasHeight(boxT - boxB)); //  Box
                if (bwOptions.MarkMeanAndMedian)
                {
                    //  Other mark
                    DrawMarkerInCanvasCoordinates(xc, ToCanvasY(otherMark), 10, MarkerShape.Cross, false, blackPen);
                }
                DrawMarkerInCanvasCoordinates(xc, ToCanvasY(centre), 10, MarkerShape.Diamond, true, blackPen);
                DrawLineInCanvasCoordinates(blackPen, xr, ToCanvasY(centre), xl, ToCanvasY(centre)); //  Centre line

                //  Draw whiskers, fences etc.
                double halfWhiskerWidth = halfBoxWidth * WHISKER_FRACTION_OF_BOX;
                xr = xc + halfWhiskerWidth;
                xl = xc - halfWhiskerWidth;

                //  Left-hand fences
                bool gatedInnerB = bwOptions.Method != BoxWhiskerOptions.BoxWhiskerMethod.SevenNumberSummary && bwOptions.Method != BoxWhiskerOptions.BoxWhiskerMethod.BowleySummary && s.Data[0] < innerFenceB && innerFenceB < boxB;
                bool gatedOuterB = s.Data[0] < outerFenceB && outerFenceB < boxB;

                // double outerFenceBY = ToCanvasY(gatedOuterB ? outerFenceB : s.Data[ 0 ]);

                //  Draw inner fence
                //  The inner fence goes to the first one of:
                //  - The inner fence for seven number and Bowley plots;
                //  - The inner fence if both inner and outer fences are selected and there's at least one outlier beyond it;
                //  - Not drawn otherwise.
                bool shouldDrawInnerFenceB = false;
                double innerFenceBY = 0;
                if (bwOptions.Method == BoxWhiskerOptions.BoxWhiskerMethod.SevenNumberSummary || bwOptions.Method == BoxWhiskerOptions.BoxWhiskerMethod.BowleySummary)
                {
                    shouldDrawInnerFenceB = true;
                    innerFenceBY = ToCanvasY(innerFenceB);
                }
                if (shouldDrawInnerFenceB)
                {
                    PenDescriptor innerPen;
                    if (bwOptions.UseOuterFence || bwOptions.Method == BoxWhiskerOptions.BoxWhiskerMethod.SevenNumberSummary || bwOptions.Method == BoxWhiskerOptions.BoxWhiskerMethod.BowleySummary)
                        innerPen = dottedBlackPen;
                    else
                        innerPen = blackPen;
                    DrawLineInCanvasCoordinates(innerPen, xr, innerFenceBY, xl, innerFenceBY);
                }

                //  Draw min whisker
                //  The min whisker goes to the first one of:
                //  - The outer fence for seven number and Bowley plots;
                //  - The first data point inside the inner fence if inner fence is selected;
                //  - The first data point inside the outer fence if outer fence is selected;
                //  - The min data point otherwise.
                double minWhiskerB = 0;
                if (bwOptions.Method == BoxWhiskerOptions.BoxWhiskerMethod.SevenNumberSummary || bwOptions.Method == BoxWhiskerOptions.BoxWhiskerMethod.BowleySummary)
                {
                    minWhiskerB = outerFenceB;
                }
                else if (bwOptions.UseInnerFence)
                {
                    for (int i = 0; i < s.Data.Length; i++)
                    {
                        if (s.Data[i] >= innerFenceB)
                        {
                            minWhiskerB = s.Data[i];
                            break;
                        }
                    }
                }
                else if (bwOptions.UseOuterFence)
                {
                    for (int i = 0; i < s.Data.Length; i++)
                    {
                        if (s.Data[i] >= outerFenceB)
                        {
                            minWhiskerB = s.Data[i];
                            break;
                        }
                    }
                }
                else
                {
                    minWhiskerB = s.Data[0];
                }

                //  Draw min whisker to outer limit
                DrawLineInCanvasCoordinates(blackPen, xc, ToCanvasY(minWhiskerB), xc, ToCanvasY(boxB));

                //  Draw outer marker
                const bool shouldDrawOuterFenceB = true;
                // ReSharper disable RedundantLogicalConditionalExpressionOperand
                bool shouldDrawOuterBracketB = shouldDrawOuterFenceB && !(bwOptions.Method == BoxWhiskerOptions.BoxWhiskerMethod.SevenNumberSummary || bwOptions.Method == BoxWhiskerOptions.BoxWhiskerMethod.BowleySummary) && !(gatedOuterB || gatedInnerB);
                // ReSharper restore RedundantLogicalConditionalExpressionOperand
                if (shouldDrawOuterFenceB)
                {
                    DrawLineInCanvasCoordinates(blackPen, xr, ToCanvasY(minWhiskerB), xl, ToCanvasY(minWhiskerB));
                    if (shouldDrawOuterBracketB)
                    {
                        DrawLineInCanvasCoordinates(blackPen, xr, ToCanvasY(minWhiskerB) + WHISKER_END_LENGTH, xr, ToCanvasY(minWhiskerB));
                        DrawLineInCanvasCoordinates(blackPen, xl, ToCanvasY(minWhiskerB), xl, ToCanvasY(minWhiskerB) + WHISKER_END_LENGTH);
                    }
                }

                //  Min outliers - below outer fence
                if (gatedInnerB)
                    for (int r = 0; r < s.Data.Length; r++)
                        if (s.Data[r] < innerFenceB && (s.Data[r] >= outerFenceB || !gatedOuterB))
                            DrawMarkerInCanvasCoordinates(xc, ToCanvasY(s.Data[r]), 2 * OUTLIER_RADIUS, MarkerShape.Circle, false, blackPen);
                if (gatedOuterB)
                    for (int r = 0; r < s.Data.Length; r++)
                        if (s.Data[r] < outerFenceB)
                            DrawMarkerInCanvasCoordinates(xc, ToCanvasY(s.Data[r]), 2 * OUTLIER_RADIUS, MarkerShape.Circle, true, blackPen);

                //  Right-hand fences
                bool gatedInnerT = bwOptions.Method != BoxWhiskerOptions.BoxWhiskerMethod.SevenNumberSummary && bwOptions.Method != BoxWhiskerOptions.BoxWhiskerMethod.BowleySummary && s.Data[^1] > innerFenceT && innerFenceT > boxT;
                bool gatedOuterT = s.Data[^1] > outerFenceT && outerFenceT > boxT;

                // double outerFenceTY = ToCanvasY(gatedOuterT ? outerFenceT : s.Data[ s.Data.Length - 1 ]);

                //  Draw inner fence
                //  The inner fence goes to the first one of:
                //  - The inner fence for seven number and Bowley plots;
                //  - The inner fence if both inner and outer fences are selected and there's at least one outlier betond it;
                //  - Not drawn otherwise.
                bool shouldDrawInnerFenceT = false;
                double innerFenceTY = 0;
                if (bwOptions.Method == BoxWhiskerOptions.BoxWhiskerMethod.SevenNumberSummary || bwOptions.Method == BoxWhiskerOptions.BoxWhiskerMethod.BowleySummary)
                {
                    shouldDrawInnerFenceT = true;
                    innerFenceTY = ToCanvasY(innerFenceT);
                }
                if (shouldDrawInnerFenceT)
                {
                    PenDescriptor innerPen;
                    if (bwOptions.UseOuterFence || bwOptions.Method == BoxWhiskerOptions.BoxWhiskerMethod.SevenNumberSummary || bwOptions.Method == BoxWhiskerOptions.BoxWhiskerMethod.BowleySummary)
                        innerPen = dottedBlackPen;
                    else
                        innerPen = blackPen;
                    DrawLineInCanvasCoordinates(innerPen, xr, innerFenceTY, xl, innerFenceTY);
                }

                //  Draw max whisker
                //  The max whisker goes to the first one of:
                //  - The outer fence for seven number and Bowley plots;
                //  - The last data point below the inner fence if inner fence is selected;
                //  - The last data point below the outer fence if outer fence is selected;
                //  - The max data point otherwise.
                double maxWhiskerT = 0;
                if (bwOptions.Method == BoxWhiskerOptions.BoxWhiskerMethod.SevenNumberSummary || bwOptions.Method == BoxWhiskerOptions.BoxWhiskerMethod.BowleySummary)
                {
                    maxWhiskerT = outerFenceT;
                }
                else if (bwOptions.UseInnerFence)
                {
                    for (int i = s.Data.Length - 1; i >= 0; i--)
                    {
                        if (s.Data[i] <= innerFenceT)
                        {
                            maxWhiskerT = s.Data[i];
                            break;
                        }
                    }
                }
                else if (bwOptions.UseOuterFence)
                {
                    for (int i = s.Data.Length - 1; i >= 0; i--)
                    {
                        if (s.Data[i] <= outerFenceT)
                        {
                            maxWhiskerT = s.Data[i];
                            break;
                        }
                    }
                }
                else
                {
                    maxWhiskerT = s.Data[^1];
                }
                double maxWhiskerTY = ToCanvasY(maxWhiskerT);
                DrawLineInCanvasCoordinates(blackPen, xc, maxWhiskerTY, xc, ToCanvasY(boxT));

                //  Outer fence
                const bool shouldDrawOuterFenceT = true;
                // If (gatedInnerT OrElse gatedOuterT) _
                //     AndAlso Not (bwOptions.Method = BoxWhiskerOptions.BoxWhiskerMethod.SevenNumberSummary OrElse bwOptions.Method = BoxWhiskerOptions.BoxWhiskerMethod.BowleySummary) Then
                // If bwOptions.UseInnerFence AndAlso (Not bwOptions.UseOuterFence) AndAlso gatedInnerR Then
                //  At least one inner outlier, and we're not using the outer fence.  The inner fence will have been drawn; we should not draw this as well.
                // shouldDrawOuterFenceT = False
                //  End If
                // ReSharper disable RedundantLogicalConditionalExpressionOperand
                bool shouldDrawOuterBracketT = shouldDrawOuterFenceT && !(bwOptions.Method == BoxWhiskerOptions.BoxWhiskerMethod.SevenNumberSummary || bwOptions.Method == BoxWhiskerOptions.BoxWhiskerMethod.BowleySummary) && !(gatedOuterT || gatedInnerT);
                // ReSharper restore RedundantLogicalConditionalExpressionOperand
                if (shouldDrawOuterFenceT)
                {
                    DrawLineInCanvasCoordinates(blackPen, xr, maxWhiskerTY, xl, maxWhiskerTY);
                    if (shouldDrawOuterBracketT)
                    {
                        DrawLineInCanvasCoordinates(blackPen, xr, maxWhiskerTY - WHISKER_END_LENGTH, xr, maxWhiskerTY);
                        DrawLineInCanvasCoordinates(blackPen, xl, maxWhiskerTY, xl, maxWhiskerTY - WHISKER_END_LENGTH);
                    }
                }

                //  Max outliers
                if (gatedInnerT)
                    for (int r = 0; r < s.Data.Length; r++)
                        if (s.Data[r] > innerFenceT && (s.Data[r] <= outerFenceT || !gatedOuterT))
                            DrawMarkerInCanvasCoordinates(xc, ToCanvasY(s.Data[r]), 2 * OUTLIER_RADIUS, MarkerShape.Circle, false, blackPen);
                if (gatedOuterT)
                    for (int r = 0; r < s.Data.Length; r++)
                        if (s.Data[r] > outerFenceT)
                            DrawMarkerInCanvasCoordinates(xc, ToCanvasY(s.Data[r]), 2 * OUTLIER_RADIUS, MarkerShape.Circle, true, blackPen);
            }

            MaybeDrawMarkerLines(axisScales);
            EndVectorPlot();
            return new ParameterBag();
        }

        private ParameterBag PlotBoxWhiskerAscii(IList<ISeries> seriesToUse)
        {
            // sort the array and get the min, max values
            Layout.Range dataRangeX = GetMinMaxSort(seriesToUse);
            DataMinX = dataRangeX.Min;
            DataMaxX = dataRangeX.Max;

            BoxWhiskerOptions bwOptions = (BoxWhiskerOptions)Definition.ChartOptions;

            double p = (1.0 - bwOptions.Cco) / 2.0;
            if (p > 1.0 - p)
                p = 1.0 - p;

            StartAsciiPlot(seriesToUse.Count * 2 + 4);

            // Draw the scale
            LayoutChartAndDrawAxes(Definition.ChartOptions.Title,
                new AxisDefinition(bwOptions.XAxisTitle, AxisMode.Scale, Definition.ScaleParameters.X.ScaleType),
                new AxisDefinition(null, AxisMode.Series, Definition.ScaleParameters.Y.ScaleType) { Labels = seriesToUse.Select(s => s.Title).ToList() },
                false, false);
            DivY = seriesToUse.Count + 1;
            OffY = AsciiYTxt;

            if (TextCanvas[0].Length > bwOptions.XAxisTitle.Length)
            {
                WriteAsciiYX(0, 45 - bwOptions.XAxisTitle.Length / 2, bwOptions.XAxisTitle);
            }
            else
            {
                //  Axis title is larger than the chart, so replace the entire first string
                TextCanvas[0] = bwOptions.XAxisTitle;
            }

            // work through the columns
            for (int c = 0; c < seriesToUse.Count; c++)
            {
                DoubleSeries s = (DoubleSeries)seriesToUse[c];
                PlotBoxWhiskerCalc(s, bwOptions.Method, p, out double mdn, out double q1, out double q3, out double _, out double _, bwOptions.UseInnerFence, out double outerFenceL, out double outerFenceR, bwOptions.UseOuterFence, out double _, out bool _);

                bool gatedl;
                int xl;
                if (s.Data[0] < outerFenceL && outerFenceL < q1)
                {
                    xl = ToAsciiX(outerFenceL);
                    gatedl = true;
                }
                else
                {
                    xl = ToAsciiX(s.Data[0]);
                    gatedl = false;
                }

                bool gatedr;
                int xr;
                if (s.Data[^1] > outerFenceR && outerFenceR > q3)
                {
                    xr = ToAsciiX(outerFenceR);
                    gatedr = true;
                }
                else
                {
                    xr = ToAsciiX(s.Data[^1]);
                    gatedr = false;
                }

                int xm = ToAsciiX(mdn);

                int lq = ToAsciiX(q1);
                int uq = ToAsciiX(q3);

                // Plot it
                int y2 = 3 + c * 2;
                WriteAsciiYX(y2, lq, new string('.', uq - lq));
                WriteAsciiYX(y2, xm, "*");

                if (gatedl)
                {
                    int l = lq - xl;
                    if (l < 2)
                        l = 2;
                    WriteAsciiYX(y2, xl, "|" + new string('-', l - 2) + "[");
                    for (int r = 0; r < s.Data.Length; r++)
                    {
                        if (s.Data[r] < outerFenceL)
                        {
                            int x1 = ToAsciiX(s.Data[r]);
                            WriteAsciiYX(y2, x1, ".");
                        }
                    }
                }
                else
                {
                    int l = lq - xl;
                    if (l < 2)
                        l = 2;
                    WriteAsciiYX(y2, xl, ">" + new string('-', l - 2) + "[");
                }

                if (gatedr)
                {
                    int l = xr - uq;
                    if (l < 2)
                        l = 2;
                    WriteAsciiYX(y2, uq, "]" + new string('-', l - 2) + "|");
                    for (int r = 0; r < s.Data.Length; r++)
                    {
                        if (s.Data[r] > outerFenceR)
                        {
                            int x1 = ToAsciiX(s.Data[r]);
                            WriteAsciiYX(y2, x1, ".");
                        }
                    }
                }
                else
                {
                    int l = xr - uq;
                    if (l < 2)
                        l = 2;
                    WriteAsciiYX(y2, uq, "]" + new string('-', l - 2) + "<");
                }
            }
            return new ParameterBag();
        }

        ///  <summary>
        ///  Calculate and return as output parameters many values that are useful for a single box+whisker from the given series.
        ///  </summary>
        ///  <param name="s">The series to use for calculation</param>
        ///  <param name="method">The calculation method</param>
        ///  <param name="p">For Mean, CI, Range: the CI to calculate</param>
        ///  <param name="centre">Returns the median value</param>
        ///  <param name="boxL">Returns the lower quertile</param>
        ///  <param name="boxR">Returns the upper quartile</param>
        ///  <param name="innerFenceL">The lower inner fence value if used, 9th centile for seven number, or 10th centile for Bowley</param>
        ///  <param name="innerFenceR">The upper inner fence value if used, 91st centile for seven number, or 90th centile for Bowley</param>
        ///  <param name="useInnerFence">True to calculate inner fences</param>
        ///  <param name="outerFenceL">The lower outer fence value if used, 2nd centile for seven number, min otherwise</param>
        ///  <param name="outerFenceR">The upper outer fence value if used, 98th centile for seven number, max otherwise</param>
        ///  <param name="useOuterFence">True to calculate outer fences</param>
        ///  <param name="otherCentre">Another centre that might be appropriate to plot.  Mean if centre is median, and vice versa.</param>
        /// <param name="centreIsMedian">True if centre is the median and otherCentre is mean, false if the reverse is true.</param>
        private void PlotBoxWhiskerCalc(DoubleSeries s, BoxWhiskerOptions.BoxWhiskerMethod method, double p, out double centre, out double boxL, out double boxR, out double innerFenceL, out double innerFenceR, bool useInnerFence, out double outerFenceL, out double outerFenceR, bool useOuterFence, out double otherCentre, out bool centreIsMedian)
        {
            int count = s.Data.Length;
            switch (method)
            {
                case BoxWhiskerOptions.BoxWhiskerMethod.MedianQuartilesRange:
                case BoxWhiskerOptions.BoxWhiskerMethod.SevenNumberSummary:
                case BoxWhiskerOptions.BoxWhiskerMethod.BowleySummary:
                    {

                        //  Median
                        centre = Quantile(s, 0.5);
                        //  Lower quartile
                        boxL = Quantile(s, 0.25);
                        //  Upper quartile
                        boxR = Quantile(s, 0.75);

                        //  Inner fence
                        switch (method)
                        {
                            case BoxWhiskerOptions.BoxWhiskerMethod.MedianQuartilesRange:
                                double interQuartileRange = Math.Abs(boxR - boxL);
                                if (useInnerFence)
                                {
                                    innerFenceL = boxL - 1.5 * interQuartileRange;
                                    innerFenceR = boxR + 1.5 * interQuartileRange;
                                }
                                else
                                {
                                    //  Get out of the way!
                                    innerFenceL = boxL;
                                    innerFenceR = boxR;
                                }
                                break;
                            case BoxWhiskerOptions.BoxWhiskerMethod.SevenNumberSummary:
                                innerFenceL = Quantile(s, 0.09);
                                innerFenceR = Quantile(s, 0.91);
                                break;
                            case BoxWhiskerOptions.BoxWhiskerMethod.BowleySummary:
                                innerFenceL = Quantile(s, 0.1);
                                innerFenceR = Quantile(s, 0.9);
                                break;
                            default:
                                throw new Exception("Unexpected method");
                        }

                        //  Fences never extend beyond the data
                        if (innerFenceL < s.Data[0])
                            innerFenceL = s.Data[0];
                        if (innerFenceR > s.Data[^1])
                            innerFenceR = s.Data[^1];

                        //  Outer fence
                        switch (method)
                        {
                            case BoxWhiskerOptions.BoxWhiskerMethod.MedianQuartilesRange:
                                if (useOuterFence)
                                {
                                    double interQuartileRange = Math.Abs(boxR - boxL);
                                    outerFenceL = boxL - 3.0 * interQuartileRange;
                                    outerFenceR = boxR + 3.0 * interQuartileRange;
                                }
                                else
                                {
                                    //  Min/max
                                    outerFenceL = s.Data[0];
                                    outerFenceR = s.Data[s.Points - 1];
                                }
                                break;
                            case BoxWhiskerOptions.BoxWhiskerMethod.SevenNumberSummary:
                                outerFenceL = Quantile(s, 0.02);
                                outerFenceR = Quantile(s, 0.98);
                                break;
                            case BoxWhiskerOptions.BoxWhiskerMethod.BowleySummary:
                                //  Min/max
                                outerFenceL = s.Data[0];
                                outerFenceR = s.Data[s.Points - 1];
                                break;
                            default:
                                throw new Exception("Unexpected method");
                        }

                        //  Fences never extend beyond the data
                        if (outerFenceL < s.Data[0])
                            outerFenceL = s.Data[0];
                        if (outerFenceR > s.Data[^1])
                            outerFenceR = s.Data[^1];

                        centreIsMedian = true;
                        //  Other centre is the mean
                        double sum = 0;
                        for (int n = 0; n < count; n++)
                            sum += s.Data[n];
                        otherCentre = sum / Convert.ToDouble(count);

                    }
                    break;
                case BoxWhiskerOptions.BoxWhiskerMethod.MeanStandardDeviationRange:
                case BoxWhiskerOptions.BoxWhiskerMethod.MeanStandardErrorRange:
                case BoxWhiskerOptions.BoxWhiskerMethod.MeanConfidenceIntervalRange:
                    {
                        double sum = 0.0;
                        double sumsqdev = 0.0;

                        for (int n = 0; n < count; n++)
                            sum += s.Data[n];

                        double mean = sum / count;

                        for (int n = 0; n < count; n++)
                        {
                            if (Math.Abs(sumsqdev) > 1.0E+300)
                            {
                                sumsqdev = Constant.MISSING;
                                break;
                            }
                            double dev = s.Data[n] - mean;
                            sumsqdev += dev * dev;
                        }

                        centre = mean;
                        centreIsMedian = false;
                        otherCentre = Quantile(s, 0.5); //  Median
                        if (sumsqdev == Constant.MISSING)
                        {
                            //  Everything collapses
                            boxL = centre;
                            boxR = centre;
                            if (useInnerFence)
                            {
                                innerFenceL = centre;
                                innerFenceR = centre;
                            }
                            else
                            {
                                innerFenceL = 0;
                                innerFenceR = 0;
                            }
                            if (useOuterFence)
                            {
                                outerFenceL = centre;
                                outerFenceR = centre;
                            }
                            else
                            {
                                outerFenceL = 0;
                                outerFenceR = 0;
                            }
                        }
                        else
                        {
                            double variance = sumsqdev / (count - 1);
                            double standardDeviation = Math.Sqrt(variance);
                            double standardError = Math.Sqrt(variance / count);

                            switch (method)
                            {
                                case BoxWhiskerOptions.BoxWhiskerMethod.MeanStandardDeviationRange:
                                    boxL = mean - standardDeviation;
                                    boxR = mean + standardDeviation;
                                    break;
                                case BoxWhiskerOptions.BoxWhiskerMethod.MeanStandardErrorRange:
                                    boxL = mean - standardError;
                                    boxR = mean + standardError;
                                    break;
                                case BoxWhiskerOptions.BoxWhiskerMethod.MeanConfidenceIntervalRange:
                                    double cit = PDF.tfromp(p, Convert.ToDouble(count - 1));
                                    double bit = cit * standardDeviation / Math.Sqrt(count);
                                    boxL = mean - bit;
                                    boxR = mean + bit;
                                    break;
                                default:
                                    throw new Exception("Unexpected box+whisker plot type");
                            }

                            if (useInnerFence)
                            {
                                //  95% CI
                                double innerFenceFactor = PDF.gauinv(0.975);
                                innerFenceL = mean - innerFenceFactor * standardDeviation;
                                innerFenceR = mean + innerFenceFactor * standardDeviation;
                            }
                            else
                            {
                                innerFenceL = 0;
                                innerFenceR = 0;
                            }
                            if (useOuterFence)
                            {
                                //  99% CI
                                double outerFenceFactor = PDF.gauinv(0.995);
                                outerFenceL = mean - outerFenceFactor * standardDeviation;
                                outerFenceR = mean + outerFenceFactor * standardDeviation;
                            }
                            else
                            {
                                outerFenceL = 0;
                                outerFenceR = 0;
                            }
                        }
                    }
                    break;
                default:
                    throw new ArgumentOutOfRangeException(nameof(method), method.ToString());
            }
        }

        ///  <summary>
        ///  Get the nth centile (divided by 100,  so 0.25 for lower quartile etc) from the given series containing a sorted 0-based array of data.
        ///  This is the conventional quantile of the descriptive statistics (centile type 2, Summary.GetCentile): the n(count + 1)th ordered value, interpolating
        ///  between neighbours, which is what the help describes and what earlier versions plotted.  The C# port had used the (n * count + 0.5)th value.
        ///  </summary>
        private static double Quantile(DoubleSeries s, double n)
        {
            int count = s.Data.Length;
            if (count == 0)
                return Constant.MISSING;
            double position = n * (count + 1) - 1; // 0-based
            if (position <= 0.0)
                return s.Data[0];
            if (position >= count - 1)
                return s.Data[count - 1];
            int lower = (int)Math.Floor(position);
            double h = position - lower;
            return h == 0.0 ? s.Data[lower] : s.Data[lower] + (s.Data[lower + 1] - s.Data[lower]) * h;
        }
    }
}
