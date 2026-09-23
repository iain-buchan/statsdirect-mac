using StatsDirect.Charting.Scales;
using StatsDirect.Numerics;
using StatsDirect.Templates;
using StatsDirect.Utilities;
using System;

namespace StatsDirect.Charting.Renderer
{
    class MHRDChartRenderer : AbstractForestishChartRenderer, IChartRenderer
    {
        public MHRDChartRenderer(ChartDefinition definition, ICanvasFactory canvasFactory)
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

            MHOptions options = (MHOptions)Definition.ChartOptions;
            ScaleHeight(options.k);

            double[] gw = new double[options.k + 1];
            double orMax = double.NegativeInfinity;
            double orMin = double.PositiveInfinity;
            double oruMax = double.NegativeInfinity;
            double orlMin = double.PositiveInfinity;
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
                if (options.OddsRatios[i] != Constant.MISSING)
                {
                    if (options.OddsRatios[i] > orMax)
                        orMax = options.OddsRatios[i];
                    if (options.OddsRatios[i] < orMin)
                        orMin = options.OddsRatios[i];
                    if (options.OddsRatioLcis[i] < orlMin && options.OddsRatioLcis[i] != Constant.MISSING)
                        orlMin = options.OddsRatioLcis[i];
                    if (options.OddsRatioUcis[i] > oruMax && options.OddsRatioUcis[i] != Constant.MISSING)
                        oruMax = options.OddsRatioUcis[i];
                    if (Math.Abs(options.OddsRatios[i]) < absMin && options.OddsRatios[i] != 0.0)
                        absMin = Math.Abs(options.OddsRatios[i]);
                    if (Math.Abs(options.OddsRatioLcis[i]) < absMin && options.OddsRatioLcis[i] != 0.0 && options.OddsRatioLcis[i] != Constant.MISSING)
                        absMin = Math.Abs(options.OddsRatioLcis[i]);
                    if (Math.Abs(options.OddsRatioUcis[i]) < absMin && options.OddsRatioUcis[i] != 0.0 && options.OddsRatioUcis[i] != Constant.MISSING)
                        absMin = Math.Abs(options.OddsRatioUcis[i]);
                }
            }

            DataMaxX = MaxIgnoringMissingAndInfinities(orMax, options.rmh, options.ul, oruMax);
            DataMinX = MinIgnoringMissingAndInfinities(orMin, options.rmh, options.ll, orlMin);

            StartVectorPlot();

            ILinearAxisScale axisScale = (ILinearAxisScale)AxisScalerFactory.AxisScalerFor(ScaleType.Linear).QAxis(DataMinX, 0, DataMaxX, false, false);
            DataMinX = axisScale.MinimumScaleValue;
            DataMaxX = axisScale.MaximumScaleValue;

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
                new AxisDefinition(null, AxisMode.None, ScaleType.Linear),
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
                if (options.OddsRatios[i] != Constant.MISSING)
                {
                    double xm = options.OddsRatios[i] < axisScales.X.MinimumScaleValue
                        ? axisScales.X.MinimumScaleValue
                        : options.OddsRatios[i];
                    double xl = options.OddsRatioLcis[i] < axisScales.X.MinimumScaleValue || options.OddsRatioLcis[i] == Constant.MISSING || double.IsInfinity(options.OddsRatioLcis[i])
                        ? axisScales.X.MinimumScaleValue
                        : options.OddsRatioLcis[i];
                    double xr = options.OddsRatioUcis[i] == Constant.MISSING || double.IsInfinity(options.OddsRatioUcis[i])
                        ? axisScales.X.MaximumScaleValue
                        : options.OddsRatioUcis[i] <= axisScales.X.MinimumScaleValue
                            ? axisScales.X.MinimumScaleValue
                            : options.OddsRatioUcis[i];

                    DrawRowInChartCoordinates(options.Titles[i], options.OddsRatios[i], options.OddsRatioLcis[i], options.OddsRatioUcis[i], gw[i] / maxGw, absMin, yc, xm, xl, xr, options.lerr[i], options.uerr[i], options.MarkCentres);
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
