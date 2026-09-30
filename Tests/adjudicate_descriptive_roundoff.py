"""Check fresh-R skewness differences by exact symmetry, without changing tolerances.

The upstream test is instrumented only to emit every failed comparison. Its raw
exit code remains a failure; this separate adjudication proves that those inputs
have exactly zero third central moment, including their binary64 representation.
"""
import argparse
from fractions import Fraction
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--dotnet', required=True)
p.add_argument('--references', type=Path, required=True)
a = p.parse_args()
refs = a.references.resolve()
work = ROOT / '.build/descriptive-roundoff'
work.mkdir(parents=True, exist_ok=True)
engine = ROOT / 'FullEngine/publish'
source = (ROOT / 'FullEngine/Upstream/tests/Descriptive/Program.cs').read_text()
marker = '                    k.bad++;'
assert source.count(marker) == 1
source = source.replace(marker, marker + '\n                    Console.WriteLine("DIFFERENCE " + System.Text.Json.JsonSerializer.Serialize(new { report = f[0], id = f[1], inputs = f[2], output, actual = shown, expected = figure }));')
(work / 'Program.cs').write_text(source)
(work / 'Check.csproj').write_text('''<Project Sdk="Microsoft.NET.Sdk">
<PropertyGroup><OutputType>Exe</OutputType><TargetFramework>net10.0</TargetFramework><ImplicitUsings>enable</ImplicitUsings></PropertyGroup>
<ItemGroup><Reference Include="''' + escape(str(engine)) + '''/*.dll" />
<Content Include="''' + escape(str(engine)) + '''/*.dll"><CopyToOutputDirectory>PreserveNewest</CopyToOutputDirectory><Link>%(Filename)%(Extension)</Link></Content></ItemGroup>
</Project>''')
env = dict(os.environ, DOTNET_CLI_HOME=str(ROOT / '.build/dotnet-home'),
           NUGET_PACKAGES=str(ROOT / '.build/nuget'), DOTNET_CLI_TELEMETRY_OPTOUT='1')
with (work / 'build.log').open('w') as log:
    subprocess.run([a.dotnet, 'build', str(work / 'Check.csproj'), '-c', 'Release', '-o', str(work / 'bin')], env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
bench = work / 'bin/benchmarks'
bench.mkdir(exist_ok=True)
for f in refs.glob('*.txt'):
    shutil.copyfile(f, bench / f.name)
result = subprocess.run([a.dotnet, str(work / 'bin/Check.dll')], env=env, capture_output=True, text=True, timeout=120)
(refs / 'adjudication-raw.log').write_text(result.stdout + result.stderr)
differences = [json.loads(line.removeprefix('DIFFERENCE ')) for line in result.stdout.splitlines() if line.startswith('DIFFERENCE ')]
assert result.returncode == 1 and '1 OF 137 CHECKS FAILED' in result.stdout, result.stdout[-2000:]
assert len(differences) == 19, len(differences)
for d in differences:
    assert d['report'] == 'RptUnivariateSummary', d
    field = re.fullmatch(r'\*fields\[12\]\.\*results\[(\d+)\]\.result', d['output'])
    assert field and float(d['actual']) == 0 and 0 < abs(float(d['expected'])) < 1e-15, d
    inputs = dict(part.split('=', 1) for part in d['inputs'].split(';'))
    values = inputs['data'].split('|')[int(field[1]) - 1].split(',')
    data = sorted(Fraction.from_float(float(x)) for x in values if x != '*')
    assert len(data) > 3 and data[0] != data[-1], d
    pair_sum = data[0] + data[-1]
    assert all(x + y == pair_sum for x, y in zip(data, reversed(data))), d
    center = sum(data) / len(data)
    assert sum((x - center) ** 3 for x in data) == 0, d
    d['adjudication'] = 'Exact binary64 rational arithmetic: symmetric sample, third central moment exactly zero; engine is correct.'
summary = dict(engineSHA256=hashlib.sha256((engine / 'StatsDirect.Headless.dll').read_bytes()).hexdigest(),
               rawExitCode=result.returncode, adjudicated=True, differences=differences,
               largestRResidual=max(abs(float(d['expected'])) for d in differences))
(refs / 'adjudication.json').write_text(json.dumps(summary, indent=2) + '\n')
print(f"Adjudicated all {len(differences)} differences: exact symmetry proves zero skewness; largest R residual {summary['largestRResidual']:.6g}. No engine, expected value or test tolerance changed.")
