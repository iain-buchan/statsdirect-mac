namespace StatsDirect.Creole
{
    public class CreoleInclude<TResult> : ICreole<TResult>
    {
        public string Source { get; set; }

        TResult ICreole<TResult>.Accept(ICreoleVisitor<TResult> visitor)
        {
            return visitor.Visit(this);
        }
    }
}
