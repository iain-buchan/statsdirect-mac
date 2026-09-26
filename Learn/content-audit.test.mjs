import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {questions} from './bank.mjs';
import {questions as archived} from '../Docs/Learn/bank.mjs';

test('published lessons and archived questions use the maintained content',()=>{
  assert.deepEqual(JSON.parse(readFileSync(new URL('./lessons.json',import.meta.url))),
    JSON.parse(readFileSync(new URL('../Content/Learn/lessons.json',import.meta.url))));
  for(const q of archived) assert.deepEqual(q,questions.find(current=>current.id===q.id));
});

test('reviewed numerical choices agree with independently expressed R calculations',()=>{
  // Literal choices bind these checks to what learners actually see, not only metadata.
  const fixtures=[
    ['UG-SENS-01','C','80%',0.8,'72/90'],
    ['UG-NNT-01','D','17',17,'ceiling(200/(28-16))'],
    ['PG-PPV-01','C','15.4%',100*90/585,'100*90/(90+495)'],
    ['PG-RROR-01','A','Risk ratio 1.50; odds ratio 2.25',1.5,'120/80'],
    ['PG-RROR-01','A','Risk ratio 1.50; odds ratio 2.25',2.25,'(120*120)/(80*80)'],
    ['PG-SE-01','D','It becomes half as large.',0.5,'sqrt(100/400)'],
    ['PH-STAND-01','C','400',400,'(75*200+25*1000)/100'],
    ['PH-CLUST-01','C','1.76',1.76,'1+19*0.04'],
    ['PH-SMR-01','C','1.25',1.25,'55/44'],
    ['RS-MULT-01','D','64%',0.6415140775914581,'pbinom(0,20,0.05,lower.tail=FALSE)'],
    ['PG-LR-01','C','40%',0.4,'6*0.1/(6*0.1+0.9)'],
    ['CORE-RATE-01','A','2 events per 100 person-years',2,'100*12/600'],
    ['AN-PREC-01','B','The service with 1,000 people',1,'as.numeric(diff(prop.test(100,1000,correct=FALSE)$conf.int) < diff(prop.test(10,100,correct=FALSE)$conf.int))'],
  ];
  const output=execFileSync('/Library/Frameworks/R.framework/Resources/bin/Rscript',
    ['--vanilla','-e',`cat(sprintf('%.17g',c(${fixtures.map(f=>f[4]).join(',')})),sep='\n')`],{encoding:'utf8'});
  const results=output.trim().split(/\s+/).map(Number);
  fixtures.forEach(([id,key,choice,expected],i)=>{
    const q=questions.find(q=>q.id===id);
    assert.equal(q.correct,key,id);
    assert.equal(q.options.find(o=>o.id===key).text,choice,id);
    assert.ok(Math.abs(results[i]-expected)<1e-12,`${id}: ${results[i]} vs ${expected}`);
  });
  const pct=questions.find(q=>q.id==='AN-PCT-01');
  assert.equal(pct.correct,'A');
  assert.equal(pct.options.find(o=>o.id==='A').text,'2 percentage points; 20% relative reduction');
  assert.ok(Math.abs((0.10-0.08)*100-2)<1e-12);
  assert.ok(Math.abs((0.10-0.08)/0.10*100-20)<1e-12);
});

// Run after each actual bundled R script, in that script's environment.
export const lessonChecks={
  paired:`stopifnot(length(change)==8, mean(change)==5.25,
    identical(change,c(7,2,8,4,3,8,2,8)), t.test(change)$parameter==7)`,
  precision:`stopifnot(length(wait)==12, sum(wait)==232, median(wait)==17.5,
    isTRUE(all.equal(sd(wait)^2,sum((wait-232/12)^2)/11)),
    mean_ci[1]<mean(wait),mean_ci[2]>mean(wait),attr(mean_ci,'conf.level')==0.95)`,
  diagnostic:`stopifnot(counts['Positive','Present']==72,counts['Positive','Absent']==81,
    counts['Negative','Present']==18,counts['Negative','Absent']==729,
    tp/(tp+fn)==0.8,tn/(tn+fp)==0.9,abs(tp/(tp+fp)-8/17)<1e-12,
    abs(tn/(tn+fn)-81/83)<1e-12,sensitivity_ci[1]<0.8,sensitivity_ci[2]>0.8)`,
  risk:`stopifnot(identical(events,c(16,28)),identical(totals,c(200,200)),
    abs(arr-0.06)<1e-12,abs(risk[1]/risk[2]-4/7)<1e-12,ceiling(1/arr)==17,
    abs(mean(arr_ci)-arr)<1e-12,arr_ci[1]<0,arr_ci[2]>0,
    abs(arr_ci[1]-(-0.0010427306))<1e-9,abs(arr_ci[2]-0.1210427306)<1e-9)`,
  regression:`stopifnot(nrow(data)==8,range(data$Minutes)==c(10,24),df.residual(fit)==6,
    abs(unname(coef(fit)[2])-sum((data$Minutes-17)*(data$Satisfaction-66.625))/168)<1e-12)`,
  epidemiology:`stopifnot(identical(events,c(30,15)),identical(at_risk,c(300,300)),
    (events[1]/at_risk[1])/(events[2]/at_risk[2])==2,
    abs(diff(rev(events/at_risk))-0.05)<1e-12)`,
  causal:`stopifnot(sum(data$Exposed_events)==44,sum(data$Unexposed_events)==26,
    all(data$Exposed_risk==data$Unexposed_risk),all(abs(standardised-0.175)<1e-12),
    sum(weights)==1,standardised[1]/standardised[2]==1)`
};
