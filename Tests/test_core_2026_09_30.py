"""New core behaviour through Mac input forms and the original report renderer."""
import re
import subprocess
from test_menu import Session, columns, near

session = Session()
try:
    summary = session.run('UnivariateSummary', {'data': columns([42])})
    for label in ['Median', 'Lower quartile', 'Upper quartile', 'Centile 5', 'Centile 95']:
        assert f'<td>{label}</td><td>42</td>' in summary['html'], label
    print('PASS: one-observation summary reports the median, quartiles and centiles')

    data = [[.25, .5, 1], [.75, 1.25, .25], [1.5, .5, 2]]
    ordinary = session.run('TwoWay', {'data': columns(*data)})
    shifted = session.run('TwoWay', {'data': columns(*[[1e15 + v for v in c] for c in data])})
    keys = ['sub_sum', 'grp_sum', 'res_sum', 'tot_sum', 'sub_vr', 'grp_vr', 'sub_p', 'grp_p']
    for key in keys:
        near(shifted['values'][key], ordinary['values'][key])
    reference = subprocess.check_output([
        '/Library/Frameworks/R.framework/Resources/bin/Rscript', '--vanilla', '-e',
        'x <- matrix(c(.25,.5,1,.75,1.25,.25,1.5,.5,2),nrow=3); '
        'fit <- aov(as.vector(x) ~ factor(row(x)) + factor(col(x))); '
        'cat(sprintf("%.17g", summary(fit)[[1]][,"Sum Sq"]),sep="\\n")'
    ], text=True)
    for key, value in zip(['sub_sum', 'grp_sum', 'res_sum'], map(float, reference.splitlines())):
        near(shifted['values'][key], value)
    print('PASS: two-way ANOVA preserves quarter-unit differences at 1e15 and agrees with R')

    tiny = session.run('Wilcoxon', {'data': columns([i * 1e-320 for i in range(1, 6)])})
    assert tiny['values']['non_0'] == 5
    near(tiny['values']['p_2'], .0625)  # 2 of the 32 equally likely sign arrangements.
    print('PASS: subnormal signed-rank differences retain their exact P value')

    for method, values in [('Gini', [1, 2, 4, 8, 16]), ('Diversity', [5, 5, 5, 5])]:
        inputs = {'data': columns(values), 'boots': 1000, 'seed': 12345}
        first = session.run(method, inputs)
        second = session.run(method, inputs)
        # A chart can have a new identity; compare the actual numerical report.
        text = lambda r: r['html'].split('<svg')[0]
        assert text(first) == text(second), method
        assert re.search(r'Seed[^<]*12345', first['html'], re.I), first['html'][:1500]
        assert any(p['name'] == 'seed' and p['value'] == 12345 for p in first['history'])
        changed = session.run(method, {**inputs, 'seed': 12346})
        assert text(first).replace('12345', '') != text(changed).replace('12346', ''), method
    print('PASS: Gini and diversity forms accept, record and reproduce the bootstrap seed')
finally:
    session.finish()
