namespace StatsDirect.Creole
{
    public class CreoleEntity<TResult> : ICreole<TResult>
    {
        public char Value { get; set; }

        TResult ICreole<TResult>.Accept(ICreoleVisitor<TResult> visitor)
        {
            return visitor.Visit(this);
        }
    }
}
