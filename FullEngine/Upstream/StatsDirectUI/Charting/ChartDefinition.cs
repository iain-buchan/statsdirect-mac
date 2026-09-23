using System;
using System.Collections.Generic;
using StatsDirect.Numerics;
using StatsDirect.Templates;

namespace StatsDirect.Charting
{
    ///  <summary>
    ///  Holds all the data for a ChartRenderer to be able to render a chart with particular data and options.
    ///  </summary>
    public class ChartDefinition : IFillable, IRenderable
    {
        private ScaleParameters scaleParameters;

        public IList<ISeries> XSeries { get; private set; }
        public IList<ISeries> YSeries { get; private set; }

        public double DataMinX { get; private set; }
        public double DataMinGreaterThanZeroX { get; private set; }
        public double DataMaxX { get; private set; }
        public double DataMinY { get; private set; }
        public double DataMinGreaterThanZeroY { get; private set; }
        public double DataMaxY { get; private set; }

        ///  <summary>
        ///  The type of chart to be plotted.
        ///  </summary>
        public ChartType ChartType { get; set; }

        public ChartOptions ChartOptions { get; set; }

        public bool IsAscii { get; set; }

        public ChartDefinition()
        {
            YSeries = new List<ISeries>();
            XSeries = new List<ISeries>();
            DataMaxX = double.MinValue;
            DataMinX = double.MaxValue;
            DataMinGreaterThanZeroX = double.MaxValue;
            DataMaxY = double.MinValue;
            DataMinY = double.MaxValue;
            DataMinGreaterThanZeroY = double.MaxValue;
        }

        ///  <summary>
        ///  Returns a copy where it's safe to alter the order of the series or the options.
        ///  </summary>
        public ChartDefinition Clone()
        {
            ChartDefinition copy = new()
            {
                ChartOptions = ChartOptions.Clone(),
                ChartType = ChartType,
                ScaleParameters = ScaleParameters.Clone()
            };
            foreach (ISeries s in XSeries)
                copy.XSeries.Add(s);
            foreach (ISeries s in YSeries)
                copy.YSeries.Add(s);
            return copy;
        }

        public void AddXSeries(double[] data, string title)
        {
            DoubleSeries s = new() { Data = new double[data.Length] };
            Array.Copy(data, s.Data, data.Length);
            s.Title = title;
            AddXSeries(s);
        }

        public void AddXSeries(ISeries s)
        {
            XSeries.Add(s);
            CheckXSeriesData(s);
        }

        public void AddXSeriesAt(ISeries newSeries, int index)
        {
            while (XSeries.Count <= index)
                XSeries.Add(null);
            XSeries[index] = newSeries;
            CheckXSeriesData(newSeries);
        }

        public void AddYSeries(double[] data, string title)
        {
            DoubleSeries s = new() { Data = new double[data.Length] };
            Array.Copy(data, s.Data, data.Length);
            s.Title = title;
            AddYSeries(s);
        }

        public void AddYSeries(ISeries s)
        {
            YSeries.Add(s);
            CheckYSeriesData(s);
        }

        public void AddYSeries(IList<ISeries> ss)
        {
            foreach (DoubleSeries s in ss)
            {
                YSeries.Add(s);
                CheckYSeriesData(s);
            }
        }

        public void AddYSeriesAt(ISeries newSeries, int index)
        {
            while (YSeries.Count <= index)
                YSeries.Add(null);
            YSeries[index] = newSeries;
            CheckYSeriesData(newSeries);
        }

        public bool HasScaleParameters => scaleParameters != null;

        public ScaleParameters ScaleParameters
        {
            get => scaleParameters ?? (scaleParameters = GetScaleParameters());
            set => scaleParameters = value;
        }

        private ScaleParameters GetScaleParameters()
        {
            using IChartRenderer renderer = ChartRendererFactory.ChartRendererFor(this, null);
            return renderer.GetScaleParameters();
        }

        private void CheckXSeriesData(ISeries series)
        {
            if (series is DoubleSeries s)
            {
                foreach (double q in s.Data)
                {
                    if (q != Constant.MISSING)
                    {
                        if (q < DataMinX)
                            DataMinX = q;
                        if (q < DataMinGreaterThanZeroX && q > 0)
                            DataMinGreaterThanZeroX = q;
                        if (q > DataMaxX)
                            DataMaxX = q;
                    }
                }
            }
        }

        private void CheckYSeriesData(ISeries series)
        {
            if (series is DoubleSeries s)
            {
                foreach (double q in s.Data)
                {
                    if (q != Constant.MISSING)
                    {
                        if (q < DataMinY)
                            DataMinY = q;
                        if (q < DataMinGreaterThanZeroY && q > 0)
                            DataMinGreaterThanZeroY = q;
                        if (q > DataMaxY)
                            DataMaxY = q;
                    }
                }
            }
        }

        void IRenderable.Accept(IRenderableVisitor visitor)
        {
            visitor.Visit(this);
        }

        public string FillerToUse => "ChartOptions";

        internal void SwapXAndYSeries()
        {
            IList<ISeries> temp = YSeries;
            YSeries = XSeries;
            XSeries = temp;
        }
    }
}
