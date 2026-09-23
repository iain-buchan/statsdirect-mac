using StatsDirect.Charting.Scales;
using StatsDirect.Numerics;
using StatsDirect.Templates;
using StatsDirect.Utilities;
using System;
using System.Drawing;

namespace StatsDirect.Charting.Renderer
{
    class EffectChartRenderer : AbstractChartRenderer, IChartRenderer
    {
        public EffectChartRenderer(ChartDefinition definition, ICanvasFactory canvasFactory)
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

        ParameterBag IChartRenderer.Plot(/* TODO: IPreferences*/ ITemplateHost host, bool isForReturnedParametersOnly)
        {
            if (isForReturnedParametersOnly)
                return new ParameterBag();

            EffectOptions options = (EffectOptions)Definition.ChartOptions;
            ScaleHeight(options.k);

            StartVectorPlot();

            double[] gn = new double[options.k + 1];
            int kok = 0;
            double ormax = double.NegativeInfinity;
            double ormin = double.PositiveInfinity;
            double orumax = double.NegativeInfinity;
            double orlmin = double.PositiveInfinity;
            double maxGn = double.NegativeInfinity;
            for (int i = 1; i <= options.k; i++)
            {
                gn[i] = options.ControlGroupSizes[i] + options.ExperimentGroupSizes[i];
                if (gn[i] > maxGn)
                    maxGn = gn[i];
                if (options.OddsRatios[i] != Constant.MISSING)
                {
                    kok += 1;
                    if (options.OddsRatios[i] > ormax)
                        ormax = options.OddsRatios[i];
                    if (options.OddsRatios[i] < ormin)
                        ormin = options.OddsRatios[i];
                    if (options.OddsRatioLcis[i] < orlmin)
                        orlmin = options.OddsRatioLcis[i];
                    if (options.OddsRatioUcis[i] > orumax)
                        orumax = options.OddsRatioUcis[i];
                }
            }

            DataMaxX = ormax;
            DataMinX = ormin;
            if (DataMaxX < options.rmh)
                DataMaxX = options.rmh;
            if (DataMaxX < options.ul && options.ul != Constant.MISSING)
                DataMaxX = options.ul;
            if (DataMaxX < orumax && orumax != Constant.MISSING)
                DataMaxX = orumax;
            if (DataMinX > options.rmh)
                DataMinX = options.rmh;
            if (DataMinX > options.ll && options.ll != Constant.MISSING)
                DataMinX = options.ll;
            if (DataMinX > orlmin && orlmin != Constant.MISSING)
                DataMinX = orlmin;

            IAxisScale xAxisScale = (ILinearAxisScale)AxisScalerFactory.AxisScalerFor(ScaleType.Linear).QAxis(DataMinX, 0, DataMaxX, false, false);
            DataMinX = xAxisScale.MinimumScaleValue;
            DataMaxX = xAxisScale.MaximumScaleValue;

            double xtra = 0;
            for (int i = 1; i <= options.k; i++)
            {
                if (options.OddsRatios[i] != Constant.MISSING)
                {
                    double w = LabelWidthInCanvasCoordinates(options.Titles[i]) + 30;
                    if (w > xtra + XAxisCanvas)
                        xtra = w - XAxisCanvas - 5;
                }
            }
            AxisScales axisScales = LayoutChartAndDrawAxes(options.cap,
                new AxisDefinition(null, AxisMode.Scale, ScaleType.Linear) { ExtraSpaceBeforeAxisStarts = xtra },
                new AxisDefinition(null, AxisMode.None, ScaleType.NotSet),
                false, false);
            axisScales.Y = new CategoryAxisScale(kok + options.pbias);
            DivY = kok + options.pbias;
            OffY = YAxisCanvas;

            PenDescriptor linePen = GetLinePen(ChartPreferences.MarkerTypes[10], true);
            double txh = LabelHeightInCanvasCoordinates(options.Titles[1]);
            int r = 0;
            double yc = 0;
            double yt = 0;
            for (int i = options.k; i >= 1; i--)
            {
                if (options.OddsRatios[i] != Constant.MISSING)
                {
                    r++;
                    double yctr = (r + options.pbias - 0.5) / DivY * YExtCanvas;
                    double ytop = (r + options.pbias) / DivY * YExtCanvas;
                    double xm = ToCanvasX(options.OddsRatios[i]);
                    double xl = ToCanvasX(options.OddsRatioLcis[i]);
                    double xr = ToCanvasX(options.OddsRatioUcis[i]);
                    double y2 = (ytop - yctr) / 1.5;
                    yc = OffY + yctr;
                    yt = OffY + yctr + y2;
                    double yb = OffY + yctr - y2;
                    // CI line
                    DrawLineInCanvasCoordinates(linePen, xl, yc, xr, yc);
                    // Weight blob
                    DrawSquareInCanvasCoordinates(linePen, xm, yc, (5 + Math.Abs(yt - yb) * (gn[i] / maxGn)) * 0.7, true);
                    DrawStringLabel(options.Titles[i], XAxisCanvas - 15, yc + txh / 2, StringAlignment.Far);
                }
            }

            if (DataMinX <= 0)
            {
                double xm = OffX;
                DrawLineInCanvasCoordinates(linePen, xm, yt, xm, YAxisCanvas - 12);
            }

            if (options.pbias == 1)
            {
                double saveYc = yc;
                double yctr = ToCanvasHeight(0.5);
                double diamondHalfSize = yctr / 1.5;
                yc = ToCanvasY(0.5);
                yt = OffY + yctr + diamondHalfSize;
                DrawDiamondInCanvasCoordinates(linePen, ToCanvasX(options.rmh), yc, diamondHalfSize * 2, false);
                DrawLineInCanvasCoordinates(linePen, ToCanvasX(options.ul), yc, ToCanvasX(options.ll), yc);
                // pooled effect marker
                PenDescriptor pooledEffectPen = GetLinePen(ChartPreferences.MarkerTypes[10], false);
                DrawLineInCanvasCoordinates(pooledEffectPen, ToCanvasX(options.rmh), saveYc, ToCanvasX(options.rmh), yt);
                string lab = "pooled " + options.qid + " = " + host.RoundU(options.rmh) + "  (" + Formatting.XRound(options.cco * 100, 1) + "% CI = " + host.RoundU(options.ll) + " to " + host.RoundU(options.ul) + ")";
                string xlab = options.cap.IndexOf("fixed", StringComparison.Ordinal) + 1 != 0 ? string.Empty : "DL ";
                lab = xlab + lab;
                DrawStringLabel(lab, XAxisCanvas + XExtCanvas / 2.0, 50, StringAlignment.Center);
            }
            EndVectorPlot();
            return new ParameterBag();
        }
    }
}
