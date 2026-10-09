"""Independent R checks for the matched and exposure-adjusted help regressions."""
import csv, math, subprocess, tempfile
from pathlib import Path
from test_help_examples import documented_inputs
from test_menu import Session
from r_runtime import rscript

s = Session()
try:
    for operation, page, roles, formula, metric in [
        ('ConditionalLogisticRegression', 'conditional_logistic',
         ['stratum', 'case-control', 'predictors'],
         'survival::clogit(V2 ~ V3+V4+V5+V6+V7+V8+strata(V1), data=d)',
         '-2*fit$loglik[2]'),
        ('PoissonRegression', 'poisson', ['response', 'exposure', 'predictors'],
         'glm(V1 ~ V3+V4+V5+V6+V7+V8+V9+V10+V11+V12+V13+offset(log(V2)), family=poisson(), data=d)',
         'deviance(fit)')]:
        answers = documented_inputs('regression_and_correlation/' + page + '.htm')
        result = s.run(operation, answers)
        cols = [c['values'] for role in roles for c in answers[role]['columns']]
        assert len({len(c) for c in cols}) == 1
        with tempfile.TemporaryDirectory() as folder:
            data = Path(folder) / 'data.csv'
            with data.open('w', newline='') as f:
                writer = csv.writer(f)
                writer.writerow(['V' + str(i+1) for i in range(len(cols))])
                writer.writerows(zip(*cols))
            code = 'library(survival);d<-read.csv(commandArgs(TRUE)[1]);fit<-' + formula + ';cat(sprintf("%.15g",' + metric + '))'
            expected = float(subprocess.check_output([rscript(), '--vanilla', '-e', code, str(data)], text=True))
        observed = result['values']['dv' if page == 'conditional_logistic' else 'dev']
        assert math.isclose(observed, expected, rel_tol=1e-10, abs_tol=1e-10), (operation, observed, expected)
        print('PASS:', operation, 'help data, grouping/exposure and model deviance agree with independent R')
finally:
    s.finish()
