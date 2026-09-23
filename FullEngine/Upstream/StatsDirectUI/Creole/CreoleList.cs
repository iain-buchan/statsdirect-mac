using System.Collections.Generic;

namespace StatsDirect.Creole
{
    public class CreoleList<TResult> : List<ICreole<TResult>>, ICreole<TResult>
    {
        public CreoleList(IEnumerable<ICreole<TResult>> victims)
            : base(victims)
        {
        }

        TResult ICreole<TResult>.Accept(ICreoleVisitor<TResult> visitor)
        {
            return visitor.Visit(this);
        }
    }
}
