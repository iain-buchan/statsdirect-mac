using System;
using System.Linq;
using System.Collections.Generic;
using System.Text;
using System.Globalization;
using StatsDirect.UI;
using StatsDirect.TemplateProcessing;
using System.Runtime.InteropServices;
using StatsDirect.Data;
using StatsDirect.Templates;
using StatsDirect.Numerics;

public static unsafe class Exports {
    static Exports() {
        // Scripts loaded by Assembly.Load must resolve types from this hosted engine context.
        AppDomain.CurrentDomain.AssemblyResolve += (_, args) =>
            new System.Reflection.AssemblyName(args.Name).Name == typeof(Exports).Assembly.GetName().Name
                ? typeof(Exports).Assembly : null;
    }
    private static string lastHtml = "";
    // C ABI: 0 success, 1 invalid input, 2 insufficient usable pairs,
    // 3 constant/non-finite differences, 4 numerical failure.
    // Output: n, mean, sd, sem, CI lower, CI upper, df, t, P1, P2, power.
    [UnmanagedCallersOnly(EntryPoint = "statsdirect_paired_t")]
    public static int Paired(double* before, double* after, int count, double confidence, double* output, int capacity) {
        return PairedCore(before, after, count, confidence, output, capacity, "PEFR Before", "PEFR After");
    }
    [UnmanagedCallersOnly]
    public static int PairedNamed(double* before, double* after, int count, double confidence, double* output, int capacity, byte* first, byte* second) {
        try { return PairedCore(before, after, count, confidence, output, capacity, Marshal.PtrToStringUTF8((IntPtr)first) ?? "Before", Marshal.PtrToStringUTF8((IntPtr)second) ?? "After"); }
        catch { return 1; }
    }
    private static int PairedCore(double* before, double* after, int count, double confidence, double* output, int capacity, string first, string second) {
        lastHtml = "";
        try {
            if (before == null || after == null || output == null || count < 2 || count > 1000000 || capacity < 11 || !(confidence > 0 && confidence < 1)) return 1;
            var left = new List<double>(); var right = new List<double>();
            for (int i=0;i<count;i++) {
                if (!double.IsFinite(before[i]) || !double.IsFinite(after[i]) || before[i] == Constant.MISSING || after[i] == Constant.MISSING) continue;
                left.Add(before[i]); right.Add(after[i]);
            }
            if (left.Count < 2) return 2;
            double firstDifference = left[0]-right[0];
            if (!double.IsFinite(firstDifference) || Enumerable.Range(0,left.Count).Any(i=>!double.IsFinite(left[i]-right[i])) || Enumerable.Range(0,left.Count).All(i=>left[i]-right[i]==firstDifference)) return 3;
            _ = SdApplication.SoleInstance;
            var csv = new StringBuilder("\"" + first.Replace("\"", "\"\"") + "\",\"" + second.Replace("\"", "\"\"") + "\"\n");
            for (int i=0;i<left.Count;i++) csv.Append(left[i].ToString("R", CultureInfo.InvariantCulture)).Append(',').Append(right[i].ToString("R", CultureInfo.InvariantCulture)).Append('\n');
            var host = new ViewerHost(new List<OperationTestInputParameter> {
                new() { Name="data", Value=csv.ToString() },
                new() { Name="gamma", Value=confidence.ToString("R", CultureInfo.InvariantCulture) },
                new() { Name="doAgreement", Value="False" }
            });
            var result = ((ITemplateProcessor)new TemplateProcessor(host)).Execute(TemplateFactory.Operations["TPaired"], new ParameterBag()).ParameterBag;
            lastHtml = host.Html.ToString();
            string[] names = ["n","mean","sd","sem","from","to","df","t","tail_1","tail_2"];
            for (int i=0;i<names.Length;i++) {
                double value=result[names[i]].IsDouble ? result[names[i]].AsDouble : result[names[i]].AsInt32;
                if (!double.IsFinite(value)) return 4;
                output[i]=value;
            }
            output[10]=StatsDirect.Builtins.Power.ptpower(1-confidence, output[1], output[2], left.Count);
            return double.IsFinite(output[10]) ? 0 : 4;
        } catch (Exception ex) { Console.Error.WriteLine(ex); return 4; }
    }

    [UnmanagedCallersOnly]
    public static int Report(byte* buffer, int capacity) {
        try {
            byte[] bytes = Encoding.UTF8.GetBytes(lastHtml);
            if (buffer != null && capacity > bytes.Length) {
                bytes.AsSpan().CopyTo(new Span<byte>(buffer, bytes.Length)); buffer[bytes.Length]=0;
            }
            return bytes.Length + 1;
        } catch { return -1; }
    }
}
