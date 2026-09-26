import {questions,tracks,bankVersion} from './bank.mjs';
import {learnerResult,sessionQuestion} from './quiz.mjs';
export const stages = {menus:'Start with menus',bridge:'Connect menus to R',coding:'Practise R coding'};
export function newPortfolio() {
  return {schemaVersion:2,id:crypto.randomUUID(),startedAt:new Date().toISOString(),profile:'foundation',stage:'menus',lesson:'epidemiology',view:'study',identity:{name:'',email:'',goal:''},learning:{needs:'',qualifications:'',priorKnowledge:'',targetDate:'',focus:['epidemiology','causal'],style:'Worked examples and questions'},conversation:[],activities:[],attempts:[],quiz:null,reflection:'',draft:''};
}
export function restorePortfolio(value) {
  const object=v=>v!==null&&typeof v==='object'&&!Array.isArray(v);
  const strings=(v,keys)=>object(v)&&keys.every(k=>typeof v[k]==='string');
  const validQuestion=q=>strings(q,['id','topic','stem','correct','explanation','hint','lesson','help'])&&Array.isArray(q.options)&&q.options.length===5&&q.options.every(o=>strings(o,['id','text','feedback']))&&q.options.filter(o=>o.id===q.correct).length===1;
  const validSession=s=>{
    if(!strings(s,['id','track','mode','startedAt'])||!tracks[s.track]||!['learn','test'].includes(s.mode)||!Array.isArray(s.questionIds)||!s.questionIds.length||new Set(s.questionIds).size!==s.questionIds.length||!Array.isArray(s.answers)||s.answers.length>s.questionIds.length||!['hints','explanations'].every(k=>Array.isArray(s[k])&&s[k].every(id=>s.questionIds.includes(id))))return false;
    if(s.questionSnapshots!==undefined&&(!Array.isArray(s.questionSnapshots)||s.questionSnapshots.length!==s.questionIds.length||!s.questionSnapshots.every(validQuestion)||new Set(s.questionSnapshots.map(q=>q.id)).size!==s.questionIds.length))return false;
    if(!s.questionIds.every(id=>typeof id==='string'&&validQuestion(sessionQuestion(s,id))))return false;
    if(!['completedAt','endedAt'].every(k=>s[k]===undefined||s[k]===null||typeof s[k]==='string')||Boolean(s.completedAt)!==(s.answers.length===s.questionIds.length))return false;
    return s.answers.every((a,i)=>strings(a,['questionId','choice','confidence','reasoning','answeredAt'])&&a.questionId===s.questionIds[i]&&['unsure','fairly','confident'].includes(a.confidence)&&typeof a.assisted==='boolean'&&typeof a.correct==='boolean'&&sessionQuestion(s,a.questionId).options.some(o=>o.id===a.choice)&&a.correct===(a.choice===sessionQuestion(s,a.questionId).correct));
  };
  const defaults=newPortfolio();
  const learning=value?.learning===undefined?defaults.learning:value.learning;
  if (!strings(value,['id','startedAt','profile','stage','lesson','view','reflection','draft']) || value.schemaVersion!==2 || !tracks[value.profile] || !stages[value.stage] || !['study','options','sources','practice','record'].includes(value.view) || !strings(value.identity,['name','email','goal']) || !strings(learning,['needs','qualifications','priorKnowledge','targetDate','style']) || !Array.isArray(learning.focus) || !learning.focus.every(x=>typeof x==='string') || !Array.isArray(value.conversation) || !value.conversation.every(c=>strings(c,['id','at','role','text','source'])&&['user','assistant'].includes(c.role)&&['lessonId','lessonTitle'].every(k=>c[k]===undefined||typeof c[k]==='string')&&(c.lessonPrompt===undefined||typeof c.lessonPrompt==='boolean')&&(!c.workspaceSources||Array.isArray(c.workspaceSources)&&c.workspaceSources.every(s=>typeof s==='string'))&&(!c.courseSources||Array.isArray(c.courseSources)&&c.courseSources.every(s=>strings(s,['id','title'])))) || !Array.isArray(value.attempts) || !value.attempts.every(validSession) || value.quiz!==null&&!validSession(value.quiz) || !Array.isArray(value.activities) || !value.activities.every(a=>strings(a,['at','text']))) throw new Error('The saved learning record is incompatible. It has not been overwritten.');
  return {...defaults,...value,learning:{...learning,focus:[...new Set(['epidemiology','causal',...learning.focus])]}};
}
export function transcriptEntry(state,role,text,source='study guide',details={}) {
  const entry={id:crypto.randomUUID(),at:new Date().toISOString(),role,text,source,...details};
  state.conversation.push(entry); return entry;
}
export function reviewRecord(state) {
  const attempts=[...state.attempts,...(state.quiz?[state.quiz]:[])].map(session=>({
    ...structuredClone(session),
    answers:session.answers.map(a=>{const copy=structuredClone(a);if(session.mode==='test'&&!session.completedAt&&!session.endedAt)delete copy.correct;return copy;}),result:session.completedAt?learnerResult(session):null,
    questionSnapshots:session.questionIds.map(id=>{const q=structuredClone(sessionQuestion(session,id));if(session.mode==='test'&&!session.completedAt&&!session.endedAt){delete q.correct;delete q.explanation;delete q.hint;delete q.lesson;q.options=q.options.map(({id,text})=>({id,text}));}return q;}),
    status:session.completedAt?'completed':session.endedAt?'ended early':'in progress'
  }));
  return {schemaVersion:2,exportedAt:new Date().toISOString(),portfolioID:state.id,startedAt:state.startedAt,
    learner:structuredClone(state.identity),learningOptions:structuredClone(state.learning),pathway:tracks[state.profile].title,rExperience:stages[state.stage],
    bankVersion,questionSource:'Original StatsDirect teaching drafts; subject-expert review pending. Not official examination questions.',
    marking:'Provisional fixed-key MCQ scoring: 1 correct, 0 otherwise. First answers retained. Confidence and free-text reasoning are not graded. Independent practice is unsupervised and cannot certify exam readiness.',
    reviewStatus:'Not independently reviewed. No accreditation or CPD points awarded. Email preparation does not confirm delivery or acceptance.',
    attempts,conversation:structuredClone(state.conversation),activities:structuredClone(state.activities),reflection:state.reflection};
}
export function reviewText(record) {
  const lines=['STATSDIRECT — LEARNING RECORD','External review request',`Prepared: ${record.exportedAt}`,`Record: ${record.portfolioID}`,`Started: ${record.startedAt}`,'',`Learner: ${record.learner.name || '(not supplied)'}`,`Reply email: ${record.learner.email || '(not supplied)'}`,`Learning goal: ${record.learner.goal || '(not supplied)'}`,`Pathway: ${record.pathway}`,`R experience: ${record.rExperience}`,`Exams / qualifications: ${record.learningOptions?.qualifications || '(not supplied)'}`,`Learning needs: ${record.learningOptions?.needs || '(not supplied)'}`,`Prior knowledge: ${record.learningOptions?.priorKnowledge || '(not supplied)'}`,`Target date: ${record.learningOptions?.targetDate || '(not supplied)'}`,`Focus: ${(record.learningOptions?.focus || []).join(', ')}`,`Preferred teaching style: ${record.learningOptions?.style || ''}`,'',record.questionSource,record.marking,record.reviewStatus,'','PRACTICE ATTEMPTS'];
  for(const a of record.attempts) {
    lines.push('',`${tracks[a.track].title} — ${a.mode==='test'?'Independent practice (unsupervised)':'Supported practice'} — ${a.status}`,`Started: ${a.startedAt} | Completed: ${a.completedAt || 'not completed'}`,a.result?`Provisional score: ${a.result.score}/${a.result.total}; ${a.result.assisted} answers flagged as assisted`:`Answered: ${a.answers.length}/${a.questionIds.length}`);
    for(const q of a.questionSnapshots) {
      const answer=a.answers.find(x=>x.questionId===q.id);
      lines.push('',`${q.id} v${q.version} — ${q.topic}`,q.stem,...q.options.map(o=>`${o.id}. ${o.text}`),`First answer: ${answer?.choice || 'not answered'} | Key: ${q.correct || 'withheld until the attempt ends'}`,`Confidence: ${answer?.confidence || 'not recorded'} | Assisted: ${answer?.assisted??false}`,`Reasoning: ${answer?.reasoning || '(none)'}`,`Feedback: ${q.explanation || 'withheld until the attempt ends'}`,`Help: https://www.statsdirect.com/help/${q.help}`);
    }
  }
  lines.push('','COMPLETE LEARNING CONVERSATION');
  for(const c of record.conversation) lines.push('',`[${c.at}] ${c.role==='user'?'Learner':'Tutor'} — ${c.source}${c.lessonTitle?' · '+c.lessonTitle:''}${c.model?' / '+c.model:''}`,c.text,...(c.courseSources??[]).map(s=>'Course reference: '+s.id+' — '+s.title),...(c.workspaceSources??[]).map(s=>'StatsDirect context: '+s));
  lines.push('','LEARNING ACTIVITIES');
  for(const a of record.activities) lines.push(`[${a.at}] ${a.text}`);
  lines.push('','LEARNER REFLECTION',record.reflection || '(not supplied)');
  return lines.join('\n');
}
export function practiceContext(state) {
  const q=state.quiz;
  if(!q || q.mode==='test'&&!q.completedAt)return '';
  const item=sessionQuestion(q,q.questionIds[Math.min(q.answers.length,q.questionIds.length-1)]);
  return item?`${item.stem}\n${item.options.map(x=>x.id+'. '+x.text).join('\n')}\nTeaching rationale: ${item.explanation}`:'';
}
