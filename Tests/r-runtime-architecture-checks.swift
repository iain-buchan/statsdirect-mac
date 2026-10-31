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
    }
}
