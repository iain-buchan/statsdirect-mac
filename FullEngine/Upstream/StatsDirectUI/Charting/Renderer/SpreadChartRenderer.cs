using System;
using System.Collections.Generic;
using Layout;
using StatsDirect.Templates;

namespace StatsDirect.Charting.Renderer
{
    internal class SpreadChartRenderer: AbstractChartRenderer, IChartRenderer
    {
        public SpreadChartRenderer(ChartDefinition definition, ICanvasFactory canvasFactory)
            : base(definition, canvasFactory)
        {
        }


        ScaleParameters IChartRenderer.GetScaleParameters()
        {
            IList<ISeries> seriesToUse = Definition.YSeries.Count > 0 ? Definition.YSeries : Definition.XSeries;
            Layout.Range xRange = GetMinMaxSort(seriesToUse);

            return new ScaleParameters
            {
                X = { AllowedScaleTypes = new[] { ScaleType.Linear }, Min = xRange.Min, MinGreaterThanZero = xRange.Min, Max = xRange.Max },
                Y = { AllowedScaleTypes = new[] { ScaleType.Category } }
            };
        }

        ParameterBag IChartRenderer.Plot(/* TODO: IPreferences*/ ITemplateHost _, bool isForReturnedParametersOnly)
        {
            if (isForReturnedParametersOnly)
                return new ParameterBag();

            SpreadOptions sOptions = (SpreadOptions)Definition.ChartOptions;
            if (sOptions.Orientation == ChartOrientation.Horizontal)
            {
                return PlotSpreadHorizontal();
            }
            if (Definition.XSeries.Count == 0 && Definition.YSeries.Count > 0)
            {
                Definition = Definition.Clone();
                Definition.SwapXAndYSeries();
                (Definition.ScaleParameters.Y, Definition.ScaleParameters.X) = (Definition.ScaleParameters.X, Definition.ScaleParameters.Y);
            }
            return PlotSpreadVertical();
        }

        private ParameterBag PlotSpreadHorizontal()
        {
            SpreadOptions sOptions = (SpreadOptions)Definition.ChartOptions;
            IList<ISeries> seriesToUse = Definition.YSeries.Count > 0 ? Definition.YSeries : Definition.XSeries;

            ScaleHeight(seriesToUse.Count);

            Layout.Range dataRangeX = GetMinMaxSort(seriesToUse);
            DataMinX = dataRangeX.Min;
            DataMaxX = dataRangeX.Max;

            StartVectorPlot(sOptions);
            AssignMarkersToSeries(sOptions);

            LayoutChartAndDrawAxes(sOptions.Title,
                new AxisDefinition(sOptions.XAxisTitle, AxisMode.Scale, Definition.ScaleParameters.X.ScaleType),
                new AxisDefinition(null, AxisMode.Series, Definition.ScaleParameters.Y.ScaleType) { Series = seriesToUse },
                sOptions.ShouldBoxAxes, false);

            double ygap = YExtCanvas / DivY;

            //  Work out what markers to use
            MarkerType mt = ChartPreferences.MarkerTypes[10]; // Default
            double diam = mt.MarkerSize;
            if (sOptions.MarkerTypes != null && sOptions.MarkerTypes.Count > 0)
            {
                diam = sOptions.MarkerTypes[0].MarkerSize;
                mt = sOptions.MarkerTypes[0];
            }

            double inc = 2 * diam;
            double xxwid = DivX / (XExtCanvas / inc);
            ygap -= diam * 2;

            for (int c = 0; c < seriesToUse.Count; c++)
            {
                DoubleSeries s = (DoubleSeries)seriesToUse[c];
                int maxcount = 0;
                int r;
                for (r = 0; r < s.Points; r++)
                {
                    double v1 = s.Data[r];
                    int r1;
                    for (r1 = r + 1; r1 < s.Points; r1++)
                    {
                        if (Math.Abs(v1 - s.Data[r1]) > xxwid)
                            break;
                    }
                    int count = r1 - r;
                    if (count > maxcount)
                        maxcount = count;
                }

                double scl;
                if (maxcount * inc > ygap)
                    scl = ygap / (maxcount * inc);
                else
                    scl = 1.0;
                // #1316: Plot labels are plotted top-down, data was plotted bottom-up.  Reverse the data so that the first series is at the top to match the labels.
                double yctr = ToCanvasY(seriesToUse.Count - c - 0.5);

                r = 0;
                while (r < s.Points)
                {
                    double v1 = s.Data[r];
                    int r1;
                    for (r1 = r + 1; r1 < s.Points; r1++)
                    {
                        if (Math.Abs(v1 - s.Data[r1]) > xxwid)
                            break;
                    }
                    // Plot r1-r markers
                    int count = r1 - r;
                    double y1 = yctr - scl * (count * diam + diam);
                    double lasty1 = 0;
                    for (int i = 1; i <= count; i++)
                    {
                        y1 += inc * scl;
                        if (Math.Abs(lasty1 - y1) > 2)
                        {
                            DrawMarkerInCanvasCoordinates(ToCanvasX(v1), y1, mt.MarkerSize, mt);
                            lasty1 = y1;
                        }
                    }
                    r = r1;
                }
            }
            EndVectorPlot();
            return new ParameterBag();
        }

        private ParameterBag PlotSpreadVertical()
        {
            SpreadOptions sOptions = (SpreadOptions)Definition.ChartOptions;
            IList<ISeries> seriesToUse = Definition.YSeries.Count > 0 ? Definition.YSeries : Definition.XSeries;

            ScaleWidth(seriesToUse.Count);

            Layout.Range dataRangeY = GetMinMaxSort(seriesToUse);
            DataMinY = dataRangeY.Min;
            DataMaxY = dataRangeY.Max;

            StartVectorPlot(sOptions);
            AssignMarkersToSeries(sOptions);

            //  TODO: Should we be using the X axis title for something that will be shown vertically?
            LayoutChartAndDrawAxes(sOptions.Title,
                new AxisDefinition(null, AxisMode.Series, Definition.ScaleParameters.X.ScaleType) { Series = seriesToUse },
                new AxisDefinition(sOptions.XAxisTitle, AxisMode.Scale, Definition.ScaleParameters.Y.ScaleType),
                sOptions.ShouldBoxAxes, false);
            double xgap = XExtCanvas / DivX;

            //  Work out what markers to use
            MarkerType mt = ChartPreferences.MarkerTypes[10]; //  Default
            double diam = mt.MarkerSize;
            if (sOptions.MarkerTypes != null && sOptions.MarkerTypes.Count > 0)
            {
                diam = sOptions.MarkerTypes[0].MarkerSize;
                mt = sOptions.MarkerTypes[0];
            }

            double inc = 2 * diam;
            double yywid = DivY / (YExtCanvas / inc);
            xgap -= diam * 2;

            for (int c = 0; c < seriesToUse.Count; c++)
            {
                DoubleSeries s = ((DoubleSeries)seriesToUse[c]);
                int maxcount = 0;
                int r;
                for (r = 0; r < s.Points; r++)
                {
                    double v1 = s.Data[r];
                    int r1;
                    for (r1 = r + 1; r1 < s.Points; r1++)
                    {
                        if (Math.Abs(v1 - s.Data[r1]) > yywid)
                            break;
                    }
                    int count = r1 - r;
                    if (count > maxcount)
                        maxcount = count;
                }

                double scl;
                if (maxcount * inc > xgap)
                    scl = xgap / (maxcount * inc);
                else
                    scl = 1.0;
                double xctr = ToCanvasX(c + 0.5);

                r = 0;
                while (r < s.Points)
                {
                    double v1 = s.Data[r];
                    int r1;
                    for (r1 = r + 1; r1 < s.Points; r1++)
                    {
                        if (Math.Abs(v1 - s.Data[r1]) > yywid)
                            break;
                    }
                    // Plot r1 - r markers
                    int count = r1 - r;
                    double x1 = xctr - scl * (count * diam + diam);
                    double lastx1 = 0;
                    for (int i = 1; i <= count; i++)
                    {
                        x1 += inc * scl;
                        if (Math.Abs(lastx1 - x1) > 2)
                        {
                            DrawMarkerInCanvasCoordinates(x1, ToCanvasY(v1), mt.MarkerSize, mt);
                            lastx1 = x1;
                        }
                    }
                    r = r1;
                }

            }
            EndVectorPlot();
            return new ParameterBag();
        }
    }
}
