namespace StatsDirect.Charting
{
    public class ColorDescriptor
    {
        public int R { get; }
        public int G { get; }
        public int B { get; }

        public static ColorDescriptor Black { get; } = FromArgb(0, 0, 0);
        public static ColorDescriptor Blue { get; } = FromArgb(0, 0, 255);
        public static ColorDescriptor Gray { get; } = FromArgb(128, 128, 128);
        public static ColorDescriptor Green { get; } = FromArgb(0, 128, 0);
        public static ColorDescriptor Magenta { get; } = FromArgb(255, 0, 255);
        public static ColorDescriptor Red { get; } = FromArgb(255, 0, 0);
        public static ColorDescriptor White { get; } = FromArgb(255, 255, 255);

        public static ColorDescriptor FromArgb(int r, int g, int b)
        {
            return new ColorDescriptor(r, g, b);
        }

        public override bool Equals(object obj)
        {
            ColorDescriptor descriptor = obj as ColorDescriptor;
            return descriptor != null &&
                   R == descriptor.R &&
                   G == descriptor.G &&
                   B == descriptor.B;
        }

        public override int GetHashCode()
        {
            var hashCode = -1520100960;
            hashCode = hashCode * -1521134295 + R.GetHashCode();
            hashCode = hashCode * -1521134295 + G.GetHashCode();
            hashCode = hashCode * -1521134295 + B.GetHashCode();
            return hashCode;
        }

        private ColorDescriptor(int r, int g, int b)
        {
            R = r;
            G = g;
            B = b;
        }


    }
}