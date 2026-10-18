# StatsDirect recipe: the selected method-comparison regressions, using mcr.
# data: plasma = testData, serum = referenceData
# settings: error_ratio = error-ratio, confidence = ci, seed = seed, do.deming.jackknife = do.deming.jackknife, do.deming.bootstrap = do.deming.bootstrap, do.deming.analytical = do.deming.analytical, do.wdeming.jackknife = do.wdeming.jackknife, do.wdeming.nestedbootstrap = do.wdeming.nestedbootstrap, do.paba = do.paba, do.paba.nestedbootstrap = do.paba.nestedbootstrap, do.pabalarge = do.pabalarge, do.pabalarge.nestedbootstrap = do.pabalarge.nestedbootstrap
# settings: draw_scatter = plot.testvsreference, draw_comparison = plot.modelcomparison, draw_difference = plot.bland.altman, draw_residuals = plot.residuals, draw_bias = plot.bias

if (!requireNamespace("mcr", quietly = TRUE)) install.packages("mcr", repos = "https://cloud.r-project.org")
library(mcr)

# The saved choices remain editable. These are mcr's regression and CI methods.
chosen <- names(Filter(isTRUE, list(
  do.deming.jackknife = do.deming.jackknife, do.deming.bootstrap = do.deming.bootstrap,
  do.deming.analytical = do.deming.analytical, do.wdeming.jackknife = do.wdeming.jackknife,
  do.wdeming.nestedbootstrap = do.wdeming.nestedbootstrap, do.paba = do.paba,
  do.paba.nestedbootstrap = do.paba.nestedbootstrap, do.pabalarge = do.pabalarge,
  do.pabalarge.nestedbootstrap = do.pabalarge.nestedbootstrap)))
if (!length(chosen)) stop("Select at least one regression method.")
regressions <- list(
  do.deming.jackknife = c("Deming", "jackknife"), do.deming.bootstrap = c("Deming", "bootstrap"),
  do.deming.analytical = c("Deming", "analytical"), do.wdeming.jackknife = c("WDeming", "jackknife"),
  do.wdeming.nestedbootstrap = c("WDeming", "nestedbootstrap"), do.paba = c("PaBa", "bootstrap"),
  do.paba.nestedbootstrap = c("PaBa", "nestedbootstrap"), do.pabalarge = c("PaBaLarge", "bootstrap"),
  do.pabalarge.nestedbootstrap = c("PaBaLarge", "nestedbootstrap"))
fits <- lapply(chosen, function(name) {
  set.seed(seed)   # Each selected method starts with its recorded seed, as in StatsDirect.
  mcreg(serum, plasma, error.ratio = error_ratio, alpha = 1 - confidence,
        method.reg = regressions[[name]][1], method.ci = regressions[[name]][2],
        method.bootstrap.ci = "BCa",
        mref.name = "Reference", mtest.name = "Test", na.rm = TRUE)
})
names(fits) <- chosen

# Older reports have no recorded chart choices; use one regression plot for those.
if (is.null(draw_scatter)) draw_scatter <- TRUE
for (fit in fits) {
  printSummary(fit)
  if (isTRUE(draw_scatter)) plot(fit, x.lab = "Reference", y.lab = "Test", equal.axis = TRUE)
  if (isTRUE(draw_difference)) plotDifference(fit)
  if (isTRUE(draw_residuals)) plotResiduals(fit)
  if (isTRUE(draw_bias)) plotBias(fit)
}
if (isTRUE(draw_comparison)) do.call(compareFit, fits)
