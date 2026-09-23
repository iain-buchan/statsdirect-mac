namespace StatsDirect.Creole
{
    public class CreoleLineBreak<TResult> : ICreole<TResult>
    {
        TResult ICreole<TResult>.Accept(ICreoleVisitor<TResult> visitor)
        {
            return visitor.Visit(this);
        }
    }
}
