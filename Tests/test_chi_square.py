"""Original screen-data operation through the same native bridge as the Mac form."""
import json, math, subprocess, sys, uuid, re, xml.etree.ElementTree as ET
from pathlib import Path
root = Path(__file__).resolve().parents[1]
driver = Path(sys.argv[1]).resolve()
library = root / 'FullEngine/publish/StatsDirectEngine.dylib'
process = subprocess.Popen([str(driver), str(library)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
counts = [[17,9,8],[6,5,1],[3,5,4],[1,2,5]]
def run(**changes):
    data = dict(counts=counts, xp=True, cs=True); data.update(changes)
    process.stdin.write(json.dumps(dict(action='run', id=str(uuid.uuid4()), input=data))+'\n'); process.stdin.flush()
    return json.loads(process.stdout.readline())
def near(actual, expected, tolerance=1e-10):
    assert math.isclose(actual, expected, rel_tol=tolerance, abs_tol=tolerance), (actual, expected)
try:
    original = run(); assert 'error' not in original, original
    values = original['values']
    # Independent R calculations, using precisely the help example's counts.
    rscript = '/Library/Frameworks/R.framework/Resources/bin/Rscript'
    r = subprocess.check_output([rscript,'--vanilla','-e', '''x <- matrix(c(17,9,8,6,5,1,3,5,4,1,2,5),nrow=4,byrow=TRUE)
a <- suppressWarnings(chisq.test(x,correct=FALSE)); f <- fisher.test(x)
g <- 2*sum(x*log(x/a$expected)); cat(sprintf("%.17g",c(a$statistic,a$parameter,a$p.value,g,pchisq(g,6,lower.tail=FALSE),f$p.value)),sep=",")'''], text=True)
    for key, expected in zip(['chio','dfo','po','g2','pog2','p2'], map(float,r.split(','))): near(values[key],expected)
    for key, expected in dict(chit=5.6598, gamma=.349223,taub=.236078,phi=.388447,cramer=.274673).items(): near(values[key], expected, 1e-6)
    html = original['html']
    for text in ['Expected','DChi','% of row','Warning: 9 out of 12','Fisher-Freeman-Halton','0.1264','0.1426']: assert text in html, text
    assert original['total'] == 66 and original['operation'] == 'ExactChiRbyCScreen'
    print('PASS: help example matches independent R Pearson, G and Fisher exact calculations; original report and warnings retained')
    transposed = run(counts=list(map(list,zip(*counts))))
    for key in ['chio','po','g2','p2']: near(transposed['values'][key],values[key])
    edited = run(counts=[[18,9,8],*counts[1:]])
    assert edited['values']['chio'] != values['chio']
    reduced = run(doExact=False,show_pc=False,xp=False,cs=False)
    for text in ['Expected','DChi','% of row']: assert text not in reduced['html'],text
    assert reduced['values']['p2'] == 'not calculated'
    print('PASS: transpose invariance, edited data recomputation and original report options')
    scores = run(specify_scores=True,rowScores=[1,2,4,8],columnScores=[1,3,4])
    assert 'error' not in scores,scores
    near(scores['values']['chio'],values['chio']); assert scores['values']['chit'] != values['chit']
    mc1 = run(doExact=False,doMonteCarlo=True,iterations=5000,seed=9123)
    mc2 = run(doExact=False,doMonteCarlo=True,iterations=5000,seed=9123)
    assert 'error' not in mc1,mc1
    for key in ['*pmcx2','*pmcg2','*pmcx2eq','*pmcx2trend']:
        assert mc1['values'][key] == mc2['values'][key]
        assert mc1['values'][key][0]['its'] == 5000
    print('PASS: custom trend scores leave Pearson unchanged; fixed-seed simulation repeats exactly')
    for data in [dict(counts=[[0,0],[2,3]]),dict(counts=[[0,1],[0,2]]),dict(counts=[[1,-1],[2,3]]),dict(counts=[[1,1.2],[2,3]]),dict(counts=[[1,None],[2,3]]),dict(counts=[[1,2],[3]]),dict(cco=1),dict(specify_scores=True,rowScores=[1,1,1,1],columnScores=[1,2,3]),dict(doMonteCarlo=True,iterations=10000001),dict(doMonteCarlo=True,seed=0)]:
        assert 'error' in run(**data),data
    assert 'error' not in run(counts=[[0,2],[3,0]])
    assert run(counts=[[60000,1],[2,60000]])['exactSkipped']
    print('PASS: invalid/missing/fractional counts, margins, confidence and simulation settings rejected; individual zeros accepted')
finally:
    process.stdin.close(); process.wait(timeout=15)
# Cancel while a long simulation is being prepared/run. The engine must not return a partial report.
id = str(uuid.uuid4())
request = dict(action='run',id=id,input=dict(counts=counts,doExact=False,doMonteCarlo=True,iterations=10000000,seed=9123))
output = subprocess.run([str(driver),str(library),'1500',id], input=json.dumps(request)+'\n',text=True,capture_output=True,timeout=30)
assert json.loads(output.stdout) == {'cancelled':True},output.stdout
print('PASS: cancellation returns no partial report')
