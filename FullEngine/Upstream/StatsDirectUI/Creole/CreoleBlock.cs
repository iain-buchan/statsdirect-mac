namespace StatsDirect.Creole
{
    public class CreoleBlock<TResult> : CreoleContainer<TResult>, ICreole<TResult>
    {
        public string Name { get; set; }
        public string Separator { get; set; } = string.Empty;

        TResult ICreole<TResult>.Accept(ICreoleVisitor<TResult> visitor)
        {
            return visitor.Visit(this);
        }
    }
}
