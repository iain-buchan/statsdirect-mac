namespace StatsDirect.Creole
{
    public class CreoleText<TResult> : ICreole<TResult>
    {
        public string Text { get; set; }

        TResult ICreole<TResult>.Accept(ICreoleVisitor<TResult> visitor)
        {
            return visitor.Visit(this);
        }
    }
}
