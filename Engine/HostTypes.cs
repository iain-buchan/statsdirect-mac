// Minimal data/parameter host for the unmodified paired-test routine.
// The full Windows operation host and chart engine are not included.
namespace StatsDirect.Data {
    public sealed class DoubleVariable {
        public double[] Data { get; init; }
        public string Title { get; init; }
        public int Length => Data.Length;
    }
    public sealed class DataFrame {
        public DoubleVariable[] Variables { get; init; }
        public int VariableCount => Variables.Length;
        public int MaxRows => Variables.Max(v => v.Length);
    }
}
namespace StatsDirect.Templates {
    public sealed class FilledParameter {
        public object Value { get; init; }
        public StatsDirect.Data.DataFrame AsDataFrame => (StatsDirect.Data.DataFrame)Value;
        public double AsDouble => Convert.ToDouble(Value);
        public bool AsBoolean => (bool)Value;
    }
    public sealed class ParameterBag : Dictionary<string,FilledParameter> {
        public void AddOutput(string name, object value) => this[name] = new FilledParameter { Value = value };
    }
    public sealed class StepOutput(ParameterBag parameters) {
        public ParameterBag Parameters { get; } = parameters;
    }
}
namespace StatsDirect.Charting {
    public enum ChartType { Ties }
    public sealed class TiesOptions {
        public TiesOptions(double[] x, double[] y, int n, double lower, double upper, double confidence, string a, string b, double mean) { }
    }
    public static class ChartRendererFactory {
        public static object PrepForLater(ChartType type, TiesOptions options) =>
            throw new NotSupportedException("Agreement charts are not included in this paired-test prototype.");
    }
}
