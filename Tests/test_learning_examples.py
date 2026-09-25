"""Verify the new worksheet examples against the unchanged Windows core and base R."""
from pathlib import Path
import json, math, subprocess
from test_menu import Session, columns
root=Path(__file__).resolve().parents[1]
lessons={l['id']:l for l in json.loads((root/'Content/Learn/lessons.json').read_text())}
s=Session()
try:
 paired=lessons['paired']['columns']
 result=s.run('TPaired',{'data':columns(*(c['values'] for c in paired)),'doAgreement':False})
 print('PASS learning paired example:',json.dumps(result['values']))
 r_script='x<-c(142,136,151,145,139,148,132,155);y<-c(135,134,143,141,136,140,130,147);t<-t.test(x,y,paired=TRUE);cat(sprintf("%.17g",c(mean(x-y),t$statistic,t$p.value,t$conf.int)),sep="\\n")'
 expected=list(map(float,subprocess.check_output(['/Library/Frameworks/R.framework/Resources/bin/Rscript','--vanilla','-e',r_script],text=True).split()))
 for key,value in zip(['mean','t','tail_2','from','to'],expected):
  assert math.isclose(result['values'][key],value,rel_tol=1e-10,abs_tol=1e-12),(key,value,result['values'][key])
 precision=lessons['precision']['columns']
 result=s.run('UnivariateSummary',{'data':columns(*(c['values'] for c in precision))})
 assert result['html'] and result['state']=='complete';print('PASS learning descriptive example')
 regression=lessons['regression']['columns']
 result=s.run('SimpleLinearRegression',{'y':columns(regression[0]['values']),'x':columns(regression[1]['values'])})
 assert result['html'] and result['state']=='complete';print('PASS learning regression example')
finally:s.finish()
