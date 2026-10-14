// Mac AI dock: reuse Learning's sanitized rich output and streaming selection logic.
import {richText,bindRichText} from './rich-text.mjs';
import {conversationReading,restoreConversationReading} from './conversation-view.mjs';
const messages=document.getElementById('messages');
let generation=null;
const post=value=>window.webkit?.messageHandlers.statsDirectAI.postMessage(value);
function render(state){
 const reading=state.generation===generation?conversationReading(messages):null;
 generation=state.generation;
 const fragment=document.createDocumentFragment();
 if(!state.messages.length){const p=document.createElement('p');p.className='intro';p.textContent=state.introduction;fragment.append(p);}
 for(const row of state.messages){
  const article=document.createElement('article');article.className='message '+row.role;article.dataset.messageId=row.id;
  const label=document.createElement('div');label.className='message-label';label.textContent=row.role==='user'?'You':'ChatGPT';article.append(label);
  if(row.context){const scope=document.createElement('p');scope.className='scope';scope.textContent=row.context;article.append(scope);}
  const body=document.createElement('div');body.className='message-body';
  if(row.role==='assistant')body.innerHTML=richText(row.text);else {body.classList.add('user-text');body.textContent=row.text;}
  article.append(body);fragment.append(article);
  const approvedGeneration=state.generation;
  bindRichText(body,{copy:()=>{},openR:(_code,info)=>post({action:'openR',generation:approvedGeneration,messageID:info.messageID,blockIndex:info.blockIndex})});
  // Bind Copy to a native lookup, never a script-provided code payload.
  body.querySelectorAll('[data-code=copy]').forEach((button,index)=>button.onclick=()=>post({action:'copyCode',generation:approvedGeneration,messageID:row.id,code:button.closest(".code-block").querySelector("code").textContent}));
  if(row.pending)body.querySelectorAll('[data-code]').forEach(button=>button.disabled=true);
 }
 messages.replaceChildren(fragment);
 restoreConversationReading(messages,reading);
}
window.StatsDirectAIConversation={render};
post({action:'ready'});
