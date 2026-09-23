using System.Collections.Generic;
using System;

namespace StatsDirect.Data
{
    [Serializable]
    public class ColumnData  
    { 
        public string Title; 
        public int Rows; 
        public double Sum; 
        public IList<Group> Groups; 
    } 
} 
