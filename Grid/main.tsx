import React, { useCallback, useEffect, useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import DataEditor, { CompactSelection, GridCellKind, type GridCell, type GridSelection, type Item, type DataEditorRef } from '@glideapps/glide-data-grid';
import '@glideapps/glide-data-grid/dist/index.css';
import './style.css';
import { columnName, MAX_ROWS, MAX_COLS } from './store.mjs';
import { WorkbookStore, cellKind } from './workbook.mjs';
import example from '../Content/paired-example.json';
declare global {
  interface Window {
    webkit?: any;
    statsDirectGrid: any;
  }
}
const workbook = new WorkbookStore(example);
function native(action: string, extra: object = {}) {
  const bridge = window.webkit?.messageHandlers?.statsDirectGrid;
  if (bridge) bridge.postMessage({
    action,
    ...extra
  });else if (action === 'run') alert('Run this worksheet inside StatsDirect to calculate a report.');
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
    [message, setMessage] = useState('Ready · Double-click a cell to edit'),
    [first, setFirst] = useState(0),
    [second, setSecond] = useState(1),
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
  const paired = () => {
    const s = selectionRef.current,
      cols = s.columns.toArray(),
      area = s.current?.range;
    const result = cols.length === 2 ? store.paired(cols[0], cols[1]) : area?.width === 2 ? store.paired(area.x, area.x + 1, area.y, area.y + area.height) : store.paired(first, second);
    result.range = workbook.name + ' / ' + workbook.sheets[sheetIndex].name + ' · ' + result.range;
    return result;
  };
  useEffect(() => {
    window.statsDirectGrid = {
      pairedData: () => {
        try {
          return paired();
        } catch (e) {
          return {
            error: (e as Error).message
          };
        }
      },
      csvData: () => store.csv(),
      excelData: () => workbook.export(),
      loadWorkbook: (data: any) => {
        setSheetIndex(workbook.load(data));
        setSelection(empty);
        setFirst(0);
        setSecond(data.sheets[0]?.columns > 1 ? 1 : 0);
        setMessage(`Opened ${data.name} · ${data.sheets.length} worksheets`);
        refresh(n => n + 1);
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
  <header><div><span className="eyebrow">WORKSHEET</span><h1>{workbook.name}</h1></div><span className="badge">Glide Data Grid</span></header>
  <div className="tools">
   <button onClick={() => native('openExcel')}>Open Excel…</button>
   <button onClick={() => native('openExample')}>Open test.xlsx</button>
   <button onClick={() => attempt(() => {
        if (store.undo()) changed();
      })} disabled={!store.undoStack.length}>Undo</button>
   <button onClick={() => attempt(() => {
        if (store.redo()) changed();
      })} disabled={!store.redoStack.length}>Redo</button>
   <button onClick={() => attempt(() => native('copy', {
        text: copy()
      }))}>Copy selection</button>
   <button onClick={() => native('paste')}>Paste from clipboard</button>
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
   <button onClick={() => native('save')}>Export CSV…</button>
   <button onClick={() => native('saveExcel')}>Save Excel…</button>
  </div>
  {workbook.imported && <div className="sheetbar" role="tablist" aria-label="Worksheets">{workbook.sheets.map((sheet: any, i: number) => <button key={sheet.name} role="tab" aria-selected={i === sheetIndex} onClick={() => {
        setSheetIndex(i);
        setSelection(empty);
        setFirst(0);
        setSecond(sheet.store.columns.length > 1 ? 1 : 0);
        setWidths({});
        setMessage(sheet.name + (sheet.hidden ? " (hidden in Excel)" : ""));
      }}>{sheet.name}{sheet.hidden ? " (hidden)" : ""}</button>)}</div>}
  <div className="formula"><label htmlFor="cellValue">{current ? columnName(current[0]) + (current[1] + 1) : 'Cell'}</label><input id="cellValue" aria-label="Selected cell value" placeholder="Select a cell, then edit its value here or double-click the cell" disabled={!current || !!store.metadata.get(`${current[0]},${current[1]}`)?.formula} value={value} onChange={e => setValue(e.target.value)} onKeyDown={e => {
        if (e.key === 'Enter' && current) {
          store.apply([[current[0], current[1], value]]);
          changed();
          grid.current?.focus();
        }
      }} /><span>{current && store.metadata.get(`${current[0]},${current[1]}`)?.formula ? "Formula: " + store.metadata.get(`${current[0]},${current[1]}`).formula : "↵ to apply"}</span></div>
  <div className="canvas" ref={container}><DataEditor ref={grid} width={containerSize.width} height={containerSize.height} columns={store.columns.map((title: string, c: number) => ({
        id: String(c),
        title: columnName(c) + ' · ' + store.columnTitle(c),
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
  <div className="analysis">{workbook.imported && <label><input type="checkbox" checked={store.headerRow} onChange={e => {
          store.headerRow = e.target.checked;
          refresh(n => n + 1);
        }} />First row has column names</label>}<strong>Paired t test</strong><label>First column <select aria-label="First paired column" value={first} onChange={e => setFirst(Number(e.target.value))}>{store.columns.map((name: string, i: number) => <option value={i} key={i}>{columnName(i)} · {store.columnTitle(i)}</option>)}</select></label><span>−</span><label>Second column <select aria-label="Second paired column" value={second} onChange={e => setSecond(Number(e.target.value))}>{store.columns.map((name: string, i: number) => <option value={i} key={i}>{columnName(i)} · {store.columnTitle(i)}</option>)}</select></label><button className="primary" onClick={() => attempt(() => {
        paired();
        native('run');
      })}>Run paired t test</button></div>
  <footer><span role="status">{message}</span><span>{store.rows.toLocaleString()} rows × {store.columns.length} columns · {store.cells.size} filled cells</span></footer>
  {workbook.formulaCount > 0 && <p className="formula-note">{workbook.formulaCount} formula cells show results from the last Excel save and are read-only. Formulas are retained on export and recalculate in Excel. {workbook.edited ? "After editing, reopen the recalculated file before analysing formula cells." : ""}</p>}
  <p className="hint">Select two column headers or a two-column range to analyse that selection. Otherwise the chosen columns above are used. Blank cells are missing values. Save Excel keeps all worksheets; CSV exports the current sheet.</p>
 </main>;
}
createRoot(document.getElementById('root')!).render(<App />);
