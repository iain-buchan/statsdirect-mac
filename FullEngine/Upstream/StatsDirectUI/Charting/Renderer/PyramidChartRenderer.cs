using StatsDirect.Data;
using StatsDirect.Numerics;
using StatsDirect.Templates;
using System;
using System.Drawing;

namespace StatsDirect.Charting.Renderer
{
    internal class PyramidChartRenderer : AbstractChartRenderer, IChartRenderer
    {
        public PyramidChartRenderer(ChartDefinition definition, ICanvasFactory canvasFactory)
            : base(definition, canvasFactory)
        {
        }

        ScaleParameters IChartRenderer.GetScaleParameters()
        {
            PyramidOptions pOptions = (PyramidOptions)Definition.ChartOptions;

            DataFrame maleFrame = pOptions.MaleFrame;
            DoubleVariable males = (DoubleVariable)maleFrame.Variables[0];
            double maxmale = males.Max;

            double maxfemale;
            if (pOptions.FemaleFrame != null)
            {
                //  Separate male and female values
                DataFrame femaleFrame = pOptions.FemaleFrame;
                DoubleVariable females = (DoubleVariable)femaleFrame.Variables[0];
                maxfemale = females.Max;
            }
            else
            {
                //  Combined male/female values - assume an even split
                maxmale /= 2.0;
                maxfemale = maxmale;
            }

            double tmax = maxfemale > maxmale ? maxfemale : maxmale;

            return new ScaleParameters
            {
                X =
                {
                    AllowedScaleTypes = new[] { ScaleType.Linear },
                    Max = tmax,
                    Min = 0
                },
                Y =
                {
                    AllowedScaleTypes = new[] { ScaleType.Category },
                    Max = 0,
                    Min = 0
                }
            };
        }

        private enum PyramidMode
        {
            Totals,
            Pairs
        }

        ParameterBag IChartRenderer.Plot(/* TODO: IPreferences*/ ITemplateHost _, bool isForReturnedParametersOnly)
        {
            if (isForReturnedParametersOnly)
                return new ParameterBag();

            PyramidOptions pOptions = (PyramidOptions)Definition.ChartOptions;

            DataFrame maleFrame = pOptions.MaleFrame;
            DoubleVariable males = (DoubleVariable)maleFrame.Variables[0];
            int nmale = males.Length;
            double maxmale = males.Max;

            int nfemale = 0;
            double[] female;
            double[] male;
            double maxfemale = 0;
            PyramidMode mode;
            if (pOptions.FemaleFrame != null)
            {
                //  Separate male and female values
                DataFrame femaleFrame = pOptions.FemaleFrame;
                DoubleVariable females = (DoubleVariable)femaleFrame.Variables[0];
                female = new double[nmale];
                male = new double[nmale];
                maxfemale = females.Max;

                for (int r = 0; r < nmale; r++)
                {
                    if (females.Data[r] != Constant.MISSING && males.Data[r] != Constant.MISSING)
                    {
                        female[nfemale] = females.Data[r];
                        male[nfemale] = males.Data[r];
                        nfemale += 1;
                    }
                }
                nmale = nfemale;
                mode = PyramidMode.Pairs;
            }
            else
            {
                //  Combined male/female values - assume an even split
                female = new double[nmale];
                male = new double[nmale];
                for (int r = 0; r < nmale; r++)
                {
                    if (males.Data[r] != Constant.MISSING)
                    {
                        female[nfemale] = males.Data[r] / 2.0;
                        male[nfemale] = males.Data[r] / 2.0;
                        nfemale += 1;
                    }
                }
                nmale = nfemale;
                mode = PyramidMode.Totals;
            }

            string[] title = new string[nmale + 1];
            if (pOptions.LabelFrame != null)
            {
                StringVariable labels = (StringVariable)pOptions.LabelFrame.Variables[0];
                int i;
                for (i = labels.Length - 1; i >= 0; i--)
                {
                    if (labels.Data[i] != null && labels.Data[i].Length > 0)
                        break;
                }
                int lastrow = i;
                if (lastrow == nmale - 1)
                {
                    for (i = 0; i <= lastrow; i++)
                        title[i] = MakeTitle(labels.Data[i], "group " + (i + 1));
                }
            }

            double tmax = maxfemale > maxmale ? maxfemale : maxmale;
            double tmx = pOptions.ScaleMaximum;

            double scaleMax = tmx;
            if (scaleMax < tmax)
                scaleMax = tmax;

            BrushDescriptor maleBrush = null;
            if (pOptions.MarkerTypes.Count >= 1)
                maleBrush = MarkerTypeToBrush(pOptions.MarkerTypes[0]);
            BrushDescriptor femaleBrush = null;
            if (pOptions.MarkerTypes.Count >= 2)
                femaleBrush = MarkerTypeToBrush(pOptions.MarkerTypes[1]);

            ScaleHeight(nmale);

            StartVectorPlot(pOptions);

            double xtra = 0;
            for (int i = 0; i < nmale; i++)
            {
                double w = AxisLabelWidthInCanvasCoordinates(title[i]);
                if (w > xtra)
                    xtra = w;
            }

            DefaultAxes(null, new Size((int)Math.Ceiling(xtra), 0));

            DrawTitle(pOptions.Title);

            double ystep = YExtCanvas / nmale;
            if (title[0].Length > 0)
            {
                for (int i = 0; i < nmale; i++)
                {
                    double yc = YAxisCanvas + (nmale - i) * ystep - ystep / 2;
                    AxisDrawStringAtAngleRM(title[i], XAxisCanvas - 15, yc, LabelDirection.Across);
                }
            }

            double xstep = XExtCanvas / 2;
            double xc = XAxisCanvas + xstep;
            PenDescriptor blackPen = GetMarkerPen(ChartPreferences.MarkerTypes[10]);
            for (int i = 0; i < nmale; i++)
            {
                double yt = YAxisCanvas + (nmale - i) * ystep;
                double yb = YAxisCanvas + (nmale - i - 1) * ystep;
                double xl = XAxisCanvas + xstep - male[i] / scaleMax * xstep;
                double xr = XAxisCanvas + xstep + female[i] / scaleMax * xstep;
                if (mode == PyramidMode.Pairs)
                {
                    //  Male/female
                    DrawRectangleInCanvasCoordinates(blackPen, maleBrush, xl, yt, xc - xl, yt - yb);
                    DrawRectangleInCanvasCoordinates(blackPen, femaleBrush, xc, yt, xr - xc, yt - yb);
                }
                else
                {
                    //  Just the one
                    DrawRectangleInCanvasCoordinates(blackPen, maleBrush, xl, yt, xr - xl, yt - yb);
                }
            }

            if (mode == PyramidMode.Pairs)
            {
                DrawLineInCanvasCoordinates(blackPen, xc, YAxisCanvas, XAxisCanvas + xstep, YAxisCanvas + nmale * ystep);
                AxisDrawStringAtAngleCT("male", XExtCanvas / 4 + XAxisCanvas, YAxisCanvas - 12, LabelDirection.Across);
                AxisDrawStringAtAngleCT("female", XExtCanvas / 4 + XExtCanvas / 2 + XAxisCanvas, YAxisCanvas - 12, LabelDirection.Across);
            }

            AxisDrawStringAtAngleLT("Scale maximum = " + scaleMax, 40, YAxisCanvas - 40, LabelDirection.Across);

            EndVectorPlot();
            return new ParameterBag();
        }
    }
}
