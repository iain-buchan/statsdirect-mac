using StatsDirect.Charting;
using System;

namespace StatsDirect.Templates
{
    [Serializable]
    public sealed class FilledChartDefinitionParameter : FilledParameter
    {
        internal FilledChartDefinitionParameter()
        {
        }

        public FilledChartDefinitionParameter(FilledParameterDirection direction, ChartDefinition data)
            : base(direction)
        {
            Direction = direction;
            Data = data;
        }

        public override bool HasData => null != Data;

        public ChartDefinition Data { get; set; }

        public override object AsObject => Data;

        public override string ToString() => $"FP({Direction}, {Data})";

        public override void Accept(IFilledParameterVisitor visitor)
        {
            visitor.Visit(this);
        }
    }
}
