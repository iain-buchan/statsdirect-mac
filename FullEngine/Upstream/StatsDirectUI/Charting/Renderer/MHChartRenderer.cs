using StatsDirect.Charting.Scales;
using StatsDirect.Numerics;
using StatsDirect.Templates;
using StatsDirect.Utilities;
using System;

namespace StatsDirect.Charting.Renderer
{
    class MHChartRenderer : AbstractForestishChartRenderer, IChartRenderer
    {
        public MHChartRenderer(ChartDefinition definition, ICanvasFactory canvasFactory)
            : base(definition, canvasFactory)
        {
        }

        ScaleParameters IChartRenderer.GetScaleParameters()
        {
            return new ScaleParameters
            {
                X = new AxisScaleParameters { ScaleType = ScaleType.Log10 },
                Y = new AxisScaleParameters { ScaleType = ScaleType.Linear }
            };
        }

        ParameterBag IChartRenderer.Plot(/* TODO: IPreferences*/ ITemplateHost _, bool isForReturnedParametersOnly)
        {
            if (isForReturnedParametersOnly)
                return new ParameterBag();

            MHOptions options = (MHOptions)Definition.ChartOptions;
            ScaleHeight(options.k);

            double[] gw = new double[options.LowerBound + options.k];
            double ormax = double.NegativeInfinity;
            double ormin = double.PositiveInfinity;
            double orumax = double.NegativeInfinity;
            double orlmin = double.PositiveInfinity;
            double maxGw = double.NegativeInfinity;
            double absMin = double.PositiveInfinity;
            for (int i = options.LowerBound; i < options.LowerBound + options.k; i++)
            {
                if (options.GroupSizes[i] != Constant.MISSING)
                {
                    if (options.GroupSizes[i] > maxGw)
                        maxGw = options.GroupSizes[i];
                    gw[i] = options.GroupSizes[i];
                }
                if (options.OddsRatios[i] != Constant.MISSING && Included(options, i) && !double.IsInfinity(options.OddsRatios[i]))
                {
                    if (options.OddsRatios[i] > ormax)
                        ormax = options.OddsRatios[i];
                    if (options.OddsRatioUcis[i] > orumax && options.OddsRatioUcis[i] != Constant.MISSING && !double.IsInfinity(options.OddsRatioUcis[i]))
                        orumax = options.OddsRatioUcis[i];
                    if (options.OddsRatioUcis[i] < orlmin && options.OddsRatioUcis[i] > 0 && options.OddsRatioUcis[i] != Constant.MISSING && !double.IsInfinity(options.OddsRatioUcis[i]))
                        orlmin = options.OddsRatioUcis[i];
                    if (options.OddsRatios[i] > 0)
                    {
                        if (options.OddsRatios[i] < ormin)
                            ormin = options.OddsRatios[i];
                        if (options.OddsRatioLcis[i] < orlmin && options.OddsRatioLcis[i] > 0 && options.OddsRatioLcis[i] != Constant.MISSING && !double.IsInfinity(options.OddsRatioLcis[i]))
                            orlmin = options.OddsRatioLcis[i];
                    }
                    if (Math.Abs(options.OddsRatios[i]) < absMin && options.OddsRatios[i] != 0.0)
                        absMin = Math.Abs(options.OddsRatios[i]);
                    if (Math.Abs(options.OddsRatioLcis[i]) < absMin && options.OddsRatioLcis[i] != 0.0 && options.OddsRatioLcis[i] != Constant.MISSING && !double.IsInfinity(options.OddsRatioLcis[i]))
                        absMin = Math.Abs(options.OddsRatioLcis[i]);
                    if (Math.Abs(options.OddsRatioUcis[i]) < absMin && options.OddsRatioUcis[i] != 0.0 && options.OddsRatioUcis[i] != Constant.MISSING && !double.IsInfinity(options.OddsRatioUcis[i]))
                        absMin = Math.Abs(options.OddsRatioUcis[i]);
                }
            }

            DataMinX = orlmin;
            DataMinGreaterThanZeroX = orlmin;
            DataMaxX = ormax;

            if (DataMaxX < options.rmh)
                DataMaxX = options.rmh;
            if (DataMaxX < options.ul && options.ul != Constant.MISSING && !double.IsInfinity(options.ul))
                DataMaxX = options.ul;
            if (DataMaxX < orumax && orumax != Constant.MISSING && !double.IsInfinity(orumax))
                DataMaxX = orumax;

            StartVectorPlot();
            double rgap = 0;
            double xtra = 0;
            // allow room for right hand labels of effect and CI
            double w = LegendWidthInCanvasCoordinates(ComboTi(options.cap)) + 30;
            if (w > xtra + XAxisCanvas)
                xtra = w - XAxisCanvas - AxisBigTick;
            for (int i = options.LowerBound; i < options.LowerBound + options.k; i++)
            {
                if (options.OddsRatios[i] != Constant.MISSING && !double.IsInfinity(options.OddsRatios[i]))
                {
                    w = LegendWidthInCanvasCoordinates(options.Titles[i]) + 30;
                    if (w > xtra + XAxisCanvas)
                        xtra = w - XAxisCanvas - AxisBigTick;
                    w = LegendWidthInCanvasCoordinates(RangeLabel(options.OddsRatios[i], options.OddsRatioLcis[i], options.OddsRatioUcis[i], absMin));
                    if (w > rgap)
                        rgap = w;
                }
            }
            AxisScales axisScales = LayoutChartAndDrawAxes(options.cap,
                new AxisDefinition(options.qid + " (" + Formatting.XRound(options.cco * 100, 1) + "% confidence interval" + ")", AxisMode.Scale, Definition.ScaleParameters.X.ScaleType) { ExtraSpaceBeforeAxisStarts = xtra, ExtraSpaceAfterAxisEnds = rgap },
                new AxisDefinition(null, AxisMode.None, ScaleType.Category),
                false, false);
            axisScales.Y = new CategoryAxisScale(options.k + options.pbias);
            DivY = options.k + options.pbias;
            OffY = YAxisCanvas;

            int r = 0;
            double yc = 0;
            for (int i = options.LowerBound + options.k - 1; i >= options.LowerBound; i--)
            {
                r++;
                yc = r + options.pbias - 0.5;
                if (options.OddsRatios[i] != Constant.MISSING && !double.IsInfinity(options.OddsRatios[i]) && Included(options, i))
                {
                    double xm = options.OddsRatios[i] <= 0 || options.OddsRatios[i] < axisScales.X.MinimumScaleValue
                        ? axisScales.X.MinimumScaleValue
                        : options.OddsRatios[i];
                    double xl = options.OddsRatioLcis[i] <= 0 || options.OddsRatioLcis[i] < axisScales.X.MinimumScaleValue || options.OddsRatioLcis[i] == Constant.MISSING || double.IsInfinity(options.OddsRatioLcis[i])
                        ? axisScales.X.MinimumScaleValue
                        : options.OddsRatioLcis[i];
                    double xr = options.OddsRatioUcis[i] == Constant.MISSING || double.IsInfinity(options.OddsRatioUcis[i])
                        ? axisScales.X.MaximumScaleValue
                        : options.OddsRatioUcis[i] <= axisScales.X.MinimumScaleValue
                            ? axisScales.X.MinimumScaleValue
                            : options.OddsRatioUcis[i];

                    bool arrowL = options.OddsRatioLcis[i] <= 0 || options.lerr[i] || options.OddsRatioLcis[i] < orlmin || options.OddsRatioLcis[i] == Constant.MISSING || double.IsInfinity(options.OddsRatioLcis[i]);
                    bool arrowU = options.uerr[i] || double.IsInfinity(options.OddsRatioUcis[i]) || options.OddsRatioUcis[i] == Constant.MISSING;
                    DrawRowInChartCoordinates(options.Titles[i], options.OddsRatios[i], options.OddsRatioLcis[i], options.OddsRatioUcis[i], gw[i] / maxGw, absMin, yc, xm, xl, xr, arrowL, arrowU, options.MarkCentres);
                }
                else
                {
                    DrawExcludedInChartCoordinates(options.Titles[i], yc);
                }
            }

            PlotNoEffectMarker(axisScales);

            if (options.pbias == 1)
                PlotPooledMarker(options.rmh, options.ll, options.ul, absMin, yc, options.cap);

            EndVectorPlot();
            return new ParameterBag();
        }
    }
}
