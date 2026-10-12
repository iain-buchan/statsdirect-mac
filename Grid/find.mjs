// Search only populated cells; empty Excel-sized sheets need no rectangular scan.
export function findCell(store, query, after, backwards=false) {
  const needle=String(query).toLocaleLowerCase();
  if(!needle)return null;
  const order=([c,r])=>r*16384+c;
  const start=after?order(after):(backwards?Infinity:-1);
  let next=null, wrap=null;
  store.forEachCell((c,r,text)=>{
    if(!String(text).toLocaleLowerCase().includes(needle))return;
    const cell=[c,r], index=order(cell);
    if(!wrap||(backwards?index>order(wrap):index<order(wrap)))wrap=cell;
    if((backwards?index<start:index>start)&&(!next||(backwards?index>order(next):index<order(next))))next=cell;
  });
  return next??wrap;
}
