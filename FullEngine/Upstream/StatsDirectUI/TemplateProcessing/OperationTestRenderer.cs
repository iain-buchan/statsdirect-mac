using StatsDirect.CsvParser;
using StatsDirect.Data;
using StatsDirect.Templates;
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;

namespace StatsDirect.TemplateProcessing
{
    /// <summary>
    /// Turn a ParameterBag into a list of OperationTestInputParameters suitable for using as inputs to a test.
    /// </summary>
    public static class OperationTestRenderer
    {
        public static OperationTest Render(ParameterBag parameters)
        {
            return new OperationTest
            {
                Inputs = RenderAsInputs(parameters),
                Outputs = RenderAsOutputs(parameters)
            };
        }

        private static IList<OperationTestInputParameter> RenderAsInputs(ParameterBag parameters)
        {
            return parameters
                .Where(parameter => null != parameter.Value && (parameter.Value.Direction == FilledParameterDirection.Default || parameter.Value.Direction == FilledParameterDirection.Input))
                .SelectMany(parameter => InputOrOutputVisitor<OperationTestInputParameter>.Render(parameter.Key, parameter.Value))
                .ToList();
        }

        private static IList<OperationTestOutputParameter> RenderAsOutputs(ParameterBag parameters)
        {
            return parameters
                .Where(parameter => null != parameter.Value && parameter.Value.Direction == FilledParameterDirection.Output)
                .SelectMany(parameter => InputOrOutputVisitor<OperationTestOutputParameter>.Render(parameter.Key, parameter.Value))
                .ToList();
        }

        private class InputOrOutputVisitor<T> : IFilledParameterVisitor where T : IOperationTestParameter, new()
        {
            private readonly IList<T> inputs = new List<T>();
            private string NameOrPrefix { get; }

            public static IList<T> Render(string nameOrPrefix, FilledParameter victim)
            {
                InputOrOutputVisitor<T> inputVisitor = new(nameOrPrefix);
                if (null != victim && victim.HasData)
                    victim.Accept(inputVisitor);
                return inputVisitor.inputs;
            }

            private InputOrOutputVisitor(string nameOrPrefix)
            {
                NameOrPrefix = nameOrPrefix;
            }

            void IFilledParameterVisitor.Visit(FilledBooleanParameter victim)
            {
                inputs.Add(new T { Name = NameOrPrefix, Value = victim.Data.ToString() });
            }

            void IFilledParameterVisitor.Visit(FilledChartDefinitionParameter victim)
            {
                // Do nothing - we're never interested in this
            }

            void IFilledParameterVisitor.Visit(FilledDataFrameParameter victim)
            {
                if (!victim.HasData)
                    return;

                DataFrame frame = victim.Data;
                List<string> header = frame.Variables
                    .Select(variable => string.IsNullOrWhiteSpace(variable.Title) ? string.Empty : variable.Title)
                    .ToList();
                List<IList<string>> rows = new();
                for (int rowIndex = 0; rowIndex < frame.MaxRows; rowIndex++)
                    rows.Add(frame.Variables
                        .Select(variable => rowIndex < variable.Length ? variable.DataAsObject(rowIndex).ToString() : string.Empty)
                        .ToList());

                inputs.Add(new T { Name = NameOrPrefix, Value = new CsvRenderer().Render(header, rows) });
            }

            void IFilledParameterVisitor.Visit(FilledDoubleParameter victim)
            {
                // Microsoft recommends using G17 for double rather than R ("Round-trip") as bugs in R can prevent a successful round-trip.
                // See https://docs.microsoft.com/en-us/dotnet/standard/base-types/standard-numeric-format-strings#RFormatString retrieved 2019-09-17.
                inputs.Add(new T { Name = NameOrPrefix, Value = victim.Data.ToString("G17", CultureInfo.InvariantCulture) });
            }

            void IFilledParameterVisitor.Visit(FilledInt32Parameter victim)
            {
                inputs.Add(new T { Name = NameOrPrefix, Value = victim.Data.ToString(CultureInfo.InvariantCulture) });
            }

            void IFilledParameterVisitor.Visit(FilledObjectParameter victim)
            {
                throw new NotImplementedException();
            }

            void IFilledParameterVisitor.Visit(FilledPaneParameter victim)
            {
                // Do nothing - we're never interested in this
            }

            void IFilledParameterVisitor.Visit(FilledPaneAndPositionParameter victim)
            {
                // Do nothing - we're never interested in this
            }

            void IFilledParameterVisitor.Visit(FilledParameterBagParameter victim)
            {
                foreach (KeyValuePair<string, FilledParameter> innerPair in victim.Data)
                {
                    string innerPrefix = $"{NameOrPrefix}${innerPair.Key}";
                    foreach (var x in Render(innerPrefix, innerPair.Value))
                        inputs.Add(x);
                }
            }

            void IFilledParameterVisitor.Visit(FilledParameterBagListParameter victim)
            {
                IList<ParameterBag> data = victim.Data;
                for (int i = 0; i < data.Count; i++)
                {
                    ParameterBag innerBag = data[i];
                    string innerPrefix = $"{NameOrPrefix}${i + 1}";
                    foreach (T x in Render(innerPrefix, FilledParameterFactory.Input(innerBag)))
                        inputs.Add(x);
                }
            }

            void IFilledParameterVisitor.Visit(FilledStringParameter victim)
            {
                inputs.Add(new T { Name = NameOrPrefix, Value = string.IsNullOrEmpty(victim.Data) ? string.Empty : victim.Data });
            }

            void IFilledParameterVisitor.Visit(FilledStringListParameter victim)
            {
                if (victim.HasData)
                    inputs.Add(new T { Name = NameOrPrefix, Value = new CsvRenderer().Render(string.Empty, victim.Data) });
            }
        }
    }
}
