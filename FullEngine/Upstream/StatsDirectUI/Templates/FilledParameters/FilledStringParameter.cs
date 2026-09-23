using System;

namespace StatsDirect.Templates
{
    [Serializable]
    public sealed class FilledStringParameter : FilledParameter
    {
        internal FilledStringParameter()
        {
        }

        public FilledStringParameter(FilledParameterDirection direction, string data)
            : base(direction)
        {
            Direction = direction;
            Data = data;
        }

        public override bool HasData => null != Data;

        public string Data { get; set; }

        public override string AsString => Data;

        public override object AsObject => Data;

        public override bool IsString => true;

        public override string ToString() => $"FP({Direction}, {(null != Data ? Data : "(null)")})";

        public override void Accept(IFilledParameterVisitor visitor)
        {
            visitor.Visit(this);
        }
    }
}
