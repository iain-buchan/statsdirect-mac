import React,{useState,useEffect,useRef} from 'react';
import {createRoot} from 'react-dom/client';
import DataEditor,{GridCellKind,CompactSelection,type GridSelection,type DataEditorRef} from '@glideapps/glide-data-grid';
import '@glideapps/glide-data-grid/dist/index.css';
import './operation.css';
import {ResultPreview} from './ResultPreview';
import {InstantAnswers} from './instant-answers.mjs';
import {columnName} from './store.mjs';
import {worksheetInput,worksheetRows,enteredInput,pasteMatrix,initialGrid} from './operation-data.mjs';
import {selectAdjacentCell, cellMovement, arrowKeyEditor} from './navigation';
declare global { interface Window { statsDirectOperation:any; webkit?:any; } }
const native=(action:string,extra:object={})=>window.webkit?.messageHandlers?.statsDirectOperation?.postMessage({action,...extra});
const empty:GridSelection={columns:CompactSelection.empty(),rows:CompactSelection.empty()};
function DataInput({p,source,onChange,initial}:{p:any,source:any,onChange:(v:any)=>void,initial:any}) {
  const [useSheet,setUseSheet]=useState(!!source && !p.screen && !initial),[selected,setSelected]=useState<number[]>(()=>source?.selection?.slice(0,p.maxColumns)??[]);
  const [rowOverride,setRowOverride]=useState<{first:string,last:string}|null>(null);
  const suggestedRows=worksheetRows(source,selected,p.length);
  const first=rowOverride?.first??String(suggestedRows.first),last=rowOverride?.last??String(suggestedRows.last);
  useEffect(()=>setRowOverride(null),[source]);
  const [starting]=useState(()=>initialGrid(p,source,initial));
  const [matrix,setMatrix]=useState<string[][]>(starting.matrix);
  const [titles,setTitles]=useState<string[]>(starting.titles);
  const [selection,setSelection]=useState(empty),[cell,setCell]=useState(''),[error,setError]=useState(starting.error);
  const container=useRef<HTMLDivElement>(null),[width,setWidth]=useState(700);
  const grid=useRef<DataEditorRef>(null);
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
      <p className="selection">Selected order: {selected.map(i=>source.columns[i]).join(' → ')||'None'}</p><div className="row-range"><label>First worksheet row<input type="number" min={source.firstRow} value={first} onChange={e=>setRowOverride({first:e.target.value,last})}/></label><label>Last worksheet row<input type="number" max={source.rows} value={last} onChange={e=>setRowOverride({first,last:e.target.value})}/></label></div><p className="hint">The row range follows the selected cells or columns. Missing cells inside this range retain their worksheet positions.</p>
    </>:<><div className="grid-tools"><button type="button" onClick={()=>{window.statsDirectOperation.pasteText=paste;native('paste');}}>Paste data</button>{!p.fixedRows&&<button type="button" onClick={()=>apply([...matrix,...Array.from({length:10},()=>titles.map(()=>''))])}>+ 10 rows</button>}{titles.length<p.maxColumns&&<button type="button" onClick={()=>apply(matrix.map(r=>[...r,'']))}>+ Column</button>}{titles.length>p.minColumns&&<button type="button" onClick={()=>apply(matrix.map(r=>r.slice(0,-1)))}>Remove last column</button>}<span>{matrix.length} rows × {titles.length} columns</span></div>
      {p.rowLabels&&<p>Rows: {p.rowLabels.join(' / ')}</p>}<label className="cell-editor">Row {r+1}, column {c+1}<input value={cell} aria-label="Selected data cell" onChange={e=>{setCell(e.target.value);edit(e.target.value);}} onKeyDown={e=>{const movement=cellMovement(e);if(movement){e.preventDefault();e.stopPropagation();selectAdjacentCell([c,r],movement,titles.length,matrix.length,setSelection,grid.current);}}}/></label>
      <div ref={container} className="grid"><div className="grid-frame"><DataEditor ref={grid} provideEditor={arrowKeyEditor} trapFocus width={Math.min(width,40+170*titles.length)} height={Math.min(300,36+34*matrix.length+(40+170*titles.length>width?16:0))} rowMarkerWidth={40} headerHeight={36} rowHeight={34} columns={titles.map(title=>({title,width:170}))} rows={matrix.length} rowMarkers="number" getCellsForSelection={true} getCellContent={([x,y])=>({kind:GridCellKind.Text,data:matrix[y]?.[x]??'',displayData:matrix[y]?.[x]??'',allowOverlay:true})} gridSelection={selection} onGridSelectionChange={setSelection} onCellsEdited={items=>{const next=matrix.map(r=>[...r]);items.forEach(({location:[x,y],value})=>{if(value.kind===GridCellKind.Text)next[y][x]=value.data;});apply(next);return true;}} onPaste={(target,values)=>{try{apply(pasteMatrix(matrix,values.map(r=>r.join('\t')).join('\n'),target[0],target[1],p.fixedRows,p.maxColumns));}catch(e){setError((e as Error).message);}return false;}} smoothScrollX smoothScrollY/></div></div>
      <details><summary>Column names</summary>{titles.map((title,i)=><label className="field" key={i}>Column {i+1}<input value={title} onChange={e=>setTitles(t=>t.map((v,n)=>n===i?e.target.value:v))}/></label>)}</details><p className="hint">Paste tab-separated cells without headings or totals. Use * for a missing observation. Blank trailing rows are ignored.</p></>}
    {p.mode?.includes('Coding')&&<p className="hint">Text columns are treated as categories. The engine will ask about reference categories when dummy coding is needed.</p>}{error&&<p role="alert" className="error">{error}</p>}
  </div>;
}
function Prompt({p,source,onSubmit,onCancel,initial,busy,embedded=false,register}:{p:any,source:any,onSubmit:(v:any)=>void,onCancel:()=>void,initial:any,busy:boolean,embedded?:boolean,register?:(reader:()=>any)=>void}) {
  const initialValue=()=>initial??(p.kind==='options'?Object.fromEntries(p.options.map((o:any)=>[o.value,o.selected])):['fields','settings'].includes(p.kind)?Object.fromEntries(p.fields.map((o:any)=>[o.name,o.defaultValue??''])):p.kind==='selectList'?[]:p.defaultValue??(p.kind==='option'?p.options[0]?.value:'')??'');
  const [value,setValue]=useState<any>(initialValue),[error,setError]=useState(''); const gridValue=useRef<()=>any>(()=>{throw new Error('Enter or select data.');});
  useEffect(()=>{register?.(()=>p.kind==='grid'?gridValue.current():value);},[value,p.kind,register]);
  const Container=embedded?'div':'form';
  function submit(e:React.FormEvent){e.preventDefault();try{onSubmit(p.kind==='grid'?gridValue.current():value);setError('');}catch(e){setError((e as Error).message);}}
  return <Container className={embedded?'embedded-prompt':p.kind==='settings'?'settings-form':undefined} onSubmit={embedded?undefined:submit}><fieldset disabled={busy}><div className="prompt-body"><h2>{p.kind==='settings'?'Current defaults':p.prompt==='Enter a value'&&p.kind==='confidence'?'Confidence level':p.prompt==='Enter a value'&&p.kind==='grid'?'Enter the data table':p.prompt||p.title}</h2>{p.rubric&&<p className="rubric">{p.rubric}</p>}{p.error&&<p className="error" role="alert">{p.error}</p>}
    {p.kind==='settings'?<><p>These defaults are saved for new analyses. Analyses already open keep their current settings.</p><div className="settings">{p.fields.map((f:any)=><div key={f.name} className="field">{f.kind==='boolean'?<label><input type="checkbox" disabled={f.disabled} checked={!!value[f.name]} onChange={e=>setValue({...value,[f.name]:e.target.checked})}/>{f.prompt}</label>:<label>{f.prompt}<select aria-label={f.prompt} value={value[f.name]} onChange={e=>setValue({...value,[f.name]:e.target.value})}>{f.options.map((o:any)=><option key={o.value} value={o.value}>{o.label}</option>)}</select></label>}{f.note&&<span className="hint">{f.note}</span>}</div>)}</div><p className="hint">Turn off “Use a default confidence interval” to choose confidence separately for each analysis. Methods that require an explicit confidence or probability still ask for it.</p></>:
    p.kind==='boolean'?<div className="yesno"><label><input type="radio" name={`boolean-${p.name}`} checked={value===true} onChange={()=>setValue(true)}/>Yes</label><label><input type="radio" name={`boolean-${p.name}`} checked={value!==true} onChange={()=>setValue(false)}/>No</label></div>:
    p.kind==='options'?<div className="choices">{p.options.map((o:any)=><label key={o.value}><input type="checkbox" checked={!!value[o.value]} onChange={e=>setValue({...value,[o.value]:e.target.checked})}/>{o.label}</label>)}</div>:
    p.kind==='option'?<div className="choices">{p.options.map((o:any)=><label key={o.value}><input type="radio" name={`choice-${p.name}`} checked={value===o.value} onChange={()=>setValue(o.value)}/>{o.label}</label>)}</div>:
    p.kind==='selectList'?<div className="choices">{p.options.map((o:any)=><label key={o.value}><input type={p.multiple?'checkbox':'radio'} name={`list-${p.name}`} checked={value.includes(Number(o.value))} onChange={e=>setValue(p.multiple?(e.target.checked?[...value,Number(o.value)]:value.filter((x:number)=>x!==Number(o.value))):[Number(o.value)])}/>{o.label}</label>)}</div>:
    p.kind==='grid'?<DataInput p={p} source={source} initial={initial??p.initial} onChange={f=>gridValue.current=f}/>:
    p.kind==='fields'?<div className="fields">{p.fields.map((f:any)=><label className="field" key={f.name}>{f.label}<input type={f.kind==='text'?'text':'number'} step={f.kind==='integer'?1:'any'} value={value[f.name]??''} min={f.min??undefined} max={f.max??undefined} required={f.kind!=='text'} onChange={e=>setValue({...value,[f.name]:e.target.value})}/></label>)}</div>:
    <label className="field">{p.kind==='confidence'?(p.prompt==='Enter a value'?'Confidence level (%)':'Percentage (%)'):'Value'}<input autoFocus aria-label={p.kind==='confidence'?(p.prompt==='Enter a value'?'Confidence level (%)':'Percentage (%)'):'Value'} required={p.kind!=='text'} type={p.kind==='text'?'text':'number'} step={p.kind==='integer'?1:'any'} min={p.min??undefined} max={p.max??undefined} value={value} onChange={e=>setValue(e.target.value)}/></label>}
    {error&&<p className="error" role="alert">{error}</p>}</div>{!embedded&&<div className="actions"><button className="primary" type="submit">{p.kind==='settings'?'Save defaults':'Continue →'}</button>{p.kind==='settings'&&<button type="button" onClick={onCancel}>Cancel</button>}{p.skip&&<button type="button" onClick={()=>onSubmit({skip:true})}>{p.skip}</button>}{p.kind==='settings'&&busy&&<span role="status">Saving defaults…</span>}</div>}</fieldset></Container>;
}
function InstantEditor({steps,onRun,busy}:{steps:any[],onRun:(steps:any[])=>void,busy:boolean}) {
  const readers=useRef(new Map<number,()=>any>()),[error,setError]=useState('');
  return <form className="instant-inputs" onSubmit={e=>{e.preventDefault();try{onRun(steps.map((s,i)=>({...s,value:readers.current.get(i)!()})));setError('');}catch(e){setError((e as Error).message);}}}>
    <h2>Data and parameters</h2>
    {steps.map((s,i)=><Prompt key={i} p={s.p} initial={s.value} source={null} busy={busy} onSubmit={()=>{}} onCancel={()=>{}} embedded register={reader=>readers.current.set(i,reader)}/>)}
    {error&&<p className="error" role="alert">{error}</p>}
    <div className="actions"><button className="primary" disabled={busy}>Recalculate</button></div>
  </form>;
}
function App(){
  const [config,setConfig]=useState<any>({title:'Analysis'}),[source,setSource]=useState<any>(null),[state,setState]=useState<any>({state:'ready'}),[busy,setBusy]=useState(false),[error,setError]=useState('');
  const lastAnswer=useRef<any>();
  const answers=useRef(new InstantAnswers());
  const [result,setResult]=useState<any>(null),[steps,setSteps]=useState<any[]>([]);
  useEffect(()=>{window.statsDirectOperation={configure:(c:any)=>setConfig(c),setSource:(s:any)=>setSource(s),update:(s:any)=>{setState(s);setBusy(false);setError('');if(s.state==='input'){const next=answers.current.next(s.prompt);if(next.found){lastAnswer.current=next.value;setBusy(true);native('answer',{token:s.token,value:next.value});}}if(s.state==='complete')setSteps(answers.current.finish());},showResult:(r:any)=>{setResult(r);window.scrollTo(0,0);},resultKept:(name:string)=>setResult((r:any)=>r?{...r,kept:name}:r),error:(s:string)=>{setError(s);setBusy(false);}};native('ready');return()=>{delete window.statsDirectOperation;};},[]);
  const isActive=['input','running'].includes(state.state),isSettings=config.id==='AnalysisOptions';
  return <main className={isSettings?'options-page':undefined}><header><div><div className="eyebrow">ANALYSIS / STATSDIRECT</div><h1>{config.title}</h1><p>{isSettings?"Review all defaults below, then save them together.":"Results collect in the active report. Use File → New Report to start another."}</p></div><button onClick={()=>native('help')}>Method help ↗</button></header>
    {error&&<p className="error" role="alert">{error}</p>}
    <ResultPreview result={result} busy={busy} onKeep={()=>native('keepResult',{id:result.id})}/>
    {config.instant&&state.state==='complete'&&steps.length>0&&<InstantEditor steps={steps} busy={busy} onRun={edited=>{answers.current.restart(edited);setResult(null);setBusy(true);native('start');}}/>}
    {state.state==='ready'&&<section><h2>{config.unavailable?'Method help available':error?'Unable to open the form':'Opening input form…'}</h2>{config.unavailable&&<p className="notice">{config.unavailable}</p>}{error&&!config.unavailable&&<button className="primary" disabled={busy} onClick={()=>{setBusy(true);native('start');}}>Try again</button>}</section>}
    {state.state==='input'&&<Prompt key={state.token} p={state.prompt} source={source} busy={busy} initial={state.prompt.error?lastAnswer.current:undefined} onCancel={()=>{setBusy(true);native('cancel');}} onSubmit={value=>{lastAnswer.current=value;answers.current.record(state.prompt,value);setBusy(true);native('answer',{token:state.token,value});}}/>}
    {state.state==='running'&&<section aria-live="polite"><h2>{state.progress||'Calculating…'}</h2><progress value={state.fraction??undefined} max={1}/><p>You can read help and earlier reports while this calculation runs.</p></section>}
    {!isActive&&state.state!=='ready'&&!(config.instant&&state.state==='complete')&&<section><h2>{state.state==='complete'?(isSettings?'Analysis defaults saved':'Analysis complete'):state.state==='cancelled'?(isSettings?'Changes cancelled':'Analysis cancelled'):'Analysis could not finish'}</h2><p className={state.state==='failed'?'error':''}>{state.error|| (state.state==='complete'?(isSettings?'These settings will be used by new analyses, including after restarting StatsDirect.':'Your results have been added to the active report.'):(isSettings?'Your saved defaults are unchanged.':'No final report was created.'))}</p><button className="primary" disabled={busy} onClick={()=>{lastAnswer.current=undefined;answers.current=new InstantAnswers();setResult(null);setBusy(true);native('start');}}>{isSettings?'Edit defaults':'Run again'}</button></section>}
    {isActive&&(!isSettings||state.state==='running')&&<div className="cancel"><button onClick={()=>{setBusy(true);native('cancel');}}>{isSettings?'Cancel':'Cancel analysis'}</button><span>{busy?'Waiting for the engine…':'Answers are checked by the StatsDirect engine.'}</span></div>}
    {!isSettings&&!!state.history?.length&&<details className="history"><summary>{state.history.length} completed input steps</summary><ol>{state.history.map((h:any,i:number)=><li key={i}>{h.title||`Input ${i+1}`}</li>)}</ol></details>}
  </main>;
}
createRoot(document.getElementById('root')!).render(<App/>);
