import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync,existsSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {questions,tracks} from './bank.mjs';
import {createSession,recordAnswer,recordAssistance,learnerResult,reviewBundle} from './model.mjs';
const root=new URL('../../',import.meta.url);

test('each draft has one valid key, five distinct choices, a real help topic and a real operation mapping',()=>{
 const operations=JSON.parse(readFileSync(new URL('Content/analysis-menu.json',root))).operations;
 assert.equal(questions.length,12);assert.equal(new Set(questions.map(q=>q.id)).size,12);
 for(const track of Object.keys(tracks)) assert.equal(questions.filter(q=>q.track===track).length,4);
 for(const q of questions){
  assert.equal(q.options.length,5);assert.equal(new Set(q.options.map(o=>o.text)).size,5);
  assert.equal(q.options.filter(o=>o.id===q.correct).length,1);
  assert.ok(q.options.every(o=>o.feedback.length>10));
  assert.ok(existsSync(new URL('Content/Help/'+q.help,root)),q.help);
  if(q.operation)assert.ok(operations[q.operation],q.operation);
 }
});

test('a test withholds results until complete, disallows hints and rejects duplicate or out-of-order answers',()=>{
 const s=createSession('foundation','test','TEST-1');
 assert.throws(()=>learnerResult(s));assert.throws(()=>reviewBundle(s));
 assert.throws(()=>recordAssistance(s,s.questionIds[0],'hints'));
 assert.throws(()=>recordAssistance(s,s.questionIds[0],'explanations'));
 assert.throws(()=>recordAnswer(s,s.questionIds[1],'A','confident'));
 assert.throws(()=>recordAnswer(s,s.questionIds[0],'X','confident'));
 assert.equal(s.answers.length,0);
 recordAnswer(s,s.questionIds[0],'C','confident','Use the denominator with the condition.');
 assert.throws(()=>recordAnswer(s,s.questionIds[0],'C','confident'));
 for(const id of s.questionIds.slice(1)){
  const q=questions.find(q=>q.id===id);recordAnswer(s,id,q.correct,'fairly');
 }
 assert.equal(learnerResult(s).score,4);assert.ok(s.completedAt);
 assert.throws(()=>recordAnswer(s,s.questionIds[0],'C','confident'));
 const bundle=reviewBundle(s);
 assert.equal(bundle.submissionStatus,'not_submitted');assert.equal(bundle.universityReview.status,'not_connected');
 assert.equal(bundle.universityReview.decision,null);assert.equal(bundle.intendedRouting.active,false);
 assert.equal(bundle.session.answers[0].reasoning,'Use the denominator with the condition.');
 assert.equal(bundle.questionSnapshots.length,4);
});

test('learning support and uncertainty are recorded separately from MCQ score',()=>{
 const s=createSession('medicine','learn','TEST-2');
 recordAssistance(s,s.questionIds[0],'hints');recordAssistance(s,s.questionIds[0],'hints');
 assert.equal(s.hints.length,1);
 for(const [i,id] of s.questionIds.entries()){
  const q=questions.find(q=>q.id===id);
  recordAnswer(s,id,i===3?'A':q.correct,i===1?'unsure':'confident','<script>Untrusted learner text</script>');
 }
 const r=learnerResult(s);assert.equal(r.score,3);assert.equal(r.assisted,1);assert.equal(r.revisit.length,3);
 assert.ok(r.revisit.some(p=>p.reason==='Confident but incorrect'));
 s.reflection='I will practise a fresh example.';
 assert.equal(reviewBundle(s).session.reflection,s.reflection);
 assert.throws(()=>recordAssistance(s,s.questionIds[0],'hints'));
});

test('every numerical answer agrees with a separately expressed base R calculation',()=>{
 const values=execFileSync('/Library/Frameworks/R.framework/Resources/bin/Rscript',['--vanilla','-e',`
 answers <- c(72/(72+18), ceiling(1/(28/200-16/200)),
   (0.9*0.01)/(0.9*0.01+(1-0.95)*(1-0.01)),
   (120/200)/(80/200), (120*120)/(80*80),
   sqrt(100)/sqrt(400), sum(c(200,1000)*c(0.75,0.25)), 1+(20-1)*0.04, 55/44)
 cat(sprintf("%.17g", answers), sep="\\n")
 `],{encoding:'utf8'}).trim().split(/\s+/).map(Number);
 const expected=questions.filter(q=>q.calculation).flatMap(q=>q.calculation.expected);
 assert.equal(values.length,expected.length);
 expected.forEach((n,i)=>assert.ok(Math.abs(n-values[i])<1e-12,`${n} vs R ${values[i]}`));
});
