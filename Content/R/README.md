# R recipes

The analyses that "Continue in R" writes for a result. `analysis-recipes.json` maps engine operation names to recipe files under
`recipes/`. A script for a result is short: the run's data as named vectors (or a matrix of counts), the settings as named values,
then the recipe's analysis, so that the user can run it, edit it, or take it to R or RStudio.

A recipe is the analysis as the help's R code shows it for that method, which reproduces the figures of the help's worked example. It
starts with a header that names the variables it takes; the script writer (`StatsDirectUI/R/RScriptWriter.cs`) writes the run's values
under those names before the body:

    # data: farm, town                 the columns of the run's frames, in order, as vectors; "rest..." takes any further columns as a named list
    # table: counts                    a 2 by 2 table typed in, as a matrix with the labels of its rows and columns
    # matrix: counts                   a frame of counts, its columns the columns of a matrix
    # settings: confidence = gamma     variables from the run's parameters (a confidence level as a proportion)

The recipes were generated from the help's R sections (the topic of each operation, through `Data/Alias.xml`), with the example's data
and settings taken out and the confidence level taken from the run; files marked `# hand-edited` were adjusted by hand after that. The
checks in `tests/RScript` run every recipe on the help's own example, through a run's record, and compare its output with the help's
script, and run the paired t test and the 2 by 2 chi-square against the engine. The files are shared with the Mac version of
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
the operation it continues under `inherits`. A table typed on screen (the 2 by k tables, the standardization screens, kappa from
counts, the likelihood ratios, the Woolf and Mantel-Haenszel strata) reaches the record as an entered frame under the grid's name, usually `data`, its columns `Column 1`, `Column 2` and so on
in the grid's order, and its recipe binds them by that name.
