using StatsDirect.Configuration;
using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;


namespace StatsDirect.UI.Properties
{
    internal enum FormWindowState { Normal, Minimized, Maximized }
    internal sealed class Settings
    {
        public static Settings Default { get; } = new();
        /// <summary>
        /// Guaranteed a new copy each time, with no load of any other data on top.
        /// </summary>
        public static Settings InstallationDefaults => new();

        public int MainTop { get; set; }
        public int MainLeft { get; set; }
        public int MainWidth { get; set; }
        public int MainHeight { get; set; }
        public FormWindowState MainWindowState { get; set; }

        [JsonIgnore]
        public string MenuFileName { get; set; } = "menu.xml";
        public bool MetaPlotCI { get; set; } = true;
        public int MetaPlotMethod { get; set; } = 1;
        public int PDecimalPlaces { get; set; } = 4;
        public double MetaCC { get; set; } = -9;
        public bool MetaExact { get; set; } = true;
        public bool DelayContinuityCorrection { get; set; } = false;
        public bool CanDefaultConfidenceInterval { get; set; } = true;
        public double DefaultConfidenceInterval { get; set; } = 0.95;
        public IReadOnlyList<string> RecentFileList { get; set; }
        public bool SelectGroupsByIdentifier { get; set; } = false;
        public IReadOnlyList<string> ToolsNames { get; set; } = new string[] { "Calculator", "Notepad"};
        public IReadOnlyList<string> ToolsPrograms { get; set; } = new string[] { "%STATSDIRECT%\\StatsDirect.exe -calculator", "notepad.exe" };

        [JsonIgnore]
        public string DataDirectory => "Data";

        [JsonIgnore]
        public string DefaultRecentlyUsedFile => "test.xlsx";
        public bool ShouldKeepData { get; set; } = false;
        public int DisplayDecimalPlaces { get; set; } = 6;
        public bool ShouldUseColour { get; set; } = true;
        public string DefaultWorkbookFont { get; set; } = "Calibri;0;11";

        [JsonIgnore]
        public string TemplateDirectory => "Template";

        [JsonIgnore]
        public string OperationsDirectory => "Operations";

        [JsonIgnore]
        public string UserOperationsDirectory => "UserOperations";
        public int CalculatorTop { get; set; } = 0;
        public int CalculatorLeft { get; set; } = 0;
        public int CalculatorWidth { get; set; } = 0;
        public int CalculatorHeight { get; set; } = 0;
        public bool CalculatorMaximized { get; set; } = false;
        public string Markers { get; set; } = string.Empty;
        public string TitleFont { get; set; } = string.Empty;
        public string LabelFont { get; set; } = string.Empty;
        public bool BoxAxes { get; set; } = false;
        public bool BlackAndWhite { get; set; } = false;
        public bool RequestScaleLimits { get; set; } = false;
        public bool UseScientificNotationForSmallPValues { get; set; } = false;

        [JsonIgnore]
        public bool WasLoaded { get; set;} = false;

        public void Save()
        {
            // Preferences are owned by the native host; the headless engine does not persist them.
        }
    }
}
