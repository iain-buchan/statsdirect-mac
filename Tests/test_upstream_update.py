"""Exercise 5.0.7 fixes through the Mac host, with independent base R references."""
from html.parser import HTMLParser
import math
from pathlib import Path
import re
import subprocess
from test_menu import Session, columns


class Text(HTMLParser):
    def __init__(self, source):
        super().__init__()
        self.parts = []
        self.feed(source.split('<svg')[0])
        self.text = ' '.join(' '.join(self.parts).split())

    def handle_data(self, value):
        self.parts.append(value)


rscript = Path('/Library/Frameworks/R.framework/Resources/bin/Rscript')
reference = subprocess.check_output([str(rscript), '--vanilla', '-e', '''
options(digits=17)
s <- shapiro.test(c(1,2,2,3,4,5,6,7,8,10))
cat(s$statistic, s$p.value, pnorm(9, lower.tail=FALSE),
    pf(1e20, 5, 10, lower.tail=FALSE), ppois(10, 2, lower.tail=FALSE), sep="\\n")
'''], text=True)
sw_w, sw_p, normal_tail, f_tail, poisson_tail = map(float, reference.split())
preferences = {
    'use-default-ci': True, 'default-ci': '95', 'selectGroupsByIdentifier': False,
    'decp': '12', 'pdecp': '7', 'use-scientific-notation-for-small-p-values': True,
}
s = Session()


def distribution(operation, inputs):
    ident, state = s.start(operation)
    try:
        assert state['prompt']['kind'] == 'fields', state
        s.request(action='answer', id=ident, token=state['token'], value=inputs)
        result = s.wait(ident)
        assert result['state'] == 'complete', result
        return result
    finally:
        s.close(ident)


try:
    x = [1, 2, 2, 3, 4, 5, 6, 7, 8, 10]
    baseline = None
    for label, data in [('ordinary', x), ('large', [v * 1e300 for v in x]),
                        ('tiny', [v * 1e-300 for v in x]), ('shifted', [v + 1e12 for v in x])]:
        result = s.run('Normality', {'data': columns(data)}, preferences)
        text = Text(result['html']).text
        match = re.search(r'Shapiro-Wilk W ([\d.]+), V = [\d.]+, P = ([\d.]+)', text)
        assert match, text
        w, p = map(float, match.groups())
        assert math.isclose(w, sw_w, rel_tol=0, abs_tol=5e-12), (label, w, sw_w)
        assert math.isclose(p, sw_p, rel_tol=0, abs_tol=5e-8), (label, p, sw_p)
        statistics = text[text.index('Skewness'):text.index('No non-normality')]
        if baseline is None:
            baseline = statistics
            assert '<svg' in result['html']
        else:
            assert statistics == baseline, (label, statistics)
    print('PASS normality statistics are invariant under extreme scaling and large offsets; Shapiro-Wilk matches R')

    for data, message in [([3] * 10, 'all the values are the same'),
                          ([1, 2], 'Too few observations for the tests')]:
        result = s.run('Normality', {'data': columns(data)})
        text = Text(result['html']).text
        assert message in text and 'No non-normality detected' not in text, text
    print('PASS constant and two-value samples give explicit normality limitations without a false conclusion')

    for z in (9, -9):
        result = distribution('DistributionNormal', {'x': z})
        tail = result['values']['upper' if z > 0 else 'lower']
        assert math.isclose(tail, normal_tail, rel_tol=1e-12, abs_tol=0), (z, tail, normal_tail)
        two_sided = float(re.search(r'Two-sided P = ([\d.Ee+\-]+)', Text(result['html']).text)[1])
        assert math.isclose(two_sided, 2 * normal_tail, rel_tol=1e-12, abs_tol=0)
    result = distribution('DistributionF', {'x': 1e20, 'df': 5, 'df2': 10})
    assert math.isclose(result['values']['upper'], f_tail, rel_tol=1e-12, abs_tol=0)
    result = distribution('DistributionPoisson', {'df': 11, 'df2': 2})
    # The Windows calculator's upper tail includes the event count.
    assert math.isclose(result['values']['upper'], poisson_tail, rel_tol=1e-10, abs_tol=0)
    print('PASS small normal, F and Poisson upper tails match R without subtraction loss')

    for tau in (-1, 0, 1):
        result = distribution('DistributionKendall', {'x': tau, 'df': 2})
        assert 0 <= result['values']['upper'] <= 1
    ident, state = s.start('DistributionKendall')
    assert next(field for field in state['prompt']['fields'] if field['name'] == 'df')['min'] == 2
    s.request(action='answer', id=ident, token=state['token'], value={'x': 0, 'df': 1})
    state = s.wait(ident)
    assert state['state'] == 'input' and 'at least 2' in state['prompt']['error'], state
    s.close(ident)
    print('PASS Kendall accepts signed tau with two observations and rejects a sample of one')
finally:
    s.finish()
