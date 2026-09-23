#include <dlfcn.h>
#include <iostream>
#include <string>
int main(int argc, char** argv) {
    if (argc != 2) return 1;
    auto library = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (!library) { std::cerr << dlerror(); return 1; }
    auto invoke = (char*(*)(const char*))dlsym(library, "statsdirect_workbook");
    auto release = (void(*)(char*))dlsym(library, "statsdirect_workbook_free");
    if (!invoke || !release) return 1;
    std::string input;
    while (std::getline(std::cin, input)) {
        auto result = invoke(input.c_str());
        if (!result) return 2;
        std::cout << result << std::endl;
        release(result);
    }
}
