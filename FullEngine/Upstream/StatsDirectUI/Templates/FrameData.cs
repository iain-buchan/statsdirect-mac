using StatsDirect.CsvParser;
using StatsDirect.Data;
using StatsDirect.Numerics;
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Xml.Serialization;

namespace StatsDirect.Templates
{
    public class FrameData
    {
        [XmlAttribute("type")]
        public string MimeType { get; set; }
        private string rawData;
        private DataFrame frame;

        [XmlText]
        public string DataForXml
        {
            get
            {
                if (null != rawData)
                    return rawData;
                return ToXmlData();
            }
            set
            {
                frame = null;
                rawData = value;
            }
        }

        private string ToXmlData()
        {
            throw new NotImplementedException();
        }

        [XmlIgnore]
        public DataFrame Frame
        {
            get
            {
                if (null == frame)
                {
                    frame = ParseToFrame(rawData);
                    rawData = null;
                }
                return frame;
            }
            set
            {
                frame = value;
                rawData = null;
            }
        }

        public static DataFrame ParseToFrame(string rawData)
        {
            // Assumes NumericReplaceMissing.  TODO: Fix this!
            List<List<string>> strings = CsvReader.Read(new StringReader(rawData));
            DataFrame outputFrame = new();
            int row = 0;
            // Skip blank rows at the top - deliberate so that someone can have a CDATA section with the header row on the next line.
            while (strings[row].Count == 0 || strings[row].Count == 1 && string.IsNullOrWhiteSpace(strings[row][0]))
                row++;

            // Read the header row and create variables.
            foreach (string s in strings[row])
                outputFrame.Variables.Add(new DoubleVariable(strings.Count - 1 /* for the header row */ - row /* for leading blanks */, s.Trim()));
            int columns = outputFrame.VariableCount;
            row++;

            // Read the remaining rows.  Again, skip entirely blank rows.
            int outputRow = 0;
            while (row < strings.Count)
            {
                List<string> l = strings[row];
                if (l.Count > 0 && !(l.Count == 1 && string.IsNullOrWhiteSpace(l[0])))
                {
                    for (int column = 0; column < Math.Min(l.Count, columns); column++)
                    {
                        if (!double.TryParse(l[column], NumberStyles.Float, CultureInfo.InvariantCulture, out double value))
                            value = Constant.MISSING;
                        ((DoubleVariable)outputFrame.Variables[column]).Data[outputRow] = value;
                    }
                    outputRow++;
                }
                row++;
            }
            // Lose the extra space for any blank rows
            for (int column = 0; column < columns; column++)
                outputFrame.Variables[column].TruncateDataToLength(outputRow);

            // Done
            return outputFrame;
        }
    }
}
