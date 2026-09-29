"""Run the upstream calculation tests against the actual Mac headless assembly.

Upstream suite source and reference fixtures are compiled/read in place. Only the
Crosstabs test of the Windows DataGridView control is explicitly omitted. The
Frequencies input helper uses the Mac worksheet converter in place of the Windows
cell-selection helper. All calculation checks and expected values are unchanged.
"""
import argparse
import hashlib
import json
import os
import subprocess
import time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
DEFAULT=['GlmFitRegression','CorrelationRegression','CoxRegression','Agreement','Survival','MetaAnalysis','NoncentralTRegression','Crosstabs','Frequencies','ExactTests','ChiSquare','Proportions','Rates']
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--dotnet',required=True)
p.add_argument('--suite',nargs='+',default=DEFAULT,choices=DEFAULT)
a=p.parse_args()
work=ROOT/'.build/upstream-suites';work.mkdir(parents=True,exist_ok=True)
source=(ROOT/'FullEngine/Upstream/tests/Crosstabs/Reports.cs').read_text()
start=source.index('        // The dialog that asks for the scores')
end=source.index('        // scores that the user gives are the scores of the analysis',start)
source=source[:start]+'        Console.WriteLine("SKIP: Windows ctlScores/DataGridView UI; Mac score entry is checked by the Mac host tests.");\n\n'+source[end:]
source=source.replace('using System.Windows.Forms;\n','')
mac=work/'CrosstabsReports.cs';mac.write_text(source)

# Exercise the Mac worksheet boundary; the Windows helper does not exist here.
source=(ROOT/'FullEngine/Upstream/tests/Frequencies/Program.cs').read_text()
start=source.index('        int rows = columns.Max(c => c.Length);')
end=source.index('        return frame;',start)+len('        return frame;')
source=source[:start]+'        var input = System.Text.Json.JsonSerializer.SerializeToElement(new {\n            columns = columns.Select((values, i) => new { title = titles[i], values }).ToArray()\n        });\n        var reader = typeof(Describe).Assembly.GetType("HostParameters");\n        return (DataFrame)reader.GetMethod("ReadFrame", BindingFlags.NonPublic | BindingFlags.Static)\n            .Invoke(null, new object[] { input, DataAcquisitionMode.CategoryReplaceMissing, null });'+source[end:]
frequency=work/'FrequenciesProgram.cs';frequency.write_text(source)

env=dict(os.environ,DOTNET_CLI_HOME=str(ROOT/'.build/dotnet-home'),NUGET_PACKAGES=str(ROOT/'.build/nuget'),DOTNET_CLI_TELEMETRY_OPTOUT='1')
summary=work/'summary.json'
engine_hash=hashlib.sha256((ROOT/'FullEngine/publish/StatsDirect.Headless.dll').read_bytes()).hexdigest()
revision=subprocess.check_output(['git','-C',str(ROOT/'FullEngine/Upstream'),'rev-parse','HEAD'],text=True).strip()
# Never mix partial reruns with results from an older engine build.
previous=json.loads(summary.read_text()) if summary.exists() else []
results={r['suite']:r for r in previous if r.get('engineSHA256')==engine_hash and r.get('revision')==revision}
for suite in a.suite:
    start=time.monotonic();output=work/suite;output.mkdir(exist_ok=True)
    print('RUN',suite,flush=True)
    project=ROOT/'FullEngine/Upstream/tests/GlmFitRegression/GlmFitRegression.csproj' if suite=='GlmFitRegression' else ROOT/'Tests/UpstreamSuites/UpstreamSuites.csproj'
    log=output/'result.log'
    with log.open('w') as f:
        command=[a.dotnet,'build',str(project),'-c','Release','--nologo','-o',str(output/'bin')]
        if suite!='GlmFitRegression':command += ['-p:Suite='+suite,'-p:MacReports='+str(mac),'-p:MacFrequency='+str(frequency),'-p:BaseIntermediateOutputPath='+str(output/'obj')+'/']
        build=subprocess.run(command,cwd=ROOT,env=env,stdout=f,stderr=subprocess.STDOUT)
        code=build.returncode
        if code==0:
            assembly='GlmFitRegression.dll' if suite=='GlmFitRegression' else 'Upstream'+suite+'.dll'
            try:code=subprocess.run([a.dotnet,str(output/'bin'/assembly)],cwd=ROOT,env=env,stdout=f,stderr=subprocess.STDOUT,timeout=1200).returncode
            except subprocess.TimeoutExpired:code=124;f.write('\nFAIL: suite exceeded 20-minute bound\n')
    result=dict(suite=suite,revision=revision,engineSHA256=engine_hash,exitCode=code,seconds=round(time.monotonic()-start,2),log=str(log.relative_to(ROOT)))
    results[suite]=result;print(json.dumps(result),flush=True)
    if code:print(log.read_text()[-9000:],flush=True)
summary.write_text(json.dumps([results[s] for s in DEFAULT if s in results],indent=2)+'\n')
raise SystemExit(any(results[s]['exitCode'] for s in a.suite))
