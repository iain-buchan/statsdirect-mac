import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {bankVersion,bankPublication,questions,tracks} from './bank.mjs';
import {questions as earlierQuestions} from '../Docs/Learn/bank.mjs';
import {createSession,recordAnswer,sessionQuestion} from './quiz.mjs';
import {newPortfolio,restorePortfolio,reviewRecord} from './portfolio.mjs';
import {lessonGuideHTML,learningTargetHTML} from './lesson-guide.mjs';
import {ensureLessonPrompt} from './lesson-context.mjs';

const json=path=>JSON.parse(readFileSync(new URL(path,import.meta.url),'utf8'));
const esc=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));

test('published JSON is the question bank and retains every earlier question/pathway ID',()=>{
  assert.deepEqual(questions,json('./AuthoredTutor/questions.json'));
  assert.deepEqual(tracks,json('./AuthoredTutor/tracks.json'));
  assert.equal(bankVersion,json('./AuthoredTutor/manifest.json').bankVersion);
  assert.equal(bankPublication.commit,json('../Content/learning-manifest.json').commit);
  assert.equal(bankPublication.reviewProofBinding,'authoring-source-before-generated-sync-v1');
  for(const q of earlierQuestions)assert.ok(questions.some(item=>item.id===q.id),q.id);
  for(const id of ['foundation','medicine','publicHealth','analyst','researcher'])assert.ok(tracks[id]);
  assert.ok(questions.every(q=>!q.id.startsWith('course:')));
});

test('question targeting, exact review and publication metadata survive saved attempts and later bank edits',()=>{
  const q=questions.find(item=>item.track==='foundation'),saved=structuredClone(q);
  try{
    Object.assign(q,{difficulty:'advanced',learnerGoals:['publicHealth','usMedicalBoards'],learnerGoalNotes:'Study public health board questions',review:{status:'Reviewed by course author',reviewer:'Synthetic Tutor',notes:'Review of fictional example',date:'2026-11-04',contentSha256:'a'.repeat(64)}});
    const p=newPortfolio();p.identity.goal='Pass a public health module';p.learning.qualifications='MFPH';p.lesson='paired';
    p.quiz=createSession('foundation','learn','preserved-attempt');
    const question=sessionQuestion(p.quiz,q.id);recordAnswer(p.quiz,q.id,question.correct,'fairly','My reasoning');
    q.stem='Changed in a later publication';q.difficulty='beginner';q.review.status='Draft';
    const restored=restorePortfolio(structuredClone(p)),record=reviewRecord(restored);
    assert.equal(restored.id,p.id);assert.equal(restored.lesson,'paired');assert.equal(restored.learning.qualifications,'MFPH');
    assert.equal(restored.quiz.id,'preserved-attempt');assert.equal(restored.quiz.answers.length,1);
    assert.deepEqual(sessionQuestion(restored.quiz,q.id),question);
    assert.equal(record.attempts[0].questionSnapshots[0].review.status,'Reviewed by course author');
    assert.deepEqual(record.attempts[0].questionSnapshots[0].learnerGoals,['publicHealth','usMedicalBoards']);
    assert.deepEqual(record.attempts[0].contentPublication,bankPublication);
    assert.equal(record.attempts[0].contentPublication.publication.reviewWarningCount,bankPublication.publication.reviewWarningCount);
  }finally{for(const key of Object.keys(q))delete q[key];Object.assign(q,saved);}
});

test('older saved portfolios without publication metadata still restore with their original identity and progress',()=>{
  const p=newPortfolio();p.quiz=createSession('publicHealth','learn');delete p.quiz.contentPublication;
  const q=sessionQuestion(p.quiz,p.quiz.questionIds[0]);recordAnswer(p.quiz,q.id,q.correct,'confident');
  const restored=restorePortfolio(structuredClone(p));
  assert.equal(restored.id,p.id);assert.equal(restored.quiz.answers[0].questionId,q.id);
  assert.equal(restored.quiz.answers[0].correct,true);assert.equal(restored.quiz.contentPublication,undefined);
});

test('lesson and question presentation uses actual review and optional learning targets, with escaped text',()=>{
  const lesson={id:'new-topic',title:'New topic',summary:'Summary',steps:'',difficulty:'advanced',learnerGoals:['publicHealth','mastersStatistics'],learnerGoalNotes:'<script>not executable</script>',review:{status:'Reviewed by course author',reviewer:'Tutor <A>',date:'2026-11-04'}};
  const html=lessonGuideHTML(lesson,[lesson],esc,()=>false);
  assert.match(html,/Reviewed by course author/);assert.match(html,/Tutor &lt;A&gt;/);
  assert.match(html,/Advanced/);assert.match(html,/Public health/);assert.match(html,/Master&#39;s-level statistics/);
  assert.ok(!html.includes('AI-assisted editorial'));assert.ok(!html.includes('<script>'));
  assert.equal(learningTargetHTML({},esc),'');
  assert.equal(learningTargetHTML({difficulty:[],learnerGoals:'publicHealth',learnerGoalNotes:{}},esc),'');
  assert.match(learningTargetHTML({learnerGoals:[null,3,'publicHealth']},esc),/Public health/);
});

test('an authored lesson with no exercise does not add an undefined or empty study-guide entry',()=>{
  const p=newPortfolio();p.lesson='no-exercise';
  for(const challenge of [undefined,null,'','   '])assert.equal(ensureLessonPrompt(p,[{id:p.lesson,title:'Reading',challenge}]),false);
  assert.deepEqual(p.conversation,[]);
});
