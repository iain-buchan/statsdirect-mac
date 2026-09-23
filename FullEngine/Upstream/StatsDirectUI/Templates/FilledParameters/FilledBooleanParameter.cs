using System;

namespace StatsDirect.Templates
{
    [Serializable]
    public sealed class FilledBooleanParameter : FilledParameter
    {
        internal FilledBooleanParameter()
        {
        }

        public FilledBooleanParameter(FilledParameterDirection direction, bool data)
            : base(direction)
        {
            Direction = direction;
            Data = data;
        }

        public override bool HasData => true;

        public bool Data { get; set; }

        public override bool AsBoolean => Data;

        public override object AsObject => Data;

        public override bool IsBoolean => true;

        public override string ToString() => $"FP({Direction}, {Data})";

        public override void Accept(IFilledParameterVisitor visitor)
        {
            visitor.Visit(this);
        }
    }
}
