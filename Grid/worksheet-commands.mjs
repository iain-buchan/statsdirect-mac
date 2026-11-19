const roots = new Set(['Analysis', 'Data', 'Graphics']);

export function worksheetCommands(value) {
  if (!Array.isArray(value)) return [];
  return value.filter(item => item && typeof item.id === 'string' && item.id.trim() &&
    typeof item.label === 'string' && item.label.trim() && Array.isArray(item.path) &&
    item.path.every(part => typeof part === 'string' && part.trim()) && roots.has(item.path[0]))
    .map(({id, label, path, disabled, title}) => ({
      id, label, path: [...path], disabled: disabled === true,
      title: typeof title === 'string' ? title : ''
    }));
}

function searchText(value) {
  return value.normalize('NFD').replace(/\p{M}/gu, '').toLocaleLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, ' ').trim();
}

export function matchingWorksheetCommands(commands, query) {
  const phrase = searchText(query), words = phrase.split(/\s+/).filter(Boolean);
  const groups = {Analysis:0, Data:1, Graphics:2};
  function rank(command) {
    const label = searchText(command.label);
    if (!phrase) return 0;
    if (label === phrase) return 3;
    if (label.startsWith(phrase)) return 2;
    const terms = searchText(command.label + ' ' + command.title).split(' ');
    return words.every(word => terms.some(term => term.startsWith(word))) ? 1 : 0;
  }
  return commands.filter(command => {
    const text = searchText([...command.path, command.label, command.title, command.id].join(' '));
    return words.every(word => text.includes(word));
  }).sort((a,b) => groups[a.path[0]] - groups[b.path[0]] || rank(b) - rank(a));
}
