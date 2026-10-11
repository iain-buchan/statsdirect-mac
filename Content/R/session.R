# Persistent local R session. Each submitted script gets a headless PDF device;
# the Mac host displays new/updated plot files after the completion marker.
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
      args$file <- file.path(session_directory, sprintf("plots-%04d-%03d.pdf", run_number, plot_number))
      if (is.null(args$width)) args$width <- 8
      if (is.null(args$height)) args$height <- 5
      args$onefile <- TRUE
      do.call(grDevices::pdf, args)
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
