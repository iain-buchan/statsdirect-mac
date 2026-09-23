using System;

namespace StatsDirect.Data
{
    ///  <summary>
    ///  Represents a single variant variable/factor/column/field.
    ///  </summary>
    [Serializable]
    public sealed class VariantVariable : GenericVariable<object>
    {
        public VariantVariable()
        {
        }

        public VariantVariable(object[] data)
            : base(data)
        {
        }

        public VariantVariable(object[] data, string title)
            : base(data, title)
        {
        }

        public VariantVariable(int length, string title)
            : base(length, title)
        {
        }

        public override void Accept(IVariableVisitor visitor)
        {
            visitor.Visit(this);
        }
    }
}
