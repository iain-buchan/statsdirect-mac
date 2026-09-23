using StatsDirect.Templates;
using System;

namespace StatsDirect.UI
{
    [Serializable]
    public class PaneAndPosition
    {
        public Pane Pane { get; set; }
        public RelativePosition WritePosition { get; set; }

        internal PaneAndPosition(Pane pane, RelativePosition writePosition)
        {
            Pane = pane;
            WritePosition = writePosition;
        }

        public override string ToString()
        {
            string renderedPosition = string.Empty;
            switch (WritePosition)
            {
                case RelativePosition.FirstColumn:
                    renderedPosition = "first column";
                    break;
                case RelativePosition.BeforeSelection:
                    renderedPosition = "before current position";
                    break;
                case RelativePosition.ReplaceSelection:
                    renderedPosition = "replacing current selection";
                    break;
                case RelativePosition.AfterSelection:
                    renderedPosition = "after current position";
                    break;
                case RelativePosition.LastColumn:
                    renderedPosition = "last column";
                    break;
                    // default: No effect
            }
            if (string.IsNullOrEmpty(renderedPosition))
                return Pane.ToString();

            return Pane + " (" + renderedPosition + ")";
        }

        public override bool Equals(object obj)
        {
            if (null == obj)
                return false;
            if (GetType() != obj.GetType())
                return false;
            PaneAndPosition rhs = (PaneAndPosition)obj;

            // Pane
            bool bothNull = null == Pane && null == rhs.Pane;
            if (!bothNull && null == Pane || null == rhs.Pane)
                return false;
            if (!bothNull && !Pane.Equals(rhs.Pane))
                return false;

            // WritePosition
            return WritePosition == rhs.WritePosition;
        }

        public override int GetHashCode()
        {
            return Pane.GetHashCode() ^ (int)WritePosition;
        }
    }
}
