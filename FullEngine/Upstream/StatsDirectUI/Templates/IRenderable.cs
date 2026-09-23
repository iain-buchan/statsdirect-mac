namespace StatsDirect.Templates
{
    /// <summary>
    /// Something that could be rendered into a viewable form, for example a chart or a template+its contents.
    /// </summary>
    public interface IRenderable
    {
        void Accept(IRenderableVisitor visitor);
    }
}
