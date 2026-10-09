#!/usr/bin/env python3
"""Check that each native debug-symbol bundle belongs to the packaged binary."""
import argparse
import json
from pathlib import Path
import re
import subprocess


def uuids(path):
    output = subprocess.check_output(['xcrun', 'dwarfdump', '--uuid', str(path)], text=True)
    values = set(re.findall(r'UUID: ([0-9A-Fa-f-]+) \(([^)]+)\)', output))
    if not values:
        raise RuntimeError(f'No Mach-O UUID found: {path}')
    return values


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    parser.add_argument('symbols', type=Path)
    args = parser.parse_args()
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
