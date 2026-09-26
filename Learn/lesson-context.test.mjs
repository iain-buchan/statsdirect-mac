import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {newPortfolio,transcriptEntry,restorePortfolio,reviewRecord,reviewText} from './portfolio.mjs';
import {labelStudyGuides,ensureLessonPrompt,guidePresentation,conversationForTutor} from './lesson-context.mjs';
const lessons=JSON.parse(readFileSync(new URL('../Content/Learn/lessons.json',import.meta.url)));
const epi=lessons.find(l=>l.id==='epidemiology'),paired=lessons.find(l=>l.id==='paired');
test('reopening paired lesson labels and collapses a legacy epidemiology prompt without deleting history',()=>{
  const s=newPortfolio();s.lesson='paired';s.draft='My unfinished answer';
  const old=transcriptEntry(s,'assistant',epi.challenge,'Study guide');
  const learner=transcriptEntry(s,'user',epi.challenge,'Learner');
  assert.equal(ensureLessonPrompt(s,lessons),true);
  assert.equal(old.lessonId,'epidemiology');assert.equal(learner.lessonId,undefined);
  assert.deepEqual(guidePresentation(old,paired),{label:'Earlier study guide · Epidemiological foundations',earlier:true});
  assert.equal(s.conversation.at(-1).text,paired.challenge);assert.equal(s.draft,'My unfinished answer');
  assert.equal(ensureLessonPrompt(s,lessons),false);assert.equal(s.conversation.length,3);
  const restored=restorePortfolio(JSON.parse(JSON.stringify(s)));assert.equal(ensureLessonPrompt(restored,lessons),false);
  assert.match(reviewText(reviewRecord(restored)),/Study guide · Epidemiological foundations/);
  assert.equal(restored.conversation[0].text,epi.challenge);
});
test('switching lessons supplies the right prompt and tags model history with its original topic',()=>{
  const s=newPortfolio();ensureLessonPrompt(s,lessons);s.lesson='paired';ensureLessonPrompt(s,lessons);
  assert.equal(guidePresentation(s.conversation[0],paired).earlier,true);assert.equal(guidePresentation(s.conversation[1],paired).earlier,false);
  const history=conversationForTutor(s);assert.match(history[0].text,/Lesson context: Epidemiological foundations/);assert.match(history[1].text,/Lesson context: Comparing paired measurements/);
  s.lesson='epidemiology';assert.equal(ensureLessonPrompt(s,lessons),true);assert.equal(s.conversation.at(-1).text,epi.challenge);
});
test('the paired lesson establishes actual pairing and upgrades its older prompt without rewriting it',()=>{
  assert.match(paired.challenge,/same eight people/);assert.match(paired.challenge,/different, unmatched people/);assert.match(paired.summary,/not automatically paired/);
  const s=newPortfolio();s.lesson='paired';const old=transcriptEntry(s,'assistant',paired.previousChallenges[0],'Study guide');
  labelStudyGuides(s,lessons);assert.equal(old.lessonId,'paired');assert.equal(guidePresentation(old,paired).earlier,true);
  assert.equal(ensureLessonPrompt(s,lessons),true);assert.equal(old.text,paired.previousChallenges[0]);
});
