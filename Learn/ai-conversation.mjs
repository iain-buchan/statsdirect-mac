// Mac AI dock: reuse Learning's sanitized rich output and streaming selection logic.
import {richText,bindRichText} from './Upstream/Learning/rich-text.mjs';
import {conversationReading,restoreConversationReading} from './Upstream/Learning/conversation-view.mjs';
const messages=document.getElementById('messages');
let generation=null;
const post=value=>window.webkit?.messageHandlers.statsDirectAI.postMessage(value);
// Copy answers: the host copies its own text for the block shown, or says that it could not match it.
const copyInHost=value=>{const handler=window.webkit?.messageHandlers.statsDirectAICopy;return handler?handler.postMessage(value).then(copied=>copied===true,()=>false):false;};
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
  // Both buttons send the block's text as shown; the host uses only its own reading of the saved reply (code-blocks.mjs).
  bindRichText(body,{copy:code=>copyInHost({generation:approvedGeneration,messageID:row.id,code}),
   openR:(code,info)=>post({action:'openR',generation:approvedGeneration,messageID:info.messageID,blockIndex:info.blockIndex,code})});
  if(row.pending)body.querySelectorAll('[data-code]').forEach(button=>button.disabled=true);
 }
 messages.replaceChildren(fragment);
 restoreConversationReading(messages,reading);
}
window.StatsDirectAIConversation={render};
post({action:'ready'});
