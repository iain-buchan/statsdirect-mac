using System.Collections.Generic;

namespace StatsDirect.Creole
{
    public class CreoleAttributes<TResult> : ICreole<TResult>
    {
        public IDictionary<string, CreoleAttribute<TResult>> Attributes { get; }

        public CreoleAttributes(IDictionary<string, CreoleAttribute<TResult>> attributes)
        {
            Attributes = attributes;
        }

        TResult ICreole<TResult>.Accept(ICreoleVisitor<TResult> visitor)
        {
            return visitor.Visit(this);
        }
    }
}
