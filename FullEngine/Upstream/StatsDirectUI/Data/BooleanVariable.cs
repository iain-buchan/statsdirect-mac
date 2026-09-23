using System;

namespace StatsDirect.Data
{
    [Serializable]
    public class BooleanVariable : GenericVariable<bool>
    {
        public BooleanVariable()
        {
        }

        public BooleanVariable(bool[] data)
            : base(data)
        {
        }

        public BooleanVariable(bool[] data, string title)
            : base(data, title)
        {
        }

        public BooleanVariable(int length, string title)
            : base(length, title)
        {
        }

        public override void Accept(IVariableVisitor visitor)
        {
            visitor.Visit(this);
        }
    }
}
