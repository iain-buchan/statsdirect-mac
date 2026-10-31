import Cocoa

@MainActor enum RExternalScript {
    nonisolated(unsafe) static var opensExternally = true
    static var scriptsFolder: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("StatsDirect Viewer/R Scripts", isDirectory: true) }

    static func save(_ source: String, name: String) throws -> URL {
        var name = name.components(separatedBy: CharacterSet(charactersIn: "/:")).joined(separator: "_").trimmingCharacters(in: .whitespaces)
        if name.isEmpty { name = "Script" }
        if (name as NSString).pathExtension.lowercased() != "r" { name += ".R" }
        let url = scriptsFolder.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: scriptsFolder, withIntermediateDirectories: true)
        try source.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Each external window receives immutable source, even when another tab
    /// saves the same title while installation or application launch is pending.
    static func snapshot(_ url: URL, source: String? = nil, workingDirectory: URL) throws -> URL {
        let directory = workingDirectory.appendingPathComponent("External R-" + UUID().uuidString, isDirectory: true)
        let copy = directory.appendingPathComponent(url.lastPathComponent)
        let data = try source.map { Data($0.utf8) } ?? Data(contentsOf: url)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: copy, options: .atomic)
        return copy
    }

    static func launch(_ url: URL, source: String? = nil, workingDirectory: URL, status: @escaping @MainActor (String) -> Void) {
        let script: URL
        do { script = try snapshot(url, source: source, workingDirectory: workingDirectory) }
        catch { status("Open in R failed: \(error.localizedDescription)"); return }
        let workspace = NSWorkspace.shared
        let completed: @Sendable (NSRunningApplication?, Error?) -> Void = { application, error in
            DispatchQueue.main.async {
                if let error { status("Open in R failed: \(error.localizedDescription). Your script is saved in R Scripts.") }
                else { status("Opened \(url.lastPathComponent) in \(application?.localizedName ?? "R")") }
            }
        }
        if let rstudio = workspace.urlForApplication(withBundleIdentifier: "org.rstudio.RStudio") ?? workspace.urlForApplication(withBundleIdentifier: "com.rstudio.desktop") {
            status("Opening script in RStudio…")
            workspace.open([script], withApplicationAt: rstudio, configuration: NSWorkspace.OpenConfiguration(), completionHandler: completed)
        } else if let r = workspace.urlForApplication(withBundleIdentifier: "org.R-project.R") {
            do {
                let session = try RExternalSession(script: script, directory: script.deletingLastPathComponent())
                status("Starting R and running the script…")
                workspace.open([session.directory], withApplicationAt: r, configuration: session.configuration(), completionHandler: completed)
            } catch { status("Open in R failed: \(error.localizedDescription)") }
        } else { status("Saved \(url.lastPathComponent) in R Scripts; install RStudio or R to open it") }
    }
}

/// A private startup profile for a new R.app process. Merely opening an .R file
/// in R.app opens its editor; the profile also runs it, as the Windows host does.
/// Never change the user's .Rprofile or replace an existing R workspace.
struct RExternalSession {
    let directory: URL
    let script: URL
    let profile: URL

    init(script source: URL, directory: URL) throws {
        self.directory = directory
        script = directory.appendingPathComponent(source.lastPathComponent)
        profile = directory.appendingPathComponent("startup.R")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(contentsOf: source).write(to: script, options: .atomic)
        func literal(_ value: String) throws -> String {
            String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .withoutEscapingSlashes]), as: UTF8.self)
        }
        let text = """
        # Only this R process uses the StatsDirect startup profile.
        Sys.unsetenv("R_PROFILE_USER")
        .First <- local({
          started <- FALSE
          function() {
            if (started) return(invisible(NULL))
            started <<- TRUE
            # Only base is attached when R calls .First.
            for (package in getOption("defaultPackages"))
              suppressPackageStartupMessages(require(package, character.only = TRUE))
            folder <- Sys.getenv("STATSDIRECT_R_FOLDER", unset = path.expand("~/Library/Application Support/StatsDirect Viewer"))
            library <- file.path(folder, "R Library")
            if (dir.exists(library)) .libPaths(c(library, .libPaths()))
            setwd(\(try literal(directory.path)))
            file <- \(try literal(script.path))
            cat("\\nStatsDirect: running ", basename(file), "\\n", sep = "")
            tryCatch(source(file, local = .GlobalEnv, echo = TRUE, print.eval = TRUE,
                            max.deparse.length = Inf, spaced = FALSE, encoding = "UTF-8"),
                     error = function(e) message("StatsDirect script: ", conditionMessage(e)))
            if (interactive()) try(utils::file.edit(file), silent = TRUE)
            invisible(NULL)
          }
        })
        """
        // R's startup parser requires a final newline to evaluate the last
        // expression (source() alone would not expose this difference).
        try (text + "\n").write(to: profile, atomically: true, encoding: .utf8)
    }

    @MainActor func configuration() -> NSWorkspace.OpenConfiguration {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.environment = ["R_PROFILE_USER": profile.path]
        return configuration
    }
}
