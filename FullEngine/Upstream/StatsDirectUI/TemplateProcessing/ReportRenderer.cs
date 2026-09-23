using System.IO;
using System.Text;
using StatsDirect.Templates;
using StatsDirect.Configuration;

namespace StatsDirect.TemplateProcessing
{
    public abstract class ReportRenderer
    {
        public static string GetContent(string name)
        {
            string path = Path.Combine(SDConfiguration.TemplatePath, name);
            using TextReader tr = new StreamReader(path, Encoding.ASCII);
            return tr.ReadToEnd();
        }

        public abstract string Render(/* TODO: IPreferences */ ITemplateHost host, string content, ParameterBag substitutions);
    }
}
