namespace StatsDirect.Data
{
    ///  <summary>
    ///  The available origin types.
    ///  </summary>
    public enum OriginType
    {
        Worksheet
    }

    public interface IOrigin 
    { 
        ///  <summary>
        ///  Returns the type of this Origin.
        ///  </summary>
        ///  <value></value>
        ///  <returns>The type of this origin, for use in a Select Case or switch() statement for downcasting</returns>
        ///  <remarks></remarks>
        OriginType Type { get; }

        /// <summary>
        /// Where multiple items (for example, multiple variables in the same frame) were requested at the same time, they should have the same OriginGroup; where they were requested at different times, they should have different origin groups.  TakeANumber is one way of handing out these values.
        /// </summary>
        int OriginGroup { get; }
    } 
} 
