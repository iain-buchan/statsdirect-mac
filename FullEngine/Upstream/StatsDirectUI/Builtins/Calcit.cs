using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.Emit;
using StatsDirect.Expressions;
using StatsDirect.TemplateProcessing;

namespace StatsDirect.Builtins
{
    public class Calcit
    {
        private static readonly IEnumerable<MetadataReference> metadataReferences;

        private object instance;
        private MethodInfo methodInfo;
        public DataType OutputType { get; }

        static Calcit()
        {
            metadataReferences = new MetadataReferenceGatherer(true).MetadataReferences;
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="equation"></param>
        /// <param name="passedVariableTypes"></param>
        /// <param name="assumeVariants">If true, </param>
        public Calcit(string equation, DataType[] passedVariableTypes, bool assumeVariants)
            : this(equation, passedVariableTypes, assumeVariants, false)
        {
        }

        /// <param name="invariantNotation">true for a formula that ships with the program (the unit conversions), which is written with a decimal point whatever the regional settings</param>
        public Calcit(string equation, DataType[] passedVariableTypes, bool assumeVariants, bool invariantNotation)
        {
            OutputType = SetEquation(equation, passedVariableTypes, assumeVariants, invariantNotation, out bool _);
        }

        public static bool IsValid(string expression) => Converter.IsValid(expression);

        private DataType SetEquation(string equation, DataType[] passedVariableTypes, bool assumeVariants, bool invariantNotation, out bool compiledForVariants)
        {
            const string typeName = "Temp1";
            const string methodName = "DoIt";
            bool allDoubles = passedVariableTypes.Aggregate(true, (okSoFar, dt) => okSoFar && dt == DataType.Double);
            compiledForVariants = assumeVariants || !allDoubles;
            string cSharpExpression = Converter.ConvertToCSharp(equation, passedVariableTypes, compiledForVariants, out DataType retval, invariantNotation);

            // By now, cSharpExpression will either be safe (every character has been through the parser) or an exception will have been thrown.  Therefore, it's reasonable to throw the expression at the compiler.
            StringBuilder functionBuilder = new();
            functionBuilder.AppendLine("using System;");
            functionBuilder.AppendLine("using StatsDirect.Expressions;");
            functionBuilder.Append("public class ");
            functionBuilder.AppendLine(typeName);
            functionBuilder.AppendLine("{");
            functionBuilder.Append("public object ");
            functionBuilder.Append(methodName);
            functionBuilder.Append('(');
            functionBuilder.Append(compiledForVariants ? "object" : "double");
            functionBuilder.AppendLine("[] x)");
            functionBuilder.AppendLine("{");
            functionBuilder.Append("return ");
            functionBuilder.Append(cSharpExpression);
            functionBuilder.AppendLine(";");
            functionBuilder.AppendLine("}");
            functionBuilder.AppendLine("}");
            string cSharpFunction = functionBuilder.ToString();
            string mainModulePath = Process.GetCurrentProcess().MainModule.FileName;
            string assemblyPath = Path.GetDirectoryName(mainModulePath);
            Debug.Assert(assemblyPath is not null);
            if (!TryCompileAssembly(cSharpFunction, metadataReferences, out Assembly assembly, out string errorMessage))
                throw new Exception("Couldn't translate your expression to valid C# code:" + Environment.NewLine + errorMessage);

            instance = assembly.CreateInstance(typeName);
            Debug.Assert(instance is not null);
            Type type = instance.GetType();
            methodInfo = type.GetMethod(methodName);

            // By now, compiledScript is non-null or an exception has been thrown
            return retval;
        }

        public bool TryCompileAssembly(string source, IEnumerable<MetadataReference> references, out Assembly assembly, out string errorMessage, bool load = true)
        {
            SyntaxTree tree = SyntaxFactory.ParseSyntaxTree(source.Trim());
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

        public T Evaluate<T>(double[] values)
        {
            try
            {
                object[] parameters = { values };
                object output = methodInfo.Invoke(instance, parameters);
                return (T)Convert.ChangeType(output, typeof(T));
            }
            catch (TargetInvocationException tie)
            {
                if (tie.InnerException is not null)
                    throw tie.InnerException;
                throw;
            }
        }

        public T EvaluateObject<T>(object[] values)
        {
            try
            {
                object[] parameters = { values };
                return (T)methodInfo.Invoke(instance, parameters);
            }
            catch (TargetInvocationException tie)
            {
                if (tie.InnerException is not null)
                    throw tie.InnerException;
                throw;
            }
        }
    }
} 
