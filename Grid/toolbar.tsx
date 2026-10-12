import React, {useEffect, useRef} from 'react';
import icons from '../Content/Mac/toolbar-icons.json';
import '../Content/Mac/toolbar.js';
import '../Content/Mac/toolbar.css';
(window as any).StatsDirectToolbarIcons=icons;
export type ToolbarAction={id:string,label:string,icon:string,run:()=>void,disabled?:boolean,priority?:number,group?:boolean};
export function Toolbar({actions}:{actions:ToolbarAction[]}) {
  const host=useRef<HTMLDivElement>(null);
  useEffect(()=>{
    const el=host.current!;
    return (window as any).StatsDirectToolbar.overflow(el.querySelector('.sd-toolbar-row'),el.querySelector('[data-command=more]'),el.querySelector('.sd-toolbar-popup'),el);
  },[]);
  return <div ref={host} className="sd-toolbar" role="toolbar" aria-label="Worksheet commands">
    <div className="sd-toolbar-row">
      {actions.map(a=><button key={a.id} type="button" className="sd-icon" data-command={a.id} data-priority={a.priority??50} data-group-start={a.group?'':undefined} aria-label={a.label} title={a.label} disabled={a.disabled} onMouseDown={e=>e.preventDefault()} onClick={a.run} dangerouslySetInnerHTML={{__html:(window as any).StatsDirectToolbar.icon(a.icon)}}/>)}
      <button type="button" data-command="more"/>
    </div>
    <div id="grid-more-tools" className="sd-toolbar-popup" hidden role="group" aria-label="More worksheet commands"/>
  </div>;
}
