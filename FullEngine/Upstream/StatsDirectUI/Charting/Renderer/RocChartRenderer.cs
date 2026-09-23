using StatsDirect.Numerics;
using StatsDirect.Templates;
using StatsDirect.Utilities;
using System;
using System.Collections.Generic;
using System.Linq;

namespace StatsDirect.Charting.Renderer
{
    class RocChartRenderer : AbstractChartRenderer, IChartRenderer
    {
        public RocChartRenderer(ChartDefinition cd, ICanvasFactory canvasFactory)
            : base(cd, canvasFactory)
        {
        }

        ScaleParameters IChartRenderer.GetScaleParameters()
        {
            return new ScaleParameters
            {
                X =
                {
                    AllowedScaleTypes = new[] { ScaleType.Linear },
                    Max = 1,
                    Min = 0
                },
                Y =
                {
                    AllowedScaleTypes = new[] { ScaleType.Linear },
                    Max = 1,
                    Min = 0
                }
            };
        }

        ///  <summary>
        ///  Plot a ROC chart.
        ///  </summary>
        /// <param name="host"></param>
        ParameterBag IChartRenderer.Plot(ITemplateHost host, bool _)
        {
            ROCOptions rOptions = (ROCOptions)Definition.ChartOptions;
            double gamma = rOptions.GAMMA;
            if (gamma <= 0)
                return null;
            MathDbl.civ(0, out double cit, gamma, out double p0);

            //  Assume data passed as series - X is positive, Y is negative.

            IList<ROCSeriesRecord> seriesRecords = MakeAndMaybeAmendSeriesRecords(host, Definition);

            AssignMarkersToSeries(rOptions);
            Legend legend = new();
            for (int cs = 0; cs < Definition.XSeries.Count; cs++)
                legend.LegendEntries.Add(new LegendEntry { Label = rOptions.SeriesTitles[cs], MarkerType = ((DoubleSeries)Definition.YSeries[cs]).MarkerType });

            StartVectorPlot(rOptions, legend);

            DataMinX = 0;
            DataMaxX = 1;
            DataMinY = 0;
            DataMaxY = 1;

            // Draw the scale
            LayoutChartAndDrawAxes(rOptions.Title,
                new AxisDefinition("1-Specificity", AxisMode.Scale, ScaleType.Linear),
                new AxisDefinition("Sensitivity", AxisMode.Scale, ScaleType.Linear),
                true, false,
                legend, ChartAreaShape.Square);

            // null effect diagonal
            PenDescriptor tenPenDiagonal = new(ChartPreferences.MarkerTypes[10].LineColor, rOptions.AxisLineThickness);
            DrawLineInCanvasCoordinates(tenPenDiagonal, XAxisCanvas, YAxisCanvas, XAxisCanvas + XExtCanvas, YAxisCanvas + YExtCanvas);

            // get the offsets for the markers
            OffX = XAxisCanvas;
            OffY = YAxisCanvas;

            ParameterBag results = new();
            IList<ParameterBag> allResults = new List<ParameterBag>();
            results.AddOutput("*datasets", allResults);
            for (int cs = 0; cs < Definition.XSeries.Count; cs++)
            {
                ROCSeriesRecord seriesRecord = seriesRecords[cs];
                DoubleSeries xs = (DoubleSeries)Definition.XSeries[cs];
                DoubleSeries ys = (DoubleSeries)Definition.YSeries[cs];

                // make first mark
                double cutoff = seriesRecord.cutoff;
                int a = seriesRecord.pdata.Count(value => seriesRecord.comparisonFunction(value, cutoff));
                int c = seriesRecord.pdata.Length - a;
                int b = seriesRecord.adata.Count(value => seriesRecord.comparisonFunction(value, cutoff));
                int d = seriesRecord.adata.Length - b;
                double sens = a / (double)(a + c);
                double mspec = 1.0 - d / (double)(b + d);
                double x1 = OffX + mspec * XExtCanvas;
                double y1 = OffY + sens * YExtCanvas;

                int stps = seriesRecord.tdata.Length;
                double[] rx = new double[stps];
                double[] ry = new double[stps];

                for (int r = 0; r < stps; r++)
                {
                    cutoff = seriesRecord.tdata[r];
                    a = CountValuesSingleSided(seriesRecord.comparison, seriesRecord.pdata, cutoff);
                    c = seriesRecord.pdata.Length - a;
                    b = CountValuesSingleSided(seriesRecord.comparison, seriesRecord.adata, cutoff);
                    d = seriesRecord.adata.Length - b;
                    sens = a / (double)(a + c);
                    ry[r] = sens;
                    mspec = 1.0 - d / (double)(b + d);
                    rx[r] = mspec;
                }

                // Draw markers
                for (int r = 0; r < stps; r++)
                {
                    double x2 = OffX + rx[r] * XExtCanvas;
                    double y2 = OffY + ry[r] * YExtCanvas;
                    DrawMarkerInCanvasCoordinates(x2, y2, ys.MarkerType.MarkerSize, (DoubleSeries)Definition.YSeries[cs]);
                }

                // Draw lines between markers
                double lastX2 = x1;
                double lastY2 = y1;
                PenDescriptor linePen = GetLinePen(xs.MarkerType, false);
                for (int r = 0; r < stps; r++)
                {
                    double x2 = OffX + rx[r] * XExtCanvas;
                    double y2 = OffY + ry[r] * YExtCanvas;
                    if (r > 0 && (x2 != lastX2 || y2 != lastY2))
                        DrawLineInCanvasCoordinates(linePen, lastX2, lastY2, x2, y2);
                    lastX2 = x2;
                    lastY2 = y2;
                }

                // Mark cutoff point.  This is reversed if the chart requires reversal.
                double x = 1.0 - seriesRecord.spec;
                double y = seriesRecord.sens;
                if (seriesRecord.comparison == Comparison.LessThan || seriesRecord.comparison == Comparison.LessEqual)
                {
                    x = 1.0 - x;
                    y = 1.0 - y;
                }
                DrawMarkerInChartCoordinates(x, y, rOptions.MarkerTypes[Definition.XSeries.Count + cs].MarkerSize, rOptions.MarkerTypes[Definition.XSeries.Count + cs]);

                seriesRecord.auc = MathDbl.trapezoid_xy_roc(rx, ry, 0, stps);

                if (rOptions.ShowOptimumCutOff)
                {
                    ParameterBag thisResults = new();
                    allResults.Add(thisResults);
                    // Wilcoxon estimate for AUC
                    // Hanley JA, mcNeil BJ, Radiology 143:29-36
                    // Note that mwx and mwr are 1-based
                    double[] mwx = new double[seriesRecord.pdata.Length + seriesRecord.adata.Length + 1];
                    Array.Copy(seriesRecord.pdata, 0, mwx, 1, seriesRecord.pdata.Length);
                    Array.Copy(seriesRecord.adata, 0, mwx, 1 + seriesRecord.pdata.Length, seriesRecord.adata.Length);
                    NonParametric.MannWhitneyUTest(mwx, mwx.Length - 1, seriesRecord.pdata.Length, seriesRecord.adata.Length, out double[] _, out double u, out double _, out double _, out double _, out bool fault);
                    double theta;
                    double ll;
                    double ul;
                    double sew = 0;
                    if (fault)
                    {
                        theta = Constant.MISSING;
                        ll = Constant.MISSING;
                        ul = Constant.MISSING;
                    }
                    else
                    {
                        theta = u / (seriesRecord.pdata.Length * seriesRecord.adata.Length);
                        sew = DeLongSE(seriesRecord.pdata, seriesRecord.adata, theta);
                        if (sew == Constant.MISSING)
                        {
                            ll = Constant.MISSING;
                            ul = Constant.MISSING;
                        }
                        else
                        {
                            ll = theta - cit * sew;
                            ul = theta + cit * sew;
                        }
                    }
                    // end of Wilcoxon estimate
                    thisResults.AddOutput("ti", rOptions.SeriesTitles[cs]);
                    thisResults.AddOutput("auc", seriesRecord.auc);
                    thisResults.AddOutput("theta", theta);
                    thisResults.AddOutput("se", sew);
                    thisResults.AddOutput("pc", 100.0 * (1.0 - p0));
                    if (ll < 0.0)
                        ll = 0.0;
                    thisResults.AddOutput("ll", ll);
                    if (ul > 1.0)
                        ul = 1.0;
                    thisResults.AddOutput("ul", ul);
                    thisResults.AddOutput("cut", seriesRecord.cutoff);
                    thisResults.AddOutput("a", seriesRecord.a);
                    thisResults.AddOutput("b", seriesRecord.b);
                    thisResults.AddOutput("c", seriesRecord.c);
                    thisResults.AddOutput("d", seriesRecord.d);
                    // sensitivity CI
                    MathDbl.binci(seriesRecord.a, seriesRecord.a + seriesRecord.c, out ll, out ul, gamma, out string warn);
                    thisResults.AddOutput("senspc", 100.0 * (1.0 - p0));
                    thisResults.AddOutput("sens", seriesRecord.sens);
                    thisResults.AddOutput("sensll", ll);
                    thisResults.AddOutput("sensul", ul);
                    thisResults.AddOutput("senswarn", warn);
                    // specificity CI
                    MathDbl.binci(seriesRecord.d, seriesRecord.d + seriesRecord.b, out ll, out ul, gamma, out warn);
                    thisResults.AddOutput("specpc", 100.0 * (1.0 - p0));
                    thisResults.AddOutput("spec", seriesRecord.spec);
                    thisResults.AddOutput("specll", ll);
                    thisResults.AddOutput("specul", ul);
                    thisResults.AddOutput("specwarn", warn);

                    //  BEWARE from this point on: a, b, c, d are integer, but divisions need to deal with floating-point.
                    // prevalence
                    double n = seriesRecord.a + seriesRecord.b + seriesRecord.c + seriesRecord.d;
                    double prevel = (seriesRecord.a + seriesRecord.c) / n;

                    // ppv
                    double ptld;
                    double temp1; double temp2;
                    if (seriesRecord.a + seriesRecord.b > 0)
                    {
                        ptld = seriesRecord.a / Convert.ToDouble(seriesRecord.a + seriesRecord.b);
                        temp1 = ptld * 100.0;
                        temp2 = Convert.ToInt64(ptld * 100.0) - Convert.ToInt64(prevel * 100.0);
                    }
                    else
                    {
                        ptld = Constant.MISSING;
                        temp1 = Constant.MISSING;
                        temp2 = Constant.MISSING;
                    }
                    thisResults.AddOutput("likely", ptld);
                    // Clopper-Pearson CI
                    MathDbl.binci(seriesRecord.a, seriesRecord.a + seriesRecord.b, out double pil, out double piu, gamma, out warn);
                    thisResults.AddOutput("likely_from", pil);
                    thisResults.AddOutput("likely_to", piu);
                    thisResults.AddOutput("likely_warn", warn);
                    // as percentage
                    thisResults.AddOutput("likely_pc", temp1);
                    thisResults.AddOutput("likely_from_pc", pil != Constant.MISSING ? 100.0 * pil : Constant.MISSING);
                    thisResults.AddOutput("likely_to_pc", piu != Constant.MISSING ? 100.0 * piu : Constant.MISSING);
                    // change
                    thisResults.AddOutput("likely_change", temp2);

                    // npv
                    double ptlng;
                    if (seriesRecord.d + seriesRecord.c > 0)
                    {
                        ptlng = seriesRecord.d / (double)(seriesRecord.d + seriesRecord.c);
                        temp1 = ptlng * 100.0;
                        temp2 = Convert.ToInt32(ptlng * 100.0) - Convert.ToInt32((seriesRecord.b + seriesRecord.d) / n * 100.0);
                    }
                    else
                    {
                        ptlng = Constant.MISSING;
                        temp1 = Constant.MISSING;
                        temp2 = Constant.MISSING;
                    }
                    thisResults.AddOutput("likely_negative", ptlng);
                    // Clopper-Pearson CI
                    MathDbl.binci(seriesRecord.d, seriesRecord.d + seriesRecord.c, out pil, out piu, gamma, out warn);
                    thisResults.AddOutput("likely_negative_from", pil);
                    thisResults.AddOutput("likely_negative_to", piu);
                    thisResults.AddOutput("likely_negative_warn", warn);
                    // as percentage
                    thisResults.AddOutput("likely_negative_pc", temp1);
                    thisResults.AddOutput("likely_negative_from_pc", pil != Constant.MISSING ? 100.0 * pil : Constant.MISSING);
                    thisResults.AddOutput("likely_negative_to_pc", piu != Constant.MISSING ? 100.0 * piu : Constant.MISSING);
                    // change
                    thisResults.AddOutput("likely_negative_change", temp2);

                    // p[dx] despite -ve test
                    double ptlnd;
                    if (seriesRecord.d + seriesRecord.c > 0)
                    {
                        ptlnd = 1.0 - seriesRecord.d / (double)(seriesRecord.d + seriesRecord.c);
                        temp1 = ptlnd * 100.0;
                        temp2 = Convert.ToInt32(ptlnd * 100.0) - Convert.ToInt32(prevel * 100.0);
                    }
                    else
                    {
                        ptlnd = Constant.MISSING;
                        temp1 = Constant.MISSING;
                        temp2 = Constant.MISSING;
                    }
                    thisResults.AddOutput("likely_despite", ptlnd);
                    // Clopper-Pearson CI
                    MathDbl.binci(seriesRecord.d, seriesRecord.d + seriesRecord.c, out pil, out piu, gamma, out warn);
                    thisResults.AddOutput("likely_despite_from", Math.Min(1.0 - pil, 1.0 - piu));
                    thisResults.AddOutput("likely_despite_to", Math.Max(1.0 - pil, 1.0 - piu));
                    thisResults.AddOutput("likely_despite_warn", warn);
                    // as percentage
                    thisResults.AddOutput("likely_despite_pc", temp1);
                    pil = pil != Constant.MISSING
                        ? 100.0 * (1.0 - pil)
                        : Constant.MISSING;
                    piu = piu != Constant.MISSING
                        ? 100.0 * (1.0 - piu)
                        : Constant.MISSING;
                    thisResults.AddOutput("likely_despite_from_pc", Math.Min(pil, piu));
                    thisResults.AddOutput("likely_despite_to_pc", Math.Max(pil, piu));
                    // change
                    thisResults.AddOutput("likely_despite_change", temp2);
                }
            }
            DrawLegend(legend);
            EndVectorPlot();
            return results;
        }

        private static IList<ROCSeriesRecord> MakeAndMaybeAmendSeriesRecords(ITemplateHost host, ChartDefinition definition)
        {
            ROCOptions rOptions = (ROCOptions)definition.ChartOptions;
            double gamma = rOptions.GAMMA;
            if (gamma <= 0)
                return null;

            //  Assume data passed as series - X is positive, Y is negative.

            IList<ROCSeriesRecord> seriesRecords = MakeSeriesRecords(definition);

            if (rOptions.ShowOptimumCutOff)
            {
                for (int cs = 0; cs < seriesRecords.Count; cs++)
                {
                    ROCSeriesRecord seriesRecord = seriesRecords[cs];
                    if (rOptions.ShowCutOffCalculator)
                    {
                        string title = "ROC plot for " + rOptions.SeriesTitles[cs];
                        seriesRecord = ShowCutoff(host, seriesRecord, title);
                    }
                    seriesRecords[cs] = seriesRecord;
                }
            }
            return seriesRecords;
        }

        private static IList<ROCSeriesRecord> MakeSeriesRecords(ChartDefinition definition)
        {
            ROCOptions rOptions = (ROCOptions)definition.ChartOptions;
            double gamma = rOptions.GAMMA;
            if (gamma <= 0)
                return null;

            //  Assume data passed as series - X is positive, Y is negative.

            Func<double, double, bool> comparisonFunction = ToComparisonFunction(rOptions.Comparison);
            ROCSeriesRecord[] seriesRecords = new ROCSeriesRecord[definition.XSeries.Count];
            for (int c = 0; c < definition.XSeries.Count; c++)
            {
                DoubleSeries xs = (DoubleSeries)definition.XSeries[c];
                DoubleSeries ys = (DoubleSeries)definition.YSeries[c];
                double[] tdata = new double[xs.Points + ys.Points];
                Array.Copy(xs.Data, tdata, xs.Points);
                Array.Copy(ys.Data, 0, tdata, xs.Points, ys.Points);
                Array.Sort(tdata);
                seriesRecords[c] = new ROCSeriesRecord()
                {
                    comparison = rOptions.Comparison,
                    comparisonFunction = comparisonFunction,
                    pdata = xs.Data,
                    adata = ys.Data,
                    pmn = xs.Sum / xs.Points,
                    amn = ys.Sum / ys.Points,
                    min = Math.Min(xs.Min, ys.Min),
                    max = Math.Max(xs.Max, ys.Max),
                    // get a sorted list of all data in order to calculate cut points
                    tdata = tdata
                };
            }

            for (int cs = 0; cs < definition.XSeries.Count; cs++)
            {
                ROCSeriesRecord seriesRecord = seriesRecords[cs];
                double weight = rOptions.Weight;
                if (weight <= 0)
                    weight = 1.0;
                seriesRecord.weight = weight;

                if (rOptions.ShowOptimumCutOff)
                {
                    // work out cutoff for max(weight*sens+spec)
                    double maxss = 0.0;
                    for (int r = 0; r < seriesRecord.tdata.Length; r++)
                    {
                        double cutoff = seriesRecord.tdata[r];
                        int a = seriesRecord.pdata.Count(value => comparisonFunction(value, cutoff));
                        int c = seriesRecord.pdata.Length - a;
                        int b = seriesRecord.adata.Count(value => comparisonFunction(value, cutoff));
                        int d = seriesRecord.adata.Length - b;
                        double sens = a / (double)(a + c);
                        double spec = d / (double)(b + d);
                        if (weight * sens + spec > maxss)
                        {
                            maxss = weight * sens + spec;
                            seriesRecord.cutoff = cutoff;
                            seriesRecord.a = a;
                            seriesRecord.b = b;
                            seriesRecord.c = c;
                            seriesRecord.d = d;
                            seriesRecord.sens = sens;
                            seriesRecord.spec = spec;
                        }
                    }
                }
            }
            return seriesRecords;
        }

        private static Func<double, double, bool> ToComparisonFunction(Comparison comparisonValue)
        {
            // TODO: Is there a way of using Double's native operator< etc. to prevent the intermediate functions?
            switch (comparisonValue)
            {
                case Comparison.LessThan:
                    return (value, threshold) => value < threshold;
                case Comparison.LessEqual:
                    return (value, threshold) => value <= threshold;
                case Comparison.GreaterThan:
                    return (value, threshold) => value > threshold;
                default:
                    return (value, threshold) => value >= threshold;
            }
        }

        private static int CountValuesSingleSided(Comparison showopt, double[] data, double cutoff)
        {
            int a = 0;
            for (int j = 0; j < data.Length; j++)
            {
                switch (showopt)
                {
                    case Comparison.LessThan:
                    case Comparison.GreaterThan:
                        if (data[j] > cutoff)
                            a++;
                        break;
                    default:
                        if (data[j] >= cutoff)
                            a++;
                        break;
                }
            }
            return a;
        }

        private static double DeLongSE(double[] x, double[] y, double auc)
        {
            double[] v10 = new double[x.Length];
            double[] v01 = new double[y.Length];
            for (int i = 0; i < x.Length; i++)
            {
                for (int j = 0; j < y.Length; j++)
                    v10[i] += DeLongPsi(x[i], y[j]);
                v10[i] /= y.Length;
            }
            for (int j = 0; j < y.Length; j++)
            {
                for (int i = 0; i < x.Length; i++)
                    v01[j] += DeLongPsi(x[i], y[j]);
                v01[j] /= x.Length;
            }
            double s10 = 0.0;
            double s01 = 0.0;
            for (int i = 0; i < x.Length; i++)
                s10 += Math.Pow(v10[i] - auc, 2.0);
            s10 /= x.Length - 1;
            for (int j = 0; j < y.Length; j++)
                s01 += Math.Pow(v01[j] - auc, 2.0);
            s01 /= y.Length - 1;
            double var = s10 / x.Length + s01 / y.Length;
            return var < 0.0 
                ? Constant.MISSING 
                : Math.Sqrt(var);
        }

        private static double DeLongPsi(double x, double y)
        {
            if (y == x)
                return 0.5;
            return y < x 
                ? 1.0 
                : 0.0;
        }

        ///  <summary>
        ///  Cause the host to amend the thisData record in-place with any revisions to the cutoff data.
        ///  </summary>
        private static ROCSeriesRecord ShowCutoff(ITemplateHost host, ROCSeriesRecord seriesRecord, string title)
        {
            ROCCutoff payload = new() { SeriesRecord = seriesRecord, Title = title };
            host.Amend(payload, null);
            return payload.SeriesRecord;
        }
    }
}
