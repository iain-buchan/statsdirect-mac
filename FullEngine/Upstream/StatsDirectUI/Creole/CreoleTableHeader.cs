namespace StatsDirect.Creole
{
    public class CreoleTableHeader<TResult> : CreoleContainer<TResult>, ICreole<TResult>
    {
        public int Colspan { get; set; }

        TResult ICreole<TResult>.Accept(ICreoleVisitor<TResult> visitor)
        {
            return visitor.Visit(this);
        }
    }
}
