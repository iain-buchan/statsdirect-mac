"""Exercise the 5.0.8 distributions through Mac forms, expressions and reports."""
import math
import re
import subprocess
from test_menu import Session, columns


def references(expressions):
    script = 'options(digits=17); cat(c(' + ','.join(expressions) + '), sep="\\n")'
    return list(map(float, subprocess.check_output([
        '/Library/Frameworks/R.framework/Resources/bin/Rscript', '--vanilla', '-e', script
    ], text=True).split()))


def near(actual, expected, label):
    # No absolute tolerance: a lost small tail must not pass as zero.
    assert math.isfinite(actual) and math.isclose(actual, expected, rel_tol=2e-11, abs_tol=0), (label, actual, expected)


session = Session()
try:
    tails = [
        ('T', {'x': -1e20, 'df': 2}, 'lower', 'pt(-1e20,2)'),
        ('T', {'x': 1e20, 'df': 2}, 'upper', 'pt(1e20,2,lower.tail=FALSE)'),
        ('F', {'x': 1e-20, 'df': 5, 'df2': 10}, 'lower', 'pf(1e-20,5,10)'),
        # R's direct pf(1e308,30,1) path overflows; use the exact reciprocal-F identity.
        ('F', {'x': 1e308, 'df': 30, 'df2': 1}, 'upper', 'pf(1e-308,1,30)'),
        ('ChiSquare', {'x': 1e-20, 'df': 2}, 'lower', 'pchisq(1e-20,2)'),
        ('ChiSquare', {'x': 1400, 'df': 2}, 'upper', 'pchisq(1400,2,lower.tail=FALSE)'),
    ]
    for (name, inputs, side, expression), expected in zip(tails, references([c[3] for c in tails])):
        ident, state = session.start('Distribution' + name)
        try:
            session.request(action='answer', id=ident, token=state['token'], value=inputs)
            result = session.wait(ident)
            assert result['state'] == 'complete', result
            near(result['values'][side], expected, name + ' ' + side)
            if name == 'T':
                reported = float(re.search(r'Two-sided P = ([\d.Ee+\-]+)', result['html'])[1])
                near(reported, 2 * expected, name + ' reported two-sided P')
        finally:
            session.close(ident)
    print('PASS six small t/F/chi-square tails and both signed t reports match R without subtraction loss', flush=True)

    expressions = [
        # R's qf approximation loses accuracy here. Use the F(1,df) = t(df)^2 identity.
        ('QF(0.001,1,1e6)', 'qt((1+.001)/2,1e6)^2'),
        ('QF(0.0005,1,1e8,FALSE)', 'qt(.0005/2,1e8,lower.tail=FALSE)^2'),
        ('QT(0.975,1e8)', 'qt(.975,1e8)'),
        ('PT(-1e20,2)', 'pt(-1e20,2)'),
        ('PF(1e20,2,1000,FALSE,TRUE)', 'pf(1e20,2,1000,lower.tail=FALSE,log.p=TRUE)'),
        ('PCHISQ(1e12,1e12)', 'pchisq(1e12,1e12)'),
        ('QCHISQ(-1000,2,FALSE,TRUE)', 'qchisq(-1000,2,lower.tail=FALSE,log.p=TRUE)'),
    ]
    for (expression, _), expected in zip(expressions, references([c[1] for c in expressions])):
        result = session.run('ApplyFunction', {
            'data': columns([1]), 'expression': expression, 'new_column_name': 'Reference check'
        })
        cells = [c for c in result['frames'][0]['cells'] if c['row'] == 1 and c['col'] == 0]
        assert len(cells) == 1 and cells[0]['kind'] == 'number', (expression, result)
        near(float(cells[0]['text']), expected, expression)
    print('PASS seven worksheet expressions match R for large degrees of freedom, quantiles and log tails', flush=True)

    result = session.run('RateCompareTwo', {
        'scrap': columns([1, 100], [50000000, 150]), 'do_cml': False, 'gamma': 99.8
    }, {'use-default-ci': False, 'default-ci': '95', 'selectGroupsByIdentifier': False,
        'decp': '12', 'pdecp': '7', 'use-scientific-notation-for-small-p-values': True})
    alpha = (1 - .998) / 2
    lower, upper = references([
        # Exact closed form of the F(df,2) quantile, arranged with expm1/log1p.
        f'1.5*expm1(-log1p(-{alpha:.17g})/50000001)',
        # Independently invert R's forward tail, avoiding its large-df qf approximation.
        f'1.5*2/50000000*exp(uniroot(function(z) pf(exp(z),4,100000000,lower.tail=FALSE,log.p=TRUE)-log({alpha:.17g}), c(-50,50),tol=1e-14)$root)',
    ])
    near(result['values']['irr_from'], lower, 'rate ratio lower limit')
    near(result['values']['irr_to'], upper, 'rate ratio upper limit')
    near(result['values']['irr_to'], 2.7700242710030197463e-7, '70-digit upstream rate ratio reference')
    displayed = re.search(r'exact 99\.8% confidence interval = ([\d.Ee+\-]+) to\s+([\d.Ee+\-]+)', result['html'])
    assert displayed, result['html']
    for printed, expected in zip(map(float, displayed.groups()), [lower, upper]):
        assert abs(printed-expected) <= .5e-12, (printed, expected)  # Selected 12 decimal places.
    print('PASS the 99.8% rate-ratio report uses the corrected inverse and agrees with R and the upstream high-precision reference', flush=True)
finally:
    session.finish()
