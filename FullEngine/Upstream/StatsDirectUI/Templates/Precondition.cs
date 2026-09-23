using System.Xml.Serialization;

namespace StatsDirect.Templates
{
    public class Precondition
    {
        [XmlElement("condition")]
        public Expression Condition { get; set; }

        [XmlElement("failure-message")]
        public string FailureMessage { get; set; }

        /// <summary>
        /// Check this Precondition.
        /// </summary>
        /// <returns>true if there is no body or the body evaluates to a true bool, false if the body evaluates to a non-bool or false.</returns>
        public bool Check(ITemplateProcessor processor, ParameterBag parameters)
        {
            if (Condition?.Body == null)
                return true;
            object o = processor.Evaluate(Condition, parameters);
            if (o is bool)
                return (bool)o;
            return false;
        }
    }
}
