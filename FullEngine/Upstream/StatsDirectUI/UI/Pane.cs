using System;
using StatsDirect.Data;

namespace StatsDirect.UI
{
    /// <summary>
    /// Represents one user-identifiable object within a StatsDirectForm.
    /// This may be a report (there's only one object in it), a script (ditto) or a grid (which may have sheets within it)
    /// </summary>
    [Serializable]
    public class Pane
    {
        public string Name { get; }
        [NonSerialized]
        private readonly WindowInformation windowInformation; // Can't be converted to an auto-property, as NonSerialized can only apply to fields.
        public object Tag { get; }

        internal Pane(string name, WindowInformation info, object tag)
        {
            Name = name;
            windowInformation = info;
            Tag = tag;
        }

        public WindowInformation WindowInformation => windowInformation;

        public override string ToString()
        {
            return Name;
        }

        public override bool Equals(object obj)
        {
            if (null == obj)
                return false;
            if (GetType() != obj.GetType())
                return false;
            Pane rhs = (Pane)obj;

            // Name
            bool bothNull = null == Name && null == rhs.Name;
            if (!bothNull && null == Name || null == rhs.Name)
                return false;
            if (!bothNull && !Name.Equals(rhs.Name))
                return false;

            // Window information
            bothNull = null == WindowInformation && null == rhs.WindowInformation;
            if (!bothNull && null == WindowInformation || null == rhs.WindowInformation)
                return false;
            if (!bothNull && !WindowInformation.Equals(rhs.WindowInformation))
                return false;

            // Tag
            if (null == Tag && null == rhs.Tag)
                return true;
            if (null == Tag || null == rhs.Tag)
                return false;
            return Tag.Equals(rhs.Tag);
        }

        public override int GetHashCode()
        {
            return Name.GetHashCode() ^ WindowInformation.GetHashCode() ^ Tag.GetHashCode();
        }
    }
}
