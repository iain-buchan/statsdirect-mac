import {test} from 'node:test';
import assert from 'node:assert/strict';
import {WorkbookStore} from './workbook.mjs';
import {columnName} from './store.mjs';
import {worksheetRImport, rNumber, numberValue, trimSpace} from './worksheet-r.mjs';

// The shared rules ("Worksheet data sent to R", statisticalhelp): rule numbers refer to them.
function workbook(cells, {headerRow = false, columns = 8, rows = 100, name = 'Measurements'} = {}) {
  const book = new WorkbookStore();
  book.load({name: 'Selected.xlsx', sheets: [{name, headerRow, columns, rows, cells}]});
  return book;
}
const cell = (col, row, text, kind = 'number', extra = {}) => ({col, row, text, kind, ...extra});
// Columns of values from row 1: a number is a number cell, a string a text cell, null a blank cell,
// and an object {text, kind, ...} is taken as given.
const value = v => typeof v === 'number' ? {text: Object.is(v, -0) ? '-0' : String(v), kind: 'number'} : typeof v === 'string' ? {text: v, kind: 'text'} : v;
function sheet(columns, options) {
  const cells = [];
  columns.forEach((values, c) => values.forEach((v, r) => { if (v !== null) cells.push({col: c, row: r, ...value(v)}); }));
  return workbook(cells, options);
}
const entire = (columns, options = {}) => worksheetRImport(sheet(columns), 0, {}, 'entire', options);
const column = (values, options) => entire([values], options).columns[0];
const datetime = text => ({text, kind: 'datetime'}), timespan = text => ({text, kind: 'timespan'});
const boolean = text => ({text, kind: 'boolean'}), error = text => ({text, kind: 'error'});

// Reads an R numeric literal as R does, from the IEEE bits its hexadecimal form names.
function readR(literal) {
  if (literal === 'Inf' || literal === '-Inf') return literal === 'Inf' ? Infinity : -Infinity;
  const hex = /^(-?)0x([01])\.([0-9a-f]{13})p([+-][0-9]+)$/.exec(literal);
  if (!hex) {
    assert.match(literal, /^-?[0-9]+(\.[0-9]{1,4})?$/, literal);
    return Number(literal);
  }
  const [, sign, lead, fraction, exponent] = hex, biased = lead === '1' ? Number(exponent) + 1023 : 0;
  assert.ok(lead === '1' ? biased >= 1 && biased <= 2046 : exponent === '-1022', literal);
  const view = new DataView(new ArrayBuffer(8));
  view.setUint32(0, (sign ? 0x80000000 : 0) + biased * 0x100000 + parseInt(fraction.slice(0, 5), 16));
  view.setUint32(4, parseInt(fraction.slice(5), 16));
  return view.getFloat64(0);
}

test('rule 3.8 writes every example number as a literal that names the same double', () => {
  const examples = [[0.30000000000000004, '0x1.3333333333334p-2'], [1 / 3, '0x1.5555555555555p-2'], [5.499065962e-14, '0x1.ef4fd3fb883e3p-45'],
    [84814136847853600000, '0x1.264216064eebbp+66'], [1e22, '0x1.0f0cf064dd592p+73'], [1e23, '0x1.52d02c7e14af6p+76'],
    [9007199254740993, '0x1.0000000000000p+53'], [1.7976931348623157e308, '0x1.fffffffffffffp+1023'],
    [2.2250738585072014e-308, '0x1.0000000000000p-1022'], [5e-324, '0x0.0000000000001p-1022'], [-0, '0'],
    [0.883020325331, '0x1.c41b3d75fff63p-1'], [12, '12'], [13.5, '13.5'], [0.1, '0.1'], [98.6, '98.6'], [-0.25, '-0.25']];
  for (const [x, literal] of examples) {
    assert.equal(rNumber(x), literal, String(x));
    assert.ok(readR(literal) === x, literal);
  }
  const data = column(examples.map(([x]) => x));
  assert.equal(data.type, 'double');
  assert.deepEqual(data.values, examples.map(([, literal]) => literal));
  // The decimal band: no exponent, at most four decimals, at most 15 digits once leading zeros go.
  assert.deepEqual([0.0001, 0.00001, 100.1234, 100.12345, 123456789012345, 1234567890123456, 1e20, 1e21, -1.5, -5e-324].map(rNumber),
    ['0.0001', '0x1.4f8b588e368f1p-17', '100.1234', '0x1.907e69ad42c3dp+6', '123456789012345', '0x1.18b54f22aeb00p+50',
      '0x1.5af1d78b58c40p+66', '0x1.b1ae4d6e2ef50p+69', '-1.5', '-0x0.0000000000001p-1022']);
  assert.deepEqual([Infinity, -Infinity].map(rNumber), ['Inf', '-Inf']);
});

test('rule 3.8 literals read back exactly over a large random sample of doubles', () => {
  const view = new DataView(new ArrayBuffer(8));
  let seed = 0x9e3779b9;
  const random = () => (seed = Math.imul(seed ^ seed >>> 15, 0x2c1b3c6d) + 0x6d2b79f5 >>> 0);
  for (let i = 0; i < 200000; i++) {
    view.setUint32(0, i % 10 === 0 ? random() & 0x800fffff : random());   // one in ten subnormal or zero
    view.setUint32(4, random());
    const x = view.getFloat64(0);
    if (!Number.isFinite(x)) continue;
    const literal = rNumber(x);
    assert.ok(readR(literal) === x, `${x} as ${literal}`);
  }
  for (let i = 0; i < 50000; i++) {   // short typed decimals stay decimal and exact
    const x = Number(((random() % 2000000) - 1000000) / 10 ** (random() % 5));
    assert.ok(readR(rNumber(x)) === x, String(x));
  }
});

test('rule 3.1 trims Unicode White_Space only, and rule 3.4 reads finite ASCII decimals without a leading zero', () => {
  const space = [...Array(0x10000).keys()].map(u => String.fromCharCode(u)).filter(ch => /\p{White_Space}/u.test(ch));
  assert.equal(space.length, 25);
  for (const ch of space) assert.equal(trimSpace(ch + 'x' + ch), 'x', ch.codePointAt(0).toString(16));
  assert.equal(trimSpace('\u200bx\ufeff'), '\u200bx\ufeff');
  for (const [text, x] of [['12', 12], ['.5', 0.5], ['5.', 5], ['+5', 5], ['1E+05', 100000], ['1e-400', 0], ['0', 0], ['0.5', 0.5],
    ['-0.25', -0.25], ['0e5', 0], ['-0', -0]]) assert.ok(Object.is(numberValue(text), x), text);
  for (const text of ['0012', '-007', '00.5', '1e999', '0x10', 'Infinity', 'NaN', '1,000', '\u0661\u0662\u0663', ' 13', '', '.', 'e5']) assert.ok(Number.isNaN(numberValue(text)), text);
});

test('rule 3.2 and A1: missing markers, and the any-case words only beside numbers, Booleans or dates', () => {
  assert.deepEqual(column(['Na', 'K', 'Cl']), {type: 'character', values: ['Na', 'K', 'Cl']});
  assert.deepEqual(column(['1', 'na', '2']), {type: 'double', values: ['1', null, '2']});
  assert.deepEqual(column([1, 'na', 2]), {type: 'double', values: ['1', null, '2']});
  assert.deepEqual(column(['Alive', 'Missing']), {type: 'character', values: ['Alive', 'Missing']});
  assert.deepEqual(column(['Smith', 'NA']), {type: 'character', values: ['Smith', null]});
  assert.deepEqual(column([boolean('TRUE'), 'na']), {type: 'logical', values: ['TRUE', null]});
  assert.deepEqual(column(['TRUE', 'na']), {type: 'logical', values: ['TRUE', null]});
  assert.deepEqual(column([datetime('2026-11-21 00:00:00'), 'Null']), {type: 'Date', values: ['20778', null]});
  // No anchor: the words and Inf stay text.
  assert.deepEqual(column(['Nan', 'Nan']), {type: 'character', values: ['Nan', 'Nan']});
  assert.deepEqual(column(['na']), {type: 'character', values: ['na']});
  assert.deepEqual(column(['Inf']), {type: 'character', values: ['Inf']});
  assert.deepEqual(column(['Inf', 1]), {type: 'double', values: ['Inf', '1']});
  assert.deepEqual(column(['na', 1]), {type: 'double', values: [null, '1']});
  assert.deepEqual(column(['na', 'Inf']), {type: 'character', values: ['na', 'Inf']});
  assert.deepEqual(column([boolean('TRUE'), 'Inf']), {type: 'character', values: ['TRUE', 'Inf']});
  // Every marker of any column, around white space, beside one number.
  const markers = ['', ' ', '*', '* (missing)', '.', 'NA', 'N/A', 'NaN', 'NULL', 'MISSING', ' NA ', '\u00a0*\u3000', 'n/a', 'NAN', 'mIsSiNg'];
  assert.deepEqual(column([7, ...markers.map(text => ({text, kind: 'text'})), 8]), {type: 'double', values: ['7', ...markers.map(() => null), '8']});
  assert.deepEqual(column(['*', '.', 'N/A', null, 'x']), {type: 'character', values: [null, null, null, null, 'x']});
  // A column of missing values only is logical NA.
  assert.deepEqual(column(['NA', '*', ' ', error('#N/A')]), {type: 'logical', values: [null, null, null, null]});
});

test('rule 3.2 white space and C9 codes: numbers, missing values and text', () => {
  assert.deepEqual(column([' 13']), {type: 'double', values: ['13']});
  assert.deepEqual(column(['13\u0085']), {type: 'double', values: ['13']});
  assert.deepEqual(column(['\u3000']), {type: 'logical', values: [null]});
  assert.deepEqual(column(['\ufeff13']), {type: 'character', values: ['\ufeff13']});
  assert.deepEqual(column(['0012', '-007', '00.5']), {type: 'character', values: ['0012', '-007', '00.5']});
  assert.deepEqual(column(['0', '0.5', '-0.25', '0e5']), {type: 'double', values: ['0', '0.5', '-0.25', '0']});
  assert.deepEqual(column([1, 'Inf', '-infinity', ' INFINITY ', '-Inf']), {type: 'double', values: ['1', 'Inf', '-Inf', 'Inf', '-Inf']});
  assert.deepEqual(column(['1e999', 1]), {type: 'character', values: ['1e999', '1']});
  assert.deepEqual(column(['0x10', 1]), {type: 'character', values: ['0x10', '1']});
  assert.deepEqual(column(['+Inf', 1]), {type: 'character', values: ['+Inf', '1']});
  // A typed number keeps its text in the Mac grid; its value is read from that text (rule 3.4).
  const typed = workbook([]), store = typed.sheets[0].store;
  store.apply([[0, 0, '1.50'], [0, 1, ' 13'], [0, 2, '5.'], [0, 3, '1E+05'], [0, 4, '-0'], [0, 5, '1e-400'], [1, 0, 'x'], [1, 1, '1.50'], [1, 2, '-0']]);
  assert.deepEqual([0, 1, 2, 3, 4, 5].map(r => store.kind(0, r)), Array(6).fill('number'));
  const data = worksheetRImport(typed, 0, {}, 'entire');
  assert.deepEqual(data.columns[0], {type: 'double', values: ['1.5', '13', '5', '100000', '0', '0']});
  assert.deepEqual(data.columns[1], {type: 'character', values: ['x', '1.5', '0', null, null, null]});
});

test('rules 3.5 to 3.7: Booleans, mixed columns and number cells written as JavaScript writes them', () => {
  assert.deepEqual(column(['true', 'True', boolean('FALSE'), ' false ']), {type: 'logical', values: ['TRUE', 'TRUE', 'FALSE', 'FALSE']});
  assert.deepEqual(column(['true', 'True', boolean('FALSE'), 'x']), {type: 'character', values: ['true', 'True', 'FALSE', 'x']});
  assert.deepEqual(column([boolean('TRUE'), 1]), {type: 'character', values: ['TRUE', '1']});
  assert.deepEqual(column(['x', 100000, 0.00001, 1e-7, 1.2e-7, 1e21, -0, 123456789012345680000, 5e-324, 1.7976931348623157e308, 0.30000000000000004]),
    {type: 'character', values: ['x', '100000', '0.00001', '1e-7', '1.2e-7', '1e+21', '0', '123456789012345680000', '5e-324', '1.7976931348623157e+308', '0.30000000000000004']});
  // Text cells keep their exact text, white space included.
  assert.deepEqual(column(['x', '1.50', ' 13 ', 'true', '\tTab\n']), {type: 'character', values: ['x', '1.50', ' 13 ', 'true', '\tTab\n']});
  // Doubles, never integers: whole numbers are plain literals of a double column.
  assert.deepEqual(column([1, 2, 3]), {type: 'double', values: ['1', '2', '3']});
});

test('C4: a spreadsheet error is missing; text that looks like an error stays text', () => {
  assert.deepEqual(column([1, error('#DIV/0!'), error('#N/A'), 3]), {type: 'double', values: ['1', null, null, '3']});
  assert.deepEqual(column(['#DIV/0!', 'x']), {type: 'character', values: ['#DIV/0!', 'x']});
  assert.deepEqual(entire([[error('#REF!'), 1, 2], ['B', 3, 4]], {headings: true}).names, ['A', 'B']);
});

test('rule 3.9 and A2: dates, date-times, times of day, durations and serial 60', () => {
  const dates = column([datetime('2026-11-21 00:00:00'), datetime('1970-01-01'), datetime('1900-01-01 00:00:00'), null, datetime('1904-01-01 00:00:00')]);
  assert.deepEqual(dates, {type: 'Date', values: ['20778', '0', '-25567', null, '-24107']});
  assert.deepEqual(column([datetime('2026-11-21 00:00:00'), datetime('2026-11-21 14:30:00.5')]),
    {type: 'character', values: ['2026-11-21 00:00:00', '2026-11-21 14:30:00.5']});
  assert.deepEqual(column([datetime('2026-11-21 00:00:00'), 'x', datetime('2026-11-22 08:00:00')]),
    {type: 'character', values: ['2026-11-21', 'x', '2026-11-22 08:00:00']});
  assert.deepEqual(column([timespan('14:30:00'), timespan('1.02:00:00'), timespan('-01:00:00'), timespan('14:30:00.5000000'), timespan('00:00:00.0004')]),
    {type: 'character', values: ['14:30:00', '26:00:00', '-01:00:00', '14:30:00.5', '00:00:00']});
  assert.deepEqual(column([timespan('-00:00:00.0004'), timespan('10675199.02:48:05.4775807'), timespan('23:59:59.9996')]),
    {type: 'character', values: ['00:00:00', '256204778:48:05.478', '24:00:00']});
  // Serial 60, the nonexistent 1900-02-29, is NA; beside dates the column is still Date.
  assert.deepEqual(column([datetime('1900-02-29'), datetime('1900-03-01 00:00:00')]), {type: 'Date', values: [null, '-25508']});
  assert.deepEqual(column([datetime('1900-02-29 06:00:00')]), {type: 'logical', values: [null]});
  // Rounding to the millisecond carries into the seconds, minutes and date.
  assert.deepEqual(column([datetime('2026-12-31 23:59:59.9996'), datetime('2026-11-21T10:30:00.1234'), datetime('2026-11-21T10:30:00.500000Z'), datetime('2026-11-21 10:30')]),
    {type: 'character', values: ['2027-01-01 00:00:00', '2026-11-21 10:30:00.123', '2026-11-21 10:30:00.5', '2026-11-21 10:30:00']});
  assert.deepEqual(column([datetime('2026-12-31 23:59:59.9996')]), {type: 'Date', values: ['20819']});
  // A datetime cell whose text is not a calendar date is text: Excel's own or an R NaN Date.
  assert.deepEqual(column([datetime('2026-02-30'), datetime('2026-11-21 24:00:00'), datetime('NaN')]), {type: 'character', values: ['2026-02-30', '2026-11-21 24:00:00', null]});
  assert.deepEqual(column([datetime('0001-01-01 00:00:00'), datetime('9999-12-31 00:00:00')]), {type: 'Date', values: ['-719162', '2932896']});
  // A2: the date comment depends on the data cells, not the heading.
  assert.equal(entire([[1, 2]]).dates, false);
  assert.equal(entire([[timespan('14:30:00'), 2]]).dates, true);
  assert.equal(entire([[datetime('2026-11-21 00:00:00'), 2]], {headings: true}).dates, false);
  assert.equal(entire([['When', datetime('1900-02-29')]], {headings: true}).dates, true);
});

test('rule 3.10: text is exact, a lone surrogate becomes U+FFFD and a NUL is refused with its cell', () => {
  assert.deepEqual(column(['a\u2068b\u2069\u202ec', '"\\\r\n\u001a']), {type: 'character', values: ['a\u2068b\u2069\u202ec', '"\\\r\n\u001a']});
  assert.deepEqual(column(['a\ud800b', '\udc00', '\ud83d\ude00']), {type: 'character', values: ['a\ufffdb', '\ufffd', '\ud83d\ude00']});
  assert.deepEqual(entire([['\ud800'], ['x\udfff']], {headings: false}).columns.map(c => c.values), [['\ufffd'], ['x\ufffd']]);
  assert.deepEqual(entire([['H\ud800', 1, 2]], {headings: true}).names, ['H\ufffd']);
  const nul = workbook([cell(0, 0, 'Head', 'text'), cell(1, 6, 'a\0b', 'text')]);
  assert.throws(() => worksheetRImport(nul, 0, {}, 'entire'),
    {message: 'Cell B7 contains a null character, which R cannot hold. Remove it, then open the R import again.'});
  const heading = workbook([cell(2, 0, '\0', 'text'), cell(2, 1, '1')]);
  assert.throws(() => worksheetRImport(heading, 0, {}, 'entire', {headings: true}), /^Error: Cell C1 contains a null character/);
});

test('rules 4.1 to 4.5: the heading suggestion, exact names and the column letters', () => {
  const electrolytes = sheet([['Na', 140, 138], ['K', 4.1, 3.9]]);
  assert.equal(worksheetRImport(electrolytes, 0).entire.suggestHeadings, true);
  const named = worksheetRImport(electrolytes, 0, {}, 'entire', {headings: true});
  assert.deepEqual([named.names, named.rowCount, named.columns], [['Na', 'K'], 3, [{type: 'double', values: ['140', '138']}, {type: 'double', values: ['4.1', '3.9']}]]);
  const unnamed = worksheetRImport(electrolytes, 0, {}, 'entire', {headings: false});
  assert.deepEqual([unnamed.names, unnamed.columns[0]], [['A', 'B'], {type: 'double', values: [null, '140', '138']}]);
  // Column 365 is named NA; a blank heading takes its letter, even beside a heading of that letter.
  const wide = workbook([cell(364, 0, '1')], {columns: 400});
  assert.equal(columnName(364), 'NA');
  assert.deepEqual(worksheetRImport(wide, 0, {}, 'entire').names, ['NA']);
  assert.deepEqual(entire([['B', 1, 2], [null, 3, 4], [' ', 5, 6]], {headings: true}).names, ['B', 'B', 'C']);
  const awkward = ['row.names', 'row.names', 'check.rows', 'stringsAsFactors', '..adfl.x', ' Before  ', 'x'.repeat(10001), 'NA', '*'];
  assert.deepEqual(entire(awkward.map(name => [name, 1, 2]), {headings: true}).names, awkward);
  // Headings from other kinds of cell, when the box is ticked by hand (rule 4.5).
  const kinds = entire([[1.5, 1, 2], [{text: '1.50', kind: 'number'}, 1, 2], [-0, 1, 2], [boolean('true'), 1, 2], [datetime('2026-11-21 00:00:00'), 1, 2],
    [datetime('2026-11-21 10:30:00'), 1, 2], [timespan('1.02:00:00'), 1, 2], [datetime('1900-02-29'), 1, 2]], {headings: true});
  assert.deepEqual(kinds.names, ['1.5', '1.5', '0', 'TRUE', '2026-11-21', '2026-11-21 10:30:00', '26:00:00', 'H']);
  assert.equal(worksheetRImport(sheet([[1.5, 1, 2]]), 0).entire.suggestHeadings, false);
  // One row cannot be both headings and data: the box is disabled, and ignored if sent.
  const single = entire([['Na'], ['K']], {headings: true});
  assert.deepEqual([single.names, single.rowCount, single.columns[0].values], [['A', 'B'], 1, ['Na']]);
});

test('rule 4.1: which first rows are suggested as headings', () => {
  const suggests = (...first) => worksheetRImport(sheet(first.map(v => [v, 1])), 0).entire.suggestHeadings;
  for (const heading of ['Label', 'Na', 'n/a', 'Inf', '1e999', 'Group 1', '\ud835\udc00', '\ud840\udc00', 'é', ' PEFR  Before ']) assert.equal(suggests(heading), true, heading);
  for (const heading of ['---', '%', '(1)', '1,000', '12-14', '*', '.', 'NA', 'N/A', 'NaN', 'NULL', 'MISSING', '* (missing)', '\u0661\u0662\u0663', '²', '12', '0012',
    'TRUE', 'false', 12, boolean('TRUE'), datetime('2026-11-21 00:00:00'), timespan('14:30:00'), error('#N/A')]) assert.equal(suggests(heading), false, String(heading.text ?? heading));
  assert.equal(suggests('Label', null), true);
  assert.equal(suggests('Label', '   '), true);
  assert.equal(suggests('   '), false);
  assert.equal(suggests('Label', 'NA'), false);
  assert.equal(worksheetRImport(sheet([['Label']]), 0).entire.suggestHeadings, false);
  // A formula counts by its value.
  const formula = workbook([cell(0, 0, 'Group 1', 'text', {formula: 'A9&" 1"'}), cell(1, 0, '', 'blank', {formula: 'IF(1,"","")'}), cell(0, 1, '4')]);
  assert.equal(worksheetRImport(formula, 0).entire.suggestHeadings, true);
});

test('rule 2.1 and the preview: populated bounds, the sheet and no selection', () => {
  const book = workbook([cell(2, 4, ' PEFR  Before ', 'text'), cell(4, 4, 'After', 'text'),
    cell(2, 5, '3.25'), cell(4, 8, '7'), cell(0, 0, '', 'blank', {format: '0.00'}), cell(6, 9, '  ', 'text')]);
  assert.deepEqual(worksheetRImport(book, 0), {sheet: 'Measurements',
    entire: {range: 'C5:G10', rowCount: 6, columnCount: 5, suggestHeadings: true}, selected: null, selectedReason: 'none'});
  const data = worksheetRImport(book, 0, {}, 'entire');
  assert.deepEqual([data.sheet, data.range, data.rangeAll, data.rowCount, data.columnCount, data.names, data.dates],
    ['Measurements', 'C5:G10', 'C5:G10', 6, 5, ['C', 'D', 'E', 'F', 'G'], false]);
  assert.deepEqual(data.columns.map(c => c.values), [[' PEFR  Before ', '3.25', null, null, null, null], [null, null, null, null, null, null],
    ['After', null, null, null, '7', null], [null, null, null, null, null, null], [null, null, null, null, null, null]]);
  assert.deepEqual(data.columns.map(c => c.type), ['character', 'logical', 'character', 'logical', 'logical']);
  assert.deepEqual(worksheetRImport(book, 0, {}, 'entire', {headings: true}).names, [' PEFR  Before ', 'D', 'After', 'F', 'G']);
});

test('rules 2.2 and 2.8: a rectangle keeps its bounds, one cell is valid, and a blank rectangle is not available', () => {
  const book = workbook([cell(0, 0, 'First', 'text'), cell(1, 0, 'Second', 'text'), cell(0, 2, '5'), cell(1, 3, 'true', 'boolean')], {headerRow: true});
  const rectangle = {range: {x: 0, y: 0, width: 3, height: 8}};
  assert.deepEqual(worksheetRImport(book, 0, rectangle).selected, {range: 'A1:C8', rowCount: 8, columnCount: 3, suggestHeadings: true});
  const raw = worksheetRImport(book, 0, rectangle, 'selected', {headings: true});
  assert.deepEqual([raw.names, raw.columns.map(c => c.type)], [['First', 'Second', 'C'], ['double', 'logical', 'logical']]);
  assert.deepEqual(raw.columns[0].values, [null, '5', null, null, null, null, null]);
  assert.deepEqual(worksheetRImport(book, 0, {range: {x: 0, y: 2, width: 1, height: 1}}), {sheet: 'Measurements',
    entire: {range: 'A1:B4', rowCount: 4, columnCount: 2, suggestHeadings: true}, selected: {range: 'A3', rowCount: 1, columnCount: 1, suggestHeadings: false}, selectedReason: null});
  const blank = worksheetRImport(book, 0, {range: {x: 3, y: 1, width: 2, height: 4}});
  assert.deepEqual([blank.selected, blank.selectedReason], [null, 'empty']);
  assert.throws(() => worksheetRImport(book, 0, {range: {x: 3, y: 1, width: 2, height: 4}}, 'selected'), /Select worksheet cells, columns or rows/);
  // The grid's own header-row flag plays no part: names come only from the prompt's choice.
  const interior = worksheetRImport(book, 0, {range: {x: 0, y: 2, width: 2, height: 2}}, 'selected');
  assert.deepEqual([interior.names, interior.columns[0].values], [['A', 'B'], ['5', null]]);
});

test('rule 2.3 and C7: whole columns, trimmed to their data rows, in sheet order and written as Excel writes a union', () => {
  const book = workbook([cell(2, 2, '1'), cell(2, 3, '2'), cell(4, 2, '3'), cell(4, 3, '4'), cell(3, 9, 'far', 'text'), cell(7, 0, 'x', 'text')]);
  assert.deepEqual(worksheetRImport(book, 0, {columns: [4, 2]}).selected, {range: 'C3:C4,E3:E4', rowCount: 2, columnCount: 2, suggestHeadings: false});
  const pair = worksheetRImport(book, 0, {columns: [4, 2]}, 'selected');
  assert.deepEqual([pair.names, pair.columns.map(c => c.values), pair.rangeAll], [['C', 'E'], [['1', '2'], ['3', '4']], 'C3:C4,E3:E4']);
  assert.equal(worksheetRImport(book, 0, {columns: [2, 3, 4]}).selected.range, 'C3:E10');
  // A selected column with no data stays, as NA.
  const withBlank = worksheetRImport(book, 0, {columns: [2, 5]}, 'selected');
  assert.deepEqual([withBlank.range, withBlank.columns], ['C3:C4,F3:F4', [{type: 'double', values: ['1', '2']}, {type: 'logical', values: [null, null]}]]);
  assert.deepEqual(worksheetRImport(book, 0, {columns: [5, 6]}).selectedReason, 'empty');
  // The prompt lists three areas, then an ellipsis; the comment's text lists them all.
  const spread = workbook([0, 2, 4, 6, 8].map(c => cell(c, 0, String(c))), {columns: 12});
  const five = worksheetRImport(spread, 0, {columns: [0, 2, 4, 6, 8]}, 'selected');
  assert.deepEqual([five.range, five.rangeAll], ['A1,C1,E1,…', 'A1,C1,E1,G1,I1']);
  assert.equal(worksheetRImport(spread, 0, {columns: [0, 2, 4]}).selected.range, 'A1,C1,E1');
});

test('C6: whole rows, from the first to the last selected row with data, across the data of those rows', () => {
  const book = workbook([cell(2, 2, 'Name', 'text'), cell(3, 2, 'Count', 'text'), cell(2, 3, 'Alpha', 'text'), cell(3, 3, '5'),
    cell(3, 5, '7'), cell(6, 30, 'later', 'text')]);
  const rows = Array.from({length: 10}, (_, r) => r);
  assert.deepEqual(worksheetRImport(book, 0, {rows}).selected, {range: 'C3:D6', rowCount: 4, columnCount: 2, suggestHeadings: true});
  const data = worksheetRImport(book, 0, {rows}, 'selected', {headings: true});
  assert.deepEqual([data.names, data.columns], [['Name', 'Count'], [{type: 'character', values: ['Alpha', null, null]}, {type: 'double', values: ['5', null, '7']}]]);
  // Unselected rows between selected ones are not sent; each run of rows is an area.
  const gaps = worksheetRImport(book, 0, {rows: [2, 3, 5, 90]}, 'selected');
  assert.deepEqual([gaps.range, gaps.rowCount, gaps.columns[1].values], ['C3:D4,C6:D6', 3, ['Count', '5', '7']]);
  assert.deepEqual(worksheetRImport(book, 0, {rows: [6, 7, 8]}).selectedReason, 'empty');
  assert.equal(worksheetRImport(book, 0, {rows: [5, 30]}).selected.range, 'D6:G6,D31:G31');
});

test('rule 2.6: select all is the entire worksheet, by the corner, Command-A or every column', () => {
  const book = workbook([cell(2, 2, 'x', 'text'), cell(3, 4, '1')]);
  const store = book.sheets[0].store, whole = worksheetRImport(book, 0).entire;
  assert.deepEqual(whole, {range: 'C3:D5', rowCount: 3, columnCount: 2, suggestHeadings: true});
  for (const selection of [{range: {x: 0, y: 0, width: store.columns.length, height: store.rows}},
    {rows: Array.from({length: store.rows}, (_, r) => r)}, {columns: Array.from({length: store.columns.length}, (_, c) => c)}]) {
    assert.deepEqual(worksheetRImport(book, 0, selection), {sheet: 'Measurements', entire: whole, selected: whole, selectedReason: null});
    assert.deepEqual(worksheetRImport(book, 0, selection, 'selected'), worksheetRImport(book, 0, {}, 'entire'));
  }
  // Edit ▸ Select All selects the used rows, marked as select all; the same rectangle drawn by hand
  // keeps its own bounds.
  const menu = {range: {x: 0, y: 0, width: store.columns.length, height: store.usedRows()}};
  assert.deepEqual(worksheetRImport(book, 0, {...menu, all: true}).selected, whole);
  assert.equal(worksheetRImport(book, 0, menu).selected.range, 'A1:H5');
  const blank = workbook([]), size = blank.sheets[0].store;
  assert.deepEqual(worksheetRImport(blank, 0, {range: {x: 0, y: 0, width: size.columns.length, height: size.rows}}),
    {sheet: 'Measurements', entire: null, selected: null, selectedReason: 'empty'});
  assert.equal(worksheetRImport(blank, 0, {range: {x: 0, y: 0, width: size.columns.length, height: 1}, all: true}).selectedReason, 'empty');
});

test('C7: a multiple selection other than whole columns or whole rows is refused as a shape', () => {
  const book = workbook([cell(0, 0, '1'), cell(1, 1, '2')]);
  for (const selection of [{range: {x: 0, y: 0, width: 1, height: 1}, ranges: [{x: 1, y: 1, width: 1, height: 1}]},
    {columns: [0], rows: [1]}, {columns: [0], range: {x: 0, y: 0, width: 1, height: 1}}]) {
    assert.deepEqual(worksheetRImport(book, 0, selection).selectedReason, 'shape');
    assert.throws(() => worksheetRImport(book, 0, selection, 'selected'), /Select worksheet cells, columns or rows/);
  }
});

test('R import refuses selections outside the worksheet, unknown scopes and empty worksheets', () => {
  const empty = workbook([]);
  assert.deepEqual(worksheetRImport(empty, 0), {sheet: 'Measurements', entire: null, selected: null, selectedReason: 'none'});
  assert.throws(() => worksheetRImport(empty, 0, {}, 'entire'), {message: 'The worksheet contains no data.'});
  assert.throws(() => worksheetRImport(empty, 0, {}, 'selected'), {message: 'Select worksheet cells, columns or rows to import.'});
  assert.throws(() => worksheetRImport(empty, 0, {range: {x: 7, y: 0, width: 2, height: 1}}), /inside/);
  assert.throws(() => worksheetRImport(empty, 0, {columns: [0, 0]}), /inside/);
  assert.throws(() => worksheetRImport(empty, 0, {rows: [100]}), /inside/);
  assert.throws(() => worksheetRImport(empty, 0, {}, 'invalid'), /entire worksheet/);
  assert.throws(() => worksheetRImport(empty, 3), /open worksheet/);
  // The entire worksheet ignores a selection it does not use.
  const book = workbook([cell(0, 0, '1')]);
  assert.equal(worksheetRImport(book, 0, {columns: [0, 0]}, 'entire').columns[0].values[0], '1');
});

test('rules 3.2 and 7: formula cells send saved values; an empty saved result is NA; others are refused', () => {
  const formulaOnly = workbook([cell(25, 11, '', 'blank', {formula: '1+2'}), cell(0, 0, '', 'blank', {style: 'Heading'})], {columns: 26});
  assert.deepEqual(worksheetRImport(formulaOnly, 0).entire, {range: 'Z12', rowCount: 1, columnCount: 1, suggestHeadings: false});
  assert.throws(() => worksheetRImport(formulaOnly, 0, {}, 'entire'), {message: 'Recalculate and save this workbook in Excel, then reopen it before using formula cells in R.'});
  const cached = workbook([cell(25, 11, '3', 'number', {formula: '1+2'})], {columns: 26});
  assert.deepEqual(worksheetRImport(cached, 0, {}, 'entire').columns, [{type: 'double', values: ['3']}]);
  const savedEmpty = workbook([cell(0, 0, '5'), cell(0, 1, '', 'blank', {formula: 'IF(A1>9,A1,"")', savedEmpty: true}), cell(0, 2, '7')]);
  assert.deepEqual(worksheetRImport(savedEmpty, 0, {}, 'entire').columns, [{type: 'double', values: ['5', null, '7']}]);
  // Once the workbook is edited, every formula result may be out of date, the empty ones too.
  for (const book of [savedEmpty, cached]) {
    book.sheets[0].store.formulasStale = true;
    assert.throws(() => worksheetRImport(book, 0, {}, 'entire'), /Recalculate/);
  }
  const heading = workbook([cell(0, 0, 'Total', 'text', {formula: '"Total"'}), cell(0, 1, '1')]);
  heading.sheets[0].store.formulasStale = true;
  assert.throws(() => worksheetRImport(heading, 0, {}, 'entire', {headings: true}), /Recalculate/);
});

test('the 8 MiB check refuses only what no script could hold, before reading huge sparse data', () => {
  const book = workbook([], {columns: 10, rows: 10000});
  book.sheets[0].store.apply(Array.from({length: 10}, (_, c) => Array.from({length: 10000}, (_, r) => [c, r, String(r + c)])).flat());
  const result = worksheetRImport(book, 0, {columns: Array.from({length: 10}, (_, c) => c)}, 'selected');
  assert.deepEqual([result.rowCount, result.columns[9].values[9999], result.range], [10000, '10008', 'A1:J10000']);
  assert.throws(() => worksheetRImport(book, 0, {columns: [0]}, 'selected', {}, 100), {message: 'The selected data exceed the 8 MiB editable R script limit. Select a smaller range, or export the worksheet as RDS from File → Export.'});
  const large = workbook([cell(0, 0, '1')], {columns: 8, rows: 1048576});
  assert.throws(() => worksheetRImport(large, 0, {range: {x: 0, y: 0, width: 7, height: 1048576}}, 'selected'), /8 MiB/);
  // Long values count by their own length.
  const long = workbook([cell(0, 0, 'x'.repeat(5000), 'text'), cell(0, 1, 'y'.repeat(5000), 'text')]);
  assert.throws(() => worksheetRImport(long, 0, {}, 'entire', {}, 9000), /8 MiB/);
  assert.equal(worksheetRImport(long, 0, {}, 'entire', {}, 11000).columns[0].values[1].length, 5000);
});

test('R import preview does not materialise huge sparse worksheet data', () => {
  const book = workbook([cell(0, 0, '1'), cell(16383, 1048575, '2')], {columns: 16384, rows: 1048576});
  const store = book.sheets[0].store, get = store.get.bind(store);
  let reads = 0;
  store.get = (c, r) => { assert.ok(++reads <= 16384); return get(c, r); };
  assert.deepEqual(worksheetRImport(book, 0).entire, {range: 'A1:XFD1048576', rowCount: 1048576, columnCount: 16384, suggestHeadings: false});
  reads = 0;
  assert.equal(worksheetRImport(book, 0, {range: {x: 0, y: 0, width: 16384, height: 1048576}}).selectedReason, null);
  reads = 0;
  assert.equal(worksheetRImport(book, 0, {rows: [5, 1048575]}).selected.range, 'XFD1048576');
  assert.throws(() => worksheetRImport(book, 0, {}, 'entire'), /8 MiB/);
});
