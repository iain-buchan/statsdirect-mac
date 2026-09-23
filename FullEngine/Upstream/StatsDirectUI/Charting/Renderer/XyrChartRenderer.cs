using StatsDirect.Numerics;
using StatsDirect.Templates;
using System.Drawing;

namespace StatsDirect.Charting.Renderer
{
    class XyrChartRenderer : AbstractChartRenderer, IChartRenderer
    {
        public XyrChartRenderer(ChartDefinition definition, ICanvasFactory canvasFactory)
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

            XyrOptions options = (XyrOptions)Definition.ChartOptions;
            DataMinX = options.minMax.MinX;
            DataMaxX = options.minMax.MaxX;
            DataMinY = options.minMax.MinY;
            DataMaxY = options.minMax.MaxY;

            Legend legend = null;
            if (options.ng > 1)
            {
                legend = new Legend();
                for (int g = 1; g <= options.ng; g++)
                {
                    MarkerType mt = ChartPreferences.MarkerTypes[ChartOptions.SeriesNumberToMarkerNumber(g - 1)];
                    legend.LegendEntries.Add(new LegendEntry { Label = options.bnam[g], MarkerType = mt });
                }
            }

            StartVectorPlot(null, legend);
            LayoutChartAndDrawAxes(options.Title,
                new AxisDefinition(options.XAxisTitle, AxisMode.Scale, ScaleType.Linear),
                new AxisDefinition(options.YAxisTitle, AxisMode.Scale, ScaleType.Linear),
                false, false,
                legend);

            // Plot the points
            for (int g = 1; g <= options.ng; g++)
            {
                int mkr = ChartOptions.SeriesNumberToMarkerNumber(g - 1);
                MarkerType t = ChartPreferences.MarkerTypes[mkr];
                PenDescriptor p = GetMarkerPen(t);
                double minx = double.MaxValue;
                double maxx = double.MinValue;
                double miny = double.MaxValue;
                double maxy = double.MinValue;
                double x1;
                double y1;
                for (int r = 1; r <= options.gn[g]; r++)
                {
                    PointF[] xys = new PointF[options.nr[g, r]];
                    for (int k = 1; k <= options.nr[g, r]; k++)
                    {
                        if (options.x[g, r] != Constant.MISSING)
                        {
                            x1 = ToCanvasX(options.x[g, r]);
                            if (options.x[g, r] > maxx)
                                maxx = options.x[g, r];
                            if (options.x[g, r] < minx)
                                minx = options.x[g, r];
                            if (options.y[g, r, k] != Constant.MISSING)
                            {
                                y1 = ToCanvasY(options.y[g, r, k]);
                                if (options.y[g, r, k] > maxy)
                                    maxy = options.y[g, r, k];
                                if (options.y[g, r, k] < miny)
                                    miny = options.y[g, r, k];
                                xys[k - 1].X = (float)x1;
                                xys[k - 1].Y = (float)y1;
                            }
                            else
                            {
                                xys[k - 1].X = -1;
                                xys[k - 1].Y = -1;
                            }
                        }
                        else
                        {
                            xys[k - 1].X = -1;
                            xys[k - 1].Y = -1;
                        }
                    }
                    DrawMarkerSeriesInCanvasCoordinates(xys, 6, t.MarkerShape, t.IsMarkerFilled, p, p, false, true);
                }
                x1 = ToCanvasX(minx);
                double calcy = options.a[g] + options.b[g] * minx;
                if (calcy < miny)
                {
                    calcy = miny;
                    if (options.b[g] != 0.0)
                        x1 = ToCanvasX((calcy - options.a[g]) / options.b[g]);
                }
                else if (calcy > maxy)
                {
                    calcy = maxy;
                    if (options.b[g] != 0.0)
                        x1 = ToCanvasX((calcy - options.a[g]) / options.b[g]);
                }
                y1 = ToCanvasY(calcy);
                double x2 = ToCanvasX(maxx);
                calcy = options.a[g] + options.b[g] * maxx;
                if (calcy < miny)
                {
                    calcy = miny;
                    if (options.b[g] != 0.0)
                        x2 = ToCanvasX((calcy - options.a[g]) / options.b[g]);
                }
                else if (calcy > maxy)
                {
                    calcy = maxy;
                    if (options.b[g] != 0.0)
                        x2 = ToCanvasX((calcy - options.a[g]) / options.b[g]);
                }
                DrawLineInCanvasCoordinates(p, x1, y1, x2, ToCanvasY(calcy));
            }
            DrawLegend(legend);
            EndVectorPlot();
            return new ParameterBag();
        }
    }
}
