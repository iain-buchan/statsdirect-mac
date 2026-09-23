using StatsDirect.Charting.Scales;
using StatsDirect.Numerics;
using StatsDirect.Templates;
using System.Drawing;

namespace StatsDirect.Charting.Renderer
{
    class SurvivalChartRenderer : AbstractChartRenderer, IChartRenderer
    {
        public SurvivalChartRenderer(ChartDefinition definition, ICanvasFactory canvasFactory)
            : base(definition, canvasFactory)
        {
        }

        ScaleParameters IChartRenderer.GetScaleParameters()
        {
            SurvivalOptions sOptions = (SurvivalOptions)Definition.ChartOptions;

            // Setup the Min & Max Values
            DataMinX = double.MaxValue;
            DataMaxX = double.MinValue;
            DataMinY = double.MaxValue;
            DataMaxY = double.MinValue;
            foreach (SurvivalOptions.SurvivalSeries ss in sOptions.Series)
            {
                foreach (double d in ss.XDat)
                {
                    if (d != Constant.MISSING)
                    {
                        if (d < DataMinX)
                            DataMinX = d;
                        if (d > DataMaxX)
                            DataMaxX = d;
                    }
                }
                foreach (double d in ss.YDat)
                {
                    if (d != Constant.MISSING)
                    {
                        if (d < DataMinY)
                            DataMinY = d;
                        if (d > DataMaxY)
                            DataMaxY = d;
                    }
                }
            }

            // #641: User can change survival plot maximum within reason - it can be set between actual DataMaxY and 1.0
            double candidateMaxY = Definition.HasScaleParameters ? Definition.ScaleParameters.Y.Max : 1.0;
            if (candidateMaxY < DataMaxY)
                candidateMaxY = DataMaxY;
            if (candidateMaxY > 1.0)
                candidateMaxY = 1.0;
            DataMaxY = candidateMaxY;
            return new ScaleParameters
            {
                X =
                    {
                        AllowedScaleTypes = new[] { ScaleType.Linear },
                        Min = DataMinX,
                        Max = DataMaxX
                    },
                Y =
                    {
                        AllowedScaleTypes = new[] { ScaleType.Linear },
                        Max = DataMaxY,
                        Min = 0
                    }
            };
        }

        ParameterBag IChartRenderer.Plot(/* TODO: IPreferences*/ ITemplateHost _, bool isForReturnedParametersOnly)
        {
            if (isForReturnedParametersOnly)
                return new ParameterBag();

            SurvivalOptions sOptions = (SurvivalOptions)Definition.ChartOptions;

            // Setup the Min & Max Values
            DataMinX = double.MaxValue;
            DataMaxX = double.MinValue;
            DataMinY = double.MaxValue;
            DataMaxY = double.MinValue;
            bool doCi = true;
            foreach (SurvivalOptions.SurvivalSeries ss in sOptions.Series)
            {
                //  If any series doesn't have both confidence intervals, we don't plot them at all.
                if (ss.YDatL == null || ss.YDatU == null)
                {
                    doCi = false;
                }
                foreach (double d in ss.XDat)
                {
                    if (d != Constant.MISSING)
                    {
                        if (d < DataMinX)
                            DataMinX = d;
                        if (d > DataMaxX)
                            DataMaxX = d;
                    }
                }
                foreach (double d in ss.YDat)
                {
                    if (d != Constant.MISSING)
                    {
                        if (d < DataMinY)
                            DataMinY = d;
                        if (d > DataMaxY)
                            DataMaxY = d;
                    }
                }
            }
            DataMinY = 0;
            // #641: User can change survival plot maximum within reason - it can be set between actual DataMaxY and 1.0
            double candidateMaxY = Definition.HasScaleParameters ? Definition.ScaleParameters.Y.Max : 1.0;
            if (candidateMaxY < DataMaxY)
                candidateMaxY = DataMaxY;
            if (candidateMaxY > 1.0)
                candidateMaxY = 1.0;
            DataMaxY = candidateMaxY;

            bool useMarker = sOptions.ShowEventMarkers;
            bool useTic = sOptions.ShowCensorshipTics;

            //  Legend
            Legend legend = null;
            if (sOptions.ShowLegend)
            {
                legend = new Legend { Position = LegendPosition.Bottom };
                for (int c = 0; c < sOptions.Series.Count; c++)
                    legend.LegendEntries.Add(new LegendEntry { Label = MakeTitle(sOptions.SeriesTitles[c], string.Empty), MarkerType = sOptions.MarkerTypes[c] });
            }


            StartVectorPlot(sOptions, legend);
            AssignMarkersToSeries(sOptions);

            AxisScales axisScales = LayoutChartAndDrawAxes(sOptions.Title,
                new AxisDefinition("Times", AxisMode.Scale, Definition.ScaleParameters.X.ScaleType),
                new AxisDefinition(sOptions.YAxisTitle, AxisMode.Scale, Definition.ScaleParameters.Y.ScaleType),
                false, false,
                legend);
            DivY = 1;
            OffY = YAxisCanvas;

            // Work through the columns
            //  The CI marker type is always the last one in the list
            MarkerType ciMarkerType = sOptions.MarkerTypes[sOptions.MarkerTypes.Count - 1];
            for (int c = 0; c < sOptions.Series.Count; c++)
            {
                double[] ydat = sOptions.Series[c].YDat;
                double[] xdat = sOptions.Series[c].XDat;
                int[] cdat = sOptions.Series[c].CDat;
                double[] ydatL = sOptions.Series[c].YDatL;
                double[] ydatU = sOptions.Series[c].YDatU;

                MarkerType mType = sOptions.MarkerTypes[c];
                PenDescriptor p = GetMarkerPen(mType);
                double x1 = ToCanvasX(axisScales.X.MinimumScaleValue);
                double y1 = ToCanvasY(1.0);
                double x2 = 0;
                double y2 = 0;
                for (int r = ydat.GetLowerBound(0); r <= ydat.GetUpperBound(0); r++)
                {
                    if (ydat[r] != Constant.MISSING && xdat[r] != Constant.MISSING && cdat[r] != -1)
                    {
                        x2 = ToCanvasX(xdat[r]);
                        y2 = ToCanvasY(ydat[r]);
                        if (useMarker && cdat[r] > 0)
                            DrawMarkerInCanvasCoordinates(x2, y2, mType.MarkerSize, mType);
                        // Draw tic if censored
                        if (cdat[r] == 0 && useTic)
                            DrawLineInCanvasCoordinates(p, x2, y2, x2, y2 + 7);
                        // Then the lines
                        DrawLineInCanvasCoordinates(p, x1, y1, x2, y1);
                        DrawLineInCanvasCoordinates(p, x2, y1, x2, y2);
                    }
                    x1 = x2;
                    y1 = y2;
                }

                //  overlay confidence intervals
                if (doCi)
                {
                    ColorDescriptor ciPenColour = sOptions.UseSeriesColourForConfidenceIntervals ? p.Color : ciMarkerType.LineColor;
                    PenDescriptor ciPen = new(ciPenColour, ciMarkerType.Width) { DashStyle = ciMarkerType.LineDashStyle };
                    for (int r = ydat.GetLowerBound(0); r <= ydat.GetUpperBound(0); r++)
                    {
                        if (ydat[r] != Constant.MISSING && ydatL[r] != Constant.MISSING && ydatU[r] != Constant.MISSING && xdat[r] != Constant.MISSING && cdat[r] != -1)
                        {
                            // Confidence interval
                            if (cdat[r] > 0)
                                DrawLineInChartCoordinates(ciPen, xdat[r], ydatL[r], xdat[r], ydatU[r]);
                        }
                    }
                }
            }

            if (null != legend)
                DrawLegend(legend);

            EndVectorPlot();
            return new ParameterBag();
        }
    }
}
