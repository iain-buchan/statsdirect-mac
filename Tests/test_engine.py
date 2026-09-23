"""Exercise the actual NativeAOT library used by the Mac application."""
from pathlib import Path
import ctypes, json, math, sys, hashlib
base=Path(__file__).resolve().parents[1]
manifest=json.loads((base/'Engine/upstream-manifest.json').read_text())
for name, expected in manifest['sha256'].items():
    if 'extracted verbatim' not in name:
        assert hashlib.sha256((base/'Engine/Upstream'/name).read_bytes()).hexdigest()==expected,name
assert hashlib.sha256((base/'Engine/Upstream/Paired.cs').read_bytes()).hexdigest()==manifest['extracted_paired_sha256']
print('PASS: vendored numerical files and extracted paired method match recorded source hashes')
path=Path(sys.argv[1]) if len(sys.argv)>1 else base/'Engine/publish/StatsDirectEngine.dylib'
lib=ctypes.CDLL(str(path.resolve()))
f=lib.statsdirect_paired_t
pointer=ctypes.POINTER(ctypes.c_double)
f.argtypes=[pointer,pointer,ctypes.c_int,ctypes.c_double,pointer,ctypes.c_int];f.restype=ctypes.c_int
fixture=json.loads((base/'Content/paired-example.json').read_text())
a,b=fixture['before'],fixture['after']
def calc(a,b,confidence=.95):
    assert len(a)==len(b)
    aa=(ctypes.c_double*len(a))(*a);bb=(ctypes.c_double*len(b))(*b);out=(ctypes.c_double*11)()
    code=f(aa,bb,len(a),confidence,out,11)
    return code,list(out)
def close(x,y): assert math.isclose(x,y,rel_tol=1e-11,abs_tol=1e-12),(x,y)
code,r=calc(a,b);assert code==0
for i,name in enumerate(['n','mean','sd','sem','from','to','df','t','tail_1','tail_2']): close(r[i],float(fixture['expected'][name]))
assert f'{100*r[10]:.2f}%' in fixture['expected']['pwr']
print('PASS: live paired-test output matches all 10 numeric operation-fixture values and formatted power')
code,reverse=calc(b,a);assert code==0
for i in [1,7]:close(reverse[i],-r[i])
close(reverse[4],-r[5]);close(reverse[5],-r[4]);close(reverse[9],r[9])
print('PASS: swapping pairs reverses effect/CI/t and preserves two-sided P')
code,scaled=calc([x*2 for x in a],[x*2 for x in b]);assert code==0
for i in [1,2,3,4,5]:close(scaled[i],r[i]*2)
close(scaled[7],r[7]);close(scaled[9],r[9])
print('PASS: changing measurement units scales effect/CI and preserves t/P')
code,missing=calc(a+[math.nan,100],b+[100,math.nan]);assert code==0
for x,y in zip(missing,r):close(x,y)
print('PASS: incomplete pairs are excluded pairwise')
assert calc([1,1],[0,0])[0]==3
assert calc([1,2],[1,2])[0]==3
assert calc([1,math.nan],[0,1])[0]==2
assert calc(a,b,1)[0]==1
print('PASS: constant differences, insufficient pairs and invalid confidence fail explicitly')
code,edited=calc([a[0]+20]+a[1:],b);assert code==0;assert edited[1]!=r[1] and edited[9]!=r[9]
print('PASS: edited data produces a new calculation')
print(json.dumps(dict(zip(['n','mean','sd','sem','lower','upper','df','t','p_one','p_two','power'],r)),indent=2))
