using System.Diagnostics;
using Microsoft.VisualBasic;
using System;
using System.Collections.Generic;

using StatsDirect.Data;
using StatsDirect.Numerics;
using StatsDirect.Templates;
using StatsDirect.Utilities;
using StatsDirect.Expressions;
using System.Globalization;
using System.Linq;

namespace StatsDirect.Builtins
{
    public static class Sheet
    {
        private struct Catvar : IComparable<Catvar>
        {
            public string Title;
            public int Id;

            private int CompareTo(Catvar other)
            {
                if (double.TryParse(Title, out double mti) && double.TryParse(other.Title, out double oti))
                {
                    if (mti < oti)
                        return -1;
                    return mti == oti ? 0 : 1;
                }
                return string.CompareOrdinal(Title, other.Title);
            }
            // interface methods implemented by CompareTo
            int IComparable<Catvar>.CompareTo(Catvar other)
            {
                return CompareTo(other);
            }

        }

        private class SortPair : IComparable<SortPair>
        {
            public double Value { get; }
            public int Row { get; }

            private int CompareTo(SortPair other)
            {
                return Value.CompareTo(other.Value);
            }

            int IComparable<SortPair>.CompareTo(SortPair other)
            {
                return CompareTo(other);
            }

            public SortPair(double value, int row)
            {
                Value = value;
                Row = row;
            }
        }

        public static StepOutput ShtFillSeries(ParameterBag parameters)
        {
            int rows = parameters["rows"].AsInt32;
            if (rows < 1)
                rows = 100;
            if (rows > 1000000)
                rows = 1000000;
            double startval = parameters["startval"].AsDouble;
            string formula = parameters["formula"].AsString;
            // only an empty formula falls back to the default: "-X", "X" or "PI" are formulas too
            if (formula.Trim().Length == 0)
                formula = "x+1";

            string title = parameters["title"].AsString;
            if (title.Length < 1)
                title = "series=" + formula;

            double currentval = startval;
            DoubleVariable v = new(rows, title);
            Calcit c = new(formula, new[] { DataType.Double }, false);
            DataFrame outputFrame = new(v);
            double[] x = new double[1];
            for (int i = 0; i < rows; i++)
            {
                v.SetData(i, currentval);
                x[0] = currentval;
                currentval = c.Evaluate<double>(x);
            }
            ParameterBag outputParameters = new();
            outputParameters.AddOutput("output", outputFrame);
            return new StepOutput(outputParameters);
        }

        public static StepOutput ShtConvertUnits(ParameterBag parameters)
        {
            string conversion = parameters["conversion"].AsString;
            string[] splitConversion = conversion.Split('|');
            string formula = splitConversion[0];
            string outputUnits = splitConversion[1];
            // the built-in conversions are written with a decimal point: read them so whatever the regional settings (60 of the 68
            // could not be read where the comma is the decimal separator)
            Calcit c = new(formula, new[] { DataType.Double }, false, true);
            double[] x = new double[1];

            DataFrame dataFrame = parameters["data"].AsDataFrame;
            DataFrame outputFrame = new();
            foreach (IVariable inputVariable in dataFrame.Variables)
            {
                DoubleVariable dataVariable = (DoubleVariable)inputVariable;
                DoubleVariable outputVariable = new(dataVariable.Length, inputVariable.Title + " {" + outputUnits + "}");
                outputFrame.Variables.Add(outputVariable);
                double[] data = dataVariable.Data;
                double[] output = outputVariable.Data;
                for (int i = 0; i < data.Length; i++)
                {
                    if (data[i] == Constant.MISSING)
                        output[i] = Constant.MISSING;
                    else
                    {
                        x[0] = data[i];
                        output[i] = c.Evaluate<double>(x);
                    }
                }
            }
            ParameterBag outputParameters = new();
            outputParameters.AddOutput("output", outputFrame);
            return new StepOutput(outputParameters);
        }

        ///  <summary>
        ///  Returns a constant to add to all input values to ensure that all are greater than 0.
        ///  </summary>
        public static double XConstant(double[] data)
        {
            double minimum = double.MaxValue;
            for (int n = 0; n < data.Length; n++)
                if (data[n] != Constant.MISSING && data[n] < minimum)
                    minimum = data[n];
            return minimum < 0 ? Math.Abs(minimum) : Constant.MISSING;
        }

        public static StepOutput ShtClearMissing(ParameterBag parameters)
        {
            int r;
            int ctr;

            DataFrame data = parameters["data"].AsDataFrame;
            int totrows = data.MaxRows;
            int totcols = data.VariableCount;
            string[,] hold = new string[totrows + 1, totcols + 1];

            string clearRowString = parameters["row-or-cell"].AsString;
            bool clearRow = totcols > 1 && "row".Equals(clearRowString);
            double userNumber = parameters.ContainsKey("missing-double") ? parameters["missing-double"].AsDouble : Constant.MISSING;
            string userText = parameters.ContainsKey("missing-text") && parameters["missing-text"].AsString.Trim().Length > 0
                                  ? parameters["missing-text"].AsString
                                  : string.Empty;
            for (int c = 0; c < totcols; c++)
            {
                StringVariable v = (StringVariable)data.Variables[c];
                int rx = 0;
                for (r = 0; r < totrows; r++)
                {
                    rx++;
                    hold[rx, c] = v.Length <= r || IsMissing(v.Data[r], userNumber, userText) ? string.Empty : v.Data[r];
                }
                hold[0, c] = v.Title;
            }
            int maxctr = 0;
            // int lc = totcols; 

            //  Set up the output
            DataFrame outputFrame = new();
            for (int c = 0; c < totcols; c++)
            {
                string outputName = ((StringVariable)data.Variables[c]).Title;
                if (outputName.Length > 0)
                    outputName += " [no gaps]";
                StringVariable outputVariable = new(totrows, outputName);
                outputFrame.Variables.Add(outputVariable);
            }
            // lc = lc + 1; 
            if (clearRow)
            {
                ctr = 0;
                for (r = 1; r <= totrows; r++)
                {
                    int ctrx = 0;
                    for (int c = 0; c < totcols; c++)
                    {
                        if (hold[r, c].Length > 0)
                            ctrx++;
                    }
                    if (ctrx == totcols)
                    {
                        ctr++;
                        for (int c = 0; c < totcols; c++)
                        {
                            if (ctr > maxctr)
                                maxctr = ctr;
                            ((StringVariable)outputFrame.Variables[c]).SetData(ctr - 1, hold[r, c]);
                        }
                    }
                }
                for (int c = 0; c < totcols; c++)
                    outputFrame.Variables[c].EnsureLength(ctr);
            }
            else
            {
                for (int c = 0; c < totcols; c++)
                {
                    ctr = 0;
                    for (r = 1; r <= totrows; r++)
                    {
                        if (hold[r, c].Length > 0)
                        {
                            ctr++;
                            if (ctr > maxctr)
                                maxctr = ctr;
                            ((StringVariable)outputFrame.Variables[c]).SetData(ctr - 1, hold[r, c]);
                        }
                    }
                    outputFrame.Variables[c].EnsureLength(ctr);
                }
            }
            ParameterBag outputParameters = new();
            outputParameters.AddOutput("output", outputFrame);
            return new StepOutput(outputParameters);
        }

        public static bool IsMissing(string value, double userNumber, string userText)
        {
            if (double.TryParse(value, out double x))
            {
                // It's a double.  If it's MISSING, it's missing.
                if (x == Constant.MISSING)
                    return true;
                // If there is a user number and x is that user number, it's missing.
                return userNumber != Constant.MISSING && x == userNumber;
            }
            if (value == null || Formatting.ASTERISK.Equals(value) || "MISSING".Equals(value.ToUpper(CultureInfo.InvariantCulture)) || ".".Equals(value) || value.Trim().Length == 0)
                return true;

            return !string.IsNullOrEmpty(userText) && userText.Equals(value);
        }

        public static StepOutput ShtDummyVariables(ITemplateHost host, ParameterBag parameters)
        {
            DataFrame data = parameters["data"].AsDataFrame;
            ClassifierVariable categoryVariable = data.Variables[0] as ClassifierVariable;
            DataFrame outputFrame = ToDummyVariables(host, categoryVariable, false);
            ParameterBag outputParameters = new();
            outputParameters.AddOutput("output", outputFrame);
            return new StepOutput(outputParameters);
        }

        /// <returns>null if the user wishes to treat the data as continuous (in which case the caller should probably use the variable that has been passed in), otherwise a frame of dummies.</returns>
        public static DataFrame ToDummyVariables(ITemplateHost host, ClassifierVariable categoryVariable, bool allowContinuous)
        {
            int rows = categoryVariable.Length;
            int cats = categoryVariable.GroupCount;

            // find missing data category
            int mc = -1;
            for (int i = 0; i < cats; i++)
            {
                if (categoryVariable.Groups[i].Label == Formatting.MISSINGLABEL)
                {
                    mc = i;
                    break;
                }
            }

            // find the most prevalent category
            int maxcat = 0;
            int maxcatidx = 0;
            for (int i = 0; i < cats; i++)
            {
                if (i != mc && categoryVariable.Groups[i].NBin > maxcat)
                {
                    maxcat = categoryVariable.Groups[i].NBin;
                    maxcatidx = i;
                }
            }
            string maxcatti = categoryVariable.Groups[maxcatidx].Label;

            // get non-missing categories
            int ng = 1;
            double[] g = new double[cats];
            Catvar[] gcat = new Catvar[cats];
            for (int j = 0; j < rows; j++)
            {
                if (categoryVariable.Data[j] != mc && categoryVariable.Data[j] != Constant.MISSING)
                {
                    g[0] = categoryVariable.Data[j];
                    gcat[0].Title = categoryVariable.Groups[Convert.ToInt32(categoryVariable.Data[j])].Label;
                    gcat[0].Id = Convert.ToInt32(categoryVariable.Data[j]);
                    break;
                }
            }
            for (int j = 1; j < rows; j++)
            {
                bool newa = true;
                for (int i = 0; i < ng; i++)
                {
                    if (categoryVariable.Data[j] == g[i] || categoryVariable.Data[j] == mc || categoryVariable.Data[j] == Constant.MISSING)
                    {
                        newa = false;
                        break;
                    }
                }
                if (newa)
                {
                    g[ng] = categoryVariable.Data[j];
                    gcat[ng].Title = categoryVariable.Groups[Convert.ToInt32(categoryVariable.Data[j])].Label;
                    gcat[ng].Id = Convert.ToInt32(categoryVariable.Data[j]);
                    ng++;
                }
            }

            int dummies = ng - 1;
            if (dummies < 1)
            {
                host.Error("You must have more than one category in your data", "Dummy Variables");
                return null;
            }

            // sort categories by label to be consistent with Stata xi etc.
            Array.Sort(gcat, 0, ng);

            DummyOptions dm = new() { LargestCategoryTitle = maxcatti, CategoryNames = new List<string>(), VariableName = categoryVariable.Title, AllowUserToTreatAsContinuous = allowContinuous };
            for (int j = 0; j < ng; j++)
                dm.CategoryNames.Add(gcat[j].Title);
            bool wasOk = null != host.Amend(dm, new ParameterBag());
            if (!wasOk)
                throw new TemplateOperationCancelledException();

            DataFrame outputFrame = new();
            if (dm.TreatAsContinuous)
                return null;
            // Split to multiple dummies
            for (int j = 0; j < ng; j++)
            {
                if (j != dm.JDrop)
                {
                    string title = categoryVariable.Title + "(" + gcat[j].Title + ")";
                    DoubleVariable outputVariable = new(rows, title);
                    for (int r = 0; r < rows; r++)
                    {
                        // only enter if not missing category mc
                        if (categoryVariable.Data[r] != mc && categoryVariable.Data[r] != Constant.MISSING)
                            outputVariable.Data[r] = categoryVariable.Data[r] == gcat[j].Id ? 1 : 0;
                    }
                    outputFrame.Variables.Add(outputVariable);
                }
            }
            return outputFrame;
        }

        public static StepOutput ShtLadderPowers(ParameterBag parameters)
        {
            DataFrame data = parameters["data"].AsDataFrame;
            DoubleVariable inputVariable = (DoubleVariable)data.Variables[0];
            double cons = Constant.MISSING;
            if (parameters.ContainsKey("c"))
                cons = parameters["c"].AsDouble;
            bool skipMissing = cons == Constant.MISSING;
            if (skipMissing)
                cons = 0;
            string titleCore = inputVariable.Title;
            string logTitle = "ln(" + titleCore + ")";
            if (cons != 0)
            {
                titleCore = "(" + titleCore + " + " + cons.ToString(CultureInfo.CurrentCulture) + ")";
                logTitle = "ln" + titleCore;
            }

            DataFrame outputFrame = new();
            DoubleVariable minusTwoVariable = new(inputVariable.Length, titleCore + "^-2");
            outputFrame.Variables.Add(minusTwoVariable);
            DoubleVariable minusOneVariable = new(inputVariable.Length, titleCore + "^-1");
            outputFrame.Variables.Add(minusOneVariable);
            DoubleVariable minusHalfVariable = new(inputVariable.Length, titleCore + "^-0.5");
            outputFrame.Variables.Add(minusHalfVariable);
            DoubleVariable logVariable = new(inputVariable.Length, logTitle);
            outputFrame.Variables.Add(logVariable);
            DoubleVariable halfVariable = new(inputVariable.Length, titleCore + "^0.5");
            outputFrame.Variables.Add(halfVariable);
            DoubleVariable squaredVariable = new(inputVariable.Length, titleCore + "^2");
            outputFrame.Variables.Add(squaredVariable);

            for (int n = 0; n < inputVariable.Length; n++)
            {
                if (inputVariable.Data[n] == Constant.MISSING)
                {
                    minusTwoVariable.SetData(n, Constant.MISSING);
                    minusOneVariable.SetData(n, Constant.MISSING);
                    minusHalfVariable.SetData(n, Constant.MISSING);
                    logVariable.SetData(n, Constant.MISSING);
                    halfVariable.SetData(n, Constant.MISSING);
                    squaredVariable.SetData(n, Constant.MISSING);
                }
                else
                {
                    double z = inputVariable.Data[n] + cons;
                    // -2
                    if (z == 0)
                    {
                        minusTwoVariable.SetData(n, Constant.MISSING);
                    }
                    else
                    {
                        try
                        {
                            minusTwoVariable.SetData(n, Math.Pow(z, -2.0));
                        }
                        catch (Exception)
                        {
                            minusTwoVariable.Data[n] = Constant.MISSING;
                        }
                    }
                    // -1
                    minusOneVariable.SetData(n, z == 0 ? Constant.MISSING : Math.Pow(z, -1.0));
                    // -0.5
                    if (z <= 0)
                    {
                        minusHalfVariable.SetData(n, Constant.MISSING);
                    }
                    else
                    {
                        try
                        {
                            minusHalfVariable.SetData(n, Math.Pow(z, -0.5));
                        }
                        catch (Exception)
                        {
                            minusHalfVariable.Data[n] = Constant.MISSING;
                        }
                    }
                    // log
                    logVariable.SetData(n, z <= 0 ? Constant.MISSING : Math.Log(z));
                    // 0.5
                    if (z < 0)
                    {
                        halfVariable.SetData(n, Constant.MISSING);
                    }
                    else
                    {
                        try
                        {
                            halfVariable.SetData(n, Math.Pow(z, 0.5));
                        }
                        catch (Exception)
                        {
                            halfVariable.SetData(n, Constant.MISSING);
                        }
                    }
                    // 2
                    try
                    {
                        squaredVariable.SetData(n, Math.Pow(z, 2.0));
                    }
                    catch (Exception)
                    {
                        squaredVariable.SetData(n, Constant.MISSING);
                    }
                }
            }
            ParameterBag outputParameters = new();
            outputParameters.AddOutput("output", outputFrame);
            return new StepOutput(outputParameters);
        }

        internal static StepOutput RptChildGrowth(ITemplateHost host, ParameterBag parameters)
        {
            const double DEFAULT_GESTATIONAL_AGE_WEEKS = 40.0;

            string standardisation = parameters["standardisation"].AsString;
            string[] standardisationParts = standardisation.Split('|');
            string dataIs = standardisationParts[0];
            string standardiseIs = standardisationParts[1];
            string standard = parameters["standard"].AsString;
            string ageUnit = parameters.ContainsKey("age-unit") ? parameters["age-unit"].AsString : null;
            string sexCoding = parameters["sex-coding"].AsString;
            string zCorrectionString = parameters["z-correction"].AsString;
            ChildGrowthZCorrectionMode zCorrectionMode;
            switch (zCorrectionString)
            {
                case "all":
                    zCorrectionMode = ChildGrowthZCorrectionMode.All;
                    break;
                case "censor-5sd":
                    zCorrectionMode = ChildGrowthZCorrectionMode.Censor5Sd;
                    break;
                case "censor-3sd":
                    zCorrectionMode = ChildGrowthZCorrectionMode.Censor3Sd;
                    break;
                case "who":
                    zCorrectionMode = ChildGrowthZCorrectionMode.Who;
                    break;
                default:
                    throw new Exception("Unknown z correction '" + zCorrectionString + "'");
            }
            bool includeCentiles = parameters["include-centiles"].AsBoolean;
            DataFrame measureFrame = parameters["measure"].AsDataFrame;
            DoubleVariable measureVariable = (DoubleVariable)measureFrame.Variables[0];
            DataFrame xvarFrame = parameters["x"].AsDataFrame;
            DoubleVariable xvarVariable = (DoubleVariable)xvarFrame.Variables[0];
            DataFrame sexFrame = parameters["sex"].AsDataFrame;
            StringVariable sexVariable = (StringVariable)sexFrame.Variables[0];
            bool includeBmi = "BMI".Equals(dataIs);

            bool hasGestationalAge = parameters.ContainsKey("gestational-age");
            DoubleVariable gestationalAgeVariable = null;
            if (hasGestationalAge)
            {
                DataFrame gestationalAgeFrame = parameters["gestational-age"].AsDataFrame;
                gestationalAgeVariable = (DoubleVariable)gestationalAgeFrame.Variables[0];
            }

            double[] measure = measureVariable.Data;
            double[] xvar = xvarVariable.Data;
            string[] codedSex = sexVariable.Data;
            double[] gestationalAge = gestationalAgeVariable?.Data;
            bool[] isRowMissing = new bool[measure.Length];
            bool[] isMale = new bool[measure.Length];

            // Data preparation: Note missing values so we don't try to calculate the row.  Tight loops on arrays to encourage read-ahead and possible parallelisation by future compilers.
            for (int i = 0; i < measure.Length; i++)
                isRowMissing[i] |= measure[i] == Constant.MISSING;
            for (int i = 0; i < xvar.Length; i++)
                isRowMissing[i] |= xvar[i] == Constant.MISSING;
            if (hasGestationalAge)
                for (int i = 0; i < gestationalAge.Length; i++)
                    isRowMissing[i] |= gestationalAge[i] == Constant.MISSING;

            // Data preparation: Code sex to a boolean.  If we can't interpret it, set missing.
            switch (sexCoding)
            {
                case "f0m1":
                    for (int i = 0; i < codedSex.Length; i++)
                    {
                        string value = codedSex[i].Trim();
                        if ("0".Equals(value))
                            isMale[i] = false;
                        else if ("1".Equals(value))
                            isMale[i] = true;
                        else
                            isRowMissing[i] = true;
                    }
                    break;
                case "m0f1":
                    for (int i = 0; i < codedSex.Length; i++)
                    {
                        string value = codedSex[i].Trim();
                        if ("0".Equals(value))
                            isMale[i] = true;
                        else if ("1".Equals(value))
                            isMale[i] = false;
                        else
                            isRowMissing[i] = true;
                    }
                    break;
                case "f1m2":
                    for (int i = 0; i < codedSex.Length; i++)
                    {
                        string value = codedSex[i].Trim();
                        if ("1".Equals(value))
                            isMale[i] = false;
                        else if ("2".Equals(value))
                            isMale[i] = true;
                        else
                            isRowMissing[i] = true;
                    }
                    break;
                case "m1f2":
                    for (int i = 0; i < codedSex.Length; i++)
                    {
                        string value = codedSex[i].Trim();
                        if ("1".Equals(value))
                            isMale[i] = true;
                        else if ("2".Equals(value))
                            isMale[i] = false;
                        else
                            isRowMissing[i] = true;
                    }
                    break;
                case "mf":
                    for (int i = 0; i < codedSex.Length; i++)
                    {
                        string value = codedSex[i].Trim().ToLowerInvariant();
                        if ("m".Equals(value))
                            isMale[i] = true;
                        else if ("f".Equals(value))
                            isMale[i] = false;
                        else
                            isRowMissing[i] = true;
                    }
                    break;
                case "malefemale":
                    for (int i = 0; i < codedSex.Length; i++)
                    {
                        string value = codedSex[i].Trim().ToLowerInvariant();
                        if ("male".Equals(value))
                            isMale[i] = true;
                        else if ("female".Equals(value))
                            isMale[i] = false;
                        else
                            isRowMissing[i] = true;
                    }
                    break;
                default:
                    throw new Exception("Unknown sex coding '" + sexCoding + "'");
            }

            // Data preparation: Where ages aren't in years, standardise to years.
            double[] ageInYears = new double[xvar.Length];
            double[] tenThousandthsOfDay = new double[xvar.Length];
            if (null == ageUnit)
            {
                ageInYears = xvar;
                for (int i = 0; i < xvar.Length; i++)
                    tenThousandthsOfDay[i] = xvar[i] * 10000;
            }
            else
            {
                switch (ageUnit)
                {
                    case "year":
                        for (int i = 0; i < xvar.Length; i++)
                        {
                            ageInYears[i] = xvar[i];
                            tenThousandthsOfDay[i] = xvar[i] * 365.25 * 10000;
                        }
                        break;
                    case "month":
                        for (int i = 0; i < xvar.Length; i++)
                        {
                            ageInYears[i] = xvar[i] / 12.0;
                            tenThousandthsOfDay[i] = xvar[i] * (365.25 / 12.0) * 10000;
                        }
                        break;
                    case "week":
                        for (int i = 0; i < xvar.Length; i++)
                        {
                            ageInYears[i] = xvar[i] / (365.25 / 7.0);
                            tenThousandthsOfDay[i] = xvar[i] * 7.0 * 10000;
                        }
                        break;
                    case "day":
                        for (int i = 0; i < xvar.Length; i++)
                        {
                            ageInYears[i] = xvar[i] / 365.25;
                            tenThousandthsOfDay[i] = xvar[i] * 10000;
                        }
                        break;
                    default:
                        throw new Exception("Unknown age unit '" + ageUnit + "'");
                }
            }
            // Data preparation: Correct for gestational age where not 40 weeks
            if (hasGestationalAge)
            {
                double maxGestationalAge = double.MinValue;
                for (int i = 0; i < ageInYears.Length; i++)
                {
                    double gestationalAgeInWeeks = gestationalAge[i];
                    if (gestationalAgeInWeeks > maxGestationalAge)
                        maxGestationalAge = gestationalAgeInWeeks;
                    ageInYears[i] += (gestationalAgeInWeeks - DEFAULT_GESTATIONAL_AGE_WEEKS) * 7.0 / 365.0;
                }
                if (maxGestationalAge > 42)
                    host.Warning("Maximum value in your gestational age variable is " + maxGestationalAge + " weeks", "Anthropometric standardisation");
            }

            // Work out which tables to use
            List<string> maleTableNames = new();
            List<string> femaleTableNames = new();
            string parameterName = dataIs + "-" + standardiseIs + "-" + standard;
            foreach (KeyValuePair<string, FilledParameter> pair in parameters)
            {
                if (pair.Key.StartsWith(parameterName))
                {
                    if (pair.Key.Contains("-female"))
                        femaleTableNames.Add(pair.Key);
                    else
                        maleTableNames.Add(pair.Key);
                }
            }

            // Tables are named by ascending order of the standard, but zanthro always uses data from the older row where two rows would match.  Duplicate this by putting "older" tables (higher names) higher up our preference list.
            maleTableNames = maleTableNames.OrderByDescending(name => name).ToList();
            femaleTableNames = femaleTableNames.OrderByDescending(name => name).ToList();

            List<LmsTable> maleTables = new(maleTableNames.Count);
            List<LmsTable> femaleTables = new(femaleTableNames.Count);
            foreach (string name in maleTableNames)
                maleTables.Add(ToLmsTable(parameters[name].AsDataFrame));
            foreach (string name in femaleTableNames)
                femaleTables.Add(ToLmsTable(parameters[name].AsDataFrame));

            BmiCategoryTable maleBmiCategories = includeBmi ? ToBmiCategoryTable(parameters["bmicat-male"].AsDataFrame) : null;
            BmiCategoryTable femaleBmiCategories = includeBmi ? ToBmiCategoryTable(parameters["bmicat-female"].AsDataFrame) : null;

            // Output arrays
            double[] uncorrectedZ = new double[measure.Length];
            double[] correctedZ = new double[measure.Length];
            double[] centile = includeCentiles ? new double[measure.Length] : null;
            string[] bmiCategory = includeBmi ? new string[measure.Length] : null;

            // Run the calculation for each row
            for (int i = 0; i < measure.Length; i++)
            {
                // If any input data is missing, set all output data missing and carry on.
                if (isRowMissing[i])
                {
                    uncorrectedZ[i] = Constant.MISSING;
                    correctedZ[i] = Constant.MISSING;
                    if (includeCentiles)
                        centile[i] = Constant.MISSING;
                    if (includeBmi)
                        bmiCategory[i] = Formatting.MISSINGLABEL;
                    continue;
                }

                uncorrectedZ[i] = ChildGrowthCalculateUncorrectedZ(isMale[i] ? maleTables : femaleTables, measure[i], ageInYears[i], tenThousandthsOfDay[i], out double lambda, out double mu, out double sigma);
                correctedZ[i] = ChildGrowthCorrectZ(uncorrectedZ[i], zCorrectionMode, measure[i], lambda, mu, sigma);
                if (includeCentiles)
                    centile[i] = Constant.MISSING == correctedZ[i] ? Constant.MISSING : PDF.alnorm(correctedZ[i]) * 100.0;
                if (includeBmi)
                    bmiCategory[i] = ChildGrowthCalculateBmiCategory(isMale[i] ? maleBmiCategories : femaleBmiCategories, measure[i], ageInYears[i]);
            }

            ParameterBag outputParameters = new();
            DataFrame outputFrame = new();
            outputFrame.Variables.Add(new DoubleVariable(correctedZ, "z " + dataIs));
            if (includeCentiles)
                outputFrame.Variables.Add(new DoubleVariable(centile, "Percentile"));
            if (includeBmi)
                outputFrame.Variables.Add(new StringVariable(bmiCategory, "BMI category"));
            outputParameters.AddOutput("output", outputFrame);
            return new StepOutput(outputParameters);
        }

        private static string ChildGrowthCalculateBmiCategory(BmiCategoryTable table, double bmi, double age)
        {
            // Use a row if the value being considered is at least the row's age and less than the next row's age.
            // The -1 is deliberate here; the last row of the table isn't usable, it merely provides an upper age.
            for (int i = 0; i < table.Rows.Length - 1; i++)
            {
                BmiCategoryTableRow candidate = table.Rows[i];
                if (candidate.Age <= age && table.Rows[i + 1].Age >= age)
                    return ChildGrowthCalculateBmiCategory(table.Rows[i], bmi, age);
            }
            // If we get here, no row matched
            return Formatting.MISSINGLABEL;
        }

        private static string ChildGrowthCalculateBmiCategory(BmiCategoryTableRow tableRow, double bmi, double age)
        {
            if (bmi < Interpolate(age, tableRow.Q16))
                return "Grade 3 thinness";
            if (bmi < Interpolate(age, tableRow.Q17))
                return "Grade 2 thinness";
            if (bmi < Interpolate(age, tableRow.Q18_5))
                return "Grade 1 thinness";
            if (bmi < Interpolate(age, tableRow.Q25))
                return "Normal wt";
            if (bmi < Interpolate(age, tableRow.Q30))
                return "Overweight";
            return "Obese";
        }

        private static LmsTable ToLmsTable(DataFrame frame)
        {
            // Assumption: Columns are xmrg, 4 x xvar, 4 x l, 4 x m, 4 x s.
            // Assumption: l, m, s all have _pre, unnamed, _nx, _nx2 in that order.
            LmsTable table = new() { Rows = new LambdaMuSigmaTableRow[frame.MinRows] };
            double[] variable0 = ((DoubleVariable)frame.Variables[0]).Data;
            double[] variable1 = ((DoubleVariable)frame.Variables[1]).Data;
            double[] variable2 = ((DoubleVariable)frame.Variables[2]).Data;
            double[] variable3 = ((DoubleVariable)frame.Variables[3]).Data;
            double[] variable4 = ((DoubleVariable)frame.Variables[4]).Data;
            double[] variable5 = ((DoubleVariable)frame.Variables[5]).Data;
            double[] variable6 = ((DoubleVariable)frame.Variables[6]).Data;
            double[] variable7 = ((DoubleVariable)frame.Variables[7]).Data;
            double[] variable8 = ((DoubleVariable)frame.Variables[8]).Data;
            double[] variable9 = ((DoubleVariable)frame.Variables[9]).Data;
            double[] variable10 = ((DoubleVariable)frame.Variables[10]).Data;
            double[] variable11 = ((DoubleVariable)frame.Variables[11]).Data;
            double[] variable12 = ((DoubleVariable)frame.Variables[12]).Data;
            double[] variable13 = ((DoubleVariable)frame.Variables[13]).Data;
            double[] variable14 = ((DoubleVariable)frame.Variables[14]).Data;
            double[] variable15 = ((DoubleVariable)frame.Variables[15]).Data;
            double[] variable16 = ((DoubleVariable)frame.Variables[16]).Data;
            for (int row = 0; row < frame.MinRows; row++)
            {
                table.Rows[row] = new LambdaMuSigmaTableRow
                {
                    Xmrg = variable0[row],
                    Xvars =
                    {
                        Previous = variable1[row],
                        Value = variable2[row],
                        Next = variable3[row],
                        NextNext = variable4[row]
                    },
                    Lambdas =
                    {
                        Previous = variable5[row],
                        Value = variable6[row],
                        Next = variable7[row],
                        NextNext = variable8[row]
                    },
                    Mus =
                    {
                        Previous = variable9[row],
                        Value = variable10[row],
                        Next = variable11[row],
                        NextNext = variable12[row]
                    },
                    Sigmas =
                    {
                        Previous = variable13[row],
                        Value = variable14[row],
                        Next = variable15[row],
                        NextNext = variable16[row]
                    }
                };
            }
            return table;
        }

        private static BmiCategoryTable ToBmiCategoryTable(DataFrame frame)
        {
            // Assumption: Columns are age, 4 x 16, 4 x 17, 4 x 18.5, 4 x 25, 4 x 30.
            // Assumption: The quads all have _pre, unnamed, _nx, _nx2 in that order.
            BmiCategoryTable table = new() { Rows = new BmiCategoryTableRow[frame.MinRows] };
            double[] variable0 = ((DoubleVariable)frame.Variables[0]).Data;
            double[] variable1 = ((DoubleVariable)frame.Variables[1]).Data;
            double[] variable2 = ((DoubleVariable)frame.Variables[2]).Data;
            double[] variable3 = ((DoubleVariable)frame.Variables[3]).Data;
            double[] variable4 = ((DoubleVariable)frame.Variables[4]).Data;
            double[] variable5 = ((DoubleVariable)frame.Variables[5]).Data;
            double[] variable6 = ((DoubleVariable)frame.Variables[6]).Data;
            double[] variable7 = ((DoubleVariable)frame.Variables[7]).Data;
            double[] variable8 = ((DoubleVariable)frame.Variables[8]).Data;
            double[] variable9 = ((DoubleVariable)frame.Variables[9]).Data;
            double[] variable10 = ((DoubleVariable)frame.Variables[10]).Data;
            double[] variable11 = ((DoubleVariable)frame.Variables[11]).Data;
            double[] variable12 = ((DoubleVariable)frame.Variables[12]).Data;
            double[] variable13 = ((DoubleVariable)frame.Variables[13]).Data;
            double[] variable14 = ((DoubleVariable)frame.Variables[14]).Data;
            double[] variable15 = ((DoubleVariable)frame.Variables[15]).Data;
            double[] variable16 = ((DoubleVariable)frame.Variables[16]).Data;
            double[] variable17 = ((DoubleVariable)frame.Variables[17]).Data;
            double[] variable18 = ((DoubleVariable)frame.Variables[18]).Data;
            double[] variable19 = ((DoubleVariable)frame.Variables[19]).Data;
            double[] variable20 = ((DoubleVariable)frame.Variables[20]).Data;
            for (int row = 0; row < frame.MinRows; row++)
            {
                table.Rows[row] = new BmiCategoryTableRow
                {
                    Age = variable0[row],
                    Q16 =
                    {
                        Previous = variable1[row],
                        Value = variable2[row],
                        Next = variable3[row],
                        NextNext = variable4[row]
                    },
                    Q17 =
                    {
                        Previous = variable5[row],
                        Value = variable6[row],
                        Next = variable7[row],
                        NextNext = variable8[row]
                    },
                    Q18_5 =
                    {
                        Previous = variable9[row],
                        Value = variable10[row],
                        Next = variable11[row],
                        NextNext = variable12[row]
                    },
                    Q25 =
                    {
                        Previous = variable13[row],
                        Value = variable14[row],
                        Next = variable15[row],
                        NextNext = variable16[row]
                    },
                    Q30 =
                    {
                        Previous = variable17[row],
                        Value = variable18[row],
                        Next = variable19[row],
                        NextNext = variable20[row]
                    }
                };
            }
            return table;
        }

        private static double ChildGrowthCorrectZ(double rawZ, ChildGrowthZCorrectionMode zCorrectionMode, double y, double lambda, double mu, double sigma)
        {
            if (Constant.MISSING == rawZ)
                return rawZ;

            switch (zCorrectionMode)
            {
                case ChildGrowthZCorrectionMode.All:
                    return rawZ;
                case ChildGrowthZCorrectionMode.Censor3Sd:
                    return Math.Abs(rawZ) > 3.0 ? Constant.MISSING : rawZ;
                case ChildGrowthZCorrectionMode.Censor5Sd:
                    return Math.Abs(rawZ) > 5.0 ? Constant.MISSING : rawZ;
                case ChildGrowthZCorrectionMode.Who:
                    // For -3 <= z <= 3, use the uncorrected score
                    if (Math.Abs(rawZ) <= 3)
                        return rawZ;
                    // Otherwise, it's at one extreme or the other.
                    if (rawZ > 0)
                    {
                        double sd3Pos = WhoCutoff(3, lambda, mu, sigma);
                        double sd2Pos = WhoCutoff(2, lambda, mu, sigma);
                        double sd23Pos = sd3Pos - sd2Pos;
                        return 3 + (y - sd3Pos) / sd23Pos;
                    }
                    else
                    {
                        double sd3Neg = WhoCutoff(-3, lambda, mu, sigma);
                        double sd2Neg = WhoCutoff(-2, lambda, mu, sigma);
                        double sd23Neg = sd2Neg - sd3Neg;
                        return -3 + (y - sd3Neg) / sd23Neg;
                    }
                default:
                    throw new Exception("Unknown Z correction mode " + zCorrectionMode);
            }
        }

        private static double WhoCutoff(double z, double lambda, double mu, double sigma)
        {
            return mu * Math.Pow(1 + lambda * sigma * z, 1.0 / lambda);
        }

        private enum ChildGrowthZCorrectionMode
        {
            All = 0,
            Censor5Sd = 1,
            Censor3Sd = 2,
            Who = 3
        }

        public class LmsTable
        {
            public double XmrgLowerBound => Rows[0].Xmrg;
            public double XmrgUpperBound => Rows[Rows.Length - 1].Xmrg;
            public LambdaMuSigmaTableRow[] Rows { get; set; }
        }

        public class LambdaMuSigmaTableRow
        {
            public double Xmrg;
            public InterpolationQuad Xvars;
            public InterpolationQuad Lambdas;
            public InterpolationQuad Mus;
            public InterpolationQuad Sigmas;
        }

        public class BmiCategoryTable
        {
            public BmiCategoryTableRow[] Rows { get; set; }
        }

        public class BmiCategoryTableRow
        {
            public double Age;
            public InterpolationQuad Q16;
            public InterpolationQuad Q17;
            public InterpolationQuad Q18_5;
            public InterpolationQuad Q25;
            public InterpolationQuad Q30;
        }

        public struct InterpolationQuad
        {
            public double Previous;
            public double Value;
            public double Next;
            public double NextNext;
        }

        private static double ChildGrowthCalculateUncorrectedZ(ICollection<LmsTable> tables, double measure, double t, double tenThousandthsOfDay, out double lambda, out double mu, out double sigma)
        {
            // Find the correct table to use. Tables are passed in order of preference, so simply use the first one that matches.
            foreach (LmsTable table in tables)
                if (table.XmrgLowerBound <= tenThousandthsOfDay && table.XmrgUpperBound >= tenThousandthsOfDay)
                    return ChildGrowthCalculateUncorrectedZ(table, measure, t, tenThousandthsOfDay, out lambda, out mu, out sigma);
            // If we get here, no table matched.
            lambda = mu = sigma = Constant.MISSING;
            return Constant.MISSING;
        }

        private static double ChildGrowthCalculateUncorrectedZ(LmsTable table, double measure, double t, double tenThousandthsOfDay, out double lambda, out double mu, out double sigma)
        {
            // We already know the value is within the bounds of this table; it's just a case of finding which row.
            // Use a row if the value being considered is at least the row's xmrg and less than the next row's xmrg.
            for (int i = 0; i < table.Rows.Length; i++)
            {
                LambdaMuSigmaTableRow candidate = table.Rows[i];
                if (candidate.Xmrg <= tenThousandthsOfDay && (i == table.Rows.Length - 1 || table.Rows[i + 1].Xmrg >= tenThousandthsOfDay))
                    return ChildGrowthCalculateUncorrectedZ(table.Rows[i], measure, t, out lambda, out mu, out sigma);
            }
            // If we get here, no row matched despite the table having rows that must match.  Assume the final row.
            return ChildGrowthCalculateUncorrectedZ(table.Rows[table.Rows.Length - 1], measure, t, out lambda, out mu, out sigma);
        }

        private static double ChildGrowthCalculateUncorrectedZ(LambdaMuSigmaTableRow tableRow, double measure, double t, out double lambda, out double mu, out double sigma)
        {
            // t is the corrected xvar - turned into years for any age, TODO: Not sure for ht/wt.
            lambda = Interpolate(t, tableRow.Xvars, tableRow.Lambdas);
            mu = Interpolate(t, tableRow.Xvars, tableRow.Mus);
            sigma = Interpolate(t, tableRow.Xvars, tableRow.Sigmas);

            double z = (Math.Pow(measure / mu, lambda) - 1) / (lambda * sigma);
            return z;
        }

        private static double Interpolate(double age, InterpolationQuad quad)
        {
            // If we have all values, cubic interpolation is appropriate.
            if (quad.Previous != Constant.MISSING && quad.Value != Constant.MISSING && quad.Next != Constant.MISSING && quad.NextNext != Constant.MISSING)
                return CubicInterpolate(age, quad);
            // If we have current and next, linear interpolation is appropriate.
            if (quad.Value != Constant.MISSING && quad.Next != Constant.MISSING)
                return LinearInterpolate(age, quad);
            // If we're missing even these, there's not a lot we can do.
            throw new NotImplementedException("The table you're aiming to use has an error for value " + age + ": there's not enough data for a cubic or linear interpolation.");
        }

        private static double LinearInterpolate(double age, InterpolationQuad quad)
        {
            const double ROW_AGE_SPAN = 0.5; // years
            double ageInWholeYears = Math.Floor(age);
            double halfYearAge = ageInWholeYears + (age - ageInWholeYears >= 0.5 ? 0.5 : 0);

            double agefrac = (age - halfYearAge) / ROW_AGE_SPAN;
            return quad.Value + agefrac * (quad.Next - quad.Value);
        }

        private static double CubicInterpolate(double age, InterpolationQuad quad)
        {
            const double ROW_AGE_SPAN = 0.5; // years

            double ageInWholeYears = Math.Floor(age);
            double halfYearAge = ageInWholeYears + (age - ageInWholeYears >= 0.5 ? 0.5 : 0);

            double agefrac = (age - halfYearAge) / ROW_AGE_SPAN;
            double agefrac2 = agefrac * agefrac;

            double a0 = (0.0 - quad.Previous) / 6.0 + quad.Value / 2.0 - quad.Next / 2.0 + quad.NextNext / 6.0;
            double a1 = quad.Previous / 2.0 - quad.Value + quad.Next / 2.0;
            double a2 = (0.0 - quad.Previous) / 3.0 - quad.Value / 2.0 + quad.Next - quad.NextNext / 6.0;
            double a3 = quad.Value;
            return a0 * agefrac * agefrac2 + a1 * agefrac2 + a2 * agefrac + a3;
        }

        private static double Interpolate(double t, InterpolationQuad xvar, InterpolationQuad lms)
        {
            // If we have all values, cubic interpolation is appropriate.
            if (xvar.Previous != Constant.MISSING && xvar.Value != Constant.MISSING && xvar.Next != Constant.MISSING && xvar.NextNext != Constant.MISSING
                && lms.Previous != Constant.MISSING && lms.Value != Constant.MISSING && lms.Next != Constant.MISSING && lms.NextNext != Constant.MISSING)
                return CubicInterpolate(t, xvar, lms);
            // If we have current and next, linear interpolation is appropriate.
            if (xvar.Value != Constant.MISSING && xvar.Next != Constant.MISSING
                && lms.Value != Constant.MISSING && lms.Next != Constant.MISSING)
                return LinearInterpolate(t, xvar, lms);
            // If we're missing even these, there's not a lot we can do.
            throw new NotImplementedException("The table you're aiming to use has an error for value " + t + ": there's not enough data for a cubic or linear interpolation.");
        }

        private static double CubicInterpolate(double t, InterpolationQuad xvar, InterpolationQuad lms)
        {
            return lms.Previous * (t - xvar.Value) * (t - xvar.Next) * (t - xvar.NextNext) / ((xvar.Previous - xvar.Value) * (xvar.Previous - xvar.Next) * (xvar.Previous - xvar.NextNext))
                + lms.Value * (t - xvar.Previous) * (t - xvar.Next) * (t - xvar.NextNext) / ((xvar.Value - xvar.Previous) * (xvar.Value - xvar.Next) * (xvar.Value - xvar.NextNext))
                + lms.Next * (t - xvar.Previous) * (t - xvar.Value) * (t - xvar.NextNext) / ((xvar.Next - xvar.Previous) * (xvar.Next - xvar.Value) * (xvar.Next - xvar.NextNext))
                + lms.NextNext * (t - xvar.Previous) * (t - xvar.Value) * (t - xvar.Next) / ((xvar.NextNext - xvar.Previous) * (xvar.NextNext - xvar.Value) * (xvar.NextNext - xvar.Next));
        }

        private static double LinearInterpolate(double t, InterpolationQuad xvar, InterpolationQuad lms)
        {
            double xvarfrac = (t - xvar.Value) / (xvar.Next - xvar.Value);
            return lms.Value + xvarfrac * (lms.Next - lms.Value);
        }

        internal static StepOutput ShtFindAndReplaceAdvanced(ParameterBag parameters)
        {
            DataFrame inputFrame = parameters["data"].AsDataFrame;
            string searchRule = parameters["search-rule"].AsString;
            bool hasSearchExpression = !("blank".Equals(searchRule));
            string userSearchExpression = hasSearchExpression ? parameters["search-expression"].AsString : string.Empty;
            string action = parameters["action"].AsString;
            string replaceExpression = parameters.ContainsKey("replace-expression") ? parameters["replace-expression"].AsString : null;

            bool isNumeric = "numeric".Equals(parameters["search-type"].AsString) && hasSearchExpression;
            DataType inputType = isNumeric ? DataType.Double : DataType.String;

            // Use the expression parser and evaluator to make this simple
            string wrappedUserSearchExpression = isNumeric ? userSearchExpression : "\"" + userSearchExpression.Replace("\"", "\"\"") + "\"";
            string searchExpression;
            switch (searchRule)
            {
                case "blank":
                case "equal":
                    searchExpression = "X = " + wrappedUserSearchExpression;
                    break;
                case "gt":
                    searchExpression = "X > " + wrappedUserSearchExpression;
                    break;
                case "lt":
                    searchExpression = "X < " + wrappedUserSearchExpression;
                    break;
                case "ge":
                    searchExpression = "X >= " + wrappedUserSearchExpression;
                    break;
                case "le":
                    searchExpression = "X <= " + wrappedUserSearchExpression;
                    break;
                case "ne":
                    searchExpression = "X <> " + wrappedUserSearchExpression;
                    break;
                case "match":
                    searchExpression = userSearchExpression;
                    break;
                default:
                    throw new Exception("Unknown operation");
            }
            Calcit searcher = new(searchExpression, new[] { inputType }, true);
            if (searcher.OutputType != DataType.Boolean)
                throw new Exception("Please specify a valid search expression");

            // Output
            bool counting = "count".Equals(action);
            bool deletingCells = "delete-cells".Equals(action);
            bool deletingRows = "delete-rows".Equals(action);
            bool replacingWithValue = "replace-value".Equals(action);
            bool replacingWithExpression = "replace-expression".Equals(action);

            Calcit replacer = null;
            if (replacingWithExpression)
                replacer = new Calcit(replaceExpression, new[] { inputType }, true);

            DataFrame outputFrame = new();
            bool[] rowsToDelete = new bool[inputFrame.MaxRows];
            int matches = 0;
            object[] values = new object[1];
            foreach (IVariable inputVariable in inputFrame.Variables)
            {
                // Use a VariantVariable as we're not sure what the result of the replace will be
                IVariable outputVariable = new VariantVariable();
                outputVariable.EnsureLength(inputVariable.Length);
                outputVariable.Title = inputVariable.Title;
                outputFrame.Variables.Add(outputVariable);
                int outputIndex = 0;
                for (int inputIndex = 0; inputIndex < inputVariable.Length; inputIndex++)
                {
                    values[0] = inputVariable.DataAsObject(inputIndex);
                    // A missing numeric cell holds a huge negative sentinel: it matched "X < 0", and a replacement such as -X or ABS(X)
                    // turned it into +1.8E308, which is no longer recognised as missing. It is passed through untouched, as the other
                    // worksheet functions do.
                    bool isMissingNumber = values[0] is double cellValue && (cellValue == Constant.MISSING || double.IsNaN(cellValue));
                    bool isMatch = !isMissingNumber && searcher.EvaluateObject<bool>(values);
                    if (isMatch)
                    {
                        matches++; // In case counting - faster to just do this than branch and cause a bubble in the CPU pipeline.
                        // If deleting matching cells, do nothing - this avoids copying the value to the output, effectively deleting it.
                        rowsToDelete[inputIndex] = true; // In case deleting rows - probably faster to just do this than branch.
                        if (replacingWithValue)
                            outputVariable.DataAsObject(outputIndex++, replaceExpression);
                        else if (replacingWithExpression)
                        {
                            // values still holds the value we need; we can simply re-use it.
                            outputVariable.DataAsObject(outputIndex++, replacer.EvaluateObject<object>(values));
                        }
                    }
                    else
                    {
                        outputVariable.DataAsObject(outputIndex++, inputVariable.DataAsObject(inputIndex));
                    }
                }
                // If deleting cells, the output variable may well be shorter than the input.
                if (deletingCells)
                    outputVariable.TruncateDataToLength(outputIndex);
            }

            // If deleting rows, knock out any that have been detected.
            if (deletingRows)
            {
                foreach (GenericVariable<object> vv in outputFrame.Variables)
                {
                    int outputLocation = 0;
                    for (int i = 0; i < vv.Length; i++)
                        if (!rowsToDelete[i])
                            vv.Data[outputLocation++] = vv.Data[i];
                    vv.TruncateDataToLength(outputLocation);
                }
            }

            ParameterBag outputParameters = new();
            outputParameters.AddOutput("matches", matches);
            outputParameters.AddOutput("output", outputFrame);
            return new StepOutput(outputParameters);
        }

        public static StepOutput ShtStandardize(ParameterBag parameters)
        {
            string msd = parameters["mode"].AsString;
            int method;
            string lab;
            if ("msd".Equals(msd))
            {
                method = 1;
                lab = "(x-mean)/SD";
            }
            else if ("sd".Equals(msd))
            {
                method = 2;
                lab = "x/SD";
            }
            else if ("m".Equals(msd))
            {
                method = 3;
                lab = "x-mean";
            }
            else if ("ecdf".Equals(msd))
            {
                method = 4;
                lab = "ecdf";
            }
            else
            {
                throw new ArgumentException("Unknown method");
            }

            DataFrame data = parameters["data"].AsDataFrame;
            DoubleVariable inputVariable = (DoubleVariable)data.Variables[0];
            double[] inputData = inputVariable.Data;
            double sum = 0;
            int nx = 0;
            foreach (double value in inputData)
            {
                if (value != Constant.MISSING)
                {
                    nx++;
                    sum += value;
                }
            }
            double mean = sum / nx;
            double ssq = 0;
            foreach (double value in inputData)
            {
                ssq += (value - mean) * (value - mean);
            }
            double sd = Math.Sqrt(ssq / (nx - 1));
            // int lc = 1; 
            string pre = "Std (" + lab + "): ";

            DataFrame outputFrame = new();
            DoubleVariable outputVariable = new(inputVariable.Length, pre + inputVariable.Title);
            outputFrame.Variables.Add(outputVariable);
            if (method == 4)
            {
                MathDbl.ecdf(inputVariable.Data, outputVariable.Data, out int ierr);
                if (ierr == 1)
                    throw new ArgumentException("Must have at least 3 data values to calculate empirical CDF");
            }
            else
            {
                for (int c = 0; c < inputVariable.Length; c++)
                {
                    double x = inputVariable.Data[c];
                    if (inputVariable.Data[c] != Constant.MISSING)
                    {
                        double tr;
                        switch (method)
                        {
                            case 1:
                                if (sd != 0.0)
                                    tr = (x - mean) / sd;
                                else
                                    tr = Constant.MISSING;
                                break;
                            case 2:
                                if (sd != 0.0)
                                    tr = x / sd;
                                else
                                    tr = Constant.MISSING;
                                break;
                            default:
                                tr = x - mean;
                                break;
                        }

                        outputVariable.SetData(c, tr);
                    }
                    else
                    {
                        outputVariable.SetData(c, Constant.MISSING);
                    }
                }
            }

            ParameterBag outputParameters = new();
            outputParameters.AddOutput("output", outputFrame);
            return new StepOutput(outputParameters);
        }

        public static double XSpr(double q)
        {
            // TODO: This can never work as we're off the top of what double can represent.  Should we be using IsInfinity here?
            double q1 = Math.Abs(q) > double.MaxValue ? Constant.MISSING : q;
            return double.IsNaN(q) ? Constant.MISSING : q1;
        }

        public static StepOutput ShtCombine(ParameterBag parameters)
        {
            int totrows = 0;
            int ep;
            string gpti = null; string datti = null; string lastgpti = null; string lastdatti = null;

            DataFrame data = parameters["data"].AsDataFrame;
            foreach (IVariable v in data.Variables)
                totrows += v.Length;

            // reconstitute original labels if split using split function --->
            bool ok = true;
            for (int c = 0; c < data.VariableCount; c++)
            {
                DoubleVariable v = (DoubleVariable)data.Variables[c];
                ep = v.Title.IndexOf("=", StringComparison.Ordinal);
                int tp = v.Title.IndexOf("~", StringComparison.Ordinal);
                if (ep < 0 || tp < 0 || tp > ep)
                {
                    ok = false;
                    break;
                }
                datti = v.Title.Substring(0, tp);
                if (!string.IsNullOrEmpty(lastdatti) && datti != lastdatti)
                {
                    ok = false;
                    break;
                }
                lastdatti = datti;
                gpti = v.Title.Substring(tp + 1, ep - tp - 1);
                if (!string.IsNullOrEmpty(lastgpti) && gpti != lastgpti)
                {
                    ok = false;
                    break;
                }
                lastgpti = gpti;
            }
            // <---
            if (!ok)
            {
                datti = "Data";
                gpti = "Group ID";
            }
            DataFrame outputFrame = new();
            StringVariable groupVariable = new(totrows, gpti);
            outputFrame.Variables.Add(groupVariable);
            DoubleVariable dataVariable = new(totrows, datti);
            outputFrame.Variables.Add(dataVariable);
            int row = 0;
            for (int c = 0; c < data.VariableCount; c++)
            {
                DoubleVariable v = (DoubleVariable)data.Variables[c];
                ep = v.Title.IndexOf("=", StringComparison.Ordinal) + 1;
                string outputTitle = v.Title;
                if (ok)
                {
                    groupVariable.SetData(row, v.Title.Substring(v.Title.Length - v.Title.Length - ep));
                }
                foreach (double value in v.Data)
                {
                    groupVariable.SetData(row, outputTitle);
                    dataVariable.SetData(row, value);
                    row += 1;
                }
            }

            ParameterBag outputParameters = new();
            outputParameters.AddOutput("output", outputFrame);
            return new StepOutput(outputParameters);
        }

        public static StepOutput ShtDates(ParameterBag parameters)
        {
            DataFrame data = parameters["data"].AsDataFrame;
            GenericVariable<DateTime> inputVariable = (GenericVariable<DateTime>)data.Variables[0];

            string interval = parameters["interval"].AsString;
            DateTime indate = parameters["indate"].AsDate;
            string q;
            switch (interval)
            {
                case "yyyy":
                    q = "Years";
                    break;
                case "m":
                    q = "Months";
                    break;
                case "w":
                    q = "Weeks";
                    break;
                case "d":
                    q = "Days";
                    break;
                case "h":
                    q = "Hours";
                    break;
                case "n":
                    q = "Minutes";
                    break;
                case "s":
                    q = "Seconds";
                    break;
                default:
                    throw new ArgumentException("parameters[interval]: Unexpected interval", nameof(parameters));
            }

            string outputTitle = inputVariable.Title + "~" + q + " from " + indate;
            DataFrame outputFrame = new();
            DoubleVariable outputVariable = new(inputVariable.Length, outputTitle);
            outputFrame.Variables.Add(outputVariable);
            for (int i = 0; i < inputVariable.Length; i++)
            {
                if (inputVariable.Data[i] == DateTime.MinValue)
                    outputVariable.Data[i] = Constant.MISSING;
                else
                    outputVariable.Data[i] = DateAndTime.DateDiff(interval, indate, inputVariable.Data[i]);
            }

            ParameterBag outputParameters = new();
            outputParameters.AddOutput("output", outputFrame);
            return new StepOutput(outputParameters);
        }

        public static StepOutput ShtGroupSplit(ParameterBag parameters)
        {
            DataFrame gidsFrame = parameters["gids"].AsDataFrame;
            ClassifierVariable gidsVariable = (ClassifierVariable)gidsFrame.Variables[0];
            int rows = gidsVariable.Length;
            int ng = gidsVariable.GroupCount;
            string[] glabel = new string[ng];
            double[] g = new double[ng];
            for (int group = 0; group < ng; group++)
            {
                glabel[group] = gidsVariable.Title == "Group ID" 
                    ? gidsVariable.Groups[group].Label 
                    : gidsVariable.Title + "=" + gidsVariable.Groups[group].Label;
                g[group] = gidsVariable.Groups[group].Label == Formatting.MISSINGLABEL 
                    ? Constant.MISSING 
                    : group;
            }

            DataFrame data = parameters["data"].AsDataFrame;
            int cols = data.VariableCount;

            DataFrame outputFrame = new();
            int lc = 0;
            for (int j = 0; j < ng; j++)
            {
                for (int c = 0; c < cols; c++)
                {
                    string variableName = data.Variables[c].Title == "Data" ? glabel[j] : data.Variables[c].Title + "~" + glabel[j];
                    outputFrame.Variables.Add(new DoubleVariable(rows, variableName));
                }
                int outputRow = 0;
                for (int r = 0; r < rows; r++)
                {
                    if (gidsVariable.Data[r] == g[j])
                    {
                        for (int c = 0; c < cols; c++)
                            ((DoubleVariable)outputFrame.Variables[lc + c]).Data[outputRow] = r >= data.Variables[c].Length
                                ? Constant.MISSING
                                : ((DoubleVariable)data.Variables[c]).Data[r];
                        outputRow++;
                    }
                }
                for (int c = 0; c < cols; c++)
                    outputFrame.Variables[lc + c].TruncateDataToLength(outputRow);
                lc += cols;
            }

            ParameterBag outputParameters = new();
            outputParameters.AddOutput("ng", ng);
            outputParameters.AddOutput("output", outputFrame);
            return new StepOutput(outputParameters);
        }

        public static StepOutput ShtNormal(ParameterBag parameters)
        {
            string lab = parameters["method"].AsString;
            int method;
            if ("vdW".Equals(lab))
                method = 1;
            else if ("Blom".Equals(lab))
                method = 2;
            else
                method = 3;
            DataFrame data = parameters["data"].AsDataFrame;
            DoubleVariable dataVariable = (DoubleVariable)data.Variables[0];
            int rows = dataVariable.Length;
            double[] prk = new double[rows + 1];
            int nx = 0;
            for (int n = 0; n < rows; n++)
            {
                if (dataVariable.Data[n] != Constant.MISSING)
                {
                    nx++;
                    prk[nx] = dataVariable.Data[n];
                }
            }
            double[] r = new double[nx + 1];
            ExFortran.Rank(prk, r, 1, nx, 0, out double _);
            if (method == 3)
            {
                if (nx > 2500)
                {
                    method = 1;
                    lab = "vdW";
                }
            }
            string pre = "Nml Score (" + lab + "): ";
            DataFrame outputFrame = new();
            DoubleVariable outputVariable = new(rows, pre + dataVariable.Title);
            outputFrame.Variables.Add(outputVariable);
            // The sample size is the number of valid observations, nx, which is what the ranks run over. It was the length of the
            // column, so missing cells inside it made every score too small in size and the scores no longer centred on zero.
            double den;
            if (method == 1)
                den = Convert.ToDouble(nx + 1L);
            else
                den = Convert.ToDouble(nx) + 1.0 / 4.0;
            int cx = 0;
            for (int c = 0; c < rows; c++)
            {
                if (dataVariable.Data[c] != Constant.MISSING)
                {
                    cx++;
                    double tr;
                    int ifault;
                    switch (method)
                    {
                        case 1:
                            // van der Waerden, Conover P396
                            tr = PDF.gauinv(r[cx] / den, out ifault);
                            if (ifault != 0)
                                tr = Constant.MISSING;
                            break;
                        case 2:
                            // Blom
                            tr = PDF.gauinv((r[cx] - 3.0 / 8.0) / den, out ifault);
                            if (ifault != 0)
                                tr = Constant.MISSING;
                            break;
                        default:
                            // expected normal order
                            // a tied value has a mid-rank ending in .5: it takes the mean of the two neighbouring expected order
                            // statistics. Rounding the mid-rank (to the even neighbour) made the scores of symmetrical data
                            // asymmetrical. For a whole-number rank this is the same value as before.
                            double eoBelow = Expnos.expnos((int)Math.Floor(r[cx]), nx);
                            double eoAbove = Expnos.expnos((int)Math.Ceiling(r[cx]), nx);
                            tr = eoBelow == Constant.MISSING || eoAbove == Constant.MISSING ? Constant.MISSING : 0.5 * (eoBelow + eoAbove);
                            break;
                    }

                    outputVariable.Data[c] = tr == Constant.MISSING ? Constant.MISSING : tr;
                }
                else
                {
                    outputVariable.Data[c] = Constant.MISSING;
                }
            }

            ParameterBag outputParameters = new();
            outputParameters.AddOutput("output", outputFrame);
            return new StepOutput(outputParameters);
        }

        public static StepOutput ShtPairDifferences(IPreferences host, ParameterBag parameters)
        {
            return ShtPair(host, parameters, 1);
        }

        public static StepOutput ShtPairMeans(IPreferences host, ParameterBag parameters)
        {
            return ShtPair(host, parameters, 2);
        }

        public static StepOutput ShtPairSlopes(IPreferences host, ParameterBag parameters)
        {
            return ShtPair(host, parameters, 3);
        }

        ///  <param name="parameters"></param>
        /// <param name="index">1 = differences, 2 = means, 3 = slopes</param>
        /// <param name="host"></param>
        private static StepOutput ShtPair(IPreferences host, ParameterBag parameters, int index)
        {
            int ctr; int rows2 = 0; int limit = 0;
            string qx = null; string xt = null;
            double[] xx = null; double[] x; double[] y = null;
            double mdn = 0;

            DataFrame yFrame = parameters["y"].AsDataFrame;
            DoubleVariable yVariable = (DoubleVariable)yFrame.Variables[0];
            int rows = yVariable.Length;
            string yt = yVariable.Title;
            double[] yy = new double[rows + 1];
            for (int i = 1; i <= rows; i++)
                yy[i] = yVariable.Data[i - 1];
            if (index != 2)
            {
                DataFrame xFrame = parameters["x"].AsDataFrame;
                DoubleVariable xVariable = (DoubleVariable)xFrame.Variables[0];
                rows2 = xVariable.Length;
                if (rows2 != rows & index == 3)
                {
                    //  Should never happen due to the data acquisition, but just in case...
                    throw new TemplateOperationCancelledException("Unequal number of observations in X and Y.", "Pairwise");
                }
                xt = xVariable.Title;
                xx = new double[rows2 + 1];
                for (int i = 1; i <= rows2; i++)
                    xx[i] = xVariable.Data[i - 1];
            }

            if (index == 2)
            {
                // means
                x = new double[rows + 1];
                ctr = 0;
                for (int i = 1; i <= rows; i++)
                {
                    if (yy[i] != Constant.MISSING)
                    {
                        ctr += 1;
                        x[ctr] = yy[i];
                    }
                }
                rows = ctr;
            }
            else if (index == 3)
            {
                // slopes
                x = new double[rows + 1];
                y = new double[rows + 1];
                ctr = 0;
                for (int i = 1; i <= rows; i++)
                {
                    Debug.Assert(xx != null, "xx != null");
                    if (xx[i] != Constant.MISSING & yy[i] != Constant.MISSING)
                    {
                        ctr += 1;
                        x[ctr] = xx[i];
                        y[ctr] = yy[i];
                    }
                }
                rows = ctr;
            }
            else
            {
                // differences
                x = new double[rows + 1];
                y = new double[rows2 + 1];
                ctr = 0;
                for (int i = 1; i <= rows2; i++)
                {
                    Debug.Assert(xx != null, "xx != null");
                    if (xx[i] != Constant.MISSING)
                    {
                        ctr++;
                        x[ctr] = xx[i];
                    }
                }
                rows2 = ctr;
                ctr = 0;
                for (int i = 1; i <= rows; i++)
                {
                    if (yy[i] != Constant.MISSING)
                    {
                        ctr++;
                        y[ctr] = yy[i];
                    }
                }
                rows = ctr;
            }

            // lc = 1; 
            switch (index)
            {
                case 1:
                    limit = rows * rows;
                    qx = "Differences (" + xt + " - " + yt + ")";
                    break;
                case 2:
                    limit = Convert.ToInt32(rows * (rows + 1) / 2);
                    qx = "Means within " + yt;
                    break;
                case 3:
                    limit = Convert.ToInt32((rows - 2) * (rows - 1) / 2);
                    qx = "Slopes(" + xt + ", " + yt + ")";
                    break;
            }

            if (limit > host.Preferences.MaxRows)
                throw new TemplateOperationCancelledException("Too many data.", "Pairwise");

            string t = qx;

            DataFrame outputFrame = new();
            DoubleVariable outputVariable = new(limit, t);
            outputFrame.Variables.Add(outputVariable);
            int cnt = 0;
            switch (index)
            {
                case 1:
                    for (int i = 1; i <= rows; i++)
                    {
                        for (int j = 1; j <= rows2; j++)
                        {
                            Debug.Assert(y != null, "y != null");
                            if (x[i] == Constant.MISSING || y[j] == Constant.MISSING)
                                outputVariable.SetData(cnt, Constant.MISSING);
                            else
                                outputVariable.SetData(cnt, x[i] - y[j]);
                            cnt++;
                        }
                    }
                    break;
                case 2:
                    for (int i = 1; i <= rows; i++)
                    {
                        for (int j = i; j <= rows; j++)
                        {
                            if (x[i] == Constant.MISSING)
                                outputVariable.SetData(cnt, Constant.MISSING);
                            else
                                outputVariable.SetData(cnt, (x[i] + x[j]) / 2.0);
                            cnt++;
                        }
                    }
                    break;
                case 3:
                    Debug.Assert(y != null, "y != null");
                    for (int i = 1; i < rows; i++)
                    {
                        for (int j = i + 1; j <= rows; j++)
                        {
                            if (x[i] != x[j])
                            {
                                if (x[i] == Constant.MISSING || y[j] == Constant.MISSING || x[i] - x[j] == 0.0)
                                    outputVariable.SetData(cnt, Constant.MISSING);
                                else
                                    outputVariable.SetData(cnt, (y[i] - y[j]) / (x[i] - x[j]));
                                cnt++;
                            }
                        }
                    }
                    if (parameters["calculate-slope"].AsBoolean)
                    {
                        double gamma = parameters["gamma"].AsDouble;
                        double p = (1.0 - gamma) / 2.0;
                        if (p < 0 || p > 1)
                            p = 0.025;
                        int nx = rows;
                        MathDbl.taufromp(p, out double _, out int ix, ref nx, out int fault);
                        double[] pws = new double[cnt + 1];
                        if (fault == 0)
                        {
                            cnt = 0;
                            for (int i = 1; i < rows; i++)
                            {
                                for (int j = i + 1; j <= rows; j++)
                                {
                                    if (x[i] != x[j])
                                    {
                                        cnt += 1;
                                        // adding zero turns a slope of minus zero into zero
                                        if (x[i] != Constant.MISSING && y[j] != Constant.MISSING)
                                            pws[cnt] = (y[i] - y[j]) / (x[i] - x[j]) + 0.0;
                                    }
                                }
                            }
                            Array.Sort(pws, 1, cnt);
                            // The limits are the rth smallest and the rth largest slope (Conover 1999), as in the nonparametric
                            // linear regression report; the rth largest is the (N + 1 - r)th smallest. The ((N + w) / 2)th was used
                            // for the upper limit, one ordered slope too low.
                            int ri = (int)Math.Floor(0.5 * Convert.ToDouble(cnt - ix));
                            int si = cnt + 1 - ri;
                            double imdn = 0.5 * Convert.ToDouble(cnt + 1);
                            if (imdn < 1.0)
                                imdn = 1.0;
                            if (imdn > cnt)
                                imdn = cnt;
                            if (imdn - Math.Floor(imdn) == 0.0)
                                mdn = pws[Convert.ToInt32(imdn)];
                            if (imdn - Math.Floor(imdn) != 0.0)
                                mdn = pws[(int)Math.Floor(imdn)] + (pws[Convert.ToInt32(Math.Floor(imdn) + 1.0)] - pws[(int)Math.Floor(imdn)]) * (imdn - Math.Floor(imdn));
                            // r below 1: too few slopes for an interval at this level of confidence; the limits used to be read from
                            // outside the ordered slopes
                            string limits = ri < 1
                                ? "too few pairs for an interval at this level of confidence"
                                : host.RoundU(pws[ri]) + " to " + host.RoundU(pws[si]);
                            t = t + " [Median slope (" + Formatting.XRound(gamma * 100, 2) + "% CI)= " + host.RoundU(mdn) + " (" + limits + ")]";
                            outputVariable.Title = t;
                        }
                        else
                        {
                            throw new TemplateOperationCancelledException("TODO: Error description", "Pairwise");
                        }
                    }
                    break;
            }

            ParameterBag outputParameters = new();
            outputParameters.AddOutput("output", outputFrame);
            return new StepOutput(outputParameters);
        }

        public static StepOutput ShtRndBeta(ParameterBag parameters)
        {
            int cols = parameters["cols"].AsInt32;
            int rows = parameters["rows"].AsInt32;
            double a = parameters["a"].AsDouble;
            double b = parameters["b"].AsDouble;
            int seed = parameters["seed"].AsInt32;
            return WrapFrame("output", Random.RndBeta(rows, cols, a, b, seed));
        }

        public static StepOutput ShtRndBinomial(ParameterBag parameters)
        {
            int cols = parameters["cols"].AsInt32;
            int rows = parameters["rows"].AsInt32;
            int nn = parameters["nn"].AsInt32;
            double p = parameters["p"].AsDouble;
            int seed = parameters["seed"].AsInt32;
            return WrapFrame("output", Random.RndBino(rows, cols, nn, p, seed));
        }

        public static StepOutput ShtRndCauchy(ParameterBag parameters)
        {
            int cols = parameters["cols"].AsInt32;
            int rows = parameters["rows"].AsInt32;
            double l = parameters["l"].AsDouble;
            double s = parameters["s"].AsDouble;
            int seed = parameters["seed"].AsInt32;
            return WrapFrame("output", Random.RndCauchy(rows, cols, l, s, seed));
        }

        public static StepOutput ShtRndChiSquare(ParameterBag parameters)
        {
            int cols = parameters["cols"].AsInt32;
            int rows = parameters["rows"].AsInt32;
            double df = parameters["df"].AsDouble;
            int seed = parameters["seed"].AsInt32;
            return WrapFrame("output", Random.RndChi(rows, cols, df, seed));
        }

        public static StepOutput ShtRndExponential(ParameterBag parameters)
        {
            int cols = parameters["cols"].AsInt32;
            int rows = parameters["rows"].AsInt32;
            double xm = parameters["xm"].AsDouble;
            int seed = parameters["seed"].AsInt32;
            return WrapFrame("output", Random.RndExpo(rows, cols, xm, seed));
        }

        public static StepOutput ShtRndF(ParameterBag parameters)
        {
            int cols = parameters["cols"].AsInt32;
            int rows = parameters["rows"].AsInt32;
            double dfn = parameters["dfn"].AsDouble;
            double dfd = parameters["dfd"].AsDouble;
            int seed = parameters["seed"].AsInt32;
            return WrapFrame("output", Random.RndF(rows, cols, dfn, dfd, seed));
        }

        public static StepOutput ShtRndGamma(ParameterBag parameters)
        {
            int cols = parameters["cols"].AsInt32;
            int rows = parameters["rows"].AsInt32;
            double a = parameters["a"].AsDouble;
            double b = parameters["b"].AsDouble;
            int seed = parameters["seed"].AsInt32;
            return WrapFrame("output", Random.RndGamma(rows, cols, a, b, seed));
        }

        public static StepOutput ShtRndGeometric(ParameterBag parameters)
        {
            int cols = parameters["cols"].AsInt32;
            int rows = parameters["rows"].AsInt32;
            double p = parameters["p"].AsDouble;
            int seed = parameters["seed"].AsInt32;
            return WrapFrame("output", Random.RndGeom(rows, cols, p, seed));
        }

        public static StepOutput ShtRndLogit(ParameterBag parameters)
        {
            int cols = parameters["cols"].AsInt32;
            int rows = parameters["rows"].AsInt32;
            double mu = parameters["mu"].AsDouble;
            double sigma = parameters["sigma"].AsDouble;
            int seed = parameters["seed"].AsInt32;
            return WrapFrame("output", Random.RndLogit(rows, cols, mu, sigma, seed));
        }

        public static StepOutput ShtRndLogNormal(ParameterBag parameters)
        {
            int cols = parameters["cols"].AsInt32;
            int rows = parameters["rows"].AsInt32;
            double xm = parameters["xm"].AsDouble;
            double sd = parameters["sd"].AsDouble;
            int seed = parameters["seed"].AsInt32;
            return WrapFrame("output", Random.RndLogNorm(rows, cols, xm, sd, seed));
        }

        public static StepOutput ShtRndNegativeBinomial(ParameterBag parameters)
        {
            int cols = parameters["cols"].AsInt32;
            int rows = parameters["rows"].AsInt32;
            double n = parameters["n"].AsDouble;
            double p = parameters["p"].AsDouble;
            int seed = parameters["seed"].AsInt32;
            return WrapFrame("output", Random.RndNegBin(rows, cols, n, p, seed));
        }

        public static StepOutput ShtRndNormal(ParameterBag parameters)
        {
            int cols = parameters["cols"].AsInt32;
            int rows = parameters["rows"].AsInt32;
            double xm = parameters["xm"].AsDouble;
            double sd = parameters["sd"].AsDouble;
            int seed = parameters["seed"].AsInt32;
            return WrapFrame("output", Random.RndNorm(rows, cols, xm, sd, seed));
        }

        public static StepOutput ShtRndPoisson(ParameterBag parameters)
        {
            int cols = parameters["cols"].AsInt32;
            int rows = parameters["rows"].AsInt32;
            double xm = parameters["xm"].AsDouble;
            int seed = parameters["seed"].AsInt32;
            return WrapFrame("output", Random.RndPoisson(rows, cols, xm, seed));
        }

        public static StepOutput ShtRndT(ParameterBag parameters)
        {
            int cols = parameters["cols"].AsInt32;
            int rows = parameters["rows"].AsInt32;
            double df = parameters["df"].AsDouble;
            int seed = parameters["seed"].AsInt32;
            return WrapFrame("output", Random.RndT(rows, cols, df, seed));
        }

        public static StepOutput ShtRndUniform01(ParameterBag parameters)
        {
            int cols = parameters["cols"].AsInt32;
            int rows = parameters["rows"].AsInt32;
            int seed = parameters["seed"].AsInt32;
            return WrapFrame("output", Random.RndUni(rows, cols, Constant.MISSING, Constant.MISSING, false, seed));
        }

        public static StepOutput ShtRndUniformAB(ParameterBag parameters)
        {
            int cols = parameters["cols"].AsInt32;
            int rows = parameters["rows"].AsInt32;
            double a = parameters["a"].AsDouble;
            double b = parameters["b"].AsDouble;
            bool isCount = "count".Equals(parameters["numberType"].AsString);
            int seed = parameters["seed"].AsInt32;
            return WrapFrame("output", Random.RndUni(rows, cols, a, b, isCount, seed));
        }

        public static StepOutput ShtRndWeibull(ParameterBag parameters)
        {
            int cols = parameters["cols"].AsInt32;
            int rows = parameters["rows"].AsInt32;
            double a = parameters["a"].AsDouble;
            double b = parameters["b"].AsDouble;
            int seed = parameters["seed"].AsInt32;
            return WrapFrame("output", Random.RndWeibull(rows, cols, a, b, seed));
        }

        private static StepOutput WrapFrame(string name, DataFrame frame)
        {
            ParameterBag outputParameters = new();
            outputParameters.AddOutput(name, frame);
            return new StepOutput(outputParameters);
        }

        public static StepOutput ShtRank(ParameterBag parameters)
        {
            DataFrame data = parameters["data"].AsDataFrame;
            DoubleVariable inputVariable = (DoubleVariable)data.Variables[0];
            int q = Parsing.Cint_Txt(parameters["tie-correction"].AsString);
            int rows = inputVariable.Length;
            double[] prk = new double[rows + 1];
            int nx = 0;
            foreach (double value in inputVariable.Data)
            {
                if (value != Constant.MISSING)
                    prk[++nx] = value;
            }
            double[] r = new double[nx + 1];
            ExFortran.Rank(prk, r, 1, nx, q, out double tie);
            string title = "Rank: " + inputVariable.Title + (q < 2 ? string.Empty : " [tie correction = " + tie.ToString(CultureInfo.CurrentCulture) + "]");
            DataFrame outputFrame = new();
            DoubleVariable outputVariable = new(rows, title);
            outputFrame.Variables.Add(outputVariable);
            int cx = 0;
            for (int c = 0; c < rows; c++)
            {
                if (inputVariable.Data[c] != Constant.MISSING)
                {
                    cx++;
                    outputVariable.SetData(c, r[cx] == Constant.MISSING ? Constant.MISSING : r[cx]);
                }
                else
                    outputVariable.SetData(c, Constant.MISSING);
            }
            return WrapFrame("output", outputFrame);
        }

        ///  <summary>
        ///  Assumes the input is a frame of string variables.  Returns a frame mirrored around x=y.
        ///  </summary>
        ///  <param name="host"></param>
        ///  <param name="parameters"></param>
        ///  <returns></returns>
        public static StepOutput ShtRotate(ParameterBag parameters)
        {
            DataFrame data = parameters["data"].AsDataFrame;
            int cols = data.VariableCount;
            int rows = data.MaxRows;
            DataFrame outputFrame = new();
            for (int row = 0; row < rows; row++)
            {
                StringVariable v = new(cols, null); //  Prevent title being emitted on output
                outputFrame.Variables.Add(v);
                for (int col = 0; col < cols; col++)
                {
                    StringVariable inv = (StringVariable)data.Variables[col];
                    if (inv.Length > row)
                        v.SetData(col, inv.Data[row]);
                }
            }
            return WrapFrame("output", outputFrame);
        }

        private class DoubleAscending : IComparer<double>
        {
            private static int Compare(double x, double y)
            {
                if (x > y)
                    return 1;
                if (x == y)
                    return 0;
                return -1;
            }

            // interface methods implemented by Compare
            int IComparer<double>.Compare(double x, double y)
            {
                return Compare(x, y);
            }

        }

        private class DoubleDescending : IComparer<double>
        {
            private static int Compare(double x, double y)
            {
                if (x < y)
                    return 1;
                return x == y ? 0 : -1;
            }

            // interface methods implemented by Compare
            int IComparer<double>.Compare(double x, double y)
            {
                return Compare(x, y);
            }
        }

        public static StepOutput ShtSort(ParameterBag parameters)
        {
            DataFrame data = parameters["data"].AsDataFrame;
            DoubleVariable dataVariable = (DoubleVariable)data.Variables[0];
            string sort = parameters["sort"].AsString;
            IComparer<double> comp;
            if ("asc".Equals(sort))
            {
                comp = new DoubleAscending();
            }
            else { comp = new DoubleDescending(); }
            bool hasLink = parameters.ContainsKey("linkdata") && parameters["linkdata"] != null;

            int rows = dataVariable.Length;

            string t = "Sort: " + dataVariable.Title;

            double[] dataArray = new double[rows];
            int nx;
            if (hasLink)
            {
                DataFrame linkData = parameters["linkdata"].AsDataFrame;
                DoubleVariable linkVariable = (DoubleVariable)linkData.Variables[0];
                t += " (by " + linkVariable.Title + ")";
                double[] linkArray = new double[rows];
                nx = 0;
                for (int i = 0; i < rows; i++)
                {
                    if (dataVariable.Data[i] != Constant.MISSING && linkVariable.Data[i] != Constant.MISSING)
                    {
                        dataArray[nx] = dataVariable.Data[i];
                        linkArray[nx] = linkVariable.Data[i];
                        nx += 1;
                    }
                }
                Array.Sort(linkArray, dataArray, 0, nx, comp);
            }
            else
            {
                nx = 0;
                foreach (double v in dataVariable.Data)
                {
                    if (v != Constant.MISSING)
                    {
                        dataArray[nx] = v;
                        nx += 1;
                    }
                }
                Array.Sort(dataArray, 0, nx, comp);
            }

            DataFrame outputFrame = new();
            DoubleVariable outputVariable = new(dataArray, t);
            outputVariable.TruncateDataToLength(nx);
            outputFrame.Variables.Add(outputVariable);
            return WrapFrame("output", outputFrame);
        }

        public static StepOutput ShtSortByExpression(ParameterBag parameters)
        {
            DataFrame data = parameters["data"].AsDataFrame;
            string expression = parameters["expression"].AsString;

            int rows = data.MaxRows;
            int cols = data.VariableCount;

            // Work through the rows
            DataType[] dataTypes = new DataType[cols];
            for (int col = 0; col < cols; col++)
                dataTypes[col] = DataType.Double;
            Calcit clc = new(expression, dataTypes, false);

            double[] x = new double[cols];
            SortPair[] sortArray = new SortPair[rows];
            for (int row = 0; row < rows; row++)
            {
                for (int col = 0; col < cols; col++)
                    x[col] = ((DoubleVariable)data.Variables[col]).Data[row];
                sortArray[row] = new SortPair(XSpr(clc.Evaluate<double>(x)), row);
            }
            Array.Sort(sortArray);

            DataFrame outputFrame = new();
            foreach (IVariable v in data.Variables)
                outputFrame.Variables.Add(new DoubleVariable(rows, "Sort(" + expression + "): " + v.Title));
            for (int col = 0; col < cols; col++)
            {
                double[] src = ((DoubleVariable)data.Variables[col]).Data;
                double[] target = ((DoubleVariable)outputFrame.Variables[col]).Data;
                for (int row = 0; row < rows; row++)
                    target[row] = src[sortArray[row].Row];
            }
            return WrapFrame("output", outputFrame);
        }

        public static StepOutput ShtSortInPlace(ITemplateHost host, ParameterBag parameters)
        {
            //  A gross hack - this just hands off to the UI.
            host.Amend(new SortInPlaceOptions(), parameters);
            return StepOutput.Empty();
        }


        public static StepOutput ShtTransformLog(ParameterBag parameters)
        {
            return ShtTransforms(parameters, 0);
        }


        public static StepOutput ShtTransformLog10(ParameterBag parameters)
        {
            return ShtTransforms(parameters, 1);
        }


        public static StepOutput ShtTransformLogit(ParameterBag parameters)
        {
            return ShtTransforms(parameters, 2);
        }


        public static StepOutput ShtTransformProbit(ParameterBag parameters)
        {
            return ShtTransforms(parameters, 3);
        }


        public static StepOutput ShtTransformAngular(ParameterBag parameters)
        {
            return ShtTransforms(parameters, 4);
        }


        public static StepOutput ShtTransformCumulate(ParameterBag parameters)
        {
            return ShtTransforms(parameters, 5);
        }


        public static StepOutput ShtTransformECDF(ParameterBag parameters)
        {
            return ShtTransforms(parameters, 6);
        }


        public static StepOutput ShtTransformZsd(ParameterBag parameters)
        {
            return ShtTransforms(parameters, 7);
        }


        public static StepOutput ShtTransformZecdf(ParameterBag parameters)
        {
            return ShtTransforms(parameters, 8);
        }


        private static StepOutput ShtTransforms(ParameterBag parameters, int index)
        {
            DataFrame data = parameters["data"].AsDataFrame;
            DoubleVariable inputVariable = (DoubleVariable)data.Variables[0];
            double[] inputData = inputVariable.Data;
            int rows = inputData.Length;

            double[] a = new double[rows];
            if (index == 0)
            {
                double cons = Constant.MISSING;
                if (parameters.ContainsKey("c"))
                {
                    cons = parameters["c"].AsDouble;
                }
                bool skipInvalid = cons == Constant.MISSING;
                if (skipInvalid)
                {
                    cons = 0;
                }
                for (int n = 0; n < rows; n++)
                {
                    if (inputData[n] == Constant.MISSING)
                    {
                        a[n] = Constant.MISSING;
                    }
                    else
                    {
                        double z = inputData[n] + cons;
                        if (z <= 0.0)
                            a[n] = Constant.MISSING;
                        else
                            a[n] = Math.Log(z);
                    }
                }
                string title = cons != 0.0 ? "Log(natural): " + cons.ToString() + " + " + inputVariable.Title : "Log(natural): " + inputVariable.Title;
                return WrapDoubleVariable(a, title);
            }
            if (index == 1)
            {
                double cons = Constant.MISSING;
                if (parameters.ContainsKey("c"))
                {
                    cons = parameters["c"].AsDouble;
                }
                bool skipInvalid = cons == Constant.MISSING;
                if (skipInvalid)
                {
                    cons = 0;
                }
                double log10 = Math.Log(10.0);
                for (int n = 0; n < rows; n++)
                {
                    if (inputData[n] == Constant.MISSING)
                    {
                        a[n] = Constant.MISSING;
                    }
                    else
                    {
                        double z = inputData[n] + cons;
                        if (z <= 0.0)
                            a[n] = Constant.MISSING;
                        else
                            a[n] = Math.Log(z) / log10;
                    }
                }
                string title = cons != 0.0 ? "Log(base 10): " + cons.ToString() + " + " + inputVariable.Title : "Log(base 10): " + inputVariable.Title;
                return WrapDoubleVariable(a, title);
            }
            if (index == 2)
            {
                double maxi = XAmanipdp(parameters["discrete"].AsString, inputData);
                for (int n = 0; n < rows; n++)
                {
                    if (inputData[n] == Constant.MISSING)
                    {
                        a[n] = Constant.MISSING;
                    }
                    else
                    {
                        double prop = Math.Abs(inputData[n] / maxi);
                        if (prop == 1 || prop == 0)
                        {
                            a[n] = Constant.MISSING;
                        }
                        else
                        {
                            if (prop / (1.0 - prop) < 0)
                                a[n] = Constant.MISSING;
                            else
                                a[n] = Math.Log(prop / (1.0 - prop));
                        }
                    }
                }
                return WrapDoubleVariable(a, "Logit: " + inputVariable.Title);
            }
            if (index == 3)
            {
                double maxi = XAmanipdp(parameters["discrete"].AsString, inputData);
                for (int n = 0; n < rows; n++)
                {
                    if (inputData[n] == Constant.MISSING)
                    {
                        a[n] = Constant.MISSING;
                    }
                    else
                    {
                        double prop = Math.Abs(inputData[n] / maxi);
                        if (prop == 1.0 || prop == 0.0)
                        {
                            a[n] = Constant.MISSING;
                        }
                        else
                        {
                            double zed = PDF.gauinv(prop, out int fault);
                            if (fault == 0)
                                a[n] = 5 + zed;
                            else
                                a[n] = Constant.MISSING;
                        }
                    }
                }
                return WrapDoubleVariable(a, "Probit: " + inputVariable.Title);
            }
            if (index == 4)
            {
                double maxi = XAmanipdp(parameters["discrete"].AsString, inputData);
                for (int n = 0; n < rows; n++)
                {
                    if (inputData[n] == Constant.MISSING)
                    {
                        a[n] = Constant.MISSING;
                    }
                    else
                    {
                        double prop = Math.Abs(inputData[n] / maxi);
                        if (prop == 0.0)
                        {
                            a[n] = 0;
                        }
                        else if (prop == 1.0)
                        {
                            a[n] = 90;
                        }
                        else if (prop < 0.0 || prop > 1.0)
                        {
                            a[n] = Constant.MISSING;
                        }
                        else
                        {
                            double x = Math.Sqrt(prop);
                            a[n] = 57.2957795130824 * Math.Atan(x / Math.Sqrt(1.0 - x * x));
                        }
                    }
                }
                return WrapDoubleVariable(a, "Angle: " + inputVariable.Title);
            }
            if (index == 5)
            {
                for (int n = 0; n < rows; n++)
                {
                    if (inputData[n] == Constant.MISSING)
                        a[n] = Constant.MISSING;
                    else if (n == 0)
                        a[n] = inputData[n];
                    else
                        a[n] = a[n - 1] + inputData[n];
                }
                return WrapDoubleVariable(a, "Cumulate: " + inputVariable.Title);
            }
            if (index == 6)
            {
                double[] fn = new double[inputData.Length];
                MathDbl.ecdf(inputData, fn, out int err);
                if (err == 0)
                    return WrapDoubleVariable(fn, "ECDF: " + inputVariable.Title);
                throw new ArgumentException("Insufficient data");
            }
            if (index == 7)
            {
                double[] fn = new double[inputData.Length];
                MathDbl.zscore(inputData, ref fn, false, out int err);
                if (err == 0)
                    return WrapDoubleVariable(fn, "Z: " + inputVariable.Title);
                throw new ArgumentException("Insufficient data");
            }
            if (index == 8)
            {
                double[] fn = new double[inputData.Length];
                MathDbl.zscore(inputData, ref fn, true, out int err);
                if (err == 0)
                    return WrapDoubleVariable(fn, "Z score (ECDF): " + inputVariable.Title);
                throw new ArgumentException("Insufficient data");
            }
            throw new ArgumentException("Unknown index");
        }

        private static double XAmanipdp(string discrete, double[] data)
        {
            if ("discrete".Equals(discrete))
            {
                bool allMissing = true;
                double maxi = double.MinValue;
                foreach (double v in data)
                {
                    if (v != Constant.MISSING)
                    {
                        allMissing = false;
                        if (Math.Abs(v) > maxi)
                            maxi = Math.Abs(v);
                    }
                }
                return allMissing ? Constant.MISSING : maxi;
            }
            return 1.0;
        }


        private static StepOutput WrapDoubleVariable(double[] a, string title)
        {
            DataFrame outputFrame = new();
            DoubleVariable outputVariable = new(a, title);
            outputFrame.Variables.Add(outputVariable);
            return WrapFrame("output", outputFrame);
        }


        public static StepOutput ShtGroupCategorise(ITemplateHost host, ParameterBag parameters)
        {
            DataFrame data = parameters["data"].AsDataFrame;
            DoubleVariable inputVariable = (DoubleVariable)data.Variables[0];
            int rows = inputVariable.Length;
            CategoriseOptions options = new()
            {
                Title = "Categorised: " + inputVariable.Title,
                PassX = new double[rows],
                Data = inputVariable
            };
            if (null == host.Amend(options, parameters))
                throw new TemplateOperationCancelledException();

            DataFrame outputFrame = new();
            if (options.PassX != null && options.PassX.Length > 0)
            {
                DoubleVariable boundariesVariable = new(options.PassX, options.Title);
                outputFrame.Variables.Add(boundariesVariable);
            }
            if (options.Categories != null)
            {
                StringVariable categoryVariable = new(options.Categories, "category");
                outputFrame.Variables.Add(categoryVariable);
                DoubleVariable countVariable = new(options.Counts.Length, "count");
                outputFrame.Variables.Add(countVariable);
                for (int r = 0; r < options.Counts.Length; r++)
                    countVariable.SetData(r, options.Counts[r]);
            }
            return WrapFrame("output", outputFrame);
        }


        public static StepOutput ShtGroupExtract(ITemplateHost host, ParameterBag parameters)
        {
            DataFrame data = parameters["data"].AsDataFrame;
            bool isFindAndReplace = data.VariableCount > 1;

            if (isFindAndReplace)
            {
                ExtractionOptions options = new() { DataFrame = data };
                ParameterBag outputParameters = host.Amend(options, parameters);
                return new StepOutput(outputParameters);
            }
            else
            {
                DoubleVariable dataVariable = (DoubleVariable)data.Variables[0];
                string dtitle = dataVariable.Title;

                DataFrame identifiersFrame = parameters["identifiers"].AsDataFrame;

                int cols = identifiersFrame.VariableCount;
                string l = string.Empty;
                for (int j = 1; j <= cols; j++)
                    l += "X" + j + ": " + identifiersFrame.Variables[j - 1].Title + "\r\n";

                ExtractionOptions options = new()
                {
                    Title = dtitle,
                    IdentifierNames = l,
                    DataFrame = data,
                    IdentifiersFrame = identifiersFrame
                };
                ParameterBag outputParameters = host.Amend(options, parameters);
                return new StepOutput(outputParameters);
            }
        }

        public static StepOutput ConvertUnits(ITemplateHost host, ParameterBag parameters)
        {
            ConvertUnitsOptions convertUnitsOptions = new();
            ParameterBag outputParameters = host.Amend(convertUnitsOptions, parameters);
            return new StepOutput(outputParameters);
        }

        internal static StepOutput ShtToggleFilters(ITemplateHost host, ParameterBag parameters)
        {
            //  A gross hack - this just hands off to the UI.
            host.Amend(new ToggleFiltersOptions(), parameters);
            return StepOutput.Empty();
        }

        internal static StepOutput ShtContract(ParameterBag parameters)
        {
            DataFrame covariatesOrNull;
            bool hasResponses;

            string type = parameters["type"].AsString;
            switch (type)
            {
                case "categories":
                    {
                        covariatesOrNull = null;
                        hasResponses = false;
                    }
                    break;
                case "categories-covariates":
                    {
                        covariatesOrNull = parameters["covariates"].AsDataFrame;
                        hasResponses = false;
                    }
                    break;
                case "response-covariates":
                    {
                        covariatesOrNull = parameters["covariates"].AsDataFrame;
                        hasResponses = true;
                    }
                    break;
                default:
                    throw new Exception("Unknown type '" + type + "' when trying to contract data");
            }

            // We do fundamentally different things depending on whether we have responses or categories - the output contains different numbers of rows.
            // Deal with this as two separate workflows.
            if (hasResponses)
            {
                // 0 or 1 responses - one row per covariate pattern
                DataFrame responsesFrame = parameters["responses"].AsDataFrame;
                DoubleVariable responsesVariable = (DoubleVariable)responsesFrame.Variables[0];
                double[] responseData = responsesVariable.Data;

                int[] differenceArray;
                int nextDifferentValue;
                if (null == covariatesOrNull)
                {
                    nextDifferentValue = 1;
                    differenceArray = new int[nextDifferentValue];
                }
                else
                {
                    nextDifferentValue = ClassifyObjects(covariatesOrNull, out differenceArray);
                }

                // Gather counts and sequencing for later use
                int[] differenceValuesInOrder = new int[nextDifferentValue];
                int nextInOrderOffset = 0;
                Dictionary<int, RespondersCountAndRowIndex> countMap = new();
                for (int sourceIndex = 0; sourceIndex < differenceArray.Length; sourceIndex++)
                {
                    int value = differenceArray[sourceIndex];
                    if (countMap.TryGetValue(value, out RespondersCountAndRowIndex rcari))
                    {
                        rcari.Count++;
                    }
                    else
                    {
                        rcari = new RespondersCountAndRowIndex { Count = 1, RowIndex = sourceIndex };
                        countMap.Add(value, rcari);
                        differenceValuesInOrder[nextInOrderOffset++] = value;
                    }
                    if (responseData[sourceIndex] != 0.0)
                        rcari.Responders++;
                }

                // Generate output
                double[] outputTotals = new double[nextDifferentValue];
                double[] outputResponders = new double[nextDifferentValue];
                double[] outputNonResponders = new double[nextDifferentValue];
                double[] outputProportionsResponding = new double[nextDifferentValue];
                for (int i = 0; i < nextDifferentValue; i++)
                {
                    RespondersCountAndRowIndex rcari = countMap[differenceValuesInOrder[i]];
                    outputTotals[i] = rcari.Count;
                    outputResponders[i] = rcari.Responders;
                    outputNonResponders[i] = rcari.NonResponders;
                    outputProportionsResponding[i] = rcari.ProportionResponding;
                }
                DataFrame outputFrame = new();
                string group = parameters["group"].AsString;
                if (group.Contains("totals"))
                    outputFrame.Variables.Add(new DoubleVariable(outputTotals, "Total"));
                if (group.Contains("responders"))
                    outputFrame.Variables.Add(new DoubleVariable(outputResponders, "Responders"));
                if (group.Contains("nonresps"))
                    outputFrame.Variables.Add(new DoubleVariable(outputNonResponders, "Non-responders"));
                if (group.Contains("resprops"))
                    outputFrame.Variables.Add(new DoubleVariable(outputProportionsResponding, "Proportion responding"));

                if (null != covariatesOrNull)
                {
                    // Add covariates.
                    foreach (IVariable inputCovariant in covariatesOrNull.Variables)
                    {
                        GenericVariable<object> outputCovariant = new VariantVariable(nextDifferentValue, inputCovariant.Title);
                        for (int i = 0; i < nextDifferentValue; i++)
                            outputCovariant.Data[i] = inputCovariant.DataAsObject(countMap[differenceValuesInOrder[i]].RowIndex);
                        outputFrame.Variables.Add(outputCovariant);
                    }
                }
                ParameterBag outputParameters = new();
                outputParameters.AddOutput("output", outputFrame);
                return new StepOutput(outputParameters);

            }
            else
            {
                // Categories - one row per combination of category and covariate pattern
                DataFrame categoriesFrame = parameters["categories"].AsDataFrame;
                ClassifierVariable categoriesVariable = (ClassifierVariable)categoriesFrame.Variables[0];
                int nextDifferentValue = ClassifyObjects(categoriesFrame, out int[] differenceArray);
                if (null != covariatesOrNull)
                    nextDifferentValue = ClassifyObjects(differenceArray, covariatesOrNull, nextDifferentValue);

                // Gather counts and sequencing for later use
                int[] differenceValuesInOrder = new int[nextDifferentValue];
                int nextInOrderOffset = 0;
                Dictionary<int, CountAndRowIndex> countMap = new();
                for (int sourceIndex = 0; sourceIndex < differenceArray.Length; sourceIndex++)
                {
                    int value = differenceArray[sourceIndex];
                    if (countMap.TryGetValue(value, out CountAndRowIndex cari))
                        cari.Count++;
                    else
                    {
                        cari = new CountAndRowIndex { Count = 1, RowIndex = sourceIndex };
                        countMap.Add(value, cari);
                        differenceValuesInOrder[nextInOrderOffset++] = value;
                    }
                }

                // Generate output
                string[] outputValues = new string[nextDifferentValue];
                double[] outputFrequencies = new double[nextDifferentValue];
                for (int i = 0; i < nextDifferentValue; i++)
                {
                    int rowIndex = countMap[differenceValuesInOrder[i]].RowIndex;
                    int groupIndex = (int)categoriesVariable.Data[rowIndex];
                    outputValues[i] = categoriesVariable.Groups[groupIndex].Label;
                    outputFrequencies[i] = countMap[differenceValuesInOrder[i]].Count;
                }
                string valuesTitle = categoriesVariable.Title;
                if (valuesTitle.EndsWith("_Individual"))
                    valuesTitle = valuesTitle.Replace("_Individual", string.Empty);
                else
                    valuesTitle += "_Grouped";
                string frequenciesTitle = categoriesVariable.Title;
                if (frequenciesTitle.EndsWith("_Individual"))
                    frequenciesTitle = frequenciesTitle.Replace("_Individual", string.Empty);
                StringVariable valuesVariable = new(outputValues, valuesTitle);
                DoubleVariable frequenciesVariable = new(outputFrequencies, frequenciesTitle);
                DataFrame outputFrame = new();
                outputFrame.Variables.Add(valuesVariable);
                outputFrame.Variables.Add(frequenciesVariable);

                if (null != covariatesOrNull)
                {
                    // Add covariates.
                    foreach (IVariable inputCovariant in covariatesOrNull.Variables)
                    {
                        VariantVariable outputCovariant = new(nextDifferentValue, inputCovariant.Title);
                        for (int i = 0; i < nextDifferentValue; i++)
                            outputCovariant.Data[i] = inputCovariant.DataAsObject(countMap[differenceValuesInOrder[i]].RowIndex);
                        outputFrame.Variables.Add(outputCovariant);
                    }
                }
                ParameterBag outputParameters = new();
                outputParameters.AddOutput("output", outputFrame);
                return new StepOutput(outputParameters);

            }
        }

        internal static StepOutput ShtExpand(ParameterBag parameters)
        {
            int MAXROWS = 1000000; // Maximum number of output rows we're willing to tolerate.  TODO: Should really acquire this from the host.
            string mode = parameters["mode"].AsString;
            DataFrame covariatesOrNull;
            StringVariable labelsOrNull;
            int totalOutputRows;
            int[] yesPerGroup;
            int[] noPerGroup;
            bool hasResponses;
            switch (mode)
            {
                case "categories-counts":
                    {
                        DoubleVariable countsVariable = (DoubleVariable)parameters["counts"].AsDataFrame.Variables[0];
                        yesPerGroup = ToIntArray(countsVariable.Data, out totalOutputRows);
                        noPerGroup = new int[yesPerGroup.Length]; // Initialised to 0
                        labelsOrNull = parameters["categories"].AsDataFrame.Variables[0] as StringVariable;
                        covariatesOrNull = null;
                        hasResponses = false;
                    }
                    break;
                case "categories-counts-covariates":
                    {
                        DoubleVariable countsVariable = (DoubleVariable)parameters["counts"].AsDataFrame.Variables[0];
                        yesPerGroup = ToIntArray(countsVariable.Data, out totalOutputRows);
                        noPerGroup = new int[yesPerGroup.Length]; // Initialised to 0
                        labelsOrNull = parameters["categories"].AsDataFrame.Variables[0] as StringVariable;
                        covariatesOrNull = parameters["covariates"].AsDataFrame;
                        hasResponses = false;
                    }
                    break;
                case "responders-nonresps-covariates":
                    {
                        DoubleVariable respondersVariable = (DoubleVariable)parameters["responders"].AsDataFrame.Variables[0];
                        yesPerGroup = ToIntArray(respondersVariable.Data, out int yesses);
                        DoubleVariable nonrespsVariable = (DoubleVariable)parameters["nonresps"].AsDataFrame.Variables[0];
                        noPerGroup = ToIntArray(nonrespsVariable.Data, out int noes);
                        totalOutputRows = yesses + noes;
                        labelsOrNull = null;
                        covariatesOrNull = parameters["covariates"].AsDataFrame;
                        hasResponses = true;
                    }
                    break;
                case "responders-totals-covariates":
                    {
                        DoubleVariable respondersVariable = (DoubleVariable)parameters["responders"].AsDataFrame.Variables[0];
                        yesPerGroup = ToIntArray(respondersVariable.Data, out int _);
                        DoubleVariable totalsVariable = (DoubleVariable)parameters["totals"].AsDataFrame.Variables[0];
                        int[] totalsPerGroup = ToIntArray(totalsVariable.Data, out totalOutputRows);
                        noPerGroup = new int[yesPerGroup.Length];
                        for (int i = 0; i < yesPerGroup.Length; i++)
                            noPerGroup[i] = totalsPerGroup[i] - yesPerGroup[i];
                        labelsOrNull = null;
                        covariatesOrNull = parameters["covariates"].AsDataFrame;
                        hasResponses = true;
                    }
                    break;
                case "resprops-totals-covariates":
                    {
                        DoubleVariable respropsVariable = (DoubleVariable)parameters["resprops"].AsDataFrame.Variables[0];
                        DoubleVariable totalsVariable = (DoubleVariable)parameters["totals"].AsDataFrame.Variables[0];
                        int[] totalsPerGroup = ToIntArray(totalsVariable.Data, out totalOutputRows);
                        yesPerGroup = new int[totalsVariable.Length];
                        noPerGroup = new int[yesPerGroup.Length];
                        for (int i = 0; i < yesPerGroup.Length; i++)
                        {
                            yesPerGroup[i] = (int)Math.Round(totalsPerGroup[i] * respropsVariable.Data[i], MidpointRounding.AwayFromZero);
                            noPerGroup[i] = totalsPerGroup[i] - yesPerGroup[i];
                        }
                        labelsOrNull = null;
                        covariatesOrNull = parameters["covariates"].AsDataFrame;
                        hasResponses = true;
                    }
                    break;
                default:
                    throw new Exception("Unknown mode '" + mode + "' when trying to expand data");
            }
            if (totalOutputRows > MAXROWS)
                throw new TemplateOperationCancelledException("The output would require " + totalOutputRows + " rows, which will not fit into the spreadsheet", "Expand");

            bool hasLabels = null != labelsOrNull;
            int covariatesCount = covariatesOrNull?.VariableCount ?? 0;

            DataFrame outputFrame = new();
            // Add label variable if we have it
            StringVariable outputLabels;
            if (hasLabels)
            {
                string title = labelsOrNull.Title;
                if (title.EndsWith("_Grouped"))
                    title = title.Replace("_Grouped", string.Empty);
                else
                    title += "_Individual";
                outputLabels = new StringVariable(totalOutputRows, title);
                outputFrame.Variables.Add(outputLabels);
            }
            else
                outputLabels = null;

            // Add responses variable if we have it
            DoubleVariable outputResponses;
            if (hasResponses)
            {
                outputResponses = new DoubleVariable(totalOutputRows, "Response");
                outputFrame.Variables.Add(outputResponses);
            }
            else
                outputResponses = null;

            // Add covariates if we have them
            GenericVariable<object>[] outputCovariates = new GenericVariable<object>[covariatesCount];
            for (int i = 0; i < covariatesCount; i++)
            {
                GenericVariable<object> v = new VariantVariable(totalOutputRows, covariatesOrNull.Variables[i].Title);
                outputFrame.Variables.Add(v);
                outputCovariates[i] = v;
            }
            int nextOutputOffset = 0;
            for (int srcRow = 0; srcRow < yesPerGroup.Length; srcRow++)
            {
                if (yesPerGroup[srcRow] > 0)
                    nextOutputOffset = FillExtractOutputRow(covariatesOrNull, labelsOrNull, yesPerGroup[srcRow], 1, hasResponses, hasLabels, covariatesCount, outputLabels, outputResponses, outputCovariates, nextOutputOffset, srcRow);
                if (noPerGroup[srcRow] > 0)
                    nextOutputOffset = FillExtractOutputRow(covariatesOrNull, labelsOrNull, noPerGroup[srcRow], 0, hasResponses, hasLabels, covariatesCount, outputLabels, outputResponses, outputCovariates, nextOutputOffset, srcRow);

            }
            ParameterBag outputParameters = new();
            outputParameters.AddOutput("output", outputFrame);
            return new StepOutput(outputParameters);
        }

        private static int FillExtractOutputRow(DataFrame covariatesOrNull, StringVariable labelsOrNull, int copies, int response, bool hasResponses, bool hasLabels, int covariatesCount, StringVariable outputLabels, DoubleVariable outputResponses, GenericVariable<object>[] outputCovariates, int nextOutputOffset, int srcRow)
        {
            for (int copy = 0; copy < copies; copy++)
            {
                if (hasLabels)
                    outputLabels.Data[nextOutputOffset] = labelsOrNull.Data[srcRow];
                if (hasResponses)
                    outputResponses.Data[nextOutputOffset] = response;
                for (int covariate = 0; covariate < covariatesCount; covariate++)
                    outputCovariates[covariate].Data[nextOutputOffset] = covariatesOrNull.Variables[covariate].DataAsObject(srcRow);
                nextOutputOffset++;
            }
            return nextOutputOffset;
        }

        private static int[] ToIntArray(double[] doubles, out int sum)
        {
            int total = 0;
            int[] output = new int[doubles.Length];
            for (int i = 0; i < doubles.Length; i++)
            {
                int rounded = (int)Math.Round(doubles[i], MidpointRounding.AwayFromZero);
                total += rounded;
                output[i] = rounded;
            }
            sum = total;
            return output;
        }

        /// <summary>
        /// Returns an array of the same length as inputFrame.MaxRows.  Values in cells of the output array will be identical where an input row is identical, otherwise different.
        /// This can be used to compress differences across input rows into a single signature array.
        /// </summary>
        /// <param name="inputFrame"></param>
        /// <param name="differenceArray"></param>
        /// <returns></returns>
        private static int ClassifyObjects(DataFrame inputFrame, out int[] differenceArray)
        {
            differenceArray = new int[inputFrame.MaxRows]; // Initialise all rows to zero
            return ClassifyObjects(differenceArray, inputFrame, 1);
        }

        private static int ClassifyObjects(int[] differenceArray, DataFrame inputFrame, int nextDifferentValue)
        {
            foreach (dynamic variable in inputFrame.Variables)
                nextDifferentValue = ClassifyObjectsInOneVariable(differenceArray, variable, nextDifferentValue);
            return nextDifferentValue;
        }

        private class IntAndSomething<T>
        {
            public int I { get; }
            public T Something { get; }

            public override int GetHashCode()
            {
                return I ^ Something.GetHashCode();
            }

            public override bool Equals(object obj)
            {
                if (!(obj is IntAndSomething<T>))
                    return false;
                IntAndSomething<T> other = (IntAndSomething<T>)obj;
                return I == other.I && Something.Equals(other.Something);
            }

            public IntAndSomething(int i, T something)
            {
                I = i;
                Something = something;
            }
        }

        /// <summary>
        /// Assume differenceArray already holds differences for variables earlier than this one.  Where elements of this variable differ, distinguish new values in differenceArray.
        /// </summary>
        /// <param name="differenceArray"></param>
        /// <param name="variable"></param>
        /// <param name="nextDifferentValue"></param>
        /// <returns></returns>
        private static int ClassifyObjectsInOneVariable<T>(int[] differenceArray, GenericVariable<T> variable, int nextDifferentValue)
        {
            T[] testArray = variable.Data;
            HashSet<int> seenDifferences = new();
            Dictionary<IntAndSomething<T>, int> differenceMapper = new();
            for (int i = 0; i < differenceArray.Length; i++)
            {
                int differenceValue = differenceArray[i];
                IntAndSomething<T> probe = new(differenceValue, i < testArray.Length ? testArray[i] : default);
                // Holds the value we'll use
                if (differenceMapper.TryGetValue(probe, out int target))
                {
                    // We've seen this value before; use the existing mapping
                }
                else
                {
                    // We've not seen this combination before.  Create a mapping for it and set the value in differenceArray accordingly.
                    // If this is the first time we've seen this value in differenceArray, re-use it; otherwise, assign a new unique value.
                    if (!seenDifferences.Contains(differenceValue))
                    {
                        seenDifferences.Add(differenceValue);
                        target = differenceValue;
                    }
                    else
                        target = nextDifferentValue++;
                    differenceMapper.Add(probe, target);
                }
                differenceArray[i] = target;
            }
            return nextDifferentValue;
        }

        private class CountAndRowIndex
        {
            public int Count { get; set; }
            public int RowIndex { get; set; }
        }

        private class RespondersCountAndRowIndex : CountAndRowIndex
        {
            public int Responders { get; set; }
            public int NonResponders => Count - Responders;
            public double ProportionResponding => Responders / (double)Count;
        }

        internal static StepOutput ValuesToFrequencies(ParameterBag parameters)
        {
            DataFrame rawValuesFrame = parameters["rawValues"].AsDataFrame;

            // Gather all labels mentioned, and construct counts for each one of those labels
            List<string> labelsByDiscoveryOrder = new();
            Dictionary<string, int[]> countsByLabelAndVariable = new();
            for (int variableIndex = 0; variableIndex < rawValuesFrame.Variables.Count; variableIndex++)
            {
                ClassifierVariable cv = (ClassifierVariable)rawValuesFrame.Variables[variableIndex];
                foreach (Group group in cv.Groups)
                {
                    // HACK: There has to be a better way of getting rid of missing values - but there's no CategorySkipMissing selection.
                    if (Formatting.MISSINGLABEL.Equals(group.Label))
                        continue;

                    if (!countsByLabelAndVariable.TryGetValue(group.Label, out int[] countsByVariable))
                    {
                        countsByVariable = new int[rawValuesFrame.Variables.Count];
                        countsByLabelAndVariable.Add(group.Label, countsByVariable);
                        labelsByDiscoveryOrder.Add(group.Label);
                    }
                    countsByVariable[variableIndex] += group.NBin;
                }
            }

            labelsByDiscoveryOrder.Sort(new SortAlphaNumeric());

            bool shouldUseProportions = rawValuesFrame.Variables.Count > 1;

            // Synthesise "values" and "labels" variables suitable for a bar plot
            ParameterBag outputParameters = new();
            DataFrame labelsFrame = new(new StringVariable(labelsByDiscoveryOrder.ToArray()));
            outputParameters.AddOutput("labels", labelsFrame);

            DataFrame valuesFrame = new() { Name = rawValuesFrame.Name };
            outputParameters.AddOutput("values", valuesFrame);
            // A bit of rotation - we've stored counts in rows, the output variables want them by column.
            for (int valueIndex = 0; valueIndex < rawValuesFrame.Variables.Count; valueIndex++)
            {
                double[] data = new double[labelsByDiscoveryOrder.Count];
                double sum = 0;
                for (int labelIndex = 0; labelIndex < labelsByDiscoveryOrder.Count; labelIndex++)
                {
                    string label = labelsByDiscoveryOrder[labelIndex];
                    int[] countsByVariable = countsByLabelAndVariable[label];
                    double value = countsByVariable[valueIndex];
                    data[labelIndex] = value;
                    sum += value;
                }
                if (shouldUseProportions && sum > 0)
                    for (int labelIndex = 0; labelIndex < labelsByDiscoveryOrder.Count; labelIndex++)
                        data[labelIndex] /= sum;
                DoubleVariable values = new(data, rawValuesFrame.Variables[valueIndex].Title);
                valuesFrame.Variables.Add(values);
            }
            return new StepOutput(outputParameters);
        }

        private class SortAlphaNumeric : IComparer<string>
        {
            private static int Compare(string x, string y)
            {
                if (x.Equals(y))
                    return 0;

                //  If both are numeric, compare numerically; else, compare as text
                bool lower;
                if (double.TryParse(x, out double numericX) && double.TryParse(y, out double numericY))
                    lower = numericX <= numericY;
                else
                    lower = string.CompareOrdinal(x, y) < 0;

                return lower ? -1 : 1;
            }

            // interface methods implemented by Compare
            int IComparer<string>.Compare(string x, string y)
            {
                return Compare(x, y);
            }
        }
    }
}
