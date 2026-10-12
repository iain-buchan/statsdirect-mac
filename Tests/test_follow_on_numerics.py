"""Independent R references and isolation of simultaneously retained model fits."""
import math
import subprocess
from test_menu import Session, columns
from r_runtime import rscript


def r_values(code):
    return [float(n) for n in subprocess.check_output(
        [rscript(), '--vanilla', '-e', code], text=True).split()]


def compare(actual, expected):
    assert len(actual) == len(expected)
    for a, e in zip(actual, expected):
        assert math.isclose(a, e, rel_tol=2e-8, abs_tol=2e-8), (a, e)


s = Session()
try:
    anova = s.run('OneWay', {'data': columns([1, 2, 3, 4], [3, 5, 6, 8], [7, 8, 9, 11])}, keep=True)
    tukey = s.run('Tukey', {}, parent=anova['id'], keep=True)
    reference = r_values("y<-c(1,2,3,4,3,5,6,8,7,8,9,11);g<-factor(rep(1:3,each=4));"
                         "fit<-aov(y~g);cat(sprintf('%.15g',c(qtukey(.95,3,df.residual(fit)),"
                         "sqrt(deviance(fit)/df.residual(fit)))));")
    compare([tukey['values']['q'], tukey['values']['psd']], reference)
    # A post-hoc operation must not overwrite its parent's pooled error/context.
    chain = s.run('Bonferroni', {'variables': [0, 2], 'comparisons': 3}, parent=tukey['id'])
    direct = s.run('Bonferroni', {'variables': [0, 2], 'comparisons': 3}, parent=anova['id'])
    assert chain['values'] == direct['values'] and chain['html'] == direct['html']
    print('PASS: ANOVA Tukey critical value and pooled SD agree with R; chained Bonferroni matches direct use')

    x, y = list(range(1, 11)), [2, 4, 8, 17, 29, 48, 75, 110, 156, 218]
    original = s.run('PolynomialRegression', {'x': columns(x), 'y': columns(y), 'degree': '2'}, keep=True)
    before = s.run('PolynomialRegressionInterpolation', {'newx': 2.5}, parent=original['id'])
    changed = s.run('PolynomialRegressionChangeDegree', {'degree': '3'}, parent=original['id'], keep=True)
    cubic = s.run('PolynomialRegressionInterpolation', {'newx': 2.5}, parent=changed['id'])
    # An unrelated open fit and the changed-degree branch cannot alter the original.
    other = s.run('PolynomialRegression', {'x': columns(x), 'y': columns([v + 100 for v in y]), 'degree': '2'}, keep=True)
    shifted = s.run('PolynomialRegressionInterpolation', {'newx': 2.5}, parent=other['id'])
    after = s.run('PolynomialRegressionInterpolation', {'newx': 2.5}, parent=original['id'])
    assert before['values'] == after['values']
    compare([shifted['values']['y_res']], [before['values']['y_res'] + 100])
    fields = ['y_res', 'from_conf', 'to_conf', 'from_pred', 'to_pred']
    for degree, result in [(2, after), (3, cubic)]:
        reference = r_values(
            'x<-1:10;y<-c(2,4,8,17,29,48,75,110,156,218);'
            f'fit<-lm(y~poly(x,{degree},raw=TRUE));'
            'ci<-predict(fit,data.frame(x=2.5),interval="confidence",level=.95);'
            'pi<-predict(fit,data.frame(x=2.5),interval="prediction",level=.95);'
            'cat(sprintf("%.15g",c(ci,pi[2:3])));')
        compare([result['values'][key] for key in fields], reference)
    assert not math.isclose(after['values']['y_res'], cubic['values']['y_res'])
    print('PASS: degree-2 and refitted degree-3 predictions and 95% confidence/prediction limits agree with R; original and unrelated fits remain independent')
finally:
    s.finish()
