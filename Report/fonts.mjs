// Metafiles name Windows fonts but normally do not embed them. Always retain the
// requested face first, then give WebKit a fallback in the same typeface family.
// In particular, Calibri is often private to Office on macOS; a bare Calibri name
// otherwise falls all the way back to the browser's default serif font.
const sans = ['Calibri','Calibri Light','Aptos','Aptos Display','Aptos Narrow','Arial','Arial Narrow','Arial Black','Helvetica','Segoe UI','Tahoma','Verdana','Trebuchet MS','Microsoft Sans Serif','MS Sans Serif'];
const serif = ['Cambria','Constantia','Times New Roman','Times','Georgia','Palatino Linotype','Book Antiqua'];
const mono = ['Consolas','Courier New','Courier','Lucida Console'];
export const chartFontMap = Object.fromEntries([
  ...sans.map(name=>[name,`${name}, ${name.startsWith('Calibri')?'Carlito, ':''}Arial, Helvetica, sans-serif`]),
  ...serif.map(name=>[name,`${name}, Times New Roman, Times, serif`]),
  ...mono.map(name=>[name,`${name}, Menlo, Courier New, monospace`]),
]);
const families = new Map(Object.entries(chartFontMap).map(([name,value])=>[name.toLowerCase(),value]));
export function chartFontFamily(value) {
  return families.get(value.trim().replace(/^(['"])(.*)\1$/,'$2').toLowerCase()) ?? value;
}

export function restoreChartFontFallbacks(root) {
  for(const svg of root.querySelectorAll('svg')) for(const el of [svg,...svg.querySelectorAll('*')]) {
    const family=el.getAttribute('font-family');
    if(family)el.setAttribute('font-family',chartFontFamily(family));
    if(el.style?.fontFamily)el.style.fontFamily=chartFontFamily(el.style.fontFamily);
  }
}

// The Windows recording's viewport may only just contain the original lettering.
// Keep every drawing coordinate intact but enlarge that viewport if a substitute
// font extends beyond it, including rotated axis labels. This also makes standalone
// SVG/PNG/Word exports complete instead of relying on CSS overflow in the viewer.
export function fitChartText(svg) {
  const view=svg.viewBox.baseVal, matrix=svg.getCTM();
  if(!view.width || !view.height || !matrix)return;
  let left=view.x,top=view.y,right=left+view.width,bottom=top+view.height;
  const inverse=matrix.inverse();
  for(const text of svg.querySelectorAll('text')) {
    const transform=text.getCTM();if(!transform)continue;
    const box=text.getBBox(),relative=inverse.multiply(transform);
    for(const [x,y] of [[box.x,box.y],[box.x+box.width,box.y],[box.x,box.y+box.height],[box.x+box.width,box.y+box.height]]) {
      const point=new DOMPoint(x,y).matrixTransform(relative);
      if(!Number.isFinite(point.x)||!Number.isFinite(point.y))continue;
      left=Math.min(left,point.x);top=Math.min(top,point.y);right=Math.max(right,point.x);bottom=Math.max(bottom,point.y);
    }
  }
  if(left<view.x-0.01||top<view.y-0.01||right>view.x+view.width+0.01||bottom>view.y+view.height+0.01)
    svg.setAttribute('viewBox',`${left-2} ${top-2} ${right-left+4} ${bottom-top+4}`);
}
