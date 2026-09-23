using System;
namespace StatsDirect.Data
{
    [Serializable]
    public sealed class DateVariable : GenericVariable<DateTime>
    {
        public DateVariable()
        {
        }

        public DateVariable(DateTime[] data)
            : base(data)
        {
        }

        public DateVariable(DateTime[] data, string title)
            : base(data, title)
        {
        }

        public DateVariable(int length, string title)
            : base(length, title)
        {
        }

        public override void Accept(IVariableVisitor visitor)
        {
            visitor.Visit(this);
        }
    }
}
