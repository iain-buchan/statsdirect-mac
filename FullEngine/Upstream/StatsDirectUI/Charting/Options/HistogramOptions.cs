using System;
using System.Collections.Generic;

namespace StatsDirect.Charting
{
    [Serializable]
    public class HistogramOptions : GenericOptions
    {
        private bool showRelativeFrequencies;

        public bool OverlayNormalCurve { get; set; }
        ///  <summary>
        ///  Informational to the filler.  ASCII charts cannot overlay normals, so the option should not be given.
        ///  </summary>
        public bool IsAscii { get; set; }

        ///  <summary>
        ///  If true, all variables are pooled for bin calculations (i.e. there is a common X axis).
        ///  If false, bin calculations are per-variable.
        ///  </summary>
        public bool PoolVariablesForBins { get; set; }

        public BinChoiceMethod BinChoiceMethod { get; set; } = BinChoiceMethod.Doane;

        /// <summary>
        /// Calculate minimum bin midpoint, midpoint interval and number of bins given the current state of the options.
        /// If PoolVariablesForBins is true, this combines the data for all the variables.
        /// If PoolVariablesForBins is false, this uses just the data from the series at seriesIndex.
        /// </summary>
        /// <param name="calculateBinCount">If true, force a full calculation of the number of bins.  If false, use the user-entered number of bins as a hint.</param>
        /// <param name="binsFromUser">The user-entered number of bins</param>
        /// <param name="series"> </param>
        public void Reset(bool calculateBinCount, int binsFromUser, int seriesIndex, DoubleSeries series)
        {
            HistoSeriesOptions[seriesIndex].Reset(calculateBinCount, binsFromUser, series, BinChoiceMethod);

            // Warn listeners that we've just changed our scale.
            ScaleChanged?.Invoke(this, EventArgs.Empty);
        }

        public bool ShowRelativeFrequencies
        {
            get => showRelativeFrequencies;
            set
            {
                bool changed = value != showRelativeFrequencies;
                showRelativeFrequencies = value;
                if (changed)
                    ScaleChanged?.Invoke(this, EventArgs.Empty);
            }
        }

        //  Display options
        public int LineWidth { get; set; }
        public string AxisFontDescriptor { get; set; }
        public List<HistogramSeriesOptions> HistoSeriesOptions { get; set; }
        [field: NonSerialized]
        public event EventHandler ScaleChanged;

        public override bool UsesShowLegend => false;

        public override bool UsesXAxisOptions => false;

        public override bool ShowHistogramOptions => true;

        public override bool ShowLegendIsRelevant => HistoSeriesOptions.Count > 1;

        public override void Accept(IChartOptionVisitor visitor)
        {
            visitor.Visit(this);
        }
    }
}
