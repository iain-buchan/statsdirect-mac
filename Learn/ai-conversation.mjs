// Mac AI dock: reuse Learning's sanitized rich output and streaming selection logic.
import {richText,bindRichText} from './Upstream/Learning/rich-text.mjs';
import {conversationReading,restoreConversationReading} from './Upstream/Learning/conversation-view.mjs';
const messages=document.getElementById('messages');
let generation=null;
const post=value=>window.webkit?.messageHandlers.statsDirectAI.postMessage(value);
// Copy answers: the host copies its own text for the block shown, or says that it could not match it.
const copyInHost=value=>{const handler=window.webkit?.messageHandlers.statsDirectAICopy;return handler?handler.postMessage(value).then(copied=>copied===true,()=>false):false;};
// AI Assist's local receipt under a reply: the ranges its bounded reads used, or that it read no cells. It is built
// from text only (workbook and sheet names come from files) and stays outside the reply body, so the reading position
// and the R block numbering are unaffected. The provider never receives it.
function receipt(row,opened){
 if(row.role!=='assistant')return null;
 if(Array.isArray(row.dataUsed)&&row.dataUsed.length){
  const details=document.createElement('details'),summary=document.createElement('summary'),list=document.createElement('ul');
  details.className='data-used';details.dataset.receipt=row.id;details.open=opened.has(row.id);
  summary.textContent='Data used';
  for(const line of row.dataUsed){const item=document.createElement('li');item.textContent=String(line);list.append(item);}
  details.append(summary,list);return details;
 }
 if(row.generalGuidance===true){const p=document.createElement('p');p.className='scope data-used-none';p.textContent='General guidance · No worksheet cells read for this reply';return p;}
 return null;
}
function render(state){
 const reading=state.generation===generation?conversationReading(messages):null;
 const expanded=state.generation===generation&&state.collapseR
  ?new Set(Array.from(messages.querySelectorAll('details[data-r-block][open]'),block=>block.dataset.rBlock))
  :new Set();
 const opened=state.generation===generation
  ?new Set(Array.from(messages.querySelectorAll('details[data-receipt][open]'),block=>block.dataset.receipt))
  :new Set();
 generation=state.generation;
 const fragment=document.createDocumentFragment();
 if(!state.messages.length){const p=document.createElement('p');p.className='intro';p.textContent=state.introduction;fragment.append(p);}
 for(const row of state.messages){
  const article=document.createElement('article');article.className='message '+row.role;article.dataset.messageId=row.id;
  const label=document.createElement('div');label.className='message-label';label.textContent=row.role==='user'?'You':'ChatGPT';article.append(label);
  if(row.context){const scope=document.createElement('p');scope.className='scope';scope.textContent=row.context;article.append(scope);}
  const body=document.createElement('div');body.className='message-body';
  if(row.role==='assistant')body.innerHTML=richText(row.text);else {body.classList.add('user-text');body.textContent=row.text;}
  article.append(body);
  const used=receipt(row,opened);if(used)article.append(used);
  fragment.append(article);
  const approvedGeneration=state.generation;
  for(const [index,button] of Array.from(body.querySelectorAll('[data-code=r]')).entries()){
   const block=button.closest('.code-block');
   if(state.runRInSession){
    button.textContent='Run in this R session';
    const shown=block.querySelector('code').textContent;
    button.disabled=row.pending||!row.rBlockTexts?.includes(shown);
   }
   if(state.collapseR){
    const disclosure=document.createElement('details'),summary=document.createElement('summary');
    disclosure.dataset.rBlock=row.id+':'+index;
    disclosure.open=expanded.has(disclosure.dataset.rBlock);
    summary.textContent='Suggested R code';
    block.replaceWith(disclosure);
    disclosure.append(summary,block);
   }
  }
  // Both buttons send the block's text as shown; the host uses only its own reading of the saved reply (code-blocks.mjs).
  bindRichText(body,{copy:code=>copyInHost({generation:approvedGeneration,messageID:row.id,code}),
   openR:(code,info)=>post({action:state.runRInSession?'runR':'openR',generation:approvedGeneration,messageID:info.messageID,blockIndex:info.blockIndex,code})});
  if(row.pending)body.querySelectorAll('[data-code]').forEach(button=>button.disabled=true);
 }
 messages.replaceChildren(fragment);
 restoreConversationReading(messages,reading);
}
window.StatsDirectAIConversation={render};
post({action:'ready'});
