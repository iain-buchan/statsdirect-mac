using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Text;
using System.IO;
using System.Reflection;
using StatsDirect.R;
using StatsDirect.Templates;
using StatsDirect.Utilities;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.VisualBasic;
using Microsoft.CodeAnalysis.Emit;
using Microsoft.CodeAnalysis;
using System.Linq;

namespace StatsDirect.TemplateProcessing
{
    public sealed class ScriptEngine : IScriptEngine
    {
        private static readonly IEnumerable<MetadataReference> cSharpMetadataReferences;
        private static readonly IEnumerable<MetadataReference> visualBasicMetadataReferences;

        static ScriptEngine()
        {
            cSharpMetadataReferences = new MetadataReferenceGatherer(true)
                .AddAssembly("Microsoft.CSharp.dll")
                .MetadataReferences;
            visualBasicMetadataReferences = new MetadataReferenceGatherer(true)
                .AddAssembly("Microsoft.VisualBasic.dll")
                .MetadataReferences;
        }

        private const string CSHARP = "CSharp";
        private const string CHASH = "C#";
        private const string CHASHLOWER = "c#";
        private const string R = "R";
        private const string VISUALBASIC = "VB";
        private const string VISUALBASICLOWER = "vb";

        private class CompiledScript
        {
            public object Instance;
            public MethodInfo MethodInfo;
        };

        private static Dictionary<string, Dictionary<string, CompiledScript>> compiledScripts;

        public ScriptEngine()
        {
            if (null == compiledScripts)
                compiledScripts = new Dictionary<string, Dictionary<string, CompiledScript>>();
        }

        /// <summary>
        /// Runs the script's step entry point.  If it doesn't have one, throws an exception.
        /// </summary>
        /// <returns>Whatever the script returned</returns>
        object IScriptEngine.Run(string scriptLanguage, string code, ScriptType scriptType, ITemplateHost host, ParameterBag parameters, Parameter parameter, string entryPoint)
        {
            switch (scriptLanguage)
            {
                case CSHARP:
                case CHASH:
                case CHASHLOWER:
                case VISUALBASIC:
                case VISUALBASICLOWER:
                    return RunDotNet(scriptLanguage, code, scriptType, host, parameters, parameter, entryPoint);
                case R:
                    return RunR(host, code, parameters);
                default:
                    throw new ArgumentOutOfRangeException(nameof(scriptLanguage), scriptLanguage, "Must be CSharp, R, VB");
            }
        }

        public static bool CanHandle(string scriptLanguage)
        {
            switch (scriptLanguage)
            {
                case CSHARP:
                case CHASH:
                case CHASHLOWER:
                case VISUALBASIC:
                case VISUALBASICLOWER:
                case R:
                    return true;
                default:
                    return false;
            }
        }

        private static object RunR(ITemplateHost host, string code, ParameterBag parameters)
        {
            StringBuilder sb = new();
            if (null != parameters)
            {
                foreach (KeyValuePair<string, FilledParameter> pair in parameters.Pairs)
                    RConvert.ToR(sb, pair.Key, pair.Value, FrameType.Wide);
            }
            sb.AppendLine(code);
            string modifiedCode = sb.ToString();
            using IProgressBar progress = host.StartProgress("Running R script", false);
            Process p = RController.RunScriptAndQuit(host, modifiedCode, out string codeForEmit);
            while (true)
            {
                bool exited = p.WaitForExit(50);
                if (exited)
                    break;
                if (progress.Update(0))
                {
                    p.Kill();
                    throw new TemplateOperationCancelledException();
                }
            }
            int exitCode = p.ExitCode;
            if (0 != exitCode)
                throw new Exception(RController.GetErrorText() ?? "R did not complete successfully and did not save an error message");
            else
            {
                ParameterBag pb = RController.FilesToParameterBag();
                pb.AddOutput("formattedRScript", codeForEmit);
                return pb;
            }
        }

        /// <summary>
        /// Runs the script's step entry point.  If it doesn't have one, throws an exception.
        /// </summary>
        /// <returns></returns>
        private static object RunDotNet(string scriptLanguage, string code, ScriptType scriptType, ITemplateHost host, ParameterBag parameters, Parameter parameter, string entryPoint)
        {
            CompiledScript compiledScript = null;
            // Look aside to the cache - do we already have this one?
            if (compiledScripts.ContainsKey(code))
            {
                Dictionary<string, CompiledScript> codeDic = compiledScripts[code];
                if (codeDic.ContainsKey(scriptLanguage))
                    compiledScript = codeDic[scriptLanguage];
            }

            if (null == compiledScript)
            {
                compiledScript = CompileDotNet(scriptLanguage, code, scriptType, entryPoint);
                if (!compiledScripts.ContainsKey(code))
                    compiledScripts.Add(code, new Dictionary<string, CompiledScript>());
                compiledScripts[code][scriptLanguage] = compiledScript;
            }
            try
            {
                object[] invokeParameters;
                switch (scriptType)
                {
                    case ScriptType.Validator:
                        invokeParameters = new object[] { host, parameters, parameter };
                        break;
                    default:
                        invokeParameters = new object[] { host, parameters };
                        break;
                }
                return compiledScript.MethodInfo.Invoke(compiledScript.Instance, invokeParameters);
            }
            catch (TargetInvocationException tie)
            {
                if (null != tie.InnerException)
                    throw tie.InnerException;
                throw;
            }
        }

        private static CompiledScript CompileDotNet(string scriptLanguage, string code, ScriptType scriptType, string entryPoint)
        {
            switch (scriptLanguage)
            {
                case CSHARP:
                case CHASH:
                case CHASHLOWER:
                    return CompileCSharp(code, scriptType, entryPoint);
                case VISUALBASIC:
                case VISUALBASICLOWER:
                    return CompileVisualBasic(code, scriptType, entryPoint);
                default:
                    throw new ArgumentOutOfRangeException(nameof(scriptLanguage), scriptLanguage, "Must be CSharp, VB");
            }
        }

        /// <summary>
        /// Compile the script.  Throw an exception if the compile fails.
        /// </summary>
        /// <returns></returns>
        private static CompiledScript CompileCSharp(string code, ScriptType scriptType, string entryPoint)
        {
            // Build up the source in sourceBuilder
            StringBuilder sourceBuilder = new();
            sourceBuilder.AppendLine("using System;");
            sourceBuilder.AppendLine("using System.Collections;");
            sourceBuilder.AppendLine("using System.Collections.Generic;");
            sourceBuilder.AppendLine("using System.Globalization;");
            sourceBuilder.AppendLine("using System.Linq;");
            sourceBuilder.AppendLine("using System.Text;");
            sourceBuilder.AppendLine("using StatsDirect.Builtins;");
            sourceBuilder.AppendLine("using StatsDirect.Data;");
            sourceBuilder.AppendLine("using StatsDirect.Numerics;");
            sourceBuilder.AppendLine("using StatsDirect.R;");
            sourceBuilder.AppendLine("using StatsDirect.Templates;");
            sourceBuilder.AppendLine("using StatsDirect.Utilities;");
            sourceBuilder.AppendLine("namespace StatsDirect.Templates {");
            sourceBuilder.AppendLine("public class Temp1 {");
            switch (scriptType)
            {
                case ScriptType.Expression:
                    sourceBuilder.AppendLine("public object DoIt(ITemplateHost host, ParameterBag parameters) {");
                    sourceBuilder.AppendLine("return " + code + ";");
                    sourceBuilder.AppendLine("} // DoIt");
                    entryPoint = "DoIt";
                    break;
                case ScriptType.Function:
                    sourceBuilder.AppendLine("public object DoIt(ITemplateHost host, ParameterBag parameters) {");
                    sourceBuilder.AppendLine(code);
                    sourceBuilder.AppendLine("} // DoIt");
                    entryPoint = "DoIt";
                    break;
                case ScriptType.Method:
                    sourceBuilder.AppendLine("public void DoIt(ITemplateHost host, ParameterBag parameters) {");
                    sourceBuilder.AppendLine(code);
                    sourceBuilder.AppendLine("} // DoIt");
                    entryPoint = "DoIt";
                    break;
                case ScriptType.MultipleMethods:
                    sourceBuilder.AppendLine(code);
                    break;
                case ScriptType.Validator:
                    sourceBuilder.AppendLine("public object DoIt(ITemplateHost host, ParameterBag parameters, Parameter parameter) {");
                    sourceBuilder.AppendLine(code);
                    sourceBuilder.AppendLine("} // DoIt");
                    entryPoint = "DoIt";
                    break;
                default:
                    throw new ArgumentOutOfRangeException(nameof(scriptType), scriptType, "Cannot construct code for that script type");
            }
            sourceBuilder.AppendLine("} // class");
            sourceBuilder.AppendLine("} // namespace");

            const string typeName = "StatsDirect.Templates.Temp1";
            string sourceFunction = sourceBuilder.ToString();
            string mainModulePath = Process.GetCurrentProcess().MainModule.FileName;
            string assemblyPath = Path.GetDirectoryName(mainModulePath);
            Debug.Assert(assemblyPath is not null);
            if (!TryCompileCSharpAssembly(sourceFunction, cSharpMetadataReferences, out Assembly assembly, out string errorMessage))
                throw new Exception("Couldn't compile C# code:" + Environment.NewLine + errorMessage);

            object instance = assembly.CreateInstance(typeName);
            Debug.Assert(instance is not null);
            Type type = instance.GetType();
            MethodInfo methodInfo = type.GetMethod(entryPoint);
            return new CompiledScript { Instance = instance, MethodInfo = methodInfo };
        }

        /// <summary>
        /// Compile the script.  Throw an exception if the compile fails.
        /// </summary>
        /// <returns></returns>
        private static CompiledScript CompileVisualBasic(string code, ScriptType scriptType, string entryPoint)
        {
            // Build up the source in sourceBuilder
            StringBuilder sourceBuilder = new();
            // sourceBuilder.AppendLine("Imports Microsoft.VisualBasic");
            sourceBuilder.AppendLine("Imports System");
            sourceBuilder.AppendLine("Imports System.Collections");
            sourceBuilder.AppendLine("Imports System.Collections.Generic");
            sourceBuilder.AppendLine("Imports System.Globalization");
            sourceBuilder.AppendLine("Imports System.Linq");
            sourceBuilder.AppendLine("Imports System.Text");
            sourceBuilder.AppendLine("Imports StatsDirect.Builtins");
            sourceBuilder.AppendLine("Imports StatsDirect.Data");
            sourceBuilder.AppendLine("Imports StatsDirect.Expressions");
            sourceBuilder.AppendLine("Imports StatsDirect.Numerics");
            sourceBuilder.AppendLine("Imports StatsDirect.R");
            sourceBuilder.AppendLine("Imports StatsDirect.Templates");
            sourceBuilder.AppendLine("Imports StatsDirect.Utilities");
            sourceBuilder.AppendLine("Namespace StatsDirect.Templates");
            sourceBuilder.AppendLine("Public Class Temp1");
            switch (scriptType)
            {
                case ScriptType.Expression:
                    sourceBuilder.AppendLine("Public Function DoIt(ByVal host As ITemplateHost, ByVal parameters As ParameterBag) As Object");
                    sourceBuilder.AppendLine("Return " + code);
                    sourceBuilder.AppendLine("End Function");
                    entryPoint = "DoIt";
                    break;
                case ScriptType.Function:
                    sourceBuilder.AppendLine("Public Function DoIt(ByVal host As ITemplateHost, ByVal parameters As ParameterBag) As Object");
                    sourceBuilder.AppendLine(code);
                    sourceBuilder.AppendLine("End Function");
                    entryPoint = "DoIt";
                    break;
                case ScriptType.Method:
                    sourceBuilder.AppendLine("Public Sub DoIt(ByVal host As ITemplateHost, ByVal parameters As ParameterBag)");
                    sourceBuilder.AppendLine(code);
                    sourceBuilder.AppendLine("End Sub");
                    entryPoint = "DoIt";
                    break;
                case ScriptType.MultipleMethods:
                    sourceBuilder.AppendLine(code);
                    break;
                case ScriptType.Validator:
                    sourceBuilder.AppendLine("Public Sub DoIt(ByVal host As ITemplateHost, ByVal parameters As ParameterBag, ByVal parameter as Parameter)");
                    sourceBuilder.AppendLine(code);
                    sourceBuilder.AppendLine("End Sub");
                    entryPoint = "DoIt";
                    break;
                default:
                    throw new ArgumentOutOfRangeException(nameof(scriptType), scriptType, "Cannot construct code for that script type");
            }
            sourceBuilder.AppendLine("End Class");
            sourceBuilder.AppendLine("End Namespace");
            const string typeName = "StatsDirect.Templates.Temp1";

            string sourceFunction = sourceBuilder.ToString();
            string mainModulePath = Process.GetCurrentProcess().MainModule.FileName;
            string assemblyPath = Path.GetDirectoryName(mainModulePath);
            Debug.Assert(assemblyPath is not null);
            if (!TryCompileVisualBasicAssembly(sourceFunction, visualBasicMetadataReferences, out Assembly assembly, out string errorMessage))
                throw new Exception("Couldn't compile Visual Basic code:" + Environment.NewLine + errorMessage);

            object instance = assembly.CreateInstance(typeName);
            Debug.Assert(instance is not null);
            Type type = instance.GetType();
            MethodInfo methodInfo = type.GetMethod(entryPoint);
            return new CompiledScript { Instance = instance, MethodInfo = methodInfo };
        }

        private static bool TryCompileCSharpAssembly(string source, IEnumerable<MetadataReference> references, out Assembly assembly, out string errorMessage, bool load = true)
        {
            SyntaxTree tree = Microsoft.CodeAnalysis.CSharp.SyntaxFactory.ParseSyntaxTree(source.Trim());
            Compilation compilation = CSharpCompilation.Create(null)
                .WithOptions(new CSharpCompilationOptions(OutputKind.DynamicallyLinkedLibrary,
                            optimizationLevel: OptimizationLevel.Debug))
                .AddReferences(references)
                .AddSyntaxTrees(tree);

            using MemoryStream codeStream = new();
            EmitResult compilationResult = null;
            compilationResult = compilation.Emit(codeStream);

            // Compilation Error handling
            if (!compilationResult.Success)
            {
                StringBuilder sb = new();
                foreach (Diagnostic diag in compilationResult.Diagnostics)
                    sb.AppendLine(diag.ToString());

                errorMessage = sb.ToString();
                assembly = null;
                return false;
            }

            errorMessage = null;
            assembly = load
                ? Assembly.Load(((MemoryStream)codeStream).ToArray())
                : null;

            return true;
        }

        private static bool TryCompileVisualBasicAssembly(string source, IEnumerable<MetadataReference> references, out Assembly assembly, out string errorMessage, bool load = true)
        {
            SyntaxTree tree = Microsoft.CodeAnalysis.VisualBasic.SyntaxFactory.ParseSyntaxTree(source.Trim());
            Compilation compilation = VisualBasicCompilation.Create(null)
                .WithOptions(new VisualBasicCompilationOptions(OutputKind.DynamicallyLinkedLibrary,
                            optimizationLevel: OptimizationLevel.Debug))
                .AddReferences(references)
                .AddSyntaxTrees(tree);

            using MemoryStream codeStream = new();
            EmitResult compilationResult = null;
            compilationResult = compilation.Emit(codeStream);

            // Compilation Error handling
            if (!compilationResult.Success)
            {
                StringBuilder sb = new();
                foreach (Diagnostic diag in compilationResult.Diagnostics)
                    sb.AppendLine(diag.ToString());

                errorMessage = sb.ToString();
                assembly = null;
                return false;
            }

            errorMessage = null;
            assembly = load
                ? Assembly.Load(((MemoryStream)codeStream).ToArray())
                : null;

            return true;
        }

        public string Check(string scriptLanguage, string code, ScriptType scriptType, string entryPoint)
        {
            try
            {
                switch (scriptLanguage)
                {
                    case CSHARP:
                    case CHASH:
                    case CHASHLOWER:
                    case VISUALBASIC:
                    case VISUALBASICLOWER:
                        CompileDotNet(scriptLanguage, code, scriptType, entryPoint);
                        return null;
                    case R:
                        // No way of detecting errors at present
                        return null;
                    default:
                        throw new ArgumentOutOfRangeException(nameof(scriptLanguage), scriptLanguage, "Must be CSharp, R, VB");
                }
            }
            catch (Exception ex)
            {
                return ex.Message;
            }
        }
    }

    /// <summary>
    /// 
    /// </summary>
    /// <remarks>With thanks to Rick Strahl: https://weblog.west-wind.com/posts/2022/Jun/07/Runtime-CSharp-Code-Compilation-Revisited-for-Roslyn</remarks>
    public class MetadataReferenceGatherer
    {
        public IReadOnlyCollection<MetadataReference> MetadataReferences => metadataReferences;

        private readonly HashSet<PortableExecutableReference> metadataReferences = new();

        public MetadataReferenceGatherer(bool addDefaultReferences)
        {
            if (addDefaultReferences)
                AddDefaultReferences();
        }

        public bool MaybeAddAssembly(string assemblyDll)
        {
            if (string.IsNullOrEmpty(assemblyDll))
                return false;

            string file = Path.GetFullPath(assemblyDll);

            if (!File.Exists(file))
            {
                // check framework or dedicated runtime app folder
                string path = Path.GetDirectoryName(typeof(object).Assembly.Location);
                file = Path.Combine(path, assemblyDll);
                if (!File.Exists(file))
                    return false;
            }

            if (metadataReferences.Any(r => r.FilePath == file))
                return true;

            try
            {
                PortableExecutableReference reference = MetadataReference.CreateFromFile(file);
                metadataReferences.Add(reference);
            }
            catch
            {
                return false;
            }
            return true;
        }

        public bool MaybeAddAssembly(Type type)
        {
            try
            {
                if (metadataReferences.Any(r => r.FilePath == type.Assembly.Location))
                    return true;

                PortableExecutableReference systemReference = MetadataReference.CreateFromFile(type.Assembly.Location);
                metadataReferences.Add(systemReference);
            }
            catch
            {
                return false;
            }

            return true;
        }

        public MetadataReferenceGatherer AddAssembly(string assemblyDll)
        {
            MaybeAddAssembly(assemblyDll);
            return this;
        }

        public MetadataReferenceGatherer AddAssembly(Type type)
        {
            MaybeAddAssembly(type);
            return this;
        }

        public bool MaybeAddAssemblies(params string[] assemblyDlls) => assemblyDlls.All(assemblyDll => MaybeAddAssembly(assemblyDll));

        public MetadataReferenceGatherer AddAssemblies(params string[] assemblyDlls)
        {
            foreach (string assemblyDll in assemblyDlls)
                AddAssembly(assemblyDll);
            return this;
        }

        private void AddDefaultReferences()
        {
            // Prevent repeated File.Exists tests for files we know don't exist by supplying a full path to AddAssembly.
            string runtimePath = Path.GetDirectoryName(typeof(object).Assembly.Location);

            AddAssemblies(
                Path.Combine(runtimePath, "System.Private.CoreLib.dll"),
                Path.Combine(runtimePath, "System.Runtime.dll"),
                Path.Combine(runtimePath, "System.Console.dll"),
                Path.Combine(runtimePath, "netstandard.dll"),

                Path.Combine(runtimePath, "System.Text.RegularExpressions.dll"),
                Path.Combine(runtimePath, "System.Linq.dll"),
                Path.Combine(runtimePath, "System.Linq.Expressions.dll"),

                Path.Combine(runtimePath, "System.IO.dll"),
                Path.Combine(runtimePath, "System.Net.Primitives.dll"),
                Path.Combine(runtimePath, "System.Net.Http.dll"),
                Path.Combine(runtimePath, "System.Private.Uri.dll"),
                Path.Combine(runtimePath, "System.Reflection.dll"),
                Path.Combine(runtimePath, "System.ComponentModel.Primitives.dll"),
                Path.Combine(runtimePath, "System.Globalization.dll"),
                Path.Combine(runtimePath, "System.Collections.Concurrent.dll"),
                Path.Combine(runtimePath, "System.Collections.NonGeneric.dll")
            );

            AddAssembly(GetType()); // Ourselves - in this case, StatsDirect.
        }
    }
}
