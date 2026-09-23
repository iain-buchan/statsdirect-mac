using StatsDirect.Numerics;
using StatsDirect.Templates;
using System.Drawing;

namespace StatsDirect.Charting.Renderer
{
    class LadderChartRenderer : AbstractChartRenderer, IChartRenderer
    {
        public LadderChartRenderer(ChartDefinition definition, ICanvasFactory canvasFactory)
            : base(definition, canvasFactory)
        {
        }

        ScaleParameters IChartRenderer.GetScaleParameters()
        {
            return new ScaleParameters
            {
                X =
                {
                    AllowedScaleTypes = new[] { ScaleType.Category },
                    Max = 0,
                    Min = 0
                },
                Y =
                {
                    AllowedScaleTypes = new[] { ScaleType.Linear },
                    Max = DataMaxY,
                    Min = DataMinY
                }
            };
        }

        ParameterBag IChartRenderer.Plot(/* TODO: IPreferences*/ ITemplateHost _, bool isForReturnedParametersOnly)
        {
            if (isForReturnedParametersOnly)
                return new ParameterBag();

            // Get the plot title
            LadderOptions lOptions = (LadderOptions)Definition.ChartOptions;
            StartVectorPlot(lOptions);
            AssignMarkersToSeries(Definition.YSeries, lOptions);

            //  No need to calculate min/max values, as they've already been calculated as the series were added.
            //  We just need to set the neat scale.
            LayoutChartAndDrawAxes(lOptions.Title,
                new AxisDefinition(null, AxisMode.Series, Definition.ScaleParameters.X.ScaleType) { Series = Definition.YSeries },
                new AxisDefinition(lOptions.YAxisTitle, AxisMode.Scale, Definition.ScaleParameters.Y.ScaleType),
                lOptions.ShouldBoxAxes, false);
            double x1 = XAxisCanvas + XExtCanvas * 0.25;
            double x2 = XAxisCanvas + XExtCanvas * 0.75;

            // Plot the points & join the lines
            DoubleSeries s0 = (DoubleSeries)Definition.YSeries[0];
            DoubleSeries s1 = (DoubleSeries)Definition.YSeries[1];
            //  Points
            for (int r = 0; r < s0.Points; r++)
            {
                if (s0.Data[r] != Constant.MISSING && s1.Data[r] != Constant.MISSING)
                {
                    double y1 = ToCanvasY(s0.Data[r]);
                    double Y2 = ToCanvasY(s1.Data[r]);
                    DrawMarkerInCanvasCoordinates(x1, y1, s0.MarkerType.MarkerSize, s0);
                    DrawMarkerInCanvasCoordinates(x2, Y2, s1.MarkerType.MarkerSize, s1);
                }
            }
            //  Lines
            MarkerType rungMarkerType = ChartPreferences.MarkerTypes[10];
            if (lOptions.MarkerTypes != null && lOptions.MarkerTypes.Count >= 1 && lOptions.MarkerTypes[0] != null)
                rungMarkerType = lOptions.MarkerTypes[0];

            PenDescriptor rungPen = new(ColorDescriptor.Black, rungMarkerType.Width);
            rungPen.DashStyle = rungMarkerType.LineDashStyle;
            for (int r = 0; r < s0.Points; r++)
            {
                if (s0.Data[r] != Constant.MISSING && s1.Data[r] != Constant.MISSING)
                {
                    double y1 = ToCanvasY(s0.Data[r]);
                    double Y2 = ToCanvasY(s1.Data[r]);
                    DrawLineInCanvasCoordinates(rungPen, x1, y1, x2, Y2);
                }
            }
            EndVectorPlot();
            return new ParameterBag();
        }
    }
}
