import React, {useEffect, useMemo, useRef, useState} from 'react';
import {worksheetCommandsWithSharedLabels, worksheetSearchMatches} from './worksheet-commands.mjs';
import {pairedStudyMethods} from './worksheet-study-design.mjs';

export type WorksheetCommand = {
  id: string;
  label: string;
  path: string[];
  disabled?: boolean;
  title?: string;
  helpKeywords?: string[];
};

type OutlineItem = {
  key: string;
  label: string;
  parent?: OutlineItem;
  children: OutlineItem[];
  command?: WorksheetCommand;
};

function commandItem(command: WorksheetCommand, parent?: OutlineItem): OutlineItem {
  return {
    key: JSON.stringify(['command', command.path, command.id, command.label]),
    label: command.label, parent, children: [], command
  };
}

function buildOutline(commands: WorksheetCommand[]) {
  const roots: OutlineItem[] = [];
  const branches = new Map<string, OutlineItem>();
  for (const command of commands) {
    let parent: OutlineItem | undefined;
    const path: string[] = [];
    for (const label of command.path) {
      path.push(label);
      const key = JSON.stringify(['branch', ...path]);
      let branch = branches.get(key);
      if (!branch) {
        branch = {key, label, parent, children: []};
        branches.set(key, branch);
        (parent?.children ?? roots).push(branch);
      }
      parent = branch;
    }
    parent?.children.push(commandItem(command, parent));
  }
  return roots;
}

function searchOutline(exact: WorksheetCommand[], related: WorksheetCommand[], other: WorksheetCommand[]) {
  const roots = buildOutline(other);
  for (const [key, label, entries] of [
    ['related', 'Related methods', related],
    ['exact', 'Exact matches', exact]
  ] as const) {
    if (!entries.length) continue;
    const group: OutlineItem = {key, label, children: []};
    group.children = entries.map(command => commandItem(command, group));
    if (key === 'exact') roots.unshift(group);
    else roots.push(group);
  }
  return roots;
}

const itemID = (item: OutlineItem) => 'worksheet-analysis-item-' + encodeURIComponent(item.key);

export function WorksheetAnalysis({commands, run, searchHelp, close, position, expanded, setExpanded}: {
  commands: WorksheetCommand[];
  run: (id: string) => void;
  searchHelp: (query: string) => void;
  close: (returnFocus?: boolean) => void;
  position: {anchor: number; width: number};
  expanded: ReadonlySet<string>;
  setExpanded: (branches: ReadonlySet<string>) => void;
}) {
  const [query, setQuery] = useState('');
  const [closedMatches, setClosedMatches] = useState<ReadonlySet<string>>(() => new Set());
  const [matchingKey, setMatchingKey] = useState<string>();
  const [focusedKey, setFocusedKey] = useState<string>();
  const search = useRef<HTMLInputElement>(null);
  const searching = query.trim().length > 0;
  const found = useMemo(() => worksheetSearchMatches(commands, query), [commands, query]);
  const foundCount = found.exact.length + found.related.length + found.other.length;
  const designSearch = found.related.length > 0;
  const roots = useMemo(() => searchOutline(found.exact, found.related, found.other), [found]);
  const sharedLabels = useMemo(() => worksheetCommandsWithSharedLabels(commands), [commands]);
  const isExpanded = (item: OutlineItem) => searching ? !closedMatches.has(item.key) : expanded.has(item.key);
  function visibleItems(items: OutlineItem[]): OutlineItem[] {
    return items.flatMap(item => [item, ...(!item.command && isExpanded(item) ? visibleItems(item.children) : [])]);
  }
  const visible = visibleItems(roots);
  const matches = searching ? visible.filter(item => item.command && !item.command.disabled) : [];
  const match = matches.find(item => item.key === matchingKey) ?? (designSearch ? undefined : matches[0]);
  const tabStop = visible.find(item => item.key === focusedKey) ?? visible[0];

  useEffect(() => { search.current?.focus(); }, []);
  useEffect(() => {
    if (match && document.activeElement === search.current) {
      document.getElementById(itemID(match))?.firstElementChild?.scrollIntoView({block: 'nearest'});
    }
  }, [matchingKey, query, match]);

  function focusItem(item: OutlineItem | undefined) {
    if (!item) return;
    const row = document.getElementById(itemID(item));
    row?.focus({preventScroll: true});
    row?.firstElementChild?.scrollIntoView({block: 'nearest'});
  }
  function toggle(item: OutlineItem, includeDescendants = false) {
    const next = new Set(searching ? closedMatches : expanded);
    const opening = !isExpanded(item);
    function update(branch: OutlineItem) {
      if (branch.command) return;
      if (opening !== searching) next.add(branch.key);
      else next.delete(branch.key);
      if (includeDescendants) branch.children.forEach(update);
    }
    update(item);
    if (searching) setClosedMatches(next);
    else setExpanded(next);
  }
  function activate(item: OutlineItem | undefined, includeDescendants = false) {
    if (!item) return;
    if (!item.command) {
      toggle(item, includeDescendants);
    } else if (!item.command.disabled) {
      close(false);
      run(item.command.id);
    }
  }
  function searchKeyDown(event: React.KeyboardEvent<HTMLInputElement>) {
    if (event.nativeEvent.isComposing) return;
    if (event.key === 'Enter') {
      event.preventDefault();
      activate(match);
    } else if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
      event.preventDefault();
      const down = event.key === 'ArrowDown';
      if (!searching) focusItem(down ? visible[0] : visible.at(-1));
      else if (matches.length) {
        const index = match ? matches.indexOf(match) + (down ? 1 : -1) : down ? 0 : matches.length - 1;
        setMatchingKey(matches[Math.max(0, Math.min(matches.length - 1, index))]?.key);
      }
    }
  }
  function treeKeyDown(event: React.KeyboardEvent<HTMLDivElement>) {
    const index = visible.findIndex(item => itemID(item) === (event.target as HTMLElement).id);
    if (index < 0) return;
    const item = visible[index], branch = !item.command;
    switch (event.key) {
      case 'ArrowDown': focusItem(visible[index + 1]); break;
      case 'ArrowUp': focusItem(visible[index - 1]); break;
      case 'Home': focusItem(visible[0]); break;
      case 'End': focusItem(visible.at(-1)); break;
      case 'ArrowRight':
        if (branch && isExpanded(item)) focusItem(item.children[0]);
        else if (branch) toggle(item, event.altKey);
        break;
      case 'ArrowLeft':
        if (branch && isExpanded(item)) toggle(item, event.altKey);
        else focusItem(item.parent);
        break;
      case 'Enter':
      case ' ': activate(item, event.altKey); break;
      default: return;
    }
    event.preventDefault();
  }
  function renderItems(items: OutlineItem[], path: string[] = []): React.ReactNode {
    return items.map(item => {
      const itemPath = [...path, item.label];
      const method = designSearch && item.command ? pairedStudyMethods[item.command.id] : undefined;
      const menuPath = item.command && searching && (method || item.parent?.key === 'exact' || sharedLabels.has(item.command))
        ? item.command.path.join(' › ') : '';
      const purpose = method ? [method.outcome, method.purpose].join(' · ') : '';
      return <div key={item.key} id={itemID(item)} role="treeitem"
        aria-label={[item.label, menuPath, purpose].filter(Boolean).join(', ')}
        aria-expanded={item.command ? undefined : isExpanded(item)}
        aria-disabled={item.command?.disabled || undefined}
        aria-selected={item.command && searching ? match === item : undefined}
        data-worksheet-branch={item.command ? undefined : itemPath.join(' › ')}
        data-worksheet-command={item.command?.id}
        tabIndex={tabStop === item ? 0 : -1}
        onFocus={event => { if (event.target === event.currentTarget) setFocusedKey(item.key); }}
        onClick={event => {
          event.stopPropagation();
          focusItem(item);
          activate(item, event.altKey);
        }}>
        <div className="worksheet-tree-row">
          <span aria-hidden="true" className={item.command ? 'worksheet-tree-inset' : 'worksheet-tree-disclosure'}/>
          <span className="worksheet-tree-text">
            <span className="worksheet-tree-label">{item.label}</span>
            {purpose && <span className="worksheet-tree-purpose">{purpose}</span>}
            {menuPath && <span className="worksheet-tree-path">{menuPath}</span>}
          </span>
        </div>
        {!item.command && <div role="group" hidden={!isExpanded(item)}>{renderItems(item.children, itemPath)}</div>}
      </div>;
    });
  }

  return <section id="worksheet-analysis-chooser" className="worksheet-analysis-chooser" role="dialog" aria-label="Analyse worksheet"
    style={{
      '--analysis-anchor': position.anchor + 'px',
      '--analysis-toolbar-width': position.width + 'px'
    } as React.CSSProperties}
    onBlur={event => {
      if (event.relatedTarget && !event.currentTarget.contains(event.relatedTarget as Node)) close(false);
    }}
    onKeyDown={event => {
      if (event.key === 'Escape' && !event.nativeEvent.isComposing) {
        event.preventDefault(); event.stopPropagation(); close();
      }
    }}>
    <input ref={search} id="worksheet-analysis-search" type="search" placeholder="Search worksheet commands"
      aria-label="Search worksheet commands" autoComplete="off" spellCheck={false} role="combobox"
      aria-haspopup="tree" aria-autocomplete="list" aria-expanded="true" aria-controls="worksheet-analysis-results"
      aria-activedescendant={match ? itemID(match) : undefined} onKeyDown={searchKeyDown}
      value={query} onChange={event => {
        setQuery(event.target.value);
        setMatchingKey(undefined);
        setClosedMatches(new Set());
      }}/>
    <div id="worksheet-analysis-results" role="tree" aria-label="Worksheet commands" onKeyDown={treeKeyDown}>
      {renderItems(roots)}
    </div>
    {(searching || commands.length === 0) && <div className="worksheet-analysis-footer">
      <p className="worksheet-analysis-count" role="status">
        {commands.length === 0 ? 'Loading worksheet commands…' : foundCount === 0 ? 'No matching commands.' :
          designSearch && !match ? 'Choose a method for your data.' : foundCount + (foundCount === 1 ? ' command' : ' commands')}
      </p>
      {searching && <button type="button" id="worksheet-analysis-search-help" onClick={() => {
        close(false);
        searchHelp(query.trim());
      }}>Search Help</button>}
    </div>}
  </section>;
}
