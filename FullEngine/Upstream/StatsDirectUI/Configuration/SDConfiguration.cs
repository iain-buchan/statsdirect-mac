using System;
using System.IO;
using StatsDirect.UI.Properties;
using System.Reflection;

namespace StatsDirect.Configuration
{
    public static class SDConfiguration
    {
        private const string STATSDIRECT_FOLDER_NAME = "StatsDirect";
        private const string R_FOLDER_NAME = "R";
        public const string PERSISTENT_VALUE_FILE_NAME = "session.ser";
        private const string HELP_FILE_NAME = "statsdirect.chm";
        private const string SETTINGS_FILE_NAME = "statsdirect.json";

        public static string HelpFilePath => Path.Combine(InstallationDirectory, HELP_FILE_NAME);

        public static string TemplatePath => Path.Combine(InstallationDirectory, Settings.Default.TemplateDirectory);

        public static string MyStatsDirectFolder => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), STATSDIRECT_FOLDER_NAME);

        public static string MyStatsDirectRFolder => Path.Combine(MyStatsDirectFolder, R_FOLDER_NAME);

        public static string MyTestFilePath => Path.Combine(MyStatsDirectFolder, Settings.Default.DefaultRecentlyUsedFile);

        public static string InstallationDirectory => Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);

        public static string SettingsPath => Path.Combine(MyStatsDirectFolder, SETTINGS_FILE_NAME);
    }
}
