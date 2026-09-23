#include <dlfcn.h>
#include <filesystem>
#include <mutex>
#include <cstdio>
#include "hostfxr.h"
#include "coreclr_delegates.h"
using paired_fn = int (*)(const double*, const double*, int, double, double*, int);
using named_paired_fn = int (*)(const double*, const double*, int, double, double*, int, const char*, const char*);
static named_paired_fn pairedNamed = nullptr;
using options_paired_fn = int (*)(const double*, const double*, int, double, double*, int, const char*, const char*, int);
static options_paired_fn pairedOptions = nullptr;
using report_fn = int (*)(char*, int);
static paired_fn paired = nullptr;
static report_fn report = nullptr;
using workbook_fn = char* (*)(const char*);
using free_fn = void (*)(char*);
static workbook_fn workbookRequest = nullptr;
static free_fn workbookFree = nullptr;
static workbook_fn analysisRequest = nullptr;
static free_fn analysisFree = nullptr;
static workbook_fn operationRequest = nullptr;
static free_fn operationFree = nullptr;
static std::once_flag initialized;
static void initialize() {
    Dl_info location{};
    dladdr((void*)&initialize, &location);
    auto directory = std::filesystem::path(location.dli_fname).parent_path();
    if (!std::filesystem::exists(directory / "StatsDirect.Headless.runtimeconfig.json"))
        directory = directory.parent_path() / "Resources/Engine";
    void* library = dlopen((directory / "dotnet/libhostfxr.dylib").c_str(), RTLD_NOW | RTLD_LOCAL);
    if (!library) { fprintf(stderr, "StatsDirect: %s\n", dlerror()); return; }
    auto init = (hostfxr_initialize_for_runtime_config_fn)dlsym(library, "hostfxr_initialize_for_runtime_config");
    auto get = (hostfxr_get_runtime_delegate_fn)dlsym(library, "hostfxr_get_runtime_delegate");
    auto close = (hostfxr_close_fn)dlsym(library, "hostfxr_close");
    if (!init || !get || !close) return;
    hostfxr_handle context = nullptr;
    const auto runtimeRoot = directory / "dotnet";
    hostfxr_initialize_parameters options{sizeof(hostfxr_initialize_parameters), nullptr, runtimeRoot.c_str()};
    int code = init((directory / "StatsDirect.Headless.runtimeconfig.json").c_str(), &options, &context);
    if (code < 0 || !context) return;
    load_assembly_and_get_function_pointer_fn load = nullptr;
    code = get(context, hdt_load_assembly_and_get_function_pointer, (void**)&load);
    close(context);
    if (code < 0 || !load) return;
    const auto assembly = directory / "StatsDirect.Headless.dll";
    code = load(assembly.c_str(), "Exports, StatsDirect.Headless", "Paired", UNMANAGEDCALLERSONLY_METHOD, nullptr, (void**)&paired);
    if (code < 0) { paired = nullptr; return; }
    code = load(assembly.c_str(), "Exports, StatsDirect.Headless", "Report", UNMANAGEDCALLERSONLY_METHOD, nullptr, (void**)&report);
    if (code < 0) report = nullptr;
    code = load(assembly.c_str(), "Exports, StatsDirect.Headless", "PairedNamed", UNMANAGEDCALLERSONLY_METHOD, nullptr, (void**)&pairedNamed);
    if (code < 0) pairedNamed = nullptr;
    code = load(assembly.c_str(), "Exports, StatsDirect.Headless", "PairedOptions", UNMANAGEDCALLERSONLY_METHOD, nullptr, (void**)&pairedOptions);
    if (code < 0) pairedOptions = nullptr;
    code = load(assembly.c_str(), "WorkbookIO, StatsDirect.Headless", "Invoke", UNMANAGEDCALLERSONLY_METHOD, nullptr, (void**)&workbookRequest);
    if (code < 0) workbookRequest = nullptr;
    code = load(assembly.c_str(), "WorkbookIO, StatsDirect.Headless", "Free", UNMANAGEDCALLERSONLY_METHOD, nullptr, (void**)&workbookFree);
    if (code < 0) workbookFree = nullptr;
    code = load(assembly.c_str(), "AnalysisIO, StatsDirect.Headless", "Invoke", UNMANAGEDCALLERSONLY_METHOD, nullptr, (void**)&analysisRequest);
    if (code < 0) analysisRequest = nullptr;
    code = load(assembly.c_str(), "AnalysisIO, StatsDirect.Headless", "Free", UNMANAGEDCALLERSONLY_METHOD, nullptr, (void**)&analysisFree);
    if (code < 0) analysisFree = nullptr;
    code = load(assembly.c_str(), "OperationSessions, StatsDirect.Headless", "Invoke", UNMANAGEDCALLERSONLY_METHOD, nullptr, (void**)&operationRequest);
    if (code < 0) operationRequest = nullptr;
    code = load(assembly.c_str(), "OperationSessions, StatsDirect.Headless", "Free", UNMANAGEDCALLERSONLY_METHOD, nullptr, (void**)&operationFree);
    if (code < 0) operationFree = nullptr;
}
extern "C" int statsdirect_paired_t(const double* before, const double* after, int count, double confidence, double* output, int capacity) {
    std::call_once(initialized, initialize);
    return paired ? paired(before, after, count, confidence, output, capacity) : 5;
}
extern "C" int statsdirect_paired_report(char* buffer, int capacity) {
    std::call_once(initialized, initialize);
    return report ? report(buffer, capacity) : -1;
}

extern "C" int statsdirect_paired_t_named(const double* before, const double* after, int count, double confidence, double* output, int capacity, const char* first, const char* second) {
    std::call_once(initialized, initialize);
    return pairedNamed ? pairedNamed(before, after, count, confidence, output, capacity, first, second) : 5;
}
extern "C" char* statsdirect_workbook(const char* request) {
    std::call_once(initialized, initialize);
    return workbookRequest && workbookFree ? workbookRequest(request) : nullptr;
}
extern "C" void statsdirect_workbook_free(char* result) {
    if (workbookFree) workbookFree(result);
}

extern "C" char* statsdirect_analysis(const char* request) {
    std::call_once(initialized, initialize);
    return analysisRequest && analysisFree ? analysisRequest(request) : nullptr;
}
extern "C" void statsdirect_analysis_free(char* result) { if (analysisFree) analysisFree(result); }

extern "C" int statsdirect_paired_t_options(const double* before, const double* after, int count, double confidence, double* output, int capacity, const char* first, const char* second, int agreement) {
    std::call_once(initialized, initialize);
    return pairedOptions ? pairedOptions(before, after, count, confidence, output, capacity, first, second, agreement) : 5;
}

extern "C" char* statsdirect_operation(const char* request) {
    std::call_once(initialized, initialize);
    return operationRequest && operationFree ? operationRequest(request) : nullptr;
}
extern "C" void statsdirect_operation_free(char* result) { if (operationFree) operationFree(result); }
