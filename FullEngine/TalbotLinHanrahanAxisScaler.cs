using System.Drawing;
using Layout;
using StatsDirect.Templates;

namespace StatsDirect.Charting.Scales
{
    internal class TalbotLinHanrahanAxisScaler : IAxisScaler
    {
        public IAxisScale QAxis(double minimumDataValue, double minimumDataValueGreaterThanZero, double maximumDataValue, bool isYAxis, bool useDataValuesAsScaleValues)
        {
            Range dataRange = new(minimumDataValue, maximumDataValue);
            RectangleF todoScreen = new(0, 0, 1100, 800);
            // do axis layout
            AxisLayout axisLayout = new(isYAxis, dataRange, dataRange,
                (label, pos, axis) => /* ComputeLabelRect(label, pos, bottomPanel.ToScreen(), screen, axis) */ new RectangleF(0, (float)-pos, 0.1f, 0.1f), todoScreen);
            // Font metrics are supplied by CoreText in the host QuantitativeFormatter.
            Axis tlhAxis = axisLayout.LayoutAxis(null);
            if (null == tlhAxis)
                throw new System.Exception("Cannot create a suitable axis based on the specified data or scale values");
            return new TalbotLinHanrahanAxisScale(tlhAxis, minimumDataValue, maximumDataValue);
        }
    }
}
