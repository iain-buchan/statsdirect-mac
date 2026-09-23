using System;

namespace StatsDirect.Charting
{
    ///  <summary>
    ///  A way of specifying the options that can be set for a series when it is passed through to some UI.
    ///  </summary>
    ///  <remarks></remarks>
    [Serializable]
    public class SeriesOptionsDescriptor  
    {
        public string SeriesName { get; set; }
        public bool AllowChangeToMarkerType { get; set; }
        public bool AllowChangeToMarkerSize { get; set; }
        public bool AllowChangeToMarkerColour { get; set; }
        public bool AllowChangeToLineColour { get; set; }
        public bool AllowChangeToLineThickness { get; set; }
        public bool AllowChangeToDashStyle { get; set; }
        public bool AllowChangeToFill { get; set; }
        ///  <summary>
        ///  The index of the marker that this descriptor will affect.  This is designed to allow multiple descriptors to affect the same marker.
        ///  </summary>
        public int MarkerIndex { get; set; }
        
        public SeriesOptionsDescriptor() 
        { 
            AllowChangeToDashStyle = true; 
            AllowChangeToLineThickness = true; 
            AllowChangeToMarkerColour = true;
            AllowChangeToLineColour = true;
            AllowChangeToMarkerSize = true; 
            AllowChangeToMarkerType = true; 
            AllowChangeToFill = false; 
        } 
    } 
    
    
} 
