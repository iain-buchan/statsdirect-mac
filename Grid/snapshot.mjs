// Typed columnar worksheet snapshot, shared with FullEngine/WorkbookIO.cs (WriteSnapshot /
// ReadSnapshot). Little-endian. Header: "SCOL" u32, version u32 (1), sheet count u32,
// reserved u32. Sheet: name length u32, UTF-8 name, pad to 4, column count u32. Column:
// index u32, cell count n u32, text count u32, formula count u32, rows u32[n], kinds u8[n],
// pad to 8, numbers f64[n], then text and formula entries (cell ordinal u32, byte length u32,
// UTF-8 bytes), each group padded to 4. Kinds follow KINDS in store.mjs: a number cell carries
// its value in `nums`; every other kind carries its text. When bit 0 of the header's fourth
// word (reserved, otherwise 0) is set, each column header has a fifth count and a third
// string group follows the formulas: `extras`, a JSON object of loader metadata per cell
// (the R data markers `rMissing` and `rRaw`).
const MAGIC = 0x4C4F4353, VERSION = 1;
const align = (p, a) => (p + a - 1) & ~(a - 1);

// Decodes a snapshot into {sheets: [{name, columns: [{col, rows, kinds, nums, texts, formulas, extras}]}]}.
// `rows`, `kinds` and `nums` are typed-array views, `texts`, `formulas` and `extras` are Maps
// from the cell ordinal within the column to the string.
export function decodeSnapshot(input) {
  let bytes = input instanceof ArrayBuffer ? new Uint8Array(input) : new Uint8Array(input.buffer, input.byteOffset, input.byteLength);
  if (bytes.byteOffset % 8) bytes = bytes.slice();
  const base = bytes.byteOffset, view = new DataView(bytes.buffer, base, bytes.byteLength), decoder = new TextDecoder('utf-8', {ignoreBOM: true});
  let p = 0;
  const u32 = () => { if (p + 4 > bytes.byteLength) throw new Error('The worksheet snapshot is truncated.'); const v = view.getUint32(p, true); p += 4; return v; };
  if (u32() !== MAGIC || u32() !== VERSION) throw new Error('The worksheet snapshot is not in a recognised format.');
  const sheetCount = u32(), flags = u32();
  const strings = (count) => {
    const map = new Map();
    for (let i = 0; i < count; i++) {
      const ordinal = u32(), length = u32();
      if (p + length > bytes.byteLength) throw new Error('The worksheet snapshot is truncated.');
      map.set(ordinal, decoder.decode(bytes.subarray(p, p + length))); p += length;
    }
    p = align(p, 4);
    return map;
  };
  const sheets = [];
  for (let s = 0; s < sheetCount; s++) {
    const nameLength = u32(), name = decoder.decode(bytes.subarray(p, p + nameLength)); p += nameLength; p = align(p, 4);
    const columnCount = u32(), columns = [];
    for (let c = 0; c < columnCount; c++) {
      const col = u32(), n = u32(), textCount = u32(), formulaCount = u32(), extraCount = flags & 1 ? u32() : 0;
      if (p + n * 13 > bytes.byteLength) throw new Error('The worksheet snapshot is truncated.');
      const rows = new Uint32Array(bytes.buffer, base + p, n); p += 4 * n;
      const kinds = new Uint8Array(bytes.buffer, base + p, n); p += n; p = align(p, 8);
      const nums = new Float64Array(bytes.buffer, base + p, n); p += 8 * n;
      const texts = strings(textCount), formulas = strings(formulaCount), extras = flags & 1 ? strings(extraCount) : new Map();
      columns.push({col, rows, kinds, nums, texts, formulas, extras});
    }
    sheets.push({name, columns});
  }
  return {sheets};
}

// Encodes [{name, columns: [{col, rows, kinds, nums, texts, formulas, extras}]}] (array-likes
// and Maps or [ordinal, string] arrays; `extras` optional) to a Uint8Array in the format above.
export function encodeSnapshot(sheets) {
  const encoder = new TextEncoder();
  const entries = (group) => Array.from(group ?? [], ([ordinal, text]) => [ordinal, encoder.encode(String(text))]);
  const prepared = sheets.map(sheet => ({
    name: encoder.encode(String(sheet.name ?? '')),
    columns: sheet.columns.map(c => ({...c, textEntries: entries(c.texts), formulaEntries: entries(c.formulas), extraEntries: entries(c.extras)}))
  }));
  const flags = prepared.some(s => s.columns.some(c => c.extraEntries.length)) ? 1 : 0;
  let size = 16;
  for (const sheet of prepared) {
    size = align(size + 4 + sheet.name.length, 4) + 4;
    for (const c of sheet.columns) {
      const n = c.rows.length;
      size = align(size + 16 + (flags ? 4 : 0) + 4 * n + n, 8) + 8 * n;
      for (const group of flags ? [c.textEntries, c.formulaEntries, c.extraEntries] : [c.textEntries, c.formulaEntries]) { for (const [, bytes] of group) size += 8 + bytes.length; size = align(size, 4); }
    }
  }
  const out = new Uint8Array(size), view = new DataView(out.buffer);
  let p = 0;
  const u32 = (v) => { view.setUint32(p, v, true); p += 4; };
  u32(MAGIC); u32(VERSION); u32(prepared.length); u32(flags);
  for (const sheet of prepared) {
    u32(sheet.name.length); out.set(sheet.name, p); p = align(p + sheet.name.length, 4);
    u32(sheet.columns.length);
    for (const c of sheet.columns) {
      const n = c.rows.length;
      if (c.kinds.length !== n || c.nums.length !== n) throw new Error('Snapshot column arrays differ in length.');
      u32(c.col); u32(n); u32(c.textEntries.length); u32(c.formulaEntries.length);
      if (flags) u32(c.extraEntries.length);
      for (let i = 0; i < n; i++) u32(c.rows[i]);
      for (let i = 0; i < n; i++) out[p + i] = c.kinds[i];
      p = align(p + n, 8);
      new Float64Array(out.buffer, p, n).set(c.nums); p += 8 * n;
      for (const group of flags ? [c.textEntries, c.formulaEntries, c.extraEntries] : [c.textEntries, c.formulaEntries]) {
        for (const [ordinal, bytes] of group) { u32(ordinal); u32(bytes.length); out.set(bytes, p); p += bytes.length; }
        p = align(p, 4);
      }
    }
  }
  return out;
}
