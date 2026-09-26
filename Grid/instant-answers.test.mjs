import {test} from 'node:test';
import assert from 'node:assert/strict';
import {InstantAnswers} from './instant-answers.mjs';
test('recalculation uses edited values but pauses for new questions and engine validation',()=>{
 const a=new InstantAnswers();
 const p={name:'scrap',kind:'grid'},choice={name:'study_type',kind:'option'};
 a.record(p,{columns:[{values:['12','8']},{values:['3','17']}]});a.record(choice,'casecontrol');
 const previous=a.finish();
 const edited=structuredClone(previous);edited[0].value.columns[0].values[0]='13';edited[1].value='neither';
 a.restart(edited);
 assert.equal(a.next(p).value.columns[0].values[0],'13');
 assert.equal(a.next(choice).value,'neither');
 assert.deepEqual(a.next({name:'doFisher',kind:'boolean'}),{found:false});
 assert.deepEqual(a.next({...p,error:'Invalid table'}),{found:false});
 a.record({...p,error:'Invalid table'},{columns:[{values:['14','8']},{values:['3','17']}]});
 const final=a.finish();assert.equal(final.length,2);assert.equal(final[0].p.error,null);
 assert.equal(previous[0].value.columns[0].values[0],'12');
});
