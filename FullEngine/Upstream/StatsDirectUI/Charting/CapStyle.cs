namespace StatsDirect.Charting
{
    public enum CapStyle
    {
        /// <summary>
        /// Line does not extend past its end points
        /// </summary>
        Butt = 0,
        /// <summary>
        /// Line is capped by a semicircle of diameter equal to LineThickness
        /// </summary>
        Round = 1,
        /// <summary>
        /// Line extends past its end points by LineThickness / 2
        /// </summary>
        Square = 2
    }
}