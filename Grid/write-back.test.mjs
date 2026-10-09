import test from 'node:test';
import assert from 'node:assert/strict';
import {GridStore, MAX_COLS} from './store.mjs';
import {planWriteBack} from './write-back.mjs';

function sheet(header = true) {
  const s = new GridStore();
  s.excelRows = true; s.headerRow = header;
  const cells = [];
  const cols = [['dose', '1', '2', '4'], ['weight', '5', '6', '7'], ['note', 'a', '', 'c']];
  cols.forEach((values, col) => values.forEach((text, row) => { if (!header && row === 0) return; if (text !== '') cells.push({col, row: header ? row : row - 1, text, kind: row ? (col === 2 ? 'text' : 'number') : 'text'}); }));
  s.setLoaded(cells); s.growColumns(3);
  return s;
}
const frame = (title, values, extra = {}) => ({name: 'Out', columns: 1, rows: values.length + 1, headerRow: true, lengths: [values.length], missingIndicator: '*', keepSelection: false,
  cells: [{col: 0, row: 0, text: title}, ...values.map((v, i) => ({col: 0, row: i + 1, text: v})).filter(c => c.text !== null)], ...extra});
const text = (s, c, r) => s.get(c, r);
const apply = (s, plan) => s.apply(plan.edits, Math.max(s.rows, plan.rows), Math.max(s.columns.length, plan.cols), plan.inserts);

test('after the last used column: title in the title row, values aligned to the analysis rows, missing as *', () => {
  const s = sheet();
  const plan = planWriteBack(s, [frame('log', ['0', null, '1.386'])], 'LastColumn', {firstRow: 2, lastRow: 4, columns: [0]});
  assert.deepEqual(plan.written, [{x: 3, y: 0, width: 1, height: 4}]);
  assert.match(plan.message, /after the last used column/);
  apply(s, plan);
  assert.equal(text(s, 3, 0), 'log'); assert.equal(text(s, 3, 1), '0'); assert.equal(text(s, 3, 2), '*'); assert.equal(text(s, 3, 3), '1.386');
  assert.equal(s.columnTitle(3), 'log');
  s.undo(); assert.equal(text(s, 3, 0), ''); assert.equal(s.usedColumns().length, 3);
});
test('after the selected columns inserts and moves the columns to the right along, in one undo step', () => {
  const s = sheet();
  const plan = planWriteBack(s, [frame('log', ['0', '0.693', '1.386'])], 'AfterSelection', {firstRow: 2, lastRow: 4, columns: [0]});
  assert.deepEqual(plan.written, [{x: 1, y: 0, width: 1, height: 4}]);
  apply(s, plan);
  assert.deepEqual([0, 1, 2, 3].map(c => text(s, c, 0)), ['dose', 'log', 'weight', 'note']);
  assert.deepEqual([0, 1, 2, 3].map(c => text(s, c, 2)), ['2', '0.693', '6', '']);
  assert.equal(text(s, 3, 3), 'c');
  s.undo(); assert.deepEqual([0, 1, 2, 3].map(c => text(s, c, 0)), ['dose', 'weight', 'note', '']);
});
test('before the selected columns and as the first columns insert; in place of the selection clears first', () => {
  let s = sheet();
  apply(s, planWriteBack(s, [frame('log', ['0', '0.693', '1.386'])], 'BeforeSelection', {firstRow: 2, lastRow: 4, columns: [1, 2]}));
  assert.deepEqual([0, 1, 2, 3].map(c => text(s, c, 0)), ['dose', 'log', 'weight', 'note']);
  s = sheet();
  apply(s, planWriteBack(s, [frame('log', ['0', '0.693', '1.386'])], 'FirstColumn', {firstRow: 2, lastRow: 4, columns: [1]}));
  assert.deepEqual([0, 1, 2, 3].map(c => text(s, c, 0)), ['log', 'dose', 'weight', 'note']);
  s = sheet();
  const plan = planWriteBack(s, [frame('log', ['0', '0.693'])], 'ReplaceSelection', {firstRow: 2, lastRow: 3, columns: [1]});
  apply(s, plan);
  assert.deepEqual([0, 1, 2].map(c => text(s, c, 0)), ['dose', 'log', 'note']);
  assert.deepEqual([1, 2, 3].map(r => text(s, 1, r)), ['0', '0.693', '']);   // the whole column was cleared, not only the analysis rows
});
test('two frames: the second goes after the first, as Windows keeps the written selection', () => {
  const s = sheet();
  const plan = planWriteBack(s, [frame('a', ['1', '2', '3']), frame('b', ['4', '5', '6'])], 'AfterSelection', {firstRow: 2, lastRow: 4, columns: [0]});
  assert.deepEqual(plan.written.map(w => w.x), [1, 2]);
  apply(s, plan);
  assert.deepEqual([0, 1, 2, 3, 4].map(c => text(s, c, 0)), ['dose', 'a', 'b', 'weight', 'note']);
});
test('a sheet without a title row takes values only, from the first row; unequal lengths stay jagged', () => {
  const s = sheet(false);
  const plan = planWriteBack(s, [{...frame('x', ['1', '2']), columns: 2, lengths: [2, 1], cells: [{col: 0, row: 0, text: 'x'}, {col: 1, row: 0, text: 'y'}, {col: 0, row: 1, text: '1'}, {col: 0, row: 2, text: '2'}, {col: 1, row: 1, text: '9'}]}], 'AfterSelection', null);
  assert.match(plan.message, /no columns were selected/);
  apply(s, plan);
  assert.deepEqual([0, 1, 2].map(r => text(s, 3, r)), ['1', '2', '']);
  assert.deepEqual([0, 1].map(r => text(s, 4, r)), ['9', '']);
});
test('moving formulas and large workbooks is allowed; replacement of formulas and overflowing insertions are refused', () => {
  const f = sheet(); f.cols[2].formula.set(1, 'A2*2');
  assert.doesNotThrow(() => planWriteBack(f, [frame('a', ['1'])], 'BeforeSelection', {firstRow: 2, lastRow: 2, columns: [0]}));
  assert.throws(() => planWriteBack(f, [frame('a', ['1'])], 'ReplaceSelection', {firstRow: 2, lastRow: 2, columns: [2]}), /formulas/);
  assert.doesNotThrow(() => planWriteBack(sheet(), [frame('a', ['1'])], 'AfterSelection', {firstRow: 2, lastRow: 2, columns: [0]}, {cells: 1000001}));
  assert.doesNotThrow(() => planWriteBack(sheet(), [frame('a', ['1'])], 'LastColumn', {firstRow: 2, lastRow: 2, columns: [0]}, {cells: 1000001}));
  // Formula cells to the left of the insertion stay put; the Excel save re-references them.
  const left = sheet(); left.cols[0].formula.set(1, 'B2*2');
  assert.doesNotThrow(() => planWriteBack(left, [frame('a', ['1'])], 'AfterSelection', {firstRow: 2, lastRow: 2, columns: [0]}));
  assert.throws(() => planWriteBack(sheet(), [frame('a', ['1'])], 'Sideways', null), /Unknown write position/);
  const full = sheet(); full.setLoaded([{col: MAX_COLS - 1, row: 1, text: '1', kind: 'number'}]);
  assert.throws(() => planWriteBack(full, [frame('a', ['1'])], 'LastColumn', null), /No room/);
});
test('moved and written cells keep their kinds, whatever was loaded where they land', () => {
  const s = sheet();   // dose and weight numbers, note text
  s.setLoaded([{col: 2, row: 1, text: '2024-01-01', kind: 'datetime'}, {col: 1, row: 2, text: '007', kind: 'text'}]);
  apply(s, planWriteBack(s, [frame('log', ['0', '0.693', '1.386'])], 'FirstColumn', {firstRow: 2, lastRow: 4, columns: [0]}));
  assert.deepEqual([1, 2, 3].map(c => s.kind(c, 1)), ['number', 'number', 'datetime']);   // dose, weight, note moved right with their kinds
  assert.equal(s.kind(2, 2), 'text'); assert.equal(text(s, 2, 2), '007');
  assert.equal(s.kind(0, 1), 'number'); assert.equal(text(s, 0, 3), '1.386');
  const t = sheet();   // numbers written over loaded text stay numbers
  apply(t, planWriteBack(t, [{...frame('log', ['0', '0.693']), cells: [{col: 0, row: 0, text: 'log', kind: 'text'}, {col: 0, row: 1, text: '0', kind: 'number'}, {col: 0, row: 2, text: '0.693', kind: 'number'}]}], 'ReplaceSelection', {firstRow: 2, lastRow: 3, columns: [2]}));
  assert.deepEqual([1, 2].map(r => t.kind(2, r)), ['number', 'number']);
});
test('later frames follow their own step, never the chosen placement, so a replace does not overwrite the frame before', () => {
  const s = sheet();
  const plan = planWriteBack(s, [{...frame('fits', ['1', '2', '3']), placement: 'AfterSelection'}, {...frame('se', ['4', '5', '6']), placement: 'AfterSelection'}], 'ReplaceSelection', {firstRow: 2, lastRow: 4, columns: [0]});
  assert.deepEqual(plan.written.map(w => w.x), [0, 1]);
  apply(s, plan);
  assert.deepEqual([0, 1, 2, 3].map(c => text(s, c, 0)), ['fits', 'se', 'weight', 'note']);
});
test('a column holding only formulas counts as used; the first column needs no selection; empty output and no range do not fail', () => {
  const f = sheet(); f.cols[3] ??= f.col(3); f.cols[3].formula.set(1, 'A2*2');
  assert.equal(planWriteBack(f, [frame('a', ['1'])], 'LastColumn', null).written[0].x, 4);
  const s = sheet();
  const plan = planWriteBack(s, [frame('a', ['9'])], 'FirstColumn', null);
  assert.equal(plan.written[0].x, 0); assert.doesNotMatch(plan.message, /no columns were selected/);
  const none = planWriteBack(sheet(), [{name: 'Out', columns: 2, rows: 1, lengths: [0, 0], cells: [{col: 0, row: 0, text: 'a'}, {col: 1, row: 0, text: 'b'}]}], 'LastColumn', null);
  assert.equal(none.written.length, 1); assert.equal(none.edits.length, 2);
  const blank = planWriteBack(sheet(), [{name: 'Out', columns: 0, rows: 1, cells: []}], 'LastColumn', null);
  assert.equal(blank.edits.length, 0); assert.match(blank.message, /No columns were written/);
});
test('values align to analysis rows that start lower down; an untitled frame starts in the title row as on Windows', () => {
  const s = sheet();
  apply(s, planWriteBack(s, [frame('log', ['7', '8'])], 'LastColumn', {firstRow: 3, lastRow: 4, columns: [0]}));
  assert.deepEqual([0, 1, 2, 3].map(r => text(s, 3, r)), ['log', '', '7', '8']);
  const u = sheet();
  apply(u, planWriteBack(u, [{name: 'Out', columns: 1, rows: 3, lengths: [2], cells: [{col: 0, row: 1, text: 'p'}, {col: 0, row: 2, text: 'q'}]}], 'LastColumn', null));
  assert.deepEqual([0, 1, 2].map(r => text(u, 3, r)), ['p', 'q', '']);
});
test('an insertion is recorded for the Excel save and leaves with undo', () => {
  const s = sheet();
  const plan = planWriteBack(s, [frame('log', ['0', '0.693', '1.386'])], 'AfterSelection', {firstRow: 2, lastRow: 4, columns: [0]});
  assert.deepEqual(plan.inserts, [{col: 1, count: 1}]);
  assert.equal(s.apply(plan.edits, Math.max(s.rows, plan.rows), Math.max(s.columns.length, plan.cols), plan.inserts), true);
  assert.deepEqual(s.inserts, [{col: 1, count: 1}]);
  const again = planWriteBack(s, [frame('sq', ['1', '4', '16'])], 'LastColumn', {firstRow: 2, lastRow: 4, columns: [0]});
  assert.deepEqual(again.inserts, []);   // nothing moves for a write after the last column
  s.undo(); assert.deepEqual(s.inserts, []); s.redo(); assert.deepEqual(s.inserts, [{col: 1, count: 1}]);
});

test('structural moves preserve formula metadata, widths and loaded origins without copying values', () => {
  const s = sheet(); s.cols[2].formula.set(1, 'A2*2'); s.cols[2].displayWidth = 245;
  s.apply([[1,1,'9']]); // an edit made before insertion must move with its source
  const originalColumn = s.cols[2], p = planWriteBack(s,[frame('new',['10'])],'FirstColumn',null);
  assert.equal(p.edits.length,2); // title + result, no move/clear for any original cell
  apply(s,p);
  assert.equal(s.cols[3],originalColumn); assert.equal(s.formula(3,1),'A2*2'); assert.equal(s.cols[3].displayWidth,245);
  assert.equal(s.loaded(2,1).text,'5'); assert.equal(s.get(2,1),'9');
  s.undo(); assert.equal(s.cols[2],originalColumn); assert.equal(s.loaded(1,1).text,'5');
  s.redo(); assert.equal(s.cols[3],originalColumn); s.undo(); s.undo(); assert.equal(s.get(1,1),'5');
});
test('planning and an invalid edit after an insertion leave data and history untouched', () => {
  const s=sheet(); s.cols[1].formula.set(1,'A2*2');
  const before=JSON.stringify({csv:s.csv(),origins:[...s.originals],cols:s.cols.length,version:s.version});
  assert.throws(()=>s.apply([[2,1,'99']],100,4,[{col:0,count:1}]),/Formula cells/);
  assert.equal(JSON.stringify({csv:s.csv(),origins:[...s.originals],cols:s.cols.length,version:s.version}),before);
  assert.equal(s.canUndo,false);
});
test('file-backed insertions also move blank formatted columns beyond the last value', () => {
  const s=sheet(); const p=planWriteBack(s,[frame('new',['1'])],'AfterSelection',{columns:[2]},{backed:true});
  assert.deepEqual(p.inserts,[{col:3,count:1}]);
});
test('one million rows move by column identity with a small undo record', () => {
  const s=new GridStore();
  const rows=Uint32Array.from({length:1000001},(_,i)=>i),nums=new Float64Array(rows.length).fill(2);
  s.setLoadedBatches([{col:1,rows,nums,texts:new Map()}],()=> 'number');
  const before=s.cols[1];
  apply(s,planWriteBack(s,[frame('new',['7'])],'FirstColumn',null));
  assert.equal(s.cols[2],before); assert.equal(s.get(2,1000000),'2'); assert.ok(s.undoBytes<1024);
  s.undo(); assert.equal(s.cols[1],before); assert.equal(s.get(1,1000000),'2');
});


test('replacement at Excel width does not require room for an insertion', () => {
  const s=sheet(); s.setLoaded([{col:MAX_COLS-1,row:1,text:'2',kind:'number'}]);
  apply(s,planWriteBack(s,[frame('new',['7'])],'ReplaceSelection',{columns:[0]}));
  assert.equal(s.get(0,1),'7'); assert.equal(s.get(MAX_COLS-1,1),'2'); assert.deepEqual(s.inserts,[]);
});
