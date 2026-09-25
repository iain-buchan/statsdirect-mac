args <- commandArgs(TRUE)
cases <- read.delim(args[1], stringsAsFactors=FALSE)
options(digits=17)
con <- file(args[2], "w")
for (i in seq_len(nrow(cases))) {
  c <- cases[i, ]
  fn <- sub("_direct$", "", c$function_name)
  values <- list(c$x, c$a)
  if (fn %in% c("pbeta", "qbeta", "pf", "qf")) values <- c(values, list(c$b))
  values$lower.tail <- c$lower
  values$log.p <- c$log
  warnings <- character()
  value <- withCallingHandlers(tryCatch(do.call(fn, values), error=function(e) NaN),
    warning=function(w) { warnings <<- c(warnings, conditionMessage(w)); invokeRestart("muffleWarning") })
  cat(c$id, sprintf("%.17g", value), paste(warnings, collapse="; "), sep="\t", file=con)
  cat("\n", file=con)
}
close(con)
