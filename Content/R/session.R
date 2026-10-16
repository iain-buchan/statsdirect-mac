# Persistent local R session. Ordinary plots go to a multipage PDF per device;
# the pane displays every page after the completion marker. Report charts use
# their separate SVG path, and a script can still open an explicit graphics device.
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
    automatic_device <- function(...) {
      # Forward only arguments supplied by the caller; pdf() applies its own
      # defaults, including pdf.options(), and accepts an explicit file=NULL.
      args <- mget(as.character(names(as.list(match.call())[-1L])), envir = environment(), inherits = FALSE)
      plot_number <<- plot_number + 1L
      # Each run/device owns its file, so later plots cannot replace earlier output.
      if (!"file" %in% names(args)) {
        name <- file.path(session_directory, sprintf("plots-%04d-%03d", run_number, plot_number))
        onefile <- if ("onefile" %in% names(args)) args$onefile else grDevices::pdf.options()$onefile
        args$file <- paste0(name, if (isTRUE(onefile)) ".pdf" else "-%03d.pdf")
      }
      do.call(grDevices::pdf, args)
    }
    # dev.new() discards arguments absent from the device's formal signature.
    formals(automatic_device) <- formals(grDevices::pdf)
    options(device = automatic_device)
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
