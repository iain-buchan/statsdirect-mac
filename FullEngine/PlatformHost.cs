using System;
using StatsDirect.Templates;
namespace StatsDirect.UI {
 public sealed class WindowInformation { }
 public sealed class SdApplication {
 public static SdApplication SoleInstance { get; } = new();
 public SDPreferences Preferences { get; } = new HeadlessPreferences();
 private SdApplication() { BuiltinRegistry.SoleInstance.AddAll(Builtins.Registry.GetFunctionRegistry()); }
 }
}
namespace StatsDirect.Builtins {
 public static class ImportExport {
 public static StepOutput FileImportWorksheet(ITemplateHost host, ParameterBag parameters) => throw new PlatformNotSupportedException("File import needs a host file picker.");
 public static StepOutput FileExportWorksheet(ITemplateHost host, ParameterBag parameters) => throw new PlatformNotSupportedException("File export needs a host file picker.");
 }
}
