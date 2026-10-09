# Help examples replayed through the Mac engine

Worked help examples using the test workbook, run through the Mac engine host with the documented columns and answers; reported statistics are matched at their printed precision, with explanatory prose excluded. Conditional logistic estimates allow 1e-7 relative error for iterative stopping. Plots are checked for generated SVG or text; geometry has separate regression tests. Deferred methods are listed explicitly. Regenerate with `python3 Tests/test_help_examples.py --report`.

| Page | Operation | Result | Detail |
|---|---|---|---|
| analysis_of_variance/crossover.htm | Crossover | matched | 27/27 figures found |
| analysis_of_variance/latin_square.htm | LatinSquare | matched | 15/15 figures found |
| analysis_of_variance/nested.htm | TwoWayNested | matched | 13/13 figures found |
| analysis_of_variance/one_way.htm | OneWay | matched | 7/7 figures found |
| analysis_of_variance/two_way.htm | TwoWay | matched | 11/11 figures found |
| analysis_of_variance/two_way_replicate.htm | ReplicateTwoWay | matched | 15/15 figures found |
| graphics/bar.htm | BarPlotFrequency | chart drawn | SVG generated; geometry checked separately in test_charts.py |
| graphics/box_whisker.htm | BoxWhiskerPlot | chart drawn | SVG generated; geometry checked separately in test_charts.py |
| graphics/box_whisker_text.htm | BoxWhiskerPlotText | chart drawn | Text chart generated |
| graphics/control.htm | ControlPlot | chart drawn | SVG generated; geometry checked separately in test_charts.py |
| graphics/error_bar.htm | ErrorPlot | chart drawn | SVG generated; geometry checked separately in test_charts.py |
| graphics/forest.htm | CochranePlot | chart drawn | SVG generated; geometry checked separately in test_charts.py |
| graphics/histogram.htm | HistogramPlot | chart drawn | SVG generated; geometry checked separately in test_charts.py |
| graphics/histogram_text.htm | HistogramPlotText | chart drawn | Text chart generated |
| graphics/ladder.htm | LadderPlot | chart drawn | SVG generated; geometry checked separately in test_charts.py |
| graphics/normal.htm | NormalPlot | chart drawn | SVG generated; geometry checked separately in test_charts.py |
| graphics/population_pyramid.htm | PyramidPlot | chart drawn | SVG generated; geometry checked separately in test_charts.py |
| graphics/scatter.htm | LinePlot | chart drawn | SVG generated; geometry checked separately in test_charts.py |
| graphics/scatter_text.htm | ScatterPlotText | chart drawn | Text chart generated |
| graphics/spread.htm | SpreadPlot | chart drawn | SVG generated; geometry checked separately in test_charts.py |
| graphics/survival.htm | SurvivalPlot | chart drawn | SVG generated; geometry checked separately in test_charts.py |
| meta_analysis/correlation.htm | MetaCorrelation | matched | 101/101 figures found |
| meta_analysis/effect_size.htm | Effect | matched | 86/86 figures found |
| meta_analysis/incidence_rate.htm | MetaIncidenceRateDifference | matched | 31/31 figures found |
| meta_analysis/mh.htm | Mantel | matched | 36/36 figures found |
| meta_analysis/peto.htm | PetoMeta | matched | 91/91 figures found |
| meta_analysis/proportion.htm | ProportionMeta | matched | 176/176 figures found |
| meta_analysis/relative_risk.htm | RelativeRiskMeta | matched | 75/75 figures found |
| meta_analysis/risk_difference.htm | RiskDifference | matched | 56/56 figures found |
| meta_analysis/summary.htm | MetaSummary | matched | 80/80 figures found |
| nonparametric_methods/cuzick.htm | Cuzick | matched | 11/11 figures found |
| nonparametric_methods/diversity.htm | Diversity | matched | 25/25 figures found |
| nonparametric_methods/friedman.htm | Friedman | matched | 25/25 figures found |
| nonparametric_methods/friedman.htm#cochran | CochranQ | matched | 2/2 figures found |
| nonparametric_methods/gini.htm | Gini | matched | 13/13 figures found |
| nonparametric_methods/kendall_correlation.htm | Kendall | matched | 16/16 figures found |
| nonparametric_methods/kruskal_wallis.htm | Kruskal | matched | 46/46 figures found |
| nonparametric_methods/loess.htm | LOESS | matched | 3/3 figures found |
| nonparametric_methods/mann_whitney.htm | MannWhitney | matched | 13/13 figures found |
| nonparametric_methods/nonparametric_regression.htm | NonparametricLinearRegression | matched | 6/6 figures found |
| nonparametric_methods/quantile_ci.htm | Quantile | matched | 5/5 figures found |
| nonparametric_methods/quantile_ci.htm#conservative | Quantile | matched | 5/5 figures found |
| nonparametric_methods/smirnov.htm | Smirnov | matched | 6/6 figures found |
| nonparametric_methods/spearman.htm | Spearman | matched | 6/6 figures found |
| nonparametric_methods/wilcoxon_signed_ranks.htm | Wilcoxon | matched | 9/9 figures found |
| parametric_methods/f_variance_ratio.htm | VarianceRatio | matched | 5/5 figures found |
| parametric_methods/normality.htm | Normality | matched | 15/15 figures found |
| parametric_methods/paired_t.htm | TPaired | matched | 9/9 figures found |
| parametric_methods/reference_range.htm | ReferenceRange | matched | 23/23 figures found |
| parametric_methods/single_sample_t.htm | TSingle | matched | 8/8 figures found |
| parametric_methods/unpaired_t.htm | TUnpaired | matched | 15/15 figures found |
| parametric_methods/z_normal.htm | ZSingle | matched | 11/11 figures found |
| parametric_methods/z_normal.htm#2 | ZUnpaired | matched | 10/10 figures found |
| randomization/preference_group.htm | Preferences | matched | 0/0 figures found |
| regression_and_correlation/conditional_logistic.htm | ConditionalLogisticRegression | matched | 46/46 figures found (1e-7 relative tolerance for iterative estimates) |
| regression_and_correlation/grouped_covariance.htm | GroupedCovariance | matched | 71/71 figures found |
| regression_and_correlation/grouped_linearity_replicates.htm | GroupedLinearity | matched | 9/9 figures found |
| regression_and_correlation/logistic.htm | LogisticRegression | matched | 51/51 figures found |
| regression_and_correlation/multiple_linear.htm | MultipleLinearRegression | matched | 25/25 figures found |
| regression_and_correlation/poisson.htm | PoissonRegression | matched | 176/176 figures found |
| regression_and_correlation/polynomial.htm | PolynomialRegression | matched | 23/23 figures found |
| regression_and_correlation/probit_analysis.htm | Logit | matched | 12/12 figures found |
| regression_and_correlation/simple_linear.htm | SimpleLinearRegression | matched | 11/11 figures found |
| survival_analysis/cox_regression.htm | CoxRegression | matched | 15/15 figures found |
| survival_analysis/follow_up_life_table.htm | FollowUpLifetable | matched | 68/68 figures found |
| survival_analysis/kaplan_meier.htm | KaplanMeier | matched | 134/134 figures found |
| survival_analysis/logrank.htm | LogRank | matched | 32/32 figures found |
| survival_analysis/logrank.htm#stratified | LogRank | matched | 56/56 figures found |
| survival_analysis/wei_lachin.htm | WeiLachin | matched | 82/82 figures found |
