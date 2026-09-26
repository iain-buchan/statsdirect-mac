import {transcriptEntry} from './portfolio.mjs';

// Older records contain unlabelled guide prompts. Identify only exact bundled text;
// never infer the topic of a learner's own words or rewrite their conversation.
export function labelStudyGuides(state,lessons){
  for(const entry of state.conversation){
    if(entry.source!=='Study guide'||entry.role!=='assistant')continue;
    const origin=lessons.find(l=>l.challenge===entry.text||(l.previousChallenges??[]).includes(entry.text));
    if(origin){entry.lessonId=origin.id;entry.lessonTitle=origin.title;entry.lessonPrompt=true;}
  }
}
export function ensureLessonPrompt(state,lessons){
  labelStudyGuides(state,lessons);
  const current=lessons.find(l=>l.id===state.lesson);
  if(!current)return false;
  const latest=state.conversation.findLast(c=>c.lessonPrompt===true);
  if(latest?.lessonId===current.id&&latest.text===current.challenge)return false;
  transcriptEntry(state,'assistant',current.challenge,'Study guide',{lessonId:current.id,lessonTitle:current.title,lessonPrompt:true});
  return true;
}
export function guidePresentation(entry,currentLesson){
  if(entry.lessonPrompt!==true)return {label:entry.lessonTitle?`${entry.source} · ${entry.lessonTitle}`:entry.source,earlier:false};
  const earlier=entry.lessonId!==currentLesson.id||entry.text!==currentLesson.challenge;
  return {label:`${earlier?'Earlier study guide':'Study guide'} · ${entry.lessonTitle}`,earlier};
}
export function conversationForTutor(state){
  return state.conversation.slice(-40).map(c=>({role:c.role,text:c.lessonTitle?`[Lesson context: ${c.lessonTitle}]\n${c.text}`:c.text}));
}
