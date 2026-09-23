using System;

namespace StatsDirect.Data
{
    public interface IVariableVisitor
    {
        void Visit(GenericVariable<bool> variable);
        void Visit(ClassifierVariable variable);
        void Visit(GenericVariable<DateTime> variable);
        void Visit(DoubleVariable variable);
        void Visit(StringVariable variable);
        void Visit(GenericVariable<object> variable);
    }
}
