import test from 'node:test';
import assert from 'node:assert/strict';
import {numericValue,excelNumberFormat} from './clipboard.mjs';
test('Excel values preserve decimals, signs, exponents and percentages',()=>{
  for(const [input,expected] of [['12',12],['-2.5',-2.5],['−2.5',-2.5],['1.2e-7',1.2e-7],['.05',.05],['95%',.95],['0',0]])assert.equal(numericValue(input),expected,input);
});
test('Identifiers, precision beyond Excel and nonnumeric labels stay text',()=>{
  for(const input of ['0123','1234567890123456','Observation 1','1/2/2026','=1+1','<0.001','1,234','Infinity','NaN','','1e999'])assert.equal(numericValue(input),null,input);
});

test('Excel number formats retain displayed precision without coercing identifiers',()=>{
  for(const [value,format] of [['12.500','0.000'],['−2.50','0.00'],['95.00%','0.00%'],['1.20e-7','0.00E+00'],['12','General'],['0012','\\@'],['1234567890123456','\\@'],['=1+1','\\@']])assert.equal(excelNumberFormat(value),format,value);
});

test('Office table outlines follow merged outside cells and preserve stronger cell borders',async()=>{
  const {flattenOfficeTableBorders}=await import('./clipboard.mjs');
  const style=(edges={},collapse='collapse')=>({borderCollapse:collapse,assigned:{},
    getPropertyValue(name){
      const [,side,part]=name.split('-'),edge=edges[side]||['0px','none','black'];
      return part?edge[['width','style','color'].indexOf(part)]:edge.join(' ');
    },
    setProperty(name,value){this.assigned[name]=value;}
  });
  const cell=(colSpan=1,rowSpan=1,edges={})=>({colSpan,rowSpan,style:style(edges)});
  const header=cell(2),tall=cell(1,2),upper=cell(),lower=cell(1,1,{bottom:['4px','double','blue']});
  const table={style:style(Object.fromEntries(['top','right','bottom','left'].map(side=>[side,['2px','solid','green']]))),rows:[{cells:[header]},{cells:[tall,upper]},{cells:[lower]}]};
  flattenOfficeTableBorders({querySelectorAll:()=>[table]});
  assert.equal(table.style.border,'none');
  assert.deepEqual(header.style.assigned,{'border-top':'2px solid green','border-right':'2px solid green','border-left':'2px solid green'});
  assert.deepEqual(tall.style.assigned,{'border-bottom':'2px solid green','border-left':'2px solid green'});
  assert.deepEqual(upper.style.assigned,{'border-right':'2px solid green'});
  assert.deepEqual(lower.style.assigned,{'border-right':'2px solid green'});
});
