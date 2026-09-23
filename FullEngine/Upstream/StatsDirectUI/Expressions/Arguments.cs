using System.Collections.Generic;

namespace StatsDirect.Expressions
{
    /// <summary>
    /// A wrapper for List&lt;Argument> as Antlr doesn't appreciate some of the metacharacters being used in its definitions.
    /// </summary>
    public class Arguments : List<Argument>
    {
        public Arguments()
        {
        }

        public Arguments(Argument toAdd)
        {
            Add(toAdd);
        }
    }
}
