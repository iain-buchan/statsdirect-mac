// The grid's part of the worksheet R examples (Tests/test_worksheet_r_examples.py):
//   node Tests/worksheet-r-examples.mjs plan.json runs.json
//
// Each case's workbook has been opened by the engine's own loader, which wrote the typed snapshot the app's grid reads.
// This loads the snapshot into a WorkbookStore as the grid's loadWorkbook does (Grid/main.tsx), types the cells a Mac case
// types (store.apply, then workbook.changed(), as the grid does for each edit), makes the case's selection as Glide and
// main.tsx hand it to worksheetRImport, and calls the grid's own worksheetRImport: once for the prompt's preview, and once
// for the data of the choice the case names, with headings = options.headings ?? that choice's suggestHeadings. Select
// all runs in each form the Mac has.
import fs from 'node:fs';
import {decodeSnapshot} from '../Grid/snapshot.mjs';
import {MAX_ROWS} from '../Grid/store.mjs';
import {WorkbookStore} from '../Grid/workbook.mjs';
import {worksheetRImport} from '../Grid/worksheet-r.mjs';

const [planPath, runsPath] = process.argv.slice(2);
if (!planPath || !runsPath) { console.error('Usage: node Tests/worksheet-r-examples.mjs plan.json runs.json'); process.exit(2); }
const plan = JSON.parse(fs.readFileSync(planPath, 'utf8'));

// A1 references, zero-based: NA1 is column 364, row 0.
const columnIndex = letters => [...letters].reduce((n, ch) => n * 26 + ch.charCodeAt(0) - 64, 0) - 1;
function cellAt(ref) {
  const match = /^([A-Z]{1,3})([1-9][0-9]*)$/.exec(ref);
  if (!match) throw new Error(`Not a cell reference: ${ref}`);
  return [columnIndex(match[1]), Number(match[2]) - 1];
}
function rectangle(text) {
  const [from, to = from] = text.split(':'), [x1, y1] = cellAt(from), [x2, y2] = cellAt(to);
  return {x: Math.min(x1, x2), y: Math.min(y1, y2), width: Math.abs(x2 - x1) + 1, height: Math.abs(y2 - y1) + 1};
}
const span = (from, to) => Array.from({length: to - from + 1}, (_, i) => from + i);
const rowSpan = text => { const [from, to = from] = text.split(':').map(Number); return span(from - 1, to - 1); };

// What main.tsx passes for Glide's GridSelection: CompactSelection.toArray() of the columns and rows (ascending, each once),
// current.range and current.rangeStack (a Command-click pushes the range before it), and whether it is Edit ▸ Select All's.
const sorted = list => [...new Set(list)].sort((a, b) => a - b);
const selection = ({columns = [], rows = [], current, all = false} = {}) =>
  ({columns: sorted(columns), rows: sorted(rows), range: current?.range, ranges: current?.rangeStack ?? [], all});
const SELECT_ALL = ['the corner', 'Command-A', 'Edit > Select All', 'every column'];
// The selections a case's select gives: one, labelled '', or select all in each of its Mac forms.
function selectionFor(select, store, form) {
  if (select.entire || select.none) return selection();
  if (select.range) return selection({current: {range: rectangle(select.range), rangeStack: []}});
  if (select.areas) {
    const areas = select.areas.map(rectangle);
    return selection({current: {range: areas.at(-1), rangeStack: areas.slice(0, -1)}});
  }
  if (select.columns) return selection({columns: select.columns.map(columnIndex)});
  if (select.rows) return selection({rows: select.rows.flatMap(rowSpan)});
  if (select.all) switch (form) {
    case 'the corner': return selection({rows: span(0, store.rows - 1)});   // Glide selects every grid row
    case 'Command-A': return selection({current: {range: {x: 0, y: 0, width: store.columns.length, height: store.rows}, rangeStack: []}});
    case 'Edit > Select All':   // as main.tsx's editCommand('selectAll') makes it, marked while it lasts
      return selection({current: {range: {x: 0, y: 0, width: store.columns.length, height: Math.max(1, store.usedRows())}, rangeStack: []}, all: true});
    case 'every column': return selection({columns: span(0, store.columns.length - 1)});
  }
  throw new Error(`A selection this test cannot make: ${JSON.stringify(select)}`);
}

// The Mac grid ends at its own size (RULES.md section 7): a workbook opens with the columns its file uses, and at least
// 100 rows, so a selection beyond them can be made only once the grid has grown. The grid's own Add column and Add 100
// rows commands (main.tsx) grow it, as a user would, until the selection fits with a column and a row to spare, so that it
// stays the case's selection and does not become every grid column or row, which the Mac takes as select all (rule 2.6).
// Returns what was added, for the run's label.
function makeRoom(select, workbook, store) {
  const areas = select.range ? [rectangle(select.range)] : select.areas ? select.areas.map(rectangle) : [];
  const right = Math.max(-1, ...areas.map(a => a.x + a.width - 1), ...(select.columns ?? []).map(columnIndex));
  const bottom = Math.max(-1, ...areas.map(a => a.y + a.height - 1), ...(select.rows ?? []).map(text => Math.max(...text.split(':').map(Number)) - 1));
  const added = [];
  if (right >= store.columns.length) {
    let n = 0;
    while (store.columns.length < right + 2) { store.apply([], store.rows, store.columns.length + 1); workbook.changed(); n++; }
    added.push(`Add column ×${n}`);
  }
  if (bottom >= store.rows) {
    let n = 0;
    while (store.rows < bottom + 2) { store.apply([], Math.min(MAX_ROWS, store.rows + 100)); workbook.changed(); n++; }
    added.push(`Add 100 rows ×${n}`);
  }
  return added.length ? `the grid grown by ${added.join(' and ')}` : '';
}

// As loadWorkbook: each sheet's snapshot becomes its columnar cells, and the workbook loads the engine's reply.
function open(reply) {
  const data = structuredClone(reply);
  for (const sheet of data.sheets) {
    if (typeof sheet.snapshot !== 'string') continue;
    sheet.columnar = decodeSnapshot(fs.readFileSync(sheet.snapshot)).sheets[0]?.columns ?? [];
    delete sheet.snapshot;
  }
  const workbook = new WorkbookStore(), sheetIndex = workbook.load(data);
  return {workbook, sheetIndex};
}

const runs = [];
for (const c of plan.cases) {
  for (const form of c.select.all ? SELECT_ALL : ['']) {
    const run = {id: `${c.id}/${runs.length}`, case: c.id, form, scope: c.select.entire ? 'entire' : 'selected', options: c.options, external: false};
    runs.push(run);
    try {
      const {workbook, sheetIndex} = open(c.reply), store = workbook.sheets[sheetIndex].store;
      // One edit at a time, as onCellsEdited applies a typed cell; apply() widens the grid to a cell beyond it, as Add
      // column would first have had to.
      for (const {ref, text} of c.typed) {
        store.apply([[...cellAt(ref), text]]);
        workbook.changed();
      }
      const grown = makeRoom(c.select, workbook, store);
      if (grown) run.form = form ? `${form}, ${grown}` : grown;
      const chosen = selectionFor(c.select, store, form);
      run.preview = worksheetRImport(workbook, sheetIndex, chosen);
      const option = run.preview[run.scope];
      run.headings = (c.options.headings ?? option?.suggestHeadings ?? false) === true;
      if (!option || c.labelsOnly) continue;
      try { run.data = worksheetRImport(workbook, sheetIndex, chosen, run.scope, {headings: run.headings}); }
      catch (error) { run.error = error.message; }
    } catch (error) {
      run.previewError = error.stack ?? String(error);
    }
  }
}
fs.writeFileSync(runsPath, JSON.stringify({runs}));
console.log(`grid: ${runs.length} runs of ${plan.cases.length} cases through worksheetRImport`);
