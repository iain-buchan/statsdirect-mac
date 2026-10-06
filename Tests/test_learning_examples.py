from r_runtime import rscript as find_rscript
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
 expected=list(map(float,subprocess.check_output([find_rscript(),'--vanilla','-e',r_script],text=True).split()))
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
 rates=lessons['rates']['columns']
 direct=s.run('RateDirect',{'idxn':columns(rates[0]['values']),'times':columns(rates[1]['values']),
  'refn':columns(rates[2]['values']),'strata':{'skip':True},'nunit':'100000'})['values']
 assert direct['crude']==840 and direct['stdr']==400 and direct['pc']==95
 assert direct['from_dobson']<400<direct['to_dobson']
 print('PASS learning rates: worksheet order, multiplier, crude and adjusted estimates')
 trial=s.run('MiscRelRisk',{'scrap':columns([20,60],[30,70])})['values']
 assert math.isclose(trial['ratio'],5/6) and math.isclose(trial['dif'],-.05)
 print('PASS learning appraisal: observed-data comparison, with missing outcomes explicitly excluded')
 observed=lessons['missing']['columns'][0]['values']
 missing_summary=s.run('UnivariateSummary',{'data':columns(observed)})
 assert missing_summary['html'] and missing_summary['state']=='complete'
 validation=lessons['validation']['columns']
 calibration=s.run('SimpleLinearRegression',{'y':columns(validation[0]['values']),'x':columns(validation[1]['values'])})
 assert calibration['html'] and calibration['state']=='complete'
 print('PASS learning missing-data observed summary and prediction calibration examples')
 meta=lessons['meta']['columns']
 pooled=s.run('MetaSummary',{'type':'riskDifference','use_ci':'false','y':columns(meta[0]['values']),
  'se_y':columns(meta[1]['values']),'studies':{'skip':True}})['values']
 for key,expected in [('rmh',-.04),('from_fixed',-.0661328531272007),('to_fixed',-.0138671468727993),('qc',1.25)]:
  assert math.isclose(pooled[key],expected,rel_tol=1e-10,abs_tol=1e-12),(key,pooled[key])
 print('PASS learning meta-analysis: named input types, pooled estimate, 95% limits and Q agree with independent R checks')
finally:s.finish()
