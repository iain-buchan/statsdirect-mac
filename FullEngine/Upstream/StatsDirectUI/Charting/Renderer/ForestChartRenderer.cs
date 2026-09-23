using StatsDirect.Charting.Scales;
using StatsDirect.Numerics;
using StatsDirect.Templates;
using StatsDirect.Utilities;
using System;
using System.Drawing;

namespace StatsDirect.Charting.Renderer
{
    class ForestChartRenderer : AbstractForestishChartRenderer, IChartRenderer
    {
        public ForestChartRenderer(ChartDefinition definition, ICanvasFactory canvasFactory)
            : base(definition, canvasFactory)
        {
        }

        ScaleParameters IChartRenderer.GetScaleParameters()
        {
            ForestOptions fOptions = (ForestOptions)Definition.ChartOptions;
            int k = fOptions.k;

            DataMaxX = double.MinValue;
            DataMinX = double.MaxValue;
            DataMinGreaterThanZeroX = double.MaxValue;

            for (int i = 0; i < k; i++)
            {
                if (fOptions.OddsRatios[i] != Constant.MISSING && !double.IsInfinity(fOptions.OddsRatios[i]))
                {
                    // Odds ratio
                    if (fOptions.OddsRatios[i] > DataMaxX)
                        DataMaxX = fOptions.OddsRatios[i];
                    if (fOptions.OddsRatios[i] < DataMinX)
                        DataMinX = fOptions.OddsRatios[i];
                    if (fOptions.OddsRatios[i] > 0 && fOptions.OddsRatios[i] < DataMinGreaterThanZeroX)
                        DataMinGreaterThanZeroX = fOptions.OddsRatios[i];

                    // Swap LCI and UCI if the user's entered them the wrong way round
                    if (fOptions.OddsRatioLcis[i] != Constant.MISSING && fOptions.OddsRatioUcis[i] != Constant.MISSING && fOptions.OddsRatioLcis[i] > fOptions.OddsRatioUcis[i])
                    {
                        double tmp = fOptions.OddsRatioLcis[i];
                        fOptions.OddsRatioLcis[i] = fOptions.OddsRatioUcis[i];
                        fOptions.OddsRatioUcis[i] = tmp;
                    }
                    if (fOptions.OddsRatioLcis[i] != Constant.MISSING && !double.IsInfinity(fOptions.OddsRatioLcis[i]))
                    {
                        if (fOptions.OddsRatioLcis[i] > DataMaxX)
                            DataMaxX = fOptions.OddsRatioLcis[i];
                        if (fOptions.OddsRatioLcis[i] < DataMinX)
                            DataMinX = fOptions.OddsRatioLcis[i];
                        if (fOptions.OddsRatioLcis[i] > 0 && fOptions.OddsRatioLcis[i] < DataMinGreaterThanZeroX)
                            DataMinGreaterThanZeroX = fOptions.OddsRatioLcis[i];
                    }
                    if (fOptions.OddsRatioUcis[i] != Constant.MISSING && !double.IsInfinity(fOptions.OddsRatioUcis[i]))
                    {
                        if (fOptions.OddsRatioUcis[i] > DataMaxX)
                            DataMaxX = fOptions.OddsRatioUcis[i];
                        if (fOptions.OddsRatioUcis[i] < DataMinX)
                            DataMinX = fOptions.OddsRatioUcis[i];
                        if (fOptions.OddsRatioUcis[i] > 0 && fOptions.OddsRatioUcis[i] < DataMinGreaterThanZeroX)
                            DataMinGreaterThanZeroX = fOptions.OddsRatioUcis[i];
                    }
                }
            }

            bool shouldDrawLine = DataMinX <= 0 || null != Definition && Definition.HasScaleParameters && Definition.ScaleParameters.X.MarkerLineValue.HasValue;
            double lineX = null != Definition && Definition.HasScaleParameters && Definition.ScaleParameters.X.MarkerLineValue.HasValue ? Definition.ScaleParameters.X.MarkerLineValue.Value : 0;
            if (shouldDrawLine)
            {
                if (DataMaxX < lineX)
                    DataMaxX = lineX;
                if (DataMinX > lineX)
                    DataMinX = lineX;
            }

            return new ScaleParameters
            {
                X = { AllowedScaleTypes = new[] { ScaleType.Linear, ScaleType.Log10 }, Min = DataMinX, MinGreaterThanZero = DataMinGreaterThanZeroX, Max = DataMaxX },
                Y = { AllowedScaleTypes = new[] { ScaleType.Category } }
            };
        }

        ParameterBag IChartRenderer.Plot(/* TODO: IPreferences*/ ITemplateHost _, bool isForReturnedParametersOnly)
        {
            if (isForReturnedParametersOnly)
                return new ParameterBag();

            int pbias = 0;

            ForestOptions fOptions = (ForestOptions)Definition.ChartOptions;
            studyMarkerType = fOptions.MarkerTypes[0];
            pooledMarkerType = fOptions.MarkerTypes[1];

            double[] pg = fOptions.pg;
            int k = fOptions.k;


            ScaleHeight(k);

            int kok = 0;
            DataMaxX = double.NegativeInfinity;
            DataMinX = double.PositiveInfinity;
            DataMinGreaterThanZeroX = double.PositiveInfinity;
            double max_gn = double.NegativeInfinity;

            for (int i = 0; i < k; i++)
            {
                if (pg == null || pg[i] == 0)
                {
                    if (fOptions.GroupSizes[i] != Constant.MISSING && !double.IsInfinity(fOptions.GroupSizes[i]) && fOptions.GroupSizes[i] > max_gn)
                        max_gn = fOptions.GroupSizes[i];
                }
                if (fOptions.OddsRatios[i] != Constant.MISSING && !double.IsInfinity(fOptions.OddsRatios[i]))
                {
                    kok++;
                    if (fOptions.OddsRatios[i] > DataMaxX)
                        DataMaxX = fOptions.OddsRatios[i];
                    if (fOptions.OddsRatios[i] < DataMinX && fOptions.OddsRatios[i] > 0)
                        DataMinX = fOptions.OddsRatios[i];
                    if (fOptions.OddsRatios[i] > 0 && fOptions.OddsRatios[i] < DataMinGreaterThanZeroX)
                        DataMinGreaterThanZeroX = fOptions.OddsRatios[i];
                    if (fOptions.OddsRatioLcis[i] != Constant.MISSING && fOptions.OddsRatioUcis[i] != Constant.MISSING && fOptions.OddsRatioLcis[i] > fOptions.OddsRatioUcis[i])
                    {
                        double tmp = fOptions.OddsRatioLcis[i];
                        fOptions.OddsRatioLcis[i] = fOptions.OddsRatioUcis[i];
                        fOptions.OddsRatioUcis[i] = tmp;
                    }
                    if (fOptions.OddsRatioLcis[i] == Constant.MISSING)
                        fOptions.OddsRatioLcis[i] = double.NegativeInfinity;
                    if (fOptions.OddsRatioUcis[i] == Constant.MISSING)
                        fOptions.OddsRatioUcis[i] = double.PositiveInfinity;
                    if (fOptions.OddsRatioLcis[i] < DataMinX && fOptions.OddsRatioLcis[i] > 0 && !double.IsInfinity(fOptions.OddsRatioLcis[i]))
                        DataMinX = fOptions.OddsRatioLcis[i];
                    if (fOptions.OddsRatioUcis[i] > DataMaxX && !double.IsInfinity(fOptions.OddsRatioUcis[i]))
                        DataMaxX = fOptions.OddsRatioUcis[i];
                }
            }

            double absmin = double.PositiveInfinity;
            for (int i = 0; i < k; i++)
            {
                if (Math.Abs(fOptions.OddsRatios[i]) < absmin && fOptions.OddsRatios[i] != 0.0 && fOptions.OddsRatios[i] != Constant.MISSING && !double.IsInfinity(fOptions.OddsRatios[i]))
                    absmin = Math.Abs(fOptions.OddsRatios[i]);
                if (Math.Abs(fOptions.OddsRatioLcis[i]) < absmin && fOptions.OddsRatioLcis[i] != 0.0 && !double.IsInfinity(fOptions.OddsRatioLcis[i]))
                    absmin = Math.Abs(fOptions.OddsRatioLcis[i]);
                if (Math.Abs(fOptions.OddsRatioUcis[i]) < absmin && fOptions.OddsRatioUcis[i] != 0.0 && !double.IsInfinity(fOptions.OddsRatioUcis[i]))
                    absmin = Math.Abs(fOptions.OddsRatioUcis[i]);
            }
            DataMinGreaterThanZeroX = DataMinX;

            int decimalPlaces = fOptions.EffectSizeAndIntervalDecimalPlaces;

            // Determine whether to draw a vertical line and, if so, where; ensure it is within our scale.
            bool shouldDrawLine = DataMinX <= 0 || null != Definition && Definition.HasScaleParameters && Definition.ScaleParameters.X.MarkerLineValue.HasValue;
            double lineX = null != Definition && Definition.HasScaleParameters && Definition.ScaleParameters.X.MarkerLineValue.HasValue ? Definition.ScaleParameters.X.MarkerLineValue.Value : 0;
            if (shouldDrawLine)
            {
                if (DataMaxX < lineX)
                    DataMaxX = lineX;
                if (DataMinX > lineX)
                    DataMinX = lineX;
                if (null != Definition && Definition.HasScaleParameters)
                {
                    if (Definition.ScaleParameters.X.Max < lineX)
                        Definition.ScaleParameters.X.Max = lineX;
                    if (Definition.ScaleParameters.X.Min > lineX)
                        Definition.ScaleParameters.X.Min = lineX;
                }
            }

            StartVectorPlot(fOptions);

            double rgap = 0;
            double xtra = 0;
            //  Allow room for right hand labels of effect and CI
            for (int i = 0; i < k; i++)
            {
                if (fOptions.OddsRatios[i] != Constant.MISSING && !double.IsInfinity(fOptions.OddsRatios[i]))
                {
                    double titleWidth = LegendWidthInCanvasCoordinates(fOptions.Titles[i]);
                    if (titleWidth > xtra)
                        xtra = titleWidth;
                    string rhs = Formatting.RoundMeta(fOptions.OddsRatios[i], absmin, decimalPlaces) + " (" + Formatting.RoundMeta(fOptions.OddsRatioLcis[i], absmin, decimalPlaces) + ", " + Formatting.RoundMeta(fOptions.OddsRatioUcis[i], absmin, decimalPlaces) + ")";
                    double rhsWidth = LegendWidthInCanvasCoordinates(rhs);
                    if (rhsWidth > rgap)
                        rgap = rhsWidth;
                }
            }
            AxisScales axisScales = LayoutChartAndDrawAxes(fOptions.Title,
                new AxisDefinition(fOptions.XAxisTitle, AxisMode.Scale, Definition.ScaleParameters.X.ScaleType) { ExtraSpaceBeforeAxisStarts = xtra, ExtraSpaceAfterAxisEnds = rgap },
                new AxisDefinition(null, AxisMode.None, ScaleType.NotSet),
                false, false);
            axisScales.Y = new CategoryAxisScale(k + pbias);
            DivY = kok + pbias;
            OffY = YAxisCanvas;

            int r = 0;

            PenDescriptor effectTenPen = GetLinePen(ChartPreferences.MarkerTypes[10], false),
                ciPen = GetLinePen(studyMarkerType, true),
                dotPen = GetMarkerPen(ChartPreferences.MarkerTypes[10]),
                pooledCiPen = GetLinePen(pooledMarkerType, true);
            double yt = 0;
            for (int i = k - 1; i >= 0; --i)
            {
                if (fOptions.OddsRatios[i] != Constant.MISSING && !double.IsInfinity(fOptions.OddsRatios[i]))
                {
                    r++;
                    double yctr = ToCanvasHeight(r + pbias - 0.5);
                    double ytop = ToCanvasHeight(r + pbias);
                    double xm = ToCanvasX(Math.Max(fOptions.OddsRatios[i], axisScales.X.MinimumScaleValue));
                    double xl = ToCanvasX(Math.Max(fOptions.OddsRatioLcis[i], axisScales.X.MinimumScaleValue));
                    double xr = ToCanvasX(Math.Min(fOptions.OddsRatioUcis[i], axisScales.X.MaximumScaleValue));
                    double y2 = (ytop - yctr) / 1.5;
                    double y3 = (ytop - yctr) / 4;
                    double yc = OffY + yctr;
                    yt = OffY + yctr + y2;
                    double yb = OffY + yctr - y2;
                    if (pg == null || pg[i] == 0)
                    {
                        // Weight blob.  Draw this first so that the line appears in front of it in the case of short lines (#994).
                        // #688: Make blob size proportional to sqrt(1/variance) rather than 1/variance
                        double blobSize = (5 + Math.Abs(yt - yb) * Math.Sqrt(fOptions.GroupSizes[i] / max_gn)) * 0.7;
                        DrawMarkerInCanvasCoordinates(xm, yc, blobSize / 2, studyMarkerType);

                        // CI line
                        DrawLineInCanvasCoordinates(ciPen, xl, yc, xr, yc);
                        // Arrow ends if not plottable
                        if (fOptions.OddsRatioLcis[i] < axisScales.X.MinimumScaleValue || double.IsInfinity(fOptions.OddsRatioLcis[i]))
                        {
                            DrawLineInCanvasCoordinates(ciPen, xl + y3, yc + y3, xl, yc);
                            DrawLineInCanvasCoordinates(ciPen, xl, yc, xl + y3, yc - y3);
                        }
                        if (fOptions.OddsRatioUcis[i] > axisScales.X.MaximumScaleValue || double.IsInfinity(fOptions.OddsRatioUcis[i]))
                        {
                            DrawLineInCanvasCoordinates(ciPen, xr - y3, yc + y3, xr, yc);
                            DrawLineInCanvasCoordinates(ciPen, xr, yc, xr - y3, yc - y3);
                        }

                        // Centre mark.  If drawn, draw this last so that it appears in front of the line.
                        if (fOptions.MarkCentres)
                            DrawMarkerInCanvasCoordinates(xm, yc, 2, MarkerShape.Circle, true, dotPen);
                    }
                    else
                    {
                        // Pooled effect
                        DrawMarkerInCanvasCoordinates(xm, yc, y2, pooledMarkerType);
                        DrawLineInCanvasCoordinates(pooledCiPen, xr, yc, xl, yc);
                        if (pg[i] < 0)
                        {
                            // pooled effect marker
                            DrawLineInCanvasCoordinates(effectTenPen, xm, yt, xm, ToCanvasY(k + pbias - 0.5));
                        }
                        // Arrow ends if not plottable
                        if (fOptions.OddsRatioLcis[i] < axisScales.X.MinimumScaleValue || double.IsInfinity(fOptions.OddsRatioLcis[i]))
                        {
                            DrawLineInCanvasCoordinates(pooledCiPen, xl + y3, yc + y3, xl, yc);
                            DrawLineInCanvasCoordinates(pooledCiPen, xl, yc, xl + y3, yc - y3);
                        }
                        if (fOptions.OddsRatioUcis[i] > axisScales.X.MaximumScaleValue || double.IsInfinity(fOptions.OddsRatioUcis[i]))
                        {
                            DrawLineInCanvasCoordinates(pooledCiPen, xr - y3, yc + y3, xr, yc);
                            DrawLineInCanvasCoordinates(pooledCiPen, xr, yc, xr - y3, yc - y3);
                        }

                    }
                    AxisDrawStringAtAngleRM(fOptions.Titles[i], XAxisCanvas - 15, yc, Definition.ScaleParameters.Y.LabelDirection);
                    DrawStringLabel(Formatting.RoundMeta(fOptions.OddsRatios[i], absmin, decimalPlaces) + " (" + Formatting.RoundMeta(fOptions.OddsRatioLcis[i], absmin, decimalPlaces) + ", " + Formatting.RoundMeta(fOptions.OddsRatioUcis[i], absmin, decimalPlaces) + ")", XAxisCanvas + XExtCanvas + 10, yc, StringAlignment.Near, StringAlignment.Center);
                }
            }

            if (shouldDrawLine)
            {
                // no effect line, which is effectively part of the axis so uses the axis pen
                DrawLineInCanvasCoordinates(AxisPen, ToCanvasX(lineX), yt, ToCanvasX(lineX), ToCanvasY(axisScales.Y.MinimumScaleValue));
            }

            EndVectorPlot();
            return new ParameterBag();
        }
    }
}
