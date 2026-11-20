import {pairedStudyMethods} from './worksheet-study-design.mjs';

const roots = new Set(['Analysis', 'Data', 'Graphics']);

export function worksheetCommands(value) {
  if (!Array.isArray(value)) return [];
  return value.filter(item => item && typeof item.id === 'string' && item.id.trim() &&
    typeof item.label === 'string' && item.label.trim() && Array.isArray(item.path) &&
    item.path.every(part => typeof part === 'string' && part.trim()) && roots.has(item.path[0]))
    .map(({id, label, path, disabled, title, helpKeywords}) => ({
      id, label, path: [...path], disabled: disabled === true,
      title: typeof title === 'string' ? title : '',
      helpKeywords: Array.isArray(helpKeywords) ? helpKeywords.filter(term => typeof term === 'string' && term.trim()) : []
    }));
}

function searchText(value) {
  return value.normalize('NFD').replace(/\p{M}/gu, '').toLocaleLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, ' ').trim();
}

const pairedPhrase = /\b(?:same (?:participants|people|patients|subjects) before and after|within subjects?|matched pairs?|matched samples|dependent samples|paired)\b/;
const generalWords = new Set(['test', 'tests', 'data', 'comparison', 'comparisons', 'analysis', 'analyses',
  'measurement', 'measurements', 'sample', 'samples', 'observation', 'observations', 'outcome', 'outcomes',
  'statistical', 'statistics']);

function relatedPairedMethods(commands, phrase, exact, explicitMethod) {
  const design = phrase.match(pairedPhrase);
  if (!design || /\b(?:unpaired|independent|non paired)\b/.test(phrase)) return [];

  const qualifiers = phrase.replace(design[0], '').trim().split(/\s+/)
    .filter(word => word && !generalWords.has(word));
  if (qualifiers.length && explicitMethod) return [];

  const shown = new Set(exact.map(command => command.id));
  const related = [];
  for (const [id, method] of Object.entries(pairedStudyMethods)) {
    if (shown.has(id)) continue;
    const command = commands.find(item => item.id === id && !item.disabled);
    if (!command) continue;
    const terms = searchText([command.label, command.title, ...command.helpKeywords,
      method.outcome, method.purpose, ...(method.terms ?? [])].join(' ')).split(' ');
    if (qualifiers.every(word => terms.some(term => word.length === 1 ? word === term : term.startsWith(word)))) related.push(command);
  }
  return related;
}

function containsSearchWords(text, words) {
  return words.every(word => word === 'paired' ? /\bpaired\b/.test(text) : text.includes(word));
}

export function worksheetSearchMatches(commands, query) {
  const phrase = searchText(query), words = phrase.split(/\s+/).filter(Boolean);
  const methodName = phrase.replace(/ tests?$/, '');
  const groups = {Analysis:0, Data:1, Graphics:2};
  const matches = [];
  let explicitMethod = false;
  for (const command of commands) {
    const label = searchText(command.label), title = searchText(command.title);
    const text = searchText([...command.path, command.label, command.title, command.id].join(' '));
    const literalMatch = containsSearchWords(text, words);
    const keywords = phrase ? command.helpKeywords.map(searchText) : [];
    if (!literalMatch && !keywords.some(keyword => containsSearchWords(keyword, words))) continue;
    if (phrase && (label === methodName || title === phrase)) explicitMethod = true;

    let rank = 0;
    if (phrase && label === phrase) rank = 4;
    else if (phrase && title === phrase) rank = 3;
    else if (phrase && (label === methodName || label.startsWith(phrase) || title.startsWith(phrase) || keywords.includes(phrase))) rank = 2;
    else if (phrase && literalMatch) {
      const terms = (label + ' ' + title).split(' ');
      if (words.every(word => terms.some(term => term.startsWith(word)))) rank = 1;
    }
    matches.push({command, rank});
  }
  matches.sort((a, b) => b.rank - a.rank || groups[a.command.path[0]] - groups[b.command.path[0]]);

  const exact = [], other = [];
  for (const {command, rank} of matches) {
    (rank >= 3 ? exact : other).push(command);
  }
  const related = relatedPairedMethods(commands, phrase, exact, explicitMethod);
  if (!related.length) return {exact, related, other};

  // The design name alone can refer to a plot or a test.
  const graphics = phrase === 'paired' ? other.filter(command => command.id === 'LadderPlot' && command.path[0] === 'Graphics') : [];
  return {exact, related, other: graphics};
}

export function worksheetCommandsWithSharedLabels(commands) {
  const seen = new Map();
  const shared = new Set();
  for (const command of commands) {
    const name = searchText(command.label);
    const first = seen.get(name);
    if (first) {
      shared.add(first);
      shared.add(command);
    } else {
      seen.set(name, command);
    }
  }
  return shared;
}
