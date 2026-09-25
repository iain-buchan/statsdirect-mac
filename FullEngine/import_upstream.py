"""Record or verify the calculation source in the pinned StatsDirect submodule.

This never downloads, changes or copies calculation code. Update the submodule
explicitly, review the Mac platform copies, then regenerate the manifest.
"""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess
import xml.etree.ElementTree as ET

base = Path(__file__).resolve().parent
source = base / 'Upstream'
manifest_path = base / 'upstream-manifest.json'
info_path = base.parent / 'Content/engine-info.json'
repository = 'https://github.com/iain-buchan/statsdirect'


def snapshot():
    if not (source / '.git').exists():
        raise SystemExit('Engine submodule is missing. Run: git submodule update --init --recursive')
    revision = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
    if subprocess.check_output(['git', '-C', str(source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip():
        raise SystemExit('The engine submodule has local changes. Restore or commit them before recording provenance.')
    files = []
    for folder in ['Builtins', 'Numerics', 'Data', 'Templates', 'Utilities', 'Creole', 'Expressions', 'CsvParser', 'Configuration', 'TemplateProcessing', 'Charting', 'R']:
        files.extend(p for p in (source / 'StatsDirectUI' / folder).rglob('*')
                     if p.suffix in ('.cs', '.g4') and 'obj' not in p.parts and 'bin' not in p.parts)
    for folder in ['Operations', 'UserOperations', 'Template']:
        files.extend(p for p in (source / 'StatsDirectUI/Assets' / folder).rglob('*') if p.is_file())
    for name in ['OperationTestHost', 'OperationsTester', 'Pane', 'PaneAndPosition', 'ChartOptionsParameter', 'FillableParameter', 'Settings']:
        files.append(source / 'StatsDirectUI/UI' / f'{name}.cs')
    files.extend(p for p in (source / 'Layout').rglob('*.cs') if 'obj' not in p.parts and 'bin' not in p.parts)
    files.extend(source / path for path in ['StatsDirectUI/StatsDirectUI.csproj', 'StatsDirectUI/Assets/menu.xml', 'StatsDirectUI/Assets/Data/test.xlsx'])
    hashes = {str(p.relative_to(source)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(files)}
    version = ET.parse(source / 'StatsDirectUI/StatsDirectUI.csproj').findtext('.//Version')
    return {'repository': repository, 'commit': revision, 'version': version, 'sha256': hashes}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Verify the pinned revision and every source hash without writing.')
    args = parser.parse_args()
    current = snapshot()
    info = {key: current[key] for key in ['repository', 'commit', 'version']}
    if args.check:
        if current != json.loads(manifest_path.read_text()):
            raise SystemExit('Engine revision or source hashes differ from upstream-manifest.json. Review the update before regenerating provenance.')
        if info != json.loads(info_path.read_text()):
            raise SystemExit('Displayed engine version differs from the pinned engine revision.')
        print(f"Verified engine {current['commit'][:12]}: {len(current['sha256'])} source and asset files")
    else:
        manifest_path.write_text(json.dumps(current, indent=2) + '\n')
        info_path.write_text(json.dumps(info, indent=2) + '\n')
        print(f"Recorded engine {current['commit'][:12]}: {len(current['sha256'])} source and asset files")


if __name__ == '__main__':
    main()
