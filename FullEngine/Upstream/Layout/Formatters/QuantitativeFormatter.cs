using System;
using System.Collections.Generic;
using System.Linq;
using System.Drawing;
using Layout.AxisLabelers;

namespace Layout.Formatters
{
    internal class QuantitativeFormatter : IFormatter
    {
        private static readonly int[] FONT_SIZES = { 7, 8, 9, 10, 12, 14, 18, 20, 24 }; // LaTeX default font sizes
        private readonly Dictionary<int, float> ems; // In the paper we had a minimum font size of 5, but that's pretty stinking tiny. 7 is probably a better minimum size.

        public QuantitativeFormatter(Graphics g)
        {
            ems = (from x in FONT_SIZES select new { x, size=new Font("Verdana", x).GetHeight(g) }).ToDictionary(a=>a.x, a=>a.size);
        }

        public Axis Format(List<Axis> list, List<Format> formats, AxisLabeler.Options options, Func<Axis, double> scoreAxis, double bestScore = double.NegativeInfinity)
        {
            Axis result = options.DefaultAxis();
            foreach (Axis data in list)
            {
                foreach (Format format in formats)
                {
                    Axis f = data.Clone();
                    f.FormatStyle = format;
                    f.Legibility = LegibilityScoreMax(f, options);

                    if (scoreAxis(f) >= bestScore)
                    {
                        Tuple<IEnumerable<string>, string> labels = f.FormatStyle.FormalLabels(f.Labels.Select(x => x.Item1));
                        f.Labels = f.Labels.Select(x => x.Item1).Zip(labels.Item1, (a, b) => new Tuple<decimal, string>(a, b)).ToList();
                        f.AxisTitleExtension = labels.Item2;
                        f.Legibility = LegibilityScore(f, options);
                        f.Score = scoreAxis(f);
                        if (f.Score >= bestScore)
                        {
                            bestScore = f.Score;
                            result = f;
                        }
                    }
                }
            }
            return result;
        }

        protected double LegibilityFormat(Axis data, AxisLabeler.Options options)
        {
            return data.FormatStyle.Score(data.Labels.Select(x => x.Item1));
        }

        protected double LegibilityFontSize(Axis data, AxisLabeler.Options options)
        {
            double fsmin = FONT_SIZES.Min();
            return data.FontSize > options.FontSize || data.FontSize < fsmin
                ? double.NegativeInfinity
                : (data.FontSize == options.FontSize
                    ? 1
                    : 0.2 * ((data.FontSize - fsmin + 1) / (options.FontSize - fsmin)));
        }

        protected double LegibilityOrientation(Axis data, AxisLabeler.Options options)
        {
            return data.LabelDirection == AxisDirection.Horizontal ? 1.0 : -0.5;
        }

        protected double LegibilityOverlap(Axis data, AxisLabeler.Options options)
        {
            // compute overlap score
            double em = ems[data.FontSize];
            List<RectangleF> rects = data.Labels.Select(s => options.ComputeLabelRect(s.Item2, s.Item1, data)).ToList();
            // takes adjacent pairs of rectangles
            double overlap = rects.Take(rects.Count - 1).Zip(rects.Skip(1), 
                (a, b) =>
                {
                    double dist = options.Direction == AxisDirection.Horizontal ? b.Left - a.Right : a.Top - b.Bottom;
                    return Math.Min(1, 2 - 1.5 * em / Math.Max(0, dist));
                } ).Min();
            return overlap;
        }

        protected double LegibilityScoreMax(Axis data, AxisLabeler.Options options)
        {
            return (LegibilityFormat(data, options) +
                    LegibilityFontSize(data, options) +
                    LegibilityOrientation(data, options) +
                    1) / 4;
        }

        protected double LegibilityScore(Axis data, AxisLabeler.Options options)
        {
            return (LegibilityFormat(data, options) +
                    LegibilityFontSize(data, options) +
                    LegibilityOrientation(data, options) +
                    LegibilityOverlap(data, options)) / 4;
        }

        public List<Axis> VaryFontSize(List<Axis> list, AxisLabeler.Options options)
        {
            List<Axis> possibilities = new List<Axis>();
            // Reverse to produce the font sizes in decreasing order of goodness
            foreach (int size in FONT_SIZES.Where(s => s <= options.FontSize).Reverse())
            {
                foreach (Axis data in list)
                {
                    Axis option = data.Clone();
                    option.FontSize = size;
                    possibilities.Add(option);
                }
            }
            return possibilities;
        }

        public List<Axis> VaryOrientation(List<Axis> list)
        {
            List<Axis> possibilities = new List<Axis>();
            foreach (Axis axis in list)
            {
                Axis option = axis.Clone();
                option.LabelDirection = AxisDirection.Horizontal;
                possibilities.Add(option);
            }

            foreach (Axis axis in list)
            {
                Axis option = axis.Clone();
                option.LabelDirection = AxisDirection.Vertical;
                possibilities.Add(option);
            }
            return possibilities;
        }
    }

}
