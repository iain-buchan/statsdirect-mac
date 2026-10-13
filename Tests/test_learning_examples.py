from r_runtime import rscript as find_rscript
"""Verify the new worksheet examples against the unchanged Windows core and base R."""
from pathlib import Path
import csv, json, math, subprocess, tempfile
from test_menu import Session, columns
root=Path(__file__).resolve().parents[1]
lessons={l['id']:l for l in json.loads((root/'Content/Learn/lessons.json').read_text())}

def lesson_r_intervals():
 # Run the actual shipped script and then reuse its helper with changed counts.
 # Include boundaries, unequal sizes, rare events and several confidence levels.
 cases=[(28,200,16,200),(0,20,0,20),(20,20,20,20),(0,20,20,20),
        (20,20,0,20),(0,3,2,5),(3,3,2,5),(1,1,0,1),
        (1,7,10,100),(1,1000,8,1500),(17,20,2,80),(1,2,1,2)]
 with tempfile.TemporaryDirectory(prefix='statsdirect-learning-intervals-') as folder:
  folder=Path(folder)
  rows=[[*case,level] for level in (.90,.95,.99) for case in cases]
  counts=','.join(str(value) for row in rows for value in row)
  (folder/'check.R').write_text(f'pdf({json.dumps(str(folder/"plot.pdf"))})\n'+lessons['risk']['r']+f'''
cases <- as.data.frame(matrix(c({counts}),ncol=5,byrow=TRUE))
names(cases) <- c("x1","n1","x0","n0","level")
limits <- t(apply(cases,1,function(v) {{
  ci <- mn_interval(v[1],v[2],v[3],v[4],v[5])
  reverse <- mn_interval(v[3],v[4],v[1],v[2],v[5])
  complement <- mn_interval(v[2]-v[1],v[2],v[4]-v[3],v[4],v[5])
  estimate <- v[1]/v[2]-v[3]/v[4]
  stopifnot(all(is.finite(ci)),ci[1]>= -1,ci[2]<=1,
            ci[1]<=estimate,ci[2]>=estimate,
            max(abs(ci+rev(reverse)))<1e-11,
            max(abs(ci+rev(complement)))<1e-11)
  ci
}}))
for(i in seq_len({len(cases)})) {{
  stopifnot(limits[i,1]>=limits[i+{len(cases)},1],limits[i,2]<=limits[i+{len(cases)},2],
            limits[i+{len(cases)},1]>=limits[i+{2*len(cases)},1],limits[i+{len(cases)},2]<=limits[i+{2*len(cases)},2])
}}
for(bad in list(c(-1,20,2,20,.95),c(21,20,2,20,.95),c(1.5,20,2,20,.95),
                c(0,0,2,20,.95),c(1,20,2,20,1),c(1,20,2,20,0))) {{
  stopifnot(inherits(try(do.call(mn_interval,as.list(bad)),silent=TRUE),"try-error"))
}}
write.csv(cbind(cases,limits),{json.dumps(str(folder/"intervals.csv"))},row.names=FALSE)
dev.off()
''')
  subprocess.run([find_rscript(),'--vanilla',str(folder/'check.R')],check=True,capture_output=True,text=True)
  return list(csv.DictReader((folder/'intervals.csv').open()))

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
 for key,value in [('sensitive_from',.702457549867273),('sensitive_to',.8769444539890856)]:
  assert math.isclose(diagnostic[key],value,rel_tol=1e-11),(key,diagnostic[key])
 print('PASS learning diagnostic denominators, grid orientation and Clopper-Pearson interval')
 benefit=s.run('MiscNumberNeededToTreat',{'nt':200,'xt':16,'nc':200,'xc':28})['values']
 assert math.isclose(benefit['rd'],.06) and math.isclose(benefit['rre'],4/7)
 assert benefit['treat_round']=='17_benefit'
 assert benefit['rd_from']<0<benefit['rd_to']
 assert math.isclose(benefit['rd_from'],-.00144505772741457,abs_tol=1e-12)
 assert math.isclose(benefit['rd_to'],.123548112373396,abs_tol=1e-12)
 print('PASS learning NNT: direction, point estimate and Miettinen-Nurminen uncertainty spanning no effect')
 interval_rows=lesson_r_intervals()
 for row in interval_rows:
  result=s.run('PropUnPaired',{'n1':int(row['n1']),'r1':int(row['x1']),
                             'n2':int(row['n0']),'r2':int(row['x0'])},
               {'default-ci':str(round(float(row['level'])*100))})['values']
  assert result['ci']==round(float(row['level'])*100),result
  for r_key,engine_key in [('lower','from'),('upper','to')]:
   assert math.isclose(float(row[r_key]),result[engine_key],abs_tol=1e-11,rel_tol=1e-11),(row,result)
 print(f'PASS learning R score interval: {len(interval_rows)} Windows-core comparisons at 90/95/99%, including zero/all events, unequal groups, symmetry, widening intervals and invalid input')
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
