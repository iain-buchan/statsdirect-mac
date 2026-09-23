namespace StatsDirect.Charting
{
    public class PenDescriptor
    {
        public static PenDescriptor White { get; } = new PenDescriptor(ColorDescriptor.White);
        public static PenDescriptor Black { get; } = new PenDescriptor(ColorDescriptor.Black);

        public ColorDescriptor Color { get; set; }
        public double LineThickness { get; set; }
        public DashStyleDescriptor DashStyle { get; set; }
        public CapStyle CapStyle { get; set; }

        public PenDescriptor(ColorDescriptor color)
            : this(color, 1)
        {
        }

        public PenDescriptor(ColorDescriptor color, double lineThickness)
        {
            Color = color;
            LineThickness = lineThickness;
        }
    }
}