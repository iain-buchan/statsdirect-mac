// R devices reuse glyph/clip IDs and stylesheet selectors between files. Resolve
// each chart's own stylesheet in a separate tree, then retain portable inline
// drawing styles. No chart stylesheet is ever attached to the report document.
const drawingProperties = new Set(['font-family','font-size','font-style','font-weight','text-decoration','text-decoration-line','color','white-space','fill','fill-rule','stroke','stroke-width','stroke-linecap','stroke-linejoin','stroke-dasharray','stroke-dashoffset','stroke-miterlimit','opacity','fill-opacity','stroke-opacity','clip-path','clip-rule','mask','filter','marker-start','marker-mid','marker-end','text-anchor','dominant-baseline','stop-color','stop-opacity']);
const markerName=name=>'--statsdirect-svg-'+name;
const inheritance=value=>/^(inherit|unset|currentcolor)$/i.test(value.trim())?value.trim().toLowerCase():'';

export function isolateSvgStyles(root, safeStyle) {
  for (const svg of [...root.querySelectorAll('svg')].filter(s=>!s.parentElement?.closest('svg'))) {
    const sources=[...svg.querySelectorAll('style')];
    if(!sources.length)continue;
    const declarations=new Map();
    for(const source of sources) {
      const sheet=new CSSStyleSheet(),rules=[];
      try {
        sheet.replaceSync(source.textContent);
        for(const rule of sheet.cssRules)if(rule.type===CSSRule.STYLE_RULE) {
          const css=safeStyle(rule.style);if(css) {
            const style=document.createElement('span').style;style.cssText=css;
            // A parallel declaration lets the browser resolve specificity while
            // retaining inherit/currentColor for glyphs instantiated by <use>.
            for(const name of [...style])if(drawingProperties.has(name))style.setProperty(markerName(name),inheritance(style.getPropertyValue(name))?'keep-'+inheritance(style.getPropertyValue(name)):'computed');
            rules.push(`${rule.selectorText}{${style.cssText}}`);
            const matches=[...svg.querySelectorAll(rule.selectorText)];
            if(svg.matches(rule.selectorText))matches.push(svg);
            for(const node of matches) {
              if(!declarations.has(node))declarations.set(node,new Set());
              for(const name of rule.style)if(drawingProperties.has(name))declarations.get(node).add(name);
            }
          }
        }
      } catch {} // Match the importer's handling of unsupported CSS.
      source.textContent=rules.join('\n');
    }
    const marker=document.createComment('chart'),host=document.createElement('div');
    host.style.cssText='position:fixed;left:-100000px;top:0;visibility:hidden';
    svg.replaceWith(marker);
    const shadow=host.attachShadow({mode:'closed'});shadow.append(svg);document.body.append(host);
    try {
      // Snapshot all computed values before inlining any, preserving inheritance.
      const nodes=[...declarations.keys()];
      const styles=nodes.map(node=>{
        const computed=getComputedStyle(node),css=document.createElement('span').style;css.cssText=safeStyle(computed);
        // Do not freeze inherited paint on unused glyph definitions: <use>
        // supplies their fill/stroke when the referenced path is instantiated.
        return [...css].filter(name=>declarations.get(node).has(name)&&!node.style.getPropertyValue(name)).map(name=>{
          const marker=computed.getPropertyValue(markerName(name)).trim();
          return [name,marker.startsWith('keep-')?marker.slice(5):css.getPropertyValue(name)];
        });
      });
      nodes.forEach((node,index)=>styles[index].forEach(([name,value])=>node.style.setProperty(name,value)));
      sources.forEach(source=>source.remove());
    } finally {marker.replaceWith(svg);host.remove();}
  }
}

export function namespaceSvgIDs(root) {
  for(const svg of root.querySelectorAll('svg'))if(!svg.parentElement?.closest('svg')) {
    // The offline importer has an opaque origin, where randomUUID is unavailable.
    const prefix='chart-'+[...crypto.getRandomValues(new Uint32Array(4))].map(n=>n.toString(16).padStart(8,'0')).join('')+'-',ids=new Map();
    for(const el of [svg,...svg.querySelectorAll('[id]')])if(el.id){ids.set(el.id,prefix+el.id);el.id=prefix+el.id;}
    for(const el of [svg,...svg.querySelectorAll('*')])for(const attr of [...el.attributes]) {
      let value=attr.value;
      if(/^(href|xlink:href)$/.test(attr.name)&&value.startsWith('#')&&ids.has(value.slice(1)))value='#'+ids.get(value.slice(1));
      value=value.replace(/url\(\s*["']?#([^\s"'()<>]+)["']?\s*\)/gi,(all,id)=>ids.has(id)?`url(#${ids.get(id)})`:all);
      if(value!==attr.value)el.setAttributeNS(attr.namespaceURI,attr.name,value);
    }
  }
}
