import Foundation

/// Standalone Foundation-only checks; no UI or real R installation is changed.
@main enum RRuntimeArchitectureChecks {
    static func main() throws {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent("StatsDirect-R-architecture-" + UUID().uuidString)
        try fm.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: directory) }
        let arguments = directory.appendingPathComponent("arguments.txt")
        func fixture(_ name: String, marker: String, status: Int) throws -> String {
            let executable = directory.appendingPathComponent(name)
            let quoted = "'" + arguments.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
            let source = "#!/bin/sh\nprintf '%s\\n' \"$@\" > " + quoted + "\nprintf '%s' '" + marker + "'\nexit " + String(status) + "\n"
            try source.write(to: executable, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
            return executable.path
        }
        let native = try fixture("native-Rscript", marker: "STATSDIRECT_NATIVE_R_READY", status: 0)
        precondition(RRuntime.nativeReady(in: [native]), "Native R is accepted")
        let sent = try String(contentsOf: arguments, encoding: .utf8)
        precondition(sent.contains("--vanilla\n-e\n") && sent.contains("R.version$arch")
                     && sent.contains("arm64") && sent.contains("aarch64"), "Probe asks R for its loaded native architecture")
        print("PASS: native R architecture marker is accepted with the architecture probe")
        let intel = try fixture("intel-Rscript", marker: "x86_64\nSTATSDIRECT_R_READY", status: 0)
        precondition(!RRuntime.nativeReady(in: [intel]), "Intel/Rosetta R does not satisfy the arm64 requirement")
        print("PASS: Intel/Rosetta R does not satisfy native R")
        let broken = try fixture("broken-Rscript", marker: "STATSDIRECT_NATIVE_R_READY", status: 1)
        precondition(!RRuntime.nativeReady(in: [broken]), "A failed R invocation is not accepted even with marker output")
        precondition(!RRuntime.nativeReady(in: [directory.appendingPathComponent("missing-Rscript").path]), "Missing R is rejected")
        print("PASS: failed and missing R probes are rejected")

        // The newest R wins, a native R before an Intel one, the earlier candidate when nothing else separates two.
        let framework = directory.appendingPathComponent("R.framework")
        func rscript(_ version: String) throws -> String {
            let bin = framework.appendingPathComponent("Versions/" + version + "/Resources/bin")
            try fm.createDirectory(at: bin, withIntermediateDirectories: true)
            let file = bin.appendingPathComponent("Rscript")
            try "#!/bin/sh\nexit 0\n".write(to: file, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
            return file.path
        }
        let older = try rscript("4.4-arm64"), newer = try rscript("4.6-arm64"), intelSeries = try rscript("4.7")
        try fm.createSymbolicLink(atPath: framework.appendingPathComponent("Versions/Current").path, withDestinationPath: "4.4-arm64")
        let current = framework.appendingPathComponent("Resources/bin/Rscript").path
        precondition(RRuntime.executable(in: [current]) == newer, "the newest native series wins over the framework's Current link: \(RRuntime.executable(in: [current]) ?? "nil")")
        precondition(RRuntime.executable(in: [current, native]) == newer && RRuntime.executable(in: [native, current]) == newer, "a versioned native R outranks a path whose version is unknown")
        precondition(RRuntime.version(ofRscript: newer) == [4, 6] && RRuntime.version(ofRscript: intelSeries) == [4, 7] && RRuntime.isNative(rscript: newer) && !RRuntime.isNative(rscript: intelSeries) && RRuntime.isNative(rscript: older), "versions and architectures read from the framework's folder names")
        precondition(RRuntime.version(ofRscript: "/opt/homebrew/Cellar/r/4.5.1_2/bin/Rscript") == [4, 5, 1] && RRuntime.isNative(rscript: "/opt/homebrew/Cellar/r/4.5.1_2/bin/Rscript") && !RRuntime.isNative(rscript: "/usr/local/Cellar/r/4.5.1/bin/Rscript"), "Homebrew versions read from the Cellar, Apple Silicon only under /opt/homebrew")
        precondition(RRuntime.executable(in: ["/does/not/exist", "/bin/sh"]) == "/bin/sh" && RRuntime.executable(in: ["/bin/sh", "/bin/zsh"]) == "/bin/sh", "paths saying nothing keep their candidate order")
        // A real binary is judged by its Mach-O header, whatever its folder is called: CRAN's arm64 4.6 sits in "4.6".
        let plainFolder = framework.appendingPathComponent("Versions/4.5/Resources/bin"); try fm.createDirectory(at: plainFolder, withIntermediateDirectories: true)
        try fm.copyItem(atPath: "/bin/sh", toPath: plainFolder.appendingPathComponent("Rscript").path)
        precondition(RRuntime.machOHasArm64(at: "/bin/sh") == true && RRuntime.machOHasArm64(at: newer) == nil, "a universal system binary carries arm64; a shell script is not a Mach-O image")
        precondition(RRuntime.isNative(rscript: plainFolder.appendingPathComponent("Rscript").path), "an arm64 Rscript in a folder without the -arm64 suffix is native")
        precondition(RRuntime.executable(in: [current]) == newer, "a native 4.6 still outranks a native 4.5 found by its header")
        print("PASS: the newest Apple Silicon R is chosen across framework versions and Homebrew, the candidate order breaking ties")

        // The console's stated minimum, named in its message; the script pane is not bound by it.
        let minimum = "\(RRuntime.consoleMinimum.major).\(RRuntime.consoleMinimum.minor)"
        precondition(RRuntime.consoleVersionProblem("4.6.1") == nil && RRuntime.consoleVersionProblem(minimum + ".0") == nil && RRuntime.consoleVersionProblem("5.0.0") == nil, "R at or above the minimum is accepted")
        let refused = RRuntime.consoleVersionProblem("4.1.3")
        precondition(refused?.contains("needs R " + minimum + " or later") == true && refused?.contains("this R is 4.1.3") == true, "an older R is refused with both versions named: \(refused ?? "nil")")
        precondition(RRuntime.consoleVersionProblem("")?.contains("did not report its version") == true, "a missing version is refused, not treated as new enough")
        print("PASS: the interactive console names its minimum R, " + minimum + ", and the version it found")
    }
}
