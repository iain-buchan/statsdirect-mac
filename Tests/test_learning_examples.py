from r_runtime import rscript as find_rscript
"""Every lesson's "Try in StatsDirect" example, run through the unchanged Windows core, gives the figures the lesson quotes.

A lesson that names an operation must have its example checked here: the test fails for one that has none, so a new lesson
cannot ship with an unchecked example. Where base R can compute the same figure it is the reference."""
from pathlib import Path
import csv, html, json, math, re, subprocess, tempfile
from test_menu import Session, columns
root=Path(__file__).resolve().parents[1]
lessons={l['id']:l for l in json.loads((root/'Content/Learn/lessons.json').read_text())}
checked=set()
def example(id,operation):
 """The lesson's worksheet columns by title, after confirming the lesson opens this operation."""
 assert lessons[id].get('operation')==operation,(id,lessons[id].get('operation'),operation)
 checked.add(id)
 return {c['title']:c['values'] for c in lessons[id].get('columns') or []}
def report(result):
 """The report's text, one line per table row or paragraph."""
 text=html.unescape(re.sub(r'<[^>]+>',' ',re.sub(r'</(tr|p|div|h\d|li)>|<br ?/?>','\n',result['html'])))
 return [re.sub(r'[ \t\xa0]+',' ',line).strip() for line in text.splitlines() if line.strip()]
def stated(id,*phrases):
 """The lesson's own instructions state each figure the check below confirms."""
 said=' '.join(str(lessons[id].get(k,'')) for k in ('steps','summary','challenge'))+json.dumps(lessons[id].get('workedExample',{}),ensure_ascii=False)
 for phrase in phrases: assert phrase in said,(id,phrase)
def r_values(script):
 return list(map(float,subprocess.check_output([find_rscript(),'--vanilla','-e',script],text=True).split()))

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
 paired=lessons['paired']['columns'];example('paired','TPaired')
 result=s.run('TPaired',{'data':columns(*(c['values'] for c in paired)),'doAgreement':False})
 print('PASS learning paired example:',json.dumps(result['values']))
 r_script='x<-c(142,136,151,145,139,148,132,155);y<-c(135,134,143,141,136,140,130,147);t<-t.test(x,y,paired=TRUE);cat(sprintf("%.17g",c(mean(x-y),t$statistic,t$p.value,t$conf.int)),sep="\\n")'
 expected=list(map(float,subprocess.check_output([find_rscript(),'--vanilla','-e',r_script],text=True).split()))
 for key,value in zip(['mean','t','tail_2','from','to'],expected):
  assert math.isclose(result['values'][key],value,rel_tol=1e-10,abs_tol=1e-12),(key,value,result['values'][key])
 precision=lessons['precision']['columns'];example('precision','UnivariateSummary')
 result=s.run('UnivariateSummary',{'data':columns(*(c['values'] for c in precision))})
 assert result['html'] and result['state']=='complete'
 stated('precision','19.3','17.5','13.8 to 24.8')
 values=precision[0]['values'];lines=report(result)
 def reported(label):return float(next(l for l in lines if l.startswith(label+' '))[len(label):])
 expected=r_values('x<-c(%s);cat(sprintf("%%.6f",c(mean(x),median(x),t.test(x)$conf.int)))'%','.join(map(str,values)))
 for label,value in zip(['Mean','Median','Lower 95% CL of mean','Upper 95% CL of mean'],expected):
  assert abs(reported(label)-value)<1e-6,(label,reported(label),value)
 assert [round(v,1) for v in expected]==[19.3,17.5,13.8,24.8]
 print('PASS learning precision: mean, median and the 95% interval for the mean as the lesson states and R gives')
 regression=lessons['regression']['columns'];example('regression','SimpleLinearRegression')
 result=s.run('SimpleLinearRegression',{'y':columns(regression[0]['values']),'x':columns(regression[1]['values'])})
 assert result['html'] and result['state']=='complete'
 fit=r_values('y<-c(%s);x<-c(%s);cat(sprintf("%%.15g",coef(lm(y~x))))'%(','.join(map(str,regression[0]['values'])),','.join(map(str,regression[1]['values']))))
 assert math.isclose(result['values']['abs_yintercept'],abs(fit[0]),rel_tol=1e-10) and math.isclose(result['values']['slope'],fit[1],rel_tol=1e-10),(result['values'],fit)
 print('PASS learning regression: intercept and slope as R\'s lm gives')
 # Reproduce the four-cell layouts stated in the teaching instructions.
 example('diagnostic','MiscDiagnostic')
 diagnostic=s.run('MiscDiagnostic',{'scrap':columns([72,18],[81,729])})['values']
 for key,value in [('sensitive',.8),('specific',.9),('likely',8/17),('likely_negative',81/83)]:
  assert math.isclose(diagnostic[key],value,rel_tol=1e-12),(key,diagnostic[key])
 for key,value in [('sensitive_from',.702457549867273),('sensitive_to',.8769444539890856)]:
  assert math.isclose(diagnostic[key],value,rel_tol=1e-11),(key,diagnostic[key])
 print('PASS learning diagnostic denominators, grid orientation and Clopper-Pearson interval')
 example('risk','MiscNumberNeededToTreat')
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
 example('epidemiology','MiscRelRisk')
 cohort=s.run('MiscRelRisk',{'scrap':columns([30,270],[15,285])})['values']
 assert cohort['ratio']==2 and math.isclose(cohort['dif'],.05)
 print('PASS learning cohort: event/non-event counts, risks and reference group')
 example('causal','MiscRelRisk')
 age=s.run('MiscRelRisk',{'scrap':columns([44,156],[26,174])})['values']
 assert math.isclose(age['ratio'],22/13) and math.isclose(age['dif'],.09)
 for data in [columns([4,36],[16,144]),columns([40,120],[10,30])]:
  stratum=s.run('MiscRelRisk',{'scrap':data})['values']
  assert stratum['ratio']==1 and stratum['dif']==0
 print('PASS learning age example: crude and both within-age comparisons')
 rates=lessons['rates']['columns'];example('rates','RateDirect')
 direct=s.run('RateDirect',{'idxn':columns(rates[0]['values']),'times':columns(rates[1]['values']),
  'refn':columns(rates[2]['values']),'strata':{'skip':True},'nunit':'100000'})['values']
 assert direct['crude']==840 and direct['stdr']==400 and direct['pc']==95
 assert direct['from_dobson']<400<direct['to_dobson']
 print('PASS learning rates: worksheet order, multiplier, crude and adjusted estimates')
 example('appraisal','MiscRelRisk')
 trial=s.run('MiscRelRisk',{'scrap':columns([20,60],[30,70])})['values']
 assert math.isclose(trial['ratio'],5/6) and math.isclose(trial['dif'],-.05)
 print('PASS learning appraisal: observed-data comparison, with missing outcomes explicitly excluded')
 observed=lessons['missing']['columns'][0]['values'];example('missing','UnivariateSummary')
 missing_summary=s.run('UnivariateSummary',{'data':columns(observed)})
 assert missing_summary['html'] and missing_summary['state']=='complete'
 stated('missing','23.33')
 assert 'Mean 23.333333' in report(missing_summary) and r_values('cat(sprintf("%%.6f",mean(c(%s))))'%','.join(map(str,observed)))==[23.333333]
 validation=lessons['validation']['columns'];example('validation','SimpleLinearRegression')
 calibration=s.run('SimpleLinearRegression',{'y':columns(validation[0]['values']),'x':columns(validation[1]['values'])})
 assert calibration['html'] and calibration['state']=='complete'
 fit=r_values('y<-c(%s);x<-c(%s);cat(sprintf("%%.15g",coef(lm(y~x))))'%(','.join(map(str,validation[0]['values'])),','.join(map(str,validation[1]['values']))))
 assert math.isclose(calibration['values']['abs_yintercept'],abs(fit[0]),rel_tol=1e-9) and math.isclose(calibration['values']['slope'],fit[1],rel_tol=1e-10),(calibration['values'],fit)
 print('PASS learning missing: the observed mean the lesson states; validation: calibration intercept and slope as R\'s lm gives')
 meta=lessons['meta']['columns'];example('meta','MetaSummary')
 pooled=s.run('MetaSummary',{'type':'riskDifference','use_ci':'false','y':columns(meta[0]['values']),
  'se_y':columns(meta[1]['values']),'studies':{'skip':True}})['values']
 for key,expected in [('rmh',-.04),('from_fixed',-.0661328531272007),('to_fixed',-.0138671468727993),('qc',1.25)]:
  assert math.isclose(pooled[key],expected,rel_tol=1e-10,abs_tol=1e-12),(key,pooled[key])
 print('PASS learning meta-analysis: named input types, pooled estimate, 95% limits and Q agree with independent R checks')
 # The lessons added with the expanded course (StatsDirect 5.3.11 and Mac 1.1.3).
 wait=example('describe-data','UnivariateSummary')['Wait (minutes)']
 stated('describe-data','median is 11.5','mean is 15.75','Q1 = 10 and Q3 = 15')
 lines=report(s.run('UnivariateSummary',{'data':columns(wait)}))
 assert 'Mean 15.75' in lines and 'Median 11.5' in lines,[l for l in lines if 'ean' in l or 'edian' in l]
 assert r_values('x<-c(%s);cat(mean(x),median(x),quantile(x,c(.25,.75)),IQR(x))'%','.join(map(str,wait)))==[15.75,11.5,10,15,5]
 print('PASS learning describe-data: mean and median as the lesson states, with its quartiles by R\'s convention')
 before_after=example('choose-analysis','TPaired')
 stated('choose-analysis','average 2.625 units')
 result=s.run('TPaired',{'data':columns(before_after['Before'],before_after['After']),'doAgreement':False})['values']
 expected=r_values('x<-c(%s);y<-c(%s);t<-t.test(x,y,paired=TRUE);cat(sprintf("%%.17g",c(mean(x-y),t$statistic,t$p.value,t$conf.int)))'%(','.join(map(str,before_after['Before'])),','.join(map(str,before_after['After']))))
 assert result['mean']==2.625 and result['n']==8
 for key,value in zip(['mean','t','tail_2','from','to'],expected): assert math.isclose(result[key],value,rel_tol=1e-10,abs_tol=1e-12),(key,value,result[key])
 print('PASS learning choose-analysis: the paired mean improvement the lesson states, with R\'s t, P and interval')
 example('surveillance-outbreaks','MiscRelRisk')
 stated('surveillance-outbreaks','case counts 18 and 6, non-case counts 42 and 54','risk ratio is 3','difference is 20 percentage points')
 outbreak=s.run('MiscRelRisk',{'scrap':columns([18,42],[6,54])})['values']
 assert math.isclose(outbreak['ratio'],3) and math.isclose(outbreak['dif'],.2),outbreak
 print('PASS learning surveillance-outbreaks: attack-rate ratio and difference from the stated counts')
 example('trial-power','SizeUnPaired')
 stated('trial-power','133','527')
 for difference,size in [(4,133),(2,527)]:
  result=s.run('SizeUnPaired',{'d':difference,'sd':10,'p':90,'a':5})
  assert result['values']['size']==size and result['values']['power']==.9 and result['values']['alpha']==.05,result['values']
  assert f'Estimated minimum sample size = {size} experimental subjects and {size} controls.' in report(result)
  # R's power.t.test solves the same noncentral-t problem; it reports a fractional n to round up.
  assert math.ceil(r_values(f'cat(power.t.test(delta={difference},sd=10,power=.9,sig.level=.05)$n)')[0])==size
 print('PASS learning trial-power: 133 per arm for a difference of 4 and 527 for 2, as the lesson and R give')
 marker=example('diagnostic-evidence','ROCPlot')
 stated('diagnostic-evidence','80%')
 lines=report(s.run('ROCPlot',{'P1':columns(marker['Condition present']),'A1':columns(marker['Condition absent'])}))
 assert 'Optimum cut-off point selected = 4' in lines and 'Area under ROC curve by extended trapezoidal rule = 0.845' in lines,lines
 assert any(l.startswith('sensitivity (95% CI) = 0.8 ') for l in lines) and any(l.startswith('specificity (95% CI) = 0.8 ') for l in lines),lines
 auc=r_values('p<-c(%s);a<-c(%s);cat(mean(outer(p,a,">")+.5*outer(p,a,"==")),mean(p>=4),mean(a<4))'%(','.join(map(str,marker['Condition present'])),','.join(map(str,marker['Condition absent']))))
 assert auc==[.845,.8,.8],auc
 print('PASS learning diagnostic-evidence: cut-off 4 with sensitivity and specificity 80%, and the area under the curve R gives')
 survival=example('survival-competing-risks','KaplanMeier')
 stated('survival-competing-risks','4/9')
 lines=report(s.run('KaplanMeier',{'times':columns(survival['Time (months)']),'deaths':columns(survival['Composite event']),'groups':columns(survival['Arm'])}))
 first,second=lines.index('Column 1 = 0'),lines.index('Column 1 = 1')
 arm0=lines[first:second]
 assert any(l.startswith('4 3 1 0 0.444444 ') for l in arm0) and 'Median survival time = 4' in arm0,arm0
 assert 'Median survival time = 4.5' in lines[second:],lines[second:]
 # Arm 0 by hand: events at months 1, 2, 4 and 5 among 6, 5, 3 and 2 at risk.
 assert math.isclose((5/6)*(4/5)*(2/3),4/9)
 print('PASS learning survival-competing-risks: arm 0 estimate 4/9 at month 4 and median 4 months, as the lesson states')
 grouped=example('regression-models','LogisticRegression')
 stated('regression-models','0.50')
 lines=report(s.run('LogisticRegression',{'grouping':'grouped','intercept':True,'total':columns(grouped['Total']),'response':columns(grouped['Events']),
  'predictors':columns(grouped['Protocol'],grouped['Severe'])}))
 odds=[l for l in lines if re.match(r'^(Column 1|b1) ',l)]
 fit=r_values('d<-data.frame(p=c(%s),s=c(%s),n=c(%s),e=c(%s));m<-glm(cbind(e,n-e)~p+s,binomial,d);b<-coef(summary(m))["p",];cat(sprintf("%%.10g",exp(c(b[1],b[1]-qnorm(.975)*b[2],b[1]+qnorm(.975)*b[2]))))'%tuple(','.join(map(str,grouped[k])) for k in ('Protocol','Severe','Total','Events')))
 assert math.isclose(fit[0],.5,rel_tol=1e-9) and abs(fit[1]-.332954)<5e-7 and abs(fit[2]-.750854)<5e-7,fit
 assert any(re.search(r'\b0\.5\b.*\b0\.332954\b.*\b0\.750854\b',l) for l in lines),odds or lines
 print('PASS learning regression-models: protocol odds ratio 0.50 with the Wald interval R gives (0.333 to 0.751)')
 readings=example('measurement-agreement','TPaired')
 stated('measurement-agreement','−2.5 units','−4.84 and −0.16')
 result=s.run('TPaired',{'data':columns(readings['Reference reading'],readings['New reading']),'doAgreement':True})
 limits=r_values('d<-c(%s)-c(%s);cat(sprintf("%%.6f",c(mean(d),mean(d)-1.96*sd(d),mean(d)+1.96*sd(d))))'%(','.join(map(str,readings['Reference reading'])),','.join(map(str,readings['New reading']))))
 assert result['values']['mean']==-2.5 and limits==[-2.5,-4.842648,-0.157352],limits
 agreement=[l for l in report(result) if l.startswith('95% Limits of agreement = ')]
 found=list(map(float,re.findall(r'-?\d+\.\d+',agreement[0].split('=')[1])))
 # StatsDirect uses the exact normal quantile where the lesson's R script uses 1.96: both round to the lesson's figures.
 assert len(found)==2 and all(abs(a-b)<1e-4 for a,b in zip(found,limits[1:])) and [round(v,2) for v in found]==[-4.84,-.16],(agreement,limits)
 print('PASS learning measurement-agreement: Reference minus New, mean -2.5 with limits of agreement -4.84 to -0.16')
 groups=example('independent-group-comparisons','OneWay')
 stated('independent-group-comparisons','10.79')
 anova=s.run('OneWay',{'data':columns(*groups.values())})['values']
 expected=r_values('y<-c(%s);g<-gl(3,8);a<-anova(lm(y~g));cat(sprintf("%%.15g",c(a$F[1],a$Df,a$`Pr(>F)`[1])))'%','.join(str(v) for c in groups.values() for v in c))
 assert (anova['b_df'],anova['w_df'])==(2,21)==(expected[1],expected[2]) and round(anova['f'],2)==10.79
 assert math.isclose(anova['f'],expected[0],rel_tol=1e-10) and math.isclose(anova['p'],expected[3],rel_tol=1e-9),(anova,expected)
 print('PASS learning independent-group-comparisons: F = 10.79 on 2 and 21 degrees of freedom, as R gives')
 conditions=example('repeated-condition-comparisons','TwoWay')
 stated('repeated-condition-comparisons','22.2')
 anova=s.run('TwoWay',{'data':columns(*conditions.values())})['values']
 expected=r_values('y<-c(%s);g<-gl(3,8);b<-gl(8,1,24);a<-anova(lm(y~b+g));cat(sprintf("%%.15g",c(a$F[2],a$Df[2],a$Df[3],a$`Pr(>F)`[2])))'%','.join(str(v) for c in conditions.values() for v in c))
 assert (anova['grp_df'],anova['res_df'])==(2,14)==(expected[1],expected[2])
 assert math.isclose(anova['grp_vr'],22.2,rel_tol=1e-12) and math.isclose(anova['grp_vr'],expected[0],rel_tol=1e-10) and math.isclose(anova['grp_p'],expected[3],rel_tol=1e-9),(anova,expected)
 print('PASS learning repeated-condition-comparisons: condition F = 22.2 on 2 and 14 degrees of freedom, as R gives')
 with_example={id for id,lesson in lessons.items() if lesson.get('operation')}
 assert checked==with_example,('lessons whose example is not checked here',sorted(with_example-checked),'checked but without an operation',sorted(checked-with_example))
 print(f'PASS learning examples: all {len(checked)} lessons that open a StatsDirect analysis have their example checked ({len(lessons)-len(checked)} lessons have none)')
finally:s.finish()
