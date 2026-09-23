using System.Collections.Generic;

namespace StatsDirect.Templates
{
    public interface IAxisScale
    {
        // The lowest value of the data that was used to create the scale
        double MinimumDataValue { get; }
        // The highest value of the data that was used to create the scale
        double MaximumDataValue { get; }
        // The lowest value of the scale
        double MinimumScaleValue { get; }
        // The highest value of the scale
        double MaximumScaleValue { get; }
        // Tics, guaranteed to be in order from low to high
        IList<Tic> Tics();

        void Accept(IAxisScaleVisitor visitor);
    }
}
