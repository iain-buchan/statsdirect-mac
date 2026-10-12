import Cocoa

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
