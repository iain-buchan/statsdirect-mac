import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {validateMetafile} from './metafile.mjs';
const fixture=name=>new Uint8Array(readFileSync(new URL('../Tests/Fixtures/Reports/'+name,import.meta.url)));
test('complete WMF, placeable WMF and EMF chart records are accepted',()=>{
  const wmf=fixture('chart.wmf');validateMetafile(wmf,'wmf');validateMetafile(wmf.subarray(22),'wmf');validateMetafile(fixture('chart.emf'),'emf');
});
test('truncation, malformed records and oversized record counts cannot produce partial charts',()=>{
  for(const format of ['emf','wmf']){
    const data=fixture('chart.'+format);
    for(const cut of [0,1,16,data.length-1,data.length-8])assert.throws(()=>validateMetafile(data.subarray(0,cut),format));
  }
  const emf=fixture('chart.emf');new DataView(emf.buffer).setUint32(52,200001,true);assert.throws(()=>validateMetafile(emf,'emf'));
  const wmf=fixture('chart.wmf');new DataView(wmf.buffer).setUint32(40,0,true);assert.throws(()=>validateMetafile(wmf,'wmf'));
});
