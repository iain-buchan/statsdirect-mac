import React,{useState,useEffect,useRef} from 'react';
import {createRoot} from 'react-dom/client';
import DataEditor,{GridCellKind,CompactSelection,type GridSelection,type DataEditorRef} from '@glideapps/glide-data-grid';
import '@glideapps/glide-data-grid/dist/index.css';
import './operation.css';
import {ResultPreview} from './ResultPreview';
import {InstantAnswers} from './instant-answers.mjs';
import {columnName,MAX_ROWS} from './store.mjs';
import {EntryTable} from './entry-table.mjs';
import {worksheetInput,worksheetInputFrom,worksheetRows} from './operation-data.mjs';
import {selectAdjacentCell, cellMovement, arrowKeyEditor} from './navigation';
declare global { interface Window { statsDirectOperation:any; webkit?:any; } }
const native=(action:string,extra:object={})=>window.webkit?.messageHandlers?.statsDirectOperation?.postMessage({action,...extra});
const empty:GridSelection={columns:CompactSelection.empty(),rows:CompactSelection.empty()};
// Worksheet columns are read from the live worksheet when a step is submitted (see
// analysis-source.mjs); entered data is already complete.
const pendingColumns=new Map<string,{resolve:(v:any)=>void,reject:(e:Error)=>void}>();let columnToken=0;
const fetchColumns=(request:any)=>new Promise<any>((resolve,reject)=>{const token=String(++columnToken);pendingColumns.set(token,{resolve,reject});native('columns',{token,...request});});
const resolveInput=(v:any)=>v?.lazy?fetchColumns(v.request).then((data:any)=>worksheetInputFrom(v,data)):Promise.resolve(v);
function DataInput({p,source,onChange,initial,onChooseColumns}:{p:any,source:any,onChange:(v:any)=>void,initial:any,onChooseColumns:()=>void}) {
  // A rejected long-data answer comes back as `initial` with its worksheet columns and roles, so the same choices are shown again for correction.
  const longInitial=initial?.layout==='long'&&source?.lazy&&Array.isArray(initial.range?.columns)?initial:undefined;
  const [useSheet,setUseSheet]=useState(!!source && !p.screen && (!initial||!!longInitial)),[selected,setSelected]=useState<number[]>(()=>source?.selection?.slice(0,p.maxColumns)??[]);
  // Long data: one data column with group identifiers (or treatment and block identifiers), as the Windows "groups by identifier" setting.
  // Only a live worksheet can serve it; lesson sources carry their cells and stay in separate columns.
  // Paired modes (treatment and block; group and sub-group for two-dimensional frames) take one identifier and one block column.
  // The analysis of covariance takes a predictor (X) column, outcome (Y) column(s) and group identifier column(s).
  const twoWay=p.groupIdentifiers==='treatmentAndBlock'||p.groupIdentifiers==='groupAndSubgroup',covariance=p.groupIdentifiers==='covariance',canPivot=!!p.groupIdentifiers&&!!source?.lazy,longOnly=p.layout==='long';
  const idLabel=p.identifierLabels?.first??(p.groupIdentifiers==='treatmentAndBlock'?'Treatment (column) identifier':'Group identifier column(s)'),blockLabel=p.identifierLabels?.second??'Block (row) identifier';
  const dataLabel=covariance?'Predictor (X) column':'Data column',outcomesLabel=p.identifierLabels?.outcomes??'Outcome (Y) column(s)';
  const [byIdentifier,setByIdentifier]=useState(!!longInitial||longOnly||(canPivot&&!!p.groupsByIdentifier));
  const [dataCol,setDataCol]=useState<number|undefined>(()=>longInitial?.range.columns[0]);
  const [idCols,setIdCols]=useState<number[]>(()=>longInitial?longInitial.range.columns.slice(1,1+(longInitial.roles?.identifiers??1)):[]);
  const [blockCol,setBlockCol]=useState<number|undefined>(()=>longInitial?.roles?.block?longInitial.range.columns[1+(longInitial.roles?.identifiers??1)]:undefined);
  const [outcomeCols,setOutcomeCols]=useState<number[]>(()=>longInitial?.roles?.outcomes?longInitial.range.columns.slice(1+(longInitial.roles?.identifiers??1)+(longInitial.roles?.block?1:0)):[]);
  const longLayout=useSheet&&byIdentifier&&canPivot?{mode:p.groupIdentifiers,data:dataCol,identifiers:idCols,block:blockCol,...(covariance?{outcomes:outcomeCols}:{})}:undefined;
  const chosen=longLayout?[dataCol,...idCols,blockCol,...outcomeCols].filter((n):n is number=>Number.isInteger(n)):selected;
  const [rowOverride,setRowOverride]=useState<{first:string,last:string}|null>(longInitial?{first:String(longInitial.range.firstRow),last:String(longInitial.range.lastRow)}:null);
  const suggestedRows=worksheetRows(source,chosen,p.length);
  const first=rowOverride?.first??String(suggestedRows.first),last=rowOverride?.last??String(suggestedRows.last);
  const previousSource=useRef(source);
  useEffect(()=>{
    // A rejected answer remounts this form with the same source. Keep its restored row
    // range; reset the selection only when the worksheet actually changes or is refreshed.
    if(previousSource.current===source)return;
    previousSource.current=source;
    setRowOverride(null);if(source?.selection)setSelected(source.selection.slice(0,p.maxColumns));
    // Columns the refreshed worksheet no longer has are dropped from the long-data choices.
    const count=source?.columns?.length??0;setDataCol(d=>Number.isInteger(d)&&d!<count?d:undefined);setIdCols(a=>a.filter(n=>n<count));setBlockCol(b=>Number.isInteger(b)&&b!<count?b:undefined);setOutcomeCols(a=>a.filter(n=>n<count));},[source]);
  const [table,setTable]=useState(()=>new EntryTable(p,null,longInitial?undefined:initial));
  const [revision,refresh]=useState(0),[showTitles,setShowTitles]=useState(false);
  const [selection,setSelection]=useState(empty),[cell,setCell]=useState(''),[error,setError]=useState(table.error);
  const container=useRef<HTMLDivElement>(null),[width,setWidth]=useState(700);
  const grid=useRef<DataEditorRef>(null);
  useEffect(()=>{
    if(!p.screen||!source||initial)return;
    const next=new EntryTable(p,source,null);setTable(next);setError(next.error);setSelection(empty);
    let current=true;
    if(next.pending) resolveInput(next.pending).then(input=>{
      if(!current)return;
      next.load(input);refresh(n=>n+1);
    }).catch((e:Error)=>{if(current){next.pending=null;next.error=e.message;setError(e.message);refresh(n=>n+1);}});
    return()=>{current=false;};
  },[source]);
  const store=table.store,titles=store.columns,rows=store.rows,loading=!!table.pending;
  const [c,r]=selection.current?.cell??[0,0];
  useEffect(()=>{setCell(store.get(c,r));},[r,c,table,revision]);
  useEffect(()=>{const observer=new ResizeObserver(([e])=>setWidth(Math.floor(e.contentRect.width)));if(container.current)observer.observe(container.current);return()=>observer.disconnect();},[useSheet]);
  useEffect(()=>{
    onChange(()=> longOnly&&!longLayout ? {layout:"columns"} : useSheet ? worksheetInput(source,selected,Number(first),Number(last),longLayout) : table.input());
  },[useSheet,source,selected,first,last,table,revision,byIdentifier,dataCol,idCols,blockCol,outcomeCols]);
  const apply=(change:()=>void)=>{try{if(loading)return;change();table.error='';setError('');refresh(n=>n+1);}catch(e){setError((e as Error).message);}};
  const paste=(text:string)=>apply(()=>table.paste(text,c,r));
  useEffect(()=>{window.statsDirectOperation.pasteText=paste;return()=>{delete window.statsDirectOperation.pasteText;};});
  function edit(value:string){apply(()=>store.apply([[c,r,value]]));}
  if(longOnly&&!longLayout)return <div className="data-input"><p>This layout needs a live worksheet with a data column and group identifiers. Entered data and lesson examples use separate columns.</p><button type="button" onClick={onChooseColumns}>Use separate columns</button><button type="button" onClick={()=>{setUseSheet(true);native('refresh');}}>Refresh worksheet</button></div>;
  return <div className="data-input"><p className="hint">{p.mode?.startsWith('Text')?'Select labels or text for this step.':'Select measurements or counts for this step.'}</p>
    <div className="switch"><button type="button" className={useSheet?'chosen':''} disabled={!source} onClick={()=>setUseSheet(true)}>Worksheet columns</button><button type="button" className={!useSheet?'chosen':''} onClick={()=>setUseSheet(false)}>Enter / paste data</button><button type="button" onClick={()=>native('refresh')}>Refresh worksheet</button></div>
    {useSheet&&source?<><p className="source">{source.name} · snapshot of the last selected worksheet</p>
      {canPivot&&!longOnly&&<div className="switch layout-switch"><span>Groups are</span><button type="button" className={!byIdentifier?'chosen':''} onClick={()=>{setByIdentifier(false);native('groupsByIdentifier',{value:false});}}>in separate columns</button><button type="button" className={byIdentifier?'chosen':''} onClick={()=>{setByIdentifier(true);native('groupsByIdentifier',{value:true});}}>{twoWay?'identified by treatment and block columns':'identified by a column of group labels'}</button></div>}
      {longOnly&&!canPivot&&<p className="hint">This layout reads a live worksheet. With entered or lesson data, continue with separate columns and choose that layout when asked again, or open a worksheet and press Refresh worksheet.</p>}
      {longLayout?<>
        <p>{covariance?'Choose the predictor (X) column, the outcome (Y) column(s), one per replicate, and the column(s) whose values label each observation\u2019s group (series).':`Choose the data column, then the ${twoWay?`${idLabel.toLowerCase()} and the ${blockLabel.toLowerCase()} columns`:'column(s) whose values label each observation\u2019s group'}.`} {p.maxColumns<10000?`${p.minColumns}–${p.maxColumns} groups allowed.`:`At least ${p.minColumns} group(s).`}</p>
        <div className="roles">
          <fieldset><legend>{dataLabel}</legend><div className="column-chooser">{source.columns.map((label:string,i:number)=><label key={i}><input type="radio" name="long-data" checked={dataCol===i} onChange={()=>setDataCol(i)}/><span>{columnName(i)} · {label}</span></label>)}</div></fieldset>
          <fieldset><legend>{idLabel}</legend><div className="column-chooser">{source.columns.map((label:string,i:number)=><label key={i}><input type={twoWay?'radio':'checkbox'} name="long-ids" checked={idCols.includes(i)} onChange={e=>setIdCols(a=>twoWay?[i]:e.target.checked?[...a,i]:a.filter(n=>n!==i))}/><span>{columnName(i)} · {label}</span>{!twoWay&&idCols.includes(i)&&<b>{idCols.indexOf(i)+1}</b>}</label>)}</div></fieldset>
          {covariance&&<fieldset><legend>{outcomesLabel}</legend><div className="column-chooser">{source.columns.map((label:string,i:number)=><label key={i}><input type="checkbox" name="long-outcomes" checked={outcomeCols.includes(i)} onChange={e=>setOutcomeCols(a=>e.target.checked?[...a,i]:a.filter(n=>n!==i))}/><span>{columnName(i)} · {label}</span>{outcomeCols.includes(i)&&<b>{outcomeCols.indexOf(i)+1}</b>}</label>)}</div></fieldset>}
          {twoWay&&<fieldset><legend>{blockLabel}</legend><div className="column-chooser">{source.columns.map((label:string,i:number)=><label key={i}><input type="radio" name="long-block" checked={blockCol===i} onChange={()=>setBlockCol(i)}/><span>{columnName(i)} · {label}</span></label>)}</div></fieldset>}
        </div>
        <p className="selection">{covariance?'X':'Data'}: {Number.isInteger(dataCol)?source.columns[dataCol!]:'None'}{covariance&&<> · Y: {outcomeCols.map(i=>source.columns[i]).join(', ')||'None'}</>} · {twoWay?idLabel:'Groups'}: {idCols.map(i=>source.columns[i]).join(', ')||'None'}{twoWay&&<> · {blockLabel}: {Number.isInteger(blockCol)?source.columns[blockCol!]:'None'}</>}</p>
      </>:<>
      <p>Choose columns in the order required by the question. {p.maxColumns<10000?`${p.minColumns}–${p.maxColumns} columns allowed.`:`At least ${p.minColumns} column(s).`}</p>
      <div className="column-chooser">{source.columns.map((label:string,i:number)=><label key={i}><input type="checkbox" checked={selected.includes(i)} onChange={e=>setSelected(a=>e.target.checked?[...a,i]:a.filter(n=>n!==i))}/><span>{columnName(i)} · {label}</span>{selected.includes(i)&&<b>{selected.indexOf(i)+1}</b>}</label>)}</div>
      <p className="selection">Selected order: {selected.map(i=>source.columns[i]).join(' → ')||'None'}</p></>}<div className="row-range"><label>First worksheet row<input type="number" min={source.firstRow} value={first} onChange={e=>setRowOverride({first:e.target.value,last})}/></label><label>Last worksheet row<input type="number" max={source.rows} value={last} onChange={e=>setRowOverride({first,last:e.target.value})}/></label></div><p className="hint">The row range follows the selected cells or columns. Missing cells inside this range retain their worksheet positions.</p>
    </>:<fieldset disabled={loading} aria-busy={loading}>{loading&&<p role="status">Loading selected worksheet data…</p>}<div className="grid-tools"><button type="button" onClick={()=>{window.statsDirectOperation.pasteText=paste;native('paste');}}>Paste data</button>{!p.fixedRows&&<button type="button" disabled={rows===MAX_ROWS} onClick={()=>apply(()=>table.dimensions(Math.min(MAX_ROWS,rows+10),titles.length))}>+ 10 rows</button>}{titles.length<table.maxColumns&&<button type="button" onClick={()=>apply(()=>table.dimensions(rows,titles.length+1))}>+ Column</button>}{titles.length>p.minColumns&&<button type="button" onClick={()=>apply(()=>{table.dimensions(rows,titles.length-1);setSelection(empty);})}>Remove last column</button>}<span>{rows} rows × {titles.length} columns</span></div>
      {p.rowLabels&&<p>Rows: {p.rowLabels.join(' / ')}</p>}<label className="cell-editor">Row {r+1}, column {c+1}<input value={cell} aria-label="Selected data cell" onChange={e=>{setCell(e.target.value);edit(e.target.value);}} onKeyDown={e=>{const movement=cellMovement(e);if(movement){e.preventDefault();e.stopPropagation();selectAdjacentCell([c,r],movement,titles.length,rows,setSelection,grid.current);}}}/></label>
      <div ref={container} className="grid"><div className="grid-frame"><DataEditor ref={grid} provideEditor={arrowKeyEditor} trapFocus width={Math.min(width,40+170*titles.length)} height={Math.min(300,36+34*rows+(40+170*titles.length>width?16:0))} rowMarkerWidth={40} headerHeight={36} rowHeight={34} columns={titles.map(title=>({title,width:170}))} rows={rows} rowMarkers="number" getCellsForSelection={true} getCellContent={([x,y])=>({kind:GridCellKind.Text,data:store.get(x,y),displayData:store.get(x,y),allowOverlay:!loading,readonly:loading})} gridSelection={selection} onGridSelectionChange={setSelection} onCellsEdited={items=>{apply(()=>store.apply(items.filter(({value})=>value.kind===GridCellKind.Text).map(({location:[x,y],value})=>[x,y,value.data])));return true;}} onPaste={(target,values)=>{apply(()=>table.pasteValues(values,target[0],target[1]));return false;}} smoothScrollX smoothScrollY/></div></div>
      <details onToggle={e=>setShowTitles(e.currentTarget.open)}><summary>Column names</summary>{showTitles&&titles.map((title,i)=><label className="field" key={i}>Column {i+1}<input value={title} onChange={e=>apply(()=>{store.columns[i]=e.target.value;})}/></label>)}</details><p className="hint">Paste tab-separated cells without headings or totals. Use * for a missing observation. Blank trailing rows are ignored.</p></fieldset>}

    {p.mode?.includes('Coding')&&<p className="hint">Text columns are treated as categories. The engine will ask about reference categories when dummy coding is needed.</p>}{error&&<p role="alert" className="error">{error}</p>}
  </div>;
}
const tutorInputs=new Map<symbol,()=>any>();
function Prompt({p,source,onSubmit,onCancel,initial,busy,embedded=false,register}:{p:any,source:any,onSubmit:(v:any)=>void,onCancel:()=>void,initial:any,busy:boolean,embedded?:boolean,register?:(reader:()=>any)=>void}) {
  const initialValue=()=>initial??(p.kind==='options'?Object.fromEntries(p.options.map((o:any)=>[o.value,o.selected])):['fields','settings'].includes(p.kind)?Object.fromEntries(p.fields.map((o:any)=>[o.name,o.defaultValue??''])):p.kind==='selectList'?[]:p.defaultValue??(p.kind==='option'?p.options[0]?.value:'')??'');
  const [value,setValue]=useState<any>(initialValue),[error,setError]=useState(''); const gridValue=useRef<()=>any>(()=>{throw new Error('Enter or select data.');}); const resolving=useRef(false);
  useEffect(()=>{register?.(()=>p.kind==='grid'?gridValue.current():value);},[value,p.kind,register]);
  const tutorKey=useRef(Symbol());
  useEffect(()=>{tutorInputs.set(tutorKey.current,()=>({prompt:p.prompt,name:p.name,kind:p.kind,value:p.kind==='grid'?gridValue.current():value}));return()=>{tutorInputs.delete(tutorKey.current);};},[p,value]);
  const Container=embedded?'div':'form';
  function submit(e:React.FormEvent){e.preventDefault();if(resolving.current)return;try{const v=p.kind==='grid'?gridValue.current():value;setError('');resolving.current=true;resolveInput(v).then(resolved=>{resolving.current=false;onSubmit(resolved);}).catch((err:Error)=>{resolving.current=false;setError(err.message);});}catch(e){setError((e as Error).message);}}
  return <Container className={embedded?'embedded-prompt':p.kind==='settings'?'settings-form':undefined} onSubmit={embedded?undefined:submit}><fieldset disabled={busy}><div className="prompt-body"><h2>{p.kind==='settings'?'Current defaults':p.prompt==='Enter a value'&&p.kind==='confidence'?'Confidence level':p.prompt==='Enter a value'&&p.kind==='grid'?'Enter the data table':p.prompt||p.title}</h2>{p.rubric&&<p className="rubric">{p.rubric}</p>}{p.error&&<p className="error" role="alert">{p.error}</p>}
    {p.kind==='settings'?<><p>These defaults are saved for new analyses. Analyses already open keep their current settings.</p><div className="settings">{p.fields.map((f:any)=><div key={f.name} className="field">{f.kind==='boolean'?<label><input type="checkbox" disabled={f.disabled} checked={!!value[f.name]} onChange={e=>setValue({...value,[f.name]:e.target.checked})}/>{f.prompt}</label>:<label>{f.prompt}<select aria-label={f.prompt} value={value[f.name]} onChange={e=>setValue({...value,[f.name]:e.target.value})}>{f.options.map((o:any)=><option key={o.value} value={o.value}>{o.label}</option>)}</select></label>}{f.note&&<span className="hint">{f.note}</span>}</div>)}</div><p className="hint" hidden={!p.fields.some((f:any)=>f.name==='use-default-ci')}>Turn off “Use a default confidence interval” to choose confidence separately for each analysis. Methods that require an explicit confidence or probability still ask for it.</p></>:
    p.kind==='boolean'?<div className="yesno"><label><input type="radio" name={`boolean-${p.name}`} checked={value===true} onChange={()=>setValue(true)}/>Yes</label><label><input type="radio" name={`boolean-${p.name}`} checked={value!==true} onChange={()=>setValue(false)}/>No</label></div>:
    p.kind==='options'?<div className="choices">{p.options.map((o:any)=><label key={o.value}><input type="checkbox" checked={!!value[o.value]} onChange={e=>setValue({...value,[o.value]:e.target.checked})}/>{o.label}</label>)}</div>:
    p.kind==='option'?<div className="choices">{p.options.map((o:any)=><label key={o.value}><input type="radio" name={`choice-${p.name}`} checked={value===o.value} onChange={()=>setValue(o.value)}/>{o.label}</label>)}</div>:
    p.kind==='selectList'?<div className="choices">{p.options.map((o:any)=><label key={o.value}><input type={p.multiple?'checkbox':'radio'} name={`list-${p.name}`} checked={value.includes(Number(o.value))} onChange={e=>setValue(p.multiple?(e.target.checked?[...value,Number(o.value)]:value.filter((x:number)=>x!==Number(o.value))):[Number(o.value)])}/>{o.label}</label>)}</div>:
    p.kind==='grid'?<DataInput onChooseColumns={()=>onSubmit({layout:"columns"})} p={p} source={source} initial={initial??p.initial} onChange={f=>gridValue.current=f}/>:
    p.kind==='fields'?<div className="fields">{p.fields.map((f:any)=><label className="field" key={f.name}>{f.label}<input type={f.kind==='text'?'text':'number'} step={f.kind==='integer'?1:'any'} value={value[f.name]??''} min={f.min??undefined} max={f.max??undefined} required={f.kind!=='text'} onChange={e=>setValue({...value,[f.name]:e.target.value})}/></label>)}</div>:
    <label className="field">{p.kind==='confidence'?(p.prompt==='Enter a value'?'Confidence level (%)':'Percentage (%)'):'Value'}<input autoFocus aria-label={p.kind==='confidence'?(p.prompt==='Enter a value'?'Confidence level (%)':'Percentage (%)'):'Value'} required={p.kind!=='text'} type={p.kind==='text'?'text':'number'} step={p.kind==='integer'?1:'any'} min={p.min??undefined} max={p.max??undefined} value={value} onChange={e=>setValue(e.target.value)}/></label>}
    {error&&<p className="error" role="alert">{error}</p>}</div>{!embedded&&<div className="actions"><button className="primary" type="submit">{p.kind==='settings'?'Save defaults':'Continue →'}</button>{p.kind==='settings'&&<button type="button" onClick={onCancel}>Cancel</button>}{p.skip&&<button type="button" onClick={()=>onSubmit({skip:true})}>{p.skip}</button>}{p.kind==='settings'&&busy&&<span role="status">Saving defaults…</span>}</div>}</fieldset></Container>;
}
function InstantEditor({steps,onRun,busy}:{steps:any[],onRun:(steps:any[])=>void,busy:boolean}) {
  const readers=useRef(new Map<number,()=>any>()),[error,setError]=useState(''),resolving=useRef(false);
  return <form className="instant-inputs" onSubmit={e=>{e.preventDefault();if(resolving.current)return;try{const values=steps.map((s,i)=>readers.current.get(i)!());setError('');resolving.current=true;Promise.all(values.map(resolveInput)).then(resolved=>{resolving.current=false;onRun(steps.map((s,i)=>({...s,value:resolved[i]})));}).catch((err:Error)=>{resolving.current=false;setError(err.message);});}catch(e){setError((e as Error).message);}}}>
    <h2>Data and parameters</h2>
    {steps.map((s,i)=><Prompt key={i} p={s.p} initial={s.value} source={null} busy={busy} onSubmit={()=>{}} onCancel={()=>{}} embedded register={reader=>readers.current.set(i,reader)}/>)}
    {error&&<p className="error" role="alert">{error}</p>}
    <div className="actions"><button className="primary" disabled={busy}>Recalculate</button></div>
  </form>;
}
function App(){
  const [config,setConfig]=useState<any>({title:'Analysis'}),[source,setSource]=useState<any>(null),[state,setState]=useState<any>({state:'ready'}),[busy,setBusy]=useState(false),[error,setError]=useState('');
  const answers=useRef(new InstantAnswers());
  const [result,setResult]=useState<any>(null),[steps,setSteps]=useState<any[]>([]);
  // Where output frames go: the definition's placement in a live worksheet, as on Windows, else a new document.
  const [placement,setPlacement]=useState<string|undefined>(undefined),[includeSource,setIncludeSource]=useState(true);
  useEffect(()=>{window.statsDirectOperation={tutorSnapshot:()=>({inputs:Array.from(tutorInputs.values()).map(read=>{try{const input=read();return JSON.stringify(input).length<=50000?input:{error:'Input too large for the tutor; choose a smaller worksheet range.'};}catch(e){return {error:(e as Error).message};}})}),configure:(c:any)=>setConfig(c),setSource:(s:any)=>setSource(s),columnData:(r:any)=>{const p=pendingColumns.get(r?.token);if(!p)return;pendingColumns.delete(r.token);if(r.error)p.reject(new Error(r.error));else p.resolve(r);},update:(s:any)=>{setState(s);setBusy(false);setError('');if(s.state==='input'){const next=answers.current.next(s.prompt);if(next.found){setBusy(true);native('answer',{token:s.token,value:next.value});}}if(s.state==='complete')setSteps(answers.current.finish());},showResult:(r:any)=>{setResult(r);window.scrollTo(0,0);},resultKept:(name:string)=>setResult((r:any)=>r?{...r,kept:name}:r),error:(s:string)=>{setError(s);setBusy(false);}};native('ready');return()=>{delete window.statsDirectOperation;};},[]);
  const isActive=['input','running'].includes(state.state),isSettings=['AnalysisOptions','MetaCalculationOptions','MetaPlotOptions'].includes(config.id);
  return <main className={isSettings?'options-page':undefined}><header><div><div className="eyebrow">ANALYSIS / STATSDIRECT</div><h1>{config.title}</h1><p>{isSettings?"Review all defaults below, then save them together.":"Results collect in the active report. Use File → New Report to start another."}</p></div><button onClick={()=>native('help')}>Method help ↗</button></header>
    {error&&<p className="error" role="alert">{error}</p>}
    {state.writesWorksheet&&!config.instant&&source&&isActive&&<label className="source">Write the results <select name="output-placement" value={placement??(source.lazy?(state.placement??'new'):'new')} onChange={e=>{setPlacement(e.target.value);native('outputMode',{placement:e.target.value});}}><option value="new">into a new worksheet document</option>{source.lazy&&<><option value="AfterSelection">after the selected worksheet columns (inserted)</option><option value="BeforeSelection">before the selected worksheet columns (inserted)</option><option value="ReplaceSelection">in place of the selected worksheet columns</option><option value="LastColumn">after the last used worksheet column</option><option value="FirstColumn">as the first worksheet columns (inserted)</option></>}</select></label>}
    {config.derivedOutput&&source&&isActive&&(placement??(source.lazy?(state.placement??'new'):'new'))==='new'&&<label className="source"><input type="checkbox" checked={includeSource} onChange={e=>{setIncludeSource(e.target.checked);native('outputMode',{includeSource:e.target.checked});}}/> Keep original worksheet columns alongside the derived columns in a new worksheet. Uncheck for derived columns only.</label>}
    <ResultPreview result={result} busy={busy} onKeep={()=>native('keepResult',{id:result.id})}/>
    {state.state==='complete'&&state.suggestions?.length>0&&<section className="follow-on"><h2>Follow-on analyses</h2><p>These methods continue from the inputs and results of this analysis, as StatsDirect for Windows offers after a result.</p>
      <div className="choices">{state.suggestions.map((s:any)=><button key={s.operation} type="button" onClick={()=>native('followOn',{operation:s.operation,title:s.title,help:s.help??null})}>{s.title}</button>)}</div></section>}
    {config.instant&&state.state==='complete'&&steps.length>0&&<InstantEditor steps={steps} busy={busy} onRun={edited=>{answers.current.restart(edited);setResult(null);setBusy(true);native('start');}}/>}
    {state.state==='ready'&&<section><h2>{config.unavailable?'Method help available':error?'Unable to open the form':'Opening input form…'}</h2>{config.unavailable&&<p className="notice">{config.unavailable}</p>}{error&&!config.unavailable&&<button className="primary" disabled={busy} onClick={()=>{setBusy(true);native('start');}}>Try again</button>}</section>}
    {/* A rejected answer is shown again for correction, except for an option prompt, whose re-ask carries the engine's corrected default (the layout choice after a columns-only source). */}
    {state.state==='input'&&<Prompt key={state.token} p={state.prompt} source={source} busy={busy} initial={state.prompt.error&&state.prompt.kind!=='option'?answers.current.previous(state.prompt):undefined} onCancel={()=>{setBusy(true);native('cancel');}} onSubmit={value=>{answers.current.record(state.prompt,value);if((state.prompt.name==='layout2d'||state.prompt.name==='layoutCovariance')&&state.prompt.kind==='option')native('groupsByIdentifier',{value:value==='identifiers'});setBusy(true);native('answer',{token:state.token,value});}}/>}
    {state.state==='running'&&<section aria-live="polite"><h2>{state.progress||'Calculating…'}</h2><progress value={state.fraction??undefined} max={1}/><p>You can read help and earlier reports while this calculation runs.</p></section>}
    {!isActive&&state.state!=='ready'&&!(config.instant&&state.state==='complete')&&<section><h2>{state.state==='complete'?(isSettings?'Analysis defaults saved':'Analysis complete'):state.state==='cancelled'?(isSettings?'Changes cancelled':'Analysis cancelled'):'Analysis could not finish'}</h2><p className={state.state==='failed'?'error':''}>{state.error|| (state.state==='complete'?(isSettings?'These settings will be used by new analyses, including after restarting StatsDirect.':'Your results have been added to the active report.'):(isSettings?'Your saved defaults are unchanged.':'No final report was created.'))}</p><button className="primary" disabled={busy} onClick={()=>{answers.current=new InstantAnswers();setResult(null);setBusy(true);native('start');}}>{isSettings?'Edit defaults':'Run again'}</button></section>}
    {isActive&&(!isSettings||state.state==='running')&&<div className="cancel"><button onClick={()=>{setBusy(true);native('cancel');}}>{isSettings?'Cancel':'Cancel analysis'}</button><span>{busy?'Waiting for the engine…':'Answers are checked by the StatsDirect engine.'}</span></div>}
    {!isSettings&&!!state.history?.length&&<details className="history"><summary>{state.history.length} completed input steps</summary><ol>{state.history.map((h:any,i:number)=><li key={i}>{h.title||`Input ${i+1}`}</li>)}</ol></details>}
  </main>;
}
createRoot(document.getElementById('root')!).render(<App/>);
