using System;
using System.Globalization;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Text.Json;
using StatsDirect.Builtins;
using StatsDirect.Expressions;
using StatsDirect.Numerics;

// The Windows calculator's evaluation path, exposed to the native Mac pane.
// Expressions are parsed by Calcit; no host-language evaluation or source rewriting.
public static class CalculatorIO {
    sealed record Request(string Expression, string Culture);
    static readonly JsonSerializerOptions json = new() { PropertyNameCaseInsensitive = true };
    public static string Execute(string input) {
        try {
            var request = JsonSerializer.Deserialize<Request>(input, json) ?? throw new Exception("Enter an expression.");
            if (string.IsNullOrWhiteSpace(request.Expression)) throw new Exception("Enter an expression.");
            RuntimeHelpers.RunClassConstructor(typeof(Exports).TypeHandle);
            lock (EngineExecution.Gate) {
                var previous = CultureInfo.CurrentCulture;
                try {
                    if (!string.IsNullOrEmpty(request.Culture)) CultureInfo.CurrentCulture = CultureInfo.GetCultureInfo(request.Culture);
                    var calculator = new Calcit(request.Expression, Array.Empty<DataType>(), false);
                    object value = calculator.EvaluateObject<object>(null);
                    string result = value is double number && number == Constant.MISSING ? "error" : value?.ToString() ?? "";
                    return JsonSerializer.Serialize(new { expression = request.Expression, result, type = calculator.OutputType.ToString() });
                } finally { CultureInfo.CurrentCulture = previous; }
            }
        } catch (Exception error) {
            return JsonSerializer.Serialize(new { error = error.GetBaseException().Message });
        }
    }
    [UnmanagedCallersOnly]
    public static IntPtr Invoke(IntPtr input) => Marshal.StringToCoTaskMemUTF8(Execute(Marshal.PtrToStringUTF8(input) ?? "{}"));
    [UnmanagedCallersOnly]
    public static void Free(IntPtr result) => Marshal.FreeCoTaskMem(result);
}
