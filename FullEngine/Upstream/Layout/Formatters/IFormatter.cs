using System;
using System.Collections.Generic;
using Layout.AxisLabelers;

namespace Layout.Formatters
{
    internal interface IFormatter
    {
        Axis Format(List<Axis> list, List<Format> formats, AxisLabeler.Options options, Func<Axis, double> scoreAxis, double bestScore = double.NegativeInfinity);
    }

}
