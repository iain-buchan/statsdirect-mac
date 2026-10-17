#!/usr/bin/env python3
"""Check native deployment targets and matching packaged debug symbols."""
import argparse
import json
from pathlib import Path
import plistlib
import re
import subprocess


def uuids(path):
    output = subprocess.check_output(['xcrun', 'dwarfdump', '--uuid', str(path)], text=True)
    values = set(re.findall(r'UUID: ([0-9A-Fa-f-]+) \(([^)]+)\)', output))
    if not values:
        raise RuntimeError(f'No Mach-O UUID found: {path}')
    return values


def check_deployment_targets(app):
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    def version(value):
        return tuple((list(map(int, value.split('.'))) + [0, 0])[:3])
    minimum = version(info['LSMinimumSystemVersion'])
    magics = {bytes.fromhex(value) for value in (
        'feedface', 'cefaedfe', 'feedfacf', 'cffaedfe',
        'cafebabe', 'bebafeca', 'cafebabf', 'bfbafeca')}
    checked = 0
    for path in sorted((app / 'Contents').rglob('*')):
        if not path.is_file() or path.is_symlink():
            continue
        with path.open('rb') as handle:
            if handle.read(4) not in magics:
                continue
        # FAT Mach-O and Java class files share a magic value.
        if 'Mach-O' not in subprocess.check_output(['file', '-b', str(path)], text=True):
            continue
        output = subprocess.check_output(['xcrun', 'vtool', '-show-build', str(path)], text=True)
        targets = re.findall(r'^\s*minos ([\d.]+)\s*$', output, re.MULTILINE)
        if not targets or any(version(target) > minimum for target in targets):
            raise RuntimeError(f'{path.relative_to(app)} requires {targets or "an unknown OS"}; '
                               f'app supports macOS {info["LSMinimumSystemVersion"]}')
        checked += 1
    if checked == 0:
        raise RuntimeError(f'No native binaries found: {app}')
    print(f'PASS: {checked} native binaries support the advertised macOS {info["LSMinimumSystemVersion"]} minimum')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    parser.add_argument('symbols', type=Path)
    args = parser.parse_args()
    check_deployment_targets(args.app)
    for binary, name in [
        ('MacOS/StatsDirect', 'StatsDirect.app'),
        ('Frameworks/StatsDirectEngine.dylib', 'StatsDirectEngine.dylib'),
        ('Resources/Engine/libStatsDirectText.dylib', 'libStatsDirectText.dylib'),
    ]:
        actual = uuids(args.app / 'Contents' / binary)
        symbols = args.symbols / (name + '.dSYM')
        expected = uuids(symbols)
        if actual != expected:
            raise RuntimeError(f'Debug symbols do not match {binary}: {actual} != {expected}')
        statistics = json.loads(subprocess.check_output(
            ['xcrun', 'dwarfdump', '--statistics', str(symbols)], text=True))
        if statistics.get('#functions with location', 0) == 0:
            raise RuntimeError(f'Debug symbols have no function locations: {symbols}')
        print(f'PASS: matching debug symbols for {name}: {sorted(actual)}')
