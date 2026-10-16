# Synthetic, non-patient charts for import/rendering regression checks.
# Run from the repository root with Rscript Tests/Fixtures/RCharts/generate.R.
.libPaths(c(path.expand("~/Library/Application Support/StatsDirect Viewer/R Library"), .libPaths()))
stopifnot(requireNamespace("svglite", quietly = TRUE))
folder <- "Tests/Fixtures/RCharts"
for (device in "svglite") {
  for (i in 1:2) {
    path <- file.path(folder, paste0(device, "-", i, ".svg"))
    svglite::svglite(path, width = 4, height = 2)
    par(mar = c(1, 1, 1, 1), bg = "white")
    plot.new()
    plot.window(xlim = c(0, 1), ylim = c(0, 1))
    rect(0.05, 0.05, 0.95, 0.95, col = c("#d7eaff", "#fff0cf")[i], border = NA)
    text(0.5, 0.5, c("BEFORE 123", "AFTER 789")[i], col = c("#003399", "#990033")[i], cex = 1.7)
    dev.off()
  }
}
