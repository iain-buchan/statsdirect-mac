"""Exercise the bundled original calculator through its native JSON bridge."""
import json
import math
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
driver = sys.argv[1] if len(sys.argv) > 1 else root / '.build/calculator-driver'
library = root / 'FullEngine/publish/StatsDirectEngine.dylib'
cases = [
    ('2+3*4', 14), ('(2+3)*4', 20), ('-2^2', -4), ('4^-2', .0625),
    ('5!', 120), ('SQRT(81)', 9), ('LOG(EE)', 1), ('EXP(0)', 1),
    ('PI', math.pi), ('EE', math.e), ('ABS(-3.5)', 3.5),
    ('=2+3', 5), ('2+\n3*\n4', 14), ('−2^2', -4),
    ('PT(0,10)', .5), ('PNORM(0)', .5),
    ('1<2', 'True'), ('"hello"', 'hello'),
    ('2,5+1,25', 3.75, 'de-DE'), ('PT(0;10)', .5, 'de-DE'),
    ('1.25+2.5', 3.75, 'en-US'),
    ('+'.join(['1'] * 300), 300),
    ('', None), ('   \n', None), ('2+', None), ('2@3', None),
    ('System.IO.File.ReadAllText("/etc/passwd")', None), ('X1+1', None),
    ('1+1', 2),  # A failed expression must not poison subsequent requests.
]
requests = [{'expression': c[0], 'culture': c[2] if len(c) > 2 else 'en-GB'} for c in cases]
run = subprocess.run([str(driver), str(library)], input=''.join(json.dumps(r)+'\n' for r in requests), text=True, capture_output=True, timeout=90)
assert run.returncode == 0, (run.returncode, run.stderr)
replies = [json.loads(line) for line in run.stdout.splitlines()]
assert len(replies) == len(cases), run.stdout
for case, request, reply in zip(cases, requests, replies):
    expected = case[1]
    if expected is None:
        assert reply.get('error'), (case, reply)
    else:
        assert reply.get('expression') == case[0], (case, reply)
        answer = reply['result']
        if isinstance(expected, str):
            assert answer == expected, (case, reply)
        else:
            if request['culture'] == 'de-DE': answer = answer.replace(',', '.')
            assert math.isclose(float(answer), expected, rel_tol=1e-13, abs_tol=1e-14), (case, reply)
print(f'PASS: {len(cases)} calculator engine cases, exact input, locale, multiline and recovery')
