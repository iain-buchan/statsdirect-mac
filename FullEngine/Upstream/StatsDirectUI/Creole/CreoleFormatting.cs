namespace StatsDirect.Creole
{
    public class CreoleFormatting<TResult> : CreoleContainer<TResult>, ICreole<TResult>
    {
        public string Format { get; set; }

        TResult ICreole<TResult>.Accept(ICreoleVisitor<TResult> visitor)
        {
            return visitor.Visit(this);
        }
    }
}
