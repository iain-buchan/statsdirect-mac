namespace StatsDirect.Creole
{
    public interface ICreoleVisitor<TResult>
    {
        TResult Visit(CreoleAttribute<TResult> victim);
        TResult Visit(CreoleAttributes<TResult> victim);
        TResult Visit(CreoleBlock<TResult> victim);
        TResult Visit(CreoleEntity<TResult> victim);
        TResult Visit(CreoleFormatting<TResult> victim);
        TResult Visit(CreoleInclude<TResult> victim);
        TResult Visit(CreoleLineBreak<TResult> victim);
        TResult Visit(CreoleList<TResult> victim);
        TResult Visit(CreoleParagraph<TResult> victim);
        TResult Visit(CreoleSubstitution<TResult> victim);
        TResult Visit(CreoleTable<TResult> victim);
        TResult Visit(CreoleTableRow<TResult> victim);
        TResult Visit(CreoleTableDetail<TResult> victim);
        TResult Visit(CreoleTableHeader<TResult> victim);
        TResult Visit(CreoleText<TResult> victim);
    }
}