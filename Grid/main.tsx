import React, { useCallback, useEffect, useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import DataEditor, { CompactSelection, GridCellKind, type GridCell, type GridSelection, type Item, type DataEditorRef } from '@glideapps/glide-data-grid';
import '@glideapps/glide-data-grid/dist/index.css';
import './style.css';
import { columnName, MAX_ROWS, MAX_COLS } from './store.mjs';
import { rDataTables } from './r-data.mjs';
import { csvWorkbook } from './csv.mjs';
import { WorkbookStore, cellKind } from './workbook.mjs';
import { selectAdjacentCell, cellMovement, arrowKeyEditor } from './navigation';
declare global {
  interface Window {
    webkit?: any;
    statsDirectGrid: any;
  }
}
const workbook = new WorkbookStore();
function native(action: string, extra: object = {}) {
  const bridge = window.webkit?.messageHandlers?.statsDirectGrid;
  if (bridge) bridge.postMessage({
    action,
    ...extra
  });
}
const empty: GridSelection = {
  columns: CompactSelection.empty(),
  rows: CompactSelection.empty()
};
function App() {
  const [sheetIndex, setSheetIndex] = useState(0);
  const store = workbook.sheets[sheetIndex].store;
  const [revision, refresh] = useState(0),
    [selection, setSelection] = useState<GridSelection>(empty),
    [widths, setWidths] = useState<Record<number, number>>({}),
    [message, setMessage] = useState('Ready'),
    [value, setValue] = useState('');
  const grid = useRef<DataEditorRef>(null),
    selectionRef = useRef(selection);
  selectionRef.current = selection;
  const [containerSize, setSize] = useState({
    width: 800,
    height: 400
  });
  const container = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const observer = new ResizeObserver(entries => {
      const {
        width,
        height
      } = entries[0].contentRect;
      setSize({
        width: Math.floor(width),
        height: Math.floor(height)
      });
    });
    if (container.current) observer.observe(container.current);
    return () => observer.disconnect();
  }, []);
  const changed = useCallback(() => {
    workbook.changed();
    refresh(n => n + 1);
    native('changed');
  }, []);
  const attempt = (fn: () => void) => {
    try {
      fn();
    } catch (error) {
      setMessage((error as Error).message);
    }
  };
  const getCell = useCallback(([c, r]: Item): GridCell => {
    const raw = store.get(c, r);
    const n = cellKind(store, c, r) === 'number' ? Number(raw) : NaN;
    const formula = !!store.metadata.get(`${c},${r}`)?.formula;
    return Number.isFinite(n) ? {
      kind: GridCellKind.Number,
      data: n,
      displayData: raw,
      allowOverlay: !formula,
      readonly: formula
    } : {
      kind: GridCellKind.Text,
      data: raw,
      displayData: raw,
      allowOverlay: !formula,
      readonly: formula
    };
  }, [store]);
  const range = () => {
    const s = selectionRef.current;
    if (s.current) return s.current.range;
    const cols = s.columns.toArray();
    return {
      x: cols[0] ?? 0,
      y: 0,
      width: cols.length || 1,
      height: Math.max(1, store.usedRows())
    };
  };
  const copy = () => {
    const s = selectionRef.current,
      area = range(),
      cols = s.columns.length ? s.columns.toArray() : s.rows.length ? store.columns.map((_, i) => i) : Array.from({
        length: area.width
      }, (_, i) => area.x + i),
      rows = s.rows.length ? s.rows.toArray() : Array.from({
        length: area.height
      }, (_, i) => area.y + i);
    if (rows.length * cols.length > 100000) throw new Error('Copy at most 100,000 cells at a time.');
    const quote = (v: string) => /[\t\n\r"]/.test(v) ? '"' + v.replaceAll('"', '""') + '"' : v;
    return rows.map(r => cols.map(c => quote(store.get(c, r))).join('\t')).join('\n');
  };
  const paste = (text: string) => {
    attempt(() => {
      const area = range();
      if (store.paste(area.x, area.y, text)) {
        changed();
        setMessage('Pasted data · Undo restores the previous cells');
      }
    });
  };
  useEffect(() => {
    window.statsDirectGrid = {
      editCommand: (command: string, clipboard: string) => {
        const focused = document.activeElement as HTMLElement | null;
        if (focused?.matches('input,textarea,select') || focused?.isContentEditable) return false;
        attempt(() => {
          switch (command) {
            case 'undo': if (store.undo()) changed(); break;
            case 'redo': if (store.redo()) changed(); break;
            case 'copy': native('copy', {text: copy()}); break;
            case 'cut': native('copy', {text: copy()}); clear(); break;
            case 'paste': paste(clipboard); break;
            case 'selectAll':
              setSelection({...empty, current: {cell: [0, 0], range: {x: 0, y: 0, width: store.columns.length, height: Math.max(1, store.usedRows())}, rangeStack: []}});
              break;
          }
        });
        return true;
      },
      analysisSource: () => {
        const cells = [...new Set([...store.cells.keys(), ...store.metadata.keys()])].map(key=>{const [col,row]=key.split(',').map(Number);return {...store.metadata.get(key),col,row,text:store.get(col,row)};});
        const usedRows = cells.filter(cell=>cell.text!=='').reduce((m,cell)=>Math.max(m,cell.row+1),store.headerRow?2:1);
        return {name:workbook.name+' / '+workbook.sheets[sheetIndex].name,columns:store.columns.map((_:string,c:number)=>store.columnTitle(c)),cells,firstRow:store.headerRow?2:1,rows:usedRows,formulasStale:store.formulasStale,selection:selection.columns.toArray()};
      },
      csvData: () => store.csv(),
      csvSnapshot: () => ({text: store.csv(), canSaveDocument: !workbook.backed && workbook.sheets.length === 1 && !workbook.formulaCount && !workbook.sheets.some((s:any) => s.rColumns)}),
      rDataSnapshot: (currentOnly: boolean) => ({tables: rDataTables(workbook, currentOnly ? sheetIndex : undefined), canSaveDocument: !workbook.backed && !workbook.formulaCount && (!currentOnly || workbook.sheets.length === 1)}),
      excelData: () => workbook.export(),
      loadWorkbook: (data: any) => {
        setSheetIndex(workbook.load(data));
        setSelection(empty);
        setMessage(`Opened ${data.name} · ${data.sheets.length} worksheet${data.sheets.length === 1 ? '' : 's'}${data.warnings?.length ? '. Not imported: ' + data.warnings.join('; ') : ''}`);
        refresh(n => n + 1);
      },
      loadCSV: (text: string, name: string) => {
        const data = csvWorkbook(text, name);
        window.statsDirectGrid.loadWorkbook(data);
        setMessage(`Opened ${name} · ${data.sheets[0].rows} rows × ${data.sheets[0].columns} columns`);
        return {rows: data.sheets[0].rows, columns: data.sheets[0].columns};
      },
      pasteText: paste,
      copyText: copy,
      undo: () => {
        if (store.undo()) changed();
      },
      redo: () => {
        if (store.redo()) changed();
      },
      setStatus: setMessage
    };
  });
  useEffect(() => {
    native('ready');
  }, []);
  useEffect(() => {
    const handler = (event: ClipboardEvent) => {
      if ((event.target as HTMLElement)?.matches('input,textarea')) return;
      const text = event.clipboardData?.getData('text/plain');
      if (text !== undefined) {
        event.preventDefault();
        event.stopImmediatePropagation();
        paste(text);
      }
    };
    document.addEventListener('paste', handler, true);
    return () => document.removeEventListener('paste', handler, true);
  });
  const current = selection.current?.cell;
  useEffect(() => {
    setValue(current ? store.get(current[0], current[1]) : '');
  }, [current?.[0], current?.[1], revision, store]);
  const clear = () => {
    const s = selectionRef.current,
      a = range(),
      cols = s.columns.length ? s.columns.toArray() : s.rows.length ? store.columns.map((_, i) => i) : Array.from({
        length: a.width
      }, (_, i) => a.x + i),
      rows = s.rows.length ? s.rows.toArray() : Array.from({
        length: a.height
      }, (_, i) => a.y + i);
    if (cols.length * rows.length > 100000) throw new Error('Clear at most 100,000 cells at a time.');
    if (store.apply(rows.flatMap(r => cols.map(c => [c, r, ''])))) changed();
  };
  return <main>
  <div className="tools">
   <button onClick={() => attempt(() => {
        if (store.undo()) changed();
      })} disabled={!store.undoStack.length}>Undo</button>
   <button onClick={() => attempt(() => {
        if (store.redo()) changed();
      })} disabled={!store.redoStack.length}>Redo</button>
   <button onClick={() => attempt(() => native('copy', {
        text: copy()
      }))}>Copy</button>
   <button onClick={() => native('paste')}>Paste</button>
   <button onClick={() => attempt(clear)}>Clear cells</button>
   <span className="spacer" />
   <button onClick={() => attempt(() => {
        store.apply([], Math.min(MAX_ROWS, store.rows + 100));
        changed();
      })}>+ 100 rows</button>
   <button onClick={() => attempt(() => {
        if (store.columns.length >= MAX_COLS) throw new Error('Column limit reached.');
        store.apply([], store.rows, store.columns.length + 1);
        changed();
      })}>+ Column</button>
  </div>
  {workbook.sheets.length > 1 && <div className="sheetbar" role="tablist" aria-label="Worksheets">{workbook.sheets.map((sheet: any, i: number) => <button key={sheet.name} role="tab" aria-selected={i === sheetIndex} onClick={() => {
        setSheetIndex(i);
        setSelection(empty);
        setWidths({});
        setMessage(sheet.name + (sheet.hidden ? " (hidden in Excel)" : ""));
      }}>{sheet.name}{sheet.hidden ? " (hidden)" : ""}</button>)}</div>}
  <div className="formula"><label htmlFor="cellValue">{current ? columnName(current[0]) + (current[1] + 1) : 'Cell'}</label><input id="cellValue" aria-label="Selected cell value" placeholder="Select a cell, then edit its value here or double-click the cell" disabled={!current || !!store.metadata.get(`${current[0]},${current[1]}`)?.formula} value={value} onChange={e => setValue(e.target.value)} onKeyDown={e => {
        const movement = cellMovement(e);
        if (movement && current) {
          e.preventDefault();
          e.stopPropagation();
          attempt(() => {
            if (store.apply([[current[0], current[1], value]])) changed();
            selectAdjacentCell(current, movement, store.columns.length, store.rows, setSelection, grid.current);
          });
        }
      }} /><span>{current && store.metadata.get(`${current[0]},${current[1]}`)?.formula ? "Formula: " + store.metadata.get(`${current[0]},${current[1]}`).formula : "↵ to save and move down"}</span></div>
  <div className="canvas" ref={container}><DataEditor ref={grid} provideEditor={arrowKeyEditor} trapFocus width={containerSize.width} height={containerSize.height} columns={store.columns.map((title: string, c: number) => ({
        id: String(c),
        title: store.headerRow ? columnName(c) + ' · ' + store.columnTitle(c) : columnName(c),
        width: widths[c] ?? 178
      }))} rows={store.rows} getCellContent={getCell} getCellsForSelection={true} rowMarkers="both" rowMarkerWidth={48} headerHeight={36} rowHeight={29} freezeColumns={0} smoothScrollX smoothScrollY gridSelection={selection} onGridSelectionChange={setSelection} onColumnResize={(_col, width, index) => setWidths(w => ({
        ...w,
        [index]: width
      }))} onCellsEdited={items => {
        attempt(() => {
          store.apply(items.map(({
            location: [c, r],
            value
          }) => [c, r, 'data' in value ? String(value.data ?? '') : '']));
          changed();
          setMessage('Cell edits applied');
        });
        return true;
      }} onPaste={(target, values) => {
        attempt(() => {
          store.apply(values.flatMap((row, y) => row.map((v, x) => [target[0] + x, target[1] + y, v])));
          changed();
        });
        return false;
      }} onDelete={() => {
        attempt(clear);
        return false;
      }} onRowAppended={() => {
        store.apply([], store.rows + 1);
        changed();
      }} trailingRowOptions={{
        hint: 'Add a row',
        sticky: true,
        tint: true
      }} theme={{
        accentColor: '#23695f',
        accentLight: '#e8f2ef',
        bgHeader: '#edf1f3',
        bgHeaderHasFocus: '#dbeae5',
        textDark: '#1b2c35',
        fontFamily: '-apple-system, BlinkMacSystemFont, sans-serif',
        baseFontStyle: '13px',
        headerFontStyle: '600 12px'
      }} /></div>
  <div className="worksheet-options"><label><input type="checkbox" checked={store.headerRow} onChange={e => {
          store.headerRow = e.target.checked;
          refresh(n => n + 1);
        }} />First row has column names</label><span>Choose a method from Analysis to analyse these data.</span></div>
  <footer><span role="status">{message}</span><span>{store.rows.toLocaleString()} rows × {store.columns.length} columns · {store.cells.size} filled cells</span></footer>
  {workbook.formulaCount > 0 && <p className="formula-note">{workbook.formulaCount} formula cells show results from the last Excel save and are read-only. Formulas are retained on export and recalculate in Excel. {workbook.edited ? "After editing, reopen the recalculated file before analysing formula cells." : ""}</p>}

 </main>;
}
createRoot(document.getElementById('root')!).render(<App />);
