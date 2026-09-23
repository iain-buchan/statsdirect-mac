namespace StatsDirect.Templates
{
    /// <summary>
    /// A place to hold a bag of preference values, to be used throughout the system.
    /// </summary>
    public interface SDPreferences
    {
        bool CanDefaultConfidenceInterval
        {
            get;
            set;
        }

        double DefaultConfidenceInterval
        {
            get;
            set;
        }

        double MetaCC
        {
            get;
            set;
        }

        bool MetaExact
        {
            get;
            set;
        }

        bool MetaPlotCI
        {
            get;
            set;
        }

        int MetaPlotMethod
        {
            get;
            set;
        }

        int DisplayDecimalPlaces
        {
            get;
            set;
        }

        int PDecimalPlaces
        {
            get;
            set;
        }

        bool DelayContinuityCorrection
        {
            get;
            set;
        }

        string DECP_CHAR
        {
            get;
        }

        string Numeric_Thousands_Separator
        {
            get;
        }

        /// <summary>
        /// The largest number of rows this host is willing to output.
        /// </summary>
        int MaxRows
        {
            get;
        }

        /// <summary>
        /// If false, group selectors are by variable.
        /// If true, group selectors are by indicator.
        /// </summary>
        bool SelectGroupsByIdentifier
        {
            get;
            set;
        }
        
        /// <summary>
        /// If true, scientific notation should be used for small P value display.  If false, P < 0.*1 will be shown.
        /// </summary>
        bool UseScientificNotationForSmallPValues
        {
            get;
            set;
        }

        bool ShouldUseColour
        {
            get;
            set;
        }
    }

}
