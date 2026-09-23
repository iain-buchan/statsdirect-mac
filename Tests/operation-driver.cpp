#include <dlfcn.h>
#include <iostream>
#include <string>
#include <thread>
#include <chrono>
int main(int argc, char** argv) {
    if (argc != 2 && argc != 4) return 1;
    auto library = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (!library) { std::cerr << dlerror(); return 1; }
    auto invoke = (char*(*)(const char*))dlsym(library, "statsdirect_operation");
    auto release = (void(*)(char*))dlsym(library, "statsdirect_operation_free");
    if (!invoke || !release) return 1;
    std::string input;
    while (std::getline(std::cin, input)) {
        std::thread cancellation;
        if (argc == 4) cancellation = std::thread([&] {
            std::this_thread::sleep_for(std::chrono::milliseconds(std::stoi(argv[2])));
            std::string request = "{\"action\":\"cancel\",\"id\":\"" + std::string(argv[3]) + "\"}";
            auto response = invoke(request.c_str()); if (response) release(response);
        });
        auto result = invoke(input.c_str());
        if (cancellation.joinable()) cancellation.join();
        if (!result) return 2;
        std::cout << result << std::endl;
        release(result);
    }
}
