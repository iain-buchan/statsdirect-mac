namespace StatsDirect.Utilities
{
    public enum DataAcquisitionMode
    {
        NotSet = 0,
        /// <summary>
        /// Doubles; missing values are removed from the output
        /// </summary>
        NumericSkipMissing = 1,
        /// <summary>
        /// Doubles; missing rows are preserved in the output, replaced with Constant.MISSING.
        /// </summary>
        NumericReplaceMissing = 2,
        /// <summary>
        /// Acquire identifiers for groups or subgroups
        /// </summary>
        GroupIdentifiers = 3,
        CategoryReplaceMissing = 4,
        CategoryCombineAllColumns = 5,
        Text = 101,
        DateReplaceMissing = 102,
        TextWithFormulae = 103,
        TextNoTitles = 104,
        NumericCodingTextToCategories = 105,
        NumericCodingTextToDummies = 106,
        /// <summary>
        /// Whatever we can get, of whatever types.  Used for R export.
        /// </summary>
        Variant = 107
    }
}