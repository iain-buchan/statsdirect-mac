using StatsDirect.Builtins;
using StatsDirect.Data;
using StatsDirect.Numerics;
using StatsDirect.Templates;
using System;
using System.Collections.Generic;

namespace StatsDirect.TemplateProcessing
{
    static class ValidationProcessor
    {
        /// <returns>A string containing at least one validation error, or null if there are no validation errors detected.</returns>
        public static ValidationResult Validate(ITemplateHost host, string validatorName, Parameter parameter, ParameterBag filledParameters, string failedValidationMessage)
        {
            // Does the operation define a custom validator with that name?  If so, use it.
            if (null != parameter.Operation.CustomValidators)
            {
                foreach (CustomValidator candidate in parameter.Operation.CustomValidators)
                {
                    if (candidate.Name.Equals(validatorName))
                    {
                        string language = candidate.Language ?? "CSharp";
                        IScriptEngine scriptEngine = host.GetScriptEngine(language);
                        object result = scriptEngine.Run(language, candidate.Script, ScriptType.Validator, host, filledParameters, parameter, null);
                        if (null == result)
                            return ValidationResult.Valid;
                        return ValidationResult.Invalid(result.ToString());
                    }
                }
            }

            return ValidateGeneric(validatorName, parameter, filledParameters, failedValidationMessage);
        }

        private static ValidationResult ValidateGeneric(string validatorName, Parameter parameter, ParameterBag filledParameters, string failedValidationMessage)
        {
            // If we're allowing blank parameters, accept a blank.
            if (null != parameter.CancelSkipsParameter && (null == filledParameters || 0 == filledParameters.Count))
                return ValidationResult.Valid;

            // There's no custom validator with that name (or we would never be called), so use a generic if we have one.
            // Note that some of these validators assume a particular frame name - deal with that here.
            string parameterName;
            switch (validatorName)
            {
                case "PersonTimeSize":
                    parameterName = "data";
                    break;
                default:
                    parameterName = parameter.Name;
                    break;
            }

            // If the parameter is missing and it has an AcquireIfTrue, assume it was never acquired and that was OK.
            if (parameter.HasAcquireIfTrue && !filledParameters.ContainsKey(parameterName))
                return ValidationResult.Valid;

            FilledParameter p = filledParameters[parameterName];
            switch (validatorName)
            {
                case "Boolean":
                    return ValidateBoolean(failedValidationMessage, p.AsDataFrame);
                case "CheckForNonDummiedCategories":
                    return CheckForNonDummiedCategories(p.AsDataFrame);
                case "Expression":
                    return ValidateExpression(failedValidationMessage, p.AsString);
                case "Integer":
                    return ValidateInteger(failedValidationMessage, p.AsDataFrame);
                case "NoMissingData":
                    return ValidateNoMissingData(failedValidationMessage, p.AsDataFrame);
                case "NonNegative":
                    return ValidateNonNegative(failedValidationMessage, p.AsDataFrame);
                case "PersonTimeSize":
                    return ValidatePersonTimeSize(p.AsDataFrame);
                case "Pooling":
                    return ValidatePooling(failedValidationMessage, p.AsDataFrame);
                case "Positive":
                    return ValidatePositive(failedValidationMessage, p.AsDataFrame);
                case "PositiveRows":
                    return ValidatePositiveRows(failedValidationMessage, p.AsDataFrame);
                case "PositiveRowsExceptLastColumn":
                    return ValidatePositiveRowsExceptLastColumn(failedValidationMessage, p.AsDataFrame);
                case "Square":
                    return ValidateSquare(failedValidationMessage, p.AsDataFrame);
                case "SquareBins":
                    return ValidateSquareBins(failedValidationMessage, p.AsDataFrame);
                case "TwoBinsAndNoMissingData":
                    return ValidateTwoBins(failedValidationMessage, p.AsDataFrame);
                case "ZeroToOneExclusive":
                    return ValidateZeroToOneExclusive(failedValidationMessage, p.AsDataFrame);
                case "ZeroToOneInclusive":
                    return ValidateZeroToOneInclusive(failedValidationMessage, p.AsDataFrame);
                default:
                    throw new ArgumentOutOfRangeException(nameof(validatorName), validatorName, "No validator with the specified name");
            }
        }

        private static ValidationResult ValidatePersonTimeSize(DataFrame dataFrame)
        {
            // Assumes no missing data, no data < 0
            DoubleVariable datV0 = (DoubleVariable)dataFrame.Variables[0];
            DoubleVariable datV1 = (DoubleVariable)dataFrame.Variables[1];
            DoubleVariable datV2 = (DoubleVariable)dataFrame.Variables[2];
            int rows = dataFrame.MaxRows;

            double refntot = 0.0;
            for (int j = 0; j < rows; j++)
            {
                double xy = datV0.Data[j];
                double xn = datV1.Data[j];
                double rf = datV2.Data[j];
                refntot += rf;
                if (xn <= 0)
                    return ValidationResult.Invalid("Person-time must be greater than zero");
                if (xy > xn)
                    return ValidationResult.Invalid("Number of events must be greater then person-time, do not scale person-time");
            }

            if (refntot <= 0.0)
                return ValidationResult.Invalid("Total reference group size must be greater than zero");
            return ValidationResult.Valid;
        }

        private static ValidationResult ValidateNoMissingData(string failedValidationMessage, DataFrame dataFrame)
        {
            // Ensure there's no missing data in any of the numeric variables in the frame
            foreach (IVariable variable in dataFrame.Variables)
                if (variable is DoubleVariable doubleVariable)
                    foreach (double value in doubleVariable.Data)
                        if (value == Constant.MISSING)
                            return ValidationResult.Invalid(failedValidationMessage ?? "Data with missing values cannot be used here");
            return ValidationResult.Valid;
        }

        private static ValidationResult ValidateExpression(string failedValidationMessage, string expression)
        {
            if (!Calcit.IsValid(expression))
                return ValidationResult.Invalid(failedValidationMessage ?? "Please enter a valid expression");
            return ValidationResult.Valid;
        }

        private static ValidationResult ValidateTwoBins(string failedValidationMessage, DataFrame dataFrame)
        {
            // Ensure there are exactly two bins in the classifier variable
            if (((ClassifierVariable)dataFrame.Variables[0]).GroupCount != 2)
                return ValidationResult.Invalid(failedValidationMessage ?? "Group identifier must contain two groups and no missing data");
            return ValidationResult.Valid;
        }

        private static ValidationResult ValidateZeroToOneInclusive(string failedValidationMessage, DataFrame dataFrame)
        {
            // Ensure all values are in the range [0, 1]
            foreach (IVariable variable in dataFrame.Variables)
                if (variable is DoubleVariable doubleVariable)
                    foreach (double value in doubleVariable.Data)
                        if (value < 0 || value > 1)
                            return ValidationResult.Invalid(failedValidationMessage ?? "Data must lie between 0 and 1 inclusive");
            return ValidationResult.Valid;
        }

        private static ValidationResult ValidateZeroToOneExclusive(string failedValidationMessage, DataFrame dataFrame)
        {
            // Ensure all values are in the range (0, 1)
            foreach (IVariable variable in dataFrame.Variables)
                if (variable is DoubleVariable doubleVariable)
                    foreach (double value in doubleVariable.Data)
                        if (value <= 0 || value >= 1)
                            return ValidationResult.Invalid(failedValidationMessage ?? "Data must lie between 0 and 1");
            return ValidationResult.Valid;
        }

        private static ValidationResult ValidateNonNegative(string failedValidationMessage, DataFrame dataFrame)
        {
            // Ensure all values are >= 0
            foreach (IVariable variable in dataFrame.Variables)
                if (variable is DoubleVariable doubleVariable)
                    foreach (double value in doubleVariable.Data)
                        if (value < 0)
                            return ValidationResult.Invalid(failedValidationMessage ?? "Data must be positive or zero numbers");
            return ValidationResult.Valid;
        }

        private static ValidationResult ValidatePositiveRowsExceptLastColumn(string failedValidationMessage, DataFrame dataFrame)
        {
            foreach (IVariable variable in dataFrame.Variables)
                if (!(variable is DoubleVariable))
                    return ValidationResult.Invalid("Data must be numeric");

            // Ensure the sum of all values across a row except the last column is > 0
            for (int row = 0; row < dataFrame.MinRows; row++)
            {
                double sum = 0;
                for (int col = 0; col < dataFrame.Variables.Count - 1; col++)
                {
                    IVariable variable = dataFrame.Variables[col];
                    double x = ((DoubleVariable)variable).Data[row];
                    if (!(x == Constant.MISSING || double.IsInfinity(x)))
                        sum += x;
                }
                if (sum <= 0)
                    return ValidationResult.Invalid(failedValidationMessage ?? "Invalid data: row " + (row + 1).ToString() + " total is not greater than zero, which it must be for this calculation");
            }
            return ValidationResult.Valid;
        }

        private static ValidationResult ValidatePositiveRows(string failedValidationMessage, DataFrame dataFrame)
        {
            foreach (IVariable variable in dataFrame.Variables)
                if (!(variable is DoubleVariable))
                    return ValidationResult.Invalid("Data must be numeric");

            // Ensure the sum of all values across a row is > 0
            for (int row = 0; row < dataFrame.MinRows; row++)
            {
                double sum = 0;
                foreach (IVariable variable in dataFrame.Variables)
                {
                    double x = ((DoubleVariable)variable).Data[row];
                    if (!(x == Constant.MISSING || double.IsInfinity(x)))
                        sum += x;
                }
                if (sum <= 0)
                    return ValidationResult.Invalid(failedValidationMessage ?? "Invalid data: row " + (row + 1).ToString() + " total is not greater than zero, which it must be for this calculation");
            }
            return ValidationResult.Valid;
        }

        private static ValidationResult ValidateInteger(string failedValidationMessage, DataFrame dataFrame)
        {
            // Ensure all values are integers
            foreach (IVariable variable in dataFrame.Variables)
                if (variable is DoubleVariable doubleVariable)
                    foreach (double value in doubleVariable.Data)
                        if (value != Math.Floor(value))
                            return ValidationResult.Invalid(failedValidationMessage ?? "Data must be integer numbers");
            return ValidationResult.Valid;
        }

        private static ValidationResult ValidatePositive(string failedValidationMessage, DataFrame dataFrame)
        {
            // Ensure all values are > 0
            foreach (IVariable variable in dataFrame.Variables)
                if (variable is DoubleVariable doubleVariable)
                    foreach (double value in doubleVariable.Data)
                        if (value <= 0)
                            return ValidationResult.Invalid(failedValidationMessage ?? "Data must be positive non-zero numbers");
            return ValidationResult.Valid;
        }

        private static ValidationResult ValidateBoolean(string failedValidationMessage, DataFrame dataFrame)
        {
            // Ensure all values are in {0, 1}
            foreach (IVariable variable in dataFrame.Variables)
                if (variable is DoubleVariable doubleVariable)
                    foreach (double value in doubleVariable.Data)
                        if (0.0 != value && 1.0 != value)
                            return ValidationResult.Invalid(failedValidationMessage ?? "Case-control indicator must be 1 for case or 0 for control only");
            return ValidationResult.Valid;
        }

        private static ValidationResult CheckForNonDummiedCategories(DataFrame dataFrame)
        {
            // Ensure the number of bins, if >2, is at least 12 (or they're all distinct)
            foreach (DoubleVariable v in dataFrame.Variables)
            {
                double[] data = v.Data;
                bool allInteger = true;
                // skip if all not integers
                foreach (double t in data)
                {
                    if (t != Math.Floor(t))
                    {
                        allInteger = false;
                        break;
                    }
                }
                if (!allInteger)
                    continue;

                // All integers. How many categories have we got?  If it's 12 or more, we're OK.  If there's only one duplicate, we're also OK.
                int upperLimitForCategories = Math.Min(data.Length - 1, 11);
                HashSet<double> distinctValues = new();
                foreach (double value in data)
                    if (value != Constant.MISSING)
                    {
                        distinctValues.Add(value);
                        // Break out early if we already know we won't consider it categorical.
                        if (distinctValues.Count > upperLimitForCategories)
                            break;
                    }
                if (distinctValues.Count > 2 && distinctValues.Count <= upperLimitForCategories)
                    return new ValidationResult()
                    {
                        Validity = Validity.NeedMoreInformation,
                        HelpContextId = 1068,
                        TitleForMoreInformation = "Regression Predictor Scan",
                        PromptForMoreInformation = "The variable named '" + v.Title + "' seems to contain categorical data.\r\n\r\nIf you want to use categorical data containing more than two categories,\r\nthen please use the 'Data_Dummy Variables' menu item to convert this variable\r\nto dummy variables before running the regression again.\r\n\r\nDo you want to quit this regression and sort out your data?",
                        ActionOnMoreInformationYes = ValidationAction.CancelOperation,
                        ActionOnMoreInformationNo = ValidationAction.UseAsIs
                    };
            }
            // If we get here, we're fine
            return ValidationResult.Valid;
        }

        private static ValidationResult ValidateSquareBins(string failedValidationMessage, DataFrame dataFrame)
        {
            // Ensure the number of bins is the square root of the number of values
            DoubleVariable variable = (DoubleVariable)dataFrame.Variables[0];
            ClassifierVariable cv = TemplateProcessor.gidx_bins(variable);
            if (Math.Sqrt(variable.Length) != cv.GroupCount)
                return ValidationResult.Invalid(failedValidationMessage ?? "There should be " + Math.Sqrt(variable.Length).ToString("N0") + " classes");
            return ValidationResult.Valid;
        }

        private static ValidationResult ValidateSquare(string failedValidationMessage, DataFrame dataFrame)
        {
            // Ensure the number of values is a square number
            DoubleVariable variable = (DoubleVariable)dataFrame.Variables[0];
            if (Math.Sqrt(variable.Length) != Math.Floor(Math.Sqrt(variable.Length)))
                return ValidationResult.Invalid(failedValidationMessage ?? "Number of observations can not be arranged as a square (i.e. integer square root)");
            return ValidationResult.Valid;
        }

        private static ValidationResult ValidatePooling(string failedValidationMessage, DataFrame dataFrame)
        {
            // Ensure all values are in {-1, 0, 1}
            DoubleVariable variable = (DoubleVariable)dataFrame.Variables[0];
            foreach (double value in variable.Data)
                if (0 != value && -1 != value && 1 != value)
                    return ValidationResult.Invalid(failedValidationMessage ?? "Pooling indicator must be 0 (not pooled), 1 (subgroup) or -1 (pooled) only");
            return ValidationResult.Valid;
        }
    }

    public enum Validity
    {
        None = 0,
        Valid = 1,
        Invalid = 2,
        NeedMoreInformation = 3
    }

    public enum ValidationAction
    {
        None = 0,
        CancelOperation = 1,
        UseAsIs = 2,
        RequestAgain = 3
    }

    public class ValidationResult
    {
        public Validity Validity { get; set; }
        public string FailedValidationMessage { get; set; }
        public string PromptForMoreInformation { get; set; }
        public string TitleForMoreInformation { get; set; }
        public int HelpContextId { get; set; }
        public ValidationAction ActionOnMoreInformationYes { get; set; }
        public ValidationAction ActionOnMoreInformationNo { get; set; }

        public static ValidationResult Valid { get; } = new ValidationResult() { Validity = Validity.Valid };
        public static ValidationResult Invalid(string failedValidationMessage) => new() { Validity = Validity.Invalid, FailedValidationMessage = failedValidationMessage };
    }
}
