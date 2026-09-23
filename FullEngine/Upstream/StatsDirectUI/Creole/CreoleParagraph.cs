namespace StatsDirect.Creole
{
    public class CreoleParagraph<TResult> : CreoleContainer<TResult>, ICreole<TResult>
    {
        TResult ICreole<TResult>.Accept(ICreoleVisitor<TResult> visitor)
        {
            return visitor.Visit(this);
        }
    }
}
