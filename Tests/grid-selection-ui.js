// Run in actual WKWebView against the bundled grid; exercise real mouse handlers,
// then inspect the selections passed to analyses and copied to the clipboard.
const passed=[];
const check=(ok,label)=>{if(!ok)throw Error(label+'; selection='+JSON.stringify(statsDirectGrid.analysisSource().selection));passed.push('PASS: '+label);};
const settle=()=>new Promise(resolve=>setTimeout(resolve,65));
const fixture=(columns=8)=>({name:'Column drag fixture',sheets:[{name:'Data',rows:100,columns,headerRow:false,cells:Array.from({length:8},(_,col)=>({col,row:0,text:String(col+1),kind:'number'}))}]});
const bounds=()=>document.querySelector('canvas').getBoundingClientRect();
const scroller=()=>document.querySelector('.dvn-scroller');
const point=(col,row=-1)=>{const b=bounds();return [b.left+48+col*178+89-scroller().scrollLeft,b.top+(row<0?18:36+row*29+14)];};
function mouse(type,p,buttons=0,mods={}){
 const target=document.elementFromPoint(...p)??window;
 target.dispatchEvent(new MouseEvent(type,{bubbles:true,cancelable:true,clientX:p[0],clientY:p[1],button:0,buttons,...mods}));
}
const selected=()=>statsDirectGrid.analysisSource().selection;
const exact=(values,label)=>check(JSON.stringify(selected())===JSON.stringify(values),label);
async function click(col,mods={}){const p=point(col);mouse('mousemove',p);mouse('mousedown',p,1,mods);await settle();mouse('mouseup',p,0,mods);await settle();}
async function drag(from,to,row=-1){const a=point(from,row),b=point(to,row);mouse('mousemove',a);mouse('mousedown',a,1);await settle();for(let i=1;i<=8;i++){mouse('mousemove',[a[0]+(b[0]-a[0])*i/8,a[1]],1);await settle();}mouse('mouseup',b);await settle();}
statsDirectGrid.applyWorkbook(fixture());await settle();
await drag(0,3);exact([0,1,2,3],'drag right selects adjacent whole columns');
check(statsDirectGrid.analysisSource().range===undefined,'header dragging is a whole-column selection, not a rectangle');
check(statsDirectGrid.copyText()==='1\t2\t3\t4','Copy uses every selected column in worksheet order');
await drag(3,1);exact([1,2,3],'drag left selects the same inclusive span');
await click(1);await drag(1,2);exact([1,2],'dragging starts on an already-selected heading');
await click(0);await click(3,{shiftKey:true});exact([0,1,2,3],'Shift-click still extends the heading selection');
await click(0);await click(2,{metaKey:true});exact([0,2],'Command-click still selects separate columns');
await click(2,{metaKey:true});exact([0],'Command-click still removes an individual column');
await drag(0,2,1);
check(statsDirectGrid.analysisSource().range?.first===2 && statsDirectGrid.analysisSource().range?.last===2,'dragging cells still selects a cell rectangle');
// Release outside the grid, then hover without a button: never leave selection stuck.
const a=point(0),b=point(2);mouse('mousedown',a,1);await settle();mouse('mousemove',b,1);await settle();
window.dispatchEvent(new MouseEvent('mouseup',{bubbles:true,buttons:0,clientX:-10,clientY:-10}));
mouse('mousemove',point(3));await settle();exact([0,1,2],'releasing outside the grid ends the drag');
mouse('mousedown',point(0),1);await settle();mouse('mousemove',point(1),1);await settle();window.dispatchEvent(new Event('blur'));
mouse('mousemove',point(3),1);await settle();exact([0,1],'losing window focus ends the drag');mouse('mouseup',point(3));
// Glide owns the edge hit area and cancels whole-column dragging when resizing.
await click(0);
// Separate the resize gesture from the previous click: Glide treats a second
// header mouse-up within 500 ms as a double-click that auto-fits the column.
await new Promise(resolve=>setTimeout(resolve,550));
const edge=[bounds().left+48+178-2,bounds().top+18];
mouse('mousemove',edge);mouse('mousedown',edge,1);await settle();mouse('mousemove',[edge[0]+100,edge[1]],1);await settle();mouse('mouseup',[edge[0]+100,edge[1]]);await settle();
exact([0],'resizing a column does not extend the selection');
// The widened A header now contains the point that previously hit B.
await click(1);exact([0],'dragging the header edge really resizes the column');
// Reload restores widths; use a wide sheet to exercise native edge autoscrolling.
statsDirectGrid.applyWorkbook(fixture(40));await settle();scroller().scrollLeft=0;await settle();
mouse('mousemove',point(1));mouse('mousedown',point(1),1);await settle();
const right=[bounds().right+8,bounds().top+18];mouse('mousemove',right,1);
await new Promise(resolve=>setTimeout(resolve,700));mouse('mouseup',right);await settle();
check(scroller().scrollLeft>0 && selected()[0]===1 && selected().at(-1)>4,'dragging past the right edge scrolls and extends the selection');
// Hit testing must account for a sheet already scrolled horizontally.
scroller().scrollLeft=10*178;await settle();await drag(10,12);exact([10,11,12],'header drag uses actual column indexes after horizontal scrolling');
// Reload/switch worksheets must cancel an in-progress drag.
mouse('mousedown',point(10),1);await settle();statsDirectGrid.applyWorkbook(fixture());await settle();
scroller().scrollLeft=0;await settle();mouse('mousemove',point(3),1);await settle();
check((selected()??[]).length===0,'loading another worksheet cancels an old drag');mouse('mouseup',point(3));
// Excel-sized sparse sheets use compact column selections, never whole-row cell lists.
statsDirectGrid.applyWorkbook({...fixture(16384),sheets:[{...fixture(16384).sheets[0],rows:1048576}]});await settle();
scroller().scrollLeft=0;await settle();await drag(0,2);exact([0,1,2],'whole-column drag works at Excel row and column limits');
check(statsDirectGrid.copyText()==='1\t2\t3','whole-column Copy reads used rows only on an Excel-sized sheet');
return passed.join('\n');
