using System;
using System.Collections.Generic;
using System.Globalization;
using StatsDirect.Data;
using StatsDirect.TemplateProcessing;
using StatsDirect.Templates;

namespace StatsDirect.UI
{
    internal class ViewerHost : ITemplateHost
    {
        private Dictionary<string, OperationTestInputParameter> InputParameters { get; }

        public ViewerHost(IList<OperationTestInputParameter> inputs)
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

        public SDPreferences Preferences { get; } = new HeadlessPreferences();
        public System.Text.StringBuilder Html { get; } = new();

        public Func<bool> Cancelled { get; set; } = () => false;
        public Action<IFillable> AmendOptions { get; set; }
        public List<string> Warnings { get; } = new();
        private void CheckCancellation() { if (Cancelled()) throw new OperationCanceledException(); }

        Operation IUserInterface.Operation { get; set; }

        ParameterBag IUserInterface.Amend(IFillable options, ParameterBag context)
        {
            CheckCancellation();
            if (AmendOptions == null) return context;
            AmendOptions(options);
            return context ?? new ParameterBag();
        }

        bool IUserInterface.CanCombine(Parameter parameter)
        {
            return false; // We always force the use of single parameters to make the host's life easy
        }

        void IUserInterface.Error(string Message, string Caption)
        {
            throw new InvalidOperationException(Caption + ": " + Message);
        }

        ParameterBag IUserInterface.FillAndValidateCombinedParameters(ITemplateProcessor processor, ParameterBag context)
        {
            // Should never be called
            throw new NotImplementedException();
        }

        ParameterBag IUserInterface.FillParameter(ITemplateProcessor processor, Parameter parameter, ParameterBag context, bool shouldCombine)
        {
            CheckCancellation();
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
            CheckCancellation();
            Html.Append(new HtmlRenderer(this).Render(renderable));
            return null;
        }

        void IUserInterface.PrepareParameter(ITemplateProcessor processor, Parameter parameter, ParameterBag context)
        {
            CheckCancellation();
            if (!InputParameters.TryGetValue(parameter.Name, out OperationTestInputParameter input))
                throw new NotImplementedException($"Operation {parameter.Operation.Name} expects parameter {parameter.Name} which was not specified in the test inputs");
            context.AddInput(parameter.Name, new InputParameterFiller(input).Fill(parameter));
        }

        string IFormatting.pval(double p) => StatsDirect.Utilities.Formatting.pval(p, Preferences.PDecimalPlaces, Preferences.UseScientificNotationForSmallPValues);

        string IFormatting.pval_half(double p) => StatsDirect.Utilities.Formatting.pval_half(p, Preferences.PDecimalPlaces, Preferences.UseScientificNotationForSmallPValues);

        string IFormatting.RoundU(double amount) => StatsDirect.Utilities.Formatting.XRound(amount, Preferences.DisplayDecimalPlaces);

        IProgressBar IProgressBarHost.StartProgress(string operationDescription, bool provideProgress, bool display)
        {
            CheckCancellation();
            return new TestProgressBar(Cancelled);
        }

        void IUserInterface.Warning(string Message, string Caption)
        {
            Warnings.Add(Caption + ": " + Message);
        }

        private class TestProgressBar : IProgressBar
        {
            private readonly Func<bool> cancelled;
            public TestProgressBar(Func<bool> cancelled) { this.cancelled = cancelled; }
            void IProgressBar.Finish()
            {
                // Do nothing
            }

            bool IProgressBar.Update(double fractionComplete)
            {
                return cancelled();
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