using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using StatsDirect.Charting;
using StatsDirect.Data;
using StatsDirect.Numerics;
using StatsDirect.TemplateProcessing;
using StatsDirect.Templates;
using StatsDirect.Utilities;

namespace StatsDirect.Builtins
{
    public static class Describe
    {
        private class SortGroupByTitleAscending : IComparer<Group>
        {
            private static int Compare(Group x, Group y)
            {
                if (x.Label.Equals(y.Label))
                    return 0;

                //  If both titles are numeric, compare numerically; else, compare as text
                bool lower;
                if (double.TryParse(x.Label, out double numericX) && double.TryParse(y.Label, out double numericY))
                    lower = numericX <= numericY;
                else
                    lower = string.CompareOrdinal(x.Label, y.Label) < 0;

                return lower ? -1 : 1;
            }

            // interface methods implemented by Compare
            int IComparer<Group>.Compare(Group x, Group y)
            {
                return Compare(x, y);
            }
        }

        private class SortGroupByTitleDescending : IComparer<Group>
        {
            private static int Compare(Group x, Group y)
            {
                if (x.Label.Equals(y.Label))
                    return 0;

                //  If both titles are numeric, compare numerically; else, compare as text
                bool lower;
                if (double.TryParse(x.Label, out double numericX) && double.TryParse(y.Label, out double numericY))
                    lower = numericX <= numericY;
                else
                    lower = string.CompareOrdinal(x.Label, y.Label) < 0;

                return lower ? 1 : -1;
            }

            // interface methods implemented by Compare
            int IComparer<Group>.Compare(Group x, Group y)
            {
                return Compare(x, y);
            }
        }

        private class SortGroupByNbinAscending : IComparer<Group>
        {
            private static int Compare(Group x, Group y)
            {
                return x.NBin == y.NBin ? 0 : x.NBin < y.NBin ? -1 : 1;
            }

            // interface methods implemented by Compare
            int IComparer<Group>.Compare(Group x, Group y)
            {
                return Compare(x, y);
            }
        }

        private class SortGroupByNbinDescending : IComparer<Group>
        {
            private static int Compare(Group x, Group y)
            {
                return x.NBin == y.NBin ? 0 : x.NBin < y.NBin ? 1 : -1;
            }

            // interface methods implemented by Compare
            int IComparer<Group>.Compare(Group x, Group y)
            {
                return Compare(x, y);
            }
        }

        public static StepOutput RptPreferences(ParameterBag parameters)
        {
            const string pg = "Preference Groups";

            int seed = parameters["seed"].AsInt32;
            DataFrame capacitiesFrame = parameters["capacities"].AsDataFrame;
            DoubleVariable capacitiesVariable = (DoubleVariable)capacitiesFrame.Variables[0];
            int groups = capacitiesVariable.Length;
            int[] groupCapacities = new int[groups]; // 0-based
            int capacity = 0;
            for (int i = 0; i < groups; i++)
            {
                groupCapacities[i] = (int)capacitiesVariable.Data[i];
                capacity += groupCapacities[i];
            }
            DataFrame preferencesFrame = parameters["preferences"].AsDataFrame;
            int preferences = preferencesFrame.VariableCount;
            int subjects = preferencesFrame.Variables[0].Length;
            int[,] x = new int[preferences + 1, subjects + 1];
            for (int i = 1; i <= preferences; i++)
            {
                DoubleVariable preferencesVariable = (DoubleVariable)preferencesFrame.Variables[i - 1];
                for (int j = 1; j <= subjects; j++)
                {
                    double value = preferencesVariable.Data[j - 1];
                    x[i, j] = (int)value;
                    if (value == Constant.MISSING)
                    {
                        // #1328: Repeat the first preference if a subject doesn't express all preferences.
                        x[i, j] = x[1, j];
                    }
                    else if (x[i, j] < 1 || x[i, j] > groups)
                    {
                        throw new TemplateOperationCancelledException("invalid preference in group " + i + " at row " + j, pg);
                    }
                }
            }
            if (groups < preferences)
            {
                throw new TemplateOperationCancelledException("fewer groups than preferences", pg);
            }
            if (capacity < subjects)
            {
                throw new TemplateOperationCancelledException("more subjects (" + subjects + ") than total capacity of groups (" + capacity + ")", pg);
            }
            bool[] done = new bool[subjects + 1]; // 1-based
            int[] allocatedGroup = new int[subjects + 1]; // 1-based
            int[] allocatedSoFar = new int[groups + 1]; // 1-based
            int[] toConsider = new int[subjects]; // 0-based
            MersenneTwister mt = new(seed);
            int ok = 0;
            // First allocate according to preferences where possible - 1st preference, then 2nd preference, etc..
            for (int preference = 1; preference <= preferences; preference++)
            {
                for (int grp = 1; grp <= groups; grp++)
                {
                    // If the group is already full, there's no point trying to assign any more at this preference
                    if (allocatedSoFar[grp] < groupCapacities[grp - 1])
                    {
                        // Gather all subjects who have expressed a preference here for group grp
                        int underConsideration = 0;
                        for (int subject = 1; subject <= subjects; subject++)
                            if (x[preference, subject] == grp && !done[subject])
                                toConsider[underConsideration++] = subject;

                        // Allocate those who want this group to it; if it's over-subscribed, shuffle the candidates so that all have an equal chance to get their choice.
                        if (underConsideration > 0)
                        {
                            Shuffle(mt, toConsider, 0, underConsideration - 1);
                            int space = groupCapacities[grp - 1] - allocatedSoFar[grp];
                            int successfulCandidates = Math.Min(space, underConsideration);
                            for (int toAllocate = 0; toAllocate < successfulCandidates; toAllocate++)
                            {
                                int subject = toConsider[toAllocate];
                                allocatedGroup[subject] = grp;
                                done[subject] = true;
                                allocatedSoFar[grp]++;
                                ok++;
                            }
                        }
                    }
                }
            }

            // By now, we've assigned by preference wherever possible.  Allocate any remaining subjects randomly to groups that have space.
            while (ok < subjects)
            {
                // Put groups with remaining space into toConsider...
                int availableGroups = 0;
                for (int grp = 1; grp <= groups; grp++)
                    if (allocatedSoFar[grp] < groupCapacities[grp - 1])
                        for (int k = 1; k <= groupCapacities[grp - 1] - allocatedSoFar[grp]; k++)
                            toConsider[availableGroups++] = grp;
                // ... and shuffle them so that they're filled in random order
                Shuffle(mt, toConsider, 0, availableGroups - 1);

                // Find unallocated subjects and allocate one to a random group until we run out of subjects or groups.
                int groupToUse = 0;
                for (int k = 1; k <= subjects; k++)
                {
                    if (!done[k])
                    {
                        allocatedGroup[k] = toConsider[groupToUse++];
                        ok++;
                    }

                    // Go round again if we have more subjects than groups into which to place them in this pass
                    if (groupToUse >= availableGroups)
                        break;
                }
            }

            ParameterBag outputParameters = new();
            outputParameters.AddOutput("groups", groups);
            outputParameters.AddOutput("capacity", capacity);
            outputParameters.AddOutput("subjects", subjects);
            // outputParameters.AddOutput("seed", seed); Not required as input seed is preserved in output
            IList<ParameterBag> groupsList = new List<ParameterBag>();
            outputParameters.AddOutput("*groups", groupsList);
            for (int i = 1; i <= subjects; i++)
            {
                ParameterBag groupsParameters = new();
                groupsList.Add(groupsParameters);
                groupsParameters.AddOutput("sub", i);
                groupsParameters.AddOutput("grp", allocatedGroup[i]);
            }
            return new StepOutput(outputParameters);
        }

        /// <summary>
        /// Randomly change the order of items ary[lowerBound] to ary[upperBound] inclusive, taking random numbers from mt.
        /// </summary>
        private static void Shuffle(MersenneTwister mt, int[] ary, int lowerBound, int upperBound)
        {
            if (upperBound - lowerBound <= 0)
                return;
            {
                for (int tn = 1; tn <= 3; tn++)
                {
                    for (int k = lowerBound; k <= upperBound; k++)
                    {
                        int nrp = (int)Math.Floor((upperBound - lowerBound + 1) * mt.NextDouble()) + lowerBound;
                        int tp = ary[k];
                        ary[k] = ary[nrp];
                        ary[nrp] = tp;
                    }
                }
            }
        }

        public static StepOutput RptFrequency(ParameterBag parameters)
        {
            DataFrame data = parameters["data"].AsDataFrame;
            for (int v = 0; v < data.VariableCount; v++)
            {
                if (!(data.Variables[v] is ClassifierVariable))
                    data.Variables[v] = TemplateProcessor.gidx_bins(data.Variables[v] as DoubleVariable);
            }

            bool shouldSortByValue = "value".Equals(parameters["sortBy"].AsString);
            bool shouldSortAscending = "asc".Equals(parameters["sortOrder"].AsString);

            ParameterBag outputParameters = new();
            List<ParameterBag> variableList = new();
            outputParameters.AddOutput("*variable", variableList);
            foreach (IVariable v in data.Variables)
            {
                ClassifierVariable vc = (ClassifierVariable)v;
                ParameterBag variableParameters = new();
                variableList.Add(variableParameters);
                variableParameters.AddOutput("ti", vc.Title);
                variableParameters.AddOutput("n", vc.Length);
                int cm = 0;
                int xtot = vc.Length;
                int bins = vc.GroupCount;
                Group[] bin = new Group[bins + 1];
                for (int i = 1; i <= bins; i++)
                {
                    bin[i] = vc.Groups[i - 1];
                    if (bin[i].Label == Formatting.MISSINGLABEL)
                        xtot -= bin[i].NBin;
                }

                IComparer<Group> comparer;
                if (shouldSortByValue)
                {
                    if (shouldSortAscending)
                        comparer = new SortGroupByTitleAscending();
                    else
                        comparer = new SortGroupByTitleDescending();
                }
                else
                {
                    if (shouldSortAscending)
                        comparer = new SortGroupByNbinAscending();
                    else
                        comparer = new SortGroupByNbinDescending();
                }
                Array.Sort(bin, 1, bins, comparer);

                List<ParameterBag> binList = new();
                variableParameters.AddOutput("*bin", binList);
                for (int i = 1; i <= bins; i++)
                {
                    int xn = bin[i].NBin;
                    ParameterBag binParameters = new();
                    binList.Add(binParameters);
                    binParameters.AddOutput("x", bin[i].Label);
                    binParameters.AddOutput("fx", xn);
                    if (bin[i].Label != Formatting.MISSINGLABEL)
                    {
                        binParameters.AddOutput("pc", 100.0 * Convert.ToDouble(xn) / Convert.ToDouble(xtot));
                        cm += xn;
                        binParameters.AddOutput("cm", cm);
                        binParameters.AddOutput("pc2", 100.0 * Convert.ToDouble(cm) / Convert.ToDouble(xtot));
                    }
                    else
                    {
                        binParameters.AddOutput("pc", "na");
                        binParameters.AddOutput("cm", "na");
                        binParameters.AddOutput("pc2", "na");
                    }
                }
            }
            return new StepOutput(outputParameters);
        }


        public static StepOutput QuickSummary(IUserInterface host, ParameterBag parameters)
        {
            double GAMMA = parameters["gamma"].AsDouble;
            DataFrame data = parameters["data"].AsDataFrame;
            DoubleVariable v0 = (DoubleVariable)data.Variables[0];
            Summary sx = new();
            sx.FullSummaryFromX(v0.Data, v0.Length, v0.Title, GAMMA, 5, 95, 1);
            const int flt = 6;
            const int k = 24;
            StringBuilder sb = new();
            sb.AppendLine("Title: " + v0.Title);
            sb.AppendLine(string.Empty);
            sb.AppendLine(Formatting.PadTo("Valid data", k) + sx.ValidData);
            sb.AppendLine(Formatting.PadTo("Missing", k) + sx.MissingData);
            sb.AppendLine(Formatting.PadTo("Sum", k) + Formatting.RoundOut(sx.Sum, flt));
            sb.AppendLine(Formatting.PadTo("Mean", k) + Formatting.RoundOut(sx.Mean, flt));
            sb.AppendLine(Formatting.PadTo("Variance", k) + Formatting.RoundOut(sx.Variance, flt));
            sb.AppendLine(Formatting.PadTo("Standard deviation", k) + Formatting.RoundOut(sx.SD, flt));
            sb.AppendLine(Formatting.PadTo("Variation coefficient", k) + Formatting.RoundOut(sx.VarianceCoefficient, flt));
            sb.AppendLine(Formatting.PadTo("Standard error of mean", k) + Formatting.RoundOut(sx.SEM, flt));
            sb.AppendLine(Formatting.PadTo(Formatting.XRound(100 * GAMMA, 1) + "% Upper CL of mean", k) + Formatting.RoundOut(sx.MeanUCL, flt));
            sb.AppendLine(Formatting.PadTo(Formatting.XRound(100 * GAMMA, 1) + "% Lower CL of mean", k) + Formatting.RoundOut(sx.MeanLCL, flt));
            sb.AppendLine(Formatting.PadTo("Geometric mean", k) + Formatting.RoundOut(sx.GeometricMean, flt));
            sb.AppendLine(Formatting.PadTo("Skewness", k) + Formatting.RoundOut(sx.Skewness, flt));
            sb.AppendLine(Formatting.PadTo("Kurtosis", k) + Formatting.RoundOut(sx.Kurtosis, flt));
            sb.AppendLine(Formatting.PadTo("Maximum", k) + Formatting.RoundOut(sx.Maximum, flt));
            sb.AppendLine(Formatting.PadTo("95th percentile", k) + Formatting.RoundOut(sx.UserCentileU, flt));
            sb.AppendLine(Formatting.PadTo("Upper quartile", k) + Formatting.RoundOut(sx.UpperQuartile, flt));
            sb.AppendLine(Formatting.PadTo("Median", k) + Formatting.RoundOut(sx.Median, flt));
            sb.AppendLine(Formatting.PadTo("Lower quartile", k) + Formatting.RoundOut(sx.LowerQuartile, flt));
            sb.AppendLine(Formatting.PadTo("Interquartile range", k) + Formatting.RoundOut(sx.InterquartileRange, flt));
            sb.AppendLine(Formatting.PadTo("5th percentile", k) + Formatting.RoundOut(sx.UserCentileL, flt));
            sb.AppendLine(Formatting.PadTo("Minimum", k) + Formatting.RoundOut(sx.Minimum, flt));
            sb.AppendLine(Formatting.PadTo("Range", k) + Formatting.RoundOut(sx.Range, flt));
            SummaryStatisticsOptions sso = new() { Text = sb.ToString() };
            host.Amend(sso, parameters);
            return StepOutput.Empty();
        }

        public static StepOutput RptUnivariateSummary(ParameterBag parameters)
        {
            return RptDescriptive(parameters, false);
        }

        public static StepOutput RptWeightedUnivariateSummary(ParameterBag parameters)
        {
            return RptDescriptive(parameters, true);
        }

        private enum SummaryType
        {
            ValidData = 0,
            MissingData = 1,
            Sum = 2,
            Mean = 3,
            Variance = 4,
            Sd = 5,
            VarianceCoefficient = 6,
            Sem = 7,
            MeanUcl = 8,
            MeanLcl = 9,
            GeometricMean = 10,
            Skewness = 11,
            Kurtosis = 12,
            Maximum = 13,
            UpperQuartile = 14,
            Median = 15,
            LowerQuartile = 16,
            InterquartileRange = 17,
            Minimum = 18,
            Range = 19,
            Udc1 = 20,
            Udc2 = 21
        }

        private static StepOutput RptDescriptive(ParameterBag parameters, bool isWeighted)
        {
            double nsumwt = 0;
            string wti = null;
            ColumnData[] cdx;
            double[,] x; double[,] w = null;

            // get data
            DataFrame data = parameters["data"].AsDataFrame;
            if (isWeighted)
            {
                nsumwt = Constant.MISSING;
                // store the data
                x = new double[data.VariableCount, data.MaxRows + 1];
                cdx = new ColumnData[data.VariableCount];
                for (int i = 0; i < data.VariableCount; i++)
                {
                    DoubleVariable vi = (DoubleVariable)data.Variables[i];
                    cdx[i] = new ColumnData { Title = vi.Title, Rows = vi.Length };
                }

                w = new double[data.VariableCount, data.MaxRows + 1];
                DataFrame weightsFrame = parameters["weights"].AsDataFrame;
                DoubleVariable weightsVariable = (DoubleVariable)weightsFrame.Variables[0];
                wti = weightsVariable.Title;

                // Load the data, skipping rows where weights are 0 or missing
                int targetRow = 1;
                int removed = 0;
                for (int row = 0; row < data.MaxRows; row++)
                {
                    double weight = weightsVariable.Data[row];
                    if (weight == Constant.MISSING || weight == 0)
                    {
                        // Remove the row from any variables that are at least this long
                        for (int col = 0; col < data.VariableCount; col++)
                        {
                            if (row < cdx[col].Rows + removed)
                                cdx[col].Rows--;
                        }
                        removed++;
                        continue;
                    }

                    if (weight < 0.0)
                        throw new TemplateOperationCancelledException("Weights must not be negative", "Descriptive Statistics");

                    for (int col = 0; col < data.VariableCount; col++)
                    {
                        w[col, targetRow] = weight;
                        DoubleVariable vi = (DoubleVariable)data.Variables[col];
                        double value = Constant.MISSING;
                        if (vi.Length > row)
                            value = vi.Data[row];
                        x[col, targetRow] = value;
                    }
                    targetRow++;
                }
            }
            else
            {
                //  Index = 1: Univariate summary
                // store the data
                x = new double[data.VariableCount, data.MaxRows + 1];
                cdx = new ColumnData[data.VariableCount];
                for (int i = 0; i < data.VariableCount; i++)
                {
                    DoubleVariable vi = (DoubleVariable)data.Variables[i];
                    cdx[i] = new ColumnData { Title = vi.Title, Rows = vi.Length };
                    for (int j = 1; j <= vi.Length; j++)
                        x[i, j] = vi.Data[j - 1];
                }
            }

            // get options
            double gamma = parameters["gamma"].AsDouble;
            string qxcl = " " + Formatting.XRound(gamma * 100, 1) + "% CL of mean";
            string sumTitle = isWeighted ? "Sum of weights" : "Sum";
            string[] titles = { "Valid data", "Missing data", sumTitle, "Mean", "Variance", "Standard deviation", "Variance coefficient", "Standard error of mean", "Upper" + qxcl, "Lower" + qxcl, "Geometric mean", "Skewness", "Kurtosis", "Maximum", "Upper quartile", "Median", "Lower quartile", "Interquartile range", "Minimum", "Range", "User defined centiles", null };

            Dictionary<SummaryType, bool> shouldOutput = new()
            {
                [SummaryType.ValidData] = parameters["report-valid-data"].AsBoolean,
                [SummaryType.MissingData] = parameters["report-missing-data"].AsBoolean,
                [SummaryType.Sum] = parameters["report-sum"].AsBoolean,
                [SummaryType.Mean] = parameters["report-mean"].AsBoolean,
                [SummaryType.Variance] = parameters["report-variance"].AsBoolean,
                [SummaryType.Sd] = parameters["report-sd"].AsBoolean,
                [SummaryType.VarianceCoefficient] = parameters["report-variance-coeff"].AsBoolean,
                [SummaryType.Sem] = parameters["report-sem"].AsBoolean,
                [SummaryType.MeanUcl] = parameters["report-u95cl"].AsBoolean,
                [SummaryType.MeanLcl] = parameters["report-l95cl"].AsBoolean,
                [SummaryType.GeometricMean] = parameters["report-geometric-mean"].AsBoolean,
                [SummaryType.Skewness] = parameters["report-skewness"].AsBoolean,
                [SummaryType.Kurtosis] = parameters["report-kurtosis"].AsBoolean,
                [SummaryType.Maximum] = parameters["report-maximum"].AsBoolean,
                [SummaryType.UpperQuartile] = parameters["report-uq"].AsBoolean,
                [SummaryType.Median] = parameters["report-median"].AsBoolean,
                [SummaryType.LowerQuartile] = parameters["report-lq"].AsBoolean,
                [SummaryType.InterquartileRange] = parameters["report-iqr"].AsBoolean,
                [SummaryType.Minimum] = parameters["report-minimum"].AsBoolean,
                [SummaryType.Range] = parameters["report-range"].AsBoolean,
                [SummaryType.Udc1] = parameters["report-udc"].AsBoolean,
                [SummaryType.Udc2] = parameters["report-udc"].AsBoolean
            };

            double centxl = parameters["report-udca"].AsDouble * 100.0;
            double centxu = parameters["report-udcb"].AsDouble * 100.0;
            int prevCentileType = Parsing.Cint_Txt(parameters["report-centile-type"].AsString);
            // prevchk1 = true; 
            // If there's no output-to-frame, we're being called from the summary - which always wants this.
            bool shouldSave = !parameters.ContainsKey("output-to-frame") || parameters["output-to-frame"].AsBoolean;

            // get a result object for each column of data
            Summary[] sx = new Summary[data.VariableCount];
            for (int i = 0; i < data.VariableCount; i++)
            {
                sx[i] = new Summary();
                if (isWeighted)
                    sx[i].WeightedSummaryFromXK(i, x, cdx[i].Rows, cdx[i].Title, gamma, centxl, centxu, w, wti, nsumwt);
                else
                    sx[i].FullSummaryFromXK(i, x, cdx[i].Rows, cdx[i].Title, gamma, centxl, centxu, prevCentileType);
            }

            // Fill the report
            // Insert the result into the report
            ParameterBag outputParameters = new();
            List<ParameterBag> titlesList = new();
            outputParameters.AddOutput("*titles", titlesList);
            for (int i = 0; i < data.VariableCount; i++)
            { // Title

                ParameterBag titlesParameters = new();
                titlesList.Add(titlesParameters);
                string val = sx[i].Title;
                if ((i + 1) % 3 == 0 && data.VariableCount > 3)
                    val += Formatting.RTFCRLF;
                titlesParameters.AddOutput("title", val);
            }
            List<ParameterBag> fieldsList = new();
            outputParameters.AddOutput("*fields", fieldsList);
            foreach (SummaryType s in Enum.GetValues(typeof(SummaryType)))
            {
                if (shouldOutput[s])
                    fieldsList.Add(FillField(s, sx, data.VariableCount, shouldOutput[s], titles[(int)s], isWeighted));
            }

            // Fill the worksheet if required
            if (shouldSave)
            {
                // Find how many columns have been selected
                int lc = 0;
                foreach (SummaryType s in Enum.GetValues(typeof(SummaryType)))
                    if (shouldOutput[s])
                        lc++;

                // prevchk2 = true; 
                if (lc > 0)
                {
                    DataFrame outputFrame = new();
                    outputParameters.AddOutput("output", outputFrame);
                    if (cdx.Length == 1)
                    {
                        // Short form, single column
                        StringVariable labels = new(lc, "Measure");
                        outputFrame.Variables.Add(labels);
                        DoubleVariable values = new(lc, "Value");
                        outputFrame.Variables.Add(values);
                        int row = 0;
                        foreach (SummaryType s in Enum.GetValues(typeof(SummaryType)))
                        {
                            if (shouldOutput[s])
                            {
                                labels.Data[row] = Caption(s, sx[0], titles);
                                values.Data[row] = Value(s, sx[0], isWeighted);
                                row++;
                            }
                        }
                    }
                    else
                    {
                        // If the worksheet is loaded then fill it
                        StringVariable totalsVariable = new() { Title = "Title" };
                        totalsVariable.EnsureLength(data.VariableCount);
                        for (int i = 0; i < data.VariableCount; i++)
                            totalsVariable.SetData(i, sx[i].Title);
                        outputFrame.Variables.Add(totalsVariable);
                        foreach (SummaryType s in Enum.GetValues(typeof(SummaryType)))
                        {
                            if (shouldOutput[s])
                                outputFrame.Variables.Add(FillCell(s, sx, data.VariableCount, titles, isWeighted));
                        }
                    }
                }
            }

            return new StepOutput(outputParameters);
        }

        ///  <summary>
        ///  Return the median of the elements of x from ia to iz inclusive.
        ///  </summary>
        public static double Median(double[] x, int ia, int iz)
        {
            double[] ao = new double[iz - ia + 1];
            int reali = 0;
            for (int i = ia; i <= iz; i++)
            {
                if (x[i] != Constant.MISSING)
                {
                    ao[reali] = x[i];
                    reali += 1;
                }
            }
            //  At this point, reali counts the number of elements that have been copied to ao.
            if (reali > 1)
            {
                Array.Sort(ao, 0, reali);
                //  The -1 is because ao is 0-based
                double imdn = 0.5 * (reali + 1) - 1;
                if (imdn < 0)
                    imdn = 0;
                if (imdn > reali - 1)
                    imdn = reali - 1;
                double fimdn = Math.Floor(imdn);
                int iimdn = (int)fimdn;
                if (imdn - fimdn == 0)
                {
                    //  Exact element
                    return ao[iimdn];
                }
                //  Weighted mean of adjacent elements
                return ao[iimdn] + (ao[iimdn + 1] - ao[iimdn]) * (imdn - fimdn);
            }
            return Constant.MISSING;
        }

        private static string Caption(SummaryType summaryType, Summary sx, string[] titles)
        {
            switch (summaryType)
            {
                case SummaryType.Udc1:
                    return sx.UserCentileUCaption;
                case SummaryType.Udc2:
                    return sx.UserCentileLCaption;
                default:
                    return titles[(int)summaryType];
            }
        }

        private static double Value(SummaryType summaryType, Summary sx, bool isWeighted)
        {
            switch (summaryType)
            {
                case SummaryType.ValidData:
                    return sx.ValidData;
                case SummaryType.MissingData:
                    return sx.MissingData;
                case SummaryType.Sum:
                    // the weighted summary labels this row "Sum of weights", and the report prints SumOfWeights for it
                    return isWeighted ? sx.SumOfWeights : sx.Sum;
                case SummaryType.Mean:
                    return sx.Mean;
                case SummaryType.Variance:
                    return sx.Variance;
                case SummaryType.Sd:
                    return sx.SD;
                case SummaryType.VarianceCoefficient:
                    return sx.VarianceCoefficient;
                case SummaryType.Sem:
                    return sx.SEM;
                case SummaryType.MeanUcl:
                    return sx.MeanUCL;
                case SummaryType.MeanLcl:
                    return sx.MeanLCL;
                case SummaryType.GeometricMean:
                    return sx.GeometricMean;
                case SummaryType.Skewness:
                    return sx.Skewness;
                case SummaryType.Kurtosis:
                    return sx.Kurtosis;
                case SummaryType.Maximum:
                    return sx.Maximum;
                case SummaryType.UpperQuartile:
                    return sx.UpperQuartile;
                case SummaryType.Median:
                    return sx.Median;
                case SummaryType.LowerQuartile:
                    return sx.LowerQuartile;
                case SummaryType.InterquartileRange:
                    return sx.InterquartileRange;
                case SummaryType.Minimum:
                    return sx.Minimum;
                case SummaryType.Range:
                    return sx.Range;
                case SummaryType.Udc1:
                    return sx.UserCentileU;
                case SummaryType.Udc2:
                    return sx.UserCentileL;
                default:
                    throw new ArgumentException("Unknown option", nameof(summaryType));
            }
        }

        private static DoubleVariable FillCell(SummaryType summaryType, Summary[] sx, int cols, string[] titles, bool isWeighted)
        {
            DoubleVariable v = new();
            v.EnsureLength(cols);
            v.Title = Caption(summaryType, sx[0], titles);
            for (int i = 0; i < cols; i++)
                v.SetData(i, Value(summaryType, sx[i], isWeighted));
            return v;
        }

        private static ParameterBag FillField(SummaryType opt, Summary[] sx, int cols, bool optChecked, string optTitle, bool isWeighted)
        {
            ParameterBag fieldParameters = new();
            List<ParameterBag> resultsList = new();
            fieldParameters.AddOutput("*results", resultsList);
            if (optChecked)
            {
                switch (opt)
                {
                    case SummaryType.Udc1:
                        fieldParameters.AddOutput("title", sx[0].UserCentileUCaption);
                        break;
                    case SummaryType.Udc2:
                        fieldParameters.AddOutput("title", sx[0].UserCentileLCaption);
                        break;
                    default:
                        fieldParameters.AddOutput("title", optTitle);
                        break;
                }
                for (int i = 0; i < cols; i++)
                {
                    ParameterBag resultsParameters = new();
                    resultsList.Add(resultsParameters);
                    object res;
                    switch (opt)
                    {
                        case SummaryType.ValidData:
                            res = sx[i].ValidData;
                            break;
                        case SummaryType.MissingData:
                            res = sx[i].MissingData;
                            break;
                        case SummaryType.Sum:
                            res = isWeighted ? sx[i].SumOfWeights : sx[i].Sum;
                            break;
                        case SummaryType.Mean:
                            res = sx[i].Mean;
                            break;
                        case SummaryType.Variance:
                            res = sx[i].Variance;
                            break;
                        case SummaryType.Sd:
                            res = sx[i].SD;
                            break;
                        case SummaryType.VarianceCoefficient:
                            res = sx[i].VarianceCoefficient;
                            break;
                        case SummaryType.Sem:
                            res = sx[i].SEM;
                            break;
                        case SummaryType.MeanUcl:
                            res = sx[i].MeanUCL;
                            break;
                        case SummaryType.MeanLcl:
                            res = sx[i].MeanLCL;
                            break;
                        case SummaryType.GeometricMean:
                            res = sx[i].GeometricMean;
                            break;
                        case SummaryType.Skewness:
                            res = sx[i].Skewness;
                            break;
                        case SummaryType.Kurtosis:
                            res = sx[i].Kurtosis;
                            break;
                        case SummaryType.Maximum:
                            res = sx[i].Maximum;
                            break;
                        case SummaryType.UpperQuartile:
                            res = sx[i].UpperQuartile;
                            break;
                        case SummaryType.Median:
                            res = sx[i].Median;
                            break;
                        case SummaryType.LowerQuartile:
                            res = sx[i].LowerQuartile;
                            break;
                        case SummaryType.InterquartileRange:
                            res = sx[i].InterquartileRange;
                            break;
                        case SummaryType.Minimum:
                            res = sx[i].Minimum;
                            break;
                        case SummaryType.Range:
                            res = sx[i].Range;
                            break;
                        case SummaryType.Udc1:
                            res = sx[i].UserCentileU;
                            break;
                        case SummaryType.Udc2:
                            res = sx[i].UserCentileL;
                            break;
                        default:
                            throw new ArgumentException("Unknown opt", nameof(opt));
                    }
                    resultsParameters.AddOutput("result", res);
                }
            }
            return fieldParameters;
        }

        public static StepOutput RptTimeSeriesSummary(/* TODO: IPreferencesAndProgressBar */ ITemplateHost host, ParameterBag parameters)
        {
            // Extract our variables from the input
            DoubleVariable timesVariable = parameters["times"].AsDataFrame.Variables[0] as DoubleVariable;
            DoubleVariable observationsVariable = parameters["observations"].AsDataFrame.Variables[0] as DoubleVariable;
            ClassifierVariable subjectIdsVariable = parameters["subjectIds"].AsDataFrame.Variables[0] as ClassifierVariable;
            bool hasGroups = parameters.ContainsKey("groups") && parameters["groups"] != null && parameters["groups"].IsDataFrame;
            ClassifierVariable groupsVariable = null;
            if (hasGroups)
                groupsVariable = (ClassifierVariable)parameters["groups"].AsDataFrame.Variables[0];
            double ci = parameters["ci"].AsDouble;
            bool addZeroObservationsAtZeroTime = parameters.ContainsKey("addZeroObservationAtZeroTime") && parameters["addZeroObservationAtZeroTime"] != null && parameters["addZeroObservationAtZeroTime"].IsBoolean && parameters["addZeroObservationAtZeroTime"].AsBoolean;
            //  The question is asked only when no observation time is zero; keep to that here too, so that a real time zero row is never overwritten or counted twice
            if (addZeroObservationsAtZeroTime)
                foreach (double time in timesVariable.Data)
                    if (time == 0)
                    {
                        addZeroObservationsAtZeroTime = false;
                        break;
                    }
            // Bootstrap variables
            bool doBootstrap = parameters.ContainsKey("doExactP") && parameters["doExactP"] != null && parameters["doExactP"].IsBoolean && parameters["doExactP"].AsBoolean;
            MersenneTwister mt;
            if (doBootstrap && parameters.ContainsKey("seed") && parameters["seed"] != null && parameters["seed"].IsInt32)
                mt = new MersenneTwister(parameters["seed"].AsInt32);
            else
                mt = new MersenneTwister();
            int iterations = 100000;
            if (doBootstrap && parameters.ContainsKey("iterations") && parameters["iterations"] != null && parameters["iterations"].IsInt32)
                iterations = parameters["iterations"].AsInt32;

            // Data preparation: Construct our values
            List<TimeSeriesSummaryStore> groups = new();
            if (hasGroups)
                foreach (Group group in groupsVariable.Groups)
                {
                    int gid = (int)group.Id;
                    while (groups.Count <= gid)
                        groups.Add(new TimeSeriesSummaryStore());
                    groups[gid].Group = group;
                }
            else
                groups.Add(new TimeSeriesSummaryStore { Group = new Group("all", 0) });

            // Pass 1: Allow the data structures to size themselves
            for (int row = 0; row < timesVariable.Length; row++)
            {
                int group = 0;
                if (hasGroups)
                    group = (int)groupsVariable.Data[row];
                groups[group].NoteRowPass1(timesVariable.Data[row], subjectIdsVariable.Data[row]);
            }
            foreach (TimeSeriesSummaryStore store in groups)
                store.NoteEndOfPass1(addZeroObservationsAtZeroTime);
            // Pass 2: Allow the data structures to accumulate observations
            for (int row = 0; row < timesVariable.Length; row++)
            {
                int group = 0;
                if (hasGroups)
                    group = (int)groupsVariable.Data[row];
                groups[group].NoteRowPass2(timesVariable.Data[row], observationsVariable.Data[row], subjectIdsVariable.Data[row]);
            }
            foreach (TimeSeriesSummaryStore store in groups)
                store.NoteEndOfPass2();

            // Allow the summaries to claculate their values
            foreach (TimeSeriesSummaryStore store in groups)
            {
                store.Calculate(ci, false);
                if (doBootstrap)
                {
                    BootstrappingTimeSeriesSummaryStore bst = new(store);
                    bst.Bootstrap(host, iterations, mt, ci, groups.Count == 2);
                    store.TLclAucBarBootstrap = store.AucMean + bst.TLcl * store.Se;
                    store.TUclAucBarBootstrap = store.AucMean + bst.TUcl * store.Se;
                    store.CompletedIterations = bst.CompletedIterations;
                    store.AucMeans = bst.AucMeans;
                    store.VarAucMeans = bst.VarAucMeans;
                }
            }

            // Output preparation
            ParameterBag outputParameters = new();
            outputParameters.AddOutput("ciOutput", ci * 100);
            List<ParameterBag> groupList = new();
            outputParameters.AddOutput("*group", groupList);
            for (int groupIndex = 0; groupIndex < groups.Count; groupIndex++)
            {
                TimeSeriesSummaryStore group = groups[groupIndex];
                ParameterBag groupParameters = new();
                groupList.Add(groupParameters);
                // Per-group
                groupParameters.AddOutput("groupName", group.Group.Label);
                groupParameters.AddOutput("subjects", group.N);
                groupParameters.AddOutput("totalObservations", group.NObservations);
                groupParameters.AddOutput("meanObservationsPerTimePoint", group.MeanObservationsPerTimePoint);
                groupParameters.AddOutput("aucMean", group.AucMean);
                groupParameters.AddOutput("aucSd", group.AucSd);
                groupParameters.AddOutput("aucSe", group.Se);
                groupParameters.AddOutput("aucTLcl", group.TLclAucBar);
                groupParameters.AddOutput("aucTUcl", group.TUclAucBar);
                groupParameters.AddOutput("aucZLcl", group.ZLclAucBar);
                groupParameters.AddOutput("aucZUcl", group.ZUclAucBar);
                groupParameters.AddOutput("medianAuc", group.MedianAuc);
                groupParameters.AddOutput("iqrAuc", group.UpperQuartileAuc - group.LowerQuartileAuc);
                groupParameters.AddOutput("medianTimeToMax", group.MedianTimeToMax);
                groupParameters.AddOutput("iqrTimeToMax", group.UpperQuartileTimeToMax - group.LowerQuartileTimeToMax);
                groupParameters.AddOutput("medianSlopeToMax", group.MedianSlopeToMax);
                groupParameters.AddOutput("iqrSlopeToMax", group.UpperQuartileSlopeToMax - group.LowerQuartileSlopeToMax);
                groupParameters.AddOutput("meanSlopeToMax", group.MeanSlopeToMax);
                groupParameters.AddOutput("meanSlopeToMaxSD", group.MeanSlopeToMaxSD);

                // Per-subject in this group
                List<ParameterBag> subjectList = new();
                groupParameters.AddOutput("*subject", subjectList);
                foreach (SubjectSummary subject in group.SubjectToSummaryMap.Values)
                {
                    ParameterBag subjectParameters = new();
                    subjectList.Add(subjectParameters);
                    subjectParameters.AddOutput("subjectId", subjectIdsVariable.GroupWithId(subject.SubjectId).Label);
                    subjectParameters.AddOutput("baseline", subject.Baseline);
                    subjectParameters.AddOutput("min", subject.MinObservation);
                    subjectParameters.AddOutput("max", subject.MaxObservation);
                    subjectParameters.AddOutput("timeToMax", subject.TimeToMax);
                    subjectParameters.AddOutput("slopeToMax", subject.SlopeToMax);
                    subjectParameters.AddOutput("auc", subject.Auc);
                }

                // Per-time point in this group
                List<ParameterBag> timeList = new();
                groupParameters.AddOutput("*time", timeList);
                foreach (TimeSummary time in group.TimeToSummaryMap.Values)
                {
                    ParameterBag timeParameters = new();
                    timeList.Add(timeParameters);
                    timeParameters.AddOutput("time", time.Time);
                    timeParameters.AddOutput("observations", time.N);
                    timeParameters.AddOutput("mean", time.Mean);
                    timeParameters.AddOutput("sd", time.Sd);
                    timeParameters.AddOutput("se", time.Se);
                    timeParameters.AddOutput("median", time.Median);
                    timeParameters.AddOutput("iqr", time.UpperQuartile - time.LowerQuartile);
                }

                // Bootstrap (if present)
                if (doBootstrap)
                {
                    List<ParameterBag> bootstrapList = new();
                    groupParameters.AddOutput("*bootstrap", bootstrapList);
                    ParameterBag bootstrapParameters = new();
                    bootstrapList.Add(bootstrapParameters);
                    bootstrapParameters.AddOutput("aucTLclBoot", group.TLclAucBarBootstrap);
                    bootstrapParameters.AddOutput("aucTUclBoot", group.TUclAucBarBootstrap);
                    bootstrapParameters.AddOutput("completedIterations", group.CompletedIterations);
                }

                // Line plot, one line per subject with x-axis = time, y-axis = observation
                ChartDefinition cd = new() { ChartType = ChartType.ScatterXY, ScaleParameters = new ScaleParameters { X = new AxisScaleParameters { ScaleType = ScaleType.Linear }, Y = new AxisScaleParameters { ScaleType = ScaleType.Linear } } };
                double[] times = group.IndexToTimeMap;
                for (int subjectIndex = 0; subjectIndex < group.IndexToSubjectMap.Length; subjectIndex++)
                {
                    double[] subjectObservations = new double[times.Length];
                    for (int timeIndex = 0; timeIndex < group.IndexToTimeMap.Length; timeIndex++)
                        subjectObservations[timeIndex] = group.Observations[timeIndex, subjectIndex];
                    cd.AddXSeries(times, null);
                    cd.AddYSeries(subjectObservations, null);
                }
                ScatterXYOptions options = new(cd.XSeries, true)
                {
                    Title = group.Group.Label,
                    XAxisTitle = timesVariable.Title,
                    YAxisTitle = observationsVariable.Title
                };
                for (int marker = 0; marker < options.MarkerTypes.Count; marker++)
                    options.MarkerTypes[marker] = ChartPreferences.MarkerTypes[ChartOptions.SeriesNumberToMarkerNumber(groupIndex)].Clone();
                cd.ChartOptions = options;
                groupParameters.AddOutput("chart", cd);
            }

            // Normal plots for AUC and log10(AUC) across all groups
            List<double> values = new();
            foreach (TimeSeriesSummaryStore group in groups)
                foreach (SubjectSummary subject in group.SubjectToSummaryMap.Values)
                    values.Add(subject.Auc);
            double[] points = values.ToArray();
            {
                ChartDefinition cd = new() { ChartType = ChartType.Normal };
                cd.AddXSeries(points, "Area Under Curve");

                NormalOptions options = new()
                {
                    Title = "Normal Plot for AUC",
                    XAxisTitle = "Area Under Curve",
                    YAxisTitle = "Normal scores",
                    ShouldScaleZ = true,
                    Method = NormalOptions.ScoreMethod.VanDerWaerden
                };
                cd.ChartOptions = options;
                ParameterBag results = ChartRendererFactory.PlotForResultsOnly(host, cd);
                outputParameters.AddOutput("aucNormalChart", cd);
                //  The context holds the correlation coefficient r; the report prints R-square
                double rNormal = ((SimpleLinearRegressionContext)results["context"].AsObject).R;
                outputParameters.AddOutput("rSquareNormal", rNormal * rNormal);

            }
            {
                ChartDefinition cd = new() { ChartType = ChartType.Normal };
                for (int i = 0; i < points.Length; i++)
                    points[i] = Math.Log10(points[i]);
                cd.AddXSeries(points, "Log Area Under Curve");
                NormalOptions options = new()
                {
                    Title = "Normal Plot for Log(AUC)",
                    XAxisTitle = "Log Area Under Curve",
                    YAxisTitle = "Normal scores",
                    ShouldScaleZ = true,
                    Method = NormalOptions.ScoreMethod.VanDerWaerden
                };
                cd.ChartOptions = options;
                ParameterBag results = ChartRendererFactory.PlotForResultsOnly(host, cd);
                outputParameters.AddOutput("aucLogNormalChart", cd);
                double rLogNormal = ((SimpleLinearRegressionContext)results["context"].AsObject).R;
                outputParameters.AddOutput("rSquareLogNormal", rLogNormal * rLogNormal);
            }

            // Compare mean AUCs by group with timepoint standard errors
            // Line plot, one line per group with x-axis = time, y-axis = observation
            {
                List<MultiDoubleSeries> errorSeries = new(groups.Count);
                string[] seriesTitles = new string[groups.Count];
                double cit = PDF.gauinv(1.0 - (1.0 - ci) / 2.0);
                for (int groupIndex = 0; groupIndex < groups.Count; groupIndex++)
                {
                    TimeSeriesSummaryStore group = groups[groupIndex];
                    seriesTitles[groupIndex] = group.Group.Label;
                    MultiDoubleSeries s = new() { Title = group.Group.Label };
                    errorSeries.Add(s);

                    // Per-time point in this group
                    s.Data = new MultiDoublePoint[group.TimeToSummaryMap.Count];
                    int tIndex = 0;
                    foreach (TimeSummary time in group.TimeToSummaryMap.Values)
                    {
                        MultiDoublePoint pt = new() { X = time.Time };
                        pt.set_Y(0, time.Mean);
                        pt.set_Y(1, time.Mean - cit * time.Se);
                        pt.set_Y(2, time.Mean + cit * time.Se);
                        s.Data[tIndex++] = pt;
                    }
                }

                ChartDefinition cd = new() { ChartType = ChartType.ErrorBar, ScaleParameters = new ScaleParameters { X = new AxisScaleParameters { ScaleType = ScaleType.Linear }, Y = new AxisScaleParameters { ScaleType = ScaleType.Linear } } };
                ErrorBarOptions options = new()
                {
                    Series = errorSeries,
                    Title = "Group comparison",
                    XAxisTitle = timesVariable.Title,
                    YAxisTitle = observationsVariable.Title,
                    JoinMarkersWithLines = true,
                    ShowLegend = true,
                    SeriesTitles = seriesTitles
                };
                options.SetMarkers();
                cd.ChartOptions = options;
                outputParameters.AddOutput("meanAucChart", cd);
            }

            // Group comparison (if two groups)
            if (groups.Count == 2)
            {
                List<ParameterBag> groupComparisonList = new();
                outputParameters.AddOutput("*groupComparison", groupComparisonList);
                ParameterBag groupComparisonParameters = new();
                groupComparisonList.Add(groupComparisonParameters);

                groupComparisonParameters.AddOutput("group1Title", groups[0].Group.Label);
                groupComparisonParameters.AddOutput("group2Title", groups[1].Group.Label);

                // Welch two sample t test on the subjects' AUCs (Satterthwaite degrees of freedom), group 1 minus group 2
                double v1 = groups[0].VarAucMean;
                double v2 = groups[1].VarAucMean;
                double df = (v1 + v2) * (v1 + v2) / (v1 * v1 / groups[0].Df + v2 * v2 / groups[1].Df);
                double gamma = 1.0 - (1.0 - ci) / 2.0;
                double criticalT = Math.Abs(PDF.tfromp(gamma, df));
                double aucDifference = groups[0].AucMean - groups[1].AucMean;
                double se = Math.Sqrt(v1 + v2);
                double t = aucDifference / se;
                double p = PDF.tvalp(t, df);
                if (p > 1.0 - p)
                    p = 1.0 - p;

                groupComparisonParameters.AddOutput("t", t);
                groupComparisonParameters.AddOutput("se", se);
                groupComparisonParameters.AddOutput("df", df);
                groupComparisonParameters.AddOutput("p2", p * 2.0);
                groupComparisonParameters.AddOutput("aucDifference", aucDifference);
                groupComparisonParameters.AddOutput("aucDifferenceLcl", aucDifference - se * criticalT);
                groupComparisonParameters.AddOutput("aucDifferenceUcl", aucDifference + se * criticalT);

                // Bootstrap (if present)

                if (doBootstrap)
                {
                    int bothBoots = (int)Math.Min(groups[0].CompletedIterations, groups[1].CompletedIterations);
                    double[] tBootstraps = new double[bothBoots];
                    int k = 0;
                    for (int i = 0; i < bothBoots; i++)
                    {
                        double aucDifferenceBootstrap = aucDifference - (groups[0].AucMeans[i] - groups[1].AucMeans[i]);
                        double seBootstrap = Math.Sqrt(groups[0].VarAucMeans[i] + groups[1].VarAucMeans[i]);
                        double tBootstrap = aucDifferenceBootstrap / seBootstrap;
                        tBootstraps[i] = tBootstrap;
                        if (Math.Abs(tBootstrap) >= Math.Abs(t))
                            k++;
                    }
                    // 2-sided p-value
                    double pBootstrap = (k + 1) / (double)(bothBoots + 1);

                    Summary s = new();
                    double edge = (1.0 - ci) / 2.0;
                    s.FullSummaryFromX(tBootstraps, bothBoots, null, ci, edge * 100.0, (1.0 - edge) * 100.0, 1);
                    double tBootstrapLcl = aucDifference + s.UserCentileL * se;
                    double tBootstrapUcl = aucDifference + s.UserCentileU * se;

                    List<ParameterBag> bootstrapList = new();
                    groupComparisonParameters.AddOutput("*bootstrap", bootstrapList);
                    ParameterBag bootstrapParameters = new();
                    bootstrapList.Add(bootstrapParameters);
                    bootstrapParameters.AddOutput("pBootstrap", pBootstrap);
                    bootstrapParameters.AddOutput("iterations", bothBoots);
                    bootstrapParameters.AddOutput("tBootstrapLcl", tBootstrapLcl);
                    bootstrapParameters.AddOutput("tBootstrapUcl", tBootstrapUcl);
                }

            }

            return new StepOutput(outputParameters);
        }

        private class TimeSeriesSummaryStore
        {
            public Group Group { get; set; }
            public SortedSet<double> SortedTimes { get; set; }
            public SortedSet<double> SortedSubjectIds { get; set; }
            public double[,] Observations { get; private set; }
            public int NObservations { get; private set; }
            private double[,] AreasUnderCurve { get; set; }
            public SortedDictionary<double, TimeSummary> TimeToSummaryMap { get; private set; }
            public double[] IndexToTimeMap { get; private set; }
            public SortedDictionary<double, SubjectSummary> SubjectToSummaryMap { get; private set; }
            public double[] IndexToSubjectMap { get; private set; }
            public int AucN { get; private set; }
            public double AucSum { get; private set; }
            public double AucMean { get; private set; }
            public double AucSd { get; private set; }
            public double VarAucMean { get; private set; }
            public double Se { get; private set; }
            public double ZLclAucBar { get; private set; }
            public double ZUclAucBar { get; private set; }
            public double Df { get; private set; }
            public double CriticalT { get; private set; }
            public double TLclAucBar { get; private set; }
            public double TUclAucBar { get; private set; }
            public double MeanObservationsPerTimePoint { get; private set; }
            public double MedianAuc { get; private set; }
            public double UpperQuartileAuc { get; private set; }
            public double LowerQuartileAuc { get; private set; }
            public double MedianTimeToMax { get; private set; }
            public double UpperQuartileTimeToMax { get; private set; }
            public double LowerQuartileTimeToMax { get; private set; }
            public double MedianSlopeToMax { get; private set; }
            public double UpperQuartileSlopeToMax { get; private set; }
            public double LowerQuartileSlopeToMax { get; private set; }
            public double MeanSlopeToMax { get; set; }
            public double MeanSlopeToMaxSD { get; set; }
            // Bootstrapping
            public double TLclAucBarBootstrap { get; set; }
            public double TUclAucBarBootstrap { get; set; }
            public double CompletedIterations { get; set; }
            public double[] AucMeans { get; set; }
            public double[] VarAucMeans { get; set; }

            public TimeSeriesSummaryStore()
            {
                SortedTimes = new SortedSet<double>();
                SortedSubjectIds = new SortedSet<double>();
            }

            public int N => SortedSubjectIds.Count;

            internal void NoteRowPass1(double time, double subjectId)
            {
                SortedSubjectIds.Add(subjectId);
                SortedTimes.Add(time);
            }

            /// <summary>
            /// First pass complete; the list of time points and subject IDs is complete.  Do anything required before pass 2.
            /// </summary>
            internal void NoteEndOfPass1(bool addZeroObservationsAtZeroTime)
            {
                zeroObservationsAtZeroTime = addZeroObservationsAtZeroTime;
                // If we need to, ensure that there's space for zero time.
                if (addZeroObservationsAtZeroTime)
                    SortedTimes.Add(0);

                // Finalise any sort structures we need
                IndexToTimeMap = SortedTimes.ToArray();
                TimeToSummaryMap = new SortedDictionary<double, TimeSummary>();
                for (int i = 0; i < IndexToTimeMap.Length; i++)
                    TimeToSummaryMap.Add(IndexToTimeMap[i], new TimeSummary { Index = i, Time = IndexToTimeMap[i] });
                IndexToSubjectMap = SortedSubjectIds.ToArray();
                SubjectToSummaryMap = new SortedDictionary<double, SubjectSummary>();
                for (int i = 0; i < IndexToSubjectMap.Length; i++)
                    SubjectToSummaryMap.Add(IndexToSubjectMap[i], new SubjectSummary { Index = i, SubjectId = IndexToSubjectMap[i] });

                // Allocate our array of observations by time by subject.  First index is time point, then subject; this aids locality of reference later.
                Observations = new double[IndexToTimeMap.Length, SortedSubjectIds.Count];
                for (int time = 0; time < IndexToTimeMap.Length; time++)
                    for (int subject = 0; subject < SortedSubjectIds.Count; subject++)
                        Observations[time, subject] = Constant.MISSING;
                AreasUnderCurve = new double[IndexToTimeMap.Length, SortedSubjectIds.Count];
            }

            internal void NoteRowPass2(double time, double observation, double subjectId)
            {
                int timeIndex = TimeToSummaryMap[time].Index;
                int subjectIndex = SubjectToSummaryMap[subjectId].Index;
                if (Observations[timeIndex, subjectIndex] != Constant.MISSING)
                    throw new Exception("Your data contains multiple, non-identical observations for the same subject and time point; time series summary cannot interpret this. Please remove the duplicate(s).");
                Observations[timeIndex, subjectIndex] = observation;
                NObservations++;
            }

            private bool zeroObservationsAtZeroTime;

            /// <summary>
            /// Second pass complete. If the user asked for observations of zero at time zero, every subject without an observation there
            /// is given one (time zero was added to the time points, but the observations there had been left missing).
            /// </summary>
            internal void NoteEndOfPass2()
            {
                if (!zeroObservationsAtZeroTime || !TimeToSummaryMap.ContainsKey(0))
                    return;
                int timeIndex = TimeToSummaryMap[0].Index;
                for (int subjectIndex = 0; subjectIndex < IndexToSubjectMap.Length; subjectIndex++)
                    if (Observations[timeIndex, subjectIndex] == Constant.MISSING)
                    {
                        Observations[timeIndex, subjectIndex] = 0;
                        NObservations++;
                    }
            }

            /// <summary>
            /// 
            /// </summary>
            /// <param name="ci"></param>
            /// <param name="isBootstrap">If true, this is a calculation for bootstrapping and therefore we can elide much of the calculation.</param>
            internal void Calculate(double ci, bool isBootstrap)
            {
                // By time point, across subjects in this group
                for (int timeIndex = 0; timeIndex < IndexToTimeMap.Length; timeIndex++)
                {
                    TimeSummary summary = TimeToSummaryMap[IndexToTimeMap[timeIndex]];
                    summary.N = 0;
                    summary.Sum = 0;

                    for (int subjectIndex = 0; subjectIndex < IndexToSubjectMap.Length; subjectIndex++)
                    {
                        double observation = Observations[timeIndex, subjectIndex];
                        if (observation != Constant.MISSING)
                        {
                            summary.N++;
                            summary.Sum += observation;
                        }
                    }
                    summary.Mean = summary.N == 0 ? Constant.MISSING : summary.Sum / summary.N;
                    summary.Variance = 0;
                    if (summary.Mean == Constant.MISSING)
                        summary.Variance = Constant.MISSING;
                    else
                    {
                        for (int subjectIndex = 0; subjectIndex < IndexToSubjectMap.Length; subjectIndex++)
                        {
                            double observation = Observations[timeIndex, subjectIndex];
                            if (observation != Constant.MISSING)
                                summary.Variance += (observation - summary.Mean) * (observation - summary.Mean);
                        }
                        summary.Variance /= summary.N - 1; // Sample variance
                    }
                    summary.Sd = summary.Variance == Constant.MISSING ? Constant.MISSING : Math.Sqrt(summary.Variance);
                    summary.Se = summary.Sd == Constant.MISSING ? Constant.MISSING : summary.Sd / Math.Sqrt(summary.N);

                    int weightLowerIndex = Math.Max(0, timeIndex - 1);
                    int weightUpperIndex = Math.Min(IndexToTimeMap.Length - 1, timeIndex + 1);
                    summary.Weight = (IndexToTimeMap[weightUpperIndex] - IndexToTimeMap[weightLowerIndex]) / 2.0;
                    summary.MeanTimesWeight = summary.Mean * summary.Weight;
                    for (int subjectIndex = 0; subjectIndex < IndexToSubjectMap.Length; subjectIndex++)
                        AreasUnderCurve[timeIndex, subjectIndex] = summary.Weight == Constant.MISSING || Observations[timeIndex, subjectIndex] == Constant.MISSING ? Constant.MISSING : summary.Weight * Observations[timeIndex, subjectIndex];

                    if (!isBootstrap)
                    {
                        double[] values = new double[IndexToSubjectMap.Length];
                        for (int subjectIndex = 0; subjectIndex < IndexToSubjectMap.Length; subjectIndex++)
                            values[subjectIndex] = Observations[timeIndex, subjectIndex];

                        Summary sx = new();
                        sx.FullSummaryFromX(values, values.Length, null, ci, 5, 95, 1); // 1-based data array
                        summary.UpperQuartile = sx.UpperQuartile;
                        summary.Median = sx.Median;
                        summary.LowerQuartile = sx.LowerQuartile;
                        summary.InterquartileRange = sx.InterquartileRange;
                    }
                }

                // By subject, areas under curve etc.
                AucN = 0;
                AucSum = 0;
                for (int subjectIndex = 0; subjectIndex < IndexToSubjectMap.Length; subjectIndex++)
                {
                    SubjectSummary summary = SubjectToSummaryMap[IndexToSubjectMap[subjectIndex]];
                    // The trapezium rule over the observations the subject has. Summing each time's slice (the observation
                    // times half the gap between its neighbours) left the whole slice of a missing observation out, which
                    // underestimated the area; joining the neighbours across the gap is the usual rule and gives the same
                    // area when nothing is missing.
                    summary.Auc = 0;
                    double lastTime = Constant.MISSING;
                    double lastObservation = Constant.MISSING;
                    for (int timeIndex = 0; timeIndex < IndexToTimeMap.Length; timeIndex++)
                    {
                        double observation = Observations[timeIndex, subjectIndex];
                        if (observation == Constant.MISSING)
                            continue;
                        if (lastObservation != Constant.MISSING)
                            summary.Auc += (IndexToTimeMap[timeIndex] - lastTime) * (observation + lastObservation) / 2.0;
                        lastTime = IndexToTimeMap[timeIndex];
                        lastObservation = observation;
                    }
                    AucN++;
                    AucSum += summary.Auc;

                    if (!isBootstrap)
                    {
                        summary.Baseline = Observations[0, subjectIndex];
                        summary.MinObservation = double.MaxValue;
                        summary.MaxObservation = double.MinValue;
                        int maxIndex = -1;
                        for (int timeIndex = 0; timeIndex < IndexToTimeMap.Length; timeIndex++)
                        {
                            // a missing observation was taken as the minimum, so "*" was printed for it
                            if (Observations[timeIndex, subjectIndex] == Constant.MISSING)
                                continue;
                            summary.MinObservation = Math.Min(summary.MinObservation, Observations[timeIndex, subjectIndex]);
                            if (Observations[timeIndex, subjectIndex] > summary.MaxObservation)
                            {
                                summary.MaxObservation = Observations[timeIndex, subjectIndex];
                                summary.TimeToMax = IndexToTimeMap[timeIndex];
                                maxIndex = timeIndex;
                            }
                        }

                        // If we have a max, get the slope
                        if (maxIndex > -1)
                        {
                            double[] observations = new double[maxIndex + 1];
                            for (int timeIndex = 0; timeIndex <= maxIndex; timeIndex++)
                                observations[timeIndex] = Observations[timeIndex, subjectIndex];
                            SimpleLinearRegressionContext context = GetProcessedContext(observations, IndexToTimeMap, maxIndex + 1);
                            summary.SlopeToMax = context.Slope;
                            summary.SlopeToMaxVariance = context.SeEst * context.SeEst;
                        }
                    }
                }

                // Precision of the mean AUC from the subjects' AUCs (Bland 2000): SD across subjects, SE = SD / sqrt(n), n - 1 degrees of freedom
                AucMean = AucN == 0 || AucSum == Constant.MISSING ? Constant.MISSING : AucSum / AucN;
                double aucSumOfSquares = 0;
                for (int subjectIndex = 0; subjectIndex < IndexToSubjectMap.Length; subjectIndex++)
                {
                    double deviation = SubjectToSummaryMap[IndexToSubjectMap[subjectIndex]].Auc - AucMean;
                    aucSumOfSquares += deviation * deviation;
                }
                AucSd = AucN < 2 || AucMean == Constant.MISSING ? Constant.MISSING : Math.Sqrt(aucSumOfSquares / (AucN - 1));
                VarAucMean = AucSd == Constant.MISSING ? Constant.MISSING : AucSd * AucSd / AucN;
                Se = AucSd == Constant.MISSING ? Constant.MISSING : AucSd / Math.Sqrt(AucN);
                Df = AucN - 1;
                if (!isBootstrap)
                {
                    double gamma = 1.0 - (1.0 - ci) / 2.0;
                    CriticalT = Math.Abs(PDF.tfromp(gamma, Df));
                    double td = Se * CriticalT;
                    TLclAucBar = AucMean - td;
                    TUclAucBar = AucMean + td;
                    double invGamma = PDF.gauinv(gamma);
                    double zd = Se * invGamma;
                    ZLclAucBar = AucMean - zd;
                    ZUclAucBar = AucMean + zd;
                    MeanObservationsPerTimePoint = NObservations / (double)IndexToTimeMap.Length;

                    // AUC, time to max and slope to max medians and IQRs
                    double[] aucs = new double[IndexToSubjectMap.Length];
                    double[] timesToMax = new double[IndexToSubjectMap.Length];
                    double[] slopesToMax = new double[IndexToSubjectMap.Length];
                    for (int subjectIndex = 0; subjectIndex < IndexToSubjectMap.Length; subjectIndex++)
                    {
                        SubjectSummary ss = SubjectToSummaryMap[IndexToSubjectMap[subjectIndex]];
                        aucs[subjectIndex] = ss.Auc;
                        timesToMax[subjectIndex] = ss.TimeToMax;
                        slopesToMax[subjectIndex] = ss.SlopeToMax;
                        // double weight = 1.0 / ss.SlopeToMaxVariance;
                    }

                    Summary sAuc = new();
                    sAuc.FullSummaryFromX(aucs, aucs.Length, null, ci, 5, 95, 1);
                    UpperQuartileAuc = sAuc.UpperQuartile;
                    MedianAuc = sAuc.Median;
                    LowerQuartileAuc = sAuc.LowerQuartile;

                    Summary sTimeToMax = new();
                    sTimeToMax.FullSummaryFromX(timesToMax, timesToMax.Length, null, ci, 5, 95, 1);
                    UpperQuartileTimeToMax = sTimeToMax.UpperQuartile;
                    MedianTimeToMax = sTimeToMax.Median;
                    LowerQuartileTimeToMax = sTimeToMax.LowerQuartile;

                    Summary sSlopeToMax = new();
                    sSlopeToMax.FullSummaryFromX(slopesToMax, slopesToMax.Length, null, ci, 5, 95, 1);
                    UpperQuartileSlopeToMax = sSlopeToMax.UpperQuartile;
                    MedianSlopeToMax = sSlopeToMax.Median;
                    LowerQuartileSlopeToMax = sSlopeToMax.LowerQuartile;
                    MeanSlopeToMax = sSlopeToMax.Mean;
                    MeanSlopeToMaxSD = sSlopeToMax.SD;
                }
            }

            private static SimpleLinearRegressionContext GetProcessedContext(double[] y, double[] x, int length)
            {
                DoubleArraysAndBooleans copiesRemovingMissingRows = Numerics.Utilities.RemoveMissingRows(new[] { y, x }, 0, length, 0);
                SimpleLinearRegressionContext context = new(copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[1], copiesRemovingMissingRows.ArraysWithMissingRowsRemoved[0], string.Empty, string.Empty);
                context.CalculateLeastSquaresMethod();
                return context;
            }
        }

        private class BootstrappingTimeSeriesSummaryStore
        {
            private readonly TimeSeriesSummaryStore original;
            private TimeSeriesSummaryStore resampled;
            public int CompletedIterations { get; private set; }
            public double TLcl { get; private set; }
            public double TUcl { get; private set; }
            public double[] AucMeans { get; private set; }
            public double[] VarAucMeans { get; private set; }

            public BootstrappingTimeSeriesSummaryStore(TimeSeriesSummaryStore original)
            {
                this.original = original;
            }

            public void Bootstrap(IProgressBarHost host, int iterations, MersenneTwister mt, double ci, bool keepAucs)
            {
                if (keepAucs)
                {
                    AucMeans = new double[iterations];
                    VarAucMeans = new double[iterations];
                }

                CompletedIterations = iterations; // Will be overwritten if we abandon partway.
                resampled = new TimeSeriesSummaryStore { Group = original.Group, SortedTimes = original.SortedTimes, SortedSubjectIds = original.SortedSubjectIds };
                resampled.NoteEndOfPass1(false);
                double[] tValues = new double[iterations];
                using IProgressBar progress = host.StartProgress("Bootstrapping " + original.Group.Label, true);
                for (int iteration = 0; iteration < iterations; iteration++)
                {
                    Shuffle(mt, original.Observations, resampled.Observations);
                    resampled.Calculate(ci, true);
                    double aucDifference = original.AucMean - resampled.AucMean;
                    double t = aucDifference / resampled.Se;
                    if (keepAucs)
                    {
                        AucMeans[iteration] = resampled.AucMean;
                        VarAucMeans[iteration] = resampled.VarAucMean;
                    }
                    tValues[iteration] = t;
                    if (iteration % 5000 == 0)
                    {
                        if (progress.Update(iteration / (double)iterations))
                        {
                            // Abandon
                            CompletedIterations = iteration;
                            break;
                        }
                    }
                }
                // If we got here, we either completed fully or completedIterations will be set for the partial completion.
                Summary s = new();
                double edge = (1.0 - ci) / 2.0;
                s.FullSummaryFromX(tValues, CompletedIterations, null, ci, edge * 100.0, (1.0 - edge) * 100.0, 1);
                TLcl = s.UserCentileL;
                TUcl = s.UserCentileU;
            }

            /// <summary>
            /// Resample whole subjects (their observations at every time point) from input into output, with replacement.
            /// </summary>
            private static void Shuffle(MersenneTwister mt, double[,] input, double[,] output)
            {
                int tub = input.GetUpperBound(0);
                int sub = input.GetUpperBound(1);
                for (int subjectIndex = 0; subjectIndex <= sub; subjectIndex++)
                {
                    int drawn = (int)Math.Floor((sub + 1) * mt.NextDouble());
                    for (int timeIndex = 0; timeIndex <= tub; timeIndex++)
                        output[timeIndex, subjectIndex] = input[timeIndex, drawn];
                }
            }
        }
    }
}
