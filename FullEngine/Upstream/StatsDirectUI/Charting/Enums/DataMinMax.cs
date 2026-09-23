namespace StatsDirect.Charting
{
    public enum DataMinMax
    {
        /// <summary>
        /// Calculate X and Y separately
        /// </summary>
        XCalc_YCalc = 0,
        /// <summary>
        /// Calculate X, Y is preset
        /// </summary>
        XCalc_YPreset = 1,
        /// <summary>
        /// Use preset X and Y values
        /// </summary>
        XPreset_YPreset = -99,
        /// <summary>
        /// Use preset values in scale parameters
        /// </summary>
        XUseScaleParameters_YUseScaleParameters = -98,
        /// <summary>
        /// Calculate; X and Y must have the same scale
        /// </summary>
        XY_CalcTogether = -97
    }
}
