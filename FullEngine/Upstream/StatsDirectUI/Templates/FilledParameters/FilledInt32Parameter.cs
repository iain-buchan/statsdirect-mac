using System;

namespace StatsDirect.Templates
{
    [Serializable]
    public sealed class FilledInt32Parameter : FilledParameter
    {
        internal FilledInt32Parameter()
        {
        }

        public FilledInt32Parameter(FilledParameterDirection direction, int data)
            : base(direction)
        {
            Direction = direction;
            Data = data;
        }

        public override bool HasData => true;

        public int Data { get; set; }

        public override int AsInt32 => Data;

        public override object AsObject => Data;

        public override bool IsInt32 => true;

        public override string ToString() => $"FP({Direction}, {Data})";

        public override void Accept(IFilledParameterVisitor visitor)
        {
            visitor.Visit(this);
        }
    }
}
