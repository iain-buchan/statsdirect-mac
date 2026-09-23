using System;
using System.Drawing;
using StatsDirect.Charting.Scales;
using StatsDirect.Numerics;
using StatsDirect.Templates;

namespace StatsDirect.Charting.Renderer
{
    class ScatterChartRenderer: AbstractChartRenderer, IChartRenderer
    {
        const int ASCII_LINES_PER_TIC = 5;

        public ScatterChartRenderer(ChartDefinition cd, ICanvasFactory canvasFactory)
            : base (cd, canvasFactory)
        {
        }

        ScaleParameters IChartRenderer.GetScaleParameters()
        {
            return new ScaleParameters
            {
                X =
                {
                    AllowedScaleTypes = new[] { ScaleType.Linear, ScaleType.Log10, ScaleType.LogNatural, ScaleType.Date },
                    Max = DataMaxX,
                    MinGreaterThanZero = DataMinGreaterThanZeroX,
                    Min = DataMinX
                },
                Y =
                {
                    AllowedScaleTypes = new[] { ScaleType.Linear, ScaleType.Log10, ScaleType.LogNatural },
                    Max = DataMaxY,
                    MinGreaterThanZero = DataMinGreaterThanZeroY,
                    Min = DataMinY
                }
            };
        }

        ParameterBag IChartRenderer.Plot(/* TODO: IPreferences*/ ITemplateHost _, bool isForReturnedParametersOnly)
        {
            if (isForReturnedParametersOnly)
                return new ParameterBag();

            ScatterXYOptions sOptions = (ScatterXYOptions)Definition.ChartOptions;
            bool shouldDrawMarkers = sOptions.PlotMarkers;
            bool joinMarkersWithLines = sOptions.JoinMarkersWithLines;

            bool showLegend = sOptions.ShowLegend && Definition.XSeries.Count > 1;
            Legend legend = null;
            if (!IsAscii)
            {
                // The legend copies each series' marker, so the markers must be assigned first: on the first render they were still unset, and drawing the legend threw.
                AssignMarkersToSeries(sOptions);
                if (showLegend)
                {
                    legend = new Legend() { Position = LegendPosition.Left };
                    foreach (ISeries s in Definition.XSeries)
                        legend.LegendEntries.Add(new LegendEntry() { MarkerType = ((DoubleSeries)s).MarkerType, Label = s.Title });
                }

                // Plot a metafile version
                StartVectorPlot(sOptions, legend);
                AxisScales axisScales = LayoutChartAndDrawAxes(Definition.ChartOptions.Title,
                    new AxisDefinition(sOptions.XAxisTitle, AxisMode.Scale, Definition.ScaleParameters.X.ScaleType),
                    new AxisDefinition(sOptions.YAxisTitle, AxisMode.Scale, Definition.ScaleParameters.Y.ScaleType),
                    ChartPreferences.DefaultBoxAxes, false,
                    legend);

                if (showLegend)
                    DrawLegend(legend);

                // plot points
                for (int c = 0; c < Definition.XSeries.Count; c++)
                {
                    DoubleSeries xs = (DoubleSeries)Definition.XSeries[c];
                    DoubleSeries ys = (DoubleSeries)Definition.YSeries[c];
                    double[] xdat = xs.Data;
                    double[] ydat = ys.Data;
                    PointF[] xys = new PointF[xs.Data.Length];
                    for (int r = 0; r < xs.Data.Length; r++)
                    {
                        if (xdat[r] != Constant.MISSING && ydat[r] != Constant.MISSING)
                        {
                            xys[r].X = Convert.ToSingle(ToCanvasX(xdat[r]));
                            xys[r].Y = Convert.ToSingle(ToCanvasY(ydat[r]));
                        }
                        else
                        {
                            xys[r].X = -1;
                            xys[r].Y = -1;
                        }
                        if (float.IsInfinity(xys[r].X) || float.IsInfinity(xys[r].Y)
                            || float.IsNaN(xys[r].X) || float.IsNaN(xys[r].Y))
                        {
                            xys[r].X = -1;
                            xys[r].Y = -1;
                        }
                    }
                    PenDescriptor markerPen = GetMarkerPen(ys.MarkerType), linePen = GetLinePen(ys.MarkerType, false);
                    DrawMarkerSeriesInCanvasCoordinates(xys, ys.MarkerType.MarkerSize, ys.MarkerType.MarkerShape, ys.MarkerType.IsMarkerFilled, markerPen, linePen, joinMarkersWithLines, shouldDrawMarkers);
                }
                MaybeDrawMarkerLines(axisScales);
                EndVectorPlot();
            }
            else
            {
                int y = Definition.ScaleParameters.Y.AxisScale.Tics().Count * ASCII_LINES_PER_TIC - 1;
                StartAsciiPlot(5 + y); // 5 = Title, top axis title, bottom axis, bottom scale, bottom axis title

                // Draw the scale
                LayoutChartAndDrawAxes(Definition.ChartOptions.Title,
                    new AxisDefinition(sOptions.XAxisTitle, AxisMode.Scale, Definition.ScaleParameters.X.ScaleType),
                    new AxisDefinition(sOptions.YAxisTitle, AxisMode.Scale, Definition.ScaleParameters.Y.ScaleType),
                    false, false);

                // Draw the title text
                int l = sOptions.YAxisTitle.Length;
                int q = l < 14 ? 14 - l : 2;
                WriteAsciiYX(TextCanvas.GetUpperBound(0) - 1, q, sOptions.YAxisTitle);
                l = sOptions.XAxisTitle.Length;
                WriteAsciiYX(0, 76 - l, sOptions.XAxisTitle);

                // Work through the columns
                for (int c = 0; c < Definition.XSeries.Count; c++)
                {
                    DoubleSeries xs = (DoubleSeries)Definition.XSeries[c];
                    DoubleSeries ys = (DoubleSeries)Definition.YSeries[c];
                    double[] xdat = xs.Data;
                    double[] ydat = ys.Data;
                    // Work through the rows
                    for (int r = 0; r < xdat.Length; r++)
                        if (xdat[r] != Constant.MISSING && ydat[r] != Constant.MISSING)
                            AsciiPlotPointInChartCoordinates(xdat[r], ydat[r]);
                }
            }
            return new ParameterBag();
        }
    }
}
