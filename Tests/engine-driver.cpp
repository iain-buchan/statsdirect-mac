// A line driver for any JSON entry of the engine bridge: engine-driver <StatsDirectEngine.dylib> <entry>, e.g. statsdirect_r_script.
// Each line of standard input is one request; each line of standard output is the engine's response (the entry's _free releases it).
#include <dlfcn.h>
#include <iostream>
#include <string>
int main(int argc, char** argv) {
    if (argc != 3) { std::cerr << "usage: engine-driver <dylib> <entry>\n"; return 1; }
    auto library = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (!library) { std::cerr << dlerror(); return 1; }
    std::string entry = argv[2];
    auto invoke = (char*(*)(const char*))dlsym(library, entry.c_str());
    auto release = (void(*)(char*))dlsym(library, (entry + "_free").c_str());
    if (!invoke || !release) { std::cerr << "no such entry: " << entry << "\n"; return 1; }
    std::string input;
    while (std::getline(std::cin, input)) {
        auto result = invoke(input.c_str());
        if (!result) return 2;
        std::cout << result << std::endl;
        release(result);
    }
}
