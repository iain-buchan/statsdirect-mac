namespace StatsDirect.Templates
{
    
    
    
    public class HeadlessPreferences : SDPreferences
    {
 public HeadlessPreferences() { DefaultConfidenceInterval=.95; CanDefaultConfidenceInterval=true; MetaCC=-9; MetaExact=true; MetaPlotCI=true; MetaPlotMethod=1; DisplayDecimalPlaces=6; PDecimalPlaces=4; ShouldUseColour=true; MaxRows=1048576; DECP_CHAR="."; Numeric_Thousands_Separator=","; }
        public bool CanDefaultConfidenceInterval
        {
            get;
            set;
        }

        public double DefaultConfidenceInterval
        {
            get;
            set;
        }

        public double MetaCC
        {
            get;
            set;
        }

        public bool MetaExact
        {
            get;
            set;
        }

        public bool MetaPlotCI
        {
            get;
            set;
        }

        public int MetaPlotMethod
        {
            get;
            set;
        }

        public int DisplayDecimalPlaces
        {
            get;
            set;
        }

        public int PDecimalPlaces
        {
            get;
            set;
        }

        public bool DelayContinuityCorrection
        {
            get;
            set;
        }

        public string DECP_CHAR
        {
            get;
        }

        public string Numeric_Thousands_Separator
        {
            get;
        }

        
        
        
        public int MaxRows
        {
            get;
        }

        
        
        
        
        public bool SelectGroupsByIdentifier
        {
            get;
            set;
        }
        
        
        
        
        public bool UseScientificNotationForSmallPValues
        {
            get;
            set;
        }

        public bool ShouldUseColour
        {
            get;
            set;
        }
    }

}
