using Antlr4.Runtime;
using Microsoft.Win32;
using StatsDirect.Configuration;
using StatsDirect.Templates;
using StatsDirect.UI;
using StatsDirect.Utilities;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;

namespace StatsDirect.R
{
    public static class RController
    {
        const string RSCRIPT_EXE_NAME = "Rscript.exe";
        const string RSCRIPT_NAME = "script.r";
        const string RESULTS_FILE_NAME = "results.txt";
        const string ERROR_FILE_NAME = "error.txt";
        const string SCRIPT_HEAD = "userdir<-\"{0}\"\r\nlibdir<-\"Lib\"\r\nrlib=file.path(userdir, libdir)\r\ndir.create(rlib,recursive=T,showWarnings=F)\r\nsetwd(file.path(userdir))\r\n.libPaths(c(rlib, .libPaths()))";
        const string STATSDIRECT_HEAD = "zz <- file(\"{0}\", open = \"wt\")\r\nsink(zz, type = \"message\")\r\nreturning.to.statsdirect <- TRUE";
        /// <summary>
        /// Checks whether R is installed and, if so, what versions.
        /// </summary>
        public static List<RVersion> CheckR()
        {
            string[] rLocations = { @"Software\R-core\R", @"Software\R-core\R64" };
            List<RVersion> installedVersions = new();
            try
            {
                using RegistryKey hklm = Registry.LocalMachine;
                foreach (string rLocation in rLocations)
                {
                    using RegistryKey rKey = hklm.OpenSubKey(rLocation);
                    foreach (string version32 in rKey.GetSubKeyNames())
                    {
                        using RegistryKey versionKey = rKey.OpenSubKey(version32);
                        object installPathObject = versionKey.GetValue("InstallPath");
                        if (null != installPathObject)
                        {
                            bool isX64 = rLocation.EndsWith("64");
                            string installPath = (string)installPathObject;
                            RVersion version = new() { IsX64 = isX64, VersionString = version32, InstallPath = installPath };
                            // Probe for a binary there to check it's still around and hasn't been uninstalled/deleted
                            string binaryPath = Path.Combine(version.BinPath, "Rscript.exe");
                            if (File.Exists(binaryPath))
                                installedVersions.Add(version);
                        }
                    }
                }
            }
            catch (Exception)
            {
                // Return whatever we have
            }
            return installedVersions;
        }

        /// <summary>
        /// Rules: Prefer highest version, then highest bitness
        /// </summary>
        /// <returns></returns>
        public static RVersion PreferredRVersion()
        {
            ICollection<RVersion> candidates = CheckR();
            RVersion preferred = null;
            foreach (RVersion candidate in candidates)
                if (candidate.CompareTo(preferred) > 0)
                    preferred = candidate;
            return preferred;
        }

        /// <param name="scriptBody"></param>
        /// <param name="rtfScriptBody">A version of the script body that contains everything necessary to run the script, suitable for emitting into an RTF report window.</param>
        /// <param name="host"></param>
        /// <returns> <code>true</code> if the script appears to have been run successfully, <code>false</code> otherwise.</returns>
        public static Process RunScriptAndQuit(ITemplateHost host, string scriptBody, out string rtfScriptBody)
        {
            string rFolder = SDConfiguration.MyStatsDirectRFolder;
            // Just in case this is the first time the user has run an R script.  TODO: Is there a more sensible place for this?
            if (!Directory.Exists(rFolder))
                Directory.CreateDirectory(rFolder);
            string scriptPath = Path.Combine(rFolder, RSCRIPT_NAME);

            // We get a right mix of terminations at this point; we need Windows newlines in order to match the rest of the file format and meet the requirement to be openable in Notepad.
            string repairedScriptBody = scriptBody
                .Replace("\r", string.Empty)
                .Replace("\n", "\r\n");
            rtfScriptBody = (string.Format(SCRIPT_HEAD, rFolder.Replace(@"\", @"\\")) + "\r\n" + repairedScriptBody)
                .Replace(@"\", @"\\")
                .Replace("{", @"\{")
                .Replace("}", @"\}")
                .Replace("\n", "\n\\par ");

            using (TextWriter tw = new StreamWriter(scriptPath, false, new UTF8Encoding(false)))
            {
                tw.Write(SCRIPT_HEAD, rFolder.Replace(@"\", @"\\"));
                tw.WriteLine();
                tw.Write(STATSDIRECT_HEAD, ERROR_FILE_NAME);
                tw.WriteLine();
                tw.WriteLine(repairedScriptBody);
                tw.WriteLine("quit()");
            }

            string errorFilePath = Path.Combine(rFolder, ERROR_FILE_NAME);
            if (File.Exists(errorFilePath))
                File.Delete(errorFilePath);

            // TODO: Probably don't do this per-script in the future.
            RVersion preferredVersion = PreferredRVersion();
            while (null == preferredVersion)
            {
                if (!UserMightHaveInstalledR())
                    throw new TemplateOperationCancelledException();
                preferredVersion = PreferredRVersion();
            }

            ProcessStartInfo startInfo = new()
            {
                FileName = Path.Combine(preferredVersion.BinPath, RSCRIPT_EXE_NAME),
                WorkingDirectory = rFolder,
                Arguments = $"--vanilla --encoding=UTF-8 \"{scriptPath}\"",
                CreateNoWindow = true,
                UseShellExecute = false
            };

            //  Rscript.exe is not DPI-aware, so on a scaled display Windows tells it the screen is 96 dpi while the metafile it records is framed against the
            //  display's true resolution: at 225% R draws its chart into the top left 40% of the picture and leaves the rest blank.  This compatibility layer
            //  makes Windows give R the real figures, so the drawing fills its frame.  Any layers already set for this process are kept.
            const string compatLayerVariable = "__COMPAT_LAYER";
            const string highDpiAwareLayer = "HighDpiAware";
            //  (TryGetValue, because the indexer throws when the variable is not set, which is the normal case.)
            startInfo.Environment.TryGetValue(compatLayerVariable, out string existingLayers);
            if (string.IsNullOrWhiteSpace(existingLayers))
                startInfo.Environment[compatLayerVariable] = highDpiAwareLayer;
            else if (existingLayers.IndexOf(highDpiAwareLayer, StringComparison.OrdinalIgnoreCase) < 0)
                startInfo.Environment[compatLayerVariable] = existingLayers + " " + highDpiAwareLayer;

            return Process.Start(startInfo);
        }

        /// <summary>
        /// If necessary, prompt the user to install R.  Return true if we think the user might have installed R successfully, or false if there's no chance (for example, the user's told us that they're not going to)
        /// </summary>
        /// <returns></returns>
        public static bool UserMightHaveInstalledR()
        {
            using frmInstallR f = new();
            f.ShowDialog(SdApplication.SoleInstance.DialogOwner);
            return f.UserThinksRIsInstalled;
        }

        internal static ParameterBag FilesToParameterBag()
        {
            string rFolder = SDConfiguration.MyStatsDirectRFolder;
            string resultsPath = Path.Combine(rFolder, RESULTS_FILE_NAME);
            using Stream s = File.OpenRead(resultsPath);
            AntlrInputStream input = new(s);
            RResultsLexer lexer = new(input);
            CommonTokenStream tokenStream = new(lexer);
            RResultsParser parser = new(tokenStream);
            RResultsParser.CompileUnitContext retval = parser.compileUnit();
            if (parser.NumberOfSyntaxErrors > 0)
            {
                throw new Exception("Couldn't parse file: " + parser.NumberOfSyntaxErrors + " error(s)");
            }
            // The parser seems to dislike recognising EOF (for some reason - TODO: find out why) so instead test that we're at EOF at the end of the parse
            if (!"<EOF>".Equals(parser.CurrentToken.Text))
                throw new Exception("Couldn't parse file: syntax error near \"" + parser.CurrentToken.Text + "\"");
            //if (null == retval || null == retval.builtExpression)
            //    throw new Exception("Syntax error");
            return DictionaryToParameterBag(retval.Values);
        }

        /// <summary>
        /// Split a string of the form name$name$name so that each non-leaf name becomes a dictionary named in that way inside the current dictionary, and the leaf name is returned.
        /// </summary>
        private static ParameterBag GetBag(string nameToParse, ParameterBag current, out string leafName)
        {
            int pos = nameToParse.IndexOf('$');
            if (pos < 0)
            {
                // No more $ signs; we're at a leaf
                leafName = nameToParse;
                return current;
            }

            // A branch
            string branchName = "*" + nameToParse.Substring(0, pos);
            string rhs = nameToParse.Substring(pos + 1);
            // Branches always have indexed lists of bags as immediate children
            IList<ParameterBag> child;
            if (current.ContainsKey(branchName))
            {
                child = current[branchName].AsParameterBagList;
            }
            else
            {
                child = new List<ParameterBag>();
                current.AddOutput(branchName, child);
            }
            // The next name in the list might be non-numeric (it's the name of the next bag level at index 0 of this bag) or numeric (it's the index of a bag at this level).  Find the bag, creating as necessary.
            int nextPos = rhs.IndexOf('$');
            ParameterBag subBag;
            if (nextPos < 0 || !int.TryParse(rhs.Substring(0, nextPos), out int bagIndex))
            {
                // No $: Next is a leaf; we need to put the leaf into index 0
                // $ but non-numeric: Next is a branch; we need to put the leaf into index 0
                if (child.Count == 0)
                    child.Add(new ParameterBag());
                subBag = child[0];
            }
            else
            {
                // $ and next is numeric: We need to offset to that bag in the current list, creating any bags we're missing.  Note that R indices are 1-based, C# indices are 0-based.
                while (child.Count < bagIndex)
                    child.Add(new ParameterBag());
                subBag = child[bagIndex - 1];
                rhs = rhs.Substring(nextPos + 1);
            }
            // Search down the branch
            return GetBag(rhs, subBag, out leafName);
        }

        private static ParameterBag DictionaryToParameterBag(Dictionary<string, object> dictionary)
        {
            ParameterBag outputParameters = new();
            foreach (KeyValuePair<string, object> pair in dictionary)
            {
                ParameterBag thisBag = GetBag(pair.Key, outputParameters, out string leafName);
                if (pair.Value is TitleAndValue)
                {
                    TitleAndValue tv = (TitleAndValue)pair.Value;
                    thisBag.AddOutput(leafName, RConvert.ToFrame(leafName, tv.Title, (List<object>)tv.Value));
                }
                else
                    thisBag.AddOutput(leafName, pair.Value);
            }
            return outputParameters;
        }

        /// <summary>
        /// Returns the most recent error text from R.
        /// </summary>
        /// <returns>The most recent error text, or null if no error text could be retrieved</returns>
        public static string GetErrorText()
        {
            string rFolder = SDConfiguration.MyStatsDirectRFolder;
            string errorFilePath = Path.Combine(rFolder, ERROR_FILE_NAME);
            if (!File.Exists(errorFilePath))
                return null;

            using TextReader tr = new StreamReader(errorFilePath);
            return tr.ReadToEnd().Replace("\r", string.Empty);
        }
    }
}
