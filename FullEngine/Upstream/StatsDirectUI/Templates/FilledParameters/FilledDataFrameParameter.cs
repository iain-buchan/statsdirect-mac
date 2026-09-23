using StatsDirect.Data;
using System;

namespace StatsDirect.Templates
{
    [Serializable]
    public sealed class FilledDataFrameParameter : FilledParameter
    {
        internal FilledDataFrameParameter()
        {
        }

        public FilledDataFrameParameter(FilledParameterDirection direction, DataFrame data)
            : base(direction)
        {
            Direction = direction;
            Data = data;
        }

        public override bool HasData => true;

        public DataFrame Data { get; set; }

        public override DataFrame AsDataFrame => Data;

        public override object AsObject => Data;

        public override bool IsDataFrame => true;

        public override string ToString() => $"FP({Direction}, {Data})";

        public override void Accept(IFilledParameterVisitor visitor)
        {
            visitor.Visit(this);
        }
    }
}
