import React,{useState,useEffect,useRef} from 'react';
import {createRoot} from 'react-dom/client';
import DataEditor,{GridCellKind,CompactSelection,type GridSelection} from '@glideapps/glide-data-grid';
import '@glideapps/glide-data-grid/dist/index.css';
import './operation.css';
import {columnName} from './store.mjs';
import {worksheetInput,enteredInput,pasteMatrix} from './operation-data.mjs';
declare global { interface Window { statsDirectOperation:any; webkit?:any; } }
const native=(action:string,extra:object={})=>window.webkit?.messageHandlers?.statsDirectOperation?.postMessage({action,...extra});
const empty:GridSelection={columns:CompactSelection.empty(),rows:CompactSelection.empty()};
function DataInput({p,source,onChange,initial}:{p:any,source:any,onChange:(v:any)=>void,initial:any}) {
  const [useSheet,setUseSheet]=useState(!!source && !p.screen && !initial),[selected,setSelected]=useState<number[]>(()=>source?.selection?.slice(0,p.maxColumns)??[]);
  const [first,setFirst]=useState(String(source?.firstRow??1)),[last,setLast]=useState(String(source?.rows??12));
  const [matrix,setMatrix]=useState<string[][]>(()=>initial?.columns?Array.from({length:Math.max(p.rows,initial.columns[0].values.length)},(_,r)=>initial.columns.map((c:any)=>c.values[r]??'')):Array.from({length:p.rows??12},()=>Array.from({length:Math.max(1,p.minColumns)},()=>'')));
  const [titles,setTitles]=useState<string[]>(initial?.columns?.map((c:any)=>c.title)??p.labels??Array.from({length:Math.max(1,p.minColumns)},(_,i)=>`Column ${i+1}`));
  const [selection,setSelection]=useState(empty),[cell,setCell]=useState(''),[error,setError]=useState('');
  const container=useRef<HTMLDivElement>(null),[width,setWidth]=useState(700);
  const [c,r]=selection.current?.cell??[0,0];
  useEffect(()=>{setCell(matrix[r]?.[c]??'');},[r,c,matrix]);
  useEffect(()=>{const observer=new ResizeObserver(([e])=>setWidth(Math.floor(e.contentRect.width)));if(container.current)observer.observe(container.current);return()=>observer.disconnect();},[]);
  useEffect(()=>{
    onChange(()=> useSheet ? worksheetInput(source,selected,Number(first),Number(last)) : enteredInput(matrix,titles,p.fixedRows));
  },[useSheet,source,selected,first,last,matrix,titles]);
  const apply=(next:string[][])=>{setMatrix(next);setTitles(t=>Array.from({length:next[0].length},(_,i)=>t[i]??`Column ${i+1}`));setError('');};
  const paste=(text:string)=>{try{apply(pasteMatrix(matrix,text,c,r,p.fixedRows,p.maxColumns));}catch(e){setError((e as Error).message);}};
  useEffect(()=>{window.statsDirectOperation.pasteText=paste;return()=>{delete window.statsDirectOperation.pasteText;};});
  function edit(value:string){const next=matrix.map(r=>[...r]);next[r][c]=value;apply(next);}
  return <div className="data-input">
    <div className="switch"><button type="button" className={useSheet?'chosen':''} disabled={!source||p.screen} onClick={()=>setUseSheet(true)}>Worksheet columns</button><button type="button" className={!useSheet?'chosen':''} onClick={()=>setUseSheet(false)}>Enter / paste data</button><button type="button" onClick={()=>native('refresh')}>Refresh worksheet</button></div>
    {useSheet&&source?<><p className="source">{source.name} · snapshot of the last selected worksheet</p><p>Choose columns in the order required by the question. {p.maxColumns<10000?`${p.minColumns}–${p.maxColumns} columns allowed.`:`At least ${p.minColumns} column(s).`}</p>
      <div className="column-chooser">{source.columns.map((label:string,i:number)=><label key={i}><input type="checkbox" checked={selected.includes(i)} onChange={e=>setSelected(a=>e.target.checked?[...a,i]:a.filter(n=>n!==i))}/><span>{columnName(i)} · {label}</span>{selected.includes(i)&&<b>{selected.indexOf(i)+1}</b>}</label>)}</div>
      <p className="selection">Selected order: {selected.map(i=>source.columns[i]).join(' → ')||'None'}</p><div className="row-range"><label>First worksheet row<input type="number" min={source.firstRow} value={first} onChange={e=>setFirst(e.target.value)}/></label><label>Last worksheet row<input type="number" max={source.rows} value={last} onChange={e=>setLast(e.target.value)}/></label></div>
    </>:<><div className="grid-tools"><button type="button" onClick={()=>native('paste')}>Paste data</button>{!p.fixedRows&&<button type="button" onClick={()=>apply([...matrix,...Array.from({length:10},()=>titles.map(()=>''))])}>+ 10 rows</button>}{titles.length<p.maxColumns&&<button type="button" onClick={()=>apply(matrix.map(r=>[...r,'']))}>+ Column</button>}{titles.length>p.minColumns&&<button type="button" onClick={()=>apply(matrix.map(r=>r.slice(0,-1)))}>Remove last column</button>}<span>{matrix.length} rows × {titles.length} columns</span></div>
      {p.rowLabels&&<p>Rows: {p.rowLabels.join(' / ')}</p>}<label className="cell-editor">Row {r+1}, column {c+1}<input value={cell} aria-label="Selected data cell" onChange={e=>{setCell(e.target.value);edit(e.target.value);}}/></label>
      <div ref={container} className="grid"><DataEditor width={width} height={300} columns={titles.map(title=>({title,width:170}))} rows={matrix.length} rowMarkers="number" getCellsForSelection={true} getCellContent={([x,y])=>({kind:GridCellKind.Text,data:matrix[y]?.[x]??'',displayData:matrix[y]?.[x]??'',allowOverlay:true})} gridSelection={selection} onGridSelectionChange={setSelection} onCellsEdited={items=>{const next=matrix.map(r=>[...r]);items.forEach(({location:[x,y],value})=>{if(value.kind===GridCellKind.Text)next[y][x]=value.data;});apply(next);return true;}} onPaste={(target,values)=>{try{apply(pasteMatrix(matrix,values.map(r=>r.join('\t')).join('\n'),target[0],target[1],p.fixedRows,p.maxColumns));}catch(e){setError((e as Error).message);}return false;}} smoothScrollX smoothScrollY/></div>
      <details><summary>Column names</summary>{titles.map((title,i)=><label className="field" key={i}>Column {i+1}<input value={title} onChange={e=>setTitles(t=>t.map((v,n)=>n===i?e.target.value:v))}/></label>)}</details><p className="hint">Paste tab-separated cells without headings or totals. Use * for a missing observation. Blank trailing rows are ignored.</p></>}
    {p.mode?.includes('Coding')&&<p className="hint">Text columns are treated as categories. The engine will ask about reference categories when dummy coding is needed.</p>}{error&&<p role="alert" className="error">{error}</p>}
  </div>;
}
function Prompt({p,source,onSubmit,initial,busy}:{p:any,source:any,onSubmit:(v:any)=>void,initial:any,busy:boolean}) {
  const initialValue=()=>initial??(p.kind==='options'?Object.fromEntries(p.options.map((o:any)=>[o.value,o.selected])):p.kind==='fields'?Object.fromEntries(p.fields.map((o:any)=>[o.name,o.defaultValue??''])):p.kind==='selectList'?[]:p.defaultValue??(p.kind==='option'?p.options[0]?.value:'')??'');
  const [value,setValue]=useState<any>(initialValue),[error,setError]=useState(''); const gridValue=useRef<()=>any>(()=>{throw new Error('Enter or select data.');});
  function submit(e:React.FormEvent){e.preventDefault();try{onSubmit(p.kind==='grid'?gridValue.current():value);setError('');}catch(e){setError((e as Error).message);}}
  return <form onSubmit={submit}><fieldset disabled={busy}><h2>{p.prompt==='Enter a value'&&p.kind==='confidence'?'Confidence level':p.prompt==='Enter a value'&&p.kind==='grid'?'Enter the data table':p.prompt||p.title}</h2>{p.rubric&&<p className="rubric">{p.rubric}</p>}{p.error&&<p className="error" role="alert">{p.error}</p>}
    {p.kind==='boolean'?<div className="yesno"><label><input type="radio" name="boolean" checked={value===true} onChange={()=>setValue(true)}/>Yes</label><label><input type="radio" name="boolean" checked={value!==true} onChange={()=>setValue(false)}/>No</label></div>:
    p.kind==='options'?<div className="choices">{p.options.map((o:any)=><label key={o.value}><input type="checkbox" checked={!!value[o.value]} onChange={e=>setValue({...value,[o.value]:e.target.checked})}/>{o.label}</label>)}</div>:
    p.kind==='option'?<div className="choices">{p.options.map((o:any)=><label key={o.value}><input type="radio" name="choice" checked={value===o.value} onChange={()=>setValue(o.value)}/>{o.label}</label>)}</div>:
    p.kind==='selectList'?<div className="choices">{p.options.map((o:any)=><label key={o.value}><input type={p.multiple?'checkbox':'radio'} name="list" checked={value.includes(Number(o.value))} onChange={e=>setValue(p.multiple?(e.target.checked?[...value,Number(o.value)]:value.filter((x:number)=>x!==Number(o.value))):[Number(o.value)])}/>{o.label}</label>)}</div>:
    p.kind==='grid'?<DataInput p={p} source={source} initial={initial??p.initial} onChange={f=>gridValue.current=f}/>:
    p.kind==='fields'?<div className="fields">{p.fields.map((f:any)=><label className="field" key={f.name}>{f.label}<input type={f.kind==='text'?'text':'number'} step={f.kind==='integer'?1:'any'} value={value[f.name]??''} min={f.min??undefined} max={f.max??undefined} required={f.kind!=='text'} onChange={e=>setValue({...value,[f.name]:e.target.value})}/></label>)}</div>:
    <label className="field">{p.kind==='confidence'?(p.prompt==='Enter a value'?'Confidence level (%)':'Percentage (%)'):'Value'}<input autoFocus aria-label={p.kind==='confidence'?(p.prompt==='Enter a value'?'Confidence level (%)':'Percentage (%)'):'Value'} required={p.kind!=='text'} type={p.kind==='text'?'text':'number'} step={p.kind==='integer'?1:'any'} min={p.min??undefined} max={p.max??undefined} value={value} onChange={e=>setValue(e.target.value)}/></label>}
    {error&&<p className="error" role="alert">{error}</p>}<div className="actions"><button className="primary" type="submit">Continue →</button>{p.skip&&<button type="button" onClick={()=>onSubmit({skip:true})}>{p.skip}</button>}</div></fieldset></form>;
}
function App(){
  const [config,setConfig]=useState<any>({title:'Analysis'}),[source,setSource]=useState<any>(null),[state,setState]=useState<any>({state:'ready'}),[busy,setBusy]=useState(false),[error,setError]=useState('');
  const lastAnswer=useRef<any>();
  useEffect(()=>{window.statsDirectOperation={configure:(c:any)=>setConfig(c),setSource:(s:any)=>setSource(s),update:(s:any)=>{setState(s);setBusy(false);setError('');},error:(s:string)=>{setError(s);setBusy(false);}};native('ready');return()=>{delete window.statsDirectOperation;};},[]);
  const isActive=['input','running'].includes(state.state);
  return <main><header><div><div className="eyebrow">ANALYSIS / STATSDIRECT</div><h1>{config.title}</h1><p>Results and charts open in separate report tabs.</p></div><button onClick={()=>native('help')}>Method help ↗</button></header>
    {error&&<p className="error" role="alert">{error}</p>}
    {state.state==='ready'&&<section><h2>{config.unavailable?'Method help available':'Start analysis'}</h2>{config.unavailable&&<p className="notice">{config.unavailable}</p>}<p>{source?`Worksheet: ${source.name}. You can choose columns or enter data when prompted.`:'You can enter or paste data into the input forms, or select a worksheet tab first.'}</p><button className="primary" disabled={busy||!!config.unavailable} onClick={()=>{setBusy(true);native('start');}}>Start {config.title}</button></section>}
    {state.state==='input'&&<Prompt key={state.token} p={state.prompt} source={source} busy={busy} initial={state.prompt.error?lastAnswer.current:undefined} onSubmit={value=>{lastAnswer.current=value;setBusy(true);native('answer',{token:state.token,value});}}/>}
    {state.state==='running'&&<section aria-live="polite"><h2>{state.progress||'Calculating…'}</h2><progress value={state.fraction??undefined} max={1}/><p>You can read help and earlier reports while this calculation runs.</p></section>}
    {!isActive&&state.state!=='ready'&&<section><h2>{state.state==='complete'?'Analysis complete':state.state==='cancelled'?'Analysis cancelled':'Analysis could not finish'}</h2><p className={state.state==='failed'?'error':''}>{state.error|| (state.state==='complete'?'Your report is open in its own tab.':'No final report was created.')}</p><button className="primary" disabled={busy} onClick={()=>{lastAnswer.current=undefined;setBusy(true);native('start');}}>Run again</button></section>}
    {isActive&&<div className="cancel"><button onClick={()=>{setBusy(true);native('cancel');}}>Cancel analysis</button><span>{busy?'Waiting for the engine…':'Answers are checked by the StatsDirect engine.'}</span></div>}
    {!!state.history?.length&&<details className="history"><summary>{state.history.length} completed input steps</summary><ol>{state.history.map((h:any,i:number)=><li key={i}>{h.title||`Input ${i+1}`}</li>)}</ol></details>}
  </main>;
}
createRoot(document.getElementById('root')!).render(<App/>);
