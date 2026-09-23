using System.Collections.Generic;
using StatsDirect.Numerics;

namespace StatsDirect.Charting
{
    /// <summary>
    /// A "point" containing one x co-ordinate and one or more y co-ordinates.  The y co-ordinate use is up to the plotting routine.
    /// </summary>
    public class MultiDoublePoint
    {
        public double X { get; set; }
        private IList<double> ys;

        public MultiDoublePoint()
        {
            ys = new List<double>(1);
        }

        public int YCount => ys.Count;

        public void set_Y(int index, double value)
        {
            EnsureYIndicesInclude(index, Constant.MISSING);
            ys[index] = value;
        }

        /// <summary>
        /// Postcondition: Access to get_Y[0]...get_Y[index] will succeed, and any previously missing values will have been set to fillValue.
        /// </summary>
        /// <param name="index"></param>
        /// <param name="fillValue"></param>
        public void EnsureYIndicesInclude(int index, double fillValue)
        {
            while (ys.Count <= index)
                ys.Add(fillValue);
        }

        public double get_Y(int index)
        {
            return ys[index];
        }

        /// <summary>
        /// Return a deep copy of this MDP.
        /// </summary>
        /// <returns></returns>
        public MultiDoublePoint Clone()
        {
            return new MultiDoublePoint { X = X, ys = new List<double>(ys) };
        }
    }
}
