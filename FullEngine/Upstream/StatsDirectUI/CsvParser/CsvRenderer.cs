using System.Collections.Generic;
using System.Text;

namespace StatsDirect.CsvParser
{
    public class CsvRenderer
    {
        readonly StringBuilder sb = new();

        public string Render(IList<string> header, IList<IList<string>> rows)
        {
            RenderRow(header);
            foreach (var row in rows)
                RenderRow(row);
            return sb.ToString();
        }

        /// <summary>
        /// Render a single-column CSV - convenience function to avoid having to wrap single variables.
        /// </summary>
        /// <param name="header"></param>
        /// <param name="rows"></param>
        /// <returns></returns>
        public string Render(string header, IList<string> rows)
        {
            RenderCell(header);
            sb.AppendLine();
            foreach (string row in rows)
            {
                RenderCell(row);
                sb.AppendLine();
            }
            return sb.ToString();
        }

        private void RenderRow(IList<string> cells)
        {
            bool first = true;
            foreach (string cell in cells)
            {
                if (first)
                    first = false;
                else
                    sb.Append(',');
                RenderCell(cell);
            }
            sb.AppendLine();
        }

        private void RenderCell(string cell)
        {
            bool shouldQuote = (cell.Contains("\"") || cell.Contains("\n"));
            if (shouldQuote)
                sb.Append('"');
            sb.Append(shouldQuote ? cell.Replace("\"", "\"\"") : cell);
            if (shouldQuote)
                sb.Append('"');
        }
    }
}
