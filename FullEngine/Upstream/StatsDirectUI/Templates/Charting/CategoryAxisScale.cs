using System.Collections.Generic;

namespace StatsDirect.Templates
{
    public class CategoryAxisScale: IAxisScale
    {
        public double MinimumDataValue => 0;
        public double MaximumDataValue => Categories;
        public double MinimumScaleValue => 0;
        public double MaximumScaleValue => Categories;

        /// The number of intervals between tics (one less than the number of tics).  20 intervals = 21 tics - one extra at the end.
        private int Categories { get; }

        public CategoryAxisScale(int categories)
        {
            Categories = categories;
        }

        /// <summary>
        /// Returns a linear list of tics constructed according to the parameters.
        /// </summary>
        public IList<Tic> Tics()
        {
            List<Tic> tics = new(Categories + 1);
            for (int i = 0; i <= Categories; i++)
                tics.Add(new Tic(i, i.ToString()));
            return tics;
        }

        public override string ToString()
        {
            return $"CategoryAxisScale({Categories})";
        }

        void IAxisScale.Accept(IAxisScaleVisitor visitor)
        {
            visitor.Visit(this);
        }
    }
}
