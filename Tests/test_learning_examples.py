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
 # Reproduce the four-cell layouts stated in the teaching instructions.
 diagnostic=s.run('MiscDiagnostic',{'scrap':columns([72,18],[81,729])})['values']
 for key,value in [('sensitive',.8),('specific',.9),('likely',8/17),('likely_negative',81/83)]:
  assert math.isclose(diagnostic[key],value,rel_tol=1e-12),(key,diagnostic[key])
 print('PASS learning diagnostic denominators and grid orientation')
 benefit=s.run('MiscNumberNeededToTreat',{'nt':200,'xt':16,'nc':200,'xc':28})['values']
 assert math.isclose(benefit['rd'],.06) and math.isclose(benefit['rre'],4/7)
 assert benefit['treat_round']=='17_benefit'
 assert benefit['rd_from']<0<benefit['rd_to']
 print('PASS learning NNT: direction, point estimate and uncertainty spanning no effect')
 cohort=s.run('MiscRelRisk',{'scrap':columns([30,270],[15,285])})['values']
 assert cohort['ratio']==2 and math.isclose(cohort['dif'],.05)
 print('PASS learning cohort: event/non-event counts, risks and reference group')
 age=s.run('MiscRelRisk',{'scrap':columns([44,156],[26,174])})['values']
 assert math.isclose(age['ratio'],22/13) and math.isclose(age['dif'],.09)
 for data in [columns([4,36],[16,144]),columns([40,120],[10,30])]:
  stratum=s.run('MiscRelRisk',{'scrap':data})['values']
  assert stratum['ratio']==1 and stratum['dif']==0
 print('PASS learning age example: crude and both within-age comparisons')
finally:s.finish()
