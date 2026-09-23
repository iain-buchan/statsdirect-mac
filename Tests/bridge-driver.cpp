// Native process exercises the same hostfxr bridge as the application.
// Apple's system Python is a protected process and cannot host CoreCLR.
#include <dlfcn.h>
#include <iostream>
#include <iomanip>
#include <vector>
#include <string>
int main(int argc, char** argv) {
 if (argc != 2) return 1;
 auto handle=dlopen(argv[1], RTLD_NOW|RTLD_LOCAL);
 if (!handle) { std::cerr<<dlerror(); return 1; }
 using Calculate=int(*)(const double*,const double*,int,double,double*,int);
 using Report=int(*)(char*,int);
 auto calculate=(Calculate)dlsym(handle,"statsdirect_paired_t");
 auto report=(Report)dlsym(handle,"statsdirect_paired_report");
 if (!calculate || !report) return 1;
 int count;double confidence;std::cin>>count>>confidence;
 if(count<0 || count>1000000) return 1;
 std::vector<double> before(count),after(count);double result[11]={};std::string value;
 for(auto& x:before) {std::cin>>value;x=std::stod(value);}
 for(auto& x:after) {std::cin>>value;x=std::stod(value);}
 int code=calculate(before.data(),after.data(),count,confidence,result,11);
 std::cout<<code;for(auto x:result)std::cout<<" "<<std::setprecision(17)<<x;std::cout<<"\n";
 int n=report(nullptr,0);if(n>0&&n<10000000){std::vector<char> html(n);report(html.data(),n);std::cout<<html.data();}
 return 0;
}
