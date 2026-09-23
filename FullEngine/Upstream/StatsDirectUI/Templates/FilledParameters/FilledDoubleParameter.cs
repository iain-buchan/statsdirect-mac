using System;

namespace StatsDirect.Templates
{
    [Serializable]
    public sealed class FilledDoubleParameter : FilledParameter
    {
        internal FilledDoubleParameter()
        {
        }

        public FilledDoubleParameter(FilledParameterDirection direction, double data)
            : base(direction)
        {
            Direction = direction;
            Data = data;
        }

        public override bool HasData => true;

        public double Data { get; set; }

        public override double AsDouble => Data;

        public override object AsObject => Data;

        public override bool IsDouble => true;

        public override string ToString() => $"FP({Direction}, {Data})";

        public override void Accept(IFilledParameterVisitor visitor)
        {
            visitor.Visit(this);
        }
    }
}
