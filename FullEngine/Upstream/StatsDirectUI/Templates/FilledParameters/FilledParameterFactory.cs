using StatsDirect.Charting;
using StatsDirect.Data;
using StatsDirect.UI;
using System.Collections.Generic;

namespace StatsDirect.Templates
{
    public static class FilledParameterFactory
    {
        public static FilledParameter Input(object data) => Make(FilledParameterDirection.Input, data);
        public static FilledParameter Output(object data) => Make(FilledParameterDirection.Output, data);
        public static FilledParameter Default(object data) => Make(FilledParameterDirection.Default, data);
        public static FilledParameter Make(FilledParameterDirection direction, dynamic data)
        {
            return null == data
                ? new FilledObjectParameter(direction, data)
                : MakeInternal(direction, data);
        }
        private static FilledParameter MakeInternal(FilledParameterDirection direction, bool data) => new FilledBooleanParameter(direction, data);
        private static FilledParameter MakeInternal(FilledParameterDirection direction, ChartDefinition data) => new FilledChartDefinitionParameter(direction, data);
        private static FilledParameter MakeInternal(FilledParameterDirection direction, DataFrame data) => new FilledDataFrameParameter(direction, data);
        private static FilledParameter MakeInternal(FilledParameterDirection direction, double data) => new FilledDoubleParameter(direction, data);
        private static FilledParameter MakeInternal(FilledParameterDirection direction, int data) => new FilledInt32Parameter(direction, data);
        private static FilledParameter MakeInternal(FilledParameterDirection direction, object data) => new FilledObjectParameter(direction, data);
        private static FilledParameter MakeInternal(FilledParameterDirection direction, Pane data) => new FilledPaneParameter(direction, data);
        private static FilledParameter MakeInternal(FilledParameterDirection direction, PaneAndPosition data) => new FilledPaneAndPositionParameter(direction, data);
        private static FilledParameter MakeInternal(FilledParameterDirection direction, ParameterBag data) => new FilledParameterBagParameter(direction, data);
        private static FilledParameter MakeInternal(FilledParameterDirection direction, IList<ParameterBag> data) => new FilledParameterBagListParameter(direction, data);
        private static FilledParameter MakeInternal(FilledParameterDirection direction, string data) => new FilledStringParameter(direction, data);
        private static FilledParameter MakeInternal(FilledParameterDirection direction, IList<string> data) => new FilledStringListParameter(direction, data);
    }
}
