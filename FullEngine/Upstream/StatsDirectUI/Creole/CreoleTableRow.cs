namespace StatsDirect.Creole
{
    public class CreoleTableRow<TResult> : CreoleContainer<TResult>, ICreole<TResult>
    {
        TResult ICreole<TResult>.Accept(ICreoleVisitor<TResult> visitor)
        {
            return visitor.Visit(this);
        }
    }
}
