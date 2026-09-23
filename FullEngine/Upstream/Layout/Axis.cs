using System;
using System.Collections.Generic;
using Layout.Formatters;

namespace Layout
{
    public enum AxisDirection { Horizontal, Vertical };

    public class Axis
    {
        public AxisDirection Direction { get; set; }

        // Formatting results
        public Range VisibleRange { get; set; }

        public int FontSize { get; set; }
        public double TickSize { get; set; }
        public AxisDirection LabelDirection { get; set; }

        public List<Tuple<decimal, string>> Labels { get; set; } //tick placement, label text
        public string AxisTitleExtension { get; set; } = string.Empty;

        // Statistics and scoring
        public double Score { get; set; }

        public double Simplicity { get; set; }
        public double Coverage { get; set; }
        public double Density { get; set; }
        public double Legibility { get; set; }

        //testing purposes
        public Format FormatStyle { get; set; }

        public Axis()
        {
            Labels = new List<Tuple<decimal, string>>();
            Direction = AxisDirection.Horizontal;
            Score = -10000000;
            TickSize = 7;
            FontSize = 12;
            VisibleRange = new Range(0, 0);
            LabelDirection = AxisDirection.Horizontal;


            Simplicity = -100000000;
            Coverage = -1000000000;
            Density = -100000000;
            Legibility = -10000000;
            FormatStyle = null;
        }

        public Axis Clone()
        {
            Axis clone = (Axis)MemberwiseClone();
            clone.Labels = new List<Tuple<decimal, string>>(Labels);
            return clone;
        }

    }
}
