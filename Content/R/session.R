# Persistent local R session. A plot drawn without a device of its own goes to an SVG file, one per page, which the
# pane draws after the completion marker (as the Windows script window does; R's own default for a run is a PDF),
# or to a PDF when the svglite package is not in the program's library.
options(warn = 1)
# The program keeps a library for the packages its R operations install (svglite for charts, mcr for method comparison
# regression) beside its runs; a script continued here finds them too. STATSDIRECT_R_FOLDER moves the folder, as for those runs.
local({
  folder <- Sys.getenv("STATSDIRECT_R_FOLDER")
  if (!nzchar(folder)) folder <- path.expand("~/Library/Application Support/StatsDirect Viewer")
  rlib <- file.path(folder, "R Library")
  dir.create(rlib, recursive = TRUE, showWarnings = FALSE)
  .libPaths(c(rlib, .libPaths()))
})
cat(R.version.string, "\n", sep = "")
cat("Working directory: ", getwd(), "\n", sep = "")
local({
  marker <- commandArgs(trailingOnly = TRUE)[1]
  session_directory <- getwd()
  input <- file("stdin", open = "r")
  run_number <- 0L
  repeat {
    path <- readLines(input, n = 1, warn = FALSE)
    if (!length(path)) break
    run_number <- run_number + 1L
    plot_number <- 0L
    options(device = function(...) {
      args <- list(...)
      plot_number <<- plot_number + 1L
      name <- file.path(session_directory, sprintf("plots-%04d-%03d", run_number, plot_number))
      if (requireNamespace("svglite", quietly = TRUE)) {
        # svglite, which the program's library carries for its charts, since R's own svg() needs X11's Cairo on a Mac;
        # one device per plot number and one file per page, so a second device in a run cannot overwrite the first's pages
        args$filename <- paste0(name, "-%03d.svg")
        if (is.null(args$width)) args$width <- 7
        if (is.null(args$height)) args$height <- 7
        do.call(svglite::svglite, args)
      } else {
        args$file <- paste0(name, ".pdf")
        if (is.null(args$width)) args$width <- 8
        if (is.null(args$height)) args$height <- 5
        args$onefile <- TRUE
        do.call(grDevices::pdf, args)
      }
    })
    devices_before <- grDevices::dev.list()
    tryCatch(source(path, local = .GlobalEnv, echo = TRUE, print.eval = TRUE),
      error = function(e) cat("Error: ", conditionMessage(e), "\n", sep = ""),
      interrupt = function(e) cat("Interrupted\n"))
    # Flush every device opened by this run, including explicitly named PDFs,
    # even after an R error. This leaves complete files for the output pane.
    for (device in setdiff(grDevices::dev.list(), devices_before)) {
      tryCatch(grDevices::dev.off(device), error = function(e) NULL)
    }
    unlink(path)
    cat("\n", marker, "\n", sep = "")
    flush.console()
  }
  close(input)
})
