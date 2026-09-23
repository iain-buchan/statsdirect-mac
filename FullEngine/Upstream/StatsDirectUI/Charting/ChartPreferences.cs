using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;
using StatsDirect.UI.Properties;

namespace StatsDirect.Charting
{
    static class ChartPreferences
    {
        public static bool AreSharedValuesInitialised { get; private set; }

        private static FontDescriptor defaultAxisLabelFont;
        private static FontDescriptor defaultAxisTitleFont;
        private static FontDescriptor defaultTitleFont;
        private static FontDescriptor defaultLegendFont;
        private static FontDescriptor defaultLabelFont;

        private static bool defaultBoxAxes;

        private static bool defaultAllBlack;

        /// <summary>
        /// Default marker types; shared between renderers.
        /// </summary>
        private static MarkerType[] sharedMarkerTypes;
        // TODO: Marker stacks are an abomination for histograms and should be removed forthwith.
        private static Stack<MarkerType[]> markerTypeStack;

        public static bool DefaultRequestScaleLimits => false;

        public static bool DefaultBoxAxes
        {
            get
            {
                if (!AreSharedValuesInitialised)
                    InitSharedValues();
                return defaultBoxAxes;
            }
            set => defaultBoxAxes = value;
        }

        public static FontDescriptor DefaultAxisLabelFont
        {
            get
            {
                if (!AreSharedValuesInitialised)
                    InitSharedValues();
                return defaultAxisLabelFont;
            }
            set => defaultAxisLabelFont = value;
        }

        public static FontDescriptor DefaultSeriesLabelFont => DefaultAxisLabelFont;

        public static FontDescriptor DefaultAxisTitleFont
        {
            get
            {
                if (!AreSharedValuesInitialised)
                    InitSharedValues();
                return defaultAxisTitleFont;
            }
            set => defaultAxisTitleFont = value;
        }

        public static FontDescriptor DefaultLabelFont
        {
            get
            {
                if (!AreSharedValuesInitialised)
                    InitSharedValues();
                return defaultLabelFont;
            }
            set => defaultLabelFont = value;
        }

        public static FontDescriptor DefaultLegendFont
        {
            get
            {
                if (!AreSharedValuesInitialised)
                    InitSharedValues();
                return defaultLegendFont;
            }
            set => defaultLegendFont = value;
        }

        public static FontDescriptor DefaultTitleFont
        {
            get
            {
                if (!AreSharedValuesInitialised)
                    InitSharedValues();
                return defaultTitleFont;
            }
            set => defaultTitleFont = value;
        }

        public static MarkerType[] MarkerTypes
        {
            get
            {
                if (!AreSharedValuesInitialised)
                    InitSharedValues();
                return sharedMarkerTypes;
            }
        }

        public static void InitSharedValues()
        {
            AreSharedValuesInitialised = true; //  Set early to prevent recursively trying to initialise properties when saving them
            InitMarkerTypes();
            InitFonts();
            InitFlags();
        }

        internal static void InitFirstFonts()
        {
            //  Default fonts, in case there are no preferences
            DefaultAxisLabelFont = new FontDescriptor("Calibri", 0, 15);
            DefaultAxisTitleFont = new FontDescriptor("Calibri", 1, 15);
            DefaultLabelFont = new FontDescriptor("Calibri", 0, 15);
            DefaultLegendFont = new FontDescriptor("Calibri", 0, 15);
            DefaultTitleFont = new FontDescriptor("Calibri", 1, 22);
            SaveFonts();
        }

        ///  <summary>
        ///  Initialise the marker types from persistent storage or (if none) from defaults
        ///  </summary>
        ///  <remarks></remarks>
        private static void InitMarkerTypes()
        {
            sharedMarkerTypes = new MarkerType[11];
            for (int i = sharedMarkerTypes.GetLowerBound(0); i <= sharedMarkerTypes.GetUpperBound(0); i++)
                sharedMarkerTypes[i] = new MarkerType();

            string savedSettings = Settings.Default.Markers;

            if (savedSettings == null || savedSettings.Length < 10)
            {
                InitFirstMarkerTypes();
            }
            else
            {
                string[] markerStrings = savedSettings.Split('|');
                for (int i = 0; i <= 9; i++)
                {
                    string[] parameterStrings = markerStrings[i].Split(';');
                    //  Shape
                    MarkerShape shape = (MarkerShape)int.Parse(parameterStrings[0]);
                    //  Colour
                    string[] colourValues = parameterStrings[1].Split(',');
                    ColorDescriptor col = ColorDescriptor.FromArgb(int.Parse(colourValues[0]), int.Parse(colourValues[1]), int.Parse(colourValues[2]));
                    //  Width
                    float width = float.Parse(parameterStrings[2]);
                    //  Style
                    DashStyleDescriptor style = (DashStyleDescriptor)int.Parse(parameterStrings[3]);
                    //  Filled (1 = yes, missing or 0 = no)
                    bool isFilled = false;
                    if (parameterStrings.Length > 4)
                        isFilled = "1".Equals(parameterStrings[4]);
                    //  Marker size
                    int markerSize = 0;
                    if (parameterStrings.Length > 5)
                        int.TryParse(parameterStrings[5], out markerSize);
                    if (markerSize <= 0)
                        markerSize = 6;
                    sharedMarkerTypes[i].MarkerColor = col;
                    sharedMarkerTypes[i].LineColor = col;
                    sharedMarkerTypes[i].IsMarkerFilled = isFilled;
                    sharedMarkerTypes[i].MarkerSize = markerSize;
                    sharedMarkerTypes[i].MarkerShape = shape;
                    sharedMarkerTypes[i].LineDashStyle = style;
                    sharedMarkerTypes[i].Width = width;
                }

                // fixed style
                sharedMarkerTypes[10].MarkerShape = MarkerShape.Circle;
                sharedMarkerTypes[10].MarkerColor = ColorDescriptor.Black;
                sharedMarkerTypes[10].LineColor = ColorDescriptor.Black;
                sharedMarkerTypes[10].Width = 1;
                sharedMarkerTypes[10].LineDashStyle = DashStyleDescriptor.Dash;
                sharedMarkerTypes[10].IsMarkerFilled = false;
                sharedMarkerTypes[10].MarkerSize = 6;
            }
        }

        public static void SaveFlags()
        {
            Settings.Default.BlackAndWhite = defaultAllBlack;
            Settings.Default.BoxAxes = defaultBoxAxes;

            SaveSettings(Settings.Default);
        }

        public static void SaveFonts()
        {
            Settings.Default.LabelFont = DefaultLabelFont.ToString();
            Settings.Default.TitleFont = DefaultTitleFont.ToString();

            SaveSettings(Settings.Default);
        }

        public static void SaveMarkerTypes()
        {
            StringBuilder savedSettings = new();
            for (int i = 0; i <= 9; i++)
            {
                if (i > 0)
                {
                    savedSettings.Append("|");
                }
                //  Shape
                savedSettings.Append(Convert.ToInt32(sharedMarkerTypes[i].MarkerShape).ToString(CultureInfo.InvariantCulture));
                savedSettings.Append(";");

                // Colour.  TODO: Line colour.
                ColorDescriptor col = sharedMarkerTypes[i].MarkerColor;
                savedSettings.Append(col.R.ToString(CultureInfo.InvariantCulture));
                savedSettings.Append(",");
                savedSettings.Append(col.G.ToString(CultureInfo.InvariantCulture));
                savedSettings.Append(",");
                savedSettings.Append(col.B.ToString(CultureInfo.InvariantCulture));
                savedSettings.Append(";");
                savedSettings.Append(sharedMarkerTypes[i].Width.ToString(CultureInfo.InvariantCulture));
                savedSettings.Append(";");

                //  Line style
                savedSettings.Append(Convert.ToInt32(sharedMarkerTypes[i].LineDashStyle).ToString(CultureInfo.InvariantCulture));
                savedSettings.Append(";");

                //  Filled (1/0)
                savedSettings.Append(sharedMarkerTypes[i].IsMarkerFilled ? "1" : "0");
                savedSettings.Append(";");

                //  Marker size
                savedSettings.Append(sharedMarkerTypes[i].MarkerSize.ToString(CultureInfo.InvariantCulture));
            }
            Settings.Default.Markers = savedSettings.ToString();
            SaveSettings(Settings.Default);
        }

        private static void InitFirstMarkerTypes()
        {
            sharedMarkerTypes[0].MarkerShape = MarkerShape.Circle;
            sharedMarkerTypes[0].MarkerColor = ColorDescriptor.FromArgb(64, 105, 156);
            sharedMarkerTypes[0].LineColor = ColorDescriptor.FromArgb(64, 105, 156);
            sharedMarkerTypes[0].LineDashStyle = DashStyleDescriptor.Solid;

            sharedMarkerTypes[1].MarkerShape = MarkerShape.Square;
            sharedMarkerTypes[1].MarkerColor = ColorDescriptor.FromArgb(158, 65, 62);
            sharedMarkerTypes[1].LineColor = ColorDescriptor.FromArgb(158, 65, 62);
            sharedMarkerTypes[1].LineDashStyle = DashStyleDescriptor.Dash;

            sharedMarkerTypes[2].MarkerShape = MarkerShape.Triangle;
            sharedMarkerTypes[2].MarkerColor = ColorDescriptor.FromArgb(127, 154, 72);
            sharedMarkerTypes[2].LineColor = ColorDescriptor.FromArgb(127, 154, 72);
            sharedMarkerTypes[2].LineDashStyle = DashStyleDescriptor.Dot;

            sharedMarkerTypes[3].MarkerShape = MarkerShape.Plus;
            sharedMarkerTypes[3].MarkerColor = ColorDescriptor.FromArgb(105, 81, 133);
            sharedMarkerTypes[3].LineColor = ColorDescriptor.FromArgb(105, 81, 133);
            sharedMarkerTypes[3].LineDashStyle = DashStyleDescriptor.DashDot;

            sharedMarkerTypes[4].MarkerShape = MarkerShape.Cross;
            sharedMarkerTypes[4].MarkerColor = ColorDescriptor.FromArgb(60, 141, 163);
            sharedMarkerTypes[4].LineColor = ColorDescriptor.FromArgb(60, 141, 163);
            sharedMarkerTypes[4].LineDashStyle = DashStyleDescriptor.Solid;

            sharedMarkerTypes[5].MarkerShape = MarkerShape.CircleLine;
            sharedMarkerTypes[5].MarkerColor = ColorDescriptor.FromArgb(204, 123, 56);
            sharedMarkerTypes[5].LineColor = ColorDescriptor.FromArgb(204, 123, 56);
            sharedMarkerTypes[5].LineDashStyle = DashStyleDescriptor.Dash;

            sharedMarkerTypes[6].MarkerShape = MarkerShape.SquareLine;
            sharedMarkerTypes[6].MarkerColor = ColorDescriptor.FromArgb(79, 129, 189);
            sharedMarkerTypes[6].LineColor = ColorDescriptor.FromArgb(79, 129, 189);
            sharedMarkerTypes[6].LineDashStyle = DashStyleDescriptor.Dot;

            sharedMarkerTypes[7].MarkerShape = MarkerShape.SquareCross;
            sharedMarkerTypes[7].MarkerColor = ColorDescriptor.FromArgb(192, 80, 77);
            sharedMarkerTypes[7].LineColor = ColorDescriptor.FromArgb(192, 80, 77);
            sharedMarkerTypes[7].LineDashStyle = DashStyleDescriptor.DashDot;

            sharedMarkerTypes[8].MarkerShape = MarkerShape.Circle;
            sharedMarkerTypes[8].MarkerColor = ColorDescriptor.FromArgb(155, 187, 89);
            sharedMarkerTypes[8].LineColor = ColorDescriptor.FromArgb(155, 187, 89);
            sharedMarkerTypes[8].LineDashStyle = DashStyleDescriptor.Solid;

            sharedMarkerTypes[9].MarkerShape = MarkerShape.Square;
            sharedMarkerTypes[9].MarkerColor = ColorDescriptor.FromArgb(128, 100, 162);
            sharedMarkerTypes[9].LineColor = ColorDescriptor.FromArgb(128, 100, 162);
            sharedMarkerTypes[9].LineDashStyle = DashStyleDescriptor.Dash;

            // fixed style
            sharedMarkerTypes[10].MarkerShape = MarkerShape.Circle;
            sharedMarkerTypes[10].MarkerColor = ColorDescriptor.Black;
            sharedMarkerTypes[10].LineColor = ColorDescriptor.Black;
            sharedMarkerTypes[10].LineDashStyle = DashStyleDescriptor.Dash;

            foreach (MarkerType mt in sharedMarkerTypes)
            {
                mt.Width = 1;
                mt.MarkerSize = 6;
            }
            SaveMarkerTypes();
        }

        private static void InitFlags()
        {
            defaultBoxAxes = Settings.Default.BoxAxes;
            defaultAllBlack = Settings.Default.BlackAndWhite;
        }

        private static void InitFonts()
        {
            //  Title
            string savedTitleFont = Settings.Default.TitleFont;

            if (savedTitleFont == null || !FontDescriptor.TryParse(savedTitleFont, out FontDescriptor savedTitleFontDescriptor))
            {
                InitFirstFonts();
            }
            else
            {
                DefaultTitleFont = savedTitleFontDescriptor;
                string savedLabelFont = Settings.Default.LabelFont;
                FontDescriptor.TryParse(savedLabelFont, out FontDescriptor savedLabelFontDescriptor);
                DefaultAxisLabelFont = savedLabelFontDescriptor;
                DefaultAxisTitleFont = savedLabelFontDescriptor;
                DefaultLabelFont = savedLabelFontDescriptor;
                DefaultLegendFont = savedLabelFontDescriptor;
            }
        }

        private static void SaveSettings(Settings s)
        {
            s.Save();
        }


        public static void PushAndCloneMarkerTypes()
        {
            MarkerType[] originalMarkerTypes = sharedMarkerTypes;
            sharedMarkerTypes = new MarkerType[sharedMarkerTypes.Length];
            for (int i = 0; i < sharedMarkerTypes.Length; i++)
                sharedMarkerTypes[i] = originalMarkerTypes[i].Clone();
            if (null == markerTypeStack)
                markerTypeStack = new Stack<MarkerType[]>();
            markerTypeStack.Push(originalMarkerTypes);
        }

        public static void PopMarkerTypes()
        {
            if (null != markerTypeStack && markerTypeStack.Count > 0)
                sharedMarkerTypes = markerTypeStack.Pop();
        }
    }
}
