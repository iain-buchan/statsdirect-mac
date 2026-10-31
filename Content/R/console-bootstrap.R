# The last expression returns a private capture function held by the native worker.
# Its environment has baseenv() as its parent; learner globals cannot replace it.
local({
  directory <- Sys.getenv("STATSDIRECT_CONSOLE_PLOTS")
  if (!nzchar(directory)) stop("Missing console graphics directory")
  folder <- Sys.getenv("STATSDIRECT_R_FOLDER")
  if (!nzchar(folder)) folder <- path.expand("~/Library/Application Support/StatsDirect Viewer")
  library <- file.path(folder, "R Library")
  if (dir.exists(library)) .libPaths(c(library, .libPaths()))
  options(warn = 1)
  serial <- 0L
  device_serial <- 0L
  device_keys <- list()
  page_started <- list()
  last <- list()
  pending <- character()
  capturing <- FALSE

  automatic_device <- function(...) {
    args <- list(...)
    device_serial <<- device_serial + 1L
    if (!"file" %in% names(args))
      args$file <- file.path(directory, sprintf(".console-device-%06d.pdf", device_serial))
    do.call(grDevices::pdf, args)
    grDevices::dev.control(displaylist = "enable")
    device_keys[[as.character(grDevices::dev.cur())]] <<- device_serial
    invisible()
  }
  # dev.new() filters arguments against the device's formal signature.
  formals(automatic_device) <- formals(grDevices::pdf)
  body(automatic_device) <- quote({
    args <- mget(as.character(names(as.list(match.call())[-1L])), envir = environment(), inherits = FALSE)
    device_serial <<- device_serial + 1L
    if (!"file" %in% names(args))
      args$file <- file.path(directory, sprintf(".console-device-%06d.pdf", device_serial))
    do.call(grDevices::pdf, args)
    grDevices::dev.control(displaylist = "enable")
    device_keys[[as.character(grDevices::dev.cur())]] <<- device_serial
    invisible()
  })
  options(device = automatic_device)

  capture_current <- function() {
    if (capturing || is.null(grDevices::dev.list())) return(invisible())
    capturing <<- TRUE
    original <- grDevices::dev.cur()
    on.exit({
      if (original %in% grDevices::dev.list()) grDevices::dev.set(original)
      capturing <<- FALSE
    })
    for (device in grDevices::dev.list()) {
      tryCatch({
        grDevices::dev.set(device)
        plot <- grDevices::recordPlot()
        if (is.null(plot[[1L]])) next
        key <- paste(device, device_keys[[as.character(device)]] %||% "explicit", sep = ":")
        bytes <- serialize(plot, NULL, version = 2L)
        if (identical(last[[key]], bytes)) next
        size <- grDevices::dev.size("in")
        serial <<- serial + 1L
        path <- file.path(directory, sprintf("console-plot-%06d.pdf", serial))
        copied <- grDevices::dev.copy(grDevices::pdf, file = path, width = size[1L], height = size[2L], onefile = TRUE)
        grDevices::dev.off(copied)
        last[[key]] <<- bytes
        pending <<- c(pending, path)
      }, error = function(e) message("Plot preview unavailable: ", conditionMessage(e)))
    }
    invisible()
  }
  `%||%` <- function(left, right) if (is.null(left)) right else left
  page_key <- function() {
    device <- grDevices::dev.cur()
    paste(device, device_keys[[as.character(device)]] %||% "explicit", sep = ":")
  }
  mark_page_started <- function() {
    if (!capturing && !is.null(grDevices::dev.list()))
      page_started[[page_key()]] <<- TRUE
    invisible()
  }
  before_base_page <- function() {
    if (capturing || is.null(grDevices::dev.list())) return(invisible())
    # plot.new also begins each mfrow/layout panel. Only preserve a completed
    # physical page, and never a par()-only display list before the first plot.
    if (isTRUE(page_started[[page_key()]]) && isTRUE(graphics::par("page")))
      capture_current()
    invisible()
  }
  # Preserve earlier pages when several plots are produced by one expression.
  setHook("before.plot.new", before_base_page, action = "append")
  setHook("plot.new", mark_page_started, action = "append")
  setHook("before.grid.newpage", capture_current, action = "append")
  setHook("grid.newpage", mark_page_started, action = "append")
  function() {
    capture_current()
    result <- pending
    pending <<- character()
    result
  }
})
