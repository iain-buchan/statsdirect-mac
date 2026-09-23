using System;
using System.Drawing;
using System.Runtime.InteropServices;
namespace StatsDirect.Charting {
    internal static class MacText {
        [DllImport("libStatsDirectText.dylib", CallingConvention = CallingConvention.Cdecl)]
        private static extern int statsdirect_measure_text([MarshalAs(UnmanagedType.LPUTF8Str)] string text, [MarshalAs(UnmanagedType.LPUTF8Str)] string family, double pixels, int style, out double width, out double height);
        public static SizeF Measure(string text, string family, double points, int style = 0) {
            double width = 0, height = 0;
            foreach (var line in text.Replace("\r", "").Split('\n')) {
                if (statsdirect_measure_text(line, family, points * 96.0 / 72.0, style, out double w, out double h) != 0)
                    throw new InvalidOperationException("CoreText could not measure the chart label.");
                width = Math.Max(width, w); height += h;
            }
            return new SizeF((float)width, (float)height);
        }
    }
}
