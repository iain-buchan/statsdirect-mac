using System;

namespace StatsDirect.Charting
{
    [Flags]
    public enum AxisMode
    {
        /* Primitives */
        None = 0x0,
        Line = 0x1,
        Reverse = 0x2,
        Tics = 0x4,
        Labels = 0x8,
        AxisIsNumeric = 0x10,
        AxisIsDate = 0x20,
        AxisIsSeries = 0x30,
        /* Useful groupings */
        Scale = 0x1d,
        ScaleWithoutLabels = 0x15,
        ReverseScale = 0x1f,
        Series = 0x3d,
        LineOnly = 0x1
    }
}
