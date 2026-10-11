// The report is one editable region holding the results as blocks. Both hosts
// (the Mac shell and the Windows report window) build the region and its blocks;
// the editor finds them here. Ids are kept on the blocks so that the hosts can
// replace, extend and undo a result, and so that help and R belong to a result.
export const region=()=>document.getElementById('report-results')||document.getElementById('results');
export const emptyNotice=()=>document.getElementById('report-empty')||document.getElementById('empty');
export const entrySelector='.report-entry[data-result-id]';
export const entries=()=>{const root=region();return root?[...root.children].filter(el=>el.matches(entrySelector)):[];};
export const elementOf=node=>node?.nodeType===1?node:node?.parentElement;
export const entryOf=node=>elementOf(node)?.closest(entrySelector);
export const entryById=id=>document.getElementById('result-'+id);
export const inRegion=node=>{const root=region();return !!root&&!!node&&root.contains(node);};
// Content that is never edited as text: pictures, the inputs record, warnings.
export const protectedSelector='.report-media,.report-chart,.report-links,details,svg,img,.report-import-warning';
export const fieldSelector='input,textarea,select,[contenteditable="plaintext-only"]';
export const field=node=>!!elementOf(node)?.closest(fieldSelector);
