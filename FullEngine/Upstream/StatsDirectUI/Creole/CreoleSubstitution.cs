namespace StatsDirect.Creole
{
    public class CreoleSubstitution<TResult> : ICreole<TResult>
    {
        public string Path { get; set; }
        public string Format { get; set; }

        TResult ICreole<TResult>.Accept(ICreoleVisitor<TResult> visitor)
        {
            return visitor.Visit(this);
        }
    }
}
