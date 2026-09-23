using System;

namespace StatsDirect.Data
{
    [Serializable]
    public sealed class StringVariable : GenericVariable<string>
    {
        public StringVariable()
        {
        }

        public StringVariable(string[] data)
            : base(data)
        {
        }

        public StringVariable(string[] data, string title)
            : base(data, title)
        {
        }

        public StringVariable(int length, string title)
            : base(length, title)
        {
        }

        public override void Accept(IVariableVisitor visitor)
        {
            visitor.Visit(this);
        }
    }
}
