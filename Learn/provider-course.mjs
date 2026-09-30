export const trainingDefaults=()=>({providerName:'',courseTitle:'',courseVersion:'',reviewEmail:'support@statsdirect.com',requirements:'',cpdStatement:''});
export const safeURL=s=>{try{const u=new URL(s);return u.protocol==='https:'&&!u.username&&!u.password&&(!u.port||u.port==='443')?u.href:'';}catch{return '';}};
export const validEmail=s=>typeof s==='string'&&s.length<=254&&!/\s/.test(s)&&/^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?\.[A-Za-z]{2,63}$/.test(s);
export const courseKey=p=>p?.schemaVersion===2?`${p.id}:${p.version}`:'';
export function courseLessons(pack){return (pack?.lessons??[]).map(l=>({...l,id:`course:${courseKey(pack)}:${l.id}`,topic:l.topic||pack.title,steps:l.steps||'',challenge:l.challenge||'Explain what you have learned and how you would use it in your work.',providerCourse:true}));}
export function courseQuestions(pack){return (pack?.questions??[]).map(q=>({...q,id:`course:${courseKey(pack)}:${q.id}`,track:'core',version:pack.version,topic:q.topic||pack.title,objective:q.objective||'',hint:q.hint||'Explain the population, variables and comparison before choosing.',lesson:q.lesson||'Use the course notes and explain your reasoning.',help:q.help||'',options:q.options.map(o=>({...o,feedback:o.feedback||q.explanation}))}));}
export function adoptCourse(state,pack){
  const key=courseKey(pack);if(!key||key===state.courseKey)return;
  state.courseKey=key;state.training={providerName:pack.provider.name,courseTitle:pack.title,courseVersion:pack.version,reviewEmail:pack.provider.reviewEmail,requirements:pack.provider.assessmentRequirements||'',cpdStatement:pack.provider.cpdStatement||''};
}
export function submitCourseWork(state,lesson,text){
  if(!lesson?.providerCourse||!text.trim())throw Error('Write your answer or practical findings before saving.');
  const attempt={id:crypto.randomUUID(),at:new Date().toISOString(),courseKey:state.courseKey,training:structuredClone(state.training),lessonID:lesson.id,lessonTitle:lesson.title,objective:lesson.objective,task:lesson.challenge,text:text.trim().slice(0,20000),status:'Submitted locally for review; not marked'};
  state.courseWork.push(attempt);return attempt;
}
export function addProviderReview(state,value){
  if(value?.schemaVersion!==1||value.portfolioID!==state.id||!['provider','reviewer','reviewedAt','decision','feedback'].every(k=>typeof value[k]==='string'&&value[k].trim()&&value[k].length<=20000))throw Error('This assessment response does not match the learning record or is incomplete.');
  const review={schemaVersion:1,portfolioID:state.id,provider:value.provider,reviewer:value.reviewer,reviewedAt:value.reviewedAt,decision:value.decision,feedback:value.feedback,courseKey:String(value.courseKey||''),creditStatement:String(value.creditStatement||'').slice(0,3000),reference:String(value.reference||'').slice(0,1000),importedAt:new Date().toISOString(),verification:'Imported provider response; authenticity not independently verified by StatsDirect.'};
  state.providerReviews.push(review);return review;
}
