namespace StatsDirect.Charting
{
    public class BrushDescriptor
    {
        public static BrushDescriptor Black { get; } = new BrushDescriptor(ColorDescriptor.Black);

        public ColorDescriptor Color { get; }
        public FillStyle FillStyle { get; set; } = FillStyle.Solid;

        public BrushDescriptor(ColorDescriptor color)
        {
            Color = color;
        }

    }
}