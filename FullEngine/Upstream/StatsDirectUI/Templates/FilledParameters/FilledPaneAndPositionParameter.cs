using StatsDirect.Data;
using StatsDirect.UI;
using System;

namespace StatsDirect.Templates
{
    [Serializable]
    public sealed class FilledPaneAndPositionParameter : FilledParameter
    {
        internal FilledPaneAndPositionParameter()
        {
        }

        public FilledPaneAndPositionParameter(FilledParameterDirection direction, PaneAndPosition data)
            : base(direction)
        {
            Direction = direction;
            Data = data;
        }

        public override bool HasData => true;

        public PaneAndPosition Data { get; set; }

        public override PaneAndPosition AsPaneAndPosition => Data;

        public override object AsObject => Data;

        public override string ToString() => $"FP({Direction}, {Data})";

        public override void Accept(IFilledParameterVisitor visitor)
        {
            visitor.Visit(this);
        }
    }
}
