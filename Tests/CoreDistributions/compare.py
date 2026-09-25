"""Compare two unmodified Git revisions of the Windows numerical source with R.

This deliberately bypasses the Mac engine host, report renderer and UI.
Differences from R are diagnostics, not automatic proof of a core defect.
"""
import argparse
import csv
import hashlib
import json
import math
import os
from pathlib import Path
import random
import select
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--baseline', default='c956b122c9b77683f58c4d10c221390183968cd3')
parser.add_argument('--candidate', default='dcc2af8f0ec55d736a98acac029297510195e2df')
parser.add_argument('--dotnet', required=True)
parser.add_argument('--output', type=Path, default=ROOT / '.build/core-distributions')
args = parser.parse_args()
work = args.output.resolve()
work.mkdir(parents=True, exist_ok=True)
upstream = ROOT / 'FullEngine/Upstream'
cases = []


def add(fn, x, a, b=0, lower=False, log=False):
    cases.append(dict(id=len(cases), function_name=fn, x=x, a=a, b=b, lower=lower, log=log))


shapes = [.01, .1, .5, 1, 2, 30, 1000, 1e5, 1e8, 1e12]
probabilities = [1e-300, 1e-100, 1e-20, 1e-6, .001, .025, .5, .975, 1-1e-6]
for a in shapes:
    for b in shapes:
        for x in [1e-100, 1e-20, 1e-6, .001, .1, .5, .9, 1-1e-6]:
            add('pbeta', x, a, b, True)
        for p in probabilities:
            add('qbeta', p, a, b, True)
        for x in [1e-100, 1e-20, .001, .1, 1, 1.1, 10, 1e5, 1e100, 1e308]:
            add('pf', x, a, b)
        for p in probabilities:
            add('qf', p, a, b)
    for x in [-1e155, -1e20, -100, -2, -.001, 0, .001, 2, 100, 1e20, 1e155]:
        add('pt', x, a)
    for p in probabilities:
        add('qt', p, a)
    for scale in [1e-20, 1e-6, .1, 1, 2, 10, 1000]:
        add('pchisq', a*scale, a)
        add('pgamma', a*scale, a, lower=True)
        add('pgamma', a*scale, a)
    for p in probabilities:
        add('qchisq', p, a, lower=True)
        add('qchisq', p, a)

# New direct-tail/log interfaces: both sides, underflow, and infinite-df limits.
for a, b in [(2, 30), (30, 2), (1, 1e8), (1e8, 1e8), (2, math.inf), (math.inf, 2)]:
    for lower in [False, True]:
        for x in [1e-100, .001, 1, 1000, 1e20, 1e308]:
            add('pf_direct', x, a, b, lower, True)
        for p in [-1e-20, -.7, -10, -700, -1000, -10000, -1e12]:
            add('qf_direct', p, a, b, lower, True)
for a in [.1, 1, 2, 30, 1e8, math.inf]:
    for lower in [False, True]:
        for x in [-1e20, -10, 0, 10, 1e20, 1.5e154]:
            add('pt_direct', x, a, lower=lower, log=True)
        for p in [-1e-20, -.7, -10, -700, -1000, -10000, -1e12]:
            add('qt_direct', p, a, lower=lower, log=True)

# Ordinary parameter combinations away from the hand-picked grid.
rng = random.Random(508)
for _ in range(100):
    a, b, x, p = 10**rng.uniform(-.5, 3), 10**rng.uniform(-.5, 3), rng.random(), rng.uniform(.001, .999)
    add('pbeta', x, a, b, True)
    add('qbeta', p, a, b, True)
    add('pf', 10**rng.uniform(-2, 2), a, b)
    add('qf', p, a, b)

case_file = work / 'cases.tsv'
with case_file.open('w') as f:
    writer = csv.writer(f, delimiter='\t', lineterminator='\n')
    writer.writerow(cases[0].keys())
    for c in cases:
        writer.writerow('TRUE' if v is True else 'FALSE' if v is False else 'Infinity' if v == math.inf else repr(v) if isinstance(v, float) else v for v in c.values())

env = dict(os.environ, DOTNET_CLI_HOME=str(ROOT / '.build/dotnet-home'), DOTNET_CLI_TELEMETRY_OPTOUT='1')
provenance = {}
for label, revision in [('candidate', args.candidate), ('baseline', args.baseline)]:
    source = work / label / 'source'
    source.mkdir(parents=True, exist_ok=True)
    commit = subprocess.check_output(['git', '-C', str(upstream), 'rev-parse', revision], text=True).strip()
    paths = subprocess.check_output(['git', '-C', str(upstream), 'ls-tree', '-r', '--name-only', commit,
                                    'StatsDirectUI/Numerics'], text=True).splitlines()
    selected = [p for p in paths if p.endswith('/Numerics.cs') or p.endswith('/BetaDistributions.cs')
                or p.endswith('/BetaInverse.cs') or '/SpecialFunctions/' in p and p.endswith('.cs')]
    hashes = {}
    for path in selected:
        content = subprocess.check_output(['git', '-C', str(upstream), 'show', commit + ':' + path])
        target = source / Path(path).relative_to('StatsDirectUI/Numerics')
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(content)
        hashes[path] = hashlib.sha256(content).hexdigest()
    provenance[label] = dict(commit=commit, sha256=hashes)
    build = work / label / 'build'
    command = [args.dotnet, 'build', str(HERE / 'CoreDistributions.csproj'), '-c', 'Release', '--nologo',
               '-p:CoreSource=' + str(source), '-p:BaseIntermediateOutputPath=' + str(build / 'obj') + '/',
               '-o', str(build / 'bin')]
    with (work / (label + '-build.log')).open('w') as log:
        subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
    process = None
    with (work / (label + '.tsv')).open('w') as output:
        for line in case_file.read_text().splitlines()[1:]:
            if process is None:
                process = subprocess.Popen([args.dotnet, str(build / 'bin/CoreDistributions.dll')], env=env,
                                           stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
            process.stdin.write(line + '\n')
            process.stdin.flush()
            if select.select([process.stdout], [], [], 2)[0]:
                result = process.stdout.readline()
                if not result: raise RuntimeError(label + ' core test process stopped unexpectedly')
                output.write(result)
            else:
                process.kill()
                process.wait()
                process = None
                output.write(line.split('\t')[0] + '\tNaN\ttimeout_2s\n')
            output.flush()
    if process is not None:
        process.stdin.close()
        process.wait()
    print('Completed unmodified Windows core:', label, commit[:12], flush=True)

rscript = '/Library/Frameworks/R.framework/Resources/bin/Rscript'
subprocess.run([rscript, '--vanilla', str(HERE / 'reference.R'), str(case_file), str(work / 'R.tsv')], check=True, timeout=180)
provenance['R'] = subprocess.check_output([rscript, '--vanilla', '-e', 'cat(R.version.string)'], text=True)


def read_results(path):
    with path.open() as f:
        return {int(c[0]): (float(c[1]), c[2]) for c in csv.reader(f, delimiter='\t')}


references = read_results(work / 'R.tsv')
summary = {}
differences = []
for label in ['baseline', 'candidate']:
    output = read_results(work / (label + '.tsv'))
    counts = {}
    for c in cases:
        value, status = output[c['id']]
        expected, warning = references[c['id']]
        if status == 'unsupported': continue
        fn = c['function_name']
        stat = counts.setdefault(fn, dict(tested=0, agree=0, differ=0, faults=0, rWarnings=0))
        stat['tested'] += 1
        stat['rWarnings'] += bool(warning)
        stat['faults'] += status != '0'
        agree = status == '0' and (value == expected or math.isnan(value) and math.isnan(expected)
            or math.isfinite(value) and math.isfinite(expected)
            and abs(value - expected) <= 2e-10 * (max(1, abs(expected)) if c['log'] else abs(expected)))
        stat['agree' if agree else 'differ'] += 1
        if not agree:
            differences.append(dict(version=label, **c, actual=value, R=expected, status=status, rWarning=warning))
    summary[label] = counts

(work / 'summary.json').write_text(json.dumps(dict(provenance=provenance, caseCount=len(cases), results=summary), indent=2) + '\n')
with (work / 'differences.tsv').open('w') as f:
    writer = csv.DictWriter(f, fieldnames=differences[0].keys(), delimiter='\t', lineterminator='\n')
    writer.writeheader()
    writer.writerows(differences)
print(json.dumps(summary, indent=2))
print('Full cases, raw results, discrepancies and source hashes:', work)
