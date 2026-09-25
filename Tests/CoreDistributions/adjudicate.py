"""Independent high-precision integral checks for candidate/R discrepancies.

Requires mpmath. Integrates the beta density in log-odds coordinates; it does
not call StatsDirect or R. This is validation evidence, not replacement code.
"""
import argparse
import csv
import math
from pathlib import Path
import sys
import mpmath as mp

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('work', type=Path)
parser.add_argument('--dps', type=int, default=80)
parser.add_argument('--ids', help='Optional comma-separated case identifiers')
parser.add_argument('--output', default='high-precision.tsv')
args = parser.parse_args()
mp.mp.dps = args.dps
work = args.work
selected = set(map(int, args.ids.split(','))) if args.ids else None
cases = list(csv.DictReader((work / 'cases.tsv').open(), delimiter='\t'))


def read(name):
    return {int(c[0]): (float(c[1]), c[2]) for c in csv.reader((work / name).open(), delimiter='\t')}


candidate, reference = read('candidate.tsv'), read('R.tsv')


def beta_log_tail(logit, a, b, lower=False):
    if lower:
        return beta_log_tail(-logit, b, a)
    centre = mp.log(a / b)
    scale = mp.sqrt(1 / a + 1 / b)
    u = (logit - centre) / scale
    ln_beta = mp.loggamma(a) + mp.loggamma(b) - mp.loggamma(a + b)

    def density(v):
        t = centre + scale * v
        # Avoid subtracting two large terms in the far right tail.
        return (-b*t - (a+b)*mp.log1p(mp.exp(-t)) if t > 0
                else a*t - (a+b)*mp.log1p(mp.exp(t))) - ln_beta + mp.log(scale)

    origin = density(u)
    slope = scale * (a - (a+b) / (1 + mp.exp(-logit)))
    width = 1 / max(mp.mpf(1), -slope)
    # Split at the mode too when it lies inside the integration interval.
    points = sorted(set([mp.mpf(0), mp.mpf(1), mp.mpf(5), mp.mpf(20)] + ([-u/width] if u < 0 else [])))
    integral = mp.quad(lambda z: mp.exp(density(u + width*z) - origin), points + [mp.inf])
    return origin + mp.log(width * integral)


def f_log_tail(x, a, b, lower):
    if x <= 0: return -mp.inf if lower else mp.mpf(0)
    if x == mp.inf: return mp.mpf(0) if lower else -mp.inf
    if b == mp.inf and a == 2:
        return mp.log(-mp.expm1(-x)) if lower else -x
    if a == mp.inf and b == 2:
        return -1/x if lower else mp.log(-mp.expm1(-1/x))
    return beta_log_tail(mp.log(a*x/b), a/2, b/2, lower)


def t_log_tail(x, a, lower):
    if x == 0: return -mp.log(2)
    if a == mp.inf:
        return mp.log(mp.erfc((-x if lower else x)/mp.sqrt(2))/2)
    small = beta_log_tail(mp.log(a)-2*mp.log(abs(x)), a/2, mp.mpf('.5'), True) - mp.log(2)
    return small if (x < 0) == lower else mp.log(-mp.expm1(small))


def probability_log(fn, x, a, b, lower):
    if fn == 'pf': return f_log_tail(x, a, b, lower)
    if fn == 'pt': return t_log_tail(x, a, lower)
    if fn == 'pbeta':
        if x <= 0: return -mp.inf if lower else mp.mpf(0)
        if x >= 1: return mp.mpf(0) if lower else -mp.inf
        return beta_log_tail(mp.log(x)-mp.log1p(-x), a, b, lower)
    if fn in ('pchisq', 'pgamma'):
        if fn == 'pchisq': x, a = x/2, a/2
        if x <= 0: return -mp.inf if lower else mp.mpf(0)
        return mp.log(mp.gammainc(a, 0, x, regularized=True) if lower else mp.gammainc(a, x, mp.inf, regularized=True))
    raise ValueError('No independent probability reference for ' + fn)


def check(c, actual):
    fn = c['function_name'].replace('_direct', '')
    x, a, b = (mp.mpf(float(c[k])) for k in ['x', 'a', 'b'])
    lower, log = c['lower'] == 'TRUE', c['log'] == 'TRUE'
    y = mp.mpf(actual)
    if fn.startswith('p'):
        expected_log = probability_log(fn, x, a, b, lower)
        expected = expected_log if log else mp.exp(expected_log)
        tolerance = max(4*mp.mpf(math.ulp(actual)), mp.mpf('2e-10')*(max(1, abs(expected)) if log else abs(expected)))
        return abs(y-expected) <= tolerance, 'value', mp.nstr(expected, 24)

    # Compare the inverse via independently integrated tails. Use the smaller
    # probability directly, without subtracting a rounded probability from one.
    if log:
        target = x if x <= -mp.log(2) else mp.log(-mp.expm1(x))
        small_lower = lower if x <= -mp.log(2) else not lower
    else:
        target = mp.log(x) if x <= .5 else mp.log1p(-x)
        small_lower = lower if x <= .5 else not lower
    if fn == 'qt' and x == .5 and not log:
        return actual == 0, 'symmetry', '0'

    def tail(v):
        return probability_log('p' + fn[1:], v, a, b, small_lower)

    if math.isinf(actual):
        edge = mp.mpf(sys.float_info.max) * (1 if actual > 0 else -1)
        observed = tail(edge)
        beyond = (target > observed if small_lower else target < observed) if actual > 0 else (target < observed if small_lower else target > observed)
        return beyond, 'overflow boundary', mp.nstr(observed, 24)
    tolerance = max(4*mp.mpf(math.ulp(actual)), mp.mpf('2e-10')*(min(y, 1-y) if fn == 'qbeta' else abs(y)))
    left, right = tail(y-tolerance), tail(y+tolerance)
    ok = min(left, right) <= target <= max(left, right)
    return ok, 'inverse bracket log probability', mp.nstr(tail(y), 24)


# Check the integration machinery against closed forms before adjudicating it.
for x in [mp.mpf('.001'), mp.mpf(1), mp.mpf('1e100')]:
    expected = -15 * mp.log1p(2*x/30)
    assert abs(f_log_tail(x, mp.mpf(2), mp.mpf(30), False)-expected) < mp.mpf('1e-40')
    expected = mp.log(mp.atan(1/x)/mp.pi)
    assert abs(t_log_tail(x, mp.mpf(1), False)-expected) < mp.mpf('1e-40')
print('PASS independent integrals match six F/Cauchy closed forms at 40 decimal places', flush=True)

with (work / args.output).open('w') as output:
    writer = csv.writer(output, delimiter='\t', lineterminator='\n')
    writer.writerow(['id', 'function', 'candidate', 'R', 'verified', 'check', 'reference'])
    count = unresolved = 0
    for c in cases:
        i = int(c['id'])
        if selected is not None and i not in selected: continue
        actual, status = candidate[i]
        expected, warning = reference[i]
        log = c['log'] == 'TRUE'
        agree = status == '0' and (actual == expected or math.isnan(actual) and math.isnan(expected)
            or math.isfinite(actual) and math.isfinite(expected) and abs(actual-expected) <= 2e-10*(max(1,abs(expected)) if log else abs(expected)))
        if agree: continue
        try:
            ok, method, value = check(c, actual)
        except Exception as error:
            ok, method, value = False, 'unresolved', str(error)
        writer.writerow([i, c['function_name'], actual, expected, ok, method, value])
        output.flush()
        count += 1
        unresolved += not ok
        if not ok or count % 25 == 0: print(count, 'checked;', unresolved, 'unresolved;', i, method, value, flush=True)
print('High-precision checks:', count, 'unresolved:', unresolved)
raise SystemExit(bool(unresolved))
