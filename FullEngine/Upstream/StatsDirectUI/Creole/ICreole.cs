namespace StatsDirect.Creole
{
    public interface ICreole<TResult>
    {
        TResult Accept(ICreoleVisitor<TResult> visitor);
    }
}
