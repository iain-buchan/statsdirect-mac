import createDOMPurify from 'dompurify';

const purifier=createDOMPurify(window);
export const presentation=['font-family','font-size','font-style','font-weight','text-decoration','text-decoration-line','text-align','vertical-align','color','background-color','white-space','line-height','margin-left','margin-right','margin-top','margin-bottom','padding','padding-left','padding-right','padding-top','padding-bottom','border','border-top','border-bottom','border-left','border-right','border-collapse','border-spacing','list-style-type'];
const properties=new Set([...presentation,'width','height','max-width','fill','fill-rule','stroke','stroke-width','stroke-linecap','stroke-linejoin','stroke-dasharray','stroke-dashoffset','stroke-miterlimit','opacity','fill-opacity','stroke-opacity','clip-path','clip-rule','mask','filter','marker-start','marker-mid','marker-end','text-anchor','dominant-baseline','stop-color','stop-opacity']);
const rasterURL=value=>/^data:image\/(png|jpeg|gif|webp);base64,[a-z\d+/=\s]+$/i.test(value);
function safeStyle(style) {
  const clean=document.createElement('span').style;
  for(const name of style) {
    const value=style.getPropertyValue(name);
    // Internal SVG paint/clip references are local, never network requests.
    const check=value.replace(/url\(\s*["']?#[\w:.-]+["']?\s*\)/gi,'');
    if(properties.has(name)&&!/(?:url\s*\(|expression|javascript|@|[<>])/i.test(check))clean.setProperty(name,value);
  }
  return clean.cssText;
}
purifier.addHook('afterSanitizeAttributes',node=>{
  if(!node.attributes)return;
  for(const attr of [...node.attributes]) {
    if(/^(href|xlink:href)$/i.test(attr.name)) {
      const allowed=node.localName==='a'?/^(https?:|mailto:|#)/i.test(attr.value):attr.value.startsWith('#')||rasterURL(attr.value);
      if(!allowed)node.removeAttribute(attr.name);
    }
    if(attr.name==='src'&&!rasterURL(attr.value))node.removeAttribute(attr.name);
    if(attr.name!=='style'&&/url\s*\(/i.test(attr.value.replace(/url\(\s*["']?#[\w:.-]+["']?\s*\)/gi,'')))node.removeAttribute(attr.name);
  }
  node.removeAttribute('srcset');node.removeAttribute('name');
  if(node.style){const css=safeStyle(node.style);if(css)node.setAttribute('style',css);else node.removeAttribute('style');}
});

// Clipboard HTML is untrusted even when it carries our private pasteboard type.
// Styles are scoped and inlined in a detached fragment; no stylesheet or active
// content is ever attached to the privileged report document.
export function cleanFragment(html,{freshIDs=true}={}) {
  if(new TextEncoder().encode(html).length>30_000_000)throw new Error('The selected content is too large to paste. Select a smaller part of the report.');
  const root=purifier.sanitize(html,{RETURN_DOM_FRAGMENT:true,FORCE_BODY:true,ALLOW_DATA_ATTR:false,
    FORBID_TAGS:['script','iframe','object','embed','form','input','button','textarea','select','link','base','meta','foreignObject','animate','animateMotion','animateTransform','set'],
    FORBID_ATTR:['contenteditable','tabindex','autofocus','draggable']});
  root.querySelectorAll('.report-controls,.report-r-link,.code-actions,.report-chart[hidden]').forEach(el=>el.remove());
  for(const source of root.querySelectorAll('style')) {
    const sheet=new CSSStyleSheet();
    try {
      sheet.replaceSync(source.textContent);
      for(const rule of sheet.cssRules)if(rule.type===CSSRule.STYLE_RULE) {
        const style=document.createElement('span').style;style.cssText=safeStyle(rule.style);
        for(const el of root.querySelectorAll(rule.selectorText))for(const property of style)if(!el.style.getPropertyValue(property))el.style.setProperty(property,style.getPropertyValue(property));
      }
    } catch {} // Ignore unsupported selectors; preserve valid inline formatting.
    source.remove();
  }
  root.querySelectorAll('.report-media,.report-chart').forEach(el=>el.replaceWith(...el.childNodes));
  for(const el of root.querySelectorAll('*')) {
    el.removeAttribute('class');
    if(!el.closest('svg'))el.removeAttribute('id');
    if(el.getAttribute('role')==='textbox')el.removeAttribute('role');
  }
  for(const image of root.querySelectorAll('img'))if(!image.getAttribute('src'))image.replaceWith(document.createTextNode('[External image omitted]'));
  // Copied charts may reuse gradient, clip-path and glyph identifiers. Give
  // every pasted SVG its own namespace, preserving all internal references.
  if(freshIDs)for(const svg of root.querySelectorAll('svg'))if(!svg.parentElement?.closest('svg')) {
    const prefix='pasted-'+crypto.randomUUID()+'-',ids=new Map();
    for(const el of [svg,...svg.querySelectorAll('[id]')])if(el.id){ids.set(el.id,prefix+el.id);el.id=prefix+el.id;}
    for(const el of [svg,...svg.querySelectorAll('*')])for(const attr of [...el.attributes]) {
      let value=attr.value;
      if(/^(href|xlink:href)$/.test(attr.name)&&value.startsWith('#')&&ids.has(value.slice(1)))value='#'+ids.get(value.slice(1));
      value=value.replace(/url\(\s*["']?#([\w:.-]+)["']?\s*\)/g,(all,id)=>ids.has(id)?`url(#${ids.get(id)})`:all);
      if(value!==attr.value)el.setAttribute(attr.name,value);
    }
  }
  const holder=document.createElement('div');holder.append(root);return holder.innerHTML;
}

export function inlinePresentation(original,copy) {
  if(original.localName==='svg'&&!original.parentElement?.closest('svg')) {
    copy.style.width=original.style.width||`${original.getBoundingClientRect().width}px`;copy.style.height='auto';copy.style.maxWidth='100%';return;
  }
  if(original.closest('svg'))return;
  const computed=getComputedStyle(original);
  for(const name of presentation)copy.style.setProperty(name,computed.getPropertyValue(name));
}
