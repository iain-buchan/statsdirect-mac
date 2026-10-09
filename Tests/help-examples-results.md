# Help examples replayed through the Mac engine

Every help page that uses the test workbook, run through the Mac engine host with the columns it names and the answers it gives; the figures printed under "For this example" are looked for in the Mac report. Plots are run but their figures are not compared. Regenerate with `python3 Tests/test_help_examples.py --report`.

| Page | Operation | Result | Detail |
|---|---|---|---|
| analysis_of_variance/crossover.htm | Crossover | too few columns | Select data for Group 2 DRUG needs 1 column(s); 0 left |
| analysis_of_variance/latin_square.htm | LatinSquare | no columns | none of the quoted names is a column of the test workbook |
| analysis_of_variance/nested.htm | TwoWayNested | differs | 2/18 figures found; missing 7.560346, 2.520115, 2.6302, 0.328775, 0.07985, 0.006654, 10.270396, 378.727406 |
| analysis_of_variance/one_way.htm | OneWay | matched | 7/7 figures found |
| analysis_of_variance/two_way.htm | TwoWay | matched | 11/11 figures found |
| analysis_of_variance/two_way_replicate.htm | ReplicateTwoWay | matched | 15/15 figures found |
| graphics/bar.htm | BarPlotFrequency | chart drawn | a plot; its figures are not compared |
| graphics/box_whisker.htm | BoxWhiskerPlot | chart drawn | a plot; its figures are not compared |
| graphics/box_whisker_text.htm | BoxWhiskerPlotText | chart drawn | a plot; its figures are not compared |
| graphics/control.htm | ControlPlot | refused | X: Date, row 1: ‘1999-01-19T00:00:00’ is not numeric. Correct it or use * for a missing value. |
| graphics/error_bar.htm | ErrorPlot | chart drawn | a plot; its figures are not compared |
| graphics/forest.htm | CochranePlot | chart drawn | a plot; its figures are not compared |
| graphics/histogram.htm | HistogramPlot | chart drawn | a plot; its figures are not compared |
| graphics/histogram_text.htm | HistogramPlotText | chart drawn | a plot; its figures are not compared |
| graphics/ladder.htm | LadderPlot | chart drawn | a plot; its figures are not compared |
| graphics/normal.htm | NormalPlot | chart drawn | a plot; its figures are not compared |
| graphics/population_pyramid.htm | PyramidPlot | chart drawn | a plot; its figures are not compared |
| graphics/scatter.htm | LinePlot | chart drawn | a plot; its figures are not compared |
| graphics/scatter_text.htm | ScatterPlotText | chart drawn | a plot; its figures are not compared |
| graphics/spread.htm | SpreadPlot | chart drawn | a plot; its figures are not compared |
| graphics/survival.htm | SurvivalPlot | too few columns | Select data for censorship/death/event of group 2 needs 1 column(s); 0 left |
| meta_analysis/correlation.htm | MetaCorrelation | matched | 101/101 figures found |
| meta_analysis/effect_size.htm | Effect | matched | 86/86 figures found |
| meta_analysis/incidence_rate.htm | MetaIncidenceRateDifference | matched | 31/31 figures found |
| meta_analysis/mh.htm | Mantel | matched | 36/36 figures found |
| meta_analysis/peto.htm | PetoMeta | matched | 91/91 figures found |
| meta_analysis/proportion.htm | ProportionMeta | matched | 176/176 figures found |
| meta_analysis/relative_risk.htm | RelativeRiskMeta | matched | 75/75 figures found |
| meta_analysis/risk_difference.htm | RiskDifference | matched | 58/58 figures found |
| meta_analysis/summary.htm | MetaSummary | matched | 80/80 figures found |
| nonparametric_methods/cuzick.htm | Cuzick | too few columns | Enter scores needs 1 column(s); 0 left |
| nonparametric_methods/diversity.htm | Diversity | differs (random method) | 13/25 figures found; missing 0.008099, 0.017107, 0.865802, 0.932901, 0.866084, 0.932619, 0.118681, 0.098032 |
| nonparametric_methods/friedman.htm | Friedman | differs (random method) | 26/27 figures found; missing 0.2466 |
| nonparametric_methods/gini.htm | Gini | differs (random method) | 7/14 figures found; missing 0.040067, 0.046859, 0.223529, 0.120245, 0.279412, 0.150307, 0.1904 |
| nonparametric_methods/kendall_correlation.htm | Kendall | matched | 16/16 figures found |
| nonparametric_methods/kruskal_wallis.htm | Kruskal | matched | 46/46 figures found |
| nonparametric_methods/loess.htm | LOESS | harness error | {'error': 'This R-based method is not enabled in the Mac prototype yet. Method help and R → New R Session are available.'} |
| nonparametric_methods/mann_whitney.htm | MannWhitney | matched | 13/13 figures found |
| nonparametric_methods/nonparametric_regression.htm | NonparametricLinearRegression | too few columns | Select data for PREDICTOR (X axis) needs 1 column(s); 0 left |
| nonparametric_methods/quantile_ci.htm | Quantile | matched across runs | 10/10 figures found over the variants the page prints |
| nonparametric_methods/smirnov.htm | Smirnov | matched | 6/6 figures found |
| nonparametric_methods/spearman.htm | Spearman | matched | 6/6 figures found |
| nonparametric_methods/wilcoxon_signed_ranks.htm | Wilcoxon | matched | 9/9 figures found |
| parametric_methods/f_variance_ratio.htm | VarianceRatio | matched | 5/5 figures found |
| parametric_methods/normality.htm | Normality | matched | 15/15 figures found |
| parametric_methods/paired_t.htm | TPaired | matched | 9/9 figures found |
| parametric_methods/reference_range.htm | ReferenceRange | differs | 24/25 figures found; missing 97.5 |
| parametric_methods/single_sample_t.htm | TSingle | matched | 8/8 figures found |
| parametric_methods/unpaired_t.htm | TUnpaired | matched | 15/15 figures found |
| parametric_methods/z_normal.htm | ZSingle | differs | 11/13 figures found; missing 0.06, 0.03 |
| randomization/preference_group.htm | Preferences | matched | 0/0 figures found |
| regression_and_correlation/conditional_logistic.htm | ConditionalLogisticRegression | refused | predictors: The data must have 112 rows, matching the earlier selection. |
| regression_and_correlation/grouped_covariance.htm | GroupedCovariance | too few columns | Group 1: one column of Y replicates for each X value needs 3 column(s); 0 left |
| regression_and_correlation/grouped_linearity_replicates.htm | GroupedLinearity | matched | 9/9 figures found |
| regression_and_correlation/logistic.htm | LogisticRegression | matched | 51/51 figures found |
| regression_and_correlation/multiple_linear.htm | MultipleLinearRegression | matched | 25/25 figures found |
| regression_and_correlation/poisson.htm | PoissonRegression | failed | Poisson regression: You must have more observations than parameters |
| regression_and_correlation/polynomial.htm | PolynomialRegression | matched | 23/23 figures found |
| regression_and_correlation/probit_analysis.htm | Logit | matched | 12/12 figures found |
| regression_and_correlation/simple_linear.htm | SimpleLinearRegression | matched | 15/15 figures found |
| survival_analysis/cox_regression.htm | CoxRegression | matched | 15/15 figures found |
| survival_analysis/follow_up_life_table.htm | FollowUpLifetable | matched | 68/68 figures found |
| survival_analysis/kaplan_meier.htm | KaplanMeier | matched | 134/134 figures found |
| survival_analysis/logrank.htm | LogRank | differs | 33/88 figures found; missing 5.421429, 0.737813, 1.578571, 1.900452, -1.421429, 1.421429, 0.922398, -0.922398 |
| survival_analysis/wei_lachin.htm | WeiLachin | refused | scrapCensor: Censorship value must be 0 or 1 only |
