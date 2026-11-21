// The worksheet R import's values, checked in R: node Tests/worksheet-r-rules.mjs /path/to/Rscript
//
// Builds worksheets in the grid's own store, runs its import (Grid/worksheet-r.mjs), writes each
// column as an R vector the way the script does (literals as given, NA for missing, a Date column in
// structure()), and has R compare them with identical() against objects written by hand from the
// shared rules ("Worksheet data sent to R": C9 and rules 3.2, 3.6, 3.7 and 3.9). Numbers are also
// compared with the doubles' own bits, read by readBin, over the rules' examples and a large random
// sample. Exits non-zero when R reports a difference.
import {spawnSync} from 'node:child_process';
import {mkdtempSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {WorkbookStore} from '../Grid/workbook.mjs';
import {worksheetRImport} from '../Grid/worksheet-r.mjs';

const rscript = process.argv[2];
if (!rscript) { console.error('Usage: node Tests/worksheet-r-rules.mjs /path/to/Rscript'); process.exit(2); }

// Columns of values from row 1: a number is a number cell, a string a text cell, null a blank cell,
// and an object {text, kind, ...} is taken as given.
const cellOf = v => typeof v === 'number' ? {text: Object.is(v, -0) ? '-0' : String(v), kind: 'number'} : typeof v === 'string' ? {text: v, kind: 'text'} : v;
function imported(columns, {headings = false, rows = 100} = {}) {
  const cells = [];
  columns.forEach((values, col) => values.forEach((v, row) => { if (v !== null) cells.push({col, row, ...cellOf(v)}); }));
  const book = new WorkbookStore();
  book.load({name: 'Rules.xlsx', sheets: [{name: 'Sheet1', headerRow: false, columns: Math.max(8, columns.length), rows, cells}]});
  return worksheetRImport(book, 0, {}, 'entire', {headings});
}
const datetime = text => ({text, kind: 'datetime'}), timespan = text => ({text, kind: 'timespan'});

// An R string literal with every character outside printable ASCII written as a \u escape.
const rString = text => '"' + [...text].map(ch => {
  const u = ch.codePointAt(0);
  if (ch === '"' || ch === '\\') return '\\' + ch;
  if (u >= 0x20 && u < 0x7f) return ch;
  return u > 0xffff ? `\\U{${u.toString(16)}}` : `\\u{${u.toString(16)}}`;
}).join('') + '"';
function rVector({type, values}) {
  const vector = 'c(' + values.map(v => v === null ? 'NA' : type === 'character' ? rString(v) : v).join(', ') + ')';
  return type === 'Date' ? `structure(${vector}, class = "Date")` : vector;
}
const rFrame = data => `structure(list(${data.columns.map(rVector).join(', ')}), names = c(${data.names.map(rString).join(', ')}), `
  + `row.names = c(NA_integer_, -${data.columns[0].values.length}L), class = "data.frame")`;

const lines = [
  'checks <- 0L; failures <- 0L',
  'check <- function(label, actual, expected) {',
  '  checks <<- checks + 1L',
  '  if (!identical(actual, expected)) {',
  '    failures <<- failures + 1L',
  '    cat("FAIL: ", label, "\\n  actual:   ", sep = ""); dput(actual)',
  '    cat("  expected: "); dput(expected)',
  '  }',
  '}'];
const check = (label, actual, expected) => lines.push(`check(${rString(label)}, ${actual}, ${expected})`);
const checkColumn = (label, values, expected, options) => check(label, rVector(imported([values], options).columns[0]), expected);

// C9: codes with a leading zero stay text; other numeric text is a double.
checkColumn('C9 codes', ['0012', '-007', '00.5'], 'c("0012", "-007", "00.5")');
checkColumn('C9 numbers', ['0', '0.5', '-0.25', '0e5'], 'c(0, 0.5, -0.25, 0)');
// Rule 3.2 and A1: missing values, white space and the words in any case.
checkColumn('3.2 {Na, K, Cl}', ['Na', 'K', 'Cl'], 'c("Na", "K", "Cl")');
checkColumn('3.2 {1, na, 2}', ['1', 'na', '2'], 'c(1, NA, 2)');
checkColumn('3.2 {Alive, Missing}', ['Alive', 'Missing'], 'c("Alive", "Missing")');
checkColumn('3.2 {Smith, NA}', ['Smith', 'NA'], 'c("Smith", NA)');
checkColumn('3.2 {TRUE, na}', [{text: 'TRUE', kind: 'boolean'}, 'na'], 'c(TRUE, NA)');
checkColumn('3.2 markers beside numbers', [1, '*', '* (missing)', '.', 'N/A', 'NaN', 'NULL', 'MISSING', ' NA ', 'n/a', 'Null', {text: '#DIV/0!', kind: 'error'}, 2],
  'c(1, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, 2)');
checkColumn('3.2 white space', [' 13', '13\u0085', '\u3000', 7], 'c(13, 13, NA, 7)');
checkColumn('3.2 U+FEFF is not white space', ['\ufeff13'], '"\\ufeff13"');
checkColumn('3.3 Inf words beside numbers', [1, 'Inf', '-infinity'], 'c(1, Inf, -Inf)');
checkColumn('A1 {Nan, Nan}', ['Nan', 'Nan'], 'c("Nan", "Nan")');
checkColumn('A1 {Inf}', ['Inf'], '"Inf"');
checkColumn('A1 {Inf, 1}', ['Inf', 1], 'c(Inf, 1)');
checkColumn('A1 {na, 1}', ['na', 1], 'c(NA, 1)');
checkColumn('A1 {date, na}', [datetime('2026-11-21 00:00:00'), 'na'], 'as.Date(c("2026-11-21", NA))');
// Rule 3.6: doubles, never integers; a column of missing values only is logical NA.
checkColumn('3.6 whole numbers are double', [1, 2, 3], 'c(1, 2, 3)');
checkColumn('3.6 all missing', ['NA', '*', ' '], 'c(NA, NA, NA)');
checkColumn('3.5 Boolean text in a logical column', ['true', 'True', {text: 'FALSE', kind: 'boolean'}], 'c(TRUE, TRUE, FALSE)');
checkColumn('3.5 Boolean text in a character column', ['true', 'True', 'x'], 'c("true", "True", "x")');
// Rule 3.7: number cells in a character column are written as JavaScript's String(x).
checkColumn('3.7 number cells as text', ['x', 100000, 0.00001, 1e-7, 1.2e-7, 1e21, -0], 'c("x", "100000", "0.00001", "1e-7", "1.2e-7", "1e+21", "0")');
// Rule 3.9: dates, date-times, times of day, durations and serial 60.
checkColumn('3.9 a date column', [datetime('2026-11-21 00:00:00'), null, datetime('1970-01-01'), datetime('1900-01-01 00:00:00')],
  'as.Date(c("2026-11-21", NA, "1970-01-01", "1900-01-01"))');
checkColumn('3.9 a date column is double', [datetime('2026-11-21 00:00:00')], 'structure(20778, class = "Date")');
const dateTimes = rVector(imported([[datetime('2026-11-21 00:00:00'), datetime('2026-11-21 14:30:00.5')]]).columns[0]);
check('3.9 midnight beside a time', dateTimes, 'c("2026-11-21 00:00:00", "2026-11-21 14:30:00.5")');
check('3.9 as.POSIXct keeps every time', `as.numeric(as.POSIXct(${dateTimes}, tz = "UTC")) - as.numeric(as.POSIXct("2026-11-21", tz = "UTC"))`, 'c(0, 52200.5)');
checkColumn('3.9 time of day', [timespan('14:30:00')], '"14:30:00"');
checkColumn('3.9 duration over a day', [timespan('1.02:00:00'), timespan('-01:00:00')], 'c("26:00:00", "-01:00:00")');
checkColumn('3.9 duration with a fraction', [timespan('14:30:00.5000000')], '"14:30:00.5"');
checkColumn('3.9 serial 60', [datetime('1900-02-29'), datetime('1900-03-01 00:00:00')], 'as.Date(c(NA, "1900-03-01"))');
checkColumn('3.9 rounding carries into the date', [datetime('2026-12-31 23:59:59.9996')], 'as.Date("2027-01-01")');
// Rules 3.10 and 4: text, names and a whole data frame.
checkColumn('3.10 bidi controls and control characters', ['a\u2068b\u2069\u202ec', '"\\\r\n\t\u001a'], 'c("a\\u2068b\\u2069\\u202ec", "\\"\\\\\\r\\n\\t\\032")');
checkColumn('3.10 a lone surrogate', ['a\ud800b', '\ud83d\ude00'], 'c("a\\ufffdb", "\\U0001f600")');
checkColumn('3.2 a formula with empty text', [5, {text: '', kind: 'blank', formula: 'IF(A1>9,A1,"")', savedEmpty: true}, 7], 'c(5, NA, 7)');
const electrolytes = imported([['Na', 140, 138], ['K', 4.1, 3.9]], {headings: true});
check('4.1 headings over numbers', rFrame(electrolytes), 'data.frame(Na = c(140, 138), K = c(4.1, 3.9))');
const awkward = ['row.names', 'row.names', 'check.rows', 'stringsAsFactors', '..adfl.x', ' Before  ', 'NA'];
check('4.4 names kept exactly', `names(${rFrame(imported(awkward.map(name => [name, 1]), {headings: true}))})`, 'c(' + awkward.map(rString).join(', ') + ')');
check('4.2 column letters', `names(${rFrame(imported([[1], [null], ['x']]))})`, 'c("A", "B", "C")');
check('5.2 a mixed data frame', rFrame(imported([[12, null, 1.5], ['a', null, 'b']])), 'data.frame(A = c(12, NA, 1.5), B = c("a", NA, "b"), check.names = FALSE)');

// Rule 3.8: every number reads back as its double, over the rules' examples and a random sample of
// bit patterns (one in five subnormal) and of short typed decimals. R compares them with the bits.
const examples = [0.30000000000000004, 1 / 3, 5.499065962e-14, 84814136847853600000, 1e22, 1e23, 9007199254740993, 1.7976931348623157e308,
  2.2250738585072014e-308, 5e-324, -0, 0.883020325331, 12, 13.5, 0.1, 98.6, -0.25, -5e-324, 1e-7, 100000];
const view = new DataView(new ArrayBuffer(8));
let seed = 0x2545f491;
const random = () => (seed = Math.imul(seed ^ seed >>> 15, 0x2c1b3c6d) + 0x6d2b79f5 >>> 0);
const sample = [];
while (sample.length < 240000) {
  view.setUint32(0, sample.length % 5 === 0 ? random() & 0x800fffff : random());
  view.setUint32(4, random());
  const x = view.getFloat64(0);
  if (Number.isFinite(x)) sample.push(x);
}
const decimals = Array.from({length: 100000}, () => ((random() % 20000000) - 10000000) / 10 ** (random() % 5));
const folder = mkdtempSync(path.join(tmpdir(), 'worksheet-r-rules-'));
try {
  for (const [label, numbers, width] of [['the rules\' examples', examples, 1], ['random doubles', sample, 4], ['short decimals', decimals, 2]]) {
    const height = numbers.length / width, data = imported(Array.from({length: width}, (_, c) => numbers.slice(c * height, (c + 1) * height)), {rows: height});
    if (data.columns.some(c => c.type !== 'double')) throw new Error(`${label}: a column is not double`);
    const bits = path.join(folder, label.replace(/\W+/g, '-') + '.bin');
    writeFileSync(bits, new Uint8Array(new Float64Array(numbers).buffer));
    lines.push(`bits <- readBin(${rString(bits)}, "double", n = ${numbers.length}L, size = 8L, endian = "${new Uint8Array(new Uint16Array([1]).buffer)[0] ? 'little' : 'big'}")`);
    lines.push(`literals <- c(${data.columns.map(rVector).join(', ')})`);
    check(`3.8 ${label} are identical to their doubles`, 'literals', 'bits');
    check(`3.8 ${label} are bitwise equal, with -0 as 0`, 'identical(literals, ifelse(bits == 0, 0, bits), num.eq = FALSE)', 'TRUE');
  }
  lines.push('cat(sprintf("worksheet R rules: %d checks in R, %d failures\\n", checks, failures))', 'if (failures) quit(status = 1L)');
  const script = path.join(folder, 'rules.R');
  writeFileSync(script, lines.join('\n') + '\n');
  // source() parses the file at once; R's console reader (Rscript file.R) takes minutes over megabytes of literals.
  const run = spawnSync(rscript, ['--vanilla', '-e', `source(${rString(script)}, encoding = "UTF-8")`], {encoding: 'utf8', maxBuffer: 64 * 1024 * 1024});
  process.stdout.write(run.stdout);
  process.stderr.write(run.stderr);
  if (run.error) throw run.error;
  process.exitCode = run.status === 0 && /0 failures/.test(run.stdout) ? 0 : 1;
} finally {
  rmSync(folder, {recursive: true, force: true});
}
