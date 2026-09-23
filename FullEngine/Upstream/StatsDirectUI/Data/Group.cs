using System;

namespace StatsDirect.Data
{
    [Serializable]
    public class Group
    {
        public string Label { get; set; }
        public double Id { get; set; }
        ///  <summary>
        ///  The number of members of this group
        ///  </summary>
        public int NBin { get; set; }

        public Group(string label, double id)
        {
            Label = label;
            Id = id;
        }

        public override string ToString()
        {
            return "Group " + Id + ": " + Label;
        }
    }
}
