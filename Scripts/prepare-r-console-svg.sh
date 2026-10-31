#!/bin/bash
# Development prototype only: install the SVG device in its own R library.
set -euo pipefail
cd "$(dirname "$0")/.."
R_SCRIPT="${R_SCRIPT:-/usr/local/bin/Rscript}"
PROTOTYPE_LIBRARY="${STATSDIRECT_CONSOLE_R_LIBRARY:-$HOME/Library/Application Support/StatsDirect Console Prototype/R Library}"
"$R_SCRIPT" --vanilla - "$PROTOTYPE_LIBRARY" <<'RSCRIPT'
library_path <- commandArgs(trailingOnly = TRUE)[1L]
dir.create(library_path, recursive = TRUE, showWarnings = FALSE)
.libPaths(c(library_path, .Library))
if (!requireNamespace("svglite", quietly = TRUE)) {
  if (.Platform$OS.type != "unix" || Sys.info()[["sysname"]] != "Darwin")
    stop("This preparation script targets the Mac console prototype")
  install.packages("svglite", lib = library_path, repos = "https://cloud.r-project.org",
                   dependencies = NA, type = "binary")
}
if (!requireNamespace("svglite", quietly = TRUE)) stop("The SVG device could not be installed")
probe <- tempfile(fileext = ".svg")
tryCatch({
  svglite::svglite(probe)
  plot(1:3, main = "StatsDirect SVG device check")
  dev.off()
  svg <- paste(readLines(probe, warn = FALSE), collapse = "\n")
  if (!grepl("<svg", svg, fixed = TRUE) || !grepl("StatsDirect SVG device check", svg, fixed = TRUE))
    stop("The prototype SVG device did not create a complete vector chart")
}, finally = unlink(probe))
cat("Prototype SVG device:", as.character(packageVersion("svglite")), "\nLibrary:", find.package("svglite"), "\n")
RSCRIPT
