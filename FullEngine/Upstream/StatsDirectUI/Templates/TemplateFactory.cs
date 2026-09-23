using StatsDirect.Configuration;
using StatsDirect.UI.Properties;
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Threading;

namespace StatsDirect.Templates
{
    public static class TemplateFactory
    {
        private static IDictionary<string, Operation> operations;
        private static IList<Operation> userOperations;
        private static readonly object lockObject = new();
        private static bool loading;

        public static IDictionary<string, Operation> Operations
        {
            get
            {
                if (null == operations && !loading)
                    LoadOperations();
                lock (lockObject)
                {
                    return operations;
                }
            }
        }

        public static IList<Operation> UserOperations
        {
            get
            {
                if (null == userOperations && !loading)
                    LoadOperations();
                lock (lockObject)
                {
                    return userOperations;
                }
            }
        }

        /// <summary>
        /// Notify the factory to start loading operations and user operations on a background thread.
        /// </summary>
        public static void LoadOperationsAsync()
        {
            loading = true;
            new Thread(BackgroundLoader).Start();
        }

        private static void BackgroundLoader(object obj)
        {
            LoadOperations();
        }

        /// <summary>
        /// Load all the menu and user operations
        /// </summary>
        private static void LoadOperations()
        {
            lock (lockObject)
            {
                Dictionary<string, Exception> loadErrors = new();
                operations = new Dictionary<string, Operation>();
                System.Xml.Serialization.XmlSerializer s = new(typeof(Operation));
                DirectoryInfo di = new(Path.Combine(SDConfiguration.InstallationDirectory, Settings.Default.OperationsDirectory));
                FileInfo[] knownOperations = di.GetFiles();
                foreach (FileInfo info in knownOperations)
                {
                    // Asking a DirectoryInfo for all files of the pattern "*.xml" gets eg. "scatter.xml~" - so we do it the hard way.
                    if (".xml".Equals(info.Extension.ToLower(CultureInfo.InvariantCulture)))
                    {
                        try
                        {
                            TextReader fs = info.OpenText();
                            Operation o = (Operation)s.Deserialize(fs);
                            operations.Add(o.Name, o);
                            fs.Close();
                            o.FixAfterLoading();
                        }
                        catch (Exception ex)
                        {
                            loadErrors[info.Name] = ex;
#if WATCH_EXCEPTIONS
                            throw;
#endif
                        }
                    }
                }

                userOperations = new List<Operation>();
                string userOperationDir = Path.Combine(SDConfiguration.InstallationDirectory, Settings.Default.UserOperationsDirectory);
                if (Directory.Exists(userOperationDir))
                {
                    di = new DirectoryInfo(userOperationDir);
                    knownOperations = di.GetFiles();
                    foreach (FileInfo info in knownOperations)
                    {
                        // Asking a DirectoryInfo for all files of the pattern "*.xml" gets eg. "scatter.xml~" - so we do it the hard way.
                        if (".xml".Equals(info.Extension.ToLower(CultureInfo.InvariantCulture)))
                        {
                            TextReader fs = info.OpenText();
                            Operation o = (Operation)s.Deserialize(fs);
                            fs.Close();
                            o.FixAfterLoading();
                            userOperations.Add(o);
                        }
                    }
                }
                loading = false;
            }
        }
    }
}
