import {test} from 'node:test';
import assert from 'node:assert/strict';
import {WorkbookStore} from './workbook.mjs';
import {rDataTables} from './r-data.mjs';
import {decodeSnapshot, encodeSnapshot} from './snapshot.mjs';
import {worksheetRImport} from './worksheet-r.mjs';

// The Excel loader gives serial 60 of the 1900 date system, the nonexistent 1900-02-29, as a datetime cell with that
// text ("1900-02-29 00:00:00" for a date). R cannot read the date, so Save as R data writes it as NA, as the worksheet
// R import does (rule 3.9), instead of failing with "Invalid POSIXct value".
function book(cells, headerRow = true) {
  const w = new WorkbookStore();
  w.load({name: 'Dates.xlsx', sheets: [{name: 'S', headerRow, columns: 4, rows: 10, cells}]});
  return w;
}
const at = (col, row, text, kind) => ({col, row, text, kind});
const sheet = () => book([
  at(0, 0, 'When', 'text'), at(0, 1, '1900-02-29 00:00:00', 'datetime'), at(0, 2, '2026-11-21 00:00:00', 'datetime'),
  at(1, 0, 'Day', 'text'), at(1, 1, '1900-02-29', 'datetime'), at(1, 2, '1900-03-01', 'datetime'),
  at(2, 0, 'Note', 'text'), at(2, 1, '1900-02-29 06:00:00', 'datetime'), at(2, 2, 'x', 'text'),
  at(3, 0, 'Typed', 'text'), at(3, 1, '1900-02-29', 'text'), at(3, 2, '1900-02-28', 'datetime')]);

test('Save as R data writes a datetime on 1900-02-29 as NA, in a date-time, a date or a character column', () => {
  const {tables, sheets} = rDataTables(sheet(), 0);
  // The day does not decide a column's type: the other cells do.
  assert.deepEqual(tables[0].columns.map(c => [c.name, c.type]), [['When', 'POSIXct'], ['Day', 'Date'], ['Note', 'character'], ['Typed', 'character']]);
  const [when, day, note, typed] = sheets[0].columns;
  for (const column of [when, day, note]) {
    // Missing: no kind and no text, and marked rMissing, so that a character column holds NA rather than "".
    assert.deepEqual([[...column.kinds], [...column.texts.keys()], [...column.extras]], [[0, column === note ? 2 : 3], [1], [[0, '{"rMissing":true}']]]);
  }
  assert.deepEqual([when.texts.get(1), day.texts.get(1), note.texts.get(1)], ['2026-11-21 00:00:00', '1900-03-01', 'x']);
  // Text that only reads 1900-02-29 is text, kept as it is; so is any other day.
  assert.deepEqual([[...typed.kinds], [...typed.texts], typed.extras.size], [[2, 3], [[0, '1900-02-29'], [1, '1900-02-28']], 0]);
  // The marker travels in the snapshot the application turns into R's exchange files.
  assert.deepEqual([...decodeSnapshot(encodeSnapshot(sheets)).sheets[0].columns[2].extras], [[0, '{"rMissing":true}']]);
});

test('the worksheet R import and Save as R data agree that 1900-02-29 is missing', () => {
  const imported = worksheetRImport(sheet(), 0, {}, 'entire', {headings: true});
  assert.deepEqual(imported.columns.slice(0, 3).map(c => c.values[0]), [null, null, null]);
  const {sheets} = rDataTables(sheet(), 0);
  assert.deepEqual(sheets[0].columns.slice(0, 3).map(c => c.extras.get(0)), Array(3).fill('{"rMissing":true}'));
});

test('a sheet without a heading row, and the R markers of other cells, are unchanged', () => {
  const plain = rDataTables(book([at(0, 0, '1900-02-29 00:00:00', 'datetime'), at(0, 1, '2026-11-21 00:00:00', 'datetime')], false), 0);
  assert.deepEqual([plain.tables[0].rows, plain.tables[0].columns[0].type, [...plain.sheets[0].columns[0].kinds], [...plain.sheets[0].columns[0].extras.keys()]],
    [2, 'POSIXct', [0, 3], [0]]);
  // A cell loaded from an R file keeps its own rMissing and rRaw markers.
  const loaded = book([at(0, 0, 'n', 'text'), {col: 0, row: 1, text: '', kind: 'blank', rMissing: true}, {col: 0, row: 2, text: '2026-11-21', kind: 'datetime', rRaw: '20778.5'}]);
  assert.deepEqual([...rDataTables(loaded, 0).sheets[0].columns[0].extras], [[0, '{"rMissing":true}'], [1, '{"rRaw":"20778.5"}']]);
});
