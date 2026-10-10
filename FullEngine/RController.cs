using Antlr4.Runtime;
using StatsDirect.Templates;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;

namespace StatsDirect.R
{
    /// <summary>
    /// The Mac host of the engine's R script steps. LOESS curve fitting and method comparison regression define their
    /// calculation as &lt;script language="R"&gt;: the engine's ScriptEngine.RunR writes the parameters as R variables,
    /// starts R through this class, waits for it (killing it if the user cancels) and reads the results back. Windows finds
    /// R in the registry, runs Rscript.exe in My Documents\StatsDirect\R and takes each chart back as a metafile. Here
    /// Rscript is found where the CRAN installer, Homebrew or the user put it; every run has its own folder under
    /// Application Support, beside the shell's R sessions, so nothing is shared between runs; the script's Windows metafile
    /// device is shimmed to R's quartz PNG device, which needs no XQuartz (Windows 5.1.0 reads the picture with System.Drawing);
    /// the chart reaches the HTML report as a ReportPicture and the script as text, as on Windows. Packages a script installs go
    /// to one shared library folder.
    /// </summary>
    public static class RController
    {
        const string RSCRIPT_NAME = "script.r";
        const string RESULTS_FILE_NAME = "results.txt";
        const string ERROR_FILE_NAME = "error.txt";
        public const string NotInstalledMessage = "R is not installed. Choose R ▸ Install R… from the menu bar, or install R from cran.r-project.org, then run this analysis again.";
        static readonly string[] Candidates = { "/Library/Frameworks/R.framework/Resources/bin/Rscript", "/opt/homebrew/bin/Rscript", "/usr/local/bin/Rscript" };

        /// <summary>Where runs and the package library live. STATSDIRECT_R_FOLDER overrides it (tests use a temporary folder).</summary>
        public static string SupportFolder
        {
            get
            {
                string folder = Environment.GetEnvironmentVariable("STATSDIRECT_R_FOLDER");
                return string.IsNullOrEmpty(folder) ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Library", "Application Support", "StatsDirect Viewer") : folder;
            }
        }
        public static string RunsFolder => Path.Combine(SupportFolder, "R Operations");
        public static string LibraryFolder => Path.Combine(SupportFolder, "R Library");

        sealed class Run
        {
            public string Folder;
            public Process Process;
            public readonly StringBuilder Stderr = new();
        }
        // ScriptEngine.RunR starts R, waits and reads the results on the thread that runs the operation.
        [ThreadStatic] static Run current;

        /// <summary>
        /// Rscript: STATSDIRECT_RSCRIPT if it is set (a path that does not exist means "not installed", which tests use), then
        /// the CRAN framework, Homebrew and /usr/local, then PATH. Null when R is not installed.
        /// </summary>
        public static string FindRscript()
        {
            string env = Environment.GetEnvironmentVariable("STATSDIRECT_RSCRIPT");
            if (!string.IsNullOrEmpty(env))
                return File.Exists(env) ? env : null;
            foreach (string candidate in Candidates)
                if (File.Exists(candidate))
                    return candidate;
            foreach (string dir in (Environment.GetEnvironmentVariable("PATH") ?? string.Empty).Split(':'))
            {
                if (dir.Length == 0)
                    continue;
                string candidate = Path.Combine(dir, "Rscript");
                if (File.Exists(candidate))
                    return candidate;
            }
            return null;
        }

        public static bool IsInstalled => FindRscript() != null;

        // The engine's scripts draw their charts with R's svg device. CRAN's R for the Mac needs XQuartz for that device
        // (its cairo library links X11), so the chart is drawn by the svglite package instead, installed from CRAN into
        // the shared library the first time it is needed; its SVG carries a viewBox and Arial text like the engine's own.
        // A script that still opens the Windows metafile device gets R's quartz PNG device at 144 dots per inch.
        const string GraphicsShim = @"# StatsDirect for Mac: charts go into the report as SVG drawn by svglite (R's own svg device needs XQuartz here)
svg <- function(filename = """", width = 7, height = 7, ...) {
  if (!requireNamespace(""svglite"", quietly = TRUE))
    utils::install.packages(""svglite"", lib = rlib, repos = ""https://cloud.r-project.org"", quiet = TRUE, type = ""binary"")
  svglite::svglite(filename, width = width, height = height)
}
win.metafile <- function(filename = """", width = 7, height = 7, ...) {
  png <- sub(""\\.wmf$"", "".png"", filename, ignore.case = TRUE)
  tryCatch(grDevices::png(png, width = width, height = height, units = ""in"", res = 144, type = ""quartz""),
           error = function(e) grDevices::png(png, width = width, height = height, units = ""in"", res = 144))
}";

        // A parameter whose value R cannot take (a list, for instance) is written by RConvert as a name with nothing after
        // the arrow, which would stop R before the script ran. Windows passes the same bag; leave such lines out.
        static readonly Regex Unconvertible = new(@"^[A-Za-z._][A-Za-z0-9._]* <- *$", RegexOptions.Multiline);

        /// <param name="host">Unused here (Windows shows its install dialog over the host window).</param>
        /// <param name="scriptBody">The operation's script, after the parameters written as R variables.</param>
        /// <param name="reportScriptBody">What the report shows under "R script to reproduce this result": the script as it can be run again, as plain text.</param>
        public static Process RunScriptAndQuit(ITemplateHost host, string scriptBody, out string reportScriptBody)
        {
            string rscript = FindRscript() ?? throw new InvalidOperationException(NotInstalledMessage);
            Directory.CreateDirectory(LibraryFolder);
            Prune();
            var run = new Run { Folder = Path.Combine(RunsFolder, Guid.NewGuid().ToString("N")) };
            Directory.CreateDirectory(run.Folder);
            current = run;
            string body = Unconvertible.Replace(scriptBody.Replace("\r\n", "\n").Replace('\r', '\n'), "# (a parameter that R cannot take was left out)");
            string head = "userdir <- " + RQuote(run.Folder) + "\nrlib <- " + RQuote(LibraryFolder)
                + "\ndir.create(rlib, recursive = TRUE, showWarnings = FALSE)\nsetwd(userdir)\n.libPaths(c(rlib, .libPaths()))";
            // The script the report shows can be run again as it is: without the shim and the message sink, which are this host's.
            reportScriptBody = head + "\n" + body;
            string script = head + "\n" + GraphicsShim + "\nzz <- file(" + RQuote(ERROR_FILE_NAME) + ", open = \"wt\")\nsink(zz, type = \"message\")\nreturning.to.statsdirect <- TRUE\n" + body + "\nquit()\n";
            string scriptPath = Path.Combine(run.Folder, RSCRIPT_NAME);
            File.WriteAllText(scriptPath, script, new UTF8Encoding(false));
            var startInfo = new ProcessStartInfo
            {
                FileName = rscript,
                WorkingDirectory = run.Folder,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardError = true,
                RedirectStandardOutput = true
            };
            startInfo.ArgumentList.Add("--vanilla");
            startInfo.ArgumentList.Add("--encoding=UTF-8");
            startInfo.ArgumentList.Add(scriptPath);
            var process = Process.Start(startInfo);
            run.Process = process;
            // R's own messages before the sink starts (a syntax error, a missing package) come on stderr; what the script prints is not needed.
            process.ErrorDataReceived += (_, e) => { if (e.Data != null) lock (run.Stderr) run.Stderr.AppendLine(e.Data); };
            process.OutputDataReceived += (_, _) => { };
            process.BeginErrorReadLine();
            process.BeginOutputReadLine();
            return process;
        }

        /// <summary>Windows asks the user to install R here. The Mac shell installs R from its own menu, so the operation stops with that advice.</summary>
        public static bool UserMightHaveInstalledR()
        {
            throw new InvalidOperationException(NotInstalledMessage);
        }

        internal static ParameterBag FilesToParameterBag()
        {
            Run run = current ?? throw new InvalidOperationException("No R script has been run on this thread.");
            try
            {
                run.Process?.WaitForExit();
                string resultsPath = Path.Combine(run.Folder, RESULTS_FILE_NAME);
                if (!File.Exists(resultsPath))
                    throw new InvalidOperationException("R finished without writing its results.");
                using Stream s = File.OpenRead(resultsPath);
                AntlrInputStream input = new(s);
                RResultsLexer lexer = new(input);
                CommonTokenStream tokenStream = new(lexer);
                RResultsParser parser = new(tokenStream);
                RResultsParser.CompileUnitContext retval = parser.compileUnit();
                if (parser.NumberOfSyntaxErrors > 0)
                    throw new InvalidOperationException("The results R wrote could not be read: " + parser.NumberOfSyntaxErrors + " error(s)");
                // The parser seems to dislike recognising EOF (for some reason - TODO: find out why) so instead test that we're at EOF at the end of the parse
                if (!"<EOF>".Equals(parser.CurrentToken.Text))
                    throw new InvalidOperationException("The results R wrote could not be read near \"" + parser.CurrentToken.Text + "\"");
                return DictionaryToParameterBag(retval.Values);
            }
            finally
            {
                Finish(run);
            }
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
                if (pair.Value is TitleAndValue tv)
                    thisBag.AddOutput(leafName, RConvert.ToFrame(leafName, tv.Title, (List<object>)tv.Value));
                else
                    thisBag.AddOutput(leafName, pair.Value);
            }
            return outputParameters;
        }

        /// <summary>
        /// Why R stopped: what it wrote to its message sink (the error, after any warnings), or what it printed on stderr before
        /// the sink started. Null when nothing was recorded.
        /// </summary>
        public static string GetErrorText()
        {
            Run run = current;
            if (run == null)
                return null;
            try
            {
                run.Process?.WaitForExit();
                string text = null;
                string errorPath = Path.Combine(run.Folder, ERROR_FILE_NAME);
                if (File.Exists(errorPath))
                    text = File.ReadAllText(errorPath);
                if (string.IsNullOrWhiteSpace(text))
                    lock (run.Stderr) text = run.Stderr.ToString();
                text = (text ?? string.Empty).Replace("\r", string.Empty).Replace("Execution halted", string.Empty).Trim();
                return text.Length == 0 ? null : "R reported: " + text;
            }
            finally
            {
                Finish(run);
            }
        }

        /// <summary>
        /// Called by the host when an operation ends. A run that was cancelled (ScriptEngine.RunR kills R and throws without
        /// reading anything back) or that failed before its results were read is stopped and its folder removed.
        /// </summary>
        public static void Abandon()
        {
            Run run = current;
            if (run == null)
                return;
            try { if (run.Process != null && !run.Process.HasExited) run.Process.Kill(true); } catch (Exception) { }
            Finish(run);
        }

        static void Finish(Run run)
        {
            if (ReferenceEquals(current, run))
                current = null;
            if (!string.IsNullOrEmpty(Environment.GetEnvironmentVariable("STATSDIRECT_R_KEEP")))
                return;
            try { Directory.Delete(run.Folder, true); } catch (Exception) { }
        }

        // Runs that a crash or a force-quit left behind.
        static void Prune()
        {
            try
            {
                if (!Directory.Exists(RunsFolder))
                    return;
                foreach (string folder in Directory.GetDirectories(RunsFolder))
                    if (Directory.GetLastWriteTimeUtc(folder) < DateTime.UtcNow.AddDays(-1))
                        try { Directory.Delete(folder, true); } catch (Exception) { }
            }
            catch (Exception) { }
        }

        static string RQuote(string unquoted) => "\"" + unquoted.Replace("\\", "\\\\").Replace("\"", "\\\"") + "\"";
    }
}
