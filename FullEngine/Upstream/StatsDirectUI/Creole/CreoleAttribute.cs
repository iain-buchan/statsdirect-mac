namespace StatsDirect.Creole
{
    public class CreoleAttribute<TResult> : ICreole<TResult>
    {
        public string Name { get; set; }
        public string Value { get; set; }

        TResult ICreole<TResult>.Accept(ICreoleVisitor<TResult> visitor)
        {
            return visitor.Visit(this);
        }
    }
}
