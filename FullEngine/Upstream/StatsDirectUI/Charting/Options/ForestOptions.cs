using System;

namespace StatsDirect.Charting
{
    [Serializable]
    public class ForestOptions : ForestishOptions
    {
        public double[] pg; // Should really be integer or bool but assigning a double variable is as efficient
        public int EffectSizeAndIntervalDecimalPlaces { get; set; }

        public ForestOptions()
        {
            cco = 0.95;
        }

        public override bool UsesChartTitle => true;

        public override bool UsesXAxisTitle => true;

        public override bool ShowForestOptions => true;

        public override bool UsesAxisLabelFontDescriptor => true;

        public override bool UsesAxisTitleFontDescriptor => true;

        public override void Accept(IChartOptionVisitor visitor)
        {
            visitor.Visit(this);
        }
    }
}
