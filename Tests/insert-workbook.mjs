// Exercise the exact grid planner/store/export contract consumed by native Excel saving.
import fs from 'node:fs';
import { WorkbookStore } from '../Grid/workbook.mjs';
import { planWriteBack } from '../Grid/write-back.mjs';
const book=new WorkbookStore(); book.load(JSON.parse(fs.readFileSync(0,'utf8')));
const store=book.sheets[0].store;
store.apply([[1,2,'21','number']]);
const plan=planWriteBack(store,[{columns:1,lengths:[3],cells:[{col:0,row:0,text:'out'},{col:0,row:1,text:'10'},{col:0,row:2,text:'20'},{col:0,row:3,text:'30'}]}],'FirstColumn',null,{backed:true});
store.apply(plan.edits,plan.rows,plan.cols,plan.inserts);
const exported=()=>({...book.export(),inserts:book.sheets.map(s=>({name:s.name,inserts:s.store.inserts.map(i=>({...i}))}))});
const applied=exported(); store.undo(); const undone=exported(); store.redo(); const redone=exported();
process.stdout.write(JSON.stringify({applied,undone,redone}));
