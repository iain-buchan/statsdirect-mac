namespace StatsDirect.Expressions
{
    public partial class StatsDirectExpressionLexer
    {
        public enum SeparatorStructure
        {
            CommaDot,
            DotComma,
            SpaceDot
        }

        public SeparatorStructure Separators { get; set; }
    }
}
