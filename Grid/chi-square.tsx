import React, { useCallback, useEffect, useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import DataEditor, { CompactSelection, GridCellKind, type GridCell, type GridSelection, type Item, type DataEditorRef } from '@glideapps/glide-data-grid';
import '@glideapps/glide-data-grid/dist/index.css';
import './chi-square.css';
import { ContingencyTable, example, validate } from './contingency.mjs';
import {ResultPreview} from './ResultPreview';
import {screenSelection} from './operation-data.mjs';
import options from './chi-options.json';
import { selectAdjacentCell, cellMovement, arrowKeyEditor } from './navigation';

declare global { interface Window { webkit?: any; statsDirectChiSquare: any; } }
const table = new ContingencyTable();
const defaults = Object.fromEntries(options.map(o => [o.name, o.default]));
const native = (action: string, extra: object = {}) => window.webkit?.messageHandlers?.statsDirectAnalysis?.postMessage({action,...extra});
const emptySelection: GridSelection = { columns: CompactSelection.empty(), rows: CompactSelection.empty() };
function App() {
  const [result,setResult]=useState<any>(null);
  const [revision, refresh] = useState(0), [selection, select] = useState<GridSelection>(emptySelection);
  const [rows, setRows] = useState('2'), [cols, setCols] = useState('2');
  const [flags, setFlags] = useState(defaults), [confidence, setConfidence] = useState('95');
  const [iterations, setIterations] = useState('1000000'), [seed, setSeed] = useState('12345'), [mcConfidence, setMcConfidence] = useState('99');
  const [rowScores, setRowScores] = useState(''), [columnScores, setColumnScores] = useState('');
  const [message, setMessage] = useState('Enter observed counts, or load the worked example.'), [failed, setFailed] = useState(false);
  const [busy, setBusy] = useState(false), [cancelling, setCancelling] = useState(false), [cellText, setCellText] = useState('');
  const container = useRef<HTMLDivElement>(null), [size, setSize] = useState({width:600,height:280});
  const grid = useRef<DataEditorRef>(null);
  const current = useRef({selection,busy}); current.current = {selection,busy};
  const changed = useCallback(() => { refresh(n=>n+1); setRows(String(table.state.counts.length)); setCols(String(table.state.counts[0].length)); native('changed'); }, []);
  const attempt = (work: () => void) => { try { work(); setFailed(false); } catch(e) { setFailed(true); setMessage((e as Error).message); } };
  useEffect(() => {
    const observer = new ResizeObserver(([entry]) => setSize({width:Math.floor(entry.contentRect.width),height:Math.floor(entry.contentRect.height)}));
    if (container.current) observer.observe(container.current);
    window.statsDirectChiSquare = {
      setState: (running: boolean, text: string, error = false) => { setBusy(running); setCancelling(false); setMessage(text); setFailed(error); },
      pasteText: (text: string) => { if (current.current.busy) return; attempt(() => { const [c,r] = current.current.selection.current?.cell ?? [0,0]; table.paste(c,r,text); changed(); setMessage('Pasted counts. Review category labels and table dimensions.'); }); },
      showResult: (r:any) => {setResult(r);window.scrollTo(0,0);},
      resultKept: (name:string) => setResult((r:any)=>r?{...r,kept:name}:r),
      error: (text:string) => {setMessage(text);setFailed(true);},
      setSource: (source:any) => attempt(()=>{
        const counts=screenSelection(source,{screen:true,minColumns:2,maxColumns:200});
        if(!counts)return;
        table.change(s=>{s.counts=counts;s.columnLabels=source.selection.map((c:number)=>source.columns[c]);s.rowLabels=counts.map((_:any,i:number)=>`Row ${i+1}`);});
        changed();setMessage('Selected worksheet cells copied. Review the counts and category labels.');
      }),
      csvData: () => table.csv()
    };
    native('ready');
    return () => { observer.disconnect(); delete window.statsDirectChiSquare; };
  }, []);
  const [selectedCol, selectedRow] = selection.current?.cell ?? [0,0];
  useEffect(() => { setCellText(table.state.counts[selectedRow]?.[selectedCol] ?? ''); }, [selectedCol,selectedRow,revision]);
  const cell = useCallback(([c,r]:Item): GridCell => {
    const text = table.state.counts[r]?.[c] ?? '';
    return {kind:GridCellKind.Text,data:text,displayData:text,allowOverlay:!busy,readonly:busy};
  }, [revision,busy]);
  function editCell() {
    if (busy || table.state.counts[selectedRow]?.[selectedCol] === undefined) return;
    table.change(s=>s.counts[selectedRow][selectedCol] = cellText.trim()); changed();
  }
  function run() {
    attempt(() => {
      editCell();
      const input = {...validate(table.state),...flags,cco:Number(confidence)/100,
        iterations:Number(iterations),seed:Number(seed),ci:Number(mcConfidence)/100,
        rowScores:rowScores.trim().split(/[\s,;]+/).map(Number),columnScores:columnScores.trim().split(/[\s,;]+/).map(Number)};
      if (!(input.cco > 0 && input.cco < 1)) throw new Error('Confidence must be greater than 0% and less than 100%.');
      if (flags.doMonteCarlo && (!Number.isInteger(input.iterations) || !Number.isInteger(input.seed))) throw new Error('Iterations and seed must be whole numbers.');
      if (!window.webkit?.messageHandlers?.statsDirectAnalysis) throw new Error('Open this form in the StatsDirect Mac app to run the engine.');
      setResult(null); setBusy(true); setMessage('Running the StatsDirect engine…'); native('run',{input});
    });
  }
  const countRows = table.state.counts.length, countCols = table.state.counts[0].length;
  const total = table.state.counts.flat().reduce((a,v) => a + (v.trim() !== '' && Number.isFinite(Number(v)) ? Number(v) : 0),0);
  return <main>
    <header><div><div className="eyebrow">ANALYSIS / CHI-SQUARE / SCREEN DATA</div><h1>R × C contingency table</h1><p>Enter a count for each combination of categories.</p></div><button onClick={()=>native('help')}>Method help ↗</button></header>
    <ResultPreview result={result} busy={busy} onKeep={()=>native('keepResult',{id:result.id})}/>
    <div className="layout"><section className="data-panel" aria-label="Observed counts">
      <div className="section-title"><h2>Observed counts</h2><span>{countRows} rows × {countCols} columns</span></div>
      <div className="tools"><label>Rows <input aria-label="Number of rows" type="number" min="2" max="200" value={rows} disabled={busy} onChange={e=>setRows(e.target.value)}/></label><label>Columns <input aria-label="Number of columns" type="number" min="2" max="200" value={cols} disabled={busy} onChange={e=>setCols(e.target.value)}/></label><button disabled={busy} onClick={()=>attempt(()=>{table.resize(Number(rows),Number(cols));select(emptySelection);changed();setMessage('Table resized. Undo restores any removed counts.');})}>Resize table</button><button disabled={busy} onClick={()=>{table.change(s=>Object.assign(s,structuredClone(example)));setFlags({...defaults,xp:true,cs:true});setConfidence('95');setRowScores('1, 2, 3, 4');setColumnScores('1, 2, 3');select(emptySelection);changed();setFailed(false);setMessage('Help example: grief state by level of support · 66 observations.');}}>Load help example</button></div>
      <div className="tools"><button disabled={busy} onClick={()=>native('paste')}>Paste counts</button><button onClick={()=>native('copy',{text:table.state.counts.map(row=>row.join('\t')).join('\n')})}>Copy counts</button><button disabled={busy || !table.undoStack.length} onClick={()=>{table.undo();select(emptySelection);changed();}}>Undo</button><button disabled={busy || !table.redoStack.length} onClick={()=>{table.redo();select(emptySelection);changed();}}>Redo</button><button onClick={()=>native('save')}>Save table…</button></div>
      <div className="cell-editor"><label htmlFor="count">Row {selectedRow+1}, column {selectedCol+1}</label><input id="count" aria-label="Selected count" value={cellText} disabled={busy} onChange={e=>setCellText(e.target.value)} onBlur={editCell} onKeyDown={e=>{const movement=cellMovement(e);if(movement){e.preventDefault();e.stopPropagation();e.currentTarget.blur();selectAdjacentCell([selectedCol,selectedRow],movement,countCols,countRows,select,grid.current);}}}/></div>
      <div className="canvas" ref={container}><div className="grid-frame"><DataEditor ref={grid} provideEditor={arrowKeyEditor} trapFocus width={Math.min(size.width,40+145*countCols)} height={Math.min(280,35+32*countRows+(40+145*countCols>size.width?16:0))} columns={table.state.columnLabels.map(title=>({title,width:145}))} rows={countRows} getCellContent={cell} getCellsForSelection={true} rowMarkers="number" rowMarkerWidth={40} headerHeight={35} rowHeight={32} gridSelection={selection} onGridSelectionChange={select} onCellsEdited={items=>{if(busy)return false;table.change(s=>items.forEach(({location:[c,r],value})=>{if(value.kind===GridCellKind.Text)s.counts[r][c]=value.data;}));changed();return true;}} onPaste={(target,values)=>{if(!busy)attempt(()=>{table.pasteValues(target[0],target[1],values);changed();});return false;}} onDelete={s=>{if(!busy && s.current){const area=s.current.range;table.change(next=>{for(let r=area.y;r<area.y+area.height;r++)for(let c=area.x;c<area.x+area.width;c++)next.counts[r][c]='';});changed();}return false;}} smoothScrollX smoothScrollY /></div></div>
      <div className="table-foot"><span>Total entered <strong>{total.toLocaleString()}</strong></span><span>Enter 0 explicitly; blank cells cannot be analysed.</span></div>
      <details><summary>Category labels and row totals</summary><div className="labels"><div><h3>Rows</h3>{table.state.rowLabels.map((label,r)=><label key={r}>{r+1}<input aria-label={`Row ${r+1} label`} value={label} disabled={busy} onChange={e=>{table.change(s=>s.rowLabels[r]=e.target.value);changed();}}/><span>Σ {table.state.counts[r].reduce((a,v)=>a+(Number(v)||0),0)}</span></label>)}</div><div><h3>Columns</h3>{table.state.columnLabels.map((label,c)=><label key={c}>{c+1}<input aria-label={`Column ${c+1} label`} value={label} disabled={busy} onChange={e=>{table.change(s=>s.columnLabels[c]=e.target.value);changed();}}/><span>Σ {table.state.counts.reduce((a,row)=>a+(Number(row[c])||0),0)}</span></label>)}</div></div></details>
      <p className="hint">Paste a rectangle of counts from Excel or the data grid. Exclude headings and totals. Resizing and pasting can be undone. Prototype limit: 2,500 cells.</p>
    </section><aside><h2>Analysis options</h2><fieldset disabled={busy}>{options.map(option=><label className="check" key={option.name}><input type="checkbox" checked={flags[option.name]} onChange={e=>setFlags({...flags,[option.name]:e.target.checked})}/>{option.prompt}</label>)}
      <label className="field">Confidence level (%)<input type="number" min="0.01" max="99.99" step="any" value={confidence} onChange={e=>setConfidence(e.target.value)}/></label>
      {flags.specify_scores && <div className="suboptions"><label className="field">Row scores ({countRows})<input placeholder="1, 2, 3, …" value={rowScores} onChange={e=>setRowScores(e.target.value)}/></label><label className="field">Column scores ({countCols})<input placeholder="1, 2, 3, …" value={columnScores} onChange={e=>setColumnScores(e.target.value)}/></label><p className="hint">One score per category, separated by commas. Otherwise the engine uses 1, 2, 3, … in table order.</p></div>}
      {flags.doMonteCarlo && <div className="suboptions"><label className="field">Iterations<input type="number" min="1" max="10000000" value={iterations} onChange={e=>setIterations(e.target.value)}/></label><label className="field">Seed<input type="number" min="1" max="2147483647" value={seed} onChange={e=>setSeed(e.target.value)}/></label><label className="field">Simulation confidence (%)<input type="number" step="any" value={mcConfidence} onChange={e=>setMcConfidence(e.target.value)}/></label><p className="hint">The same seed reproduces a simulation. Up to 10 million iterations and 5 million observations.</p></div>}
    </fieldset><p className="hint">Trend and ordinal association use the category order. Exact testing is skipped by the engine above 100,000 observations.</p></aside></div>
    <footer><div role="status" aria-live="polite" className={failed?'error':''}>{message}{busy && <small>Cancel is checked at engine checkpoints. An exact-test step must finish before cancellation takes effect.</small>}</div><button disabled={!busy || cancelling} onClick={()=>{setCancelling(true);setMessage('Cancellation requested…');native('cancel');}}>Cancel calculation</button><button className="primary" disabled={busy} onClick={run}>{busy?'Calculating…':'Run analysis →'}</button></footer>
  </main>;
}
createRoot(document.getElementById('root')!).render(<App/>);
