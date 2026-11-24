import React, {useEffect, useLayoutEffect, useRef, useState} from 'react';
import {WorksheetAnalysis, type WorksheetCommand} from './WorksheetAnalysis';
import {statsDirectToolbar} from './toolbar-assets';
import '../Content/Mac/toolbar.css';
export type ToolbarAction={id:string,label:string,icon:string,run?:()=>void,disabled?:boolean,priority?:number,group?:boolean,text?:string};
export function Toolbar({actions, moreActions, commands, runAnalysis, searchHelp}: {
  actions: ToolbarAction[];
  moreActions: ToolbarAction[];
  commands: WorksheetCommand[];
  runAnalysis: (id: string, fromAssistant: boolean) => void;
  searchHelp: (query: string) => void;
}) {
  const host=useRef<HTMLDivElement>(null);
  const [analysisOpen, setAnalysisOpen] = useState(false);
  const [assistantMethods, setAssistantMethods] = useState<ReadonlySet<string> | null>(null);
  const [analysisPosition, setAnalysisPosition] = useState({anchor: 35, width: 0});
  const [expandedBranches, setExpandedBranches] = useState<ReadonlySet<string>>(() => new Set());
  function showAnalysis(methods: ReadonlySet<string> | null = null) {
    const popup = host.current?.querySelector<HTMLElement>('#grid-more-tools');
    if (popup) popup.hidden = true;
    host.current?.querySelector('[data-command=more]')?.setAttribute('aria-expanded', 'false');
    setAssistantMethods(methods);
    setAnalysisOpen(true);
    host.current?.querySelector<HTMLInputElement>('#worksheet-analysis-search')?.focus();
  }
  function closeAnalysis(returnFocus = true) {
    setAnalysisOpen(false);
    setAssistantMethods(null);
    if (returnFocus) {
      const analyse = host.current?.querySelector<HTMLButtonElement>('[data-command=analyse]');
      const target = analyse?.getClientRects().length ? analyse : host.current?.querySelector<HTMLButtonElement>('[data-command=more]');
      target?.focus();
    }
  }
  function toggleAnalysis() {
    if (analysisOpen) closeAnalysis();
    else showAnalysis();
  }
  useEffect(()=>{
    const el=host.current!;
    return statsDirectToolbar.overflow(el.querySelector('.sd-toolbar-row'),el.querySelector('[data-command=more]'),el.querySelector('.sd-toolbar-popup'),el);
  },[]);
  useLayoutEffect(() => {
    const toolbar = host.current;
    if (!analysisOpen || !toolbar) return;
    const analyse = toolbar.querySelector('[data-command=analyse]');
    const more = toolbar.querySelector('[data-command=more]');
    const updateAnchor = () => {
      const button = analyse?.getClientRects().length ? analyse : more;
      const bounds = button?.getBoundingClientRect();
      const toolbarBounds = toolbar.getBoundingClientRect();
      if (bounds) setAnalysisPosition({anchor: bounds.left + bounds.width / 2 - toolbarBounds.left, width: toolbar.clientWidth});
    };
    updateAnchor();
    const resize = new ResizeObserver(updateAnchor);
    resize.observe(toolbar);
    return () => resize.disconnect();
  }, [analysisOpen]);
  useEffect(() => {
    const dismiss = (event: PointerEvent) => {
      if (!host.current?.contains(event.target as Node)) closeAnalysis(false);
    };
    const open = (event: Event) => {
      const allowed = (event as CustomEvent<string[]>).detail;
      showAnalysis(Array.isArray(allowed) ? new Set(allowed) : null);
    };
    document.addEventListener('pointerdown', dismiss);
    window.addEventListener('statsdirect-open-worksheet-commands', open);
    return () => {
      document.removeEventListener('pointerdown', dismiss);
      window.removeEventListener('statsdirect-open-worksheet-commands', open);
    };
  }, []);
  return <div ref={host} className="sd-toolbar" role="toolbar" aria-label="Worksheet commands"
    onClickCapture={event => {
      if ((event.target as Element).closest('[data-command=more]')) closeAnalysis(false);
    }}>
    <div className="sd-toolbar-row">
      {actions.map(a=>
        <button key={a.id} type="button" className={a.text ? 'sd-labelled' : 'sd-icon'} data-command={a.id}
          data-priority={a.priority??50} data-group-start={a.group?'':undefined} aria-label={a.label} title={a.label}
          aria-haspopup={a.id === 'analyse' ? 'dialog' : undefined} aria-expanded={a.id === 'analyse' ? analysisOpen : undefined}
          aria-controls={a.id === 'analyse' ? 'worksheet-analysis-chooser' : undefined} disabled={a.disabled}
          onMouseDown={e=>e.preventDefault()} onClick={() => {
            if (a.id === 'analyse') toggleAnalysis();
            else { closeAnalysis(false); a.run?.(); }
          }}>
          <span aria-hidden="true" dangerouslySetInnerHTML={{__html:statsDirectToolbar.icon(a.icon)}}/>{a.text}
        </button>)}
      <button type="button" data-command="more"/>
    </div>
    <div id="grid-more-tools" className="sd-toolbar-popup" hidden role="group" aria-label="More worksheet commands">
      <div className="sd-toolbar-permanent">
        {moreActions.map(a => <button key={a.id} type="button" data-command={a.id} disabled={a.disabled}
          aria-label={a.label} title={a.label} onMouseDown={event => event.preventDefault()} onClick={a.run}>
          <span aria-hidden="true" dangerouslySetInnerHTML={{__html:statsDirectToolbar.icon(a.icon)}}/>{a.label}
        </button>)}
      </div>
    </div>
    {analysisOpen && <WorksheetAnalysis commands={assistantMethods ? commands.filter(command => assistantMethods.has(command.id)) : commands}
      run={id => runAnalysis(id, assistantMethods !== null)} searchHelp={searchHelp} close={closeAnalysis}
      position={analysisPosition} expanded={expandedBranches} setExpanded={setExpandedBranches}/>}
  </div>;
}
