import {test} from 'node:test';
import assert from 'node:assert/strict';
import {WorkbookStore} from './workbook.mjs';
import {decodeSnapshot, encodeSnapshot} from './snapshot.mjs';
import {columnValues} from './analysis-source.mjs';
import {worksheetInput, worksheetInputFrom} from './operation-data.mjs';
import {rDataTables} from './r-data.mjs';
import {tutorData} from './tutor-data.mjs';

// A formula whose saved result is empty text (=IF(A2="","",A2*2)) is a blank cell everywhere a
// blank counts as missing. A formula with no saved result, or any formula once the workbook has
// been edited, is refused, each place with its own message (rules 3.2 and 7).
function book() {
  const w = new WorkbookStore();
  w.load({name: 'Formulas.xlsx', sheets: [{name: 'S', rows: 10, columns: 3, headerRow: true, cells: [
    {col: 0, row: 0, text: 'Before', kind: 'text'}, {col: 1, row: 0, text: 'After', kind: 'text'},
    ...[12, 15, 11, 14].map((v, i) => ({col: 0, row: i + 1, text: String(v), kind: 'number'})),
    ...[10, 13, 12].map((v, i) => ({col: 1, row: i + 1, text: String(v), kind: 'number'})),
    {col: 1, row: 4, text: '', kind: 'blank', formula: 'IF(A5>13,"",A5)', savedEmpty: true}]}]});
  return w;
}
const withoutResult = w => { w.sheets[0].store.setLoaded([{col: 1, row: 4, text: '', kind: 'blank', formula: 'IF(A5>13,"",A5)'}]); w.sheets[0].store.col(1).extra.delete(4); return w; };
const edited = w => { w.changed(); return w; };

test('store.formulaUnavailable: a saved empty result is available; a missing result or an edited workbook is not', () => {
  const s = book().sheets[0].store;
  s.setLoaded([{col: 2, row: 1, text: '7', kind: 'number', formula: 'A2-5'}]);
  assert.deepEqual([s.formulaUnavailable(1, 4), s.formulaUnavailable(2, 1), s.formulaUnavailable(0, 1), s.formulaUnavailable(2, 9)], [false, false, false, false]);
  const missing = withoutResult(book()).sheets[0].store;
  assert.equal(missing.formulaUnavailable(1, 4), true);
  s.formulasStale = true;
  assert.deepEqual([s.formulaUnavailable(1, 4), s.formulaUnavailable(2, 1), s.formulaUnavailable(0, 1)], [true, true, false]);
});

test('the loader flag travels in the snapshot extras (I1) and marks the cell as saved empty', () => {
  const snapshot = encodeSnapshot([{name: 'S', columns: [{col: 1, rows: [0, 1], kinds: [1, 0], nums: [3, NaN], texts: new Map(),
    formulas: new Map([[0, 'A1+2'], [1, 'IF(A2>1,"",A2)']]), extras: new Map([[1, '{"savedEmpty":true}']])},
  {col: 2, rows: [1], kinds: [0], nums: [NaN], texts: new Map(), formulas: new Map([[0, 'B9']])}]}]);
  const w = new WorkbookStore();
  w.load({name: 'Loaded.xlsx', sheets: [{name: 'S', rows: 10, columns: 3, headerRow: false, columnar: decodeSnapshot(snapshot).sheets[0].columns}]});
  const s = w.sheets[0].store;
  assert.deepEqual([s.get(1, 1), s.formula(1, 1), s.formulaUnavailable(1, 1), s.formulaUnavailable(2, 1)], ['', 'IF(A2>1,"",A2)', false, true]);
});

test('analyses read a saved empty result as a blank cell and count missing results as uncached', () => {
  const read = w => columnValues(w, 0, {columns: [0, 1], first: 2, last: 5});
  const data = read(book());
  assert.deepEqual([data.uncached, data.columns[1].values, data.columns[1].kinds], [0, ['10', '13', '12', ''], ['number', 'number', 'number', 'blank']]);
  assert.equal(read(withoutResult(book())).uncached, 1);
  assert.equal(read(edited(book())).uncached, 1);
  const pending = {request: {sheet: 0, sheetName: 'S', columns: [0, 1], first: 2, last: 5}, workbook: 'Formulas.xlsx', source: 'S'};
  assert.equal(worksheetInputFrom(pending, data).columns[1].values[3], '');
  assert.throws(() => worksheetInputFrom(pending, read(withoutResult(book()))), {message: 'Recalculate and save this workbook in Excel, then reopen it before analysing formula cells.'});
  // A snapshot of copied cells follows the same rule.
  const source = {name: 'S', firstRow: 2, rows: 5, columns: ['Before', 'After'], cells: [{col: 1, row: 1, text: '10'}, {col: 1, row: 4, text: '', formula: 'IF(A5>13,"",A5)', savedEmpty: true}]};
  assert.deepEqual(worksheetInput(source, [1], 2, 5).columns[0].values, ['10', '', '', '']);
  assert.throws(() => worksheetInput({...source, cells: [{col: 1, row: 4, text: '', formula: 'IF(A5>13,"",A5)'}]}, [1], 2, 5), /Recalculate/);
  assert.throws(() => worksheetInput({...source, formulasStale: true}, [1], 2, 5), /Recalculate/);
});

test('the paired analysis takes a saved empty result as missing and keeps its two messages', () => {
  const paired = book().sheets[0].store.paired(0, 1);
  assert.deepEqual([paired.before, paired.after], [[12, 15, 11, 14], [10, 13, 12, null]]);
  assert.throws(() => withoutResult(book()).sheets[0].store.paired(0, 1), /A formula has no saved result/);
  assert.throws(() => edited(book()).sheets[0].store.paired(0, 1), /formula results that may be out of date/);
  const both = edited(withoutResult(book()));
  assert.throws(() => both.sheets[0].store.paired(0, 1), /A formula has no saved result/);
});

test('R data files and the tutor take a saved empty result as blank and refuse missing results', () => {
  const tables = rDataTables(book(), 0);
  assert.equal(tables.sheets[0].columns[1].kinds[3], 0);
  assert.throws(() => rDataTables(withoutResult(book()), 0), {message: 'Recalculate formula results in Excel before saving this table as R data.'});
  assert.throws(() => rDataTables(edited(book()), 0), /Recalculate formula results/);
  const tutor = tutorData(book(), 0, {columns: [0, 1]});
  assert.deepEqual([tutor.hasStaleFormulas, tutor.columns[1].values], [false, ['10', '13', '12', null]]);
  assert.equal(tutorData(withoutResult(book()), 0, {columns: [0, 1]}).hasStaleFormulas, true);
  assert.equal(tutorData(edited(book()), 0, {columns: [0, 1]}).hasStaleFormulas, true);
});
