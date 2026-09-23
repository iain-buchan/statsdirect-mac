namespace StatsDirect.Charting
{
    public class SizeD
    {
        public static SizeD Empty = new(0, 0);

        public double Width { get; }
        public double Height { get; }

        public SizeD(double width, double height)
        {
            Width = width;
            Height = height;
        }
    }
}