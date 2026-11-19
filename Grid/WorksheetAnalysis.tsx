import React, {useEffect, useRef, useState} from 'react';
import {matchingWorksheetCommands} from './worksheet-commands.mjs';

export type WorksheetCommand = {
  id: string;
  label: string;
  path: string[];
  disabled?: boolean;
  title?: string;
};

export function WorksheetAnalysis({commands, run, close}: {
  commands: WorksheetCommand[];
  run: (id: string) => void;
  close: (returnFocus?: boolean) => void;
}) {
  const [query, setQuery] = useState('');
  const [active, setActive] = useState(0);
  const search = useRef<HTMLInputElement>(null);
  const list = useRef<HTMLDivElement>(null);
  const matches: WorksheetCommand[] = matchingWorksheetCommands(commands, query);
  const enabled = matches.map((command, index) => command.disabled ? -1 : index).filter(index => index >= 0);
  const chosen = enabled.includes(active) ? active : enabled[0];
  useEffect(() => { search.current?.focus(); }, []);
  useEffect(() => {
    list.current?.querySelector<HTMLElement>('[aria-selected=true]')?.scrollIntoView({block:'nearest'});
  }, [query, chosen]);
  function launch(command: WorksheetCommand | undefined) {
    if (!command || command.disabled) return;
    close(false);
    run(command.id);
  }
  function keyDown(event: React.KeyboardEvent) {
    if (event.nativeEvent.isComposing) return;
    if (event.key === 'Escape') {
      event.preventDefault(); event.stopPropagation(); close(); return;
    }
    if (event.target !== search.current) return;
    if (event.key === 'Enter') {
      event.preventDefault(); launch(matches[chosen]); return;
    }
    if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
      event.preventDefault();
      const position = enabled.indexOf(chosen);
      setActive(enabled[Math.max(0, Math.min(enabled.length - 1, position + (event.key === 'ArrowDown' ? 1 : -1)))] ?? 0);
    }
  }
  return <section id="worksheet-analysis-chooser" className="worksheet-analysis-chooser" role="dialog"
    aria-labelledby="worksheet-analysis-heading" onKeyDown={keyDown}>
    <div className="worksheet-analysis-heading">
      <label id="worksheet-analysis-heading" htmlFor="worksheet-analysis-search">Analyse worksheet</label>
      <button type="button" aria-label="Close analysis chooser" onClick={() => close()}>×</button>
    </div>
    <input ref={search} id="worksheet-analysis-search" type="search" placeholder="Find an analysis or data command"
      autoComplete="off" spellCheck={false} role="combobox" aria-autocomplete="list" aria-expanded="true"
      aria-controls="worksheet-analysis-results" aria-activedescendant={chosen === undefined ? undefined : 'worksheet-analysis-option-' + chosen}
      value={query} onChange={event => { setQuery(event.target.value); setActive(0); }}/>
    <div ref={list} id="worksheet-analysis-results" role="listbox" aria-label="Worksheet analyses and commands">
      {matches.map((command, index) => <React.Fragment key={JSON.stringify([command.id, command.path, command.label])}>
        {(index === 0 || matches[index - 1].path.join('\n') !== command.path.join('\n')) &&
          <div className="worksheet-analysis-path" role="presentation">{command.path.join(' › ')}</div>}
        <button type="button" role="option" id={'worksheet-analysis-option-' + index}
          data-worksheet-command={command.id} aria-selected={chosen === index} disabled={command.disabled}
          aria-label={command.label + ', ' + command.path.join(', ')}
          tabIndex={-1} onMouseDown={event => event.preventDefault()} onClick={() => launch(command)}>
          {command.label}
        </button>
      </React.Fragment>)}
    </div>
    <p className="worksheet-analysis-count" role="status">{commands.length === 0 ? 'The worksheet commands are loading.' :
      matches.length === 0 ? 'No matching commands.' : matches.length + (matches.length === 1 ? ' command' : ' commands')}</p>
  </section>;
}
