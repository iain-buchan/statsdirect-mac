using System;
using System.Collections.Generic;
using System.Globalization;
using StatsDirect.TemplateProcessing;
using StatsDirect.Templates;

namespace StatsDirect.UI
{
    /// <summary>
    /// Test runner for operations with tests
    /// </summary>
    internal class OperationsTester
    {
        public static void TestAll()
        {
            // The SdApplication constructor initialises the function registry; doing it separately here registers every builtin twice as soon as anything touches SoleInstance.
            _ = SdApplication.SoleInstance;
            int passed = 0, failed = 0, skipped = 0;
            List<string> lines = new();
            foreach (Operation operation in TemplateFactory.Operations.Values)
            {
                for (int i = 0; i < operation.Tests.Count; i++)
                {
                    OperationTest test = operation.Tests[i];
                    string id = $"{operation.Name}[{i + 1}]";
                    if (test.Inputs.Count == 0 && test.Outputs.Count == 0)
                    {
                        skipped++;
                        lines.Add($"SKIP  {id}  (empty test)");
                        continue;
                    }
                    try
                    {
                        TestOperation(operation, test);
                        passed++;
                        lines.Add($"PASS  {id}  ({test.Outputs.Count} outputs checked)");
                    }
                    catch (Exception ex)
                    {
                        failed++;
                        Exception inner = ex;
                        while (inner is System.Reflection.TargetInvocationException && null != inner.InnerException)
                            inner = inner.InnerException;
                        lines.Add($"FAIL  {id}  {inner.GetType().Name}: {inner.Message.Replace("\r", " ").Replace("\n", " ")}");
                    }
                }
            }
            lines.Insert(0, $"Operations: {TemplateFactory.Operations.Count}; tests passed: {passed}, failed: {failed}, skipped: {skipped}");
            System.IO.File.WriteAllLines(System.IO.Path.Combine(AppContext.BaseDirectory, "test-operations-results.txt"), lines);
            Environment.Exit(0 == failed ? 0 : 1);
        }

        private static void TestOperation(Operation operation)
        {
            if (0 == operation.Tests.Count)
                return;
            foreach (OperationTest test in operation.Tests)
                TestOperation(operation, test);
        }

        private static void TestOperation(Operation operation, OperationTest test)
        {
            // Dispose of empty tests
            if (test.Inputs.Count == 0 && test.Outputs.Count == 0)
                return;
            ITemplateProcessor templateProcessor = new TemplateProcessor(new OperationTestHost(test.Inputs));
            StepOutput stepOutput = templateProcessor.Execute(operation, new ParameterBag());
            VerifyOutputs(operation, stepOutput, test.Outputs);
        }

        private static void VerifyOutputs(Operation operation, StepOutput stepOutput, IList<OperationTestOutputParameter> outputs)
        {
            if (null == stepOutput.ParameterBag)
                throw new Exception($"Operation {operation.Name} failed: no output parameter bag");

            // Test each output that is present; where nothing is specified for something that is in outputParameters, no assumptions are made.
            foreach (var output in outputs)
            {
                bool found = TryGetPath(stepOutput.ParameterBag, output.Name, out FilledParameter parameter, operation.Name);
                if (output.ShouldBeMissing)
                {
                    // The relevant name shouldn't be mentioned in outputParameters at all
                    if (found)
                        throw new Exception($"Operation {operation.Name} failed: parameter {output.Name} is present in the output but should be missing");
                }
                else
                {
                    if (!found)
                        throw new Exception($"Operation {operation.Name} failed: parameter {output.Name} must be present in the output but is missing");
                    VerifyOutputValue(operation.Name, output, parameter);
                }
            }
        }

        private static bool TryGetPath(ParameterBag outputParameters, string path, out FilledParameter parameter, string operationName)
        {
            if (path.Contains('$'))
            {
                // Split on the first $ in the path: we want the item in here that matches the prefix, then we'll work on the rest.
                string prefix = path[..path.IndexOf("$")];
                string suffix = path[(prefix.Length + 1)..];
                if (!outputParameters.TryGetValue(prefix, out FilledParameter subParameter))
                    throw new Exception($"Operation {operationName} failed: parameter {path} must be present in the output but there's no output named {prefix}");
                // Check subParameter for the rest of the path
                PathFollower pathFollower = new(operationName, suffix);
                subParameter.Accept(pathFollower);
                parameter = pathFollower.ResolvedParameter;
                return null != parameter;
            }
            else
            {
                return outputParameters.TryGetValue(path, out parameter);
            }
        }

        private static void VerifyOutputValue(string operationName, OperationTestOutputParameter output, FilledParameter parameter)
        {
            parameter.Accept(new ValueVerifier(operationName, output));
        }

        private class ValueVerifier : IFilledParameterVisitor
        {
            private string OperationName { get; }
            private OperationTestOutputParameter Output { get; }

            public ValueVerifier(string operationName, OperationTestOutputParameter output)
            {
                OperationName = operationName;
                Output = output;
            }

            void IFilledParameterVisitor.Visit(FilledBooleanParameter victim)
            {
                if (!bool.TryParse(Output.Value, out bool expectedValue))
                    throw new Exception($"Operation {OperationName}, output {Output.Name}: Couldn't parse {Output.Value} as a Boolean; use true, false, True, or False");
                if (expectedValue != victim.Data)
                    throw new Exception($"Operation {OperationName}, output {Output.Name}: Expected {Output.Value} , got {victim.Data}");
            }

            void IFilledParameterVisitor.Visit(FilledChartDefinitionParameter victim)
            {
                // throw new NotImplementedException();
            }

            void IFilledParameterVisitor.Visit(FilledDataFrameParameter victim)
            {
                throw new NotImplementedException();
            }

            void IFilledParameterVisitor.Visit(FilledDoubleParameter victim)
            {
                if (!double.TryParse(Output.Value, NumberStyles.Float, CultureInfo.InvariantCulture, out double expectedValue))
                    throw new Exception($"Operation {OperationName}, output {Output.Name}: Couldn't parse {Output.Value} as a double");
                if (expectedValue != victim.Data)
                    throw new Exception($"Operation {OperationName}, output {Output.Name}: Expected {Output.Value} , got {victim.Data}");
            }

            void IFilledParameterVisitor.Visit(FilledInt32Parameter victim)
            {
                if (!int.TryParse(Output.Value, NumberStyles.Integer, CultureInfo.InvariantCulture, out int expectedValue))
                    throw new Exception($"Operation {OperationName}, output {Output.Name}: Couldn't parse {Output.Value} as an integer");
                if (expectedValue != victim.Data)
                    throw new Exception($"Operation {OperationName}, output {Output.Name}: Expected {Output.Value} , got {victim.Data}");
            }

            void IFilledParameterVisitor.Visit(FilledObjectParameter victim)
            {
                throw new NotImplementedException();
            }

            void IFilledParameterVisitor.Visit(FilledPaneParameter victim)
            {
                throw new NotImplementedException();
            }

            void IFilledParameterVisitor.Visit(FilledPaneAndPositionParameter victim)
            {
                throw new NotImplementedException();
            }

            void IFilledParameterVisitor.Visit(FilledParameterBagParameter victim)
            {
                throw new NotImplementedException();
            }

            void IFilledParameterVisitor.Visit(FilledParameterBagListParameter victim)
            {
                throw new NotImplementedException();
            }

            void IFilledParameterVisitor.Visit(FilledStringParameter victim)
            {
                // There are many different ways of getting blanks on both sides, so do a special comparison
                if (string.IsNullOrWhiteSpace(Output.Value) && string.IsNullOrWhiteSpace(victim.Data))
                    return;

                if (Output.Value != victim.Data)
                    throw new Exception($"Operation {OperationName}, output {Output.Name}: Expected {Output.Value} , got {victim.Data}");
            }

            void IFilledParameterVisitor.Visit(FilledStringListParameter victim)
            {
                throw new NotImplementedException();
            }
        }

        private class PathFollower : IFilledParameterVisitor
        {
            private string OperationName { get; }
            private string Path { get; }
            public FilledParameter ResolvedParameter { get; private set; }

            public PathFollower(string operationName, string path)
            {
                OperationName = operationName;
                Path = path;
            }

            void IFilledParameterVisitor.Visit(FilledBooleanParameter victim)
            {
                throw new NotImplementedException();
            }

            void IFilledParameterVisitor.Visit(FilledChartDefinitionParameter victim)
            {
                throw new NotImplementedException();
            }

            void IFilledParameterVisitor.Visit(FilledDataFrameParameter victim)
            {
                throw new NotImplementedException();
            }

            void IFilledParameterVisitor.Visit(FilledDoubleParameter victim)
            {
                throw new NotImplementedException();
            }

            void IFilledParameterVisitor.Visit(FilledInt32Parameter victim)
            {
                throw new NotImplementedException();
            }

            void IFilledParameterVisitor.Visit(FilledObjectParameter victim)
            {
                throw new NotImplementedException();
            }

            void IFilledParameterVisitor.Visit(FilledPaneParameter victim)
            {
                throw new NotImplementedException();
            }

            void IFilledParameterVisitor.Visit(FilledPaneAndPositionParameter victim)
            {
                throw new NotImplementedException();
            }

            void IFilledParameterVisitor.Visit(FilledParameterBagParameter victim)
            {
                if (Path.Contains('$'))
                {
                    // Split on the first $ in the path: we want the item in here that matches the prefix, then we'll work on the rest.
                    string prefix = Path[..Path.IndexOf("$")];
                    string suffix = Path[(prefix.Length + 1)..];
                    if (!victim.Data.TryGetValue(prefix, out FilledParameter subParameter))
                        throw new Exception($"Operation {OperationName} failed: parameter {Path} must be present in the output but there's no output named {prefix}");
                    // Check subParameter for the rest of the path
                    PathFollower pathFollower = new(OperationName, suffix);
                    subParameter.Accept(pathFollower);
                    ResolvedParameter = pathFollower.ResolvedParameter;
                }
                else
                {
                    if (!victim.Data.TryGetValue(Path, out FilledParameter parameter))
                        throw new Exception($"Operation {OperationName} failed: parameter {Path} must be present in the output but is missing");
                    ResolvedParameter = parameter;
                }
            }

            void IFilledParameterVisitor.Visit(FilledParameterBagListParameter victim)
            {
                // The next path element should be an index - go for it, then try the path again
                if (!Path.Contains('$'))
                    throw new Exception($"Operation {OperationName} failed: parameter {Path} represents a list of parameter bags, so should be of the form ...$1$value");
                // Split on the first $ in the path: we want the item in here that matches the prefix (which should be a 1-based index), then we'll work on the rest.
                string prefix = Path[..Path.IndexOf("$")];
                string suffix = Path[(prefix.Length + 1)..];
                if (!int.TryParse(prefix, out int indexPlusOne))
                    throw new Exception($"Operation {OperationName} failed: parameter {Path} should have a 1-based numeric index as its next component, not {prefix}");
                if (indexPlusOne < 1 || indexPlusOne > victim.Data.Count)
                    throw new Exception($"Operation {OperationName} failed: parameter {Path} contains 1 to {victim.Data.Count} elements, we're checking {prefix}");
                FilledParameter subParameter = FilledParameterFactory.Output(victim.Data[indexPlusOne - 1]);
                // Check subParameter for the rest of the path
                PathFollower pathFollower = new(OperationName, suffix);
                subParameter.Accept(pathFollower);
                ResolvedParameter = pathFollower.ResolvedParameter;
            }

            void IFilledParameterVisitor.Visit(FilledStringParameter victim)
            {
                throw new NotImplementedException();
            }

            void IFilledParameterVisitor.Visit(FilledStringListParameter victim)
            {
                throw new NotImplementedException();
            }
        }
    }
}