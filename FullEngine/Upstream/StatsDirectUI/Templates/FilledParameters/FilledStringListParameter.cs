using System;
using System.Collections.Generic;

namespace StatsDirect.Templates
{
    [Serializable]
    public sealed class FilledStringListParameter : FilledParameter
    {
        internal FilledStringListParameter()
        {
        }

        public FilledStringListParameter(FilledParameterDirection direction, IList<string> data)
            : base(direction)
        {
            Direction = direction;
            Data = data;
        }

        public override bool HasData => null != Data;

        public IList<string> Data { get; set; }

        public override IList<string> AsStringList => Data;

        public override object AsObject => Data;

        public override string ToString() => $"FP({Direction}, {Data})";

        public override void Accept(IFilledParameterVisitor visitor)
        {
            visitor.Visit(this);
        }
    }
}
