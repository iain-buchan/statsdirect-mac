# The last expression returns a private capture function held by the native worker.
# Its environment has baseenv() as its parent; learner globals cannot replace it.
local({
  directory <- Sys.getenv("STATSDIRECT_CONSOLE_PLOTS")
  if (!nzchar(directory)) stop("Missing console graphics directory")
  folder <- Sys.getenv("STATSDIRECT_R_FOLDER")
  if (!nzchar(folder)) folder <- path.expand("~/Library/Application Support/StatsDirect Viewer")
  library <- file.path(folder, "R Library")
  prototype_library <- Sys.getenv("STATSDIRECT_CONSOLE_R_LIBRARY")
  if (!nzchar(prototype_library))
    prototype_library <- path.expand("~/Library/Application Support/StatsDirect Console Prototype/R Library")
  libraries <- c(prototype_library, library)
  .libPaths(c(libraries[dir.exists(libraries)], .libPaths()))
  if (!requireNamespace("svglite", quietly = TRUE))
    stop("The SVG console requires svglite. Run Scripts/prepare-r-console-svg.sh for this prototype.")
  options(warn = 1)
  serial <- 0L
  device_serial <- 0L
  device_keys <- list()
  page_started <- list()
  page_numbers <- list()
  next_page <- list()
  last <- list()
  pending <- character()
  capturing <- FALSE

  device_key <- function(device = grDevices::dev.cur()) {
    generation <- device_keys[[as.character(device)]]
    if (is.null(generation)) return(NULL)
    paste(device, generation, sep = ":")
  }
  register_device <- function() {
    device <- grDevices::dev.cur()
    if (device == 1L || capturing) return(NULL)
    key <- device_key(device)
    if (is.null(key)) {
      # File devices normally disable their display lists. Enable one before
      # the first page, without replacing the user's device or output file.
      grDevices::dev.control(displaylist = "enable")
      device_serial <<- device_serial + 1L
      device_keys[[as.character(device)]] <<- device_serial
      key <- device_key(device)
      page_numbers[[key]] <<- 0L
      next_page[[key]] <<- TRUE
    }
    key
  }
  automatic_device <- function(...) invisible()
  # dev.new() filters arguments against the device's formal signature.
  formals(automatic_device) <- formals(grDevices::pdf)
  body(automatic_device) <- quote({
    args <- mget(as.character(names(as.list(match.call())[-1L])), envir = environment(), inherits = FALSE)
    if (!"file" %in% names(args))
      args$file <- file.path(directory, sprintf(".console-device-%06d.pdf", device_serial + 1L))
    do.call(grDevices::pdf, args)
    register_device()
    invisible()
  })
  options(device = automatic_device)

  capture_devices <- function(devices = grDevices::dev.list()) {
    if (capturing || !length(devices)) return(invisible())
    capturing <<- TRUE
    original <- grDevices::dev.cur()
    on.exit({
      if (original %in% grDevices::dev.list()) grDevices::dev.set(original)
      capturing <<- FALSE
    })
    for (device in devices) {
      if (!device %in% grDevices::dev.list()) next
      key <- device_key(device)
      if (is.null(key) || !isTRUE(page_started[[key]])) next
      copied <- NULL
      tryCatch({
        grDevices::dev.set(device)
        plot <- grDevices::recordPlot()
        if (is.null(plot[[1L]])) next
        # Page identity matters: two identical successive plots are two pages.
        snapshot <- list(page = page_numbers[[key]], bytes = serialize(plot, NULL, version = 2L))
        if (identical(last[[key]], snapshot)) next
        size <- grDevices::dev.size("in")
        serial <<- serial + 1L
        path <- file.path(directory, sprintf("console-plot-%06d.svg", serial))
        copied <- grDevices::dev.copy(svglite::svglite, file = path, width = size[1L], height = size[2L])
        grDevices::dev.off(copied)
        copied <- NULL
        last[[key]] <<- snapshot
        pending <<- c(pending, path)
      }, error = function(e) message("Plot preview unavailable: ", conditionMessage(e)),
      finally = {
        if (!is.null(copied) && copied %in% grDevices::dev.list())
          try(grDevices::dev.off(copied), silent = TRUE)
      })
    }
    invisible()
  }
  mark_page_started <- function() {
    if (capturing) return(invisible())
    key <- register_device()
    if (is.null(key)) return(invisible())
    if (!isTRUE(page_started[[key]]) || isTRUE(next_page[[key]]))
      page_numbers[[key]] <<- page_numbers[[key]] + 1L
    page_started[[key]] <<- TRUE
    next_page[[key]] <<- FALSE
    invisible()
  }
  before_base_page <- function() {
    if (capturing) return(invisible())
    key <- register_device()
    if (is.null(key)) return(invisible())
    # plot.new also begins mfrow/layout panels. Preserve only a completed
    # physical page, and only this device, never another device mid-drawing.
    if (isTRUE(page_started[[key]]) && isTRUE(graphics::par("page"))) {
      capture_devices(grDevices::dev.cur())
      next_page[[key]] <<- TRUE
    }
    invisible()
  }
  before_grid_page <- function() {
    if (capturing) return(invisible())
    key <- register_device()
    if (!is.null(key)) {
      if (isTRUE(page_started[[key]])) capture_devices(grDevices::dev.cur())
      next_page[[key]] <<- TRUE
    }
    invisible()
  }
  close_target <- function(which) {
    if (capturing || length(which) != 1L) return(NULL)
    # dev.off itself accepts scalar device IDs through as.integer(), including
    # character IDs. Use the same coercion without turning an invalid ID into
    # an error in the tracing hook.
    device <- suppressWarnings(tryCatch(as.integer(which), error = function(e) NA_integer_))
    if (length(device) != 1L || is.na(device) || device <= 1L) return(NULL)
    device
  }
  before_close <- function(which) {
    device <- close_target(which)
    if (!is.null(device) && device %in% grDevices::dev.list()) capture_devices(device)
    invisible()
  }
  after_close <- function(which) {
    device <- close_target(which)
    if (!is.null(device) && !device %in% grDevices::dev.list()) {
      key <- device_key(device)
      if (!is.null(key)) {
        page_started[[key]] <<- NULL
        page_numbers[[key]] <<- NULL
        next_page[[key]] <<- NULL
        last[[key]] <<- NULL
        device_keys[[as.character(device)]] <<- NULL
      }
    }
    invisible()
  }
  # Both bindings are required: an attached package can retain the untraced
  # exported function even after the namespace binding has been traced. The
  # tracers carry private closures, never names in the learner's .GlobalEnv.
  for (where in list(asNamespace("grDevices"), as.environment("package:grDevices")))
    suppressMessages(invisible(trace("dev.off", where = where, print = FALSE,
      tracer = substitute(HOOK(which), list(HOOK = before_close)),
      exit = substitute(HOOK(which), list(HOOK = after_close)))))
  # Preserve earlier pages when several plots are produced by one expression.
  setHook("before.plot.new", before_base_page, action = "append")
  setHook("plot.new", mark_page_started, action = "append")
  setHook("before.grid.newpage", before_grid_page, action = "append")
  setHook("grid.newpage", mark_page_started, action = "append")
  function() {
    capture_devices()
    result <- pending
    pending <<- character()
    result
  }
})
