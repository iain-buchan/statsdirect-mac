using StatsDirect.Charting.Scales;
using StatsDirect.Numerics;
using StatsDirect.Templates;
using System;

namespace StatsDirect.Charting.Renderer
{
    class CoxSurvivalOrHazardChartRenderer : AbstractChartRenderer, IChartRenderer
    {
        public CoxSurvivalOrHazardChartRenderer(ChartDefinition definition, ICanvasFactory canvasFactory)
            : base(definition, canvasFactory)
        {
        }

        ScaleParameters IChartRenderer.GetScaleParameters()
        {
            return new ScaleParameters
            {
                X = new AxisScaleParameters { ScaleType = ScaleType.Linear },
                Y = new AxisScaleParameters { ScaleType = ScaleType.Linear }
            };
        }

        ParameterBag IChartRenderer.Plot(/* TODO: IPreferences*/ ITemplateHost _, bool isForReturnedParametersOnly)
        {
            if (isForReturnedParametersOnly)
                return new ParameterBag();

            CoxSurvivalOrHazardOptions options = (CoxSurvivalOrHazardOptions)Definition.ChartOptions;
            DataMaxX = double.MinValue;
            DataMaxY = double.MinValue;
            DataMinX = double.MaxValue;
            DataMinY = double.MaxValue;
            const string tim = "Time";
            string xAxisSuffix = options.grouped ? "(individual)" : "(baseline)";
            string title;
            string xAxisTitle;
            string yAxisTitle;
            switch (options.plotMode)
            {
                case CoxPlotMode.Survival:
                    xAxisTitle = tim;
                    yAxisTitle = "Survival Probability " + xAxisSuffix;
                    title = "Survival Plot (Cox regression)";
                    DataMaxY = 1;
                    DataMinY = 0;
                    for (int i = 1; i <= options.iobs; i++)
                    {
                        if (options.z[i].Time > DataMaxX)
                            DataMaxX = options.z[i].Time;
                        if (options.z[i].Time < DataMinX)
                            DataMinX = options.z[i].Time;
                    }
                    break;
                case CoxPlotMode.Hazard:
                    xAxisTitle = tim;
                    yAxisTitle = "Cumulative Hazard " + xAxisSuffix;
                    title = "Hazard Plot (Cox regression)";
                    for (int i = 1; i <= options.iobs; i++)
                    {
                        if (options.z[i].Time > DataMaxX)
                            DataMaxX = options.z[i].Time;
                        if (options.z[i].Time < DataMinX)
                            DataMinX = options.z[i].Time;
                        double haz;
                        if (options.grouped)
                        {
                            haz = Math.Pow(options.z[i].S, Math.Exp(Convert.ToDouble(options.z[i].Id) * options.arr3[1, options.groupid, 1]));
                            haz = haz > 0.0 ? -Math.Log(haz) : Constant.MISSING;
                        }
                        else
                            haz = options.z[i].H;
                        if (haz != Constant.MISSING & haz > DataMaxY & options.z[i].Censor != 0)
                            DataMaxY = haz;
                        if (haz != Constant.MISSING & haz < DataMinY & options.z[i].Censor != 0)
                            DataMinY = haz;
                    }
                    break;
                default:
                    throw new Exception("Unexpected case");
            }

            AssignMarkersToSeries();

            Legend legend = new();
            if (options.grouped)
            {
                for (int k = 1; k <= options.igroups; k++)
                {
                    MarkerType legendMarker = ChartPreferences.MarkerTypes[(k - 1) % 9].Clone();
                    if (!options.useMarker)
                    {
                        legendMarker = legendMarker.Clone();
                        legendMarker.MarkerShape = MarkerShape.SurvivalTic;
                    }
                    string vq = options.cdat1[options.groupid].Title.Substring(0, Math.Min(20, options.cdat1[options.groupid].Title.Length)) + "=" + options.cdat1[options.groupid].Groups[k - 1].Label;
                    legend.LegendEntries.Add(new LegendEntry { Label = vq, MarkerType = legendMarker });
                }
            }
            if (options.stratified)
            {
                for (int k = 1; k <= options.istrata; k++)
                {
                    MarkerType legendMarker = ChartPreferences.MarkerTypes[(k - 1) % 9].Clone();
                    if (!options.useMarker)
                    {
                        legendMarker = legendMarker.Clone();
                        legendMarker.MarkerShape = MarkerShape.SurvivalTic;
                    }
                    string vq = "Stratum " + k;
                    legend.LegendEntries.Add(new LegendEntry { Label = vq, MarkerType = legendMarker });
                }
            }

            StartVectorPlot(null, legend);

            // Draw the axes
            AxisScales axisScales = LayoutChartAndDrawAxes(title,
                new AxisDefinition(xAxisTitle, AxisMode.Scale, Definition.ScaleParameters.X.ScaleType),
                new AxisDefinition(yAxisTitle, AxisMode.Scale, Definition.ScaleParameters.Y.ScaleType),
                false, false,
                legend);

            // starting positions
            double ix0 = 0;
            double iy0 = 0;
            switch (options.plotMode)
            {
                case CoxPlotMode.Survival:
                    ix0 = ToCanvasX(axisScales.X.MinimumScaleValue);
                    iy0 = ToCanvasY(1.0);
                    break;
                case CoxPlotMode.Hazard:
                    ix0 = ToCanvasX(axisScales.X.MinimumScaleValue);
                    iy0 = ToCanvasY(0.0);
                    break;
            }

            double ix1 = ix0;
            double iy1 = iy0;
            int igp = 0;

            MarkerType mt = ChartPreferences.MarkerTypes[igp % 9];
            MarkerShape shape = mt.MarkerShape;
            bool isFilled = mt.IsMarkerFilled;
            PenDescriptor markerPen = GetMarkerPen(mt);
            PenDescriptor linePen = GetLinePen(mt, true);

            for (int i = 1; i <= options.iobs; i++)
            {
                if (i > 1 && (options.grouped ? options.z[i].Id != options.z[i - 1].Id : options.z[i].Stratum != options.z[i - 1].Stratum))
                {
                    igp += 1;
                    ix1 = ix0;
                    iy1 = iy0;
                    mt = ChartPreferences.MarkerTypes[igp % 9];
                    markerPen = GetMarkerPen(mt);
                    linePen = GetLinePen(mt, true);
                    shape = mt.MarkerShape;
                    isFilled = mt.IsMarkerFilled;
                }

                double ix2 = ToCanvasX(options.z[i].Time);
                double iy2 = 0;

                // get survivor or hazard function if an event occured
                switch (options.plotMode)
                {
                    case CoxPlotMode.Survival:
                        double surv = options.grouped ? Math.Pow(options.z[i].S, Math.Exp(Convert.ToDouble(options.z[i].Id) * options.arr3[1, options.groupid, 1])) : options.z[i].S;
                        iy2 = ToCanvasY(surv);
                        break;
                    case CoxPlotMode.Hazard:
                        double haz;
                        if (options.grouped)
                        {
                            haz = Math.Pow(options.z[i].S, Math.Exp(Convert.ToDouble(options.z[i].Id) * options.arr3[1, options.groupid, 1]));
                            haz = haz > 0.0 ? -Math.Log(haz) : Constant.MISSING;
                        }
                        else
                        {
                            haz = options.z[i].H;
                        }
                        if (haz != Constant.MISSING)
                            iy2 = ToCanvasY(haz);
                        break;
                }

                if (options.z[i].Censor == 0)
                    iy2 = iy1;

                if (options.z[i].Censor == 0 && options.useTic)
                {
                    // Draw tic if censored
                    if (ix1 != ix2 || iy1 != iy2)
                        DrawLineInCanvasCoordinates(linePen, ix2, iy2, ix2, iy2 + 7);
                }

                // Draw the markers
                if (iy2 != iy1 && options.useMarker)
                    DrawMarkerInCanvasCoordinates(ix2, iy2, 6, shape, isFilled, markerPen);

                // Then the lines
                if (ix1 != ix2 || iy1 != iy2)
                {
                    DrawLineInCanvasCoordinates(linePen, ix1, iy1, ix2, iy1);
                    DrawLineInCanvasCoordinates(linePen, ix2, iy1, ix2, iy2);
                }
                ix1 = ix2;
                iy1 = iy2;
            }
            DrawLegend(legend);
            EndVectorPlot();
            return new ParameterBag();
        }
    }
}
