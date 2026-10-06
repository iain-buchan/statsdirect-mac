import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {questions} from './bank.mjs';
import {createSession,recordAnswer,learnerResult,sessionQuestion} from './quiz.mjs';
import {restorePortfolio,newPortfolio} from './portfolio.mjs';
import {lessonGuideHTML} from './lesson-guide.mjs';
import {safeURL} from './provider-course.mjs';
import {lessonChecks} from './content-audit.test.mjs';
const lessons=JSON.parse(readFileSync(new URL('./lessons.json',import.meta.url)));
const esc=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));

test('every curated lesson has reviewed teaching fields, resolvable prerequisites, sources and numerical checks',()=>{
  assert.equal(lessons.length,12);
  const visit=(id,path=[])=>{assert.ok(!path.includes(id),'Cyclic prerequisite: '+id);const lesson=lessons.find(l=>l.id===id);assert.ok(lesson,id);lesson.prerequisites.forEach(next=>visit(next,[...path,id]));};
  for(const l of lessons){
    assert.equal(l.knowledgeSchemaVersion,1);assert.match(l.review.status,/external subject-expert review pending/);
    assert.equal(l.contentVersion,'2026-10-01');assert.equal(l.learningObjectives.length,3);
    assert.equal(l.keyConcepts.length,3);assert.equal(l.misconceptions.length,2);assert.equal(l.teachingPrompts.length,2);
    assert.ok(l.workedExample.design&&l.workedExample.interpretation&&lessonChecks[l.id]);visit(l.id);
    assert.deepEqual(Object.keys(l.rProgression),['menus','bridge','coding']);
    assert.ok(l.sources.length>=2);for(const s of l.sources){assert.ok(s.id&&s.scope&&s.title);assert.equal(s.checkedAt,l.review.date);assert.ok(safeURL(s.url));}
    for(const id of l.assessmentIds)assert.ok(questions.some(q=>q.id===id),id);
    for(const q of l.practiceQuestions){assert.ok(l.assessmentIds.includes(q.id));assert.equal(q.lessonId,l.id);assert.ok(q.sourceIds.every(id=>l.sources.some(s=>s.id===id)));}
  }
});

test('new library questions are scored by the practice engine and preserve old attempts',()=>{
  const added=lessons.flatMap(l=>l.practiceQuestions);assert.equal(added.length,5);
  for(const q of added){
    const session=createSession(q.track,'learn');assert.ok(session.questionIds.includes(q.id));
    for(const id of session.questionIds)recordAnswer(session,id,sessionQuestion(session,id).correct,'fairly');
    assert.equal(learnerResult(session).score,session.questionIds.length);
  }
  const p=newPortfolio();p.quiz=createSession('researcher','test');
  // Mimic a saved pre-enrichment attempt: no new question may be inserted on restore.
  p.quiz.questionIds=p.quiz.questionIds.filter(id=>!id.startsWith('LIB-'));
  p.quiz.questionSnapshots=p.quiz.questionSnapshots.filter(q=>p.quiz.questionIds.includes(q.id));
  p.quiz.bankVersion='learn-draft-2026-09-26';
  const old=restorePortfolio(structuredClone(p));assert.deepEqual(old.quiz.questionIds,p.quiz.questionIds);
  assert.equal(old.quiz.bankVersion,'learn-draft-2026-09-26');
});

test('the expandable guide shows curated content and safe references without exposing answer keys',()=>{
  for(const l of lessons){
    const html=lessonGuideHTML(l,lessons,esc,safeURL);
    assert.ok(html.includes(esc(l.keyConcepts[0].explanation)));assert.ok(html.includes(esc(l.workedExample.interpretation)));
    assert.ok(html.includes(l.sources[0].url));assert.ok(html.includes(esc(l.teachingPrompts[0].prompt)));
    for(const q of l.practiceQuestions)assert.ok(!html.includes(q.explanation));
  }
  const hostile=structuredClone(lessons[0]);hostile.keyConcepts[0].explanation='<script>bad()</script>';hostile.sources[0].url='javascript:alert(1)';
  const html=lessonGuideHTML(hostile,lessons,esc,safeURL);assert.ok(!html.includes('<script>'));assert.ok(!html.includes('javascript:'));
  assert.equal(lessonGuideHTML({summary:'Provider text',steps:'Provider steps'},[],esc,safeURL),'<p>Provider text</p><p>Provider steps</p>');
});
