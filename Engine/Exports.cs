using System.Runtime.InteropServices;
using StatsDirect.Data;
using StatsDirect.Templates;
using StatsDirect.Numerics;

public static unsafe class Exports {
    // C ABI: 0 success, 1 invalid input, 2 insufficient usable pairs,
    // 3 constant/non-finite differences, 4 numerical failure.
    // Output: n, mean, sd, sem, CI lower, CI upper, df, t, P1, P2, power.
    [UnmanagedCallersOnly(EntryPoint = "statsdirect_paired_t")]
    public static int Paired(double* before, double* after, int count, double confidence, double* output, int capacity) {
        try {
            if (before == null || after == null || output == null || count < 2 || count > 1000000 || capacity < 11 || !(confidence > 0 && confidence < 1)) return 1;
            var left = new List<double>(); var right = new List<double>();
            for (int i=0;i<count;i++) {
                if (!double.IsFinite(before[i]) || !double.IsFinite(after[i]) || before[i] == Constant.MISSING || after[i] == Constant.MISSING) continue;
                left.Add(before[i]); right.Add(after[i]);
            }
            if (left.Count < 2) return 2;
            double first = left[0]-right[0];
            if (!double.IsFinite(first) || Enumerable.Range(0,left.Count).Any(i=>!double.IsFinite(left[i]-right[i])) || Enumerable.Range(0,left.Count).All(i=>left[i]-right[i]==first)) return 3;
            var args = new ParameterBag();
            args.AddOutput("data", new DataFrame { Variables = [new DoubleVariable { Data=left.ToArray(),Title="PEFR Before" }, new DoubleVariable { Data=right.ToArray(),Title="PEFR After" }] });
            args.AddOutput("gamma", confidence);
            args.AddOutput("doAgreement", false);
            var result = StatsDirect.Builtins.Parametric.RptTPaired(args).Parameters;
            string[] names = ["n","mean","sd","sem","from","to","df","t","tail_1","tail_2"];
            for (int i=0;i<names.Length;i++) {
                double value=result[names[i]].AsDouble;
                if (!double.IsFinite(value)) return 4;
                output[i]=value;
            }
            output[10]=StatsDirect.Builtins.Power.ptpower(1-confidence, output[1], output[2], left.Count);
            return double.IsFinite(output[10]) ? 0 : 4;
        } catch { return 4; }
    }
}
