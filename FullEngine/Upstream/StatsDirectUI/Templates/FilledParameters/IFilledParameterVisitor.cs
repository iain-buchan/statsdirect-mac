using System;
using System.Collections.Generic;
using System.Linq;
namespace StatsDirect.Templates
{
    public interface IFilledParameterVisitor
    {
        void Visit(FilledBooleanParameter victim);
        void Visit(FilledChartDefinitionParameter victim);
        void Visit(FilledDataFrameParameter victim);
        void Visit(FilledDoubleParameter victim);
        void Visit(FilledInt32Parameter victim);
        void Visit(FilledObjectParameter victim);
        void Visit(FilledPaneParameter victim);
        void Visit(FilledPaneAndPositionParameter victim);
        void Visit(FilledParameterBagParameter victim);
        void Visit(FilledParameterBagListParameter victim);
        void Visit(FilledStringParameter victim);
        void Visit(FilledStringListParameter victim);
    }
}
