# First-use chart support. Installs only CRAN Mac binaries in the supplied
# StatsDirect library, never in the learner's default R library.
local({
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) < 2L || !args[[1L]] %in% c("--probe", "--install"))
    stop("Invalid R chart setup request")
  mode <- args[[1L]]
  if (Sys.info()[["sysname"]] == "Darwin" && !R.version$arch %in% c("arm64", "aarch64")) {
    message("StatsDirect needs native Apple Silicon R, not Intel R running through Rosetta.")
    quit(save = "no", status = 24L, runLast = FALSE)
  }
  library <- normalizePath(args[[2L]], mustWork = FALSE)
  .libPaths(c(library, .Library), include.site = FALSE)
  compatible <- function() {
    if (!requireNamespace("svglite", quietly = TRUE)) return(FALSE)
    version <- getNamespaceVersion("svglite")
    version >= package_version("2.2.2") && version < package_version("3.0.0")
  }
  verify <- function() {
    if (!compatible()) return(FALSE)
    probe <- tempfile(fileext = ".svg")
    device <- NULL
    on.exit({
      if (!is.null(device) && device %in% grDevices::dev.list()) try(grDevices::dev.off(device), silent = TRUE)
      unlink(probe)
    }, add = TRUE)
    svglite::svglite(probe)
    device <- grDevices::dev.cur()
    graphics::plot(1:3, main = "StatsDirect R chart support")
    grDevices::dev.off(device); device <- NULL
    svg <- paste(readLines(probe, warn = FALSE), collapse = "\n")
    grepl("<svg", svg, fixed = TRUE) && grepl("StatsDirect R chart support", svg, fixed = TRUE)
  }
  if (mode == "--probe") {
    ready <- tryCatch(verify(), error = function(e) { message("R chart support check: ", conditionMessage(e)); FALSE })
    if (!isTRUE(ready)) quit(save = "no", status = 23L, runLast = FALSE)
    cat("STATSDIRECT_CONSOLE_READY svglite=", as.character(getNamespaceVersion("svglite")), "\n", sep = "")
  } else {
    if (Sys.info()[["sysname"]] != "Darwin")
      stop("Automatic R chart setup requires the Mac version of R")
    if (length(args) != 3L) stop("Missing private setup directory")
    staging <- normalizePath(args[[3L]], mustWork = TRUE)
    dir.create(library, recursive = TRUE, showWarnings = FALSE)
    .libPaths(c(staging, library, .Library), include.site = FALSE)
    options(timeout = 60, pkgType = "binary", repos = c(CRAN = "https://cran.r-project.org"))
    utils::install.packages("svglite", lib = staging, repos = "https://cran.r-project.org",
                     dependencies = NA, type = "binary", quiet = TRUE)
    if (!isTRUE(verify())) stop("R chart support did not pass its SVG check")
    # Publish complete package directories only after the staging smoke check.
    # Backups permit the native helper to restore an interrupted replacement.
    packages <- list.dirs(staging, full.names = FALSE, recursive = FALSE)
    packages <- packages[!startsWith(packages, ".") & !startsWith(packages, "00LOCK")]
    for (package in packages) {
      source <- file.path(staging, package)
      if (!file.exists(file.path(source, "DESCRIPTION"))) next
      target <- file.path(library, package)
      backup <- file.path(staging, paste0(".backup-", package))
      if (dir.exists(target) && !file.rename(target, backup))
        stop("The private R chart library is in use. Try again after closing R sessions.")
      if (!file.rename(source, target)) {
        if (dir.exists(backup)) file.rename(backup, target)
        stop("The private R chart library could not be updated")
      }
    }
    cat("STATSDIRECT_CONSOLE_INSTALLED\n")
  }
})
