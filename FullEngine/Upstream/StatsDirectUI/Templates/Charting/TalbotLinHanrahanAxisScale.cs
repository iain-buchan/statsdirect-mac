using System;
using System.Collections.Generic;
using System.Linq;
using Layout;

namespace StatsDirect.Templates
{
    public class TalbotLinHanrahanAxisScale : ILinearAxisScale
    {
        private Axis TlhAxis { get; }
        private double QMin { get; }
        private double QMax { get; }

        public TalbotLinHanrahanAxisScale(Axis tlhAxis, double qmin, double qmax)
        {
            TlhAxis = tlhAxis;
            QMin = qmin;
            QMax = qmax;
        }

        public double MaximumDataValue => QMax;

        public double MaximumScaleValue => TlhAxis.VisibleRange.Max;

        public double MinimumDataValue => QMin;

        public double MinimumScaleValue => TlhAxis.VisibleRange.Min;

        public int IntervalsPerMajorTic => 1;

        public int Phase => 0;

        public double Interval => (double)(TlhAxis.Labels[1].Item1 - TlhAxis.Labels[0].Item1);

        public double FirstMajorTicValue => (double)TlhAxis.Labels[0].Item1;

        public IList<Tic> Tics()
        {
            return TlhAxis.Labels.Select(label => new Tic(Convert.ToDouble(label.Item1), label.Item2)).ToList();
        }

        void IAxisScale.Accept(IAxisScaleVisitor visitor)
        {
            visitor.Visit(this);
        }
    }
}
