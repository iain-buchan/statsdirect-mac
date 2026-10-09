"""Require a completed calculation for every supported XML operation in this run.

This is operation coverage, not exhaustive coverage of every branch combination.
Only fresh traces collected by test.sh count; no earlier test results are reused.
"""
import json
import os
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
trace = Path(os.environ['STATSDIRECT_FORM_TRACE'])
operations = set()
for path in (ROOT / 'FullEngine/Upstream/StatsDirectUI/Assets/Operations').glob('*.xml'):
    root = ET.parse(path).getroot()
    namespace = root.tag.partition('}')[0] + '}' if root.tag.startswith('{') else ''
    operations.add(root.findtext(namespace + 'name'))
menu = json.loads((ROOT / 'Content/analysis-menu.json').read_text())['operations']
excluded = {
    'ImportWorksheet': 'Native workbook/file host; covered by the separate file integration suites.',
    'ExportWorksheet': 'Native workbook/file host; covered by the separate file integration suites.',
    'LOESS': 'Existing explicit R deferral; no Mac calculation form.',
    'MethodComparisonRegression': 'Existing explicit R deferral; no Mac calculation form.',
}
assert {op for op, definition in menu.items() if definition.get('unavailable')} == {'LOESS', 'MethodComparisonRegression'}
assert set(excluded) <= operations
expected = operations - set(excluded)
completed = {}
for path in trace.glob('*.jsonl'):
    for line in path.read_text().splitlines():
        record = json.loads(line)
        if record['state'] == 'complete':
            completed.setdefault(record['operation'], set()).add(record['suite'])
missing = sorted(expected - set(completed))
report = {
    'scope': 'At least one completed synthetic calculation per supported operation; not every branch combination.',
    'trace': str(trace),
    'definitions': len(operations),
    'menuCompleted': len(set(menu) & set(completed)),
    'followOnsCompleted': len((expected - set(menu)) & set(completed)),
    'excluded': excluded,
    'missing': missing,
    'operations': [{'operation': op, 'status': 'complete' if op in completed else 'missing', 'suites': sorted(completed.get(op, []))} for op in sorted(expected)],
}
(ROOT / '.build/form-coverage.json').write_text(json.dumps(report, indent=2) + '\n')
assert not missing, ('Operations without completed form replay in this test run', missing)
print(f"PASS form coverage: {report['menuCompleted']} menu + {report['followOnsCompleted']} follow-on operations; {len(excluded)} explicit exclusions")
