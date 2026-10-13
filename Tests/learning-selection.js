window.runLearningSelectionChecks=async function(){
  const checks=[],check=(value,name)=>{if(!value)throw Error(name);checks.push(name);};
  const api=window.statsDirectLearn,id='selection-fixture';
  const delay=()=>new Promise(resolve=>setTimeout(resolve,120));
  const messages=()=>document.getElementById('messages');
  const body=()=>document.querySelector('[data-message-id="'+id+'"] .message-body');
  const selection=()=>window.getSelection();
  const endpointOffset=(node,offset)=>{const range=document.createRange();range.selectNodeContents(body());range.setEnd(node,offset);return range.toString().length;};
  const top=()=>messages().scrollTop;
  const bottom=()=>messages().scrollHeight-messages().clientHeight-top()<3;
  const tail=Array.from({length:45},(_,i)=>'Paragraph '+i+' with enough text to keep a substantial conversation.').join('\n\n');
  let text='A growing paragraph with **bold words** and plain text.';
  api.resumeReply({action:'partial',value:{id},partial:text+'\n\n'+tail});await delay();
  let strong=body().querySelector('strong').firstChild,plain=body().querySelector('strong').nextSibling;
  selection().setBaseAndExtent(strong,0,plain,15);
  const selected=selection().toString(),originalTop=top();
  text+=' One more sentence in the same paragraph.';
  api.partial({id,text:text+'\n\n'+tail});await delay();
  check(selection().toString()===selected,'selection across bold/plain text survives growing paragraph');
  check(Math.abs(top()-originalTop)<1,'selected text holds reading position while rendering continues');
  check(body().textContent.includes('One more sentence'),'streaming continues while selected');
  strong=body().querySelector('strong').firstChild;plain=body().querySelector('strong').nextSibling;
  selection().setBaseAndExtent(plain,15,strong,0);
  const backwardsAnchor=endpointOffset(selection().anchorNode,selection().anchorOffset),backwardsFocus=endpointOffset(selection().focusNode,selection().focusOffset);
  api.partial({id,text:text+' Extra words.\n\n'+tail});await delay();
  // At a formatting boundary, the end of one text node and start of the next
  // represent the same endpoint. Compare logical offsets and direction.
  check(selection().toString()===selected&&endpointOffset(selection().anchorNode,selection().anchorOffset)===backwardsAnchor&&endpointOffset(selection().focusNode,selection().focusOffset)===backwardsFocus&&backwardsAnchor>backwardsFocus,'backwards anchor and focus survive replacement');
  selection().removeAllRanges();messages().scrollTop=100;
  api.partial({id,text:text+' Extra words.\n\n'+tail+'\n\nLast paragraph.'});await delay();
  check(Math.abs(top()-100)<1,'scrolling back without selection pauses following');
  messages().scrollTop=messages().scrollHeight;
  const last=body().lastElementChild.firstChild;selection().setBaseAndExtent(last,0,last,4);
  const selectedAtBottom=top();
  let final=text+' Extra words.\n\n'+tail+'\n\nLast paragraph.\n\n'+tail;
  api.partial({id,text:final});await delay();
  check(selection().toString()==='Last'&&Math.abs(top()-selectedAtBottom)<1&&!bottom(),'selection at bottom suppresses following: '+JSON.stringify({selected:selection().toString(),before:selectedAtBottom,after:top(),height:messages().scrollHeight,viewport:messages().clientHeight}));
  selection().removeAllRanges();messages().scrollTop=messages().scrollHeight;
  final+='\n\nFollowing again.';api.partial({id,text:final});await delay();
  check(bottom(),'clearing selection and returning to bottom resumes following');
  const paragraph=body().lastElementChild.firstChild;
  selection().setBaseAndExtent(paragraph,9,paragraph,0);const beforeCompletion=top();
  api.reply({id,text:final,model:'fixture-model'});await delay();
  check(selection().toString()==='Following'&&selection().anchorOffset===9&&selection().focusOffset===0,'completion preserves backwards selection with the same message identity');
  // Removing the Stop/status row enlarges the viewport; its old bottom offset
  // can exceed the new scroll maximum. The browser must clamp only that excess.
  const completedTop=Math.min(beforeCompletion,messages().scrollHeight-messages().clientHeight);
  check(Math.abs(top()-completedTop)<1,'completion preserves reading position within the resized viewport');
  selection().removeAllRanges();
  api.resumeReply({action:'partial',value:{id:'stopped-fixture'},partial:'Keep this received partial reply.'});
  api.tutorError({id:'stopped-fixture',message:'Stopped by test'});await delay();
  check(document.querySelector('[data-message-id="stopped-fixture"]').textContent.includes('Keep this received partial reply.'),'stopping retains received text');
  return {checks};
};
