import DOMPurify from 'dompurify';
import {validateMetafile} from './metafile.mjs';
import {convertMetafileToSvg} from 'emf-converter';
import {chartFontMap,restoreChartFontFallbacks,fitChartText} from './fonts.mjs';
import {normalizeLegacyLayout} from './legacy-layout.mjs';

const properties = new Set(['font-family','font-size','font-style','font-weight','text-decoration','text-decoration-line','text-align','vertical-align','color','background-color','white-space','line-height','margin-left','margin-right','margin-top','margin-bottom','padding','padding-left','padding-right','padding-top','padding-bottom','border','border-top','border-bottom','border-left','border-right','border-collapse','border-spacing','width','height','max-width','list-style-type','fill','stroke','stroke-width','stroke-linecap','stroke-linejoin','stroke-dasharray','stroke-dashoffset','stroke-miterlimit','opacity','fill-opacity','stroke-opacity','fill-rule','clip-rule','clip-path','mask','filter','marker-start','marker-mid','marker-end','text-anchor','dominant-baseline','stop-color','stop-opacity']);
function safeStyle(style) {
  const result = document.createElement('span').style;
  for (const name of style) {
    const value = style.getPropertyValue(name);
    const check=value.replace(/url\(\s*["']?#[\w:.-]+["']?\s*\)/gi,'');
    if (properties.has(name) && !/url\s*\(|expression|javascript|@|[<>]/i.test(check)) result.setProperty(name,value);
  }
  return result.cssText;
}
const rasterURL = value => /^data:image\/(png|jpeg|gif|webp);base64,[a-z\d+/=\s]+$/i.test(value);
DOMPurify.addHook('afterSanitizeAttributes', node => {
  if (!node.attributes) return;
  for (const attr of [...node.attributes]) {
    if (/^(href|xlink:href)$/i.test(attr.name)) {
      const allowed = node.localName === 'a' ? /^(https?:|mailto:|#)/i.test(attr.value) : attr.value.startsWith('#') || rasterURL(attr.value);
      if (!allowed) node.removeAttribute(attr.name);
    }
    if (attr.name === 'src' && !rasterURL(attr.value)) node.removeAttribute(attr.name);
  }
  node.removeAttribute('srcset'); node.removeAttribute('name');
  if (node.style) { const css=safeStyle(node.style); if(css)node.setAttribute('style',css);else node.removeAttribute('style'); }
});
function purify(html) {
  return DOMPurify.sanitize(html,{WHOLE_DOCUMENT:true,FORBID_TAGS:['script','iframe','object','embed','form','input','button','textarea','select','link','base','meta','foreignObject','animate','animateMotion','animateTransform','set'],FORBID_ATTR:['contenteditable','tabindex','autofocus'],ALLOW_DATA_ATTR:false,RETURN_DOM:true});
}
export async function convert({html,pictures=[],legacy=false,tableRows=[]}) {
  if(html.length>30_000_000)throw new Error('This report is too large to open (30 MB limit).');
  // AppKit HTML also occurs in reports saved by earlier hosts, which did not
  // supply the explicit legacy flag or physical RTF row definitions.
  legacy ||= /<meta\b[^>]*\bcontent=["']Cocoa HTML Writer["'][^>]*>/i.test(html);
  const safe=purify(html), warnings=[];
  safe.querySelectorAll('.report-controls,.report-r-link,.code-actions').forEach(n=>n.remove());
  // Parse styles without fetching @imports. Apply only presentation properties in an
  // isolated, network-blocked document, then inline them so they cannot style the app.
  const styles=[];
  for(const source of safe.querySelectorAll('style')) {
    const sheet=new CSSStyleSheet();
    try {sheet.replaceSync(source.textContent);for(const rule of sheet.cssRules)if(rule.type===CSSRule.STYLE_RULE){const css=safeStyle(rule.style);if(css)styles.push(`${rule.selectorText}{${css}}`);}} catch {}
    source.remove();
  }
  const style=document.createElement('style');style.textContent=styles.join('\n');document.head.append(style);
  const container=document.createElement('div');container.append(...safe.querySelector('body').childNodes);document.body.append(container);
  const legacyRoots=legacy?[container]:[...container.querySelectorAll('.legacy-report,.report-body')].filter(el=>el.classList.contains('legacy-report')||(!el.querySelector('.legacy-report,.engine-report')&&el.querySelector('svg[aria-label^="Imported EMF"],svg[aria-label^="Imported WMF"]')));
  const normalizedRoots=new Set(legacyRoots.filter(el=>el.classList.contains('legacy-report')));
  for(const el of container.querySelectorAll('*')) {
    if(!el.closest('svg')) {
      const computed=getComputedStyle(el), inline=document.createElement('span').style;
      for(const name of properties) {
        const value=computed.getPropertyValue(name);
        if(value && !['width','height','max-width'].includes(name))inline.setProperty(name,value);
      }
      // Keep an explicitly resized picture independent of the importer's
      // temporary viewport. Other document widths still adapt to the report.
      if(el.localName==='img')for(const name of ['width','height','max-width'])if(el.style.getPropertyValue(name))inline.setProperty(name,el.style.getPropertyValue(name));
      el.setAttribute('style',safeStyle(inline));
      el.removeAttribute('id');el.removeAttribute('class');
    }
  }
  for(const root of legacyRoots) {if(normalizedRoots.has(root))root.classList.add('legacy-report');else normalizeLegacyLayout(root,legacy?tableRows:[]);}
  for(const img of container.querySelectorAll('img'))if(!img.getAttribute('src')) {
    img.replaceWith(document.createTextNode('[Image unavailable: external images are not loaded from imported reports.]'));
    warnings.push('An external or unsupported image was omitted.');
  }
  for(let i=0;i<pictures.length;i++) {
    const p=pictures[i];let image;
    try {
      if(['wmf','emf'].includes(p.format)) {
        const data=Uint8Array.from(atob(p.data),c=>c.charCodeAt(0));
        validateMetafile(data,p.format);
        const svg=await convertMetafileToSvg(data.buffer,{idPrefix:`legacy-${i}-`,fontFamilyMap:chartFontMap,maxWidth:4096,maxHeight:4096,maxCanvasDimension:4096,maxRecords:200000});
        if(!svg)throw new Error('Unrecognised metafile');
        image=purify(svg).querySelector('svg');
        if(!image || !image.querySelector('path,text,rect,circle,ellipse,line,polyline,polygon,image,use'))throw new Error('Empty chart');
        image.setAttribute('role','img');image.setAttribute('aria-label',`Imported ${p.format.toUpperCase()} chart ${i+1}`);
      } else if(['png','jpeg'].includes(p.format)) {
        image=document.createElement('img');image.src=`data:image/${p.format};base64,${p.data}`;image.alt=`Imported picture ${i+1}`;
        await image.decode();
      } else throw new Error('Unsupported picture format');
      if(p.width>0)image.setAttribute('width',String(p.width));if(p.height>0)image.setAttribute('height',String(p.height));
      image.style.maxWidth='100%';
    } catch {
      image=document.createElement('span');image.textContent=`[Picture ${i+1} could not be converted from ${p.format.toUpperCase()}. Check this chart in the original Windows report.]`;
      warnings.push(`Picture ${i+1} could not be converted.`);
    }
    const walker=document.createTreeWalker(container,NodeFilter.SHOW_TEXT);let text,found=false;
    while((text=walker.nextNode()))if(text.data.includes(p.marker)) {
      const parts=text.data.split(p.marker),fragment=document.createDocumentFragment();
      parts.forEach((part,j)=>{if(j)fragment.append(image.cloneNode(true));fragment.append(document.createTextNode(part));});text.replaceWith(fragment);found=true;break;
    }
    if(!found){container.append(image);warnings.push(`Picture ${i+1} was placed at the end because its original position could not be recovered.`);}
  }
  // Run the final markup through the same sanitizer after conversion as well.
  // Also repair previously saved HTML reports that contain bare Windows faces.
  restoreChartFontFallbacks(container);
  await document.fonts.ready;
  for(const svg of container.querySelectorAll('svg'))if(!svg.parentElement.closest('svg'))fitChartText(svg);
  let result=purify(container.innerHTML).querySelector('body').innerHTML;
  if(legacy)result=`<section class="legacy-report">${result}</section>`;
  container.remove();style.remove();
  return JSON.stringify({html:result,warnings:[...new Set(warnings)],metafiles:pictures.filter(p=>['wmf','emf'].includes(p.format)).length});
}
