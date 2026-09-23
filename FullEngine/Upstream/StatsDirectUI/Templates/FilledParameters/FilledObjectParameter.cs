using System;
using System.Collections.Generic;
using StatsDirect.Data;
using StatsDirect.UI;
using StatsDirect.Charting;

namespace StatsDirect.Templates
{
    [Serializable]
    public sealed class FilledObjectParameter : FilledParameter
    {
        internal FilledObjectParameter()
        {
        }

        public FilledObjectParameter(FilledParameterDirection direction, object data)
            : base(direction)
        {
            Direction = direction;
            Data = data;
        }

        public override bool HasData => null != Data;

        public object Data { get; set; }

        public override bool AsBoolean => (bool)Data;

        public override ChartOptions AsChartOptions => (ChartOptions)Data;

        public override DataFrame AsDataFrame => (DataFrame)Data;

        public override DataFrame2D AsDataFrame2D => (DataFrame2D)Data;

        public override DateTime AsDate => (DateTime)Data;

        public override double AsDouble => (double)Data;

        public override int AsInt32 => (int)Data;

        public override object AsObject => Data;

        public override Pane AsPane => (Pane)Data;

        public override PaneAndPosition AsPaneAndPosition => (PaneAndPosition)Data;

        public override ParameterBag AsParameterBag => (ParameterBag)Data;

        public override IList<ParameterBag> AsParameterBagList => (IList<ParameterBag>)Data;

        public override ScaleParameters AsScaleParameters => (ScaleParameters)Data;

        public override string AsString => (string)Data;

        public override IList<string> AsStringList => (IList<string>)Data;

        public override bool IsBoolean => Data is bool;

        public override bool IsDataFrame => Data is DataFrame;

        public override bool IsDouble => Data is double;

        public override bool IsInt32 => Data is int;

        public override bool IsParameterBag => Data is ParameterBag;

        public override bool IsParameterBagList => Data is IList<ParameterBag>;

        public override bool IsString => Data is string;

        public override string ToString()
        {
            return "FP(" + Direction.ToString() + ", " + (null == Data ? "(null)" : Data.ToString()) + ")";
        }

        public override void Accept(IFilledParameterVisitor visitor)
        {
            visitor.Visit(this);
        }
    }
}
