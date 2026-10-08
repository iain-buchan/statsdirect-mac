# Base-R data-file exchange for the grid. No packages or user profiles required.
#
# Tables cross to and from the application as an exchange folder with one file per column:
# text as percent-escaped lines (%25, %0A, %0D), flags as raw bytes and numbers as
# little-endian doubles, all read and written in bulk, so a table of Excel's full height
# costs no per-cell work here.
args <- commandArgs(trailingOnly=TRUE)
fail <- function(message) stop(message, call.=FALSE)
json_string <- function(x) {
  escape <- function(x) {
    codes <- utf8ToInt(enc2utf8(x))
    paste0('"', paste0(vapply(codes, function(n) {
      if (n == 34L) '\\"' else if (n == 92L) '\\\\' else if (n < 32L) sprintf('\\u%04x', n) else intToUtf8(n)
    }, character(1)), collapse=''), '"')
  }
  vapply(x, escape, character(1), USE.NAMES=FALSE)
}
json <- function(x) {
  if (is.null(x)) return('null')
  if (is.list(x)) {
    parts <- vapply(x, json, character(1))
    if (!is.null(names(x))) return(paste0('{', paste0(json_string(names(x)), ':', parts, collapse=','), '}'))
    return(paste0('[', paste0(parts, collapse=','), ']'))
  }
  if (length(x) != 1L) return(json(unname(as.list(x))))
  if (is.na(x)) return('null')
  if (is.character(x)) return(json_string(x))
  if (is.logical(x)) return(if (x) 'true' else 'false')
  format(x, scientific=FALSE, trim=TRUE, digits=17)
}
column_type <- function(x) {
  if (!is.null(dim(x))) return(NA_character_)   # a matrix column is not one variable
  if (is.factor(x)) 'factor' else if (inherits(x, 'Date')) 'Date' else if (inherits(x, 'POSIXct')) 'POSIXct'
  else if (is.object(x)) NA_character_ else if (is.integer(x)) 'integer' else if (is.double(x)) 'double'
  else if (is.logical(x)) 'logical' else if (is.character(x)) 'character' else NA_character_
}
escape_lines <- function(x) {
  x <- enc2utf8(as.character(x)); x[is.na(x)] <- ''
  gsub('\r', '%0D', gsub('\n', '%0A', gsub('%', '%25', x, fixed=TRUE), fixed=TRUE), fixed=TRUE)
}
# A value's leading byte-order mark travels as %EF%BB%BF, because readLines would drop it from the first line of a file.
unescape_lines <- function(x) gsub('%25', '%', gsub('%EF%BB%BF', '\ufeff', gsub('%0D', '\r', gsub('%0A', '\n', x, fixed=TRUE), fixed=TRUE), fixed=TRUE), fixed=TRUE)
write_lines <- function(x, path) { con <- file(path, 'wb'); on.exit(close(con)); writeLines(escape_lines(x), con, useBytes=TRUE) }
read_lines <- function(path, n=NA) {
  if (!file.exists(path)) { if (is.na(n)) return(character()) else fail(paste('Missing exchange file', basename(path))) }
  x <- readLines(path, encoding='UTF-8', warn=FALSE)
  if (!is.na(n) && length(x) != n) fail(sprintf('%s holds %d values where %d were expected.', basename(path), length(x), n))
  unescape_lines(x)
}
write_doubles <- function(x, path) { con <- file(path, 'wb'); on.exit(close(con)); writeBin(as.double(x), con, size=8, endian='little') }
read_doubles <- function(path, n) {
  con <- file(path, 'rb'); on.exit(close(con)); x <- readBin(con, 'double', n=n, size=8, endian='little')
  if (length(x) != n) fail(paste('Short exchange file', basename(path))); x
}
write_bytes <- function(x, path) { con <- file(path, 'wb'); on.exit(close(con)); writeBin(as.raw(as.integer(x)), con) }
read_bytes <- function(path, n) {
  if (!file.exists(path)) return(rep(FALSE, n))
  con <- file(path, 'rb'); on.exit(close(con)); x <- readBin(con, 'raw', n=n)
  if (length(x) != n) fail(paste('Short exchange file', basename(path))); x == as.raw(1)
}
read_files <- function(path, folder) {
  if (tolower(tools::file_ext(path)) == 'rds') {
    objects <- list(readRDS(path)); names(objects) <- tools::file_path_sans_ext(basename(path))
  } else {
    env <- new.env(parent=emptyenv()); object_names <- load(path, envir=env)
    objects <- mget(object_names, envir=env, inherits=FALSE)
  }
  tables <- list(); skipped <- character(); t <- 0L
  for (object_name in names(objects)) {
    x <- objects[[object_name]]
    object_type <- if (is.matrix(x)) 'matrix' else 'data.frame'
    if (is.matrix(x) && (is.numeric(x) || is.character(x) || is.logical(x))) x <- as.data.frame(x, stringsAsFactors=FALSE, optional=TRUE)
    if (!is.data.frame(x)) { skipped <- c(skipped, paste0(object_name, ' (not a data frame or matrix)')); next }
    types <- vapply(x, column_type, character(1))
    if (anyNA(types) || ncol(x) == 0L) { skipped <- c(skipped, paste0(object_name, ' (unsupported or empty columns)')); next }
    n <- nrow(x)
    if (n+1L > 1048576L || ncol(x) > 16384L) fail(paste('Table exceeds Excel dimensions:', object_name))
    columns <- vector('list', ncol(x))
    for (c in seq_along(x)) {
      column <- x[[c]]; type <- types[c]
      tz <- attr(column, 'tzone'); if (is.null(tz) || !length(tz)) tz <- ''
      lev <- levels(column)
      columns[[c]] <- list(name=names(x)[c], type=type, levels=unname(as.list(lev[!is.na(lev)])), naLevel=anyNA(lev), ordered=is.ordered(column), tzone=tz[1])
      nan <- if (is.double(column)) is.nan(column) else rep(FALSE, n)
      missing <- is.na(column) & !nan
      base <- file.path(folder, sprintf('col-%d-%d', t, c-1L))
      if (type %in% c('double', 'integer')) {
        v <- as.double(column); finite <- is.finite(v)
        kinds <- ifelse(missing, 0L, ifelse(finite, 1L, 2L))
        text <- ifelse(finite | missing, '', as.character(v))
        write_doubles(ifelse(finite, v, NaN), paste0(base, '.nums'))
      } else if (type == 'logical') {
        kinds <- ifelse(missing, 0L, 5L); text <- ifelse(missing, '', ifelse(column, 'TRUE', 'FALSE'))
      } else if (type == 'Date') {
        kinds <- ifelse(missing, 0L, 3L); text <- ifelse(missing, '', format(column, '%Y-%m-%d'))
        num <- as.numeric(column); back <- suppressWarnings(as.numeric(as.Date(text, format='%Y-%m-%d')))
        raw <- ifelse(!missing & (!is.finite(num) | is.na(back) | back != num), num, NaN)
        if (any(!is.nan(raw))) write_doubles(raw, paste0(base, '.raw'))
      } else if (type == 'POSIXct') {
        kinds <- ifelse(missing, 0L, 3L); text <- ifelse(missing, '', format(column, '%Y-%m-%dT%H:%M:%OS6Z', tz='UTC'))
        num <- as.numeric(column); back <- suppressWarnings(as.numeric(as.POSIXct(sub('Z$', '', text), format='%Y-%m-%dT%H:%M:%OS', tz='UTC')))
        raw <- ifelse(!missing & (!is.finite(num) | is.na(back) | back != num), num, NaN)
        if (any(!is.nan(raw))) write_doubles(raw, paste0(base, '.raw'))
      } else {
        text <- as.character(column); missing <- missing | is.na(text)   # a factor's NA level is missing too
        kinds <- ifelse(missing, 0L, 2L); text[missing] <- ''
        write_bytes(missing, paste0(base, '.missing'))
      }
      write_bytes(kinds, paste0(base, '.kinds'))
      write_lines(text, paste0(base, '.txt'))
    }
    automatic <- .row_names_info(x) < 0L
    if (!automatic) write_lines(row.names(x), file.path(folder, sprintf('rows-%d.txt', t)))
    tables[[length(tables)+1L]] <- list(name=object_name, object=object_name, shape=object_type, rows=n, columns=columns, rowNames=!automatic,
      rowNamesType=if (is.integer(attr(x, 'row.names'))) 'integer' else 'character')
    t <- t + 1L
  }
  if (!length(tables)) fail(paste('No supported tables found.', paste(skipped, collapse='; ')))
  writeLines(json(list(name=basename(path), warnings=unname(as.list(skipped)), tables=tables)), file.path(folder, 'manifest.json'), useBytes=TRUE)
}
read_manifest <- function(path) read.csv(path, header=TRUE, colClasses='character', na.strings=NULL, check.names=FALSE, stringsAsFactors=FALSE, fileEncoding='UTF-8', blank.lines.skip=FALSE)
write_files <- function(folder, destination, format) {
  manifest <- read_manifest(file.path(folder, 'manifest.csv'))
  objects <- list()
  for (table in unique(manifest$table)) {
    meta <- manifest[manifest$table == table,,drop=FALSE]; columns <- list()
    n <- as.integer(meta$rows[1])
    column_names <- read_lines(file.path(folder, paste0('names-', table, '.txt')), nrow(meta))
    for (i in seq_len(nrow(meta))) {
      m <- meta[i,,drop=FALSE]; m$name <- column_names[i]; base <- file.path(folder, paste0('col-', table, '-', m$column))
      text <- read_lines(paste0(base, '.txt'), n); missing <- read_bytes(paste0(base, '.missing'), n); type <- m$type
      invalid <- function(bad) { if (any(bad & !missing)) fail(paste0('Invalid ',type,' value in ', m$object, ' / ', m$name, ', row ', which(bad & !missing)[1], '.')) }
      if (type %in% c('double','integer')) {
        value <- read_doubles(paste0(base, '.nums'), n); need <- is.na(value)
        parsed <- suppressWarnings(as.numeric(text[need]))
        bad <- rep(FALSE, n); bad[need] <- is.na(parsed) & !(text[need] %in% c('NaN','NA','')); invalid(bad)
        value[need] <- parsed
        if (type == 'integer') { invalid(!is.na(value) & (!is.finite(value) | value != trunc(value) | value > .Machine$integer.max | value < -.Machine$integer.max)); value <- as.integer(value) }
      } else if (type == 'logical') {
        invalid(!(toupper(text) %in% c('TRUE','FALSE','T','F','1','0','')))
        value <- toupper(text) %in% c('TRUE','T','1'); missing <- missing | text == ''
      } else if (type == 'factor') {
        lev <- read_lines(file.path(folder, paste0('levels-', table, '-', m$column, '.txt')))
        value <- factor(text, levels=unique(c(lev, text[!missing])), ordered=m$ordered == 'true')
        if (identical(m$naLevel, 'true')) value <- addNA(value)
      } else if (type %in% c('Date','POSIXct')) {
        missing <- missing | text == ''; rawText <- read_lines(paste0(base, '.raw'), n)
        infinite <- !nzchar(rawText) & text %in% c('Inf', '-Inf'); rawText[infinite] <- text[infinite]
        has_raw <- nzchar(rawText)
        raw <- suppressWarnings(as.numeric(rawText))
        if (type == 'Date') {
          value <- as.Date(rep(NA_real_,length(text)), origin='1970-01-01')
          value[has_raw] <- as.Date(raw[has_raw],origin='1970-01-01')
          idx <- !has_raw & !missing; invalid(!has_raw & !grepl('^[0-9]{4}-[0-9]{2}-[0-9]{2}$',text))
          value[idx] <- suppressWarnings(as.Date(text[idx],format='%Y-%m-%d'))
        } else {
          value <- as.POSIXct(rep(NA_real_,length(text)),origin='1970-01-01',tz='UTC')
          value[has_raw] <- as.POSIXct(raw[has_raw],origin='1970-01-01',tz='UTC')
          idx <- !has_raw & !missing
          normalized <- sub('Z$','',sub(' ','T',text))
          invalid(!has_raw & !grepl('^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?$',normalized))
          value[idx] <- suppressWarnings(as.POSIXct(normalized[idx],format='%Y-%m-%dT%H:%M:%OS',tz='UTC'))
          attr(value,'tzone') <- m$tzone
        }
        invalid(is.na(value))
      } else value <- text
      value[missing] <- NA
      columns[[i]] <- value
    }
    names(columns) <- column_names
    # Row names as the original stored them: none (automatic), integer, or character.
    row_names <- read_lines(file.path(folder, paste0('rows-', table, '.txt')))
    if (length(row_names) != n || anyDuplicated(row_names) || anyNA(row_names)) row_names <- .set_row_names(n)
    else if (identical(meta$rowNamesType[1], 'integer') && !anyNA(suppressWarnings(as.integer(row_names)))) row_names <- as.integer(row_names)
    value <- structure(columns, class='data.frame', row.names=row_names)
    if (meta$shape[1] == 'matrix') value <- as.matrix(value)
    objects[[meta$object[1]]] <- value
  }
  if (format == 'rds') {
    if (length(objects) != 1L) fail('An RDS file contains one table. Save the current worksheet or choose RData for all worksheets.')
    saveRDS(objects[[1]],destination,version=3)
  } else {
    env <- list2env(objects,parent=emptyenv()); save(list=names(objects),file=destination,envir=env,version=3)
  }
}
tryCatch({
  if (args[1] == 'read') read_files(args[2],args[3])
  else if (args[1] == 'write') write_files(args[2],args[3],args[4])
  else fail('Unknown R data-file action.')
}, error=function(e) { cat(conditionMessage(e),'\n',file=stderr()); quit(status=1L) })
