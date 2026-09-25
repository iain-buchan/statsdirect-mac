import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync,existsSync,mkdtempSync,writeFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {execFileSync} from 'node:child_process';
import {questions,tracks} from './bank.mjs';
import {createSession,recordAnswer,recordAssistance,learnerResult,sessionQuestion} from './quiz.mjs';
import {newPortfolio,restorePortfolio,reviewRecord,reviewText,transcriptEntry,practiceContext} from './portfolio.mjs';
const root=new URL('../',import.meta.url);
const lessons=JSON.parse(readFileSync(new URL('Content/Learn/lessons.json',root)));
test('30 original draft questions map to five pathways, valid choices, real help and engine operations',()=>{
 const operations=JSON.parse(readFileSync(new URL('Content/analysis-menu.json',root))).operations;
 assert.equal(questions.length,30);assert.equal(new Set(questions.map(q=>q.id)).size,30);
 for(const t of Object.keys(tracks))assert.ok(questions.filter(q=>q.track===t).length>=4);
 for(const q of questions){assert.equal(q.options.length,5);assert.equal(q.options.filter(o=>o.id===q.correct).length,1);assert.ok(existsSync(new URL('Content/Help/'+q.help,root)),q.help);if(q.operation)assert.ok(operations[q.operation]);}
 for(const l of lessons){assert.ok(existsSync(new URL('Content/Help/'+l.help,root)),l.help);assert.ok(operations[l.operation]);}
});
test('independent practice hides answer keys and feedback from record previews until ended',()=>{
 const p=newPortfolio();p.quiz=createSession('foundation','test');const q=questions.find(q=>q.id===p.quiz.questionIds[0]);
 assert.throws(()=>recordAssistance(p.quiz,q.id,'hints'));assert.throws(()=>learnerResult(p.quiz));
 recordAnswer(p.quiz,q.id,q.correct,'confident','A denominator explanation');
 assert.throws(()=>recordAnswer(p.quiz,q.id,q.correct,'confident'));
 let r=reviewRecord(p);assert.equal(r.attempts[0].result,null);assert.equal(r.attempts[0].answers[0].correct,undefined);
 assert.ok(r.attempts[0].questionSnapshots.every(q=>!q.correct&&!q.explanation&&q.options.every(o=>!o.feedback)));
 assert.equal(practiceContext(p),'');assert.match(reviewText(r),/withheld until the attempt ends/);
 p.quiz.endedAt=new Date().toISOString();r=reviewRecord(p);assert.equal(r.attempts[0].status,'ended early');assert.equal(r.attempts[0].questionSnapshots[0].correct,q.correct);
});
test('provisional scores, support, first answers and full conversation survive reopen and export',()=>{
 const p=newPortfolio();p.quiz=createSession('researcher','learn');recordAssistance(p.quiz,p.quiz.questionIds[0],'hints');
 for(const [i,id]of p.quiz.questionIds.entries()){const q=questions.find(q=>q.id===id);recordAnswer(p.quiz,id,i===3?'A':q.correct,'fairly','My reasoning '+i);}
 transcriptEntry(p,'user','Please explain this <script>not executable</script>.','Learner');
 transcriptEntry(p,'assistant','A detailed answer.','OpenAI tutor',{model:'mock-model',promptVersion:'test'});
 p.identity={name:'Synthetic Student',email:'student@example.invalid',goal:'Practice only'};p.reflection='I will check paired differences.';
 const restored=restorePortfolio(JSON.parse(JSON.stringify(p))),record=reviewRecord(restored),text=reviewText(record);
 assert.equal(record.attempts[0].result.score,8);assert.equal(record.attempts[0].result.assisted,1);
 assert.equal(record.conversation.length,2);assert.ok(record.learningOptions.focus.includes('causal'));assert.ok(restored.quiz.questionIds.includes('CORE-MEDIATOR-01')); assert.match(text,/My reasoning 3/);assert.match(text,/Synthetic Student/);assert.match(text,/<script>not executable<\/script>/);assert.match(text,/No accreditation or CPD points awarded/);assert.match(text,/I will check paired differences/);
 assert.throws(()=>restorePortfolio({schemaVersion:999}));
});
test('bundled R examples run without packages, use exact fictional rows, and produce plots',()=>{
 const dir=mkdtempSync(tmpdir()+'/statsdirect-learn-');
 try{for(const l of lessons){const script=dir+'/'+l.id+'.R';writeFileSync(script,`pdf(${JSON.stringify(dir+'/'+l.id+'.pdf')})\n${l.r}\ndev.off()\n`);const output=execFileSync('/Library/Frameworks/R.framework/Resources/bin/Rscript',['--vanilla',script],{encoding:'utf8'});assert.ok(existsSync(dir+'/'+l.id+'.pdf'));if(l.id==='paired'){assert.match(output,/Paired t-test/);assert.match(output,/5.25/);}}}finally{rmSync(dir,{recursive:true});}
});
test('saved goals round trip; malformed nested records are rejected before replacement',()=>{
 const p=newPortfolio();p.learning.qualifications='MRCGP AKT';p.learning.needs='Causal inference and diagnostic test interpretation';p.quiz=createSession('foundation','learn');
 const restored=restorePortfolio(JSON.parse(JSON.stringify(p)));
 assert.equal(restored.learning.qualifications,'MRCGP AKT');assert.equal(restored.learning.needs,p.learning.needs);
 for(const corrupt of [x=>x.identity=null,x=>x.learning.focus=null,x=>x.conversation.push({text:3}),x=>x.quiz.answers=[null],x=>x.quiz.questionIds[0]='missing',x=>x.quiz.questionSnapshots[0].options=null]){
  const damaged=structuredClone(p);corrupt(damaged);assert.throws(()=>restorePortfolio(damaged),/not been overwritten/);
 }
});
test('a saved attempt keeps its wording and answer key when the question bank changes',()=>{
 const p=newPortfolio();p.quiz=createSession('foundation','learn');const id=p.quiz.questionIds[0],q=questions.find(q=>q.id===id),oldStem=q.stem,oldKey=q.correct;
 try{q.stem='Replacement question';q.correct=oldKey==='A'?'B':'A';const restored=restorePortfolio(JSON.parse(JSON.stringify(p)));assert.equal(sessionQuestion(restored.quiz,id).stem,oldStem);recordAnswer(restored.quiz,id,oldKey,'confident');assert.equal(restored.quiz.answers[0].correct,true);assert.equal(reviewRecord(restored).attempts[0].questionSnapshots[0].correct,oldKey);}finally{q.stem=oldStem;q.correct=oldKey;}
});
