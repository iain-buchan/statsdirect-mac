using System;
using System.Collections.Generic;
using System.Globalization;
using StatsDirect.Data;
using StatsDirect.TemplateProcessing;
using StatsDirect.Templates;

namespace StatsDirect.UI
{
    internal class OperationTestHost : ITemplateHost
    {
        private Dictionary<string, OperationTestInputParameter> InputParameters { get; }

        public OperationTestHost(IList<OperationTestInputParameter> inputs)
        {
            InputParameters = new Dictionary<string, OperationTestInputParameter>();
            foreach (OperationTestInputParameter input in inputs)
                InputParameters.Add(input.Name, input);
        }

        /// <summary>
        /// Session values in tests are always empty; always generate a new dictionary in case anything tries to fill it.
        /// </summary>
        IDictionary<string, ParameterBag> ISession.SessionParametersPerOperation => new Dictionary<string, ParameterBag>();

        ParameterBag ISession.SessionParametersAcrossOperations => throw new NotImplementedException();

        SDPreferences IPreferences.Preferences => throw new NotImplementedException();

        Operation IUserInterface.Operation { get; set; }

        ParameterBag IUserInterface.Amend(IFillable options, ParameterBag context)
        {
            // No amendment during tests
            return context;
        }

        bool IUserInterface.CanCombine(Parameter parameter)
        {
            return false; // We always force the use of single parameters to make the host's life easy
        }

        void IUserInterface.Error(string Message, string Caption)
        {
            throw new NotImplementedException();
        }

        ParameterBag IUserInterface.FillAndValidateCombinedParameters(ITemplateProcessor processor, ParameterBag context)
        {
            // Should never be called
            throw new NotImplementedException();
        }

        ParameterBag IUserInterface.FillParameter(ITemplateProcessor processor, Parameter parameter, ParameterBag context, bool shouldCombine)
        {
            if (!InputParameters.TryGetValue(parameter.Name, out OperationTestInputParameter input))
                throw new NotImplementedException($"Operation {parameter.Operation.Name} expects parameter {parameter.Name} which was not specified in the test inputs");
            return new ParameterBag(parameter.Name, FilledParameterFactory.Input(new InputParameterFiller(input).Fill(parameter)));
        }

        bool IUserInterface.GetBoolean(string prompt, string Title, bool initialValue, out bool cancelled)
        {
            throw new NotImplementedException();
        }

        IScriptEngine IScriptEngineHost.GetScriptEngine(string language)
        {
            if (ScriptEngine.CanHandle(language))
                return new ScriptEngine();
            return null;
        }

        void IUserInterface.OutputFrame(DataFrame frame, bool keepSelection, bool isFormulae, string missingIndicator, PaneAndPosition preferredOutputLocation, RelativePosition defaultPosition)
        {
            throw new NotImplementedException();
        }

        object IUserInterface.OutputReport(IRenderable renderable, Operation operation, object preferredOutputLocation)
        {
            // No UI during a test
            return null;
        }

        void IUserInterface.PrepareParameter(ITemplateProcessor processor, Parameter parameter, ParameterBag context)
        {
            if (!InputParameters.TryGetValue(parameter.Name, out OperationTestInputParameter input))
                throw new NotImplementedException($"Operation {parameter.Operation.Name} expects parameter {parameter.Name} which was not specified in the test inputs");
            context.AddInput(parameter.Name, new InputParameterFiller(input).Fill(parameter));
        }

        string IFormatting.pval(double p)
        {
            throw new NotImplementedException();
        }

        string IFormatting.pval_half(double p)
        {
            throw new NotImplementedException();
        }

        string IFormatting.RoundU(double amount)
        {
            throw new NotImplementedException();
        }

        IProgressBar IProgressBarHost.StartProgress(string operationDescription, bool provideProgress, bool display)
        {
            return new TestProgressBar();
        }

        void IUserInterface.Warning(string Message, string Caption)
        {
            // No UI during a test
        }

        private class TestProgressBar : IProgressBar
        {
            void IProgressBar.Finish()
            {
                // Do nothing
            }

            bool IProgressBar.Update(double fractionComplete)
            {
                // Do nothing, and continue: true would mean that the user had cancelled, which made any operation that reports progress cancel itself during a test
                return false;
            }

            #region IDisposable Support
            // This code added to correctly implement the disposable pattern.
            void IDisposable.Dispose()
            {
                // Nothing needed
            }
            #endregion
        }

        private class InputParameterFiller : IParameterVisitor
        {
            private OperationTestInputParameter Input { get; }

            object parsedInput;

            public InputParameterFiller(OperationTestInputParameter input)
            {
                this.Input = input;
            }
            void IParameterVisitor.Visit(BooleanParameter parameter)
            {
                parsedInput = bool.Parse(Input.Value);
            }

            void IParameterVisitor.Visit(ChartOptionsParameter parameter)
            {
                throw new NotImplementedException();
            }

            void IParameterVisitor.Visit(ConfidenceIntervalParameter parameter)
            {
                parsedInput = double.Parse(Input.Value, CultureInfo.InvariantCulture);
            }

            void IParameterVisitor.Visit(DateParameter parameter)
            {
                throw new NotImplementedException();
            }

            void IParameterVisitor.Visit(Double2By2Parameter parameter)
            {
                throw new NotImplementedException();
            }

            void IParameterVisitor.Visit(Double2By2ByKParameter parameter)
            {
                throw new NotImplementedException();
            }

            void IParameterVisitor.Visit(DoubleParameter parameter)
            {
                parsedInput = double.Parse(Input.Value, CultureInfo.InvariantCulture);
            }

            void IParameterVisitor.Visit(EditGridParameter parameter)
            {
                throw new NotImplementedException();
            }

            void IParameterVisitor.Visit(FillableParameter parameter)
            {
                throw new NotImplementedException();
            }

            void IParameterVisitor.Visit(Frame2DParameter parameter)
            {
                throw new NotImplementedException();
            }

            void IParameterVisitor.Visit(FrameParameter parameter)
            {
                parsedInput = FrameData.ParseToFrame(Input.Value);
            }

            void IParameterVisitor.Visit(GroupedCovarianceParameter parameter)
            {
                throw new NotImplementedException();
            }

            void IParameterVisitor.Visit(IntegerParameter parameter)
            {
                parsedInput = int.Parse(Input.Value, CultureInfo.InvariantCulture);
            }

            void IParameterVisitor.Visit(OptionParameter parameter)
            {
                throw new NotImplementedException();
            }

            void IParameterVisitor.Visit(OptionsParameter parameter)
            {
                throw new NotImplementedException();
            }

            void IParameterVisitor.Visit(PickFromListParameter parameter)
            {
                throw new NotImplementedException();
            }

            void IParameterVisitor.Visit(PickVariablesParameter parameter)
            {
                throw new NotImplementedException();
            }

            void IParameterVisitor.Visit(SpecialParameter parameter)
            {
                throw new NotImplementedException();
            }

            void IParameterVisitor.Visit(StringParameter parameter)
            {
                parsedInput = Input.Value;
            }

            internal object Fill(Parameter parameter)
            {
                parameter.Accept(this);
                return parsedInput;
            }
        }
    }
}