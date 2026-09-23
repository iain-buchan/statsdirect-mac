using StatsDirect.Charting;
using System;
using System.Collections.Generic;

namespace StatsDirect.Templates
{
    [Serializable]
    public class AxisScaleParameters
    {
        public double Min { get; set; }
        public double MinGreaterThanZero { get; set; }
        public double Max { get; set; }
        public ICollection<ScaleType> AllowedScaleTypes { get; set; }
        public ScaleType ScaleType { get; set; }

        // Scale
        public IAxisScale AxisScale { get; set; }
        public LabelDirection LabelDirection { get; set; }

        // Grid lines
        public bool HasGridLines { get; set; }
        public DashStyleDescriptor GridLineDashStyle { get; set; }

        // Marker line
        public double? MarkerLineValue { get; set; }

        public AxisScaleParameters Clone()
        {
            return (AxisScaleParameters)MemberwiseClone();
        }
    }
}
