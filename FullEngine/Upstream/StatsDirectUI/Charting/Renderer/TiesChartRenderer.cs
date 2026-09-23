using StatsDirect.Templates;
using StatsDirect.Utilities;
using System.Drawing;

namespace StatsDirect.Charting.Renderer
{
    class TiesChartRenderer : AbstractChartRenderer, IChartRenderer
    {
        public TiesChartRenderer(ChartDefinition definition, ICanvasFactory canvasFactory)
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

            TiesOptions options = (TiesOptions)Definition.ChartOptions;
            DataMinX = options.x[1];
            DataMaxX = options.x[1];
            DataMinY = options.y[1];
            DataMaxY = options.y[1];
            for (int j = 2; j <= options.nx; j++)
            {
                if (options.x[j] > DataMaxX)
                    DataMaxX = options.x[j];
                if (options.y[j] > DataMaxY)
                    DataMaxY = options.y[j];
                if (options.x[j] < DataMinX)
                    DataMinX = options.x[j];
                if (options.y[j] < DataMinY)
                    DataMinY = options.y[j];
            }
            if (options.lla < DataMinY)
                DataMinY = options.lla;
            if (options.ula > DataMaxY)
                DataMaxY = options.ula;
            // Draw the scale
            string xtxt = "Mean ((" + options.v0Title + " + " + options.v1Title + ") / 2)";
            string ytxt = "Difference (" + options.v0Title + " - " + options.v1Title + ")";
            StartVectorPlot();
            LayoutChartAndDrawAxes(string.Empty,
                new AxisDefinition(xtxt, AxisMode.Scale, ScaleType.Linear),
                new AxisDefinition(ytxt, AxisMode.Scale, ScaleType.Linear),
                false, false);

            // Draw the titles
            double size2 = LabelHeightInCanvasCoordinates("M") * 2;
            DrawStringLegend("mean difference \u00B1 " + Formatting.XRound(options.gamma * 100.0, 2) + "% limits of agreement", XAxisCanvas + XExtCanvas, YAxisCanvas + YExtCanvas + size2, StringAlignment.Far);

            // Draw the limits
            double x1 = XAxisCanvas + XExtCanvas;
            double y1 = ToCanvasY(options.ula);
            PenDescriptor redPen = new(GrRed);
            PenDescriptor blackPen = new(GrBlack);
            DrawLineInCanvasCoordinates(redPen, XAxisCanvas, y1, x1, y1);
            y1 = ToCanvasY(options.lla);
            DrawLineInCanvasCoordinates(redPen, XAxisCanvas, y1, x1, y1);
            y1 = ToCanvasY(options.mean);
            DrawLineInCanvasCoordinates(blackPen, XAxisCanvas, y1, x1, y1);
            // Work through the rows
            for (int r = 1; r <= options.nx; r++)
                DrawMarkerInChartCoordinates(options.x[r], options.y[r], 6, ChartPreferences.MarkerTypes[0]);
            EndVectorPlot();
            return new ParameterBag();
        }
    }
}
