import {questions,tracks} from './bank.mjs';
import {createSession,recordAssistance,recordAnswer,learnerResult,reviewBundle} from './model.mjs';
const $=id=>document.getElementById(id);
const escape=value=>String(value).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
let session=null, index=0;
const current=()=>questions.find(q=>q.id===session.questionIds[index]);
function show(id){for(const section of ['welcome','study','results']) $(section).hidden=section!==id;}
function bubble(text, extra=''){const node=document.createElement('div');node.className='bubble '+extra;node.innerHTML='<span class="who">Scripted tutor</span><p>'+escape(text)+'</p>';$('conversation').append(node);}
function question(){
 const q=current();show('study');$('progress').textContent=`Question ${index+1} of ${session.questionIds.length}`;
 $('progress-bar').value=index;$('session-mode').textContent=session.mode==='learn'?'Guided learning':'Independent test';
 $('objective').textContent=tracks[session.track].title;$('topic').textContent=q.topic;$('conversation').replaceChildren();
 bubble(q.stem,'question');$('choices').innerHTML='<legend>Choose one best answer</legend>'+q.options.map(o=>`<label class="option"><input type="radio" name="choice" value="${o.id}" required><span><b>${o.id}</b>${escape(o.text)}</span></label>`).join('');
 $('reasoning').value='';$('confidence').value='fairly';$('answer-form').hidden=false;$('answer').textContent=session.mode==='learn'?'Check my answer':'Record my answer';
 $('answer').disabled=false;$('hint').hidden=$('explain').hidden=session.mode==='test';$('hint').disabled=$('explain').disabled=false;
 $('feedback').replaceChildren();$('error').textContent='';$('next').hidden=true;$('topic').focus();
}
$('mode').addEventListener('change',()=>{$('mode-note').textContent=$('mode').value==='learn'?'Explanations and hints are available as you work.':'Four questions without hints. Feedback appears after you finish.';});
$('start').addEventListener('click',()=>{session=createSession($('track').value,$('mode').value);index=0;for(const id of ['track','mode','start'])$(id).disabled=true;question();});
$('hint').addEventListener('click',()=>{recordAssistance(session,current().id,'hints');bubble(current().hint,'support');$('hint').disabled=true;});
$('explain').addEventListener('click',()=>{recordAssistance(session,current().id,'explanations');bubble(current().lesson,'support');$('explain').disabled=true;});
$('answer-form').addEventListener('submit',event=>{
 event.preventDefault();const choice=document.querySelector('input[name=choice]:checked')?.value;
 try{recordAnswer(session,current().id,choice,$('confidence').value,$('reasoning').value);}catch(e){$('error').textContent=e.message;return;}
 const a=session.answers.at(-1),q=current();$('answer-form').hidden=true;
 if(session.mode==='learn'){
  const selected=q.options.find(o=>o.id===a.choice);
  $('feedback').innerHTML=`<div class="feedback ${a.correct?'correct':''}"><strong>${a.correct?'Correct — now check your reasoning.':'Let’s work through that.'}</strong><p>You chose ${escape(a.choice)}. ${escape(selected.feedback)}</p><p>${escape(q.explanation)}</p><a href="../../Content/Help/${q.help}" target="_blank" rel="noopener">Read the StatsDirect method →</a></div>`;
 }else $('feedback').innerHTML='<div class="note">Answer recorded. Marking and explanations appear when you finish all four questions.</div>';
 $('next').hidden=false;$('next').textContent=index===session.questionIds.length-1?'See my learning record →':'Next question →';$('next').focus();
});
$('next').addEventListener('click',()=>{if(++index<session.questionIds.length)question();else results();});
function results(){
 show('results');const r=learnerResult(session);$('reflection').value='';
 $('score').innerHTML=`<div class="score"><strong>${r.score} / ${r.total}</strong><p>${session.mode==='learn'?'Guided practice':'Independent practice'} · provisional score from draft answer keys</p><p class="small">${r.assisted} ${r.assisted===1?'answer used':'answers used'} teaching support. Confidence and written reasoning do not change the MCQ score. This short set does not establish exam readiness.</p></div>`;
 $('plan').innerHTML='<h3>What to practise next</h3>'+(r.revisit.length?r.revisit.map(p=>`<div class="plan-item"><h3>${escape(p.topic)}</h3><p>${escape(p.objective)}</p><p class="small">${escape(p.reason)} · Review the explanation, then try a fresh problem.</p><a href="../../Content/Help/${p.help}" target="_blank" rel="noopener">Open the method guide →</a></div>`).join(''):'<p>You answered these four items correctly without recorded assistance or uncertainty. Try a fresh set and explain the reasoning before checking its answers.</p>');
 $('answer-review').innerHTML='<h3>Review your answers</h3>'+session.answers.map(a=>{const q=questions.find(q=>q.id===a.questionId);return `<details><summary>${escape(q.topic)} · ${a.correct?'Correct':'Revisit'}</summary><p>${escape(q.stem)}</p><p>Your answer: ${escape(a.choice)} · Key: ${escape(q.correct)} · Confidence: ${escape(a.confidence)}</p><p>${escape(q.explanation)}</p>${a.reasoning?`<p>Your reasoning: ${escape(a.reasoning)}</p>`:''}</details>`;}).join('');
 $('result-title').focus();
}
$('reflection').addEventListener('input',()=>{session.reflection=$('reflection').value;});
$('export').addEventListener('click',()=>{const data=JSON.stringify(reviewBundle(session),null,2);const url=URL.createObjectURL(new Blob([data],{type:'application/json'}));const a=document.createElement('a');a.href=url;a.download=`statsdirect-learn-${session.id}.json`;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);});
$('again').addEventListener('click',()=>{session=null;for(const id of ['track','mode','start'])$(id).disabled=false;show('welcome');$('track').focus();});
