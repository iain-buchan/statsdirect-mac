using StatsDirect.Templates;

namespace StatsDirect.Builtins
{
    /// <summary>
    /// A marker class to be passed through ITemplateHost.Amend
    /// </summary>
    public sealed class GraphicsOptions : IFillable
    {
        public string FillerToUse => "GraphicsOptions";
    }
}
