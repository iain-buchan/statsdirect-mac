// Experimental, isolated R front end. No StatsDirect calculation-engine code is linked here.
// R's console callbacks and evaluator run only on this process's main thread.
#define R_NO_REMAP
#define R_INTERFACE_PTRS
#include <Rembedded.h>
#include <Rinterface.h>
#include <Rinternals.h>
#include <R_ext/Parse.h>
#include <R_ext/Utils.h>

#include <cerrno>
#include <chrono>
#include <clocale>
#include <csignal>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <dlfcn.h>
#include <fcntl.h>
#include <fstream>
#include <iterator>
#include <poll.h>
#include <stdexcept>
#include <string>
#include <sys/stat.h>
#include <unistd.h>

namespace {
constexpr std::uint32_t maxFrame = 8 * 1024 * 1024;
constexpr std::size_t maxCommandOutput = 1024 * 1024;
constexpr std::size_t maxSessionOutput = 24 * 1024 * 1024;
int eventFD = -1, inputFD = -1;
pid_t ownerPID = 0;
std::string sessionID, commandID, pendingCode, pendingID;
std::string inputRequestID;
std::uint64_t sequence = 0, inputSequence = 0;
std::size_t commandOutput = 0, sessionOutput = 0;
bool outputNotice = false, quitRequested = false, commandError = false, incomplete = false;
volatile sig_atomic_t interrupted = 0;
int *interruptPending = nullptr;

template<class T> T symbol(void *lib, const char *name) {
    auto value = dlsym(lib, name);
    if (!value) throw std::runtime_error(std::string("R runtime does not export ") + name);
    return reinterpret_cast<T>(value);
}

struct RAPI {
    void *library;
#define FUNCTION(member, native) decltype(&native) member
    FUNCTION(initialize, Rf_initialize_R); FUNCTION(setup, setup_Rmainloop);
    FUNCTION(end, Rf_endEmbeddedR); FUNCTION(protect, Rf_protect); FUNCTION(unprotect, Rf_unprotect);
    FUNCTION(string, Rf_mkString); FUNCTION(utf8Char, Rf_mkCharCE); FUNCTION(scalarString, Rf_ScalarString);
    FUNCTION(parse, R_ParseVector); FUNCTION(eval, Rf_eval); FUNCTION(tryEval, R_tryEval); FUNCTION(topLevel, R_ToplevelExec);
    FUNCTION(print, Rf_PrintValue); FUNCTION(length, Rf_xlength); FUNCTION(vectorAt, VECTOR_ELT);
    FUNCTION(stringAt, STRING_ELT); FUNCTION(utf8, Rf_translateCharUTF8); FUNCTION(asChar, Rf_asChar);
    FUNCTION(install, Rf_install); FUNCTION(lang1, Rf_lang1); FUNCTION(lang2, Rf_lang2);
    FUNCTION(newEnv, R_NewEnv); FUNCTION(preserve, R_PreserveObject); FUNCTION(release, R_ReleaseObject);
    FUNCTION(checkInterrupt, R_CheckUserInterrupt); FUNCTION(getOption, Rf_GetOption1);
#undef FUNCTION
    SEXP *global, *base, *nil;
    Rboolean *visible, *interactive;
    int *signalHandlers;
    int (*readConsole)(const char *, unsigned char *, int, int) = nullptr;
    SEXP capture = nullptr;
    explicit RAPI(const std::string &home) {
        library = dlopen((home + "/lib/libR.dylib").c_str(), RTLD_NOW | RTLD_GLOBAL);
        if (!library) throw std::runtime_error(dlerror());
#define LOAD(member, native) member = symbol<decltype(member)>(library, #native)
        LOAD(initialize,Rf_initialize_R); LOAD(setup,setup_Rmainloop); LOAD(end,Rf_endEmbeddedR);
        LOAD(protect,Rf_protect); LOAD(unprotect,Rf_unprotect); LOAD(string,Rf_mkString);
        LOAD(utf8Char,Rf_mkCharCE); LOAD(scalarString,Rf_ScalarString); LOAD(parse,R_ParseVector);
        LOAD(eval,Rf_eval); LOAD(tryEval,R_tryEval); LOAD(topLevel,R_ToplevelExec); LOAD(print,Rf_PrintValue);
        LOAD(length,Rf_xlength); LOAD(vectorAt,VECTOR_ELT); LOAD(stringAt,STRING_ELT);
        LOAD(utf8,Rf_translateCharUTF8); LOAD(asChar,Rf_asChar); LOAD(install,Rf_install);
        LOAD(lang1,Rf_lang1); LOAD(lang2,Rf_lang2); LOAD(newEnv,R_NewEnv);
        LOAD(preserve,R_PreserveObject); LOAD(release,R_ReleaseObject);
        LOAD(checkInterrupt,R_CheckUserInterrupt); LOAD(getOption,Rf_GetOption1);
#undef LOAD
        global = symbol<SEXP *>(library,"R_GlobalEnv"); base = symbol<SEXP *>(library,"R_BaseEnv");
        nil = symbol<SEXP *>(library,"R_NilValue"); visible = symbol<Rboolean *>(library,"R_Visible");
        interactive = symbol<Rboolean *>(library,"R_Interactive");
        signalHandlers = symbol<int *>(library,"R_SignalHandlers");
        interruptPending = symbol<int *>(library,"R_interrupts_pending");
    }
};
RAPI *r = nullptr;

std::string json(const std::string &value) {
    static const char hex[] = "0123456789abcdef";
    std::string out = "\"";
    for (unsigned char c : value) {
        if (c == '\\' || c == '"') { out += '\\'; out += char(c); }
        else if (c < 32) { out += "\\u00"; out += hex[c >> 4]; out += hex[c & 15]; }
        else out += char(c);
    }
    return out + '"';
}
void writeAll(int fd, const std::string &text) {
    std::size_t sent = 0;
    while (sent < text.size()) {
        auto n = ::write(fd, text.data() + sent, text.size() - sent);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) throw std::runtime_error("The console event channel closed.");
        sent += std::size_t(n);
    }
}
void emit(const std::string &fields) {
    writeAll(eventFD, "{\"protocolVersion\":1,\"sessionId\":" + json(sessionID) +
             ",\"seq\":" + std::to_string(++sequence) + ',' + fields + "}\n");
}
void flushConsoleOutput(bool final = true);
void state(const char *value, const std::string &prompt) {
    flushConsoleOutput();
    emit("\"type\":\"state\",\"state\":" + json(value) + ",\"prompt\":" + json(prompt) +
         ",\"commandId\":" + json(commandID));
}
std::string outputPending[2];
int lastOutputStream = -1;
auto lastOutputFlush = std::chrono::steady_clock::time_point{};
void flushOutput(int stream) {
    auto &text = outputPending[stream];
    if (text.empty()) return;
    emit("\"type\":\"output\",\"stream\":" + json(stream ? "stderr" : "stdout") +
         ",\"commandId\":" + json(commandID) + ",\"text\":" + json(text));
    text.clear(); lastOutputFlush = std::chrono::steady_clock::now();
}
void output(const std::string &text, int stream) {
    if (text.empty()) return;
    if (lastOutputStream >= 0 && lastOutputStream != stream) flushOutput(lastOutputStream);
    lastOutputStream = stream;
    if (commandOutput + text.size() > maxCommandOutput || sessionOutput + text.size() > maxSessionOutput) {
        if (!outputNotice) {
            outputNotice = true;
            flushOutput(stream);
            emit("\"type\":\"output\",\"stream\":\"stderr\",\"commandId\":" + json(commandID) +
                 ",\"text\":\"[Console output truncated at the prototype output limit.]\\n\"");
        }
        return;
    }
    commandOutput += text.size(); sessionOutput += text.size();
    outputPending[stream] += text;
    if (outputPending[stream].size() >= 8192 || text.find('\n') != std::string::npos ||
        std::chrono::steady_clock::now() - lastOutputFlush >= std::chrono::milliseconds(40)) flushOutput(stream);
}

// R can split a multibyte code point between WriteConsoleEx calls.
std::string utf8Pending[2];
void flushUTF8(int stream, bool final = false) {
    auto &buffer = utf8Pending[stream]; std::string valid;
    std::size_t i = 0;
    while (i < buffer.size()) {
        const auto c = static_cast<unsigned char>(buffer[i]);
        std::size_t width = c < 0x80 ? 1 : c >= 0xc2 && c <= 0xdf ? 2 : c >= 0xe0 && c <= 0xef ? 3 : c >= 0xf0 && c <= 0xf4 ? 4 : 0;
        if (width && i + width > buffer.size() && !final) break;
        bool okay = width && i + width <= buffer.size();
        for (std::size_t k = 1; okay && k < width; ++k) okay = (static_cast<unsigned char>(buffer[i+k]) & 0xc0) == 0x80;
        if (okay && width >= 3) {
            auto next = static_cast<unsigned char>(buffer[i+1]);
            if ((c == 0xe0 && next < 0xa0) || (c == 0xed && next >= 0xa0) || (c == 0xf0 && next < 0x90) || (c == 0xf4 && next >= 0x90)) okay = false;
        }
        if (okay) { valid.append(buffer, i, width); i += width; }
        else { valid += "\xef\xbf\xbd"; ++i; }
    }
    buffer.erase(0,i); output(valid,stream);
    if (final) flushOutput(stream);
}
void flushConsoleOutput(bool final) {
    flushUTF8(0,final); flushUTF8(1,final);
    flushOutput(0); flushOutput(1);
}
void writeConsole(const char *bytes, int length, int type) {
    int stream = type ? 1 : 0;
    if (length > 0) utf8Pending[stream].append(bytes, std::size_t(length));
    flushUTF8(stream);
}
void showMessage(const char *text) { output(std::string(text) + '\n',1); }
void onInterrupt(int) { interrupted = 1; if (interruptPending) *interruptPending = 1; }
void installInterruptHandler() {
    struct sigaction action{}; action.sa_handler=onInterrupt; sigemptyset(&action.sa_mask); sigaction(SIGINT,&action,nullptr);
    // R temporarily owns SIGINT in routines such as Sys.sleep(). The host's
    // dedicated interrupt signal keeps the cancellation flag observable too.
    sigaction(SIGUSR1,&action,nullptr);
}

struct Frame { char kind = 0; std::string payload; };
enum class Read { okay, interrupted, eof };
Read readBytes(char *data, std::size_t length, bool interruptible = true) {
    std::size_t received = 0;
    while (received < length) {
        // O_RDWR keeps the private FIFO usable during startup but also masks
        // EOF when the host dies. A reparented worker must not outlive its host.
        if (getppid() != ownerPID || (kill(ownerPID,0) < 0 && errno == ESRCH)) return Read::eof;
        // Once any frame bytes have been consumed, finish that frame before
        // delivering the interrupt so the next request cannot be misframed.
        if (interruptible && received == 0 && interrupted) return Read::interrupted;
        pollfd watch{inputFD,POLLIN,0}; int ready = poll(&watch,1,100);
        if (ready < 0 && errno == EINTR) continue;
        if (ready < 0) throw std::runtime_error("Could not poll the input channel.");
        if (!ready) continue;
        auto count = ::read(inputFD,data+received,length-received);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) return Read::eof;
        received += std::size_t(count);
    }
    return Read::okay;
}
Read frame(Frame &result) {
    char header[5]; auto status = readBytes(header,5); if (status != Read::okay) return status;
    std::uint32_t length = 0; for (int i = 1; i < 5; ++i) length = (length << 8) | static_cast<unsigned char>(header[i]);
    if (length > maxFrame) throw std::runtime_error("Console input exceeds the 8 MiB frame limit.");
    result.kind = header[0]; result.payload.resize(length);
    return length ? readBytes(result.payload.data(),length,false) : Read::okay;
}
bool identity(const std::string &payload, std::string &id, std::string &text) {
    auto split = payload.find('\n');
    if (split == std::string::npos || split == 0 || split > 120) return false;
    id = payload.substr(0,split); text = payload.substr(split+1);
    for (unsigned char c : id) if (c < 33 || c > 126) return false;
    return text.find('\0') == std::string::npos;
}
Frame interactiveFrame;
void requestInput(const char *prompt, int length, int history) {
    emit("\"type\":\"inputRequested\",\"requestId\":" + json(inputRequestID) + ",\"commandId\":" + json(commandID) +
         ",\"prompt\":" + json(prompt) + ",\"addToHistory\":" + (history ? "true" : "false") +
         ",\"maxAnswerBytes\":" + std::to_string(length >= 2 ? length-2 : 0));
    state("input",prompt);
}
int readConsole(const char *prompt, unsigned char *buffer, int length, int history) {
    flushConsoleOutput();
    // This callback can unwind through R's longjmp. Keep its request string in
    // process storage instead of a C++ local whose destructor would be skipped.
    inputRequestID = sessionID + ":input:" + std::to_string(++inputSequence);
    requestInput(prompt,length,history);
    for (;;) {
        const auto status = frame(interactiveFrame);
        if (status == Read::interrupted || interrupted) { *interruptPending=1; r->checkInterrupt(); continue; }
        if (status == Read::eof || interactiveFrame.kind == 'Q') {
            quitRequested = true; interrupted = 1; *interruptPending = 1; r->checkInterrupt(); continue;
        }
        std::string id, text;
        if (interactiveFrame.kind != 'I' || !identity(interactiveFrame.payload,id,text) || id != inputRequestID) {
            emit("\"type\":\"inputRejected\",\"requestId\":" + json(inputRequestID) + ",\"reason\":\"Stale or mismatched interactive input.\"");
            requestInput(prompt,length,history);
            continue;
        }
        if (text.find('\n') != std::string::npos || text.find('\r') != std::string::npos || text.size() + 2 > std::size_t(length)) {
            emit("\"type\":\"inputRejected\",\"requestId\":" + json(inputRequestID) +
                 ",\"reason\":\"Interactive answers must fit on one R input line.\",\"maxAnswerBytes\":" + std::to_string(length >= 2 ? length-2 : 0));
            requestInput(prompt,length,history); continue;
        }
        std::memcpy(buffer,text.data(),text.size()); buffer[text.size()] = '\n'; buffer[text.size()+1] = 0;
        state("busy",""); return 1;
    }
}

SEXP makeText(const std::string &text) {
    SEXP chars = r->protect(r->utf8Char(text.c_str(),CE_UTF8));
    SEXP result = r->scalarString(chars); r->unprotect(1); return result;
}
void capturePlots() {
    if (!r->capture) return;
    SEXP call = r->protect(r->lang1(r->capture)); int error = 0;
    SEXP paths = r->protect(r->tryEval(call,*r->global,&error));
    flushConsoleOutput(false);
    if (!error) for (R_xlen_t i=0;i<r->length(paths);++i) {
        std::string path = r->utf8(r->stringAt(paths,i));
        emit("\"type\":\"plot\",\"commandId\":" + json(commandID) + ",\"id\":" + json(path.substr(path.find_last_of('/')+1)) +
             ",\"mime\":\"image/svg+xml\",\"path\":" + json(path));
    }
    r->unprotect(2);
}
void captureCompletedPlots(void *) { capturePlots(); }
void evaluate(void *) {
    r->checkInterrupt();
    ParseStatus status;
    SEXP source = r->protect(makeText(pendingCode));
    SEXP expressions = r->protect(r->parse(source,-1,&status,*r->nil));
    if (status == PARSE_INCOMPLETE) { incomplete = true; r->unprotect(2); return; }
    if (status != PARSE_OK && status != PARSE_NULL) {
        const char *detail = symbol<const char *>(r->library,"R_ParseErrorMsg");
        output(std::string("Error: ") + (detail && *detail ? detail : "Invalid R syntax.") + '\n',1);
        commandError = true; r->unprotect(2); return;
    }
    for (R_xlen_t i=0;i<r->length(expressions);++i) {
        // R_tryEval restores R_Visible to TRUE; use eval inside the outer
        // R_ToplevelExec boundary so assignments and invisible() stay invisible.
        SEXP result = r->protect(r->eval(r->vectorAt(expressions,i),*r->global));
        if (interrupted) { commandError=true; r->unprotect(1); break; }
        if (*r->visible) r->print(result);
        r->unprotect(1);
    }
    r->unprotect(2);
}
std::string prompt(const char *option, const char *fallback) {
    auto value = r->getOption(r->install(option));
    return value == *r->nil ? fallback : r->utf8(r->asChar(value));
}
void finish(bool wasInterrupted) {
    flushConsoleOutput();
    if (wasInterrupted) output("Interrupted\n",1);
    emit("\"type\":\"commandFinished\",\"commandId\":" + json(commandID) + ",\"status\":" +
         json(wasInterrupted ? "interrupted" : commandError ? "error" : "ok") + ",\"source\":" + json(pendingCode));
    pendingCode.clear(); pendingID.clear(); commandID.clear(); interrupted = 0; *interruptPending = 0;
    state("ready",prompt("prompt","> "));
}
void loadBootstrap(void *data) {
    const auto &code = *static_cast<std::string *>(data); ParseStatus status;
    SEXP source = r->protect(makeText(code));
    SEXP expressions = r->protect(r->parse(source,-1,&status,*r->nil));
    if (status != PARSE_OK) { commandError = true; r->unprotect(2); return; }
    SEXP env = r->protect(r->newEnv(*r->base,TRUE,29));
    for (R_xlen_t i=0;i<r->length(expressions);++i) {
        int error = 0; SEXP value = r->tryEval(r->vectorAt(expressions,i),env,&error);
        if (error) { commandError = true; break; }
        if (i == r->length(expressions)-1) { r->protect(value); r->capture = value; r->preserve(value); r->unprotect(1); }
    }
    r->unprotect(3);
}
} // namespace

int main(int argc, char **argv) {
    try {
        ownerPID = getppid();
        std::string home, input, events, directory, bootstrap;
        for (int i=1;i+1<argc;i+=2) {
            std::string key = argv[i], value = argv[i+1];
            if (key == "--r-home") home=value; else if (key == "--input") input=value;
            else if (key == "--events") events=value; else if (key == "--workdir") directory=value;
            else if (key == "--bootstrap") bootstrap=value; else if (key == "--session") sessionID=value;
            else throw std::runtime_error("Unknown console worker argument: " + key);
        }
        if (home.empty()||input.empty()||events.empty()||directory.empty()||bootstrap.empty()||sessionID.empty()) throw std::runtime_error("Incomplete console worker arguments.");
        struct stat inputInfo{};
        if (lstat(input.c_str(),&inputInfo)||!S_ISFIFO(inputInfo.st_mode)||inputInfo.st_uid!=getuid()||(inputInfo.st_mode&0077)) throw std::runtime_error("Input must be a private FIFO owned by the current user.");
        eventFD = open(events.c_str(),O_WRONLY|O_APPEND|O_CREAT|O_NOFOLLOW,0600);
        if (eventFD<0) throw std::runtime_error("Could not open the private event file.");
        struct stat eventInfo{};
        if (fstat(eventFD,&eventInfo)||!S_ISREG(eventInfo.st_mode)||eventInfo.st_uid!=getuid()||fchmod(eventFD,0600)) throw std::runtime_error("Events must be a private regular file owned by the current user.");
        inputFD = open(input.c_str(),O_RDWR|O_NOFOLLOW);
        if (inputFD<0||chdir(directory.c_str())) throw std::runtime_error("Could not open the console working directory or input FIFO.");
        setenv("R_HOME",home.c_str(),1); setenv("STATSDIRECT_CONSOLE_PLOTS",directory.c_str(),1);
        std::setlocale(LC_ALL,"");
        RAPI api(home); r=&api; *r->signalHandlers=0;
        std::string program="StatsDirectRConsole";
        const char *arguments[]={program.c_str(),"--quiet","--no-save","--no-restore","--no-readline","--no-environ","--no-site-file","--no-init-file","--interactive","--gui=none"};
        char *rargv[10]; for(int i=0;i<10;++i)rargv[i]=const_cast<char *>(arguments[i]);
        if (r->initialize(10,rargv)<0) throw std::runtime_error("R initialization failed.");
        *symbol<decltype(&ptr_R_ReadConsole)>(r->library,"ptr_R_ReadConsole")=&readConsole;
        *symbol<decltype(&ptr_R_WriteConsoleEx)>(r->library,"ptr_R_WriteConsoleEx")=&writeConsole;
        *symbol<decltype(&ptr_R_WriteConsole)>(r->library,"ptr_R_WriteConsole")=nullptr;
        *symbol<decltype(&ptr_R_ShowMessage)>(r->library,"ptr_R_ShowMessage")=&showMessage;
        *symbol<FILE **>(r->library,"R_Consolefile")=nullptr; *symbol<FILE **>(r->library,"R_Outputfile")=nullptr;
        *r->interactive=TRUE; r->setup();
        installInterruptHandler();
        std::ifstream file(bootstrap); std::string init((std::istreambuf_iterator<char>(file)),{});
        if (init.empty() || !r->topLevel(loadBootstrap,&init) || commandError || !r->capture) throw std::runtime_error("The console graphics bootstrap could not be loaded.");
        emit("\"type\":\"started\",\"capabilities\":{\"plotMimes\":[\"image/svg+xml\"],\"interactiveInput\":true,\"interrupt\":true,\"interruptSignal\":\"SIGUSR1\"}");
        state("ready",prompt("prompt","> "));
        Frame request;
        while (!quitRequested) {
            // R reinstalls its own SIGINT handler after processing an interrupt.
            installInterruptHandler();
            auto received = frame(request);
            if (received==Read::eof) break;
            if (received==Read::interrupted) {
                interrupted=0; *interruptPending=0;
                if (!pendingCode.empty()) finish(true); else state("ready",prompt("prompt","> "));
                continue;
            }
            if (request.kind=='Q') break;
            std::string id, code;
            if (request.kind!='E'||!identity(request.payload,id,code)||(!pendingID.empty()&&pendingID!=id)) {
                emit("\"type\":\"requestRejected\",\"reason\":\"Stale or invalid command.\""); continue;
            }
            if (pendingCode.size()+code.size()+1>maxFrame) { output("R input exceeds the prototype command limit.\n",1); commandError=true; finish(false); continue; }
            commandID=id; pendingID=id; pendingCode+=code; pendingCode+='\n';
            commandError=false; incomplete=false; commandOutput=0; outputNotice=false;
            emit("\"type\":\"commandAccepted\",\"commandId\":"+json(commandID)); state("busy","");
            const bool completed = r->topLevel(evaluate,nullptr);
            if (!completed) commandError=true;
            if (incomplete && !interrupted) state("continuation",prompt("continue","+ "));
            else {
                // A submitted script may build one chart across plot(), lines(),
                // abline() and mtext(). Publish its finished page rather than a
                // separate unfinished snapshot after every expression. The R
                // before-new-page hooks retain distinct earlier pages.
                const bool wasInterrupted = interrupted != 0;
                interrupted=0; *interruptPending=0;
                // Evaluation errors/Stop unwind the first R boundary. Capture
                // completed drawing through a fresh boundary without running
                // any remaining source, including after an interrupt.
                r->topLevel(captureCompletedPlots,nullptr);
                finish(wasInterrupted || interrupted!=0);
            }
        }
        if (r->capture) r->release(r->capture);
        r->end(0); state("stopped","");
        close(inputFD); close(eventFD); return 0;
    } catch (const std::exception &error) {
        std::fprintf(stderr,"StatsDirect R console: %s\n",error.what()); return 1;
    }
}
