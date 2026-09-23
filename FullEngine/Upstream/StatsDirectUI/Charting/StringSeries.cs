namespace StatsDirect.Charting
{
    public class StringSeries : ISeries 
    { 
        
        public string[] Data;

        public string Title { get; set; }

        public StringSeries() 
        { 
        } 
        
        public StringSeries( int dataLength ) 
        { 
            Data = new string[ dataLength ]; 
        } 
        
        public int Length => Data.Length;
    } 
} 
