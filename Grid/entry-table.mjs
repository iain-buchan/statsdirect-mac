import {GridStore, MAX_ROWS, MAX_COLS, KINDS, deriveKind, scanDelimited} from './store.mjs';
import {screenInput} from './operation-data.mjs';

// Embedded analysis tables share the worksheet's typed, sparse storage. Editing one cell
// does not copy the table; column arrays are materialised only when submitting to the engine.
export class EntryTable {
  constructor(prompt, source, initial) {
    this.prompt = prompt;
    this.store = new GridStore();
    this.store.rows = prompt.rows ?? 12;
    this.store.columns = [...(initial?.columns?.map(c=>c.title) ?? prompt.labels ??
      Array.from({length: Math.max(1, prompt.minColumns ?? 1)}, (_,i)=>`Column ${i+1}`))];
    this.pending = null;
    this.error = '';
    try {
      const input = initial?.columns ? initial : screenInput(source, prompt);
      if (input?.lazy) this.pending = input;
      else if (input) this.load(input, initial ? this.store.rows : 0);
    } catch (e) { this.error = e.message; }
  }
  get maxColumns() { return Math.min(MAX_COLS, this.prompt.maxColumns ?? MAX_COLS); }
  bounds(rows, columns) {
    if (!Number.isInteger(rows) || !Number.isInteger(columns) || rows<1 || columns<1 || rows>MAX_ROWS || columns>MAX_COLS)
      throw new Error('This exceeds the Excel worksheet dimensions.');
    if (columns>this.maxColumns || this.prompt.fixedRows && rows>this.prompt.rows)
      throw new Error('The pasted table is larger than this form allows.');
  }
  dimensions(rows, columns) {
    this.bounds(rows, columns);
    const old = this.store.columns.length;
    if (columns < old) this.store.cols.length = Math.min(columns, this.store.cols.length); // Remove values without creating holes in unused storage.
    this.store.columns = Array.from({length:columns}, (_,i)=>this.store.columns[i] ?? `Column ${i+1}`);
    this.store.rows = rows;
  }
  load(input, minimumRows=0) {
    const rows = input.columns.reduce((end,c)=>Math.max(end,c.values.length), minimumRows);
    this.bounds(rows, input.columns.length);
    // Validate the dimensions before replacing anything. Preserve the form's category labels.
    const previous = this.store;
    this.store = new GridStore();
    this.store.columns = previous.columns;
    this.dimensions(rows, input.columns.length);
    this.store.setLoaded((function* () {
      for (let c=0; c<input.columns.length; c++) {
        const values=input.columns[c].values;
        for (let r=0; r<values.length; r++) {
          const text=String(values[r] ?? '');
          if (text!=='') yield {col:c, row:r, text, kind:KINDS[deriveKind(text)]};
        }
      }
    })(), false);
    this.pending = null;
    this.error = '';
  }
  paste(text, col=0, row=0) {
    if (!Number.isInteger(col) || !Number.isInteger(row) || col<0 || row<0) throw new Error('Choose a cell in the table.');
    // Validate all dimensions and quoting before changing a cell, including fixed-size forms.
    const shape=scanDelimited(String(text), '\t', (c,r)=>this.bounds(row+r+1,col+c+1));
    if (!shape.rows) return;
    const oldColumns=this.store.columns.length;
    this.store.paste(col,row,String(text));
    for (let c=oldColumns; c<this.store.columns.length; c++) this.store.columns[c]=`Column ${c+1}`;
    this.dimensions(Math.max(this.store.rows,row+shape.rows),Math.max(this.store.columns.length,col+shape.cols));
    this.error = '';
  }
  pasteValues(values, col=0, row=0) {
    if (!Number.isInteger(col) || !Number.isInteger(row) || col<0 || row<0) throw new Error('Choose a cell in the table.');
    let width=0;
    for (const line of values) width=Math.max(width,line.length);
    if (!values.length || !width) return;
    const rows=Math.max(this.store.rows,row+values.length), columns=Math.max(this.store.columns.length,col+width);
    this.bounds(rows,columns);
    const oldColumns=this.store.columns.length;
    this.store.apply((function* () {
      for (let r=0; r<values.length; r++) for (let c=0; c<values[r].length; c++) yield [col+c,row+r,values[r][c]];
    })(),rows,columns);
    for (let c=oldColumns; c<columns; c++) this.store.columns[c]=`Column ${c+1}`;
    this.error = '';
  }
  input() {
    if (this.pending) throw new Error('The selected worksheet data is still loading.');
    if (this.error) throw new Error(this.error);
    let end=this.prompt.fixedRows ? this.store.rows : 0;
    if (!this.prompt.fixedRows) this.store.forEachCell((c,r,text)=>{if(text.trim()!=='') end=Math.max(end,r+1);});
    if (!end) throw new Error('Enter data, paste a table, or choose worksheet columns.');
    return {source:'Entered data',preserveRows:true,columns:this.store.columns.map((title,c)=>({title,values:Array.from({length:end},(_,r)=>this.store.get(c,r))}))};
  }
}
