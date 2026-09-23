using StatsDirect.Numerics;
using StatsDirect.Templates;
using System;
using System.Drawing;

namespace StatsDirect.Charting.Renderer
{
    internal class ControlChartRenderer : AbstractChartRenderer, IChartRenderer
    {
        public ControlChartRenderer(ChartDefinition definition, ICanvasFactory canvasFactory)
            : base(definition, canvasFactory)
        {
        }

        ScaleParameters IChartRenderer.GetScaleParameters()
        {
            DoubleSeries ys0 = (DoubleSeries)Definition.YSeries[0];
            DoubleSeries xs0 = (DoubleSeries)Definition.XSeries[0];
            int rows = xs0.Points;
            double[] xdat = new double[rows + 1];
            double[] ydat = new double[rows + 1];

            int ctr = 0;
            bool looksLikeDates = true;
            double[] ySeriesData = ys0.Data;
            double[] xSeriesData = xs0.Data;
            for (int r = 0; r < rows; r++)
            {
                if (ySeriesData[r] != Constant.MISSING && xSeriesData[r] != Constant.MISSING)
                {
                    xdat[ctr] = xSeriesData[r];
                    ydat[ctr] = ySeriesData[r];
                    if (xdat[ctr] < 20000)
                        looksLikeDates = false;
                    ctr++;
                }
            }
            rows = ctr;

            MathDbl.MeanSD(ydat, ref rows, out double ymean, out double ysd);

            ControlOptions cOptions = (ControlOptions)Definition.ChartOptions;
            int kobs = cOptions.ObservationsToUse;
            if (cOptions.HasUserSpecifiedMeanAndSD)
            {
                ymean = cOptions.UserSpecifiedMean;
                ysd = cOptions.UserSpecifiedSD;
            }

            cOptions.HasUserSpecifiedLimits = cOptions.LowerWarningLimit != Constant.MISSING && cOptions.UpperWarningLimit != Constant.MISSING && cOptions.LowerControlLimit != Constant.MISSING && cOptions.UpperControlLimit != Constant.MISSING;
            if (cOptions.HasUserSpecifiedLimits)
            {
                if (cOptions.LowerControlLimit > cOptions.UpperControlLimit)
                {
                    double temp = cOptions.LowerControlLimit;
                    cOptions.LowerControlLimit = cOptions.UpperControlLimit;
                    cOptions.UpperControlLimit = temp;
                }
                if (cOptions.LowerWarningLimit > cOptions.UpperWarningLimit)
                {
                    double temp = cOptions.LowerWarningLimit;
                    cOptions.LowerWarningLimit = cOptions.UpperWarningLimit;
                    cOptions.UpperWarningLimit = temp;
                }
                if (cOptions.LowerControlLimit > cOptions.LowerWarningLimit)
                {
                    double temp = cOptions.LowerControlLimit;
                    cOptions.LowerControlLimit = cOptions.LowerWarningLimit;
                    cOptions.LowerWarningLimit = temp;
                }
                if (cOptions.UpperWarningLimit > cOptions.UpperControlLimit)
                {
                    double temp = cOptions.UpperControlLimit;
                    cOptions.UpperControlLimit = cOptions.UpperWarningLimit;
                    cOptions.UpperWarningLimit = temp;
                }
                if (DataMinY > cOptions.LowerControlLimit)
                    DataMinY = cOptions.LowerControlLimit;
                if (DataMaxY < cOptions.UpperControlLimit)
                    DataMaxY = cOptions.UpperControlLimit;
            }
            else
            {
                if (kobs != rows)
                {
                    MathDbl.MeanSD(ydat, ref kobs, out ymean, out ysd);
                }
                if (ysd != Constant.MISSING)
                {
                    if (DataMinY > ymean - ysd * 3.0)
                        DataMinY = ymean - ysd * 3.0;
                    if (DataMaxY < ymean + ysd * 3.0)
                        DataMaxY = ymean + ysd * 3.0;
                }
            }

            return new ScaleParameters
            {
                X =
                {
                    ScaleType = looksLikeDates ? ScaleType.Date : ScaleType.Linear,
                    AllowedScaleTypes = new[] { ScaleType.Linear, ScaleType.Date },
                    Max = DataMaxX,
                    Min = DataMinX
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
        ///  Plot a control chart.  Expects one X series and one Y series.
        ///  </summary>
        ParameterBag IChartRenderer.Plot(/* TODO: IPreferences*/ ITemplateHost _, bool isForReturnedParametersOnly)
        {
            if (isForReturnedParametersOnly)
                return new ParameterBag();

            DoubleSeries ys0 = (DoubleSeries)Definition.YSeries[0];
            DoubleSeries xs0 = (DoubleSeries)Definition.XSeries[0];
            int rows = xs0.Points;
            double[] xdat = new double[rows + 1];
            double[] ydat = new double[rows + 1];

            int ctr = 0;
            double[] ySeriesData = ys0.Data;
            double[] xSeriesData = xs0.Data;
            for (int r = 0; r < rows; r++)
            {
                if (ySeriesData[r] != Constant.MISSING && xSeriesData[r] != Constant.MISSING)
                {
                    xdat[ctr] = xSeriesData[r];
                    ydat[ctr] = ySeriesData[r];
                    ctr++;
                }
            }
            rows = ctr;

            MathDbl.MeanSD(ydat, ref rows, out double ymean, out double ysd);

            ControlOptions cOptions = (ControlOptions)Definition.ChartOptions;
            bool useDates = Definition.HasScaleParameters && Definition.ScaleParameters.X.ScaleType == ScaleType.Date;
            double oldymean = ymean;
            double oldysd = ysd;
            int kobs = cOptions.ObservationsToUse;
            if (cOptions.HasUserSpecifiedMeanAndSD)
            {
                ymean = cOptions.UserSpecifiedMean;
                ysd = cOptions.UserSpecifiedSD;
            }

            bool restricted = false; bool external = false;
            cOptions.HasUserSpecifiedLimits = cOptions.LowerWarningLimit != Constant.MISSING & cOptions.UpperWarningLimit != Constant.MISSING & cOptions.LowerControlLimit != Constant.MISSING & cOptions.UpperControlLimit != Constant.MISSING;
            if (cOptions.HasUserSpecifiedLimits)
            {
                external = true;
                if (cOptions.LowerControlLimit > cOptions.UpperControlLimit)
                {
                    double temp = cOptions.LowerControlLimit;
                    cOptions.LowerControlLimit = cOptions.UpperControlLimit;
                    cOptions.UpperControlLimit = temp;
                }
                if (cOptions.LowerWarningLimit > cOptions.UpperWarningLimit)
                {
                    double temp = cOptions.LowerWarningLimit;
                    cOptions.LowerWarningLimit = cOptions.UpperWarningLimit;
                    cOptions.UpperWarningLimit = temp;
                }
                if (cOptions.LowerControlLimit > cOptions.LowerWarningLimit)
                {
                    double temp = cOptions.LowerControlLimit;
                    cOptions.LowerControlLimit = cOptions.LowerWarningLimit;
                    cOptions.LowerWarningLimit = temp;
                }
                if (cOptions.UpperWarningLimit > cOptions.UpperControlLimit)
                {
                    double temp = cOptions.UpperControlLimit;
                    cOptions.UpperControlLimit = cOptions.UpperWarningLimit;
                    cOptions.UpperWarningLimit = temp;
                }
                if (DataMinY > cOptions.LowerControlLimit)
                    DataMinY = cOptions.LowerControlLimit;
                if (DataMaxY < cOptions.UpperControlLimit)
                    DataMaxY = cOptions.UpperControlLimit;
            }
            else
            {
                if (kobs != rows)
                {
                    MathDbl.MeanSD(ydat, ref kobs, out ymean, out ysd);
                    restricted = true;
                }
                else
                {
                    // restricted = false; 
                    external = oldymean != ymean || oldysd != ysd;
                }
                if (ysd != Constant.MISSING)
                {
                    if (DataMinY > ymean - ysd * 3.0)
                        DataMinY = ymean - ysd * 3.0;
                    if (DataMaxY < ymean + ysd * 3.0)
                        DataMaxY = ymean + ysd * 3.0;
                }
            }

            const int RHS_LABEL_GAP = 7;

            StartVectorPlot(cOptions);
            //  NB we use the Legend font as the Control Label font

            // Draw the scale
            AssignMarkersToSeries();

            // adjust drawing window for right hand labels and vertical date labels
            double rgap = 0;
            if (cOptions.UseMean || cOptions.Use1SD || cOptions.Use2SD || cOptions.Use3SD)
                rgap = RHS_LABEL_GAP + LegendWidthInCanvasCoordinates(Math.Round(ymean + ysd * 3.0, cOptions.RightHandDecimalPlaces) + " (+3 SD)");
            if (useDates)
            {
                double vshift = AxisLabelWidthInCanvasCoordinates(new DateTime(1899, 12, 30, 0, 0, 0).AddDays(xdat[0]).ToString("d")) + 30;
                YAxisCanvas += vshift;
                YExtCanvas -= vshift;
            }

            double xtra = 0;
            double w = TitleWidthInCanvasCoordinates(cOptions.YAxisTitle) + 30;
            if (w > xtra + XAxisCanvas)
                xtra = w - XAxisCanvas;

            XAxisCanvas += xtra;
            XExtCanvas -= xtra;

            // draw the axes
            LayoutChartAndDrawAxes(cOptions.Title,
                new AxisDefinition(cOptions.XAxisTitle, AxisMode.Scale, Definition.ScaleParameters.X.ScaleType) { ExtraSpaceAfterAxisEnds = rgap },
                new AxisDefinition(cOptions.YAxisTitle, AxisMode.Scale, Definition.ScaleParameters.Y.ScaleType),
                cOptions.ShouldBoxAxes, false);

            // plot points
            PointF[] xys = new PointF[rows];
            for (int r = 0; r < rows; r++)
            {
                if (xdat[r] != Constant.MISSING & ydat[r] != Constant.MISSING)
                {
                    xys[r].X = Convert.ToSingle(ToCanvasX(xdat[r]));
                    xys[r].Y = Convert.ToSingle(ToCanvasY(ydat[r]));
                }
                else
                {
                    xys[r].X = -1;
                    xys[r].Y = -1;
                }
            }

            PenDescriptor markerPen = GetMarkerPen(xs0.MarkerType);
            PenDescriptor linePen = GetLinePen(xs0.MarkerType, true);
            DrawMarkerSeriesInCanvasCoordinates(xys, 6, xs0.MarkerType.MarkerShape, xs0.MarkerType.IsMarkerFilled, markerPen, linePen, true, false);

            int rhDp = cOptions.RightHandDecimalPlaces;

            PenDescriptor blackPen = new(GrBlack);
            if (cOptions.HasUserSpecifiedLimits)
            {
                // user specified control and warning lines
                double x1 = XAxisCanvas + XExtCanvas;
                double y1 = ToCanvasY(cOptions.UpperWarningLimit);
                DrawLineInCanvasCoordinates(blackPen, XAxisCanvas, y1, x1, y1);
                DrawStringLegendLC(Math.Round(cOptions.UpperWarningLimit, rhDp) + " (warn)", x1 + RHS_LABEL_GAP, y1);
                y1 = ToCanvasY(cOptions.LowerWarningLimit);
                DrawLineInCanvasCoordinates(blackPen, XAxisCanvas, y1, x1, y1);
                DrawStringLegendLC(Math.Round(cOptions.LowerWarningLimit, rhDp) + " (warn)", x1 + RHS_LABEL_GAP, y1);
                PenDescriptor redPen = new(GrRed);
                {
                    y1 = ToCanvasY(cOptions.UpperControlLimit);
                    DrawLineInCanvasCoordinates(redPen, XAxisCanvas, y1, x1, y1);
                    DrawStringLegendLC(Math.Round(cOptions.UpperControlLimit, rhDp) + " (ctrl)", x1 + RHS_LABEL_GAP, y1);
                    y1 = ToCanvasY(ymean - ysd * 3.0);
                    DrawLineInCanvasCoordinates(redPen, XAxisCanvas, y1, x1, y1);
                    DrawStringLegendLC(Math.Round(cOptions.LowerControlLimit, rhDp) + " (ctrl)", x1 + RHS_LABEL_GAP, y1);
                    DrawStringLegendL("External:", x1 + RHS_LABEL_GAP, YAxisCanvas + YExtCanvas);
                }
            }
            else
            {
                // draw control lines
                if (cOptions.UseMean)
                {
                    double x1 = XAxisCanvas + XExtCanvas;
                    double y1 = ToCanvasY(ymean);
                    DrawLineInCanvasCoordinates(blackPen, XAxisCanvas, y1, x1, y1);
                    DrawStringLegendLC(Math.Round(ymean, rhDp) + " (mean)", x1 + RHS_LABEL_GAP, y1);
                    if (restricted)
                        DrawStringLegendL("On first " + kobs + " points:", x1 + RHS_LABEL_GAP, YAxisCanvas + YExtCanvas);
                    else if (external)
                        DrawStringLegendL("External:", x1 + RHS_LABEL_GAP, YAxisCanvas + YExtCanvas);
                }

                if (ysd != Constant.MISSING)
                {
                    if (cOptions.Use1SD)
                    {
                        PenDescriptor greenPen = new(GrGreen);
                        double x1 = XAxisCanvas + XExtCanvas;
                        double y1 = ToCanvasY(ymean + ysd);
                        DrawLineInCanvasCoordinates(greenPen, XAxisCanvas, y1, x1, y1);
                        DrawStringLegendLC(Math.Round(ymean + ysd, rhDp) + " (+1 SD)", x1 + RHS_LABEL_GAP, y1);
                        y1 = ToCanvasY(ymean - ysd);
                        DrawLineInCanvasCoordinates(greenPen, XAxisCanvas, y1, x1, y1);
                        DrawStringLegendLC(Math.Round(ymean - ysd, rhDp) + " (-1 SD)", x1 + RHS_LABEL_GAP, y1);
                    }

                    if (cOptions.Use2SD)
                    {
                        double x1 = XAxisCanvas + XExtCanvas;
                        double y1 = ToCanvasY(ymean + ysd * 2.0);
                        DrawLineInCanvasCoordinates(blackPen, XAxisCanvas, y1, x1, y1);
                        DrawStringLegendLC(Math.Round(ymean + ysd * 2.0, rhDp) + " (+2 SD)", x1 + RHS_LABEL_GAP, y1);
                        y1 = ToCanvasY(ymean - ysd * 2.0);
                        DrawLineInCanvasCoordinates(blackPen, XAxisCanvas, y1, x1, y1);
                        DrawStringLegendLC(Math.Round(ymean - ysd * 2.0, rhDp) + " (-2 SD)", x1 + RHS_LABEL_GAP, y1);
                    }

                    if (cOptions.Use3SD)
                    {
                        PenDescriptor redPen = new(GrRed);
                        double x1 = XAxisCanvas + XExtCanvas;
                        double y1 = ToCanvasY(ymean + ysd * 3.0);
                        DrawLineInCanvasCoordinates(redPen, XAxisCanvas, y1, x1, y1);
                        DrawStringLegendLC(Math.Round(ymean + ysd * 3.0, rhDp) + " (+3 SD)", x1 + RHS_LABEL_GAP, y1);
                        y1 = ToCanvasY(ymean - ysd * 3.0);
                        DrawLineInCanvasCoordinates(redPen, XAxisCanvas, y1, x1, y1);
                        DrawStringLegendLC(Math.Round(ymean - ysd * 3.0, rhDp) + " (-3 SD)", x1 + RHS_LABEL_GAP, y1);
                    }
                }
            }

            EndVectorPlot();
            return new ParameterBag();
        }
    }
}
