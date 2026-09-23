using Layout;
using StatsDirect.Charting.Scales;
using StatsDirect.Templates;
using StatsDirect.Utilities;

namespace StatsDirect.Charting.Renderer
{
    class AgreementPairChartRenderer : AbstractXYChartRenderer, IChartRenderer
    {
        public AgreementPairChartRenderer(ChartDefinition definition, ICanvasFactory canvasFactory)
            : base(definition, canvasFactory)
        {
        }

        ScaleParameters IChartRenderer.GetScaleParameters()
        {
            double avMin = 0;
            double avMax = 0;
            double mxdMin = 0;
            double mxdMax = 0;
            if (Definition?.ChartOptions != null)
            {
                AgreementOptions aOptions = (AgreementOptions)Definition.ChartOptions;
                Range mxdRange = GetMinMaxArray(aOptions.mxd, ScaleType.Linear);
                mxdMin = mxdRange.Min;
                mxdMax = mxdRange.Max;
                if (aOptions.HasLimits)
                {
                    if (aOptions.lla < mxdMin)
                        mxdMin = aOptions.lla;
                    if (aOptions.ula > mxdMax)
                        mxdMax = aOptions.ula;
                }
                Range avRange = GetMinMaxArray(aOptions.av, ScaleType.Linear);
                avMin = avRange.Min;
                avMax = avRange.Max;
            }

            return new ScaleParameters
            {
                X =
                {
                    ScaleType = ScaleType.Linear,
                    AllowedScaleTypes = new[] { ScaleType.Linear },
                    Max = avMax,
                    Min = avMin
                },
                Y =
                {
                    ScaleType = ScaleType.Linear,
                    AllowedScaleTypes = new[] { ScaleType.Linear },
                    Max = mxdMax,
                    Min = mxdMin
                }
            };
        }

        ParameterBag IChartRenderer.Plot(/* TODO: IPreferences*/ ITemplateHost _, bool isForReturnedParametersOnly)
        {
            if (isForReturnedParametersOnly)
                return new ParameterBag();

            AgreementOptions aOptions = (AgreementOptions)Definition.ChartOptions;
            StartVectorPlot(aOptions);
            Range mxdRange = GetMinMaxArray(aOptions.mxd, Definition.ScaleParameters.Y.ScaleType);
            double mxdMin = mxdRange.Min;
            double mxdMax = mxdRange.Max;
            AxisScales axisScales;
            PenDescriptor p = GetMarkerPen(ChartPreferences.MarkerTypes[0]);
            if (aOptions.HasLimits)
            {
                if (aOptions.lla < mxdMin)
                    mxdMin = aOptions.lla;
                if (aOptions.ula > mxdMax)
                    mxdMax = aOptions.ula;
                string xtxt = Definition.ChartOptions.XAxisTitle;
                if (string.IsNullOrEmpty(xtxt))
                    xtxt = "mean";
                string ytxt = Definition.ChartOptions.YAxisTitle;
                if (string.IsNullOrEmpty(ytxt))
                    ytxt = "difference";
                axisScales = PlotXYInternal(aOptions.av, aOptions.mxd, xtxt, ytxt, "Agreement Plot (" + Formatting.XRound(100 * (1 - aOptions.P0), 2) + "% limits of agreement)", false, DataMinMax.XCalc_YPreset, ChartPreferences.MarkerTypes[0].MarkerSize, ChartPreferences.MarkerTypes[0].MarkerShape, ChartPreferences.MarkerTypes[0].IsMarkerFilled, p, false, ChartAreaShape.Default, 0, 0, mxdMin, mxdMax);
            }
            else
            {
                string xtxt = Definition.ChartOptions.XAxisTitle;
                if (string.IsNullOrEmpty(xtxt))
                    xtxt = "mean";
                string ytxt = Definition.ChartOptions.YAxisTitle;
                if (string.IsNullOrEmpty(ytxt))
                    ytxt = "maximum difference";
                axisScales = PlotXYInternal(aOptions.av, aOptions.mxd, xtxt, ytxt, "Agreement Plot", false, DataMinMax.XCalc_YPreset, ChartPreferences.MarkerTypes[0].MarkerSize, ChartPreferences.MarkerTypes[0].MarkerShape, ChartPreferences.MarkerTypes[0].IsMarkerFilled, p, false, ChartAreaShape.Default, 0, 0, mxdMin, mxdMax);
            }

            // Plot mean
            PenDescriptor greenPen = new(GrGreen, 2);
            DrawLineInChartCoordinates(greenPen, axisScales.X.MinimumScaleValue, aOptions.mean, axisScales.X.MaximumScaleValue, aOptions.mean);
            if (aOptions.HasLimits)
            {
                // Plot upper limit
                DrawLineInChartCoordinates(greenPen, axisScales.X.MinimumScaleValue, aOptions.ula, axisScales.X.MaximumScaleValue, aOptions.ula);
                // Plot lower limit
                DrawLineInChartCoordinates(greenPen, axisScales.X.MinimumScaleValue, aOptions.lla, axisScales.X.MaximumScaleValue, aOptions.lla);
            }
            EndVectorPlot();
            return new ParameterBag();
        }
    }
}
