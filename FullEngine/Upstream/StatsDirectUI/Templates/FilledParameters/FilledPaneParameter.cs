using StatsDirect.Data;
using StatsDirect.UI;
using System;

namespace StatsDirect.Templates
{
    [Serializable]
    public sealed class FilledPaneParameter : FilledParameter
    {
        internal FilledPaneParameter()
        {
        }

        public FilledPaneParameter(FilledParameterDirection direction, Pane data)
            : base(direction)
        {
            Direction = direction;
            Data = data;
        }

        public override bool HasData => true;

        public Pane Data { get; set; }

        public override Pane AsPane => Data;

        public override object AsObject => Data;

        public override string ToString() => $"FP({Direction}, {Data})";

        public override void Accept(IFilledParameterVisitor visitor)
        {
            visitor.Visit(this);
        }
    }
}
