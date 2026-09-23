using StatsDirect.Data;
using System;
using System.Collections.Generic;

namespace StatsDirect.Templates
{
    [Serializable]
    public sealed class FilledParameterBagListParameter : FilledParameter
    {
        internal FilledParameterBagListParameter()
        {
        }

        public FilledParameterBagListParameter(FilledParameterDirection direction, IList<ParameterBag> data)
            : base(direction)
        {
            Direction = direction;
            Data = data;
        }

        public override bool HasData => true;

        public IList<ParameterBag> Data { get; set; }

        public override IList<ParameterBag> AsParameterBagList => Data;

        public override object AsObject => Data;

        public override bool IsParameterBagList => true;

        public override string ToString() => $"FP({Direction}, {Data})";

        public override void Accept(IFilledParameterVisitor visitor)
        {
            visitor.Visit(this);
        }
    }
}
