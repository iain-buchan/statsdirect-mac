using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;
using StatsDirect.Data;
using StatsDirect.Numerics;
using StatsDirect.Templates;

namespace StatsDirect.R
{
    public static class RConvert
    {
        public static string ToRVariableName(string rawVariableName)
        {
            StringBuilder sb = new();
            ToRName(sb, rawVariableName);
            return sb.ToString();
        }

        public static void ToRName(StringBuilder sb, string rawVariableName)
        {
            string[] reservedWords = { "if", "else", "repeat", "while", "function", "for", "in", "next", "break", "TRUE", "FALSE", "NULL", "Inf", "NaN", "NA", "NA_integer_", "NA_real_", "NA_complex_", "NA_character_" };
            List<string> rw = new(reservedWords);
            string lowerName = rawVariableName.ToLower(CultureInfo.InvariantCulture);
            if (rw.Contains(lowerName))
            {
                sb.Append('.');
                sb.Append(lowerName);
            }
            else
            {
                // Detect probable illegal starts to names and fix them by prefixing a dot
                if (lowerName[0] < 'a' || lowerName[0] > 'z')
                    sb.Append(".");
                if (lowerName[0] >= '0' && lowerName[0] <= '9')
                    sb.Append("."); // A second dot otherwise we run the danger of a name of the form .2way, which is illegal.
                foreach (char ch in lowerName)
                {
                    if (ch >= 'a' && ch <= 'z' || ch >= '0' && ch <= '9' || ch == '.' || ch == '_')
                        sb.Append(ch);
                    else
                        sb.Append('.');
                }
            }
        }

        public static void ToR(StringBuilder sb, string name, FilledParameter filledParameter, FrameType frameTypePreference)
        {
            if (null == filledParameter || !filledParameter.HasData)
            {
                sb.Append("NULL");
                return;
            }

            if (filledParameter.IsDataFrame)
            {
                DataFrame frame = filledParameter.AsDataFrame;
                ToR(sb, name, frame, frameTypePreference);
            }
            else
            {
                ToRName(sb, name);
                sb.Append(" <- ");
                if (filledParameter.IsString)
                    ToR(sb, filledParameter.AsString);
                else if (filledParameter.IsDouble)
                    ToR(sb, filledParameter.AsDouble);
                else if (filledParameter.IsInt32)
                    ToR(sb, filledParameter.AsInt32);
                else if (filledParameter.IsBoolean)
                    ToR(sb, filledParameter.AsBoolean);
            }
            sb.AppendLine();
        }

        public static void ToR(StringBuilder sb, string frameName, DataFrame frame, FrameType frameTypePreference)
        {
            List<string> variableNames = new();
            List<string> columnNames = new();
            foreach (IVariable variable in frame.Variables)
            {
                StringBuilder nameBuilder = new();
                ToRName(nameBuilder, variable.Title);
                string variableName = nameBuilder.ToString();
                sb.Append(variableName);
                sb.Append(" <- ");
                ToR(sb, variable);
                sb.AppendLine();
                variableNames.Add(variableName);
                columnNames.Add(variable.Title);
            }

            switch (frameTypePreference)
            { 
                case FrameType.Wide:
                    ToRName(sb, frameName);
                    sb.Append(" <- data.frame(");
                    sb.Append(string.Join(", ", variableNames.ToArray()));
                    sb.AppendLine(")");
                    sb.Append("colnames(");
                    ToRName(sb, frameName);
                    sb.Append(") <- c(");
                    sb.Append(string.Join(", ", columnNames.Select(RQuote).ToArray()));
                    sb.Append(")");
                    break;
                case FrameType.Long:
                    ToRName(sb, frameName);
                    sb.AppendLine(" <- data.frame(");
                    sb.Append("\tdata=c(");
                    sb.Append(string.Join(", ", variableNames.ToArray()));
                    sb.AppendLine("),");
                    sb.Append("\tgroups=factor(rep(c(");
                    sb.Append(string.Join(", ", columnNames.Select(RQuote).ToArray()));
                    sb.Append("), times=c(");
                    sb.Append(string.Join(", ", variableNames.Select(variableName => "length(" + variableName + ")").ToArray()));
                    sb.AppendLine(")))");
                    sb.AppendLine("\t)");
                    break;
                default:
                    throw new ArgumentOutOfRangeException(nameof(frameTypePreference), frameTypePreference, "Only Long or Wide known when converting StatsDirect frame to R frame");
            }
        }

        /// <summary>
        /// Return unquoted in such a way that it is guaranteed to be an acceptable string to the R parser.  This surrounds the string with double-quotes and escapes any \ or " in the string with a backslash (doubling the quote, as was done before, is not valid R).
        /// </summary>
        private static string RQuote(string unquoted)
        {
            return "\"" + unquoted.Replace("\\", "\\\\").Replace("\"", "\\\"") + "\"";
        }

        private class ToRVariableVisitor : IVariableVisitor
        {
            public StringBuilder Sb { get; set; }

            public void Visit(GenericVariable<bool> variable)
            {
                bool[] data = variable.Data;
                Sb.Append("c(");
                bool first = true;
                foreach (bool value in data)
                {
                    if (first)
                        first = false;
                    else
                        Sb.Append(",");
                    ToR(Sb, value);
                }
                Sb.Append(")");
            }

            public void Visit(DoubleVariable variable)
            {
                double[] data = variable.Data;
                Sb.Append("c(");
                bool first = true;
                foreach (double value in data)
                {
                    if (first)
                        first = false;
                    else
                        Sb.Append(",");
                    ToR(Sb, value);
                }
                Sb.Append(")");
            }

            public void Visit(GenericVariable<object> variable)
            {
                object[] data = variable.Data;
                Sb.Append("c(");
                bool first = true;
                foreach (object value in data)
                {
                    if (first)
                        first = false;
                    else
                        Sb.Append(",");
                    ToR(Sb, value);
                }
                Sb.Append(")");
            }

            public void Visit(StringVariable variable)
            {
                string[] data = variable.Data;
                Sb.Append("c(");
                bool first = true;
                foreach (string value in data)
                {
                    if (first)
                        first = false;
                    else
                        Sb.Append(",");
                    ToR(Sb, value);
                }
                Sb.Append(")");
            }

            public void Visit(GenericVariable<DateTime> variable)
            {
                DateTime[] data = variable.Data;
                Sb.Append("c(");
                bool first = true;
                foreach (DateTime value in data)
                {
                    if (first)
                        first = false;
                    else
                        Sb.Append(",");
                    ToR(Sb, value);
                }
                Sb.Append(")");
            }

            public void Visit(ClassifierVariable variable)
            {
                double[] data = variable.Data;
                Sb.Append("c(");
                bool first = true;
                foreach (double value in data)
                {
                    if (first)
                        first = false;
                    else
                        Sb.Append(",");
                    ToR(Sb, variable.Groups[(int)value].Label);
                }
                Sb.Append(")");
            }
        }

        public static void ToR(StringBuilder sb, IVariable variable)
        {
            variable.Accept(new ToRVariableVisitor { Sb = sb });
        }

        public static void ToR(StringBuilder sb, object value)
        {
            if (null == value)
                sb.Append("NA");
            else if (value is double)
                ToR(sb, (double)value);
            else if (value is string)
                ToR(sb, (string)value);
            else if (value is int)
                ToR(sb, (int)value);
            else if (value is bool)
                ToR(sb, (bool)value);
            else if (value is DateTime)
                ToR(sb, (DateTime)value);
        }

        public static void ToR(StringBuilder sb, double value)
        {
            sb.Append(Constant.MISSING == value ? "NA" : value.ToString("R", CultureInfo.InvariantCulture));
        }

        public static void ToR(StringBuilder sb, DateTime value)
        {
            sb.Append("as.Date(\"");
            sb.Append(value.ToString("yyyy-MM-dd hh:mm:ss"));
            sb.Append(")");
        }

        public static void ToR(StringBuilder sb, int value)
        {
            sb.Append(value.ToString(CultureInfo.InvariantCulture));
        }

        public static void ToR(StringBuilder sb, string value)
        {
            sb.Append('"');
            sb.Append(value.Replace("\"", "\\\""));
            sb.Append('"');
        }

        public static void ToR(StringBuilder sb, bool value)
        {
            sb.Append(value ? "TRUE" : "FALSE");
        }

        internal static DataFrame ToFrame(string frameName, string variableName, List<object> data)
        {
            // Check types: use double if all numeric, else (for now) string.  TODO: Other types.
            // R's NA arrives as null and is a missing value; a whole number arrives as an int.  Neither used to be allowed for: an NA threw a
            // NullReferenceException and one whole number among the values turned the whole column into text.
            bool allNumeric = data.All(o => o is null || o is double || o is int);
            IVariable v;
            if (allNumeric)
            {
                DoubleVariable dv = new(data.Count, variableName);
                for (int i = 0; i < data.Count; i++)
                    dv.Data[i] = data[i] is null ? Constant.MISSING : Convert.ToDouble(data[i], CultureInfo.InvariantCulture);
                v = dv;
            }
            else
            {
                StringVariable dv = new(data.Count, variableName);
                for (int i = 0; i < data.Count; i++)
                    dv.Data[i] = data[i]?.ToString() ?? string.Empty;
                v = dv;
            }
            return new DataFrame(v, frameName);
        }
    }
}
