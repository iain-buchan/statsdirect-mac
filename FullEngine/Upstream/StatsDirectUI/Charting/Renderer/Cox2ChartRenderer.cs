using Layout;
using StatsDirect.Numerics;
using StatsDirect.Templates;
using System;
using System.Drawing;

namespace StatsDirect.Charting.Renderer
{
    class Cox2ChartRenderer : AbstractChartRenderer, IChartRenderer
    {
        public Cox2ChartRenderer(ChartDefinition definition, ICanvasFactory canvasFactory)
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

            Cox2Options options = (Cox2Options)Definition.ChartOptions;
            Legend legend = new();
            for (int i = 1; i <= options.igroups; i++)
            {
                MarkerType mt = new() { MarkerShape = (MarkerShape)i, MarkerColor = GrBlack, MarkerSize = 6 };
                string vq = options.cdat1[options.groupid].Title[..Math.Min(20, options.cdat1[options.groupid].Title.Length)] + "=" + options.cdat1[options.groupid].Groups[i - 1].Label;
                legend.LegendEntries.Add(new LegendEntry { Label = vq, MarkerType = mt });
            }

            Layout.Range xRange = GetMinMaxArray(options.xp, Definition.ScaleParameters.X.ScaleType);
            Layout.Range yRange = GetMinMaxArray(options.yp, Definition.ScaleParameters.Y.ScaleType);
            DataMinX = xRange.Min;
            DataMaxX = xRange.Max;
            DataMinY = yRange.Min;
            DataMaxY = yRange.Max;

            StartVectorPlot(null, legend);

            //  TODO: Log and log-log axes here
            LayoutChartAndDrawAxes("Log-log plot (parallel groups if hazards proportional)",
                new AxisDefinition("log(Time)", AxisMode.Scale, ScaleType.Linear),
                new AxisDefinition("-log(-log(Survival))", AxisMode.Scale, ScaleType.Linear),
                false, false,
                legend);

            PenDescriptor p = new(GrBlack, 1);
            int istart = 0;
            for (int k = 1; k <= 2; k++)
            {
                PointF[] xys = new PointF[options.gn[k] + 1];
                xys[0].X = -1;
                xys[0].Y = -1;
                for (int i = 1; i <= options.gn[k]; i++)
                {
                    if (options.xp[istart + i] != Constant.MISSING && options.yp[istart + i] != Constant.MISSING)
                    {
                        xys[i].X = (float)ToCanvasX(options.xp[istart + i]);
                        xys[i].Y = (float)ToCanvasY(options.yp[istart + i]);
                    }
                    else
                    {
                        xys[i].X = -1;
                        xys[i].Y = -1;
                    }
                }
                DrawMarkerSeriesInCanvasCoordinates(xys, 6, (MarkerShape)k, false, p, p, true, true);
                istart += options.gn[k];
            }
            DrawLegend(legend);
            EndVectorPlot();
            return new ParameterBag();
        }
    }
}
