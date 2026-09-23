#include <dlfcn.h>
#include <filesystem>
#include <mutex>
#include <cstdio>
#include "hostfxr.h"
#include "coreclr_delegates.h"
using paired_fn = int (*)(const double*, const double*, int, double, double*, int);
using named_paired_fn = int (*)(const double*, const double*, int, double, double*, int, const char*, const char*);
static named_paired_fn pairedNamed = nullptr;
using report_fn = int (*)(char*, int);
static paired_fn paired = nullptr;
static report_fn report = nullptr;
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
