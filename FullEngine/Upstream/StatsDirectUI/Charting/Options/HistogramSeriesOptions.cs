using System;
using StatsDirect.Numerics;

namespace StatsDirect.Charting
{
    [Serializable]
    public class HistogramSeriesOptions
    {
        public string ChartTitle { get; set; }
        public string XAxisTitle { get; set; }
        public string YAxisTitle { get; set; }

        public BinsDescriptor BinsDescriptor { get; set; }

        /// <summary>
        /// Calculate minimum bin midpoint, midpoint interval and number of bins given the current state of the options.
        /// If PoolVariablesForBins is true, this combines the data for all the variables.
        /// If PoolVariablesForBins is false, this uses just the data from the series at seriesIndex.
        /// </summary>
        /// <param name="calculateBinCount">If true, force a full calculation of the number of bins.  If false, use the user-entered number of bins as a hint.</param>
        /// <param name="binsFromUser">The user-entered number of bins</param>
        /// <param name="series"> </param>
        public void Reset(bool calculateBinCount, int binsFromUser, DoubleSeries series, BinChoiceMethod binChoiceMethod)
        {
            //  Work out the values
            BinsDescriptor = Calculate(series, binsFromUser, calculateBinCount, binChoiceMethod);
        }

        ///  <summary>
        ///  
        ///  </summary>
        ///  <param name="series">Input data. All data will be pooled for the purposes of calculating minimum and maximum values.</param>
        ///  <param name="binsFromUser">A user-entered bin count.</param>
        ///  <param name="calculateBinCount">If false, use the user-entered bin count.  If true, calculate from scratch.</param>
        /// <remarks></remarks>
        public BinsDescriptor Calculate(DoubleSeries series, int binsFromUser, bool calculateBinCount, BinChoiceMethod binChoiceMethod)
        {
            double[] nonMissingData = ExtractNonMissingDataAndSort(series, out int actualRows);

            if (calculateBinCount || binsFromUser <= 1)
                return HistogramBinChooser.ChooseBins(nonMissingData, actualRows, binChoiceMethod);
            double[] edges = HistogramBinChooser.Linspace(nonMissingData[0], nonMissingData[actualRows - 1], binsFromUser);
            int[] counts = HistogramBinChooser.SortedHist(nonMissingData, actualRows, edges);
            return new BinsDescriptor { Edges = edges, Counts = counts };
        }

        public static double[] ExtractNonMissingDataAndSort(DoubleSeries series, out int actualRows)
        {
            double[] data = series.Data;
            double[] nonMissingData = new double[data.Length];
            actualRows = 0;
            for (int c = 0; c < data.Length; c++)
                if (data[c] != Constant.MISSING)
                    nonMissingData[actualRows++] = data[c];
            //  By now, nonMissingData[0] to nonMissingData[actualRows - 1] contain the actual data for the longest row, with missing data excluded.
            Array.Sort(nonMissingData, 0, actualRows);
            return nonMissingData;
        }
    }
}
