using System;
using System.IO;

namespace StatsDirect.R
{
    public class RVersion: IComparable<RVersion>
    {
        public string InstallPath { get; set; }
        public string VersionString { get; set; }
        public bool IsX64 { get; set; }
        public int MajorVersion
        {
            get
            {
                if (!numericVersionsAreSet)
                    SetNumericVersions();
                return majorVersion;
            }
        }
        public int MinorVersion
        {
            get
            {
                if (!numericVersionsAreSet)
                    SetNumericVersions();
                return minorVersion;
            }
        }
        public int Revision
        {
            get
            {
                if (!numericVersionsAreSet)
                    SetNumericVersions();
                return revision;
            }
        }
        private int majorVersion;
        private int minorVersion;
        private int revision;
        private bool numericVersionsAreSet;

        public string BinPath => Path.Combine(InstallPath, "bin", IsX64 ? "x64" : "i386");

        public string GuiPath => Path.Combine(BinPath, "Rgui.exe");

        private void SetNumericVersions()
        {
            string[] candidateSplit = VersionString.Split('.');
            if (candidateSplit.Length != 3)
                return;
            if (!int.TryParse(candidateSplit[0], out majorVersion))
                return;
            if (!int.TryParse(candidateSplit[1], out minorVersion))
                return;
            if (!int.TryParse(candidateSplit[2], out revision))
                return;
            numericVersionsAreSet = true;
        }

        /// <summary>
        /// Rules: Prefer highest version, then highest bitness.
        /// </summary>
        public int CompareTo(RVersion other)
        {
            if (null == other)
                return 1;
            int maj = MajorVersion - other.MajorVersion;
            if (maj != 0)
                return maj;
            int min = MinorVersion - other.MinorVersion;
            if (min != 0)
                return min;
            int rev = Revision - other.Revision;
            if (rev != 0)
                return rev;
            return (IsX64 ? 1 : 0) - (other.IsX64 ? 1 : 0);
        }
    }
}
