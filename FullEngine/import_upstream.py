"""Vendor the whole headless engine source and record provenance; no numerical edits."""
from pathlib import Path
import hashlib, json, shutil, subprocess, sys
source=Path(sys.argv[1]).resolve()
target=Path(__file__).resolve().parent/'Upstream'
files=[]
for folder in ['Builtins','Numerics','Data','Templates','Utilities','Creole','Expressions','CsvParser','Configuration','TemplateProcessing','Charting','R']:
    files.extend(p for p in (source/'StatsDirectUI'/folder).rglob('*') if p.suffix in ('.cs','.g4') and 'obj' not in p.parts and 'bin' not in p.parts)
for folder in ['Operations','UserOperations','Template']:
    files.extend(p for p in (source/'StatsDirectUI/Assets'/folder).rglob('*') if p.is_file())
for name in ['OperationTestHost','OperationsTester','Pane','PaneAndPosition','ChartOptionsParameter','FillableParameter','Settings']:
    files.append(source/'StatsDirectUI/UI'/f'{name}.cs')
files.extend(p for p in (source/'Layout').rglob('*.cs') if 'obj' not in p.parts and 'bin' not in p.parts)
hashes={}
for f in files:
    relative=f.relative_to(source);dest=target/relative;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(f,dest)
    hashes[str(relative)]=hashlib.sha256(f.read_bytes()).hexdigest()
manifest={'repository':'https://github.com/iain-buchan/statsdirect','commit':subprocess.check_output(['git','-C',str(source),'rev-parse','HEAD'],text=True).strip(),'sha256':hashes}
(target.parent/'upstream-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(f'Vendored {len(files)} engine source and asset files')
