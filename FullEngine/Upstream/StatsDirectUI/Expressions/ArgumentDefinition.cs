namespace StatsDirect.Expressions
{
    public class ArgumentDefinition
    {
        public string Name { get; }
        public bool IsOptional { get; }
        public string Default { get; }
        public DataType DataType { get; }

        public ArgumentDefinition(string name, DataType dataType, bool isOptional = false, string parameterDefault = null)
        {
            Name = name;
            DataType = dataType;
            IsOptional = isOptional;
            Default = parameterDefault;
        }

        public override string ToString()
        {
            // Mandatory parameters only show their name.
            if (!IsOptional)
                return Name;

            // Optional parameters show different strings depending on whether or not they have a default.
            if (null != Default)
                return $"{Name}:={Default} (default)";
            return Name + " (optional)";
        }
    }
}
