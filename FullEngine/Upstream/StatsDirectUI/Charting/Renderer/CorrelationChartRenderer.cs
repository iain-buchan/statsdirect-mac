using StatsDirect.Charting.Scales;
using StatsDirect.Numerics;
using StatsDirect.Templates;
using StatsDirect.Utilities;
using System;
using System.Drawing;

namespace StatsDirect.Charting.Renderer
{
    class CorrelationChartRenderer : AbstractChartRenderer, IChartRenderer
    {
        public CorrelationChartRenderer(ChartDefinition definition, ICanvasFactory canvasFactory)
            : base(definition, canvasFactory)
        {
        }

        ScaleParameters IChartRenderer.GetScaleParameters()
        {
            CorrelationOptions options = (CorrelationOptions)Definition.ChartOptions;
            return new ScaleParameters
            {
                X = new AxisScaleParameters { ScaleType = Transformation.Log == options.Xform ? ScaleType.Log10 : ScaleType.Linear },
                Y = new AxisScaleParameters { ScaleType = ScaleType.Linear }
            };
        }

        ParameterBag IChartRenderer.Plot(/* TODO: IPreferences*/ ITemplateHost _, bool isForReturnedParametersOnly)
        {
            if (isForReturnedParametersOnly)
                return new ParameterBag();

            CorrelationOptions options = (CorrelationOptions)Definition.ChartOptions;
            double[] odr = options.Odr;
            double[] odrl = options.Odrl;
            double[] odru = options.Odru;
            CorrelationRowType[] pg = options.Pg;
            double[] gn = options.Gn;
            ScaleHeight(options.K);

            StartVectorPlot();

            int kok = 0;
            double ormax = double.NegativeInfinity;
            double ormin = double.PositiveInfinity;
            double orumax = double.NegativeInfinity;
            double orlmin = double.PositiveInfinity;
            double maxGn = double.NegativeInfinity;

            switch (options.Xform)
            {
                case Transformation.Log:
                    {
                        for (int i = 1; i <= options.K; i++)
                        {
                            if (pg[i] == CorrelationRowType.Study)
                            {
                                if (gn[i] != Constant.MISSING && gn[i] > maxGn)
                                    maxGn = gn[i];
                            }
                            if (odr[i] != Constant.MISSING && !double.IsInfinity(odr[i]))
                            {
                                kok += 1;
                                if (odr[i] > ormax)
                                    ormax = odr[i];
                                if (odr[i] < ormin && odr[i] > 0)
                                    ormin = odr[i];
                                if (odrl[i] > odru[i])
                                {
                                    double tmp = odrl[i];
                                    odrl[i] = odru[i];
                                    odru[i] = tmp;
                                }
                                if (odrl[i] < orlmin && odrl[i] > 0 && !double.IsInfinity(odrl[i]) && odrl[i] != Constant.MISSING)
                                    orlmin = odrl[i];
                                if (odru[i] > orumax && !double.IsInfinity(odru[i]) && odru[i] != Constant.MISSING)
                                    orumax = odru[i];
                            }
                        }
                    }
                    break;
                case Transformation.Z:
                    {
                        for (int i = 1; i <= options.K; i++)
                        {
                            if (pg[i] == CorrelationRowType.Study)
                            {
                                if (gn[i] != Constant.MISSING & gn[i] > maxGn)
                                    maxGn = gn[i];
                            }
                            if (odr[i] != Constant.MISSING)
                            {
                                kok += 1;
                                if (odr[i] > ormax)
                                    ormax = odr[i];
                                if (odr[i] < ormin && odr[i] > 0)
                                    ormin = odr[i];
                                if (odrl[i] > odru[i])
                                {
                                    double tmp = odrl[i];
                                    odrl[i] = odru[i];
                                    odru[i] = tmp;
                                }
                                if (odrl[i] < orlmin && odrl[i] > 0)
                                    orlmin = odrl[i];
                                if (odru[i] > orumax)
                                    orumax = odru[i];
                            }
                        }
                    }
                    break;
                case Transformation.None:
                    for (int i = 1; i <= options.K; i++)
                    {
                        if (pg[i] == CorrelationRowType.Study)
                        {
                            if (gn[i] != Constant.MISSING && gn[i] > maxGn)
                                maxGn = gn[i];
                        }
                        if (odr[i] != Constant.MISSING)
                        {
                            kok += 1;
                            if (odr[i] > ormax)
                                ormax = odr[i];
                            if (odr[i] < ormin)
                                ormin = odr[i];
                            if (odrl[i] > odru[i])
                            {
                                double tmp = odrl[i];
                                odrl[i] = odru[i];
                                odru[i] = tmp;
                            }
                            if (odrl[i] < orlmin)
                                orlmin = odrl[i];
                            if (odru[i] > orumax)
                                orumax = odru[i];
                        }
                    }
                    break;
            }

            double absmin = Constant.MISSING;
            for (int i = 1; i <= options.K; i++)
            {
                if (Math.Abs(odr[i]) < absmin & odr[i] != 0.0)
                    absmin = Math.Abs(odr[i]);
                if (Math.Abs(odrl[i]) < absmin & odrl[i] != 0.0)
                    absmin = Math.Abs(odrl[i]);
                if (Math.Abs(odru[i]) < absmin & odru[i] != 0.0)
                    absmin = Math.Abs(odru[i]);
            }

            DataMaxX = ormax;
            if (DataMaxX < orumax && orumax != Constant.MISSING)
                DataMaxX = orumax;
            DataMinX = ormin;
            if (DataMinX > orlmin && orlmin != Constant.MISSING)
                DataMinX = orlmin;
            DataMinGreaterThanZeroX = DataMinX;

            double rgap = 0;
            double xtra = 0;
            // allow room for right hand labels of effect and CI
            for (int i = 1; i <= options.K; i++)
            {
                if (odr[i] != Constant.MISSING)
                {
                    double w = LabelWidthInCanvasCoordinates(options.Titles[i]);
                    if (w > xtra)
                        xtra = w;
                    w = LabelWidthInCanvasCoordinates(Formatting.RoundMeta(odr[i], absmin) + " (" + Formatting.RoundMeta(odrl[i], absmin) + ", " + Formatting.RoundMeta(odru[i], absmin) + ")");
                    if (w > rgap)
                        rgap = w;
                }
            }

            AxisScales axisScales;
            switch (options.Xform)
            {
                case Transformation.Log:
                    axisScales = LayoutChartAndDrawAxes(options.Cap,
                        new AxisDefinition(null, AxisMode.Scale, ScaleType.Log10) { ExtraSpaceBeforeAxisStarts = xtra, ExtraSpaceAfterAxisEnds = rgap },
                        new AxisDefinition(null, AxisMode.None, ScaleType.Linear),
                        false, false);
                    break;
                default:
                    if (options.Cap.IndexOf("Correlation (", StringComparison.Ordinal) >= 0)
                    {
                        DataMinX = DataMinX >= 0.0 ? 0.0 : -1.0;
                        DataMaxX = DataMaxX <= 0.0 ? 0.0 : 1.0;
                    }
                    axisScales = LayoutChartAndDrawAxes(options.Cap,
                        new AxisDefinition(null, AxisMode.Scale, ScaleType.Linear) { ExtraSpaceBeforeAxisStarts = xtra, ExtraSpaceAfterAxisEnds = rgap },
                        new AxisDefinition(null, AxisMode.None, ScaleType.NotSet),
                        false, false);
                    DataMinX = axisScales.X.MinimumScaleValue;
                    DataMaxX = axisScales.X.MaximumScaleValue;
                    break;
            }

            axisScales.Y = new CategoryAxisScale(kok);
            DivY = kok;
            OffY = YAxisCanvas;

            MarkerType studyMarkerType = new()
            {
                MarkerColor = ColorDescriptor.Gray,
                LineColor = ColorDescriptor.Black,
                IsMarkerFilled = true,
                MarkerShape = MarkerShape.Square,
                LineDashStyle = DashStyleDescriptor.Solid,
                Width = 1
            };
            MarkerType pooledMarkerType = new()
            {
                MarkerColor = ColorDescriptor.Gray,
                LineColor = ColorDescriptor.Black,
                IsMarkerFilled = true,
                MarkerShape = MarkerShape.Diamond,
                LineDashStyle = DashStyleDescriptor.Solid,
                Width = 1
            };

            PenDescriptor linePen = GetLinePen(ChartPreferences.MarkerTypes[10], true);
            PenDescriptor pooledEffectPen = GetLinePen(ChartPreferences.MarkerTypes[10], false);
            PenDescriptor dotPen = GetMarkerPen(ChartPreferences.MarkerTypes[10]);
            {
                double rmh = -99;
                int r = 0;
                double txh = LabelHeightInCanvasCoordinates(options.Titles[1]);
                double botlim = double.NegativeInfinity;
                double yt = 0;
                for (int i = options.K; i >= 1; i--)
                {
                    if (odr[i] != Constant.MISSING)
                    {
                        r++;
                        double yctr = (r - 0.5) / DivY * YExtCanvas;
                        double ytop = r / DivY * YExtCanvas;
                        double xm = 0;
                        if (odr[i] < botlim)
                        {
                            xm = XAxisCanvas;
                        }
                        else
                        {
                            switch (options.Xform)
                            {
                                case Transformation.Z:
                                    xm = ToCanvasX(MathDbl.rtoz(odr[i]));
                                    break;
                                case Transformation.None:
                                case Transformation.Log:
                                    xm = ToCanvasX(odr[i]);
                                    break;
                            }

                        }
                        double xl = 0;
                        if (odrl[i] < botlim)
                        {
                            xl = XAxisCanvas;
                        }
                        else
                        {
                            switch (options.Xform)
                            {
                                case Transformation.Log:
                                    xl = ToCanvasX(odrl[i]);
                                    break;
                                case Transformation.Z:
                                    xl = ToCanvasX(MathDbl.rtoz(odrl[i]));
                                    break;
                                case Transformation.None:
                                    xl = ToCanvasX(Math.Max(odrl[i], options.IsDifference ? double.MinValue : -1));
                                    break;
                            }

                        }
                        double xr = 0;
                        switch (options.Xform)
                        {
                            case Transformation.Log:
                                xr = ToCanvasX(odru[i]);
                                break;
                            case Transformation.Z:
                                xr = ToCanvasX(MathDbl.rtoz(odru[i]));
                                break;
                            case Transformation.None:
                                xr = ToCanvasX(Math.Min(odru[i], options.IsDifference ? double.MaxValue : 1));
                                break;
                        }

                        double y2 = (ytop - yctr) / 1.5;
                        double yc = OffY + yctr;
                        yt = OffY + yctr + y2;
                        double yb = OffY + yctr - y2;
                        if (pg[i] == CorrelationRowType.Study)
                        {
                            // Weight blob.  Draw this first so that the line appears in front of it in the case of short lines (#994).
                            // #688: Make blob size proportional to sqrt(1/variance) rather than 1/variance
                            double blobSize = (5 + Math.Abs(yt - yb) * Math.Sqrt(gn[i] / maxGn)) * 0.7;
                            DrawMarkerInCanvasCoordinates(xm, yc, blobSize / 2, studyMarkerType);
                            // CI line
                            DrawLineInCanvasCoordinates(linePen, xl, yc, xr, yc);
                            // Arrow ends if not plottable
                            if (odrl[i] <= 0 && options.Xform == Transformation.Log || odrl[i] == Constant.MISSING)
                            {
                                DrawLineInCanvasCoordinates(linePen, xl + y2, yc + y2, xl, yc);
                                DrawLineInCanvasCoordinates(linePen, xl, yc, xl + y2, yc - y2);
                            }
                            if (odru[i] == Constant.MISSING)
                            {
                                DrawLineInCanvasCoordinates(linePen, xr - y2, yc + y2, xr, yc);
                                DrawLineInCanvasCoordinates(linePen, xr, yc, xr - y2, yb - y2);
                            }
                            // Centre mark.  Draw this last so that it appears in front of the line.  Always black.
                            DrawMarkerInCanvasCoordinates(xm, yc, 2, MarkerShape.Circle, true, dotPen);

                        }
                        else
                        {
                            DrawMarkerInCanvasCoordinates(xm, yc, y2, pooledMarkerType);
                            DrawLineInCanvasCoordinates(linePen, xr, yc, xl, yc);
                            if (pg[i] == CorrelationRowType.Pooled)
                            {
                                rmh = odr[i];
                                // pooled effect marker
                                DrawLineInCanvasCoordinates(pooledEffectPen, xm, yt, xm, ToCanvasY(options.K - 0.5));
                            }
                        }
                        DrawStringLabel(options.Titles[i], XAxisCanvas - 15, yc + txh / 2, StringAlignment.Far);
                        DrawStringLabel(Formatting.RoundMeta(odr[i], absmin) + " (" + Formatting.RoundMeta(odrl[i], absmin) + ", " + Formatting.RoundMeta(odru[i], absmin) + ")", XAxisCanvas + XExtCanvas + 10, yc + txh / 2, StringAlignment.Near);
                    }
                }

                double noEffectPosition = 0;
                switch (options.Xform)
                {
                    case Transformation.Z:
                        // Don't care
                        break;
                    case Transformation.Log:
                        noEffectPosition = 1;
                        break;
                    case Transformation.None:
                        noEffectPosition = 0;
                        break;
                }
                if (DataMinX <= noEffectPosition && options.Xform != Transformation.Z)
                {
                    // no effect marker
                    double xm;
                    switch (options.Xform)
                    {
                        case Transformation.Z:
                            throw new Exception("Shouldn't be plotting no effect marker with a correlation plot");
                        default:
                            xm = ToCanvasX(noEffectPosition);
                            break;
                    }
                    DrawLineInCanvasCoordinates(linePen, xm, yt, xm, YAxisCanvas);
                }

                if (rmh != -99)
                {
                    string buf = options.Qid;
                    DrawStringLabel(buf, XAxisCanvas + XExtCanvas / 2, 50, StringAlignment.Center);
                }
            }

            EndVectorPlot();
            return new ParameterBag();
        }
    }
}
