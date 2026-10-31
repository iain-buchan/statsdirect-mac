# Focused device-lifecycle regression checks. No UI or learner files are used.
# Rscript --vanilla Tests/r-console-device-capture.R [bootstrap path]
local({
  args <- commandArgs(trailingOnly = TRUE)
  bootstrap <- if (length(args)) args[[1L]] else "Content/R/console-bootstrap.R"
  folder <- tempfile("statsdirect-console-devices-")
  dir.create(folder)
  on.exit(unlink(folder, recursive = TRUE), add = TRUE)
  Sys.setenv(STATSDIRECT_CONSOLE_PLOTS = folder)
  capture <- eval(parse(bootstrap), envir = new.env(parent = baseenv()))
  run <- function(code) {
    eval(parse(text = code), envir = .GlobalEnv)
    paths <- capture()
    stopifnot(all(file.exists(paths)))
    paths
  }
  label <- function(paths, text) {
    any(vapply(paths, function(path) grepl(text, paste(readLines(path, warn = FALSE), collapse = "\n"), fixed = TRUE), logical(1)))
  }
  check <- function(ok, name) {
    if (!isTRUE(ok)) stop("FAIL: ", name, call. = FALSE)
    cat("PASS: ", name, "\n", sep = "")
  }
  # One submitted chart may add several layers before its device is closed.
  paths <- run('plot(1:3, main="Closed automatic"); abline(0, 1); grDevices::dev.off()')
  check(length(paths) == 1L && label(paths, "Closed automatic"), "qualified dev.off retains one finished automatic page")
  paths <- run('plot(1:3, main="Character device ID"); grDevices::dev.off(as.character(dev.cur()))')
  check(length(paths) == 1L && label(paths, "Character device ID"), "R-compatible character device IDs retain the closing page")
  paths <- run('pdf(NULL); plot(1:4, main="Reused after character close"); dev.off()')
  check(length(paths) == 1L && label(paths, "Reused after character close"), "character device close retires identity before device reuse")
  check(length(run('dev.new(); par(mfrow=c(2,2)); dev.off()')) == 0L, "blank and par-only devices produce no previews")
  paths <- run('plot(1:3, main="First device"); dev.new(); plot(4:6, main="Second device"); graphics.off()')
  check(length(paths) == 2L && label(paths, "First device") && label(paths, "Second device"), "graphics.off captures each completed device once")
  # Quartz is macOS's native bitmap device. The bundled R Cairo device can
  # require optional XQuartz libraries; SVG uses the existing svglite package.
  for (kind in c("pdf", "png", "svg")) {
    file <- file.path(folder, paste0("user-file.", kind))
    call <- switch(kind,
      pdf = sprintf('grDevices::pdf(%s)', dQuote(file, FALSE)),
      png = sprintf('grDevices::png(%s, type="quartz")', dQuote(file, FALSE)),
      svg = sprintf('svglite::svglite(%s)', dQuote(file, FALSE)))
    paths <- run(paste0(call, '; plot(1:3, main="Named ', kind, '"); dev.off()'))
    check(length(paths) == 1L && label(paths, paste("Named", kind)), paste("explicit named", kind, "has one inline preview"))
    bytes <- readBin(file, "raw", n = 8L)
    valid <- switch(kind, pdf = identical(bytes[1:4], charToRaw("%PDF")),
      png = identical(bytes, as.raw(c(137,80,78,71,13,10,26,10))),
      svg = any(grepl("<svg", readLines(file, warn = FALSE), fixed = TRUE)))
    check(file.exists(file) && isTRUE(valid), paste("explicit named", kind, "file is preserved"))
    grid_file <- file.path(folder, paste0("grid-file.", kind))
    grid_call <- sub(file, grid_file, call, fixed = TRUE)
    paths <- run(paste0(grid_call, '; grid::grid.newpage(); grid::grid.text("Named grid ', kind, '"); grDevices::dev.off()'))
    check(length(paths) == 1L && label(paths, paste("Named grid", kind)) && file.info(grid_file)$size > 0,
      paste("explicit named", kind, "also retains grid drawing and output file"))
  }
  paths <- run('plot(1:3, main="Closed target"); target <- dev.cur(); dev.new(); plot(1:3, main="Still current"); dev.off(target); mtext("Finished current")')
  check(length(paths) == 2L && sum(vapply(paths, function(path) label(path, "Still current"), logical(1))) == 1L && label(paths, "Finished current"), "closing a noncurrent device does not snapshot another unfinished page")
  check(length(capture()) == 0L, "unchanged open device is not duplicated")
  run('graphics.off()')
  paths <- run('plot(1:3, main="Other device"); target <- dev.cur(); dev.new(); for (i in 1:2) plot(1:3, main=paste("New page",i)); dev.set(target); mtext("Final other annotation"); graphics.off()')
  check(length(paths) == 3L && sum(vapply(paths, function(path) label(path, "Other device"), logical(1))) == 1L && label(paths, "Final other annotation"),
    "page transitions do not snapshot another device before its final annotation")
  paths <- run('for (i in 1:2) { pdf(NULL); plot(1:3, main="Reused device"); dev.off() }')
  check(length(paths) == 2L, "reused device numbers retain identical new plots")
  paths <- run('for (i in 1:2) plot(1:3, main="Repeated page"); dev.off()')
  check(length(paths) == 2L && all(vapply(paths, label, logical(1), text = "Repeated page")), "identical physical pages are each captured once")
  paths <- run('par(mfrow=c(2,2)); for (i in 1:4) plot(1:3, main=paste("Panel",i)); dev.off()')
  check(length(paths) == 1L && label(paths, "Panel 1") && label(paths, "Panel 4"), "multipanel page is retained once without partial snapshots")
  paths <- run('plot(1:9, main="Paired chart"); abline(h=5); mtext("Final annotation")')
  check(length(paths) == 1L && label(paths, "Final annotation"), "submission captures one fully annotated chart")
  check(length(run('1 + 1')) == 0L, "non-graphics commands do not duplicate unchanged charts")
  run('graphics.off()')
  paths <- run('rm(list=ls(all.names=TRUE), envir=.GlobalEnv); plot(1:3, main="Private capture survives"); dev.off()')
  check(length(paths) == 1L && label(paths, "Private capture survives"), "clearing learner globals preserves private capture state")
  # Grid uses a distinct new-page hook and must retain pages on closure too.
  paths <- run('grid::grid.newpage(); grid::grid.text("Grid final page"); dev.off()')
  check(length(paths) == 1L && label(paths, "Grid final page"), "grid completed page survives device closure")
  paths <- run('for (i in 1:2) { grid::grid.newpage(); grid::grid.text("Repeated grid page") }; graphics.off()')
  check(length(paths) == 2L && all(vapply(paths, label, logical(1), text = "Repeated grid page")), "identical grid pages are each captured once")
  cat("All R console device checks passed.\n")
})
