using StatsDirect.Templates;
using StatsDirect.Utilities;

namespace StatsDirect.Builtins
{
    public enum ChartExplorerChartType
    {
        BoxWhisker,
        Histogram
    }

    public class ChartExplorerOptions : IFillable
    {
        public ChartExplorerChartType ChartType { get; set; }
        public ParameterBag Parameters { get; set; }
        public string ChartAsRtf { get; set; }

        #region IFillable Members

        public string FillerToUse => "ChartExplorer";

        #endregion
    }

    public class ChartExplorer
    {
        public static StepOutput ExploreContinuousDistributions(ITemplateHost host, ParameterBag parameters)
        {
            ChartExplorerOptions options = new() { ChartType = ChartExplorerChartType.Histogram, Parameters = parameters};
            if (null == host.Amend(options, parameters))
                throw new TemplateOperationCancelledException();
            ParameterBag outputParameters = new();
            if (null != options.ChartAsRtf)
            {
                outputParameters.AddOutput("chart", options.ChartAsRtf);
            }
            return new StepOutput(outputParameters);
        }

        public static StepOutput CompareSeveralContinuousVariables(ITemplateHost host, ParameterBag parameters)
        {
            ChartExplorerOptions options = new() { ChartType = ChartExplorerChartType.BoxWhisker, Parameters = parameters};
            if (null == host.Amend(options, parameters))
                throw new TemplateOperationCancelledException();
            ParameterBag outputParameters = new();
            if (null != options.ChartAsRtf)
            {
                outputParameters.AddOutput("chart", options.ChartAsRtf);
            }
            return new StepOutput(outputParameters);
        }
    }
}
