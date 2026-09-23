namespace StatsDirect.Creole
{
    public abstract class CreoleContainer<TResult>
    {
        public ICreole<TResult> Contents { get; set; }
    }
}
