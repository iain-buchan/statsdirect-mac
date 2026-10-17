# R recipes

The analyses that "Continue in R" writes for a result. `analysis-recipes.json` maps engine operation names to recipe files under
`recipes/`. A script for a result is short: the run's data as named vectors (or a matrix of counts), the settings as named values,
then the recipe's analysis, so that the user can run it, edit it, or take it to R or RStudio.

A recipe reproduces the selected analysis, using the help's worked example as a numerical reference. Teaching comparisons, additional
transformations and unrelated example plots are not part of a result's replay. It
starts with a header that names the variables it takes; the script writer (`StatsDirectUI/R/RScriptWriter.cs`) writes the run's values
under those names before the body:

    # data: farm, town                 the columns of the run's frames, in order, as vectors; "rest..." takes any further columns as a named list
    # table: counts                    a 2 by 2 table typed in, as a matrix with the labels of its rows and columns
    # matrix: counts                   a frame of counts, its columns the columns of a matrix
    # settings: confidence = gamma     variables from the run's parameters (a confidence level as a proportion)
    # nested: data2d = data2d          a two-level input (blocks and treatments, groups and subgroups, or the grouped covariance's groups) as a list of lists

The recipes were generated from the help's R sections (the topic of each operation, through `Data/Alias.xml`), with the example's data
and settings taken out and the confidence level taken from the run; files marked `# hand-edited` were adjusted by hand after that. The
checks in `tests/RScript` run every recipe on the help's own example, through a run's record, and compare its output with the help's
script (or compare the complete plotted arrays with an independent reference), and run the paired t test and the 2 by 2 chi-square against the engine. The files are shared with the Mac version of
StatsDirect, which keeps them the same.

Two kinds of recipe are written by hand rather than generated, and are marked `# hand-edited`. The Distributions calculator has no
columns: it records the boxes of its last calculation as settings named `value`, `df`, `df2`, `lower`, `upper` and `two_sided`, and
what was asked of them as `asked` (`calculate`, or `invert-lower`, `invert-upper` or `invert-two-sided`); each distribution's recipe
prints the probabilities of the value, or the value of the probability, as the help's illustration does. The t tests on summary
figures rebuild R's tests from the sizes, means and standard deviations, printed as R prints them, since R's own functions take the
observations.

A data item may bind an input of the run by its name: `name = input` takes the first column of the input of that name, and
`name... = input` all of its columns as a named list. When the run has no such input the variable is set to `NULL`, so that a recipe
can test for an optional frame (stratum labels, weights, a group identifier) and supply a default. Items without `= input` take the
columns in order, as before. Example: `# data: time = times, event = deaths, group = groups`.

Most recipes are generated from the help's R sections by a script kept with the maintainer's tooling, from a table of bindings per
operation; the generated files are written whole and must not be edited by hand. Those marked `# hand-edited` are written by hand
(the calculators, the summary t tests, the random number generators, and the two rank correlation calculators) and are kept as they
are. The checks in `tests/RScript` compare every recipe's figures with the help's script on the help's example, except the few whose
example file says `nocompare` (the random number generators, whose output has no fixed figures, and the rank correlation calculators,
whose help works from two rankings); those must run and print figures, and the calculators' figures are checked in `Inverse.cs`.

A follow-on operation (a prediction, the residuals, a parameter detail, an exact P by simulation, the multiple comparisons) continues
the run of the operation it was asked from without asking for the data again. The record of its run carries the frames it inherited
from that run, marked `"inherited": true`, so its recipe is the earlier operation's and binds the same inputs; the manifest names
the operation it continues under `inherits`. Every operation that continues one with a recipe (its prerequisite operation, or the root of a
chain of them) takes that recipe this way, so the follow-ons of the regressions, the one way analysis and the survival and
correlation analyses all give the script of the run they continue. A table typed on screen (the 2 by k tables, the standardization screens, kappa from
counts, the likelihood ratios, the Woolf and Mantel-Haenszel strata) reaches the record as an entered frame under the grid's name, usually `data`, its columns `Column 1`, `Column 2` and so on
in the grid's order, and its recipe binds them by that name.

A two-level frame (the replicated two-way and the nested analyses of variance) reaches the record as `"kind": "frame2d"` with its
`value.frames`, an array per block or group of its columns, each with its title and values; the grouped covariance's data reach it as
`"kind": "covariance"` in the same shape, each group's predictor levels first and then the outcome's replicates at each level, and the
confidence level it asks through the grid is recorded as the setting `ci`. A recipe binds such an input with `# nested: var = input`
and gets a list of lists, the inner vectors named by their titles when they have any; the recipe rebuilds the vectors and factors the
analysis takes from the list.

A frame asked once per pass of a loop (the groups of a survival plot, the repeats of the Wei-Lachin test) is recorded once per pass,
with the values of that pass; the values the analysis used of such pointer frames are held under the keys `name`, `name#2`, `name#3` and
so on, which the input names in `held`. The writer gathers the inputs of one name for a variable bound to that name. A recipe that names
every input it takes gets only those: the run's other inputs, such as a grid of new values a prediction asks for, and the frames the
operation left in the bag are not written; a rest list (`rest...`) likewise leaves out the bag's frames when the run asked for frames of
its own.

A column that is not at its recorded place when the script is written, because the analysis wrote its result columns to the left of
its data or a column was inserted or removed by hand, is found again by its hash and its title within 64 columns to either side
(`ColumnLocator`); the script notes the move, and the column's comment gives its new place.

Inputs are recorded at acquisition, before an engine routine can sort observations, remove incomplete pairs or overwrite an origin.
The immutable internal snapshot retains the original worksheet pointer and hash; up to 5,000 pointer values per run are retained as
before. Larger selections retain metadata rather than a second complete dataset. A private context carries these original snapshots
into follow-on operations without adding private objects to the version-1 JSON record. Reacquiring an input replaces its snapshot.
Recipes apply the analysis's preprocessing explicitly: polynomial regression, for example, removes incomplete pairs and sorts by X
before calculating its fit, Durbin-Watson statistic and trapezoidal area. A genuine worksheet edit still generates a changed-data note.

Graphical recipes bind `# settings: chart = chartSettings`. The final chart dialog records a portable bag containing titles, series
labels, orientation, fonts, markers, axes and the options specific to that chart. Axis bags `x` and `y` are in the chart definition's
original orientation; recipes swap them when the native renderer swaps axes. Histogram panels retain their selected bin edges and
titles; R recomputes the counts from the selected observations. Chart data are still supplied by the recipe's named input bindings.
The writer embeds `recipes/chart-common.R` before these recipes, so exported scripts are self-contained and need no installed helper
file. That helper supplies font fallback for PDF, measured title wrapping, axis formatting and the selected drawing styles.

One native graphical chart produces one R page. Multiple selected histograms occupy panels on that page. Legitimate multi-chart
analyses retain their separate charts. An older saved result without chart choices reports that it is using standard options; past
choices cannot be reconstructed. These graphical recipes are marked `# hand-edited` and must be preserved during regeneration.
Their tests cover native dialog-to-record-to-R binding, edited data and labels, settings, SVG/PDF page counts and every plotted value,
as well as the help examples. Text-chart recipes retain their existing output conventions.

The version-1 record also carries an additive `rootOperation` field. A private context entry preserves that analysis through follow-ons
and resets it when a new root analysis starts. Manifest `parentFiles` selects the appropriate recipe for commands shared by several
analyses, such as regression ANOVA or probit/logit continuations. Legacy ambiguous dose-response continuations provide data with a
rerun explanation instead of silently selecting logit. A recipe can bind `statsdirectOperation` or `statsdirectRootOperation` in its
settings header to obtain this provenance without adding private context objects to JSON.

Probit/logit replay uses the selected link, native coefficient scale, confidence, logged doses and interpolation requests. More prints
the selected observations and fitted counts; Plot draws the selected fitted curve. Positive-response control adjustments and the native
heterogeneity-adjusted interval convention are explicitly unsupported: these cases stop with an explanation rather than substituting
ordinary binomial intervals. This limitation concerns the R replay, not the native analysis.

Survival charts use the selected survival and interval columns. Small curves may travel with chart settings, within the 5,000-value
limit; larger selections use worksheet bindings and per-group shape metadata. Optional bounds stay with their own group. Forest charts
retain the chosen scale and optional weights/pooling labels. ROC charts retain comparison direction, confidence, weight and the final
per-series cutoffs; redraws reuse those choices. Friedman/Cochran recipes use only the selected blocks; multiple comparisons retain
confidence and sidedness. Quantiles and descriptive summaries process every selected column and preserve the report options.

The `analysis-replay`, `routed-replay`, `probit-replay` and `charts-d` groups in `tests/RScript` run actual native analyses through saved
and reopened records into installed R. They vary data, missing observations, selected columns, confidence, model and follow-on paths.
Graphical tests additionally check native and R drawing primitives, SVG and automatic PDF devices. Independent worked references are
compared per operation, so two continuations using one recipe file cannot accidentally share the wrong reference output.
