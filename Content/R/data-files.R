# Base-R data-file exchange for the grid. No packages or user profiles required.
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
  if (is.factor(x)) 'factor' else if (inherits(x, 'Date')) 'Date' else if (inherits(x, 'POSIXct')) 'POSIXct'
  else if (is.object(x)) NA_character_ else if (is.integer(x)) 'integer' else if (is.double(x)) 'double'
  else if (is.logical(x)) 'logical' else if (is.character(x)) 'character' else NA_character_
}
read_files <- function(path, destination) {
  if (file.info(path)$size > 50*1024^2) fail('R data files can be up to 50 MB in this prototype.')
  if (tolower(tools::file_ext(path)) == 'rds') {
    objects <- list(readRDS(path)); names(objects) <- tools::file_path_sans_ext(basename(path))
  } else {
    env <- new.env(parent=emptyenv()); object_names <- load(path, envir=env)
    objects <- mget(object_names, envir=env, inherits=FALSE)
  }
  sheets <- list(); skipped <- character(); total <- 0L
  for (object_name in names(objects)) {
    x <- objects[[object_name]]
    object_type <- if (is.matrix(x)) 'matrix' else 'data.frame'
    if (is.matrix(x) && (is.numeric(x) || is.character(x) || is.logical(x))) x <- as.data.frame(x, stringsAsFactors=FALSE, optional=TRUE)
    if (!is.data.frame(x)) { skipped <- c(skipped, paste0(object_name, ' (not a data frame or matrix)')); next }
    types <- vapply(x, column_type, character(1))
    if (anyNA(types) || ncol(x) == 0L) { skipped <- c(skipped, paste0(object_name, ' (unsupported or empty columns)')); next }
    if (nrow(x)+1L > 1048576L || ncol(x) > 16384L) fail(paste('Table exceeds Excel dimensions:', object_name))
    total <- total + (nrow(x)+1)*ncol(x)
    if (total > 500000L || length(sheets) >= 128L) fail('Open at most 128 tables and 500,000 cells per R data file in this prototype.')
    cells <- vector('list', (nrow(x)+1)*ncol(x)); offset <- 0L
    columns <- vector('list', ncol(x))
    for (c in seq_along(x)) {
      column <- x[[c]]; type <- types[c]
      tz <- attr(column, 'tzone'); if (is.null(tz) || !length(tz)) tz <- ''
      columns[[c]] <- list(type=type, levels=unname(as.list(levels(column))), ordered=is.ordered(column), tzone=tz[1])
      offset <- offset+1L; cells[[offset]] <- list(col=c-1L, row=0L, text=names(x)[c], kind='text')
      for (r in seq_len(nrow(x))) {
        value <- column[r]; missing <- is.na(value) && !is.nan(value)
        text <- if (missing) '' else if (type == 'Date') format(value, '%Y-%m-%d') else if (type == 'POSIXct') format(value, '%Y-%m-%dT%H:%M:%OS6Z', tz='UTC')
          else if (type == 'double') sprintf('%.17g', value) else as.character(value)
        kind <- if (type %in% c('double','integer') && is.finite(value)) 'number' else if (type == 'logical') 'boolean' else if (type %in% c('Date','POSIXct')) 'datetime' else 'text'
        offset <- offset+1L
        cells[[offset]] <- list(col=c-1L, row=r, text=text, kind=kind, rMissing=missing,
          rRaw=if (!missing && type %in% c('Date','POSIXct')) sprintf('%.17g', as.numeric(value)) else NULL)
      }
    }
    sheets[[length(sheets)+1L]] <- list(name=object_name, hidden=FALSE, headerRow=TRUE, rows=nrow(x)+1L, csvRows=nrow(x)+1L, columns=ncol(x), cells=cells,
      rColumns=columns, rRowNames=unname(as.list(row.names(x))), rObjectName=object_name, rObjectType=object_type)
  }
  if (!length(sheets)) fail(paste('No supported tables found.', paste(skipped, collapse='; ')))
  result <- list(name=basename(path), formulaCount=0L, sheets=sheets, warnings=unname(as.list(skipped)))
  writeLines(json(result), destination, useBytes=TRUE)
}
read_exchange <- function(path) read.csv(path, header=TRUE, colClasses='character', na.strings=NULL, check.names=FALSE, stringsAsFactors=FALSE, fileEncoding='UTF-8', blank.lines.skip=FALSE)
write_files <- function(folder, destination, format) {
  manifest <- read_exchange(file.path(folder, 'manifest.csv'))
  objects <- list()
  for (table in unique(manifest$table)) {
    meta <- manifest[manifest$table == table,,drop=FALSE]; columns <- list()
    for (i in seq_len(nrow(meta))) {
      m <- meta[i,,drop=FALSE]; values <- read_exchange(file.path(folder, paste0('column-',table,'-',m$column,'.csv')))
      text <- values$text; missing <- values$missing == 'true'; type <- m$type
      invalid <- function(bad) { if (any(bad & !missing)) fail(paste0('Invalid ',type,' value in ', m$object, ' / ', m$name, ', row ', which(bad & !missing)[1], '.')) }
      if (type %in% c('double','integer')) {
        suppressWarnings(value <- as.numeric(text)); invalid(is.na(value) & !(text %in% c('NaN','NA','')))
        if (type == 'integer') { invalid(!is.na(value) & (!is.finite(value) | value != trunc(value) | value > .Machine$integer.max | value < -.Machine$integer.max)); value <- as.integer(value) }
      } else if (type == 'logical') {
        invalid(!(toupper(text) %in% c('TRUE','FALSE','T','F','1','0','')))
        value <- toupper(text) %in% c('TRUE','T','1'); missing <- missing | text == ''
      } else if (type == 'factor') {
        lev <- read_exchange(file.path(folder,paste0('levels-',table,'-',m$column,'.csv')))$level
        value <- factor(text, levels=unique(c(lev,text[!missing])), ordered=m$ordered == 'true')
      } else if (type %in% c('Date','POSIXct')) {
        missing <- missing | text == ''; has_raw <- nzchar(values$raw)
        raw <- suppressWarnings(as.numeric(values$raw))
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
    names(columns) <- meta$name
    n <- if (length(columns)) length(columns[[1]]) else 0L
    row_names <- read_exchange(file.path(folder,paste0('rows-',table,'.csv')))$name
    if (length(row_names) != n || anyDuplicated(row_names) || anyNA(row_names)) row_names <- as.character(seq_len(n))
    if (identical(row_names,as.character(seq_len(n)))) row_names <- .set_row_names(n)
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
