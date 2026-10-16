# Independent numerical reference for the selected ControlPlot worked example.
# Every plotted value is checked; this file does not call the application recipe.
emit <- function(x) cat(formatC(as.double(x), digits = 8, format = "f"), "\n")
process <- c(23.9, 24.6, 24.3, 23.5, 23.5, 23.4, 23.6, 23.6, 22.9, 22.9, 23.6, 24.3, 23.4, 23.5, 22.9, 21.5, 23.7, 23.8, 23.0)
dates <- as.double(as.Date(c("1999-01-19", "1999-02-02", "1999-02-16", "1999-03-02", "1999-03-16", "1999-03-30", "1999-04-13", "1999-04-27", "1999-05-11", "1999-05-25", "1999-06-08", "1999-06-15", "1999-07-13", "1999-07-27", "1999-08-10", "1999-08-17", "1999-09-14", "1999-09-21", "1999-10-05")) - as.Date("1899-12-30"))
mean_value <- mean(process)
sd_value <- sd(process)
bands <- mean_value + c(0, 1, -1, 2, -2, 3, -3) * sd_value
emit(c(length(process), dates, process, mean_value, sd_value, bands))
