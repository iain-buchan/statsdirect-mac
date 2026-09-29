"""Updated operation definitions and calculations through the Mac form/report bridge."""
import math
import subprocess
from test_menu import Session, columns, near

R = '/Library/Frameworks/R.framework/Resources/bin/Rscript'

def reference(expression):
    output = subprocess.check_output([R, '--vanilla', '-e',
        'cat(sprintf("%.17g", {' + expression + '}), sep="\\n")'], text=True)
    return list(map(float, output.splitlines()))

session = Session()
try:
    report = session.run('RateCompareTwo', {
        'scrap': columns([40, 10], [12, 20]), 'do_cml': False
    })
    limits = reference('difference <- 40/10 - 12/20; se <- sqrt(40/10^2 + 12/20^2); '
                       'difference + c(-1,1)*qnorm(.975)*se')
    for key, expected in zip(['ird_from', 'ird_to'], limits):
        near(report['values'][key], expected)
    assert report['values']['pc'] == 95
    assert '95% confidence interval' in report['html']
    print('PASS: corrected rate-difference confidence limits match R through the Mac report')

    # Person-time need not exceed the event count. Both Windows entry routes now
    # share the calculation; the Mac must also admit this valid input in its form.
    screen = session.run('RateDirectScreen', {
        'data': columns([30, 15], [10, 5], [100, 200]), 'nunit': '1000'
    })
    sheet = session.run('RateDirect', {
        'idxn': columns([30, 15]), 'times': columns([10, 5]),
        'refn': columns([100, 200]), 'nunit': '1000'
    })
    assert screen['values'] == sheet['values']
    near(screen['values']['stdr'], 3000)
    expected = reference('events <- c(30,15); time <- c(10,5); w <- c(100,200)/300; '
                         'sqrt(sum(w^2*events/time^2))*1000')[0]
    near(screen['values']['ser_small'], expected)
    print('PASS: direct standardisation accepts events greater than person-time; form and worksheet reports agree')

    cox = session.run('CoxRegression', {
        'times': columns(range(1, 13)),
        'events': columns([1, 0, 1, 1, 0, 1, 0, 1, 1, 0, 1, 1]),
        'predictors': columns([.1, .8, .2, .7, .4, .9, .3, .6, .5, .8, .2, .9]),
        'centre-continuous-covariates': True
    })
    history = {p['name']: p['value'] for p in cox['history']}
    assert history['accuracy'] == 1e-9
    assert not any('split' in name.lower() for name in history)
    expected = reference('library(survival); fit <- coxph(Surv(1:12, '
        'c(1,0,1,1,0,1,0,1,1,0,1,1)) ~ c(.1,.8,.2,.7,.4,.9,.3,.6,.5,.8,.2,.9)); '
        '2*diff(fit$loglik)')[0]
    assert math.isclose(cox['values']['x2'], expected, rel_tol=1e-9)
    print('PASS: Cox form uses the new precision, omits splitting ratio and agrees with R survival')

    ident, state = session.start('PropSingle')
    try:
        assert state['prompt']['name'] == 'n'
        session.request(action='answer', id=ident, token=state['token'], value=2.5)
        state = session.wait(ident)
        assert state['state'] == 'input' and state['prompt']['error'], state
        assert state['prompt']['name'] == 'n'
    finally:
        session.close(ident)
    print('PASS: single-proportion form rejects a fractional observation count before analysis')
finally:
    session.finish()
